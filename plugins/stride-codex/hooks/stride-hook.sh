#!/usr/bin/env bash
#
# stride-hook.sh — Codex CLI hook surface for Stride (W2141)
#
# Records `.stride/.loop-state.json` after a successful Stride completion and
# clears it on any claim. That file is the evidence the Stop-hook gate (W2142)
# reads; THE HOOK writes it, never the agent, because an agent-written marker
# is exactly as skippable as the instruction it replaces.
#
# Three properties a later reader must not undo:
#
#   1. This script writes NOTHING to stdout, ever. Codex parses a hook's stdout
#      as a control document, so a stray line here could be read as a decision.
#      Every diagnostic goes to stderr and the script always exits 0.
#
#   2. It never reads `.stride/.last-api-response.json`. See
#      own_call_response_payload below — that file is the documented hazard
#      this port was built to avoid, and it is LIVE here because the Codex
#      skills already tee into it.
#
#   3. It executes NO `.stride.md` section. Codex's agent still runs those
#      manually per AGENTS.md / README.md, and those instructions remain
#      correct. This script is a recorder, not an executor.
#
# DELIBERATELY OMITTED from the canonical port, so a later parity audit reads
# these as decisions rather than gaps:
#   - `.stride.md` section execution (`run_stride_section`) — see 3 above.
#   - The env cache (`.stride-env-cache`) and `apply_env_lines`.
#   - Per-file diff capture and `self_heal_changed_files_upload`.
#   - `after_goal` routing and `export_after_goal_env`.
#   - The sub-skill activation gate (Codex has no equivalent tool event).
#   - The `pre` phase / `after_doing` blocking path.
#   - The Tier-2 canonical-snapshot recovery branch, and any RESPONSE_FILE
#     constant — deliberate, and the point of this file. See below.
#   - The `.ps1` twin. Windows records no loop state until it ships.
#
# Exit codes: always 0. This is a gate input, not a correctness dependency.

set -uo pipefail

PHASE="${1:-}"

# NOTE: unlike the Gemini port, there is deliberately NO `.stride.md` existence
# gate here. That port exits early when the file is absent because its hook's
# only job is executing sections. This hook's only job is the loop-state
# record, which must be written whether or not the project defines any hook
# sections at all.

[ -n "$PHASE" ] || exit 0

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

# jq is required for every path below: the payload discriminator needs real
# JSON types, and a pure-bash fallback cannot tell the boolean `true` from the
# string "true" — the exact confusion loop_state_payload_ok exists to prevent.
# Absent jq we record nothing, which is the safe direction.
command -v jq > /dev/null 2>&1 || exit 0

# --- Where the record lives ----------------------------------------------
# Codex sets neither CODEX_PROJECT_DIR nor CLAUDE_PROJECT_DIR of its own
# accord, but it DOES put the workspace root on the event as `.cwd`, so that
# is the middle fallback rather than dropping straight to ".". Reading it from
# the host's own event document is not the same as widening a path from an API
# response body — the security rule that forbids the latter is about values
# the Stride server controls, and `.cwd` is supplied by Codex itself.
PROJECT_DIR="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-}}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
fi
[ -n "$PROJECT_DIR" ] || PROJECT_DIR="."

# The loop-state record. Path is identical across every port — Claude Code
# (W2123), Gemini (W2144), Copilot (W2147) and this one must interoperate on
# one path, because a checkout may be driven by more than one of them.
LOOP_STATE_FILE="$PROJECT_DIR/.stride/.loop-state.json"

