#!/usr/bin/env bash
# Top-level smoke-test runner for the stride-codex-security-review plugin.
#
# Runs the full offline gate and aggregates the result:
#   - test-structure.sh      plugin layout (manifest, skill, agent, lib/, fixtures/)
#   - test-frontmatter.sh    skill/agent YAML frontmatter (Codex tools contract)
#   - run_transform_tests.sh deterministic SARIF/dedup/fail-on transforms vs golden
#   - check_fixtures.sh      every fixture has exactly one EXPECTED.md row
#
# Structure + frontmatter are pure shell + python3; the transform and eval
# checks require `jq` (used by the transform scripts). No network, no live agent
# — the live-agent eval (run_eval.sh, needs a Codex model) is a separate step.
# Use this as the single entry point to gate a release:
#
#   ./lib/test-all.sh
#
# Exit code: 0 only if every sub-script passes; 1 if any sub-script fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TESTS="test-structure.sh test-frontmatter.sh run_transform_tests.sh check_fixtures.sh"

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
