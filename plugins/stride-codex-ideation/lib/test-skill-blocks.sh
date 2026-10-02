#!/usr/bin/env bash
# Tests that every fenced bash block in the two surface skills
# (skills/stride-ideation-ideate/SKILL.md and
# skills/stride-ideation-stridify/SKILL.md) is self-contained: it runs in a
# fresh shell given only the values its "# Carried forward:" line names.
#
# Each block is extracted, its '<value of NAME>' placeholders are filled with
# fixture values (shell-quoted the way the skills tell the model to quote
# them), and it is run with `bash -u` in its own scratch git repository. curl
# is a PATH-prepended fake, so the ship blocks make no network request. The
# static checks then pin the rules the skills state once near their top:
#   - a block that calls an sti_ function sources its helper itself;
#   - a block reads no variable it did not assign (carried-forward values
#     are assigned at the top of the block);
#   - a block body runs in a ( ... ) subshell, so its exit ends only that
#     subshell, never a shared shell;
#   - no <plugin-root> placeholder or CLAUDE_PROJECT_DIR reference remains;
#   - the helper-root lookup (STRIDE_IDEATION_HOME, the project install, the
#     global install, the marketplace plugin directory) picks the first
#     qualifying location and fails clearly, naming every path it tried.
#
# Run:
#   ./lib/test-skill-blocks.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The checkout itself is a valid helper root: it holds lib/ and agents/.
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
TMP=""

