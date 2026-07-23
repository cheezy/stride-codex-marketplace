#!/usr/bin/env bash
#
# run_transform_tests.sh — golden-file + spec-assertion tests for the
# deterministic transforms in lib/sarif_transform.sh.
#
# The transforms (fingerprint, SARIF mapping, dedup, fail-on) are specified in
# prose in commands/security-review.md and have no other executable source of
# truth. This runner locks their behavior two ways:
#   1. Golden diffs — sarif_transform.sh output vs committed fixtures/golden/*.
#   2. Explicit spec assertions — exact values from the prose contract
#      (fingerprint preimage, severity->level/security-severity table, dedup key,
#      fail-on counting) so a golden that drifts WITH the implementation can't
#      hide a spec violation.
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
