#!/usr/bin/env bash
# Frontmatter smoke test for the stride-codex-security-review plugin.
#
# Asserts every skill and agent carries the YAML frontmatter keys the
# Codex CLI needs to load it:
#   - skills/*/SKILL.md : name, description
#   - agents/*.md       : name, description, tools     (description may be
#                         a `description: |` block scalar; tools MUST be a
#                         lowercase JSON array, e.g. ["read","search","glob"])
#
# Codex ships NO command files, so there is no commands/ check and no
# allowed-tools key. Pure shell + python3 (for the JSON array) — no
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

# Print the YAML frontmatter block (the lines between the first two `---`
# fences). Requires the file to open with `---` on line 1.
extract_frontmatter() {
  awk '
    /^---[[:space:]]*$/ { c++; if (c >= 2) exit; next }
    c == 1 { print }
  ' "$1"
}

# True when the frontmatter block declares KEY (matches `key:` at the start
# of a line — works for inline values and `key: |` block scalars alike).
has_key() {
  extract_frontmatter "$1" | grep -qE "^$2:"
}

# Echo the raw value that follows `tools:` in the frontmatter (inline form).
tools_value() {
  extract_frontmatter "$1" | sed -n 's/^tools:[[:space:]]*//p' | head -n 1
}

# Check that FILE (relative label $1, path $2) declares every key in $3..$n.
check_keys() {
  local label="$1" file="$2"; shift 2
  if [ ! -f "$file" ]; then
    nope "${label} is missing" "$file"
    return
  fi
  local missing=""
  local key
  for key in "$@"; do
    if ! has_key "$file" "$key"; then
      missing="${missing} ${key}"
    fi
  done
  if [ -z "$missing" ]; then
    ok "${label} declares:$(printf ' %s' "$@")"
  else
    nope "${label} is missing frontmatter key(s):${missing}" ""
  fi
}

# Validate that FILE's `tools:` value is a lowercase JSON array of non-empty
# strings (e.g. ["read","search","glob"]) — the Codex tools contract. A
# Claude-style comma string ("Read, Grep") is rejected.
check_tools_array() {
  local label="$1" file="$2"
  local value
  value="$(tools_value "$file")"
  if [ -z "$value" ]; then
    nope "${label} tools value is empty or not inline" ""
    return
  fi
  if printf '%s' "$value" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    arr = json.loads(raw)
except Exception:
    sys.exit(1)
if not isinstance(arr, list) or not arr:
    sys.exit(1)
for x in arr:
    if not isinstance(x, str) or not x or x != x.lower():
        sys.exit(1)
sys.exit(0)
"; then
    ok "${label} tools is a lowercase JSON array (${value})"
  else
    nope "${label} tools must be a lowercase JSON array like [\"read\",\"search\"]" "got: ${value}"
  fi
}

printf 'stride-codex-security-review frontmatter smoke test\n'
printf 'plugin root: %s\n\n' "$PLUGIN_ROOT"

# --- Skills: name + description --------------------------------------------

printf 'Skills (name, description)\n'
for skill_md in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
  [ -e "$skill_md" ] || { nope "no SKILL.md files found under skills/" ""; break; }
  rel="skills/$(basename "$(dirname "$skill_md")")/SKILL.md"
  check_keys "$rel" "$skill_md" name description
done

# --- Agents: name + description + tools (tools = lowercase JSON array) ------

printf '\nAgents (name, description, tools)\n'
for agent_md in "${PLUGIN_ROOT}"/agents/*.md; do
  [ -e "$agent_md" ] || { nope "no *.md files found under agents/" ""; break; }
  rel="agents/$(basename "$agent_md")"
  check_keys "$rel" "$agent_md" name description tools
  check_tools_array "$rel" "$agent_md"
done

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
