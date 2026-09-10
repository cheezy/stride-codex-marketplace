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
#   1. The `post` phase writes NOTHING to stdout, ever, and always exits 0.
#      Codex parses a hook's stdout as a control document, so a stray line
#      from the recorder could be read as a decision. Every diagnostic goes to
#      stderr.
#
#      This is PHASE-SCOPED as of W2181, and the scoping is the whole point.
#      The `pre` phase exists precisely to put a control document on stdout —
#      that is the only way a hook refuses a tool call — and it exits 2. Read
#      property 1 as "the recorder never speaks"; it was never a claim that
#      this file may not carry a refuser. The two phases share a process and
#      nothing else: `pre` returns before any recorder state is touched, and
#      `post` never reaches the guard.
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
#   - The `after_doing` blocking path. The `pre` phase LEFT this list in
#     W2181: it now carries the stdout-preservation guard. What stays omitted
#     is running a `.stride.md` section from it — `pre` refuses or permits and
#     does nothing else.
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

# W2181. The claim pointer the Stop gate's held-claim condition reads: which
# task this session claimed and has not completed. Written by the claim arm,
# cleared by that same arm on every claim and by a RECORDED completion. This
# port has no `.stride-env-cache` (see the omitted list above), so this is its
# own source for that question rather than a ported one.
CLAIM_STATE_FILE="$PROJECT_DIR/.stride/.claim-state.json"

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

# =========================================================================
# The `pre` phase — the stdout-preservation guard (W2181)
# =========================================================================
#
# WHY THIS PORT NEEDS IT, in this port's own terms. The recorder below reads
# a completion's response body off the Bash tool's STDOUT, on the PostToolUse
# event. Nothing else in this port ever sees that body. So a command that
# takes the response off stdout — into a file, into a transformer — leaves the
# recorder with nothing to read: `.stride/.loop-state.json` is never written,
# and the Stop gate that reads it then permits an early stop with the task
# still sitting in Doing. No error is raised anywhere along that path, which
# is what makes it worth a hook: the failure is SILENT, and the operator's
# first sign of it is work that quietly never left the board.
#
# The refusal is therefore not a policy preference about shell style. It is
# the only point in this port where that silence can be turned into a message.
#
# SCOPE — read this before widening the prefilter. The guard fires ONLY on the
# three endpoints the recorder actually routes: /api/tasks/claim, .../complete
# and .../mark_reviewed. It deliberately does NOT fire on every /api/tasks/
# call, because this port's own documented agent shell hides stdout on two
# other endpoints on purpose — the changed_files upload and the after_goal
# status probe (see skills/stride-completing-tasks/SKILL.md). Those responses
# feed no recorder here, so hiding them costs nothing, and refusing them would
# be a false positive against instructions this repository itself ships. In
# the Claude Code original those calls are made by the hook rather than by the
# agent, so its PreToolUse never sees them and the question never arises. This
# is the one place where behaviour parity required a DIFFERENT scope, not the
# same one.
#
# CROSS-PORT AGREEMENT, and the ONE place this port deliberately differs
# (recorded by W2184, which drove all three hardened guards over one corpus).
# On every other shape the three agree. Refused in all three: -O,
# --remote-name, --remote-name-all, any pipe whose next stage is not `tee`, and
# -o/-oX/-sSo/--output/--output= or > >> 1> >| &> >&2 **to a target that port
# does not read** -- which, here and in stride-gemini, means any target at all.
# Permitted in all three: a bare call, `tee`, every stderr-only redirect
# (2> 2>> 2>&1 2>&2), a `>` or `-o` inside a quoted payload, and -- BELOW each
# port's scan ceiling -- an endpoint appearing only inside a redirect target.
#
# That last one is the only entry here that depends on the ceiling, and it is
# qualified rather than dropped because the dependence is uniform. Above the
# ceiling no port has a blanked operator view to walk, so all three judge scope
# on the raw text whole and all three therefore REFUSE the shape. Agreement
# holds on both sides of the ceiling; what changes is the verdict, not which
# ports share it. Any future port that blanks redirect targets above its own
# ceiling would be the divergence, and would owe an entry below.
#
# The target qualifier in that first list is load-bearing, and an earlier
# revision of this comment omitted it and so contradicted the paragraph below.
#
# THE DIVERGENCE: stride-copilot PERMITS `-o`/`--output`/`>` when the target is
# its canonical response file, and permits a transformer or redirect after a
# `tee` into it, because that port resolves a response FILE-FIRST and genuinely
# reads the file back. This port refuses those shapes for ANY target, because it
# reads the response off stdout alone -- and more than that, it is built to
# REFUSE reading `.stride/.last-api-response.json` at all (see
# own_call_response_payload below: that cache is live here, and a cross-call read
# would record a completion that never happened). So the same command is safe
# there and unsafe here, and the two verdicts are both correct.
#
# The mirror of that: `tee -a <that file>` is refused in stride-copilot, because
# appending corrupts the single JSON document its Tier 1 parses, and permitted
# here, because `tee -a` still passes the body through on stdout, which is all
# this port reads. Do not "fix" either direction into agreement.
#
# The command text carries a Bearer token in every case the guard matches, so
# NOTHING derived from it may reach a message, a log or a file. All four
# messages below are literals selected by a `case`; none interpolates.

