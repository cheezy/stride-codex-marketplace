#!/usr/bin/env bash
# Structure smoke test for the stride-codex-exploratory-testing plugin.
#
# Asserts the plugin ships every file the Codex CLI edition requires: a
# valid manifest with the four Codex keys, all five command-skills, all
# five doctrine skills, both agents, the three README-referenced fixtures,
# and the root docs (including AGENTS.md and both installers). Codex ships
# NO command files, so there is no commands/ check. Pure shell + python3
# (for JSON) — no network, no jq.
#
# Exit code: 0 if every check passes; 1 if any check fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

ok()   { PASS=$(( PASS + 1 )); printf '  ✓  %s\n' "$1"; }
nope() { FAIL=$(( FAIL + 1 )); printf '  ✗  %s\n     %s\n' "$1" "${2:-}"; }

printf 'stride-codex-exploratory-testing structure smoke test\n'
printf 'plugin root: %s\n\n' "$PLUGIN_ROOT"

# --- Manifest --------------------------------------------------------------

MANIFEST="${PLUGIN_ROOT}/.codex-plugin/plugin.json"
if [ -f "$MANIFEST" ]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST" 2>/tmp/scet-manifest.err; then
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
    nope "plugin.json is not valid JSON" "$(cat /tmp/scet-manifest.err)"
  fi
  rm -f /tmp/scet-manifest.err
else
  nope ".codex-plugin/plugin.json not found" "$MANIFEST"
fi

# --- Command-skills (Codex has no commands/; entry is skill activation) -----

for skill in \
  stride-exploratory-testing-charter \
  stride-exploratory-testing-nightmare-headline \
  stride-exploratory-testing-explore \
  stride-exploratory-testing-recon \
  stride-exploratory-testing-debrief; do
  if [ -f "${PLUGIN_ROOT}/skills/${skill}/SKILL.md" ]; then
    ok "skills/${skill}/SKILL.md exists"
  else
    nope "skills/${skill}/SKILL.md is missing" ""
  fi
done

# --- Doctrine skills --------------------------------------------------------

for skill in stride-exploratory-testing chartering heuristics oracles session; do
  if [ -f "${PLUGIN_ROOT}/skills/${skill}/SKILL.md" ]; then
    ok "skills/${skill}/SKILL.md exists"
  else
    nope "skills/${skill}/SKILL.md is missing" ""
  fi
done

# Count only real SKILL.md files (the .gitkeep placeholder is ignored):
# 5 command-skills + 5 doctrine skills = 10.
SKILL_COUNT=$(find "${PLUGIN_ROOT}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
if [ "$SKILL_COUNT" -eq 10 ]; then
  ok "exactly 10 SKILL.md files present (.gitkeep ignored)"
else
  nope "expected 10 SKILL.md files, found ${SKILL_COUNT}" ""
fi

# --- Agents (Codex: bare *.md files, no commands/ directory) -----------------

for agent in charter-generator explorer; do
  if [ -f "${PLUGIN_ROOT}/agents/${agent}.md" ]; then
    ok "agents/${agent}.md exists"
  else
    nope "agents/${agent}.md is missing" ""
  fi
done

# Count only *.md agent files (the .gitkeep placeholder is ignored).
AGENT_COUNT=$(find "${PLUGIN_ROOT}/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -eq 2 ]; then
  ok "exactly 2 agent files present (.gitkeep ignored)"
else
  nope "expected 2 agent files, found ${AGENT_COUNT}" ""
fi

# Codex ships no command files: assert there is no commands/ directory.
if [ -d "${PLUGIN_ROOT}/commands" ]; then
  nope "unexpected commands/ directory (Codex ships no command files)" "${PLUGIN_ROOT}/commands"
else
  ok "no commands/ directory (correct for Codex)"
fi

# --- Fixtures (referenced by README.md) ------------------------------------

for fixture in example-charters.md example-session-sheet.md example-debrief.md; do
  if [ -f "${PLUGIN_ROOT}/fixtures/${fixture}" ]; then
    ok "fixtures/${fixture} exists"
  else
    nope "fixtures/${fixture} is missing" ""
  fi
done

# --- Root docs and installers ----------------------------------------------

for doc in README.md HEURISTICS.md CHANGELOG.md LICENSE AGENTS.md install.sh install.ps1; do
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
