#!/usr/bin/env bash
#
# run_transform_tests.sh — golden-file + spec-assertion tests for the
# deterministic transforms in lib/sarif_transform.sh.
#
# The transforms (fingerprint, SARIF mapping, dedup, fail-on with its verdict
# gate, baseline suppression that keeps backing findings) are specified in
# prose in skills/stride-security-review/SKILL.md (the /security-review
# command-skill) and have no other executable source of truth. This runner
# locks their behavior two ways:
#   1. Golden diffs — sarif_transform.sh output vs committed fixtures/golden/*.
#   2. Explicit spec assertions — exact values from the prose contract
#      (fingerprint preimage, severity->level/security-severity table, dedup key,
#      fail-on counting, the verdict gate, the baseline rule for a finding that
#      backs a verdict, one findings document in, verdict i answering
#      consideration i) so a golden that drifts WITH the implementation can't
#      hide a spec violation. A guard self-test deletes each input and position
#      guard from a copy of the script and checks the bad input then gets
#      through, so the assertions are proven to catch a deleted guard.
#
# Pure: no network, no agent CLI, no provider API key. Only jq + a SHA-256
# utility are needed, so it runs cheaply in CI on every push.
#
# Output is TAP version 13. Exit 0 only when every check passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XFORM="$SCRIPT_DIR/sarif_transform.sh"
GOLDEN_DIR="$ROOT_DIR/fixtures/golden"
INPUT="$GOLDEN_DIR/input_findings.json"
# The version source of truth is the `version` key of the Codex plugin manifest.
# Mirror sarif_transform.sh's reader.
PLUGIN_JSON="$ROOT_DIR/.codex-plugin/plugin.json"

# The precomputed SHA-256 of the spec preimage for input_findings.json finding[0]:
#   injection|lib/users.py|42|<first 80 chars of description>
# Computed independently and pinned here so the fingerprint algorithm itself is
# locked, not just self-consistent with the implementation.
EXPECTED_FP0="572a40cc1e8fdb62e2974d1d29b83e9aad7e1631386db9878e6ffb14c379bef2"

command -v jq >/dev/null 2>&1 || { printf 'error: jq not found\n' >&2; exit 2; }

N=0
FAILS=0
plan_printed=0

ok()      { N=$((N+1)); printf 'ok %d - %s\n' "$N" "$1"; }
not_ok()  { N=$((N+1)); FAILS=$((FAILS+1)); printf 'not ok %d - %s\n' "$N" "$1"
            [ -n "${2:-}" ] && printf '  # %s\n' "$2" || true; }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected [$2] got [$3]"; fi
}

# assert_golden <label> <golden-file> <actual-file>
assert_golden() {
  if diff -u "$2" "$3" >/dev/null 2>&1; then
    ok "$1"
  else
    not_ok "$1" "output differs from golden $2"
    diff -u "$2" "$3" | sed 's/^/  # /' >&2 || true
  fi
}