# Above this many BYTES the scan goes stateless: quote blanking is skipped and
# the raw text is judged as-is. That direction is deliberate — raw text is a
# superset of what blanking would have left, so the pathological case
# over-refuses and never over-permits.
#
# 100,000, not 4,000. The ceiling originally echoed the canonical plugin's
# figure, on the reasoning that tracking quote state across a long document
# costs more than the guard is worth. That reasoning does not survive contact
# with THIS port's traffic: a Stride completion is a single call carrying
# completion_summary and completion_notes, so a perfectly ordinary one runs to
# several KB — and above the ceiling the prose inside that payload is read as
# live shell syntax, which refused the operator's own well-formed completion
# call. A guard that blocks the correct command is worse than no guard, because
# the operator's only way past it is to stop using the tool.
#
# The actual cost is one linear awk pass, which is nothing at this size, so the
# ceiling exists only to bound the pathological input rather than to buy
# anything on the normal path. A command over 100 KB is not a completion call.
CODEX_GUARD_MAX_SCAN=100000

# The command word of a pipeline stage: the first word that is not a leading
# `env`-style assignment. `tee` reached this way is the blessed pipe; the same
# name appearing as an ARGUMENT ("curl ... -d @tee.json") is not a stage and
# never reaches here.
# W2184 added the compound-keyword skips. The cross-port matrix found that
# `RESP=$(curl ... -o x)`, a backtick substitution, `( curl ... > f )`,
# `{ curl ... -o f; }` and `if`/`while`-guarded calls were all PERMITTED here
# while the sibling ports refused them: each puts something other than curl in
# command position, so the whole segment was skipped -- the redirect rule with
# it. The caller additionally neutralises the grouping characters.
codex_guard_cmd_word() {
  local _cg_stage="$1" _cg_word
  for _cg_word in $_cg_stage; do
    case "$_cg_word" in
      '') continue ;;
      *=*) continue ;;
      env|command|builtin|exec|nohup|time) continue ;;
      if|then|elif|else|fi|while|until|do|done|'!') continue ;;
      *) printf '%s' "${_cg_word##*/}"; return 0 ;;
    esac
  done
  return 0
}

