#!/usr/bin/env bash
#
# run_eval.sh — eval runner for the security-reviewer agent.
#
# Dispatches the security-reviewer agent (via `codex exec`) against every fixture
# in fixtures/ and asserts the findings documented in fixtures/EXPECTED.md.
# Output is TAP version 13; exit 0 only when every fixture produces its expected
# vulnerability_class + severity at the expected count.
#
# Tolerance: the runner asserts (file, vulnerability_class, severity, count).
# CWE/OWASP arrays are advisory — mismatches emit `# warn:` comments but do not
# fail the run. EXPECTED.md is the spec; do not mutate it to match the agent.
#
# Considerations mode: a fixture under considerations/ ending in `.diff` is
# dispatched in the agent's `considerations` input mode — the diff plus the
# resolved list from its sibling `<stem>.considerations` file. Its EXPECTED.md
# row uses the `→ CONSIDERATIONS <s1>,<s2>,… [AND finding|AND clean]` grammar
# (see EXPECTED.md "Considerations mode"); the runner asserts the ordered
# consideration_verdicts[].status list plus the backing-finding (positive) /
# zero-finding (negative) expectation. consideration_verdicts is agent output,
# so there is no golden-file coverage for this mode.
#
# Which agent runs (W2640, porting upstream W2274): Codex CLI cannot make a
# custom agent the session agent of a headless run. `codex exec` has no agent
# flag, and Codex spawns custom agents only as subagents on request (CLI
# reference and subagents pages, learn.chatgpt.com/docs, read 2026-11-04). So
# the runner does the documented next best thing: it hands THIS checkout's
# agent file to `codex exec` as the session's base instructions with
# `-c model_instructions_file='<agents/security-reviewer.md>'` ("Replacement for
# built-in instructions", config reference). The model therefore answers under
# this plugin's agent prompt, not under Codex's default coding-agent prompt and
# not under an installed copy. Each call runs from an empty scratch directory
# (`--cd` and the cwd), outside any Git repository (`--skip-git-repo-check`),
# in a read-only sandbox, with the shell tool, web search, subagents and image
# viewing turned off, approvals set to never, no user config.toml (so no
# MCP servers from it) and no session files saved. The agent judges only the
# prompt, which carries the whole file or diff, and can neither read
# EXPECTED.md's answers nor edit the repo. None of this has been observed in a
# live Codex CLI; see the CHANGELOG's "Not verified" list.
#
# Usage:
#   bash lib/run_eval.sh                            # all fixtures
#   bash lib/run_eval.sh --fixture <path>           # one fixture
#   bash lib/run_eval.sh --only <prefix>            # fixtures whose path starts with <prefix>
#                                                   #   e.g. --only considerations/
#   bash lib/run_eval.sh --dry-run                  # print the invocation; no CLI call, exit 0
#   bash lib/run_eval.sh --verbose                  # echo prompts and raw agent JSON
#
# Every run prints `# invocation: <argv>` and `# auth: <mode>` after the TAP
# plan line, so the exact codex command is on record. --dry-run prints both,
# then lists every parsed row as `ok N - <fixture> (...) # SKIP dry run` and
# exits 0 without calling (or even looking for) the CLI.
#
# Auth (not needed for --dry-run): CODEX_API_KEY when set, otherwise a saved
# Codex login (`codex login status` exits 0). Neither the key nor the
# login-status output is ever printed, only the mode name. With neither, exit 2.
#
# Env:
#   CODEX_CLI           path to the Codex CLI (default: codex)
#   CODEX_API_KEY       API key for `codex exec`; optional when the CLI is logged in
#   EVAL_AGENT_FILE     agent file used as the instructions (default: this
#                       checkout's agents/security-reviewer.md)
#   EVAL_MODEL          model to pass with -m (default: unset = Codex's default)
#   FIXTURES_DIR        default: <lib>/../fixtures
#   LOG_DIR             default: logs
#
# Logs per fixture: <stem>.raw.txt (codex stdout, the final agent message),
# <stem>.err.txt (codex stderr: progress, auth and config errors), <stem>.json
# (parsed).
#
# Exit codes:
#   0  all fixtures pass (or --dry-run)
#   1  one or more fixtures fail
#   2  setup/usage error (missing dependency, bad args, no auth)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default is CWD-independent (resolved from this script's location); override with
# FIXTURES_DIR to point at a copy elsewhere.
FIXTURES_DIR="${FIXTURES_DIR:-$SCRIPT_DIR/../fixtures}"
EXPECTED_FILE="${FIXTURES_DIR}/EXPECTED.md"
LOG_DIR="${LOG_DIR:-logs}"
CODEX_CLI="${CODEX_CLI:-codex}"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_FILE="${EVAL_AGENT_FILE:-$ROOT_DIR/agents/security-reviewer.md}"
MODEL="${EVAL_MODEL:-}"