# --- Read the shell command off this call's input ------------------------
# Candidates are ENUMERATED, never a recursive `..` scan. A wildcard scan
# would sweep the Bearer token out of `.tool_input.command` into whatever
# else it matched. Codex's `shell` tool takes argv-style arguments, so the
# array form is tried alongside the string form.
COMMAND=$(printf '%s' "$INPUT" | jq -r '
  ( .tool_input.command // empty | if type == "array" then join(" ") else . end )
  // ( .tool_input.cmd // empty | if type == "array" then join(" ") else . end )
  // ( .command // empty | if type == "array" then join(" ") else . end )
  // ( .arguments.command // empty | if type == "array" then join(" ") else . end )
  // ( .input.command // empty | if type == "array" then join(" ") else . end )
  // ""
' 2>/dev/null || echo "")

[ -n "$COMMAND" ] || exit 0

# --- Routing --------------------------------------------------------------
# Only the two events this task owns are routed. Note the Codex-specific
# wrinkle: its /complete curl is piped through `| tee .stride/.last-api-
# response.json` (README.md). `tee` passes stdout through unchanged, so both
# the routing match and the payload read below are unaffected — but that
# pipeline is precisely why the cache hazard is live in this port.
HOOK_NAME=""

case "$PHASE" in
  post)
    case "$COMMAND" in
      */api/tasks/claim*)
        HOOK_NAME="before_doing"
        ;;
      */api/tasks/*/mark_reviewed*)
        # Matched and then deliberately left unrouted, so a reader does not
        # think it falls through to the /complete arm below. after_review is
        # out of W2141's scope.
        HOOK_NAME=""
        ;;
      */api/tasks/*/complete*)
        HOOK_NAME="before_review"
        ;;
    esac
    ;;
esac

[ -n "$HOOK_NAME" ] || exit 0

# --- Claim: clear the record ----------------------------------------------
if [ "$HOOK_NAME" = "before_doing" ]; then
  # The clear is UNCONDITIONAL — it runs on a failed claim, an empty-queue
  # claim and an unparsable claim body alike. The most common failed claim is
  # against an empty Ready queue, which is how essentially every session ends;
  # a record preserved there is byte-identical to one left by an agent that
  # completed and never claimed again, yet a gate must refuse in the second
  # case and must not in the first, and none of the four keys can tell them
  # apart. An over-eager clear costs only a missed gate, and missed is the
  # safe side.
  #
  # Best-effort but NOT silent: a stale loop state is the one direction this
  # design calls dangerous, so a failure to clear is announced.
  #
  # The one thing the clear will NOT do is reach through a symlinked .stride
  # directory, for the same reason the writer refuses one: that resolves to a
  # directory this hook never created. Refusing leaves a stale record, which is
  # the dangerous direction — so it is announced loudly rather than passed over.
  if [ -L "$PROJECT_DIR/.stride" ]; then
    printf 'stride-hook: .stride is a symlink; not clearing, so a stale completion record may remain\n' >&2
  elif [ -e "$LOOP_STATE_FILE" ] || [ -L "$LOOP_STATE_FILE" ]; then
    rm -f "$LOOP_STATE_FILE" 2>/dev/null || true
    if [ -e "$LOOP_STATE_FILE" ] || [ -L "$LOOP_STATE_FILE" ]; then
      printf 'stride-hook: could not clear the loop state at %s; a stale completion record remains\n' \
        "$LOOP_STATE_FILE" >&2
    fi
  fi
  exit 0
fi

# --- Response payload for THIS call ---------------------------------------
# Named `own_call_response_payload`, not `extract_response_payload`, and the
# name is load-bearing. The Claude Code original lost a review round because a
# plausibly-named helper turned out to be canonical-file-first.
#
# This function reads ONLY from $INPUT. It performs ZERO file reads, and in
# particular it must never read:
#
#     $PROJECT_DIR/.stride/.last-api-response.json
#
# That file survives ACROSS calls. On a completion whose response was
# truncated — or which 422'd — a cache-backed read resolves the PREVIOUS
# claim's payload, which carries both `.data.identifier` and
# `.data.needs_review` at the right types, and so records a completion that
# never happened. The hazard is not hypothetical in this port: the Codex
# skills tee every /complete response into exactly that path.
#
# There is deliberately no Tier-2 fallback. A harness-truncated success simply
# records nothing, which is the safe direction.
own_call_response_payload() {
  local _hook_input="${1:-}" _response _payload

  [ -n "$_hook_input" ] || return 0

  _response=$(printf '%s' "$_hook_input" | jq -r '
    .tool_response // .tool_output // .output // .result.stdout // ""
  ' 2>/dev/null || echo "")
  [ -n "$_response" ] || return 0

  if printf '%s' "$_response" | jq -e 'type == "object" and has("stdout")' > /dev/null 2>&1; then
    _payload=$(printf '%s' "$_response" | jq -r '.stdout // ""' 2>/dev/null)
  else
    _payload="$_response"
  fi

  printf '%s' "$_payload"
}

# --- Loop-state helpers ----------------------------------------------------
# Structurally keep response bodies and task free text out of the file: every
# string that reaches it must first match a conservative charset. A value that
# fails this is refused rather than sanitised — the file records two
# identifiers, and anything not identifier-shaped does not belong in it.
#
# IMPORTANT, so a later maintainer does not lean on this for the wrong thing:
# this is a SHAPE filter, not a credential filter. A Stride bearer token of the
# form `stride_dev_<hex>` is entirely inside this character class and under the
# length cap, so it would pass unchanged if it ever reached here. What actually
# keeps the token out is upstream — the token lives only in
# `.tool_input.command`, and the two recorded strings are read through single
# enumerated key paths that cannot resolve to it. If those reads are ever
# widened (a `..` scan, a wildcard, an extra fallback key), add an explicit
# credential-shape refusal; do NOT assume this gate is a backstop for secrets.
# What it does exclude is prose and structured bodies, which carry spaces,
# quotes, braces and newlines.
loop_state_safe() {
  [ -n "${1:-}" ] || return 1
  [ "${#1}" -le 64 ] || return 1
  # The character set is ENUMERATED, never written as A-Z / a-z ranges. A glob
  # bracket RANGE is collation-ordered rather than codepoint-ordered on bash
  # < 5.0 (macOS ships 3.2) under a UTF-8 locale, so `A-Z` there also swallows
  # accented Latin letters. An explicit enumeration has no collation order to
  # depend on, so every port and locale agrees on every input.
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-]*) return 1 ;;
  esac
  return 0
}

# A payload describes a SUCCESSFUL completion only when it carries the two
# fields the state file is built from, AT THE RIGHT JSON TYPES. Every
# non-success body the API emits (validation errors, 404s, 422s) lacks `.data`
# entirely, so this is the discriminator — a 422 body lands on stdout exactly
# like a success and would otherwise be indistinguishable from one.
#
# `type ==` is load-bearing, not decoration: `jq -r` prints the STRING "true"
# and the BOOLEAN true identically, so a body carrying `"needs_review":"true"`
# would survive a later text comparison.
loop_state_payload_ok() {
  printf '%s' "${1:-}" | jq -e '
    try (
      (.data.identifier | type == "string" and length > 0)
      and (.data.needs_review | type == "boolean")
    ) catch false
  ' > /dev/null 2>&1
}

# Atomic and never fatal: the temp file is created in the DESTINATION
# directory so the rename is same-fs, a failure at any point leaves no temp
# behind, and the function still returns 0.
write_loop_state() {
  local _json="$1" _tmp
  # Refuse a SYMLINKED .stride directory. `mkdir -p` succeeds silently when the
  # path already exists as a symlink to a directory, after which the temp is
  # staged — and renamed — inside the link target rather than the directory
  # this hook meant to write. The blast radius is small (one file, fixed name,
  # no secret in it), but a hook that runs against arbitrary user checkouts
  # should not follow a link it did not create.
  if [ -L "$PROJECT_DIR/.stride" ]; then
    printf 'stride-hook: .stride is a symlink; not recording\n' >&2
    return 0
  fi
  # `mv` into a DIRECTORY succeeds by relocating the temp inside it, so the
  # failure branch below would never run: the record would land where no
  # reader looks and the temp would survive indefinitely. Refuse any
  # destination that exists and is not a regular file — and refuse a SYMLINK
  # explicitly, because -f FOLLOWS the link, so a symlinked record would
  # otherwise pass this gate and be replaced through the link.
  if [ -L "$LOOP_STATE_FILE" ]; then
    printf 'stride-hook: loop-state path is a symlink; not recording\n' >&2
    return 0
  fi
  if [ -e "$LOOP_STATE_FILE" ] && [ ! -f "$LOOP_STATE_FILE" ]; then
    printf 'stride-hook: loop-state path is not a regular file; not recording\n' >&2
    return 0
  fi
  mkdir -p "$PROJECT_DIR/.stride" 2>/dev/null || {
    printf 'stride-hook: could not create .stride/ for the loop state; continuing\n' >&2
    return 0
  }
  _tmp=$(mktemp "$PROJECT_DIR/.stride/loop-state.XXXXXX" 2>/dev/null) || {
    printf 'stride-hook: could not stage the loop state; continuing\n' >&2
    return 0
  }
  if printf '%s\n' "$_json" > "$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$LOOP_STATE_FILE" 2>/dev/null || {
      printf 'stride-hook: could not move the loop state into place; continuing\n' >&2
      rm -f "$_tmp" 2>/dev/null
    }
  else
    printf 'stride-hook: could not write the loop state; continuing\n' >&2
    rm -f "$_tmp" 2>/dev/null
  fi
  return 0
}

# Self-gates on before_review — the routing above maps post + /complete to it.
record_loop_state_for_completion() {
  local _payload _ident _needs _sid _json

  [ "${HOOK_NAME:-}" = "before_review" ] || return 0

  _payload=$(own_call_response_payload "$INPUT")

  if ! loop_state_payload_ok "$_payload"; then
    # A 422 legitimately records nothing, and announcing every failed
    # completion would be noise. An UNPARSABLE body is the different case: the
    # completion may well have succeeded server-side and the evidence is
    # simply lost, which is indistinguishable from "nothing to record" unless
    # said. `jq empty`, not `jq -e .`: -e sets its exit status from the VALUE,
    # so a body of `false` or `null` — both well-formed — would be announced
    # as unparsable, and an ABSENT body would exit 4 on no input. `empty`
    # fails only on a genuine parse error, and the -n guard keeps "no body at
    # all" out of a channel that claims a body failed to parse.
    if [ -n "$_payload" ] && ! printf '%s' "$_payload" | jq empty > /dev/null 2>&1; then
      printf 'stride-hook: completion response was unparsable; no loop state recorded\n' >&2
    fi
    return 0
  fi

  _ident=$(printf '%s' "$_payload" | jq -r '.data.identifier' 2>/dev/null || echo "")
  _needs=$(printf '%s' "$_payload" | jq -r '.data.needs_review' 2>/dev/null || echo "")
  loop_state_safe "$_ident" || return 0
  case "$_needs" in true|false) ;; *) return 0 ;; esac

  # The session id is the only field OF THE RECORD read out of $INPUT, and the
  # read is a single named key. $INPUT also carries the Bearer token, inside
  # `.tool_input.command` — never widen this into a search, a `..` scan, or a
  # fallback that could resolve to the command. Codex may supply no session id
  # at all, as Copilot does not, so "unknown" is an ordinary outcome and no
  # consumer may depend on this field.
  _sid=$(printf '%s' "$INPUT" | jq -r '.session_id // .sessionId // .session.id // empty' 2>/dev/null || echo "")
  [ -n "$_sid" ] || _sid="${CODEX_SESSION_ID:-}"
  [ -n "$_sid" ] || _sid="${CLAUDE_SESSION_ID:-}"
  loop_state_safe "$_sid" || _sid="unknown"

  # --argjson (never --arg) for needs_review: it is already proven to be
  # exactly `true` or `false` above, and --arg would stringify it — precisely
  # the cross-port type divergence this record exists to avoid.
  _json=$(jq -nc \
    --arg ident "$_ident" \
    --argjson needs "$_needs" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$_sid" \
    '{identifier: $ident, needs_review: $needs, completed_at: $ts, session_id: $sid}' \
    2>/dev/null) || return 0
  [ -n "$_json" ] || return 0

  write_loop_state "$_json"
  return 0
}

record_loop_state_for_completion || true

exit 0