# Replace every single- and double-quoted run with spaces of the same length.
# Blanking rather than deleting keeps every offset stable, so an operator
# found afterwards is genuinely an operator and not a character that was
# sitting inside a quoted payload. This is what keeps a JSON body containing
# `>` from reading as a redirect.
# QUOTE STATE CARRIES ACROSS NEWLINES, and that is the whole reason this is
# written as one buffered pass rather than the obvious per-line awk action.
# Per-line blanking resets the quote state at every record boundary, so a
# payload spanning lines —
#
#     curl ... -d '{
#       "completion_notes": "..."
#     }' > resp.json
#
# — left the newlines INSIDE the quoted run unblanked. The splitter then treated
# them as command separators, the redirect landed in a segment carrying no
# endpoint, and the call was silently permitted. A newline inside quotes is
# payload, not a separator, and only a whole-buffer pass can know that.
#
# BACKSLASH ESCAPES are honoured too, with the shell's own asymmetry: inside
# DOUBLE quotes a backslash escapes the next character, so `\"` does NOT close
# the run; inside SINGLE quotes a backslash is a literal and closes nothing.
# Getting that wrong desynchronises the state on an ordinary escaped JSON body
# (`-d "{\"a\":\"b>c\"}"`) and exposes payload characters as operators.
#
# Every consumed character contributes exactly one output character, so the
# result is LENGTH-PRESERVING — which is what lets the caller cut the raw and
# blanked views at the same offsets. Do not "simplify" this by deleting runs.
codex_guard_blank_quotes() {
  printf '%s' "$1" | awk '
    { buf = (NR == 1 ? $0 : buf "\n" $0) }
    END {
      out = ""; q = ""
      n = length(buf)
      i = 1
      while (i <= n) {
        c = substr(buf, i, 1)
        if (q == "") {
          if (c == "\\") {
            # Escaped character outside quotes: neutralise BOTH bytes, so an
            # escaped redirect (`\>`) is not read as an operator.
            out = out " "
            if (i + 1 <= n) { out = out " "; i += 2 } else { i += 1 }
            continue
          }
          if (c == "\"" || c == "'"'"'") { q = c; out = out " "; i += 1; continue }
          out = out c; i += 1; continue
        }
        if (q == "\"" && c == "\\") {
          out = out " "
          if (i + 1 <= n) { out = out " "; i += 2 } else { i += 1 }
          continue
        }
        if (c == q) { q = ""; out = out " "; i += 1; continue }
        # Inside a quoted run everything is payload, newlines included.
        out = out " "; i += 1
      }
      printf "%s", out
    }
  ' 2>/dev/null || printf '%s' "$1"
}

# Cut both views into segments at ONE set of offsets, and emit them paired.
#
# The boundaries are located in the blanked view so that a separator inside a
# quoted payload does not split a command; the same offsets then cut the raw
# view, which is only sound because blanking is length-preserving (the caller
# asserts that). Each record is `<raw>\037<blanked>\036`.
#
# The two strings are passed through the ENVIRONMENT rather than `awk -v`,
# which processes backslash escapes in its value — a command containing `\n` or
# `\t` would otherwise arrive at awk transformed, and the offsets would no
# longer line up with what bash measured.
codex_guard_split_pairs() {
  CG_SP_RAW="$1" CG_SP_BL="$2" awk '
    function emit(s, e,   r, b) {
      if (e < s) return
      r = substr(raw, s, e - s + 1)
      b = substr(bl,  s, e - s + 1)
      printf "%s\037%s\036", r, b
    }
    BEGIN {
      raw = ENVIRON["CG_SP_RAW"]
      bl  = ENVIRON["CG_SP_BL"]
      n = length(bl); start = 1; i = 1
      while (i <= n) {
        c  = substr(bl, i, 1)
        c2 = substr(bl, i, 2)
        if (c2 == "&&" || c2 == "||") { emit(start, i - 1); i += 2; start = i; continue }
        if (c == ";" || c == "\n")    { emit(start, i - 1); i += 1; start = i; continue }
        i++
      }
      emit(start, n)
    }
  ' 2>/dev/null
}

# Raw text with every REDIRECT TARGET blanked, for the scope test only.
#
# W2184 added this. Without it `curl https://example.test/x > /tmp/api/tasks/9/complete`
# is refused: the segment carries curl and a redirect, and a routed endpoint
# appears -- but only inside the redirect's own target, which says nothing about
# what was called. A sibling port permitted it, so the two disagreed. The
# endpoint has to appear somewhere a request could actually go.
#
# Target spans are located in the BLANKED view and blanked in the RAW view at the
# same offsets, which stays sound because every substitution is a space per byte.
codex_guard_scope_text() {
  CODEX_SC_RAW="$1" CODEX_SC_BL="$2" LC_ALL=C awk '
    BEGIN {
      raw = ENVIRON["CODEX_SC_RAW"]; bl = ENVIRON["CODEX_SC_BL"]
      n = length(bl); out = raw; i = 1
      while (i <= n) {
        if (substr(bl, i, 1) != ">") { i++; continue }
        j = i + 1
        while (j <= n && (substr(bl, j, 1) == ">" || substr(bl, j, 1) == "|" || substr(bl, j, 1) == "&")) j++
        while (j <= n && substr(bl, j, 1) ~ /[ \t]/) j++
        while (j <= n && substr(bl, j, 1) !~ /[ \t\n;|&]/) {
          out = substr(out, 1, j - 1) " " substr(out, j + 1)
          j++
        }
        i = j
      }
      printf "%s", out
    }
  ' 2>/dev/null || printf '%s' "$1"
}

# Does this text name one of the three endpoints the recorder routes?
codex_guard_routed_endpoint() {
  case "$1" in
    */api/tasks/claim*|*/api/tasks/*/complete*|*/api/tasks/*/mark_reviewed*) return 0 ;;
  esac
  return 1
}

# Classify one segment. Echoes exactly one of flag|remote|pipe|redirect when
# the segment hides the response, and nothing when it does not.
#
# Order is deliberate: the flag rules run before the pipe rule so that
# `curl -o f | tee x` is reported as the flag it is rather than as a permitted
# pipe, and the redirect rule runs last because it is the only one that reads
# the segment as a whole rather than a stage.
# $1 = the RAW segment, $2 = the same segment with quoted runs blanked.
#
# THE TWO ARGUMENTS ARE NOT INTERCHANGEABLE, and getting this wrong is a silent
# full bypass rather than a rough edge. Stride-ness is judged on the RAW text,
# because this port's own documented call QUOTES its URL:
#
#     curl -X PATCH "$STRIDE_API_URL/api/tasks/$TASK_ID/complete"
#
# Blanking replaces that quoted run with spaces, so asking the blanked segment
# whether it names a routed endpoint answers NO for every call the skills
# document — and the guard would then permit precisely the calls it exists to
# refuse. Operator detection, by contrast, MUST use the blanked text, so that a
# `>` or a `-o` sitting inside a JSON payload is not read as a shell operator.
#
# Raw for "is this ours", blanked for "what does it do".
# Rule 4, extracted so the normal per-segment path and the above-ceiling
# whole-text path cannot drift apart on what counts as a redirect.
#
# Read the text as a whole: a redirect may sit anywhere in it. The fd word
# immediately before `>` is what separates stdout from stderr, and a
# stderr-only redirect MUST be permitted — it leaves the body on stdout, which
# is the whole point, so refusing it would be a false positive.
#
#   refused  : >   >>   1>   1>>   &>   &>>   >|   >&2
#   permitted: 2>   2>>   2>&1
codex_guard_redirect_kind() {
  printf '%s' "$1" | awk '
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        if (substr($0, i, 1) != ">") continue
        # W2184 reordered this. The stderr-only exemption is tested FIRST: the
        # other order refused `2>&2`, a stderr-to-stderr redirect that leaves the
        # body on stdout, which is precisely the false positive the pitfall names
        # -- and a sibling port permitted it, so the two disagreed.
        prev = (i > 1) ? substr($0, i - 1, 1) : " "
        if (prev == ">") continue                            # second > of >>
        if (prev == "2") {
          before = (i > 2) ? substr($0, i - 2, 1) : " "
          if (before ~ /[ \t]/ || i == 2) continue           # 2> 2>> 2>&1 2>&2
        }
        if (substr($0, i, 3) == ">&2") { print "redirect"; exit }
        if (prev == "&") { print "redirect"; exit }          # &> and &>>
        print "redirect"; exit
      }
    }
  ' 2>/dev/null
}

# $3, optional: "whole" for the above-ceiling path, where the entire command is
# judged as one segment because it was never blanked and so must not be split.
# There, the curl stage cannot be located reliably — a leading `cd "$X" &&` or
# `mkdir -p .stride;` makes the first command word something other than curl,
# and requiring it to BE curl silently permits the call. In whole mode the
# presence of curl as a word anywhere is enough, and every stage is scanned for
# hiding flags. That is deliberately blunter than the normal path: this branch
# is already the conservative one, and over-refusing a >100 KB command is a
# trade this guard is willing to make where under-refusing is not.
codex_guard_segment_kind() {
  local _cg_raw="$1" _cg_seg="$2" _cg_mode="${3:-}" _cg_stage _cg_word _cg_first=1 _cg_curl=0 _cg_rest

  # Scope is judged on raw text with redirect TARGETS blanked -- but only on the
  # segmented path. On the whole-mode path `$_cg_seg` is the UNBLANKED command,
  # so a `>` inside a live payload is indistinguishable from a real operator and
  # the token after it would be blanked out of the scope view. If that token were
  # the URL carrying the only endpoint, scope would be lost and the call
  # PERMITTED -- a false permit on exactly the conservative path that must not
  # have one. There, scope is judged on the raw text whole.
  if [ "$_cg_mode" = "whole" ]; then
    codex_guard_routed_endpoint "$_cg_raw" || return 0
  else
    codex_guard_routed_endpoint "$(codex_guard_scope_text "$_cg_raw" "$_cg_seg")" || return 0
  fi

  if [ "$_cg_mode" = "whole" ]; then
    for _cg_word in $_cg_seg; do
      case "${_cg_word##*/}" in
        curl) _cg_curl=1 ;;
      esac
    done
    [ "$_cg_curl" = "1" ] || return 0
    for _cg_word in $_cg_seg; do
      case "$_cg_word" in
        -O|--remote-name)          printf 'remote'; return 0 ;;
        # The whole-mode loop is a SECOND copy of the option scan, and the W2184
        # fix first landed only in the per-segment one -- so above the ceiling
        # --remote-name-all was still permitted while both siblings refused it.
        # Any option added to one of these loops belongs in both.
        --remote-name-all)         printf 'remote'; return 0 ;;
        -o|--output)               printf 'flag';   return 0 ;;
        --output=*)                printf 'flag';   return 0 ;;
        --*)                       continue ;;
        -*o)                       printf 'flag';   return 0 ;;
        -*O*)                      printf 'remote'; return 0 ;;
        -*o*)                      printf 'flag';   return 0 ;;
      esac
    done
    _cg_rest="$_cg_seg"
    _cg_first=1
    while [ -n "$_cg_rest" ]; do
      case "$_cg_rest" in
        *"|"*) _cg_stage="${_cg_rest%%|*}"; _cg_rest="${_cg_rest#*|}" ;;
        *)     _cg_stage="$_cg_rest";       _cg_rest="" ;;
      esac
      if [ "$_cg_first" = "0" ]; then
        _cg_word=$(codex_guard_cmd_word "$_cg_stage")
        if [ -n "$_cg_word" ] && [ "$_cg_word" != "tee" ]; then
          printf 'pipe'; return 0
        fi
      fi
      _cg_first=0
    done
    codex_guard_redirect_kind "$_cg_seg"
    return 0
  fi

  # --- stages, split on a single `|` ---------------------------------------
  _cg_rest="$_cg_seg"
  while [ -n "$_cg_rest" ]; do
    case "$_cg_rest" in
      *"|"*) _cg_stage="${_cg_rest%%|*}"; _cg_rest="${_cg_rest#*|}" ;;
      *)     _cg_stage="$_cg_rest";       _cg_rest="" ;;
    esac
    _cg_word=$(codex_guard_cmd_word "$_cg_stage")

    if [ "$_cg_word" = "curl" ]; then
      _cg_curl=1
      # Rule 1 / Rule 2 — the response never reaches stdout at all.
      for _cg_word in $_cg_stage; do
        case "$_cg_word" in
          -O|--remote-name)          printf 'remote'; return 0 ;;
          # W2184: named BEFORE the generic `--*` arm below, which skipped it
          # wholesale. It writes bodies to local files exactly as -O does, and it
          # was permitted here while a sibling port refused it.
          --remote-name-all)         printf 'remote'; return 0 ;;
          -o|--output)               printf 'flag';   return 0 ;;
          --output=*)                printf 'flag';   return 0 ;;
          --)                        break ;;
          --*)                       continue ;;
          -*o)                       printf 'flag';   return 0 ;;
          -*O*)                      printf 'remote'; return 0 ;;
          -*o*)                      printf 'flag';   return 0 ;;
        esac
      done
      _cg_first=0
      continue
    fi

    # Rule 3 -- anything downstream of the curl stage that is not `tee` eats the
    # body. `tee` is the one pass-through: it leaves stdout unchanged.
    #
    # W2184 made this an ALLOWLIST. It was a five-name denylist, and the
    # cross-port matrix found the consequence: `| python3 -m json.tool`,
    # `| xargs echo` and `| cat` were PERMITTED here while both sibling ports
    # refused them. A closed list silently permits every consumer nobody thought
    # to name, and the question the guard actually asks is whether the response
    # still reaches stdout -- to which only `tee` answers yes.
    if [ "$_cg_first" = "0" ] && [ "$_cg_curl" = "1" ] && [ -n "$_cg_word" ] \
       && [ "$_cg_word" != "tee" ]; then
      printf 'pipe'; return 0
    fi
    [ "$_cg_first" = "1" ] && _cg_first=0
  done

  [ "$_cg_curl" = "1" ] || return 0

  # --- Rule 4 — a shell redirect takes stdout off the pipe entirely --------
  codex_guard_redirect_kind "$_cg_seg"
  return 0
}