VERBOSE=0
DRY_RUN=0
SINGLE_FIXTURE=""
ONLY_PREFIX=""
AUTH_MODE=""
WORK_DIR=""
CODEX_ARGV=()

usage() {
  # Print the leading comment block (from line 3 to the first non-comment line).
  awk 'NR < 3 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

require_cmd() {
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH"
  [ -f "$AGENT_FILE" ] || die "agent file not found at $AGENT_FILE (EVAL_AGENT_FILE)"
  case "$AGENT_FILE" in
    /*) ;;
    *) AGENT_FILE="$(cd "$(dirname "$AGENT_FILE")" && pwd)/$(basename "$AGENT_FILE")" ;;
  esac
  # The path goes into a TOML literal string ('...'), which cannot hold a quote
  # or a line break.
  case "$AGENT_FILE" in
    *"'"*|*$'\n'*|*$'\r'*) die "agent file path must not contain a single quote or a line break: $AGENT_FILE" ;;
  esac
  [ -f "$EXPECTED_FILE" ] || die "EXPECTED.md not found at $EXPECTED_FILE"
  if [ "$DRY_RUN" -eq 0 ]; then
    command -v "$CODEX_CLI" >/dev/null 2>&1 || die "$CODEX_CLI not found on PATH (set CODEX_CLI or pass --dry-run)"
    detect_auth
  else
    AUTH_MODE="dry-run"
  fi
}

# detect_auth
# Sets AUTH_MODE to `api-key` when CODEX_API_KEY is set (Codex's documented
# credential for `codex exec`), else to `codex-login` when `codex login status`
# exits 0 (the documented logged-in result), else dies with exit 2. Never prints
# the key, and never prints the login-status output (it can name the account),
# only the mode name.
detect_auth() {
  if [ -n "${CODEX_API_KEY:-}" ]; then
    AUTH_MODE="api-key"
    return 0
  fi
  if "$CODEX_CLI" login status >/dev/null 2>&1 </dev/null; then
    AUTH_MODE="codex-login"
    return 0
  fi
  die "no Codex auth: the CLI is not logged in and CODEX_API_KEY is not set -- run \`codex login\` or export CODEX_API_KEY, or pass --dry-run"
}

# build_codex_argv
# Fills CODEX_ARGV with the exact command each fixture is dispatched with: this
# checkout's agent file as the session instructions, an empty scratch working
# root outside any Git repository, a read-only sandbox, no shell, web search,
# subagents or image viewing, approvals never, no user config.toml, no session
# files, and the prompt read from stdin (`-`). Flag sources: the `codex exec`
# section of Codex's CLI reference and its config reference.
build_codex_argv() {
  CODEX_ARGV=(
    "$CODEX_CLI" exec
    --skip-git-repo-check
    --cd "$WORK_DIR"
    --sandbox read-only
    --ephemeral
    --ignore-user-config
    --color never
    -c "model_instructions_file='$AGENT_FILE'"
    -c features.shell_tool=false
    -c 'web_search="disabled"'
    -c features.multi_agent=false
    -c features.view_image=false
    -c 'approval_policy="never"'
  )
  if [ -n "$MODEL" ]; then
    CODEX_ARGV+=(-m "$MODEL")
  fi
  CODEX_ARGV+=(-)
}

# print_invocation
# Prints `# invocation: <argv>` (shell-quoted) as a TAP comment line.
print_invocation() {
  printf '# invocation:'
  printf ' %q' "${CODEX_ARGV[@]}"
  printf '\n'
}

# parse_expected_md
# Reads $EXPECTED_FILE and emits one TAB-delimited record per expected finding:
#   path<TAB>class<TAB>severity<TAB>cwe_json<TAB>owasp_json<TAB>count
# `path` is relative to FIXTURES_DIR. The Bitbucket multi-finding row produces
# count=2; all other rows produce count=1.
parse_expected_md() {
  awk '
    /^- \[[ x]\] `[^`]+`/ {
      line = $0
      # filename: first backtick-fenced token
      match(line, /`[^`]+`/)
      path = substr(line, RSTART+1, RLENGTH-2)
      rest = substr(line, RSTART+RLENGTH)
      # negative-control marker: " → NONE" before any optional prose. Treat as count=0
      # with class/severity placeholders the comparator interprets as "no findings expected".
      if (rest ~ /^ +→ +NONE( |$)/ || rest ~ /^ +→ +NONE +—/) {
        printf "%s\t%s\t%s\t%s\t%s\t%d\n", path, "__NONE__", "__NONE__", "", "", 0
        next
      }
      # considerations-mode marker: " → CONSIDERATIONS <s1>,<s2>,... [AND finding|AND clean]".
      # Emits a record the considerations comparator interprets: class=__CONSIDERATIONS__,
      # severity=verdict CSV, cwe field carries the finding expectation (F=at least one
      # backing finding, C=zero findings, U=unchecked), count=number of verdicts.
      # U is a placeholder, never an empty field: the caller splits records with
      # IFS=TAB, and bash collapses consecutive tabs, which would shift fields.
      if (rest ~ /^ +→ +CONSIDERATIONS +/) {
        head = rest
        sub(/^ +→ +CONSIDERATIONS +/, "", head)
        fexp = "U"
        if (head ~ / AND +finding( |$|—)/) fexp = "F"
        else if (head ~ / AND +clean( |$|—)/) fexp = "C"
        split(head, hp, " ")
        verdicts = hp[1]
        nc = split(verdicts, vv, ",")
        printf "%s\t%s\t%s\t%s\t%s\t%d\n", path, "__CONSIDERATIONS__", verdicts, fexp, "", nc
        next
      }
      # class + severity: after → token, before first comma
      n = match(rest, /→ +[a-z_]+ +\([a-z]+\)/)
      if (n == 0) next
      head = substr(rest, RSTART, RLENGTH)
      gsub(/^→ +/, "", head)
      split(head, parts, " *\\(")
      cls = parts[1]
      sev = parts[2]
      sub(/\)$/, "", sev)
      # multi-finding marker: " AND " before the comma
      count = 1
      tail = substr(rest, RSTART+RLENGTH)
      if (tail ~ /^ +AND +[a-z_]+ +\([a-z]+\)/) {
        count = 2
      }
      # cwe array (first backticked block matching cwe:)
      cwe = ""
      if (match(line, /`cwe: \[[^]]*\]`/)) {
        cwe = substr(line, RSTART+1, RLENGTH-2)
        sub(/^cwe: /, "", cwe)
      }
      # owasp array
      owasp = ""
      if (match(line, /`owasp: \[[^]]*\]`/)) {
        owasp = substr(line, RSTART+1, RLENGTH-2)
        sub(/^owasp: /, "", owasp)
      }
      printf "%s\t%s\t%s\t%s\t%s\t%d\n", path, cls, sev, cwe, owasp, count
    }
  ' "$EXPECTED_FILE"
}

# sanitize_path <relative-path>
# Produces a filesystem-safe stem for log files: slashes and dots → underscores.
sanitize_path() {
  printf '%s' "$1" | tr '/.' '__'
}

# detect_lang <relative-path>
# Returns a fenced-code-block language hint for the agent prompt. Best-effort —
# the agent does not rely on this for analysis, but a plausible hint helps it
# render output consistently.
detect_lang() {
  case "$1" in
    *.py)  printf 'python' ;;
    *.js)  printf 'javascript' ;;
    *.ts)  printf 'typescript' ;;
    *.go)  printf 'go' ;;
    *.rb)  printf 'ruby' ;;
    *.ex|*.exs) printf 'elixir' ;;
    *.yml|*.yaml) printf 'yaml' ;;
    *.sh)  printf 'bash' ;;
    *.kt|*.kts) printf 'kotlin' ;;
    *.swift) printf 'swift' ;;
    *.m|*.mm) printf 'objc' ;;
    *.h)   printf 'objc' ;;
    *.jsx) printf 'javascript' ;;
    *.tsx) printf 'typescript' ;;
    *.xml|*.plist) printf 'xml' ;;
    Dockerfile*) printf 'dockerfile' ;;
    *)     printf 'text' ;;
  esac
}

# emit_rule_blocks <fixture-abs-path> <with-considerations: 0|1>
# W2636 (upstream W2285): the agent is a core that never reads a rule file
# itself; the stride-security-review skill sends its packs and mode files in
# keyed blocks. The eval sends all eleven packs, in the core's table order, so
# every fixture is scored against the full rule set the pre-split agent carried
# in its prompt, then modes/considerations.md in considerations mode and
# modes/reproduction.md, as the skill does. Never modes/result-file.md: the eval
# supplies no SECURITY_RESULT_PATH. The key is sixteen hex digits from
# /dev/urandom, made again if the fixture holds it. A file that cannot be read
# is left out with a `rule file not sent: <name>` line on stderr, and the run
# goes on, so the agent reviews with its core rules for that fixture.
EVAL_RULES_DIR="${EVAL_RULES_DIR:-$ROOT_DIR/skills/stride-security-review}"
EVAL_PACKS="packs/android.md packs/django.md packs/express.md packs/ios.md packs/phoenix.md packs/rails.md packs/react-nextjs.md packs/web-defense.md packs/supply-chain.md packs/ci-cd.md packs/agentic.md"
emit_rule_blocks() {
  local abs="$1" cons="$2" key="" tries=0 name names
  while [ "$tries" -lt 5 ]; do
    key="$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')"
    tries=$((tries + 1))
    [ "${#key}" -eq 16 ] && ! grep -qF -- "$key" "$abs" && break
    key=""
  done
  names="$EVAL_PACKS"
  [ "$cons" -eq 1 ] && names="$names modes/considerations.md"
  names="$names modes/reproduction.md"
  if [ -z "$key" ]; then
    for name in $names; do printf 'rule file not sent: %s\n' "$name" >&2; done
    return 0
  fi
  printf 'Rule-file key: %s\n\n' "$key"
  for name in $names; do
    if [ -f "$EVAL_RULES_DIR/$name" ] && [ -s "$EVAL_RULES_DIR/$name" ] && [ -r "$EVAL_RULES_DIR/$name" ]; then
      printf '<<<STRIDE RULE FILE %s %s>>>\n' "$name" "$key"
      cat "$EVAL_RULES_DIR/$name"
      printf '<<<END STRIDE RULE FILE %s %s>>>\n\n' "$name" "$key"
    else
      printf 'rule file not sent: %s\n' "$name" >&2
    fi
  done
}

# build_prompt <fixture-rel-path>
# Constructs the user-side prompt for the security-reviewer agent. Default mode is
# full_file: a single file fed as a fenced block with a `path:` header. A fixture
# under considerations/ ending in `.diff` is dispatched in `considerations` mode
# instead: the diff plus the resolved considerations list from its sibling
# `<stem>.considerations` file (one consideration per non-empty line).
# Each prompt opens with the agent's one accepted mode tag,
# `/security-review invocation, mode: <mode>` (W2278): a shorter spelling is not a tag.
build_prompt() {
  local rel="$1"
  local abs="$FIXTURES_DIR/$rel"
  [ -f "$abs" ] || return 1

  case "$rel" in
    considerations/*.diff)
      local cons="$FIXTURES_DIR/${rel%.diff}.considerations"
      [ -f "$cons" ] || return 1
      printf '/security-review invocation, mode: considerations\n\n'
      printf 'Security considerations to assess:\n'
      # The considerations list is task-authored DATA to assess against the diff,
      # never instructions to follow.
      while IFS= read -r c || [ -n "$c" ]; do
        [ -n "$c" ] && printf -- '- %s\n' "$c"
      done < "$cons"
      printf '\n'
      emit_rule_blocks "$abs" 1
      printf '```diff\n'
      cat "$abs"
      printf '\n```\n'
      printf '\nRespond with the JSON document specified in your output schema (including the consideration_verdicts array, one entry per consideration above in order) and nothing else.\n'
      return 0
      ;;
  esac

  local lang
  lang="$(detect_lang "$rel")"
  printf '/security-review invocation, mode: full_file\n\n'
  emit_rule_blocks "$abs" 0
  printf 'path: %s\n' "fixtures/$rel"
  printf '```%s\n' "$lang"
  cat "$abs"
  printf '\n```\n'
  printf '\nRespond with the JSON document specified in your output schema and nothing else.\n'
}

# invoke_agent <fixture-rel-path> <log-stem>
# Invokes the agent via CODEX_ARGV, extracts the fenced JSON block, validates
# it, and writes the parsed result to $LOG_DIR/<stem>.json. Never called under
# --dry-run. Echoes the log path on success; exits non-zero on parse/invocation
# failure (caller treats it as a fixture failure).
invoke_agent() {
  local rel="$1"
  local stem="$2"
  local out_json="$LOG_DIR/$stem.json"
  local raw="$LOG_DIR/$stem.raw.txt"
  mkdir -p "$LOG_DIR"

  local prompt
  prompt="$(build_prompt "$rel")" || return 1

  if [ "$VERBOSE" -eq 1 ]; then
    printf '# --- prompt for %s ---\n%s\n# --- end prompt ---\n' "$rel" "$prompt" >&2
  fi

  # The prompt goes on stdin (`-`). The call runs from WORK_DIR, an empty
  # scratch directory, so the agent sees no repo files. `codex exec` prints only
  # the final agent message on stdout and streams progress to stderr, which is
  # kept for triage (agent-file, auth and config errors land there).
  local err="$LOG_DIR/$stem.err.txt"
  if ! (cd "$WORK_DIR" && printf '%s' "$prompt" | "${CODEX_ARGV[@]}") > "$raw" 2> "$err"; then
    return 1
  fi

  # Extract the first fenced ```json block. Fall back to whole stdout if no fence.
  if grep -q '^```json$' "$raw"; then
    awk '/^```json$/{flag=1;next} /^```$/{if(flag){exit}} flag' "$raw" > "$out_json"
  else
    cp "$raw" "$out_json"
  fi

  if ! jq -e . "$out_json" >/dev/null 2>&1; then
    return 1
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    printf '# --- agent JSON for %s ---\n' "$rel" >&2
    jq . "$out_json" >&2
    printf '# --- end JSON ---\n' >&2
  fi

  printf '%s' "$out_json"
}

# compare_finding <path> <class> <sev> <cwe_json> <owasp_json> <count> <json_file>
# Returns 0 if the agent JSON contains at least <count> findings matching
# (file basename or suffix, class, severity). Emits a diff-style block on
# stderr when the comparison fails. CWE/OWASP mismatches are advisory warnings.
compare_finding() {
  local rel="$1" cls="$2" sev="$3" cwe="$4" owasp="$5" count="$6" json="$7"

  # Match findings whose file equals the relative path OR ends with the basename.
  # The agent may report file as "fixtures/sql_injection.py" or just
  # "sql_injection.py" depending on prompt handling.
  local base
  base="$(basename "$rel")"

  # Considerations-mode case (EXPECTED.md row → CONSIDERATIONS; cls="__CONSIDERATIONS__").
  # `sev` carries the expected ordered verdict CSV; `cwe` carries the finding
  # expectation (F=at least one backing finding, C=zero findings, U=unchecked).
  # Assert the agent's consideration_verdicts[].status list matches, in order.
  if [ "$cls" = "__CONSIDERATIONS__" ]; then
    local exp_verdicts="$sev" fexp="$cwe"
    local got_verdicts
    got_verdicts=$(jq -r '[ .consideration_verdicts // [] | .[] | .status ] | join(",")' "$json")
    local n_findings
    n_findings=$(jq '[ .findings // [] | .[] ] | length' "$json")
    local ok=1 detail=""
    if [ "$got_verdicts" != "$exp_verdicts" ]; then
      ok=0
      detail="verdicts expected [$exp_verdicts] got [$got_verdicts]"
    fi
    if [ "$fexp" = "F" ] && [ "$n_findings" -lt 1 ]; then
      ok=0
      detail="${detail:+$detail; }expected at least one backing finding, got 0"
    elif [ "$fexp" = "C" ] && [ "$n_findings" -ne 0 ]; then
      ok=0
      detail="${detail:+$detail; }negative control expected 0 findings, got $n_findings"
    fi
    if [ "$ok" -eq 0 ]; then
      cat >&2 <<EOF
  --- expected ($json)
  - considerations [$exp_verdicts] ($fexp)
  + $detail
EOF
      return 1
    fi
    return 0
  fi

  # Negative-control case (EXPECTED.md row → NONE; cls="__NONE__", count=0):
  # the fixture must produce ZERO findings of any class on this file.
  if [ "$cls" = "__NONE__" ]; then
    local any_count
    any_count=$(jq --arg rel "$rel" --arg base "$base" '
      [ .findings // []
        | .[]
        | select(
            .file == $rel
            or .file == $base
            or (.file | endswith("/" + $rel))
            or (.file | endswith("/" + $base))
          )
      ] | length
    ' "$json")
    if [ "$any_count" -gt 0 ]; then
      local actual
      actual=$(jq --arg rel "$rel" --arg base "$base" '
        [ .findings // []
          | .[]
          | select(
              .file == $rel
              or .file == $base
              or (.file | endswith("/" + $rel))
              or (.file | endswith("/" + $base))
            )
          | "\(.vulnerability_class)/\(.severity)"
        ] | join(", ")
      ' "$json")
      actual=${actual//\"/}
      cat >&2 <<EOF
  --- expected
  +++ actual ($json)
  - (none) — negative control
  + $actual
EOF
      return 1
    fi
    return 0
  fi

  local match_count
  match_count=$(jq --arg rel "$rel" --arg base "$base" --arg cls "$cls" --arg sev "$sev" '
    [ .findings // []
      | .[]
      | select(
          .file == $rel
          or .file == $base
          or (.file | endswith("/" + $rel))
          or (.file | endswith("/" + $base))
        )
      | select(.vulnerability_class == $cls and .severity == $sev)
    ] | length
  ' "$json")

  if [ "$match_count" -lt "$count" ]; then
    # Failure — build a diff-style report on stderr.
    local actual
    actual=$(jq --arg rel "$rel" --arg base "$base" '
      [ .findings // []
        | .[]
        | select(
            .file == $rel
            or .file == $base
            or (.file | endswith("/" + $rel))
            or (.file | endswith("/" + $base))
          )
        | "\(.vulnerability_class)/\(.severity)"
      ] | join(", ")
    ' "$json")
    actual=${actual//\"/}
    [ -n "$actual" ] || actual='(none)'
    cat >&2 <<EOF
  --- expected
  +++ actual ($json)
  - $cls/$sev x$count
  + $actual
EOF
    return 1
  fi

  # Advisory: check CWE / OWASP overlap on any matching finding.
  if [ -n "$cwe" ] && [ "$cwe" != "[]" ]; then
    local cwe_overlap
    cwe_overlap=$(jq --arg rel "$rel" --arg base "$base" --arg cls "$cls" --arg sev "$sev" --argjson exp "$cwe" '
      [ .findings // []
        | .[]
        | select(
            .file == $rel
            or .file == $base
            or (.file | endswith("/" + $rel))
            or (.file | endswith("/" + $base))
          )
        | select(.vulnerability_class == $cls and .severity == $sev)
        | (.cwe // []) - ((.cwe // []) - $exp)
      ] | add // []
    ' "$json")
    if [ "$cwe_overlap" = "[]" ]; then
      printf '# warn: %s — no CWE overlap with expected %s\n' "$rel" "$cwe" >&2
    fi
  fi
  if [ -n "$owasp" ] && [ "$owasp" != "[]" ]; then
    local owasp_overlap
    owasp_overlap=$(jq --arg rel "$rel" --arg base "$base" --arg cls "$cls" --arg sev "$sev" --argjson exp "$owasp" '
      [ .findings // []
        | .[]
        | select(
            .file == $rel
            or .file == $base
            or (.file | endswith("/" + $rel))
            or (.file | endswith("/" + $base))
          )
        | select(.vulnerability_class == $cls and .severity == $sev)
        | (.owasp // []) - ((.owasp // []) - $exp)
      ] | add // []
    ' "$json")
    if [ "$owasp_overlap" = "[]" ]; then
      printf '# warn: %s — no OWASP overlap with expected %s\n' "$rel" "$owasp" >&2
    fi
  fi

  return 0
}

# emit_tap <n> <status> <fixture> <detail>
emit_tap() {
  local n="$1" status="$2" fixture="$3" detail="$4"
  printf '%s %d - %s (%s)\n' "$status" "$n" "$fixture" "$detail"
}

# validate_findings_schema <json_file>
# Asserts every finding in the agent JSON carries the full documented per-finding
# schema (severity, file, line, vulnerability_class, cwe, owasp, description,
# remediation, confidence) AND that cwe/owasp are non-empty arrays for every
# non-info finding (the plugin's contract is that concrete findings always map to
# a CWE and OWASP category). Prints each offending finding to stderr and returns
# 1 on any violation; returns 0 when all findings conform (including the empty
# findings list a clean fixture or the --dry-run stub produces).
validate_findings_schema() {
  local json="$1"
  local required='["severity","file","line","vulnerability_class","cwe","owasp","description","remediation","confidence"]'
  local violations
  violations=$(jq -r --argjson req "$required" '
    [ .findings // []
      | to_entries[]
      | .key as $i | .value as $f
      | ([ $req[] | . as $k | select(($f | has($k)) | not) ]) as $missing
      | (if ($f.severity != "info")
           and ((((($f.cwe) // []) | length) == 0) or (((($f.owasp) // []) | length) == 0))
         then ["cwe/owasp empty for non-info finding"] else [] end) as $cweowasp
      | ($missing + $cweowasp) as $problems
      | select(($problems | length) > 0)
      | "finding[\($i)] \($f.vulnerability_class // "?")@\($f.file // "?"):\($f.line // "?") — \($problems | join("; "))"
    ] | .[]
  ' "$json" 2>/dev/null || true)
  if [ -n "$violations" ]; then
    {
      printf '  --- schema violation (%s)\n' "$json"
      printf '  %s\n' "$violations"
    } >&2
    return 1
  fi
  return 0
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose) VERBOSE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --fixture)
        [ $# -ge 2 ] || die "--fixture requires an argument"
        SINGLE_FIXTURE="$2"
        shift 2
        ;;
      --only)
        [ $# -ge 2 ] || die "--only requires an argument"
        ONLY_PREFIX="$2"
        shift 2
        ;;
      --fixtures-dir)
        [ $# -ge 2 ] || die "--fixtures-dir requires an argument"
        FIXTURES_DIR="$2"
        EXPECTED_FILE="${FIXTURES_DIR}/EXPECTED.md"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  require_cmd

  local records=()
  while IFS= read -r line; do
    [ -n "$line" ] && records+=("$line")
  done < <(parse_expected_md)

  if [ "${#records[@]}" -eq 0 ]; then
    die "no fixture expectations parsed from $EXPECTED_FILE"
  fi

  # Filter to single fixture if requested.
  if [ -n "$SINGLE_FIXTURE" ]; then
    local needle="$SINGLE_FIXTURE"
    needle="${needle#"$FIXTURES_DIR/"}"
    local filtered=()
    for r in "${records[@]}"; do
      local p="${r%%	*}"
      if [ "$p" = "$needle" ]; then
        filtered+=("$r")
      fi
    done
    if [ "${#filtered[@]}" -eq 0 ]; then
      die "fixture $SINGLE_FIXTURE not found in $EXPECTED_FILE"
    fi
    records=("${filtered[@]}")
  fi

  # Filter to a path prefix if requested (e.g. --only considerations/).
  if [ -n "$ONLY_PREFIX" ]; then
    local prefix="$ONLY_PREFIX"
    prefix="${prefix#"$FIXTURES_DIR/"}"
    local kept=()
    for r in "${records[@]}"; do
      local p="${r%%	*}"
      case "$p" in
        "$prefix"*) kept+=("$r") ;;
      esac
    done
    if [ "${#kept[@]}" -eq 0 ]; then
      die "no fixture in $EXPECTED_FILE matches --only $ONLY_PREFIX"
    fi
    records=("${kept[@]}")
  fi

  # LOG_DIR must be absolute: invoke_agent runs the CLI from inside WORK_DIR.
  # A dry run writes no logs, so it leaves LOG_DIR alone.
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$LOG_DIR"
    LOG_DIR="$(cd "$LOG_DIR" && pwd)"
  fi
  # The scratch working root is created on a dry run too, so the printed
  # invocation is the exact one a real run would use.
  local tmp_root="${TMPDIR:-/tmp}"
  WORK_DIR="$(mktemp -d "${tmp_root%/}/run_eval.XXXXXX")" || die "mktemp could not create a scratch directory"
  [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] || die "mktemp returned no scratch directory"
  trap 'rm -rf "$WORK_DIR"' EXIT
  build_codex_argv

  local total="${#records[@]}"
  printf 'TAP version 13\n'
  printf '1..%d\n' "$total"
  print_invocation
  printf '# auth: %s\n' "$AUTH_MODE"

  local n=0 fails=0
  for rec in "${records[@]}"; do
    n=$((n+1))
    IFS=$'\t' read -r path cls sev cwe owasp count <<<"$rec"
    local stem
    stem="$(sanitize_path "$path")"
    local detail
    if [ "$cls" = "__NONE__" ]; then
      detail="negative control"
    elif [ "$cls" = "__CONSIDERATIONS__" ]; then
      detail="considerations: $sev ($cwe)"
    else
      detail="$cls/$sev"
      [ "$count" -gt 1 ] && detail="$detail x$count"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      # Build the prompt anyway, so a row whose fixture or sidecar is missing
      # fails the dry run instead of the paid one.
      if build_prompt "$path" >/dev/null 2>&1; then
        printf 'ok %d - %s (%s) # SKIP dry run: no CLI call\n' "$n" "$path" "$detail"
      else
        emit_tap "$n" "not ok" "$path" "$detail (prompt could not be built)"
        fails=$((fails+1))
      fi
      continue
    fi

    local json
    if ! json="$(invoke_agent "$path" "$stem")"; then
      emit_tap "$n" "not ok" "$path" "$detail (agent invocation failed)"
      fails=$((fails+1))
      continue
    fi

    if ! validate_findings_schema "$json"; then
      emit_tap "$n" "not ok" "$path" "$detail (schema violation)"
      fails=$((fails+1))
      continue
    fi

    if compare_finding "$path" "$cls" "$sev" "$cwe" "$owasp" "$count" "$json"; then
      emit_tap "$n" "ok" "$path" "$detail"
    else
      emit_tap "$n" "not ok" "$path" "$detail"
      fails=$((fails+1))
    fi
  done

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '# dry run: %d row(s) parsed, no CLI call\n' "$total"
    [ "$fails" -eq 0 ] || exit 1
    exit 0
  fi

  local passed=$((total - fails))
  printf '# %d/%d passed\n' "$passed" "$total"
  if [ "$fails" -gt 0 ]; then
    printf '# logs/ contains raw agent output for each fixture\n'
    exit 1
  fi
  exit 0
}

main "$@"
