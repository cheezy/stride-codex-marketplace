#!/usr/bin/env bash
# Top-level smoke-test runner for the stride-codex-security-review plugin.
#
# Runs the full offline gate and aggregates the result:
#   - test-structure.sh      plugin layout (manifest, skill, agent, lib/, fixtures/)
#   - test-frontmatter.sh    skill/agent YAML frontmatter (Codex tools contract)
#   - check_agent_contract.sh agent/skill content pins (exact tools line, no
#                            Claude Code names, frontmatter), each with a
#                            break-it on a mktemp copy
#   - run_transform_tests.sh deterministic SARIF/dedup/fail-on transforms vs golden
#   - check_fixtures.sh      every fixture has exactly one EXPECTED.md row, and
#                            every considerations fixture has its sidecar and
#                            one expected verdict per consideration
#   - check_eval_invocation.sh how run_eval.sh invokes codex, pinned against a
#                            fake CLI (agent file as the instructions, tools
#                            off, empty scratch cwd, auth), with break-its on
#                            a scratch copy
#   - check_git_hardening.sh the five git forms, the probe's guard line and its
#                            copy step run against scratch repositories whose
#                            own config names marker programs, and a stand-in
#                            for a git older than 2.44 (needs git 2.44 or
#                            later; skips on an older one)
#   - check_install.sh       install.sh --project, a re-install and a global
#                            install (and install.ps1 -Project when pwsh is on
#                            PATH) from a local scratch clone, every pack and
#                            mode file compared byte for byte (W2636)
#
# It then runs its own self-test on scratch copies of the plugin: a good copy
# passes; a copy whose agent tools line is broken makes this runner exit 1, so
# a failing check_agent_contract.sh is shown to fail the gate; and a sabotaged
# copy whose own self-test cannot pass makes it exit 1 too, so a failing
# self-test is shown to fail the gate. TEST_ALL_CHILD stops the good and broken
# copies running the self-test again; the sabotaged copy does run it, and
# TEST_ALL_NESTED stops it running the sabotaged case, bounding the recursion
# at one level. The copies run check_agent_contract.sh,
# check_eval_invocation.sh, check_git_hardening.sh and check_install.sh with
# their *_CHILD variables set, which skips the break-its those four already ran
# once at the top level.
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

TESTS="test-structure.sh test-frontmatter.sh check_agent_contract.sh run_transform_tests.sh check_fixtures.sh check_eval_invocation.sh check_git_hardening.sh check_install.sh"

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

# --- Runner self-test --------------------------------------------------------
# Copies an explicit list of the plugin's files (never a glob of the root, so a
# local file such as a gitignored credentials file is never copied) into a
# temporary directory, removed on every exit. The good copy must pass; the copy
# with an extra tool on the agent's tools line, which only
# check_agent_contract.sh refuses, must make the runner exit 1; and the
# sabotaged copy, whose own self-test fails, must make the runner exit 1.

if [ -z "${TEST_ALL_CHILD:-}" ]; then
  printf '=== runner self-test ===\n'
  RAN=$(( RAN + 1 ))
  st_failed=0
  ROOT="${SCRIPT_DIR}/.."
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-all.XXXXXX")" || {
    printf 'FAIL: self-test: could not create a temporary directory\n'; exit 1; }
  trap 'rm -rf "$TMP"' EXIT
  trap 'exit 1' HUP INT TERM
  mkdir -p "$TMP/good"
  for p in .codex-plugin agents skills lib fixtures README.md AGENTS.md CHANGELOG.md LICENSE install.sh install.ps1; do
    cp -R "${ROOT}/${p}" "$TMP/good/" || st_failed=1
  done
  cp -R "$TMP/good" "$TMP/broken"
  A="$TMP/broken/agents/security-reviewer.md"
  awk '/^tools:/ && !d { sub(/\]$/, ", \"edit\"]"); d = 1 } { print }' "$A" > "$A.new" && mv "$A.new" "$A"

  run_copy() { # $1=label $2=tree $3=want-exit $4.. = needles that must appear
    local label="$1" tree="$2" want="$3" out rc needle
    shift 3
    out="$(TEST_ALL_CHILD=1 CHECK_AGENT_CONTRACT_CHILD=1 CHECK_EVAL_INVOCATION_CHILD=1 CHECK_GIT_HARDENING_CHILD=1 CHECK_INSTALL_CHILD=1 bash "$tree/lib/test-all.sh" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want" ]; then
      printf 'FAIL: self-test: %s -- exit %d, wanted %d\n' "$label" "$rc" "$want"; st_failed=1; return
    fi
    for needle in "$@"; do
      if ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
        printf 'FAIL: self-test: %s -- output lacks: %s\n' "$label" "$needle"; st_failed=1; return
      fi
    done
    printf 'ok: self-test: %s\n' "$label"
  }
  run_copy "a good copy passes the runner" "$TMP/good" 0 "smoke-test scripts passed"
  run_copy "a broken tools line fails the runner" "$TMP/broken" 1 \
    "smoke-test script(s) FAILED" "FAIL: the frontmatter tools line"

  # A failing self-test must fail the runner too. The sabotaged copy's runner
  # looks for a needle its good copy never prints, so its own self-test fails
  # while every sub-script passes. That copy runs its self-test (TEST_ALL_CHILD
  # unset) with TEST_ALL_NESTED set, which skips this case there and bounds the
  # recursion at one level.
  if [ -z "${TEST_ALL_NESTED:-}" ]; then
    cp -R "$TMP/good" "$TMP/sabotaged"
    R="$TMP/sabotaged/lib/test-all.sh"
    awk '/^  run_copy "a good copy passes the runner"/ && !d { sub(/"smoke-test scripts passed"/, "\"a needle no run prints\""); d = 1 } { print }' \
      "$R" > "$R.new" && mv "$R.new" "$R"
    out="$(TEST_ALL_NESTED=1 CHECK_AGENT_CONTRACT_CHILD=1 CHECK_EVAL_INVOCATION_CHILD=1 CHECK_GIT_HARDENING_CHILD=1 CHECK_INSTALL_CHILD=1 bash "$R" 2>&1)"; rc=$?
    if [ "$rc" -ne 1 ]; then
      printf 'FAIL: self-test: a failing runner self-test fails the runner -- exit %d, wanted 1\n' "$rc"; st_failed=1
    elif ! printf '%s\n' "$out" | grep -qF -- "FAIL: self-test: a good copy passes the runner -- output lacks: a needle no run prints"; then
      printf 'FAIL: self-test: a failing runner self-test fails the runner -- the sabotaged self-test did not fail\n'; st_failed=1
    elif ! printf '%s\n' "$out" | grep -qF -- "smoke-test script(s) FAILED"; then
      printf 'FAIL: self-test: a failing runner self-test fails the runner -- output lacks: smoke-test script(s) FAILED\n'; st_failed=1
    else
      printf 'ok: self-test: a failing runner self-test fails the runner\n'
    fi
  fi

  [ "$st_failed" -eq 0 ] || FAILED=$(( FAILED + 1 ))
  printf '\n'
fi

printf '================================\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%d of %d smoke-test script(s) FAILED\n' "$FAILED" "$RAN"
  exit 1
fi
printf 'All %d smoke-test scripts passed\n' "$RAN"