# The refusal document. Codex documents three equivalent ways for a PreToolUse
# hook to deny a call; this emits the CURRENT one on stdout and, belt and
# braces, the exit-2 form on stderr.
#
# WHY hookSpecificOutput and not the `{"decision":"block"}` this port's Stop
# gate emits: the port's rule has always been "emit the document the event in
# hand documents". For Stop that is decision/reason; for PreToolUse the docs
# name decision/reason as LEGACY and permissionDecision as current. Following
# the same rule to a different event gives a different document, and that is
# the rule being applied rather than drift. The two shapes are NOT combined in
# one object: a foreign key risks rejection by a strict parser, and a rejected
# document fails OPEN.
#
# A blank reason degrades a Codex block into a hook FAILURE, so every branch
# here selects a non-empty literal and nothing is interpolated.
codex_guard_refuse() {
  local _cg_kind="$1" _cg_msg _cg_doc

  case "$_cg_kind" in
    flag)
      _cg_msg='Refused: this writes the Stride response to a file with -o/--output, so it never reaches stdout. The PostToolUse recorder reads the completion body off stdout to write .stride/.loop-state.json, and the Stop gate reads that file. Hidden, the record is never written and the gate permits an early stop with the task still in Doing — silently. Let the body print, and pipe it through tee if you also want it on disk -- append | tee <file> and the body still reaches stdout.'
      ;;
    remote)
      _cg_msg='Refused: -O/--remote-name writes the Stride response to a local file named after the URL, so it never reaches stdout. The PostToolUse recorder reads the completion body off stdout to write .stride/.loop-state.json, and the Stop gate reads that file. Hidden, the record is never written and the gate permits an early stop with the task still in Doing — silently. Let the body print, and pipe it through tee if you also want it on disk -- append | tee <file> and the body still reaches stdout.'
      ;;
    pipe)
      _cg_msg='Refused: piping the Stride response into a transformer (jq, head, awk, grep, sed) consumes it before the PostToolUse recorder sees it. That recorder reads the completion body off stdout to write .stride/.loop-state.json, and the Stop gate reads that file. Consumed, the record is never written and the gate permits an early stop with the task still in Doing — silently. tee is the one pipe that is safe here: it passes stdout through unchanged.'
      ;;
    redirect)
      _cg_msg='Refused: redirecting the Stride response with > or >> takes it off stdout, where the PostToolUse recorder reads the completion body to write .stride/.loop-state.json. The Stop gate reads that file. Redirected, the record is never written and the gate permits an early stop with the task still in Doing — silently. Use | tee <file> instead, which writes the file AND leaves the body on stdout; a stderr-only redirect (2>, 2>>, 2>&1) is fine and is not refused.'
      ;;
    *)
      return 0
      ;;
  esac

  _cg_doc=$(jq -nc --arg r "$_cg_msg" '
    {hookSpecificOutput: {
       hookEventName: "PreToolUse",
       permissionDecision: "deny",
       permissionDecisionReason: $r}}' 2>/dev/null) || _cg_doc=""

  # No document means no jq, and a hook that cannot speak must not pretend to.
  # The exit-2 form still carries the refusal, and it is documented as
  # equivalent, so the call is still denied.
  [ -n "$_cg_doc" ] && printf '%s\n' "$_cg_doc"
  printf '%s\n' "$_cg_msg" >&2
  exit 2
}

