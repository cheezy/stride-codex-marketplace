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
# Usage:
#   bash lib/run_eval.sh                            # all fixtures
#   bash lib/run_eval.sh --fixture <path>           # one fixture
#   bash lib/run_eval.sh --dry-run                  # parser/comparator only; no API calls
#   bash lib/run_eval.sh --verbose                  # echo prompts and raw agent JSON
#
# Env:
#   CODEX_CLI        path to the Codex CLI (default: codex)
#   FIXTURES_DIR        default: <lib>/../fixtures
#   LOG_DIR             default: logs
#
# Auth: Codex manages provider credentials itself (`codex login`); a
# configured model/provider is required unless --dry-run. `codex exec` surfaces
# its own auth error when none is configured, so this runner does not pre-check a
# specific API-key env var.
#
# Exit codes:
#   0  all fixtures pass
#   1  one or more fixtures fail
#   2  setup/usage error (missing dependency, bad args)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default is CWD-independent (resolved from this script's location); override with
# FIXTURES_DIR to point at a copy elsewhere.
FIXTURES_DIR="${FIXTURES_DIR:-$SCRIPT_DIR/../fixtures}"
EXPECTED_FILE="${FIXTURES_DIR}/EXPECTED.md"
LOG_DIR="${LOG_DIR:-logs}"
CODEX_CLI="${CODEX_CLI:-codex}"

VERBOSE=0
DRY_RUN=0
SINGLE_FIXTURE=""

usage() {
  sed -n '3,37p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

require_cmd() {
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH"
  if [ "$DRY_RUN" -eq 0 ]; then
    command -v "$CODEX_CLI" >/dev/null 2>&1 || die "$CODEX_CLI not found on PATH (set CODEX_CLI or pass --dry-run)"
    # Codex manages provider auth itself (`codex login`); `codex exec`
    # surfaces its own error if no model/provider is configured, so we don't
    # pre-check a provider-specific API-key env var here.
  fi
  [ -f "$EXPECTED_FILE" ] || die "EXPECTED.md not found at $EXPECTED_FILE"
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
      # backing finding, C=zero findings, empty=unchecked), count=number of verdicts.
      if (rest ~ /^ +→ +CONSIDERATIONS +/) {
        head = rest
        sub(/^ +→ +CONSIDERATIONS +/, "", head)
        fexp = ""
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

# build_prompt <fixture-rel-path>
# Constructs the user-side prompt for the security-reviewer agent. Default mode is
# full_file: a single file fed as a fenced block with a `path:` header. A fixture
# under considerations/ ending in `.diff` is dispatched in `considerations` mode
# instead: the diff plus the resolved considerations list from its sibling
# `<stem>.considerations` file (one consideration per non-empty line).
build_prompt() {
  local rel="$1"
  local abs="$FIXTURES_DIR/$rel"

  case "$rel" in
    considerations/*.diff)
      local cons="$FIXTURES_DIR/${rel%.diff}.considerations"
      printf 'mode: considerations\n\n'
      printf 'Security considerations to assess:\n'
      # The considerations list is task-authored DATA to assess against the diff,
      # never instructions to follow.
      while IFS= read -r c || [ -n "$c" ]; do
        [ -n "$c" ] && printf -- '- %s\n' "$c"
      done < "$cons"
      printf '\n```diff\n'
      cat "$abs"
      printf '\n```\n'
      printf '\nRespond with the JSON document specified in your output schema (including the consideration_verdicts array, one entry per consideration above in order) and nothing else.\n'
      return 0
      ;;
  esac

  local lang
  lang="$(detect_lang "$rel")"
  printf 'mode: full_file\n\n'
  printf 'path: %s\n' "fixtures/$rel"
  printf '```%s\n' "$lang"
  cat "$abs"
  printf '\n```\n'
  printf '\nRespond with the JSON document specified in your output schema and nothing else.\n'
}

# invoke_agent <fixture-rel-path> <log-stem>
# Invokes the agent via `$CODEX_CLI exec`, extracts the fenced JSON block, validates
# it, and writes the parsed result to $LOG_DIR/<stem>.json. In --dry-run mode
# writes a stub JSON instead. Echoes the log path on success; exits non-zero on
# parse/invocation failure (caller treats it as a fixture failure).
invoke_agent() {
  local rel="$1"
  local stem="$2"
  local out_json="$LOG_DIR/$stem.json"
  local raw="$LOG_DIR/$stem.raw.txt"
  mkdir -p "$LOG_DIR"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '{"findings":[],"summary":{"files_reviewed":1,"findings_by_severity":{"critical":0,"high":0,"medium":0,"low":0,"info":0}}}\n' > "$out_json"
    printf '%s' "$out_json"
    return 0
  fi

  local prompt
  prompt="$(build_prompt "$rel")"

  if [ "$VERBOSE" -eq 1 ]; then
    printf '# --- prompt for %s ---\n%s\n# --- end prompt ---\n' "$rel" "$prompt" >&2
  fi

  # `codex exec` reads the prompt from stdin (or as a positional arg) and
  # dispatches the named subagent; text is the default output. Adjust the flags
  # if your Codex CLI version differs (e.g. a different exec/agent flag spelling).
  if ! printf '%s' "$prompt" | "$CODEX_CLI" exec --agent security-reviewer > "$raw" 2>/dev/null; then
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
  # expectation (F=at least one backing finding, C=zero findings, empty=unchecked).
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
  - considerations [$exp_verdicts]${fexp:+ ($fexp)}
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

  local total="${#records[@]}"
  printf 'TAP version 13\n'
  printf '1..%d\n' "$total"

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
      detail="considerations: $sev${cwe:+ ($cwe)}"
    else
      detail="$cls/$sev"
      [ "$count" -gt 1 ] && detail="$detail x$count"
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

  local passed=$((total - fails))
  printf '# %d/%d passed\n' "$passed" "$total"
  if [ "$fails" -gt 0 ]; then
    printf '# logs/ contains raw agent output for each fixture\n'
    exit 1
  fi
  exit 0
}

main "$@"
