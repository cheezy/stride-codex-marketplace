#!/usr/bin/env bash
# Structure smoke test for the stride-codex-security-review plugin.
#
# Asserts the plugin ships every file the Codex CLI edition requires: a valid
# manifest with the four Codex keys, the one command-equivalent skill, the one
# security-reviewer agent, the lib/ transform + eval tooling, the fixtures/ tree
# (EXPECTED.md, golden/, and the considerations positive/negative controls), and
# the root docs (including AGENTS.md and both installers). Codex ships NO command
# files, so there is no commands/ check. Pure shell + python3 (for JSON) — no
# network, no jq.
#
# Exit code: 0 if every check passes; 1 if any check fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

ok()   { PASS=$(( PASS + 1 )); printf '  ✓  %s\n' "$1"; }
nope() { FAIL=$(( FAIL + 1 )); printf '  ✗  %s\n     %s\n' "$1" "${2:-}"; }

printf 'stride-codex-security-review structure smoke test\n'
printf 'plugin root: %s\n\n' "$PLUGIN_ROOT"

# --- Manifest --------------------------------------------------------------

MANIFEST="${PLUGIN_ROOT}/.codex-plugin/plugin.json"
if [ -f "$MANIFEST" ]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST" 2>/tmp/scsr-manifest.err; then
    ok ".codex-plugin/plugin.json exists and is valid JSON"
    if python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
if not isinstance(d, dict):
    sys.exit(1)
missing = [k for k in ('name', 'description', 'version', 'skills') if k not in d]
sys.exit(1 if missing else 0)
" "$MANIFEST"; then
      ok "plugin.json has the four Codex keys (name, description, version, skills)"
    else
      nope "plugin.json is missing one of: name, description, version, skills" ""
    fi
  else
    nope "plugin.json is not valid JSON" "$(cat /tmp/scsr-manifest.err)"
  fi
  rm -f /tmp/scsr-manifest.err
else
  nope ".codex-plugin/plugin.json not found" "$MANIFEST"
fi

# --- Skills (Codex has no commands/; entry is skill activation) -------------
# The command-equivalent skill (stride-security-review) and the doctrine skill
# (security-review-essentials, the front-door surface stride-codex detects).

for skill in stride-security-review security-review-essentials; do
  if [ -f "${PLUGIN_ROOT}/skills/${skill}/SKILL.md" ]; then
    ok "skills/${skill}/SKILL.md exists"
  else
    nope "skills/${skill}/SKILL.md is missing" ""
  fi
done

# Count only real SKILL.md files (any .gitkeep placeholder is ignored): exactly 2.
SKILL_COUNT=$(find "${PLUGIN_ROOT}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
if [ "$SKILL_COUNT" -eq 2 ]; then
  ok "exactly 2 SKILL.md files present (.gitkeep ignored)"
else
  nope "expected 2 SKILL.md files, found ${SKILL_COUNT}" ""
fi

# --- Agent (Codex: bare *.md file, no commands/ directory) ------------------

if [ -f "${PLUGIN_ROOT}/agents/security-reviewer.md" ]; then
  ok "agents/security-reviewer.md exists"
else
  nope "agents/security-reviewer.md is missing" ""
fi

AGENT_COUNT=$(find "${PLUGIN_ROOT}/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -eq 1 ]; then
  ok "exactly 1 agent file present (.gitkeep ignored)"
else
  nope "expected 1 agent file, found ${AGENT_COUNT}" ""
fi

# Codex ships no command files: assert there is no commands/ directory.
if [ -d "${PLUGIN_ROOT}/commands" ]; then
  nope "unexpected commands/ directory (Codex ships no command files)" "${PLUGIN_ROOT}/commands"
else
  ok "no commands/ directory (correct for Codex)"
fi

# --- lib/ tooling (transform + eval + self-tests) --------------------------

for script in \
  sarif_transform.sh \
  run_eval.sh \
  run_transform_tests.sh \
  check_fixtures.sh \
  test-all.sh \
  test-structure.sh \
  test-frontmatter.sh; do
  if [ -f "${PLUGIN_ROOT}/lib/${script}" ]; then
    ok "lib/${script} exists"
  else
    nope "lib/${script} is missing" ""
  fi
done

# --- fixtures/ (eval corpus + golden + considerations controls) ------------

if [ -f "${PLUGIN_ROOT}/fixtures/EXPECTED.md" ]; then
  ok "fixtures/EXPECTED.md exists"
else
  nope "fixtures/EXPECTED.md is missing" ""
fi

for golden in input_findings.json dedup.golden.json fingerprint.golden sarif.golden.json; do
  if [ -f "${PLUGIN_ROOT}/fixtures/golden/${golden}" ]; then
    ok "fixtures/golden/${golden} exists"
  else
    nope "fixtures/golden/${golden} is missing" ""
  fi
done

# Considerations-mode controls: a fully-mitigated positive control and an
# unmitigated negative control, each a .considerations + .diff pair.
for stem in parameterized_query_all_mitigated token_logging_unmitigated; do
  for ext in considerations diff; do
    if [ -f "${PLUGIN_ROOT}/fixtures/considerations/${stem}.${ext}" ]; then
      ok "fixtures/considerations/${stem}.${ext} exists"
    else
      nope "fixtures/considerations/${stem}.${ext} is missing" ""
    fi
  done
done

# --- Root docs and installers ----------------------------------------------

for doc in README.md CHANGELOG.md LICENSE AGENTS.md install.sh install.ps1; do
  if [ -f "${PLUGIN_ROOT}/${doc}" ]; then
    ok "${doc} exists"
  else
    nope "${doc} is missing" ""
  fi
done

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