if [ "$PHASE" = "pre" ]; then
  # PATHNAME EXPANSION OFF for the whole guard. The word loops below split the
  # command on IFS deliberately — that is how a stage becomes argv — but an
  # unquoted glob that survives quote blanking (`-d @*.json`) would then be
  # expanded against whatever directory the hook happens to run in, and the
  # guard's verdict must not depend on the contents of a directory. No false
  # positive is reachable today (a matched filename would have to begin with
  # `-` and contain `o`), which is exactly why this is worth pinning now rather
  # than after one is. Set once here and never restored: every path out of this
  # arm exits the process.
  set -f

  # BYTES EVERYWHERE, and this is a correctness requirement rather than a
  # preference. The guard measures and slices the command in TWO languages:
  # awk (`length`, `substr`) and bash (`${#var}`). Under a UTF-8 locale those
  # disagree — awk counts BYTES, bash counts CHARACTERS, so one em dash is 3 to
  # one and 1 to the other. The raw and blanked views are cut at SHARED
  # OFFSETS, so any disagreement desynchronises them and segments are sliced in
  # the wrong places.
  #
  # Not a rough edge: a handful of em dashes in a completion note — ordinary
  # prose, and this port's own payloads are full of it — was enough to let a
  # hiding flag through a later segment. `LC_ALL=C` puts both languages on
  # bytes so the offsets agree by construction. Exported, so awk children
  # inherit it.
  LC_ALL=C
  export LC_ALL

  # Cheapest possible rejection first: the overwhelming majority of Bash calls
  # in a session are not Stride API calls at all, and this arm runs on the
  # interactive path in front of every one of them.
  case "$COMMAND" in
    *curl*) ;;
    *) exit 0 ;;
  esac
  codex_guard_routed_endpoint "$COMMAND" || exit 0

  # Join line continuations so a command split across lines is read as the one
  # command it is.
  CG_RAW=$(printf '%s' "$COMMAND" | tr '\n' '\036')
  CG_RAW="${CG_RAW//\\$'\036'/ }"
  CG_RAW="${CG_RAW//$'\036'/$'\n'}"

  CG_ONE_SEGMENT=0
  if [ "${#CG_RAW}" -le "$CODEX_GUARD_MAX_SCAN" ]; then
    CG_BL=$(codex_guard_blank_quotes "$CG_RAW")
  else
    # Above the ceiling the scan goes stateless: no blanking, and the raw text
    # is its own operator view.
    #
    # AND THE COMMAND IS NOT SEGMENTED. That second half is not an optimisation,
    # it is what makes this path safe, and leaving it out is a false PERMIT
    # rather than the false refusal one would expect. With blanking off, every
    # `;` and `&&` inside the quoted payload becomes a separator, so an ordinary
    # completion note containing prose ("...the writer; use -o to save") shatters
    # the command into fragments. The endpoint then sits in one fragment and the
    # `-o` in another, and a per-fragment check finds a hiding flag with no
    # endpoint beside it and waves it through. Measured exactly that way: a
    # 110 KB completion call with `-o` was PERMITTED.
    #
    # Treating the whole text as ONE segment restores the property this path is
    # supposed to have — raw text is a superset of the blanked text, so judging
    # it whole can only ever over-refuse.
    CG_BL="$CG_RAW"
    CG_ONE_SEGMENT=1
  fi

  # Neutralise the shell's GROUPING characters in the operator view, each
  # replaced by a space so the substitution is LENGTH-PRESERVING and the pairing
  # offsets still hold. W2184: without this a curl inside a command
  # substitution, a subshell or a brace group is invisible to the command-word
  # scan and the whole segment is skipped. Quoted spans are already blanked, so
  # a `(` surviving here is real syntax rather than payload.
  CG_BL=$(printf '%s' "$CG_BL" | LC_ALL=C tr '()`{}' '     ')

  # Blanking is length-preserving by construction, which is what lets the two
  # views be cut at the SAME offsets below. If that ever stops holding, FAIL
  # CLOSED: scan the raw text as its own operator view.
  #
  # An earlier revision tried to REPAIR a mismatch instead, padding or
  # truncating the blanked view to match. That was wrong, and wrong in the
  # direction that matters: padding or truncating shifts every offset after the
  # adjustment, so the segments are cut in the wrong places and a hidden call in
  # a later segment is silently PERMITTED. A repair that moves the offsets
  # cannot fix a problem that is about the offsets.
  #
  # Falling back to raw does over-refuse — payload characters read as live shell
  # syntax — and that is the acceptable direction here, because an over-refusal
  # is loud and recoverable while a missed hide is silent and loses the task. The
  # `LC_ALL=C` above is what makes this branch essentially unreachable; it is the
  # backstop, not the plan.
  if [ "${#CG_BL}" -ne "${#CG_RAW}" ]; then
    CG_BL="$CG_RAW"
  fi

  # Segments: a `;`, `&&`, `||` or newline starts a new command, and each is
  # judged on its own. Attributing a redirect to the wrong segment is the
  # classic false positive here — `curl ... ; echo done > log` hides nothing.
  #
  # The boundaries are found in the BLANKED view, so a `;` inside a quoted JSON
  # payload does not split a command in half; each segment is then cut from BOTH
  # views at those same offsets and the pair travels together.
  CG_KIND=""
  if [ "$CG_ONE_SEGMENT" = "1" ]; then
    CG_KIND=$(codex_guard_segment_kind "$CG_RAW" "$CG_BL" whole)
    [ -n "$CG_KIND" ] && codex_guard_refuse "$CG_KIND"
    exit 0
  fi

  while IFS= read -r -d $'\036' CG_PAIR; do
    CG_SEG_RAW="${CG_PAIR%%$'\037'*}"
    CG_SEG_BL="${CG_PAIR#*$'\037'}"
    [ -n "$CG_SEG_RAW" ] || continue
    CG_KIND=$(codex_guard_segment_kind "$CG_SEG_RAW" "$CG_SEG_BL")
    [ -n "$CG_KIND" ] && codex_guard_refuse "$CG_KIND"
  done < <(codex_guard_split_pairs "$CG_RAW" "$CG_BL")

  exit 0