cleanup() {
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

TMP="$(mktemp -d)"

pass() { PASS=$(( PASS + 1 )); printf 'PASS  %s\n' "$1"; }
fail() {
  FAIL=$(( FAIL + 1 ))
  printf 'FAIL  %s\n' "$1"
  if [ "${2:-}" != "" ]; then
    printf '      %s\n' "$2"
  fi
}

# --- fixtures -------------------------------------------------------------------

# A fake value only; the ship blocks never reach a network.
TOKEN="stride_dev_BLOCK_TEST_TOKEN_x7"
cat > "$TMP/auth.md" <<EOF
- **API URL:** \`https://stride.example\`
- **API Token:** \`$TOKEN\`
EOF

mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: answer 201 with a renderable body, whatever was asked.
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; esac
  shift
done
cat > /dev/null
[ -n "$out" ] && printf '%s' '{"success": true, "total": 1, "goals": [{"goal": {"identifier": "G1", "title": "Goal"}, "child_tasks": []}]}' > "$out"
printf '201'
EOF
chmod +x "$TMP/bin/curl"

REQ_NAME="2026-05-12T120000-dark-mode-toggle-requirements.md"
BATCH_NAME="2026-05-12T120000-dark-mode-toggle-stride-batch.json"

# new_sandbox DIR — a scratch git repo holding the fixture requirements doc
# (with a Decomposition seams section), a batch JSON and a draft.
new_sandbox() {
  local d="$1"
  mkdir -p "$d/docs/ideation" "$d/.stride" "$d/tmp"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  { cat "$PLUGIN_ROOT/fixtures/$REQ_NAME"
    printf '\n## Decomposition seams\n\n1. **Kanban app** — owns the JSON contract\n2. **stride plugin** — the adapter\n'
  } > "$d/docs/ideation/$REQ_NAME"
  git -C "$d" add docs/ideation/"$REQ_NAME"
  git -C "$d" commit -q -m fixture
  cp "$PLUGIN_ROOT/fixtures/$BATCH_NAME" "$d/docs/ideation/$BATCH_NAME"
  mkdir -p "$d/tmp/stride_stridify_validate.fixture"
  cp "$PLUGIN_ROOT/fixtures/$BATCH_NAME" "$d/tmp/stride_stridify_validate.fixture/batch.json"
  printf '# draft\n' > "$d/.stride/2026-05-12T103000-dark-mode-toggle-draft.md"
  printf '# requirements\n' > "$d/docs/ideation/2026-05-12T103000-dark-mode-toggle-requirements.md"
}

# --- extract every block, fill its placeholders ----------------------------------
#
# Pass 1 fills every ", or empty" placeholder with '' (a fresh ideate session,
# no --goal). Pass 2 re-runs each block that has such a placeholder with the
# optional values set (--continue, --goal), so those branches run too.

python3 - "$PLUGIN_ROOT" "$TMP/blocks" <<'PY'
import os, re, sys

root, out = sys.argv[1], sys.argv[2]
os.makedirs(out)

def q(value):
    # The quoting the skills prescribe: single quotes, ' written as '\''.
    return "'" + value.replace("'", "'\\''") + "'"

common = {
    "HELPER_ROOT": root,
    "SKILL_PLUGIN_DIR": root,
    "TOPIC": "Dark mode toggle — it's overdue",
    "SESSION_TS": "2026-05-12T103000",
    "SLUG": "dark-mode-toggle",
    "REQUIREMENTS_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-requirements.md",
    "GOAL_ARG": "1",
    "GOAL_INDEX": "1",
    "SOURCE_TS": "2026-05-12T120000",
    "SLUG_FOR_PATH": "dark-mode-toggle",
    "TMP_DIR": "tmp/stride_stridify_validate.fixture",
    "BATCH_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-stride-batch.json",
    "DRAFT_PATH": ".stride/2026-05-12T103000-dark-mode-toggle-draft.md",
    "EXISTING_DRAFT": ".stride/2026-05-12T103000-dark-mode-toggle-draft.md",
}
per_skill = {
    "stride-ideation-ideate": {"TARGET_PATH": "docs/ideation/2026-05-12T103000-dark-mode-toggle-requirements.md"},
    "stride-ideation-stridify": {"TARGET_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-stride-batch.json"},
}

optional = {
    "CONTINUE_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-requirements.md",
    "GOAL_SLUG": "kanban-app",
    "GOAL_ARG": "1",
    "DRAFT_PATH": ".stride/2026-05-12T103000-dark-mode-toggle-draft.md",
    "SKILL_PLUGIN_DIR": root,
}

fence = re.compile(r"^([ \t]*)```bash[ \t]*\n(.*?)^\1```[ \t]*$", re.S | re.M)
placeholder = re.compile(r"'<value of ([A-Za-z_]+)(, or empty)?>'")
n = 0
for skill in ("stride-ideation-ideate", "stride-ideation-stridify"):
    path = os.path.join(root, "skills", skill, "SKILL.md")
    text = open(path, encoding="utf-8").read()
    values = dict(common, **per_skill[skill])
    for m in fence.finditer(text):
        indent, body = m.group(1), m.group(2)
        body = "\n".join(line[len(indent):] if line.startswith(indent) else line for line in body.split("\n"))
        line_no = text.count("\n", 0, m.start()) + 1
        def fill(pm):
            name, empty = pm.group(1), pm.group(2)
            if empty and name != "SKILL_PLUGIN_DIR":
                return "''"
            return q(values[name])
        def fill_optional(pm):
            name, empty = pm.group(1), pm.group(2)
            return q(optional[name]) if empty else q(values[name])
        n += 1
        base = os.path.join(out, "%02d" % n)
        open(base + ".label", "w").write("%s:%d" % (skill, line_no))
        open(base + ".raw", "w").write(body)
        open(base + ".sh", "w").write(placeholder.sub(fill, body))
        if ", or empty>" in body:
            opt = os.path.join(out, "%02d-opt" % n)
            open(opt + ".label", "w").write("%s:%d [optional values set]" % (skill, line_no))
            open(opt + ".sh", "w").write(placeholder.sub(fill_optional, body))
PY

BLOCKS="$(ls "$TMP/blocks"/*.raw | wc -l | tr -d ' ')"
OPT_BLOCKS="$(ls "$TMP/blocks"/*-opt.sh | wc -l | tr -d ' ')"
if [ "$OPT_BLOCKS" -ge 6 ]; then
  pass "blocks with optional values also run with them set ($OPT_BLOCKS blocks)"
else
  fail "expected at least 6 blocks with optional values, found $OPT_BLOCKS"
fi
if [ "$BLOCKS" -ge 20 ]; then
  pass "extracted every bash block from both skills ($BLOCKS blocks)"
else
  fail "expected at least 20 bash blocks, found $BLOCKS"
fi

# --- no <plugin-root> placeholder or CLAUDE_PROJECT_DIR remains --------------------

if grep -rnE 'plugin-root|PLUGIN_ROOT|CLAUDE_PROJECT_DIR' "$PLUGIN_ROOT/skills" > /dev/null; then
  fail "a <plugin-root> / CLAUDE_PROJECT_DIR reference remains in skills/" "$(grep -rnE 'plugin-root|PLUGIN_ROOT|CLAUDE_PROJECT_DIR' "$PLUGIN_ROOT/skills" | head -3)"
else
  pass "no <plugin-root> placeholder or CLAUDE_PROJECT_DIR reference remains in skills/"
fi

# --- per-block static checks and a fresh-shell run --------------------------------

for sh in "$TMP/blocks"/*.sh; do
  base="${sh%.sh}"
  label="$(cat "$base.label")"
  raw="$base.raw"

  # Static checks read the raw block text, so they run once per block (the
  # optional-values pass reruns the same text with different values).
  if [ -f "$raw" ]; then
    # The body runs in a ( ... ) subshell, so an exit never ends a shared shell.
    first="$(grep -v '^[[:space:]]*$' "$raw" | head -n 1)"
    last="$(grep -v '^[[:space:]]*$' "$raw" | tail -n 1)"
    if [ "$first" = "(" ] && [ "$last" = ")" ]; then
      pass "$label: body runs in a ( ... ) subshell"
    else
      fail "$label: body is not wrapped in ( ... )" "first='$first' last='$last'"
    fi

    # A block that calls an sti_ function sources that function's helper itself.
    if grep -qE 'sti_(slugify|slug_from_path|unique_path|resolve_goal|extract_seams|scope_doc_to_seam)\b' "$raw"; then
      if grep -qF '. "$HELPER_ROOT/lib/filename.sh"' "$raw"; then pass "$label: sources lib/filename.sh for its sti_ calls"; else fail "$label: calls a filename.sh function without sourcing it"; fi
    fi
    if grep -qE 'sti_draft_[a-z]+' "$raw"; then
      if grep -qF '. "$HELPER_ROOT/lib/draft.sh"' "$raw"; then pass "$label: sources lib/draft.sh for its sti_draft_ calls"; else fail "$label: calls a draft.sh function without sourcing it"; fi
    fi

    # Every variable the block reads is assigned in the block itself.
    unassigned="$(python3 - "$raw" <<'PY'
import re, sys
body = open(sys.argv[1]).read()
code = re.sub(r"<<'PY'\n.*?\nPY\n", "\n", body, flags=re.S)        # python heredocs
code = re.sub(r"awk(?: -F'[^']*')? '[^']*'", "awk", code, flags=re.S)  # awk programs
used = set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", code))
assigned = set(re.findall(r"(?:^|[\s;(])([A-Za-z_][A-Za-z0-9_]*)=", code))
assigned |= set(re.findall(r"\bfor ([A-Za-z_][A-Za-z0-9_]*) in\b", code))
env = {"TMPDIR", "HOME", "STRIDE_IDEATION_HOME"}
print(" ".join(sorted(used - assigned - env)))
PY
  )"
    if [ -z "$unassigned" ]; then
      pass "$label: reads only variables it assigns"
    else
      fail "$label: reads variables set outside the block" "$unassigned"
    fi
  fi

  # Run it in a fresh bash with nounset on, in its own sandbox.
  box="$base.box"
  new_sandbox "$box"
  ( cd "$box" && env -i PATH="$TMP/bin:$PATH" HOME="$TMP/empty-home" TMPDIR="$box/tmp" STRIDE_AUTH_FILE="$TMP/auth.md" \
      bash -u "$sh" > "$base.out" 2> "$base.err" )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label: runs in a fresh shell (exit 0)"
  else
    fail "$label: exited $rc in a fresh shell" "$(head -c 300 "$base.err")"
  fi
  if grep -qE 'unbound variable|command not found' "$base.err"; then
    fail "$label: hit an unbound variable or undefined command" "$(grep -E 'unbound variable|command not found' "$base.err" | head -2)"
  else
    pass "$label: no unbound variable or undefined command"
  fi
  if grep -qF "$TOKEN" "$base.out" "$base.err"; then
    fail "$label: printed the token"
  fi
done

# --- the helper-root lookup ---------------------------------------------------------

mkdir -p "$TMP/empty-home"
lookup_raw="$(grep -lF 'cannot find the plugin helpers; looked in' "$TMP/blocks"/*.raw | head -n 1)"
if [ -n "$lookup_raw" ]; then pass "the skills carry a helper-root lookup block"; else fail "no helper-root lookup block found"; fi
# Both surface skills carry a copy; the tier cases below run the first one, so
# the copies must be identical for those cases to cover both.
lookup_copies="$(grep -lF 'cannot find the plugin helpers; looked in' "$TMP/blocks"/*.raw)"
if [ "$(printf '%s\n' "$lookup_copies" | wc -l | tr -d ' ')" = 2 ] && cmp -s $(printf '%s\n' "$lookup_copies" | tr '\n' ' '); then
  pass "ideate and stridify carry identical helper-root lookup blocks"
else
  fail "the two helper-root lookup blocks differ (or are not two)" "$lookup_copies"
fi

# stub_root DIR [missing-file] -- a directory that qualifies as a helper root
# (lib/filename.sh, lib/ship.py, agents/requirements-decomposer.md), minus one.
stub_root() {
  mkdir -p "$1/lib" "$1/agents"
  for f in lib/filename.sh lib/ship.py agents/requirements-decomposer.md; do
    [ "$f" = "${2:-}" ] || : > "$1/$f"
  done
}

# run_lookup <label> <expected-path-or-FAIL> <skill-plugin-dir> [env assignments...]
run_lookup() {
  local label="$1" want="$2" spd="$3"; shift 3
  python3 - "$lookup_raw" "$TMP/lookup.sh" "$spd" <<'PY'
import sys
body = open(sys.argv[1]).read()
v = sys.argv[3]
open(sys.argv[2], "w").write(body.replace("'<value of SKILL_PLUGIN_DIR, or empty>'", "'" + v.replace("'", "'\\''") + "'"))
PY
  out="$(cd "$TMP/lk/proj/sub" && env -i PATH="$PATH" "$@" bash -u "$TMP/lookup.sh" 2> "$TMP/lookup.err")"
  rc=$?
  if [ "$want" = FAIL ]; then
    if [ "$rc" -ne 0 ] && grep -qF 'stride-ideation: cannot find the plugin helpers; looked in:' "$TMP/lookup.err"; then
      pass "$label"
    else
      fail "$label" "rc=$rc out=$out err=$(cat "$TMP/lookup.err")"
    fi
  else
    # Compare physical paths: git reports the toplevel with links resolved.
    if [ "$rc" -eq 0 ] && [ -d "$out" ] && [ "$(cd "$out" && pwd -P)" = "$(cd "$want" && pwd -P)" ]; then pass "$label"; else fail "$label" "rc=$rc got '$out' want '$want'"; fi
  fi
}

mkdir -p "$TMP/lk/proj/sub" "$TMP/lk/home" "$TMP/lk/empty"
git -C "$TMP/lk/proj" init -q
stub_root "$TMP/lk/override root"
stub_root "$TMP/lk/proj/.agents/stride-codex-ideation"
stub_root "$TMP/lk/home/.agents/stride-codex-ideation"
stub_root "$TMP/lk/market"
stub_root "$TMP/lk/no-ship" lib/ship.py

# The cwd (lk/proj/sub) is inside a git repository that COMMITS a qualifying
# .agents/stride-codex-ideation -- a planted copy unless Codex loaded the skill
# from that project.
run_lookup "lookup: STRIDE_IDEATION_HOME wins over every install" "$TMP/lk/override root" "$TMP/lk/market" HOME="$TMP/lk/home" STRIDE_IDEATION_HOME="$TMP/lk/override root"
run_lookup "lookup: a skill loaded from the project's .agents uses that project install" "$TMP/lk/proj/.agents/stride-codex-ideation" "$TMP/lk/proj/.agents" HOME="$TMP/lk/home"
run_lookup "lookup: a skill loaded from the global install uses it, ignoring a repository's own copy" "$TMP/lk/home/.agents/stride-codex-ideation" "$TMP/lk/home/.agents" HOME="$TMP/lk/home"
run_lookup "lookup: a skill loaded from a marketplace plugin directory uses that directory" "$TMP/lk/market" "$TMP/lk/market" HOME="$TMP/lk/home"
run_lookup "lookup: with the skill's location unknown it uses the global install, never the repository's copy" "$TMP/lk/home/.agents/stride-codex-ideation" "" HOME="$TMP/lk/home"
run_lookup "lookup: with the skill's location unknown and no global install it fails rather than use the repository's copy" FAIL "" HOME="$TMP/lk/empty"
if grep -qF "/proj/.agents" "$TMP/lookup.err"; then
  fail "lookup: the repository's own copy was considered" "$(cat "$TMP/lookup.err")"
else
  pass "lookup: the repository's own .agents/stride-codex-ideation is never searched on its own"
fi
run_lookup "lookup: a location missing lib/ship.py does not qualify" FAIL "$TMP/lk/no-ship" HOME="$TMP/lk/empty"
if grep -qF "$TMP/lk/no-ship/stride-codex-ideation, $TMP/lk/no-ship" "$TMP/lookup.err"; then
  pass "lookup: the failure names every path it tried"
else
  fail "lookup: the failure does not name the paths tried" "$(cat "$TMP/lookup.err")"
fi

# --- a wrong HELPER_ROOT fails clearly, and never ends a shared shell ------------------

guard_raw="$(grep -lF '. "$HELPER_ROOT/lib/filename.sh"' "$TMP/blocks"/*.raw | head -n 1)"
python3 - "$guard_raw" "$TMP/badroot.sh" <<'PY'
import re, sys
body = open(sys.argv[1]).read()
body = body.replace("'<value of HELPER_ROOT>'", "'/nonexistent/helper root'")
body = re.sub(r"'<value of ([A-Za-z_]+)(, or empty)?>'", "''", body)
open(sys.argv[2], "w").write(body)
PY
bash -u "$TMP/badroot.sh" > "$TMP/badroot.out" 2> "$TMP/badroot.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -qF 'stride-ideation: cannot find the plugin helpers at /nonexistent/helper root; resolve the helper root again' "$TMP/badroot.err"; then
  pass "a wrong HELPER_ROOT fails non-zero with a clear message"
else
  fail "a wrong HELPER_ROOT did not fail clearly" "rc=$rc $(cat "$TMP/badroot.err")"
fi

{ cat "$TMP/badroot.sh"; printf '\necho "shell still alive (block status $?)"\n'; } > "$TMP/shared.sh"
out="$(bash "$TMP/shared.sh" 2>/dev/null)"
if [ "$out" = "shell still alive (block status 1)" ]; then
  pass "a failing block returns non-zero without ending a shared shell"
else
  fail "a failing block ended the shared shell" "$out"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