main() {
  printf 'TAP version 13\n'

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # ---- fingerprint -------------------------------------------------------
  bash "$XFORM" fingerprint "$INPUT" > "$tmp/fp.out"
  assert_golden "fingerprint: output matches golden" "$GOLDEN_DIR/fingerprint.golden" "$tmp/fp.out"
  assert_eq "fingerprint: finding[0] equals precomputed SHA-256" "$EXPECTED_FP0" "$(head -1 "$tmp/fp.out")"

  # Independent re-derivation: hash the spec preimage ourselves and compare.
  local sha
  if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum | cut -d' ' -f1; }
  else sha() { shasum -a 256 | cut -d' ' -f1; }; fi
  local preimage rederived
  preimage="$(jq -rj '.findings[0] | .vulnerability_class + "|" + .file + "|" + (.line|tostring) + "|" + (.description[0:80])' "$INPUT")"
  rederived="$(printf '%s' "$preimage" | sha)"
  assert_eq "fingerprint: spec preimage hashes to the same value" "$EXPECTED_FP0" "$rederived"

  # ---- SARIF severity -> level / security-severity table -----------------
  bash "$XFORM" sarif "$INPUT" > "$tmp/sarif.out"
  # Pull (severity -> level/score) straight from the generated SARIF by joining
  # results back to the input severities by index.
  local pairs
  pairs="$(paste -d'|' \
    <(jq -r '.findings[].severity' "$INPUT") \
    <(jq -r '.runs[0].results[] | "\(.level) \(.properties["security-severity"])"' "$tmp/sarif.out"))"
  assert_eq "sarif: critical -> error/9.0" "critical|error 9.0" "$(echo "$pairs" | sed -n '1p')"
  assert_eq "sarif: high -> error/7.0"     "high|error 7.0"     "$(echo "$pairs" | sed -n '3p')"
  assert_eq "sarif: medium -> warning/5.0" "medium|warning 5.0" "$(echo "$pairs" | sed -n '4p')"
  assert_eq "sarif: info -> note/1.0"      "info|note 1.0"      "$(echo "$pairs" | sed -n '5p')"
  # low is not in input_findings.json; assert it directly via a one-off finding.
  echo '{"findings":[{"severity":"low","file":"a","line":1,"vulnerability_class":"insecure_config","cwe":[],"owasp":[],"description":"d","remediation":"r","confidence":"low"}]}' > "$tmp/low.json"
  assert_eq "sarif: low -> note/3.0" "note 3.0" \
    "$(bash "$XFORM" sarif "$tmp/low.json" | jq -r '.runs[0].results[0] | "\(.level) \(.properties["security-severity"])"')"

  # ---- SARIF golden (driver.version normalized) + driver.version wiring ----
  jq '.runs[0].tool.driver.version="PLUGIN_VERSION"' "$tmp/sarif.out" > "$tmp/sarif.norm.json"
  assert_golden "sarif: document matches golden (version-normalized)" "$GOLDEN_DIR/sarif.golden.json" "$tmp/sarif.norm.json"
  assert_eq "sarif: driver.version tracks plugin.json" \
    "$(jq -r '.version' "$PLUGIN_JSON")" \
    "$(jq -r '.runs[0].tool.driver.version' "$tmp/sarif.out")"
  assert_eq "sarif: spec version stays 2.1.0" "2.1.0" "$(jq -r '.version' "$tmp/sarif.out")"

  # ---- dedup --------------------------------------------------------------
  bash "$XFORM" dedup "$INPUT" | jq -S . > "$tmp/dedup.out"
  assert_golden "dedup: output matches golden" "$GOLDEN_DIR/dedup.golden.json" "$tmp/dedup.out"
  assert_eq "dedup: duplicate (file,line,class) collapses to one" "4" \
    "$(jq '.findings | length' "$tmp/dedup.out")"
  echo '{"findings":[{"file":"a","line":1,"vulnerability_class":"x"},{"file":"a","line":2,"vulnerability_class":"x"},{"file":"a","line":1,"vulnerability_class":"x"}]}' > "$tmp/dd.json"
  assert_eq "dedup: differing line stays two" "a:1 a:2" \
    "$(bash "$XFORM" dedup "$tmp/dd.json" | jq -r '[.findings[] | "\(.file):\(.line)"] | join(" ")')"

  # ---- fail-on counting ---------------------------------------------------
  assert_eq "failon: critical counts critical only" "2" "$(bash "$XFORM" failon critical "$INPUT" || true)"
  assert_eq "failon: high counts critical+high"      "3" "$(bash "$XFORM" failon high "$INPUT" || true)"
  assert_eq "failon: medium counts crit+high+medium" "4" "$(bash "$XFORM" failon medium "$INPUT" || true)"
  assert_eq "failon: low counts everything but info"  "4" "$(bash "$XFORM" failon low "$INPUT" || true)"

  # info-only input must trip nothing (count 0, exit 0).
  echo '{"findings":[{"severity":"info","file":"a","line":1,"vulnerability_class":"insecure_config","cwe":[],"owasp":[],"description":"d","remediation":"r","confidence":"low"}]}' > "$tmp/info.json"
  local info_exit
  assert_eq "failon: info-only trips no threshold (count 0)" "0" "$(bash "$XFORM" failon low "$tmp/info.json" || true)"
  if bash "$XFORM" failon low "$tmp/info.json" >/dev/null 2>&1; then info_exit=0; else info_exit=1; fi
  assert_eq "failon: info-only exits 0" "0" "$info_exit"
  # And a tripped threshold exits non-zero.
  if bash "$XFORM" failon critical "$INPUT" >/dev/null 2>&1; then info_exit=0; else info_exit=1; fi
  assert_eq "failon: tripped threshold exits non-zero" "1" "$info_exit"

  # ---- fail-on: considerations verdicts (W2279) ---------------------------
  # exit_of <cmd...> — prints 0 or 1 for the command's success/failure.
  exit_of() { if "$@" >/dev/null 2>&1; then printf '0'; else printf '1'; fi; }
  local v_unm v_mit
  v_unm='{"consideration":"c1","status":"unmitigated","evidence":"a.py:15-16","note":"n"}'
  v_mit='{"consideration":"c2","status":"mitigated","evidence":"c.py:9","note":"n"}'

  echo "{\"findings\":[],\"consideration_verdicts\":[$v_unm]}" > "$tmp/v_nofind.json"
  assert_eq "failon: unmitigated verdict with zero findings counts 1" "1" "$(bash "$XFORM" failon low "$tmp/v_nofind.json" 1 || true)"
  assert_eq "failon: unmitigated verdict with zero findings exits 1" "1" "$(exit_of bash "$XFORM" failon low "$tmp/v_nofind.json" 1)"

  echo "{\"findings\":[{\"severity\":\"low\",\"file\":\"a.py\",\"line\":16,\"vulnerability_class\":\"x\",\"description\":\"d\"}],\"consideration_verdicts\":[$v_unm]}" > "$tmp/v_low.json"
  assert_eq "failon: unmitigated verdict backed by a low finding trips --fail-on high" "1" "$(exit_of bash "$XFORM" failon high "$tmp/v_low.json" 1)"
  assert_eq "failon: unmitigated verdict trips --fail-on critical too" "1" "$(exit_of bash "$XFORM" failon critical "$tmp/v_low.json")"

  echo "{\"findings\":[{\"severity\":\"high\",\"file\":\"c.py\",\"line\":9,\"vulnerability_class\":\"z\",\"description\":\"f\"}],\"consideration_verdicts\":[$v_mit]}" > "$tmp/v_mit.json"
  assert_eq "failon: all mitigated + high finding passes --fail-on critical" "0" "$(bash "$XFORM" failon critical "$tmp/v_mit.json" 1 || true)"
  assert_eq "failon: all mitigated + high finding exits 0 under --fail-on critical" "0" "$(exit_of bash "$XFORM" failon critical "$tmp/v_mit.json" 1)"
  assert_eq "failon: all mitigated + high finding trips --fail-on high" "1" "$(bash "$XFORM" failon high "$tmp/v_mit.json" 1 || true)"

  echo '{"findings":[{"severity":"low","file":"a.py","line":16,"vulnerability_class":"x","description":"d"}],"consideration_verdicts":[{"consideration":"c","status":"partial","evidence":"a.py:16","note":"n"}]}' > "$tmp/v_part.json"
  assert_eq "failon: backed partial is gated by its finding's severity" "0" "$(bash "$XFORM" failon high "$tmp/v_part.json" 1 || true)"
  echo '{"findings":[{"severity":"low","file":"a.py","line":16,"vulnerability_class":"x","description":"d"}],"consideration_verdicts":[{"consideration":"c","status":"partial","evidence":"see note","note":"n"}]}' > "$tmp/v_part_unbacked.json"
  assert_eq "failon: partial that no finding backs fails closed" "1" "$(bash "$XFORM" failon high "$tmp/v_part_unbacked.json" 1 || true)"

  # W2282: a partial the considerations-mode tool budget left unverified carries
  # a `budget reached:` note and evidence with no file:line, and no finding backs
  # it — so it trips even the loosest threshold, with no findings or with an
  # unrelated info finding beside it.
  echo '{"findings":[],"consideration_verdicts":[{"consideration":"c","status":"partial","evidence":"not verified within the tool budget","note":"budget reached: the session store config was not read"}]}' > "$tmp/v_budget.json"
  assert_eq "failon: a budget-reached partial with no findings trips --fail-on critical" "1" "$(exit_of bash "$XFORM" failon critical "$tmp/v_budget.json" 1)"
  echo '{"findings":[{"severity":"info","file":"a.py","line":16,"vulnerability_class":"x","description":"d"}],"consideration_verdicts":[{"consideration":"c","status":"partial","evidence":"not verified within the tool budget","note":"budget reached: the caller of a.py was not read"}]}' > "$tmp/v_budget_info.json"
  assert_eq "failon: an info finding beside a budget-reached partial does not back it" "1" "$(bash "$XFORM" failon critical "$tmp/v_budget_info.json" 1 || true)"

  echo '{"findings":[]}' > "$tmp/v_missing.json"
  assert_eq "failon: missing verdicts in considerations mode fail closed" "1" "$(bash "$XFORM" failon critical "$tmp/v_missing.json" 1 || true)"
  echo '{"findings":[],"consideration_verdicts":[]}' > "$tmp/v_short.json"
  assert_eq "failon: short verdicts array fails closed" "1" "$(bash "$XFORM" failon critical "$tmp/v_short.json" 1 || true)"
  echo '{"findings":[],"consideration_verdicts":[{"consideration":"c","status":"not_applicable","evidence":"x","note":"n"}]}' > "$tmp/v_badstatus.json"
  assert_eq "failon: status outside the enum fails closed" "1" "$(bash "$XFORM" failon critical "$tmp/v_badstatus.json" 1 || true)"
  assert_eq "failon: legacy document without n is unchanged by the verdict rule" "2" "$(bash "$XFORM" failon critical "$INPUT" || true)"

  # Empty considerations: the command refuses an empty list (exit 2, Step 1), so
  # an n_considerations below 1 is a usage error here too, never a passing gate.
  local n0_rc
  set +e; bash "$XFORM" failon critical "$tmp/v_nofind.json" 0 >/dev/null 2>&1; n0_rc=$?; set -e
  assert_eq "failon: an empty considerations count is a usage error (exit 2)" "2" "$n0_rc"
  set +e; bash "$XFORM" suppress "$tmp/v_nofind.json" "$tmp/v_nofind.json" 0 >/dev/null 2>&1; n0_rc=$?; set -e
  assert_eq "suppress: an empty considerations count is a usage error (exit 2)" "2" "$n0_rc"

  # ---- baseline suppression keeps backing findings (W2279) ---------------
  # A: low a.py:16 backs the unmitigated verdict (evidence a.py:15-16)
  # B: medium b.py:3 backs nothing
  # C: high c.py:9 is named only by a mitigated verdict, which protects nothing
  local finds
  finds='[{"severity":"low","file":"a.py","line":16,"vulnerability_class":"x","description":"d"},{"severity":"medium","file":"b.py","line":3,"vulnerability_class":"y","description":"e"},{"severity":"high","file":"c.py","line":9,"vulnerability_class":"z","description":"f"}]'
  echo "{\"findings\":$finds,\"summary\":{\"files_reviewed\":3},\"consideration_verdicts\":[$v_unm,$v_mit]}" > "$tmp/s_doc.json"
  bash "$XFORM" fingerprint "$tmp/s_doc.json" > "$tmp/s_fp.txt"
  jq -R . "$tmp/s_fp.txt" > "$tmp/s_fp.lines"
  jq -s '{schema_version:1,generated_at:"2026-01-01T00:00:00Z",acknowledged:map({fingerprint:.})}' "$tmp/s_fp.lines" > "$tmp/s_base.json"
  bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/s_doc.json" 2 > "$tmp/s_out.json"
  assert_eq "suppress: a finding that backs a verdict is never suppressed" "a.py:16" \
    "$(jq -r '[.findings[] | "\(.file):\(.line)"] | join(" ")' "$tmp/s_out.json")"
  assert_eq "suppress: non-backing and mitigated-only findings are still suppressed" "2" \
    "$(jq -r '.summary.suppressed_count' "$tmp/s_out.json")"
  assert_eq "suppress: severity counts recomputed after suppression" "0 0 0 1 0" \
    "$(jq -r '.summary.findings_by_severity | "\(.critical) \(.high) \(.medium) \(.low) \(.info)"' "$tmp/s_out.json")"

  echo "{\"findings\":$finds,\"consideration_verdicts\":[{\"consideration\":\"c1\",\"status\":\"unmitigated\",\"evidence\":\"see note\",\"note\":\"n\"}]}" > "$tmp/s_unres.json"
  assert_eq "suppress: an open verdict nothing backs protects every finding" "3 0" \
    "$(bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/s_unres.json" 1 | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  echo "{\"findings\":$finds}" > "$tmp/s_legacy.json"
  assert_eq "suppress: without considerations every acknowledged finding is dropped" "0 3" \
    "$(bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/s_legacy.json" | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  assert_eq "suppress: missing verdicts in considerations mode protect every finding" "3 0" \
    "$(bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/s_legacy.json" 1 | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  echo '{"schema_version":2,"acknowledged":[]}' > "$tmp/s_bad_base.json"
  assert_eq "suppress: malformed baseline leaves the document unchanged" "3 null" \
    "$(bash "$XFORM" suppress "$tmp/s_bad_base.json" "$tmp/s_legacy.json" 2>/dev/null | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"

  # ---- one findings document in, or exit 2 -------------------------------
  # An empty file (a crashed or truncated dispatch) and two documents run
  # together are bad input, never a gate that reads zero and passes.
  # rc_of <cmd...> — prints the command's exit code.
  rc_of() { local rc; set +e; "$@" >/dev/null 2>&1; rc=$?; set -e; printf '%s' "$rc"; }
  : > "$tmp/d_empty.json"
  cat "$tmp/v_missing.json" "$tmp/v_missing.json" > "$tmp/d_two.json"
  echo '[]' > "$tmp/d_array.json"
  echo '{"findings":"none"}' > "$tmp/d_strfind.json"
  echo '{"findings":null}' > "$tmp/d_nullfind.json"
  assert_eq "failon: an empty findings file is bad input (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/d_empty.json" 1)"
  assert_eq "failon: two documents run together are bad input (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/d_two.json" 1)"
  assert_eq "failon: a document that is not an object is bad input (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/d_array.json")"
  assert_eq "failon: findings that are not an array are bad input (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/d_strfind.json")"
  assert_eq "failon: null findings are bad input, not zero findings (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/d_nullfind.json")"
  assert_eq "suppress: null findings are bad input (exit 2)" "2" "$(rc_of bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/d_nullfind.json")"
  assert_eq "suppress: two documents run together are bad input (exit 2)" "2" "$(rc_of bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/d_two.json" 1)"
  assert_eq "suppress: two documents are bad input under a malformed baseline too (exit 2)" "2" "$(rc_of bash "$XFORM" suppress "$tmp/s_bad_base.json" "$tmp/d_two.json" 1)"

  # ---- verdict i answers consideration i ----------------------------------
  # With the resolved considerations as a file, a same-length array that
  # repeats one verdict and drops another is malformed: it fails the gate and
  # protects every finding from the baseline. A count alone checks length only.
  printf 'c1\n\n  \nc2\r\n' > "$tmp/p_list.txt"
  local p1 p2
  p1='{"consideration":"c1","status":"mitigated","evidence":"a.py:1","note":"n"}'
  p2='{"consideration":"c2","status":"mitigated","evidence":"a.py:2","note":"n"}'
  echo "{\"findings\":[],\"consideration_verdicts\":[$p1,$p2]}" > "$tmp/p_ok.json"
  echo "{\"findings\":[],\"consideration_verdicts\":[$p1,$p1]}" > "$tmp/p_dup.json"
  echo "{\"findings\":[],\"consideration_verdicts\":[$p2,$p1]}" > "$tmp/p_swap.json"
  echo "{\"findings\":[],\"consideration_verdicts\":[{\"consideration\":\"[REDACTED — row text embedded a credential]\",\"status\":\"mitigated\",\"evidence\":\"a.py:1\",\"note\":\"n\"},$p2]}" > "$tmp/p_red.json"
  echo "{\"findings\":$finds,\"consideration_verdicts\":[$p1,$p1]}" > "$tmp/p_sdup.json"
  assert_eq "failon: verdicts that answer the list in order pass" "0" "$(rc_of bash "$XFORM" failon critical "$tmp/p_ok.json" "$tmp/p_list.txt")"
  assert_eq "failon: a repeated verdict that drops a consideration fails closed" "1" "$(bash "$XFORM" failon critical "$tmp/p_dup.json" "$tmp/p_list.txt" || true)"
  assert_eq "failon: verdicts in the wrong order fail closed" "1" "$(rc_of bash "$XFORM" failon critical "$tmp/p_swap.json" "$tmp/p_list.txt")"
  assert_eq "failon: the redaction sentinel answers its own position" "0" "$(rc_of bash "$XFORM" failon critical "$tmp/p_red.json" "$tmp/p_list.txt")"
  assert_eq "failon: a count alone does not see the repeat" "0" "$(rc_of bash "$XFORM" failon critical "$tmp/p_dup.json" 2)"
  assert_eq "suppress: a repeated verdict protects every finding" "3 0" \
    "$(bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/p_sdup.json" "$tmp/p_list.txt" | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  : > "$tmp/p_empty.txt"
  assert_eq "failon: an empty considerations file is a usage error (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/p_ok.json" "$tmp/p_empty.txt")"
  assert_eq "failon: a considerations argument that is no file is a usage error (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/p_ok.json" "$tmp/no-such-list.txt")"
  # The third argument never silently weakens the gate: present but empty, the
  # literal word null with no such file, or all digits while a file of that name
  # exists are refused, not read as "no considerations" or as a bare count.
  mkdir -p "$tmp/p_dir"
  cp "$tmp/p_list.txt" "$tmp/p_dir/2"
  assert_eq "failon: an empty considerations argument is a usage error (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/v_missing.json" "")"
  assert_eq "suppress: an empty considerations argument is a usage error (exit 2)" "2" "$(rc_of bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/s_legacy.json" "")"
  assert_eq "failon: the word null is not a way to omit the considerations (exit 2)" "2" "$(cd "$tmp/p_dir" && rc_of bash "$XFORM" failon critical "$tmp/v_missing.json" null)"
  assert_eq "failon: a count that also names a file is refused (exit 2)" "2" "$(cd "$tmp/p_dir" && rc_of bash "$XFORM" failon critical "$tmp/p_dup.json" 2)"
  assert_eq "failon: the same file passed as a path gets the position check" "1" "$(cd "$tmp/p_dir" && rc_of bash "$XFORM" failon critical "$tmp/p_dup.json" ./2)"

  # ---- inputs upstream does not exercise (codex port, W2645) -------------
  # Each gives a guard or a fail-closed term below an input that reaches it:
  # a null document (the one input that gets past the findings clause to the
  # object check), a fourth argument, a verdicts value that is present but not
  # an array, a status outside the enum under suppress, a zero count beside an
  # empty verdicts array, and an unrelated or out-of-range finding beside an
  # unbacked partial.
  echo null > "$tmp/d_null.json"
  assert_eq "failon: a null document is bad input (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/d_null.json")"
  assert_eq "failon: a fourth argument is a usage error (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/v_missing.json" 1 extra)"
  assert_eq "suppress: a fourth argument is a usage error (exit 2)" "2" "$(rc_of bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/s_legacy.json" 1 extra)"
  echo '{"findings":[],"consideration_verdicts":"none"}' > "$tmp/v_notarray.json"
  assert_eq "failon: verdicts present but not an array trip without a count" "1" "$(bash "$XFORM" failon critical "$tmp/v_notarray.json" || true)"
  echo "{\"findings\":$finds,\"consideration_verdicts\":[{\"consideration\":\"c1\",\"status\":\"not_applicable\",\"evidence\":\"a.py:16\",\"note\":\"n\"}]}" > "$tmp/s_badstatus.json"
  assert_eq "suppress: a status outside the enum protects every finding" "3 0" \
    "$(bash "$XFORM" suppress "$tmp/s_base.json" "$tmp/s_badstatus.json" 1 | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  assert_eq "failon: a count of 0 is refused even beside an empty verdicts array (exit 2)" "2" "$(rc_of bash "$XFORM" failon critical "$tmp/v_short.json" 0)"
  echo '{"findings":[{"severity":"info","file":"a.py","line":16,"vulnerability_class":"x","description":"d"}],"consideration_verdicts":[{"consideration":"c","status":"partial","evidence":"see note","note":"n"}]}' > "$tmp/v_part_info.json"
  assert_eq "failon: an info finding beside an unbacked partial does not back it" "1" "$(rc_of bash "$XFORM" failon critical "$tmp/v_part_info.json" 1)"
  echo '{"findings":[{"severity":"low","file":"a.py","line":16,"vulnerability_class":"x","description":"d"}],"consideration_verdicts":[{"consideration":"c","status":"partial","evidence":"a.py:10-12","note":"n"}]}' > "$tmp/v_part_range.json"
  assert_eq "failon: a finding past the end of the cited range does not back the partial" "1" "$(rc_of bash "$XFORM" failon high "$tmp/v_part_range.json" 1)"

  # ---- guard self-test ----------------------------------------------------
  # Each guard is removed from a copy of the script, and the input it exists
  # for must then get through. This proves the assertions above bite: deleting
  # a guard from sarif_transform.sh fails them rather than passing unnoticed.
  # mutant <name> <sed-script> — writes $tmp/<name>.sh; fails if nothing changed.
  mutant() {
    sed "$2" "$XFORM" > "$tmp/$1.sh"
    if cmp -s "$XFORM" "$tmp/$1.sh"; then not_ok "guard self-test: the $1 mutation took effect" "sed changed nothing"
    else ok "guard self-test: the $1 mutation took effect"; fi
  }
  mutant no-one-document '/^  one_document "\$input"$/d'
  assert_eq "guard self-test: without one_document, suppress passes two documents" "0" \
    "$(rc_of bash "$tmp/no-one-document.sh" suppress "$tmp/s_bad_base.json" "$tmp/d_two.json" 1)"
  mutant no-input-guards '/^  one_document "\$input"$/d; /failon could not compute N_GATE/d'
  assert_eq "guard self-test: without both input guards, failon passes an empty file" "0" \
    "$(rc_of bash "$tmp/no-input-guards.sh" failon critical "$tmp/d_empty.json" 1)"
  mutant no-position-check 's/^       elif misplaced then 1$/       elif false then 1/'
  assert_eq "guard self-test: without the position check, failon passes a repeated verdict" "0" \
    "$(rc_of bash "$tmp/no-position-check.sh" failon critical "$tmp/p_dup.json" "$tmp/p_list.txt")"

  # ---- guard self-test, extended (codex port, W2645) ---------------------
  # Upstream's three mutants above cover one_document, the N_GATE integer check
  # and the position check. These cover every other input guard, the three
  # refusals 6ca7233 added, and each fail-closed verdict term, so deleting any
  # of them from sarif_transform.sh fails a case here.
  # Not covered by a mutant, because no exit code can show them: the readable-
  # file check (jq's own read failure exits 2 without it), check_n's non-integer
  # arm (considerations_arg only hands it digits), and the length-1 clause for
  # an empty file (the object check refuses an empty slurp too).
  mutant no-object-check 's/ and (\.\[0\] | type) == "object"$//'
  assert_eq "guard self-test: without the object check, failon passes a null document" "0" \
    "$(rc_of bash "$tmp/no-object-check.sh" failon critical "$tmp/d_null.json")"
  mutant no-single-document 's/^\(  jq -se .\)length == 1 and /\1/'
  assert_eq "guard self-test: without the one-document clause, suppress passes two documents" "0" \
    "$(rc_of bash "$tmp/no-single-document.sh" suppress "$tmp/s_bad_base.json" "$tmp/d_two.json" 1)"
  mutant no-findings-array 's/(\.\[0\]\.findings | type) == "array"/true/'
  assert_eq "guard self-test: without the findings-array refusal, failon passes null findings" "0" \
    "$(rc_of bash "$tmp/no-findings-array.sh" failon critical "$tmp/d_nullfind.json")"
  # Deleting the empty-argument arm alone shows nothing, since check_n refuses
  # an empty value too; the mutant restores the pre-6ca7233 reading instead,
  # an empty third argument taken as no considerations at all.
  mutant empty-arg-omitted "s/^    '') die \"considerations argument is empty.*\$/    '') return 0 ;;/"
  assert_eq "guard self-test: reading an empty argument as omitted lets failon pass missing verdicts" "0" \
    "$(rc_of bash "$tmp/empty-arg-omitted.sh" failon critical "$tmp/v_missing.json" "")"
  mutant no-count-file-clash '/is both a count and a file name/d'
  assert_eq "guard self-test: without the count-and-file refusal, failon passes a repeated verdict" "0" \
    "$(cd "$tmp/p_dir" && rc_of bash "$tmp/no-count-file-clash.sh" failon critical "$tmp/p_dup.json" 2)"
  mutant no-count-minimum '/^  \[ "\$1" -ge 1 \] || die/d'
  assert_eq "guard self-test: without the count minimum, failon passes a count of 0" "0" \
    "$(rc_of bash "$tmp/no-count-minimum.sh" failon critical "$tmp/v_short.json" 0)"
  mutant no-list-minimum 's/^      \[ "\$N" -ge 1 \] || die "considerations file lists no consideration: \$1" ;;$/      ;;/; /^  \[ "\$1" -ge 1 \] || die/d'
  assert_eq "guard self-test: without both minimums, failon passes an empty considerations file" "0" \
    "$(rc_of bash "$tmp/no-list-minimum.sh" failon critical "$tmp/v_short.json" "$tmp/p_empty.txt")"
  mutant failon-arg-count 's/^    failon)      { \[ \$# -eq 2 \] || \[ \$# -eq 3 \]; } || die .*$/    failon)/'
  assert_eq "guard self-test: without its argument count, failon skips the verdict check on a fourth argument" "0" \
    "$(rc_of bash "$tmp/failon-arg-count.sh" failon critical "$tmp/v_missing.json" 1 extra)"
  mutant suppress-arg-count 's/^    suppress)    { \[ \$# -eq 2 \] || \[ \$# -eq 3 \]; } || die .*$/    suppress)/'
  assert_eq "guard self-test: without its argument count, suppress drops findings on a fourth argument" "0 3" \
    "$(bash "$tmp/suppress-arg-count.sh" suppress "$tmp/s_base.json" "$tmp/s_legacy.json" 1 extra | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  mutant no-unmitigated-term '/^      + (\[ verdicts\[] | select(vstatus == "unmitigated") ] | length)$/d'
  assert_eq "guard self-test: without the unmitigated term, failon passes an unmitigated verdict" "0" \
    "$(rc_of bash "$tmp/no-unmitigated-term.sh" failon low "$tmp/v_nofind.json" 1)"
  mutant no-unbacked-term '/select(vstatus == "partial") | select(\. as \$v | \$doc | unbacked(\$v))/d'
  assert_eq "guard self-test: without the unbacked term, failon passes an unbacked partial" "0" \
    "$(rc_of bash "$tmp/no-unbacked-term.sh" failon high "$tmp/v_part_unbacked.json" 1)"
  mutant no-bad-status-term '/^      + (bad_status | length)$/d'
  assert_eq "guard self-test: without the bad-status term, failon passes a status outside the enum" "0" \
    "$(rc_of bash "$tmp/no-bad-status-term.sh" failon critical "$tmp/v_badstatus.json" 1)"
  mutant no-length-check 's/^          or (\.consideration_verdicts | length) != \$n then 1$/          then 1/'
  assert_eq "guard self-test: without the length check, failon passes a short verdicts array" "0" \
    "$(rc_of bash "$tmp/no-length-check.sh" failon critical "$tmp/v_short.json" 1)"
  mutant no-type-check-without-count 's/^      (if has("consideration_verdicts")$/      (if false/'
  assert_eq "guard self-test: without the countless type check, failon passes non-array verdicts" "0" \
    "$(rc_of bash "$tmp/no-type-check-without-count.sh" failon critical "$tmp/v_notarray.json")"
  mutant no-malformed-term '/^      + malformed$/d'
  assert_eq "guard self-test: without the malformed term, failon passes missing verdicts" "0" \
    "$(rc_of bash "$tmp/no-malformed-term.sh" failon critical "$tmp/v_missing.json" 1)"
  mutant suppress-drops-backing 's/and (any(\$open\[]; backs(\$f; \.)) | not)) }/) }/'
  assert_eq "guard self-test: without the backing rule, suppress drops a backing finding" "0 3" \
    "$(bash "$tmp/suppress-drops-backing.sh" suppress "$tmp/s_base.json" "$tmp/s_doc.json" 2 | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  mutant suppress-ignores-unbacked 's/^    | ( (open | any(\.\[]; \. as \$v | \$doc | unbacked(\$v)))$/    | ( false/'
  assert_eq "guard self-test: without the unbacked protection, suppress drops every finding" "0 3" \
    "$(bash "$tmp/suppress-ignores-unbacked.sh" suppress "$tmp/s_base.json" "$tmp/s_unres.json" 1 | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  mutant suppress-ignores-bad-status '/^        or ((bad_status | length) > 0)$/d'
  assert_eq "guard self-test: without the bad-status protection, suppress drops every finding" "0 3" \
    "$(bash "$tmp/suppress-ignores-bad-status.sh" suppress "$tmp/s_base.json" "$tmp/s_badstatus.json" 1 | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"
  mutant suppress-ignores-malformed 's/^        or (malformed > 0) ) as \$protect_all$/        ) as $protect_all/'
  assert_eq "guard self-test: without the malformed protection, suppress drops every finding" "0 3" \
    "$(bash "$tmp/suppress-ignores-malformed.sh" suppress "$tmp/s_base.json" "$tmp/s_legacy.json" 1 | jq -r '"\(.findings | length) \(.summary.suppressed_count)"')"

  # ---- corruption self-test ----------------------------------------------
  # A deliberately corrupted golden MUST be detected (assert_golden returns
  # non-zero / the diff is non-empty). This proves the runner actually fails on
  # mismatch rather than rubber-stamping.
  cp "$GOLDEN_DIR/fingerprint.golden" "$tmp/corrupt.golden"
  printf 'deadbeef\n' >> "$tmp/corrupt.golden"
  if diff -u "$tmp/corrupt.golden" "$tmp/fp.out" >/dev/null 2>&1; then
    not_ok "corruption self-test: corrupted golden is detected" "diff did not flag the corruption"
  else
    ok "corruption self-test: corrupted golden is detected"
  fi

  printf '1..%d\n' "$N"
  if [ "$FAILS" -gt 0 ]; then
    printf '# %d/%d checks failed\n' "$FAILS" "$N"
    exit 1
  fi
  printf '# all %d checks passed\n' "$N"
  exit 0
}

main "$@"