fi

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

# NOTE (W2181): the `before_doing` arm used to sit HERE. It now sits below the
# helper definitions, because it also writes the claim pointer and so needs
# own_call_response_payload — and a second copy of that read is exactly what
# this port must not grow, since the whole point of that function's name is
# that there is only one of it. The move is behaviour-preserving: everything
# between this point and the arm's new home is a function DEFINITION, so
# nothing that ran before the arm runs after it now.

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
    if [ -z "$_payload" ]; then
      # ABSENT or EMPTY body. W2181: this used to return in silence, and the
      # silence was the bug. This is the single most consequential outcome the
      # recorder has — the completion may well have succeeded server-side,
      # the loop state is NOT written, and the Stop gate will therefore permit
      # an early stop with the task still in Doing. Saying nothing here is
      # indistinguishable from a task that was never completed at all.
      #
      # The `pre` guard above now refuses the commands that cause this
      # deliberately, so reaching here means something the guard cannot see:
      # a harness-truncated response, a dropped connection, a tool wrapper
      # that swallowed the body. The guard narrows this path; it does not
      # close it, which is exactly why the announcement still has to exist.
      printf 'stride-hook: no completion response reached this hook; no loop state recorded, so the Stop gate cannot tell this task was completed\n' >&2
    elif ! printf '%s' "$_payload" | jq empty > /dev/null 2>&1; then
      printf 'stride-hook: completion response was unparsable; no loop state recorded\n' >&2
    fi
    # A body that parsed but is not a success (a 422, a 404) legitimately
    # records nothing and stays SILENT: the task genuinely was not completed,
    # so there is nothing for the gate to miss and announcing every failed
    # completion would be noise. Only the two branches above are anomalies.
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

