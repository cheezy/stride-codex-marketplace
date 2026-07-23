#!/usr/bin/env bash
#
# check_fixtures.sh — fast parity guard between fixtures/ and EXPECTED.md.
#
# The eval suite assumes every fixture file has exactly one EXPECTED.md row and
# every EXPECTED.md row names a fixture that exists on disk. That parity is
# maintained by hand, so it silently breaks the moment someone adds a fixture
# without a row (or deletes a fixture but leaves its row). This script fails
# fast and cheap when the two sets diverge — no API key, no agent CLI, just a
# set comparison — so CI catches the drift before spending money on the eval.
#
# Exit 0 when the fixture files and the EXPECTED.md rows are in exact parity
# AND the README's eval-runner annotation stays count-agnostic; exit 1 (listing
# the offenders) on parity divergence or a hardcoded README fixture-count
# annotation; exit 2 on a setup error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIX_DIR="$ROOT_DIR/fixtures"
EXPECTED="$FIX_DIR/EXPECTED.md"

[ -d "$FIX_DIR" ] || { printf 'error: fixtures dir not found at %s\n' "$FIX_DIR" >&2; exit 2; }
[ -f "$EXPECTED" ] || { printf 'error: EXPECTED.md not found at %s\n' "$EXPECTED" >&2; exit 2; }

# Fixture files on disk, relative to fixtures/, excluding EXPECTED.md itself,
# the considerations-mode `.considerations` sidecars, and the golden/ subtree.
# Covers nested subdirectories (e.g. ci_cd/, considerations/) since the paths in
# EXPECTED.md rows are likewise relative to fixtures/. A `.considerations` file is
# the input list paired with a considerations-mode `.diff` fixture (see EXPECTED.md
# "Considerations mode"), not an independently-registered fixture, so it carries
# no EXPECTED.md row of its own and is excluded from the parity set. The golden/
# subtree holds the transform-test golden outputs (dedup/fingerprint/sarif/input),
# which are consumed by run_transform_tests.sh — not eval fixtures — so it is
# excluded too (they have no EXPECTED.md rows by design).
disk="$(cd "$FIX_DIR" && find . -type f ! -name 'EXPECTED.md' ! -name '*.considerations' ! -path './golden/*' | sed 's|^\./||' | sort)"

# Fixture paths referenced by EXPECTED.md checkbox rows: the FIRST backtick-fenced
# token of each `- [ ] \`path\` → ...` row (same extraction run_eval.sh uses).
rows="$(awk '
  /^- \[[ x]\] `[^`]+`/ {
    match($0, /`[^`]+`/)
    print substr($0, RSTART + 1, RLENGTH - 2)
  }
' "$EXPECTED" | sort -u)"

# Set differences (comm needs sorted input, which both are).
missing_rows="$(comm -23 <(printf '%s\n' "$disk") <(printf '%s\n' "$rows") | sed '/^$/d')"
missing_files="$(comm -13 <(printf '%s\n' "$disk") <(printf '%s\n' "$rows") | sed '/^$/d')"

fail=0
if [ -n "$missing_rows" ]; then
  printf 'Fixture files with no EXPECTED.md row:\n' >&2
  printf '%s\n' "$missing_rows" | sed 's/^/  - /' >&2
  fail=1
fi
if [ -n "$missing_files" ]; then
  printf 'EXPECTED.md rows naming a fixture that does not exist:\n' >&2
  printf '%s\n' "$missing_files" | sed 's/^/  - /' >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  printf 'FAIL: fixtures/ and EXPECTED.md are out of sync.\n' >&2
  exit 1
fi

count="$(printf '%s\n' "$disk" | sed '/^$/d' | wc -l | tr -d ' ')"
printf 'OK: %s fixtures, each with exactly one matching EXPECTED.md row.\n' "$count"

# Drift guard: the README's eval-runner annotation must stay count-agnostic.
# W1274 made it so; "(64 today)" regressed it and went stale within two releases
# (W1472). Scoped to README lines mentioning run_eval.sh or EXPECTED.md so
# unrelated numbers (example output, exit-code tables, version strings) and the
# CHANGELOG's historical snapshot counts can never false-positive.
README="$ROOT_DIR/README.md"
if [ -f "$README" ]; then
  drift="$(grep -nE 'run_eval\.sh|EXPECTED\.md' "$README" | grep -E '\(?[0-9]+ +(today|fixtures?|expectations?)\)?|all [0-9]+ expectations' || true)"
  if [ -n "$drift" ]; then
    printf 'FAIL: README.md hardcodes a fixture-count annotation on an eval-runner line.\n' >&2
    printf 'Keep the comment count-agnostic — this script prints the live count (%s).\n' "$count" >&2
    printf '%s\n' "$drift" | sed 's/^/  - /' >&2
    exit 1
  fi
fi

exit 0
