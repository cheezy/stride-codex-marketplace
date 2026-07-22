#!/usr/bin/env bash
# Top-level smoke-test runner for the stride-codex-exploratory-testing plugin.
#
# Runs every lib/test-*.sh check (structure + frontmatter) and aggregates
# the result. Pure shell — no network, no jq. Use this as the single entry
# point to gate a release:
#
#   ./lib/test-all.sh
#
# Exit code: 0 only if every sub-script passes; 1 if any sub-script fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TESTS="test-structure.sh test-frontmatter.sh"

RAN=0
FAILED=0

for t in $TESTS; do
  printf '=== %s ===\n' "$t"
  RAN=$(( RAN + 1 ))
  if bash "${SCRIPT_DIR}/${t}"; then
    :
  else
    FAILED=$(( FAILED + 1 ))
  fi
  printf '\n'
done

printf '================================\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%d of %d smoke-test script(s) FAILED\n' "$FAILED" "$RAN"
  exit 1
fi
printf 'All %d smoke-test scripts passed\n' "$RAN"