# A claim pointer is a SUCCESSFUL claim only when the body carries an
# identifier at the right type. Deliberately weaker than its loop-state
# sibling: a claim body has no needs_review to check, and the pointer records
# nothing else.
claim_state_payload_ok() {
  printf '%s' "${1:-}" | jq -e '
    try ((.data.identifier | type == "string" and length > 0)) catch false
  ' > /dev/null 2>&1
}

# Sibling of write_loop_state, NOT a rename of it — the two records answer
# opposite questions and the gate must never be able to read one for the
# other. Same symlink refusals, same atomic staging, same never-fatal
# contract; only the destination differs.
write_claim_state() {
  local _json="$1" _tmp
  if [ -L "$PROJECT_DIR/.stride" ]; then
    printf 'stride-hook: .stride is a symlink; not recording the claim\n' >&2
    return 0
  fi
  if [ -L "$CLAIM_STATE_FILE" ]; then
    printf 'stride-hook: claim-state path is a symlink; not recording the claim\n' >&2
    return 0
  fi
  if [ -e "$CLAIM_STATE_FILE" ] && [ ! -f "$CLAIM_STATE_FILE" ]; then
    printf 'stride-hook: claim-state path is not a regular file; not recording the claim\n' >&2
    return 0
  fi
  mkdir -p "$PROJECT_DIR/.stride" 2>/dev/null || {
    printf 'stride-hook: could not create .stride/ for the claim state; continuing\n' >&2
    return 0
  }
  _tmp=$(mktemp "$PROJECT_DIR/.stride/claim-state.XXXXXX" 2>/dev/null) || {
    printf 'stride-hook: could not stage the claim state; continuing\n' >&2
    return 0
  }
  if printf '%s\n' "$_json" > "$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$CLAIM_STATE_FILE" 2>/dev/null || {
      printf 'stride-hook: could not move the claim state into place; continuing\n' >&2
      rm -f "$_tmp" 2>/dev/null
    }
  else
    printf 'stride-hook: could not write the claim state; continuing\n' >&2
    rm -f "$_tmp" 2>/dev/null
  fi
  return 0
}

# --- Claim: clear the record, and record the claim ------------------------
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

  # W2181: the claim pointer, cleared UNCONDITIONALLY and then rewritten only
  # from THIS call's parsed response. The order is the whole guarantee. A
  # failed claim, an empty queue or an unparsable body must all leave NO
  # pointer, because a stale one would refuse to let a finished session end —
  # the gate's own wedge, arriving through its evidence rather than its logic.
  #
  # The pointer is built from $INPUT via own_call_response_payload and from
  # nothing else. It must NEVER be sourced from .stride/.last-api-response.json:
  # that file survives across calls, so on a failed claim it would resolve the
  # PREVIOUS claim's body and record a claim this session does not hold. That
  # is the same cross-call hazard the loop-state recorder was built to avoid,
  # and it is just as live here.
  if [ ! -L "$PROJECT_DIR/.stride" ]; then
    rm -f "$CLAIM_STATE_FILE" 2>/dev/null || true
  fi
  _claim_payload=$(own_call_response_payload "$INPUT")
  if claim_state_payload_ok "$_claim_payload"; then
    _claim_ident=$(printf '%s' "$_claim_payload" | jq -r '.data.identifier' 2>/dev/null || echo "")
    if loop_state_safe "$_claim_ident"; then
      _claim_sid=$(printf '%s' "$INPUT" | jq -r '.session_id // .sessionId // .session.id // empty' 2>/dev/null || echo "")
      [ -n "$_claim_sid" ] || _claim_sid="${CODEX_SESSION_ID:-}"
      [ -n "$_claim_sid" ] || _claim_sid="${CLAUDE_SESSION_ID:-}"
      loop_state_safe "$_claim_sid" || _claim_sid="unknown"
      _claim_json=$(jq -nc \
        --arg ident "$_claim_ident" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg sid "$_claim_sid" \
        '{identifier: $ident, claimed_at: $ts, session_id: $sid}' \
        2>/dev/null) || _claim_json=""
      [ -n "$_claim_json" ] && write_claim_state "$_claim_json"
    fi
  fi
  exit 0
fi

record_loop_state_for_completion || true

# A RECORDED completion clears the claim pointer — and the condition is the
# loop-state file itself, not merely "this was a /complete call". The
# distinction is the whole point: a 422 completion leaves the task STILL
# CLAIMED and unfinished, so clearing the pointer there would disarm the
# held-claim gate at the exact moment it is needed. Only evidence that the
# completion actually landed retires the pointer, and that evidence is the
# record the gate itself reads.
if [ "${HOOK_NAME:-}" = "before_review" ] \
   && [ ! -L "$PROJECT_DIR/.stride" ] \
   && [ -f "$LOOP_STATE_FILE" ]; then
  rm -f "$CLAIM_STATE_FILE" 2>/dev/null || true
fi

exit 0
