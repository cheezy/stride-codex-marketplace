#!/usr/bin/env bash
# Tests for install.sh (and, when pwsh is available, its agreement with
# install.ps1): the namespaced helper layout, stale-file cleanup, and the
# managed AGENTS.md block — fresh, existing, empty, malformed-marker and re-run
# cases.
#
# Fully offline: every run sets INSTALL_SOURCE_DIR to this checkout, so the
# installer copies from it instead of cloning from GitHub. Every run gets its
# own temp HOME, so nothing outside the test's temp dir is touched.
#
# lib/test-install.ps1 is the PowerShell twin and runs the same cases.
#
# Run:
#   ./lib/test-install.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$PLUGIN_ROOT/install.sh"
INSTALL_PS1="$PLUGIN_ROOT/install.ps1"

PASS=0
FAIL=0
TMP=""

cleanup() {
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

# A space in the temp path exercises quoting in every installer path.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sti install.XXXXXX")"

pass() { PASS=$(( PASS + 1 )); printf 'PASS  %s\n' "$1"; }
fail() {
  FAIL=$(( FAIL + 1 ))
  printf 'FAIL  %s\n' "$1"
  if [ "${2:-}" != "" ]; then
    printf '      %s\n' "$2"
  fi
}

BEGIN_MARKER="<!-- BEGIN stride-ideation -->"
END_MARKER="<!-- END stride-ideation -->"
NOTE_MARKER="<!-- Managed by the stride-codex-ideation installer; content between these markers is regenerated on each install. Add your own notes outside this block. -->"

# The exact managed block both installers must write.
BLOCK="$TMP/expected-block.md"
{
  printf '%s\n' "$BEGIN_MARKER"
  printf '%s\n' "$NOTE_MARKER"
  cat "$PLUGIN_ROOT/AGENTS.md"
  [ -n "$(tail -c1 "$PLUGIN_ROOT/AGENTS.md")" ] && printf '\n'
  printf '%s\n' "$END_MARKER"
} > "$BLOCK"

# A fake git that fails loudly: INSTALL_SOURCE_DIR must mean no clone at all.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "fake git: the installer tried to clone" >&2\nexit 97\n' > "$TMP/bin/git"
chmod +x "$TMP/bin/git"
PATH="$TMP/bin:$PATH"

HAVE_PWSH=false
command -v pwsh >/dev/null 2>&1 && HAVE_PWSH=true

# run_sh <home> [--project] — runs install.sh with HOME=<home> from cwd $CWD
# (default <home>). Leaves output in $OUT and exit status in $RC.
run_sh() {
  local home="$1"; shift
  mkdir -p "$home"
  OUT="$(cd "${CWD:-$home}" && HOME="$home" INSTALL_SOURCE_DIR="$PLUGIN_ROOT" bash "$INSTALL_SH" "$@" 2>&1)"
  RC=$?
}

# run_ps <home> [-Project] — the same through install.ps1, with USERPROFILE
# unset so the HOME fallback is what resolves the global directory.
run_ps() {
  local home="$1"; shift
  mkdir -p "$home"
  OUT="$(cd "${CWD:-$home}" && env -u USERPROFILE HOME="$home" INSTALL_SOURCE_DIR="$PLUGIN_ROOT" pwsh -NoProfile -NonInteractive -File "$INSTALL_PS1" "$@" 2>&1)"
  RC=$?
}

count_begin() { grep -cxF "$BEGIN_MARKER" "$1"; }

# --- fresh global install ------------------------------------------------------

H="$TMP/fresh"
run_sh "$H"
A="$H/.agents"
if [ "$RC" -eq 0 ]; then pass "fresh: install.sh exits 0"; else fail "fresh: install.sh exit $RC" "$OUT"; fi
if cmp -s "$BLOCK" "$A/AGENTS.md"; then pass "fresh: AGENTS.md is exactly the managed block"; else fail "fresh: AGENTS.md differs from the managed block"; fi
if [ "$(ls "$A/skills" | wc -l | tr -d ' ')" = 3 ] && [ "$(ls "$A/agents"/*.md | wc -l | tr -d ' ')" = 2 ]; then
  pass "fresh: 3 skills and 2 agents land where Codex discovers them"
else
  fail "fresh: skills/agents missing" "$(ls -R "$A" | head -20)"
fi
if [ -f "$A/stride-codex-ideation/lib/ship.py" ] && [ -f "$A/stride-codex-ideation/lib/filename.sh" ] && [ -f "$A/stride-codex-ideation/fixtures/README.md" ]; then
  pass "fresh: helpers and fixtures install under the namespaced stride-codex-ideation/ dir"
else
  fail "fresh: namespaced helpers missing" "$(ls -R "$A/stride-codex-ideation" 2>&1 | head -20)"
fi
if [ -f "$A/stride-codex-ideation/agents/requirements-decomposer.md" ] && [ -f "$A/stride-codex-ideation/agents/requirements-reviewer.md" ]; then
  pass "fresh: agent files are also installed under the helper root, where the skills look them up"
else
  fail "fresh: helper root has no agents/ copy"
fi
if [ -x "$A/stride-codex-ideation/lib/test-ship.sh" ]; then pass "fresh: the executable bit on .sh helpers is preserved"; else fail "fresh: .sh helpers lost their executable bit"; fi
if [ ! -e "$A/lib" ] && [ ! -e "$A/fixtures" ]; then pass "fresh: nothing is written to the shared .agents/lib or .agents/fixtures"; else fail "fresh: shared lib/ or fixtures/ was created"; fi
case "$OUT" in
  *"Helper root: $(cd "$A/stride-codex-ideation" && pwd)"*) pass "fresh: the resolved helper root is printed" ;;
  *) fail "fresh: helper root line missing" "$OUT" ;;
esac
case "$OUT" in
  *"fake git"*) fail "fresh: INSTALL_SOURCE_DIR still ran git clone" ;;
  *) pass "fresh: INSTALL_SOURCE_DIR installs from the checkout without cloning" ;;
esac
case "$OUT" in
  *"an earlier release installed helpers"*) fail "fresh: the legacy-helpers note printed on a clean home" ;;
  *) pass "fresh: no legacy-helpers note on a clean home" ;;
esac

# --- re-run: idempotent, stale helpers removed, nothing outside touched ---------

cp "$A/AGENTS.md" "$TMP/fresh-agents.md"
printf 'stale\n' > "$A/stride-codex-ideation/lib/dropped-by-a-newer-release.sh"
printf 'stale\n' > "$A/stride-codex-ideation/fixtures/dropped.md"
mkdir -p "$A/lib" "$A/fixtures"
printf 'other tool\n' > "$A/lib/other-tool.sh"
printf 'legacy\n' > "$A/lib/filename.sh"
printf 'legacy\n' > "$A/lib/validate_batch.py"
printf 'other tool\n' > "$A/fixtures/other-tool.md"
run_sh "$H"
if [ "$RC" -eq 0 ]; then pass "re-run: install.sh exits 0"; else fail "re-run: exit $RC" "$OUT"; fi
if cmp -s "$TMP/fresh-agents.md" "$A/AGENTS.md"; then pass "re-run: AGENTS.md is unchanged (one block, refreshed in place)"; else fail "re-run: AGENTS.md changed on a re-run"; fi
if [ ! -e "$A/stride-codex-ideation/lib/dropped-by-a-newer-release.sh" ] && [ ! -e "$A/stride-codex-ideation/fixtures/dropped.md" ]; then
  pass "re-run: helper files no longer shipped are removed"
else
  fail "re-run: stale helper files survived"
fi
if [ -f "$A/lib/other-tool.sh" ] && [ -f "$A/lib/filename.sh" ] && [ -f "$A/fixtures/other-tool.md" ]; then
  pass "re-run: nothing outside the namespaced dir is deleted"
else
  fail "re-run: a file outside the namespaced dir was removed"
fi
case "$OUT" in
  *"an earlier release installed helpers into $A/lib"*) pass "re-run: legacy helpers in .agents/lib are pointed out, not deleted" ;;
  *) fail "re-run: legacy-helpers note missing" "$OUT" ;;
esac

# --- the clear step never deletes the source -------------------------------------

H="$TMP/self"
mkdir -p "$H/.agents/stride-codex-ideation"
cp -R "$PLUGIN_ROOT/." "$H/.agents/stride-codex-ideation/src-copy"
OUT="$(cd "$H" && HOME="$H" INSTALL_SOURCE_DIR="$H/.agents/stride-codex-ideation/src-copy" bash "$INSTALL_SH" 2>&1)"
RC=$?
if [ "$RC" -ne 0 ] && [ -f "$H/.agents/stride-codex-ideation/src-copy/install.sh" ]; then
  pass "self-install: a source inside the install target is refused and left intact"
else
  fail "self-install: source inside the target was not refused (rc=$RC)" "$OUT"
fi

# --- existing AGENTS.md shapes ----------------------------------------------------
#
# seed_case <name> — writes the case's pre-existing AGENTS.md to $TMP/seed-<name>.md.

seed_case() {
  case "$1" in
    user) printf '# My project\n\nMy own notes.\n' ;;
    noeol) printf '# My project\n\nNo trailing newline' ;;
    empty) : ;;
    refresh) printf '# Mine before\n\n%s\nold managed text\n%s\n\n# Mine after\n' "$BEGIN_MARKER" "$END_MARKER" ;;
    endfirst) printf 'intro\n%s\nmiddle\n%s\noutro\n' "$END_MARKER" "$BEGIN_MARKER" ;;
    strayend) printf 'intro\n%s\n%s\nold managed text\n%s\noutro\n' "$END_MARKER" "$BEGIN_MARKER" "$END_MARKER" ;;
    beginonly) printf 'intro\n%s\norphan begin, no end\n' "$BEGIN_MARKER" ;;
    midline) printf 'Our docs mention %s and %s inline.\n' "$BEGIN_MARKER" "$END_MARKER" ;;
    crlf) printf '# Windows file\r\n%s\r\nold\r\n%s\r\nafter\r\n' "$BEGIN_MARKER" "$END_MARKER" ;;
    latin1) printf '# Caf\351 notes (Windows-1252)\n\n%s\nold\n%s\n' "$BEGIN_MARKER" "$END_MARKER" ;;
    bom) printf '\357\273\277# Notes with a UTF-8 BOM \342\200\224 kept\n' ;;
  esac > "$TMP/seed-$1.md"
}

# expected_case <name> — the AGENTS.md the installer must leave behind.
expected_case() {
  local seed="$TMP/seed-$1.md"
  case "$1" in
    empty) cat "$BLOCK" ;;
    refresh)
      printf '# Mine before\n\n'
      cat "$BLOCK"
      printf '\n# Mine after\n'
      ;;
    noeol) cat "$seed"; printf '\n\n'; cat "$BLOCK" ;;
    strayend) printf 'intro\n%s\n' "$END_MARKER"; cat "$BLOCK"; printf 'outro\n' ;;
    latin1) printf '# Caf\351 notes (Windows-1252)\n\n'; cat "$BLOCK" ;;
    crlf) printf '# Windows file\r\n'; cat "$BLOCK"; printf 'after\r\n' ;;
    *) cat "$seed"; printf '\n'; cat "$BLOCK" ;;
  esac
}

for c in user noeol empty refresh endfirst strayend beginonly midline crlf latin1 bom; do
  seed_case "$c"
  expected_case "$c" > "$TMP/expected-$c.md"
  H="$TMP/case-sh-$c"
  mkdir -p "$H/.agents"
  cp "$TMP/seed-$c.md" "$H/.agents/AGENTS.md"
  run_sh "$H"
  if [ "$RC" -eq 0 ] && cmp -s "$TMP/expected-$c.md" "$H/.agents/AGENTS.md"; then
    pass "AGENTS.md [$c]: install.sh writes the expected result"
  else
    fail "AGENTS.md [$c]: install.sh result differs (rc=$RC)" "$(diff "$TMP/expected-$c.md" "$H/.agents/AGENTS.md" | head -8)"
  fi
  cp "$H/.agents/AGENTS.md" "$TMP/after-first-$c.md"
  run_sh "$H"
  if [ "$(count_begin "$H/.agents/AGENTS.md")" -ge 1 ] && cmp -s "$TMP/after-first-$c.md" "$H/.agents/AGENTS.md"; then
    pass "AGENTS.md [$c]: a second install.sh run changes nothing"
  else
    fail "AGENTS.md [$c]: a second run changed the file"
  fi
done

# The user's own text survives every malformed shape untouched, as a prefix.
for c in endfirst beginonly midline bom; do
  if [ "$(head -c "$(wc -c < "$TMP/seed-$c.md")" "$TMP/case-sh-$c/.agents/AGENTS.md")" = "$(cat "$TMP/seed-$c.md")" ]; then
    pass "AGENTS.md [$c]: user content (malformed markers, legacy encodings, a BOM) survives byte for byte"
  else
    fail "AGENTS.md [$c]: user content was altered"
  fi
done

# --- a bundle AGENTS.md without a final newline still ends the block cleanly ------

SRC2="$TMP/source-noeol"
mkdir -p "$SRC2"
(cd "$PLUGIN_ROOT" && tar --exclude .git -cf - .) | (cd "$SRC2" && tar -xf -)
printf '%s' "$(cat "$PLUGIN_ROOT/AGENTS.md")" > "$SRC2/AGENTS.md"
H="$TMP/noeol-bundle"
mkdir -p "$H"
OUT="$(cd "$H" && HOME="$H" INSTALL_SOURCE_DIR="$SRC2" bash "$INSTALL_SH" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] && cmp -s "$BLOCK" "$H/.agents/AGENTS.md"; then
  pass "bundle: an AGENTS.md source without a final newline still puts END on its own line"
else
  fail "bundle: missing final newline not supplied (rc=$RC)" "$(tail -3 "$H/.agents/AGENTS.md" 2>&1)"
fi

# --- never write through a symlinked AGENTS.md, never delete through a link -------

H="$TMP/symlink-agents"
mkdir -p "$H/.agents"
printf 'precious\n' > "$TMP/precious-rc"
ln -s "$TMP/precious-rc" "$H/.agents/AGENTS.md"
run_sh "$H"
if [ "$RC" -ne 0 ] && [ "$(cat "$TMP/precious-rc")" = "precious" ]; then
  pass "symlink: a symlinked AGENTS.md is refused and its target left untouched"
else
  fail "symlink: wrote through a symlinked AGENTS.md (rc=$RC)" "$OUT"
fi
ln -s "$TMP/never-created" "$H/dangling-agents"
rm -f "$H/.agents/AGENTS.md"
ln -s "$TMP/never-created" "$H/.agents/AGENTS.md"
run_sh "$H"
if [ "$RC" -ne 0 ] && [ ! -e "$TMP/never-created" ]; then
  pass "symlink: a dangling AGENTS.md link is refused and nothing is created at its target"
else
  fail "symlink: a dangling AGENTS.md link was followed (rc=$RC)"
fi

H="$TMP/linked-root"
mkdir -p "$H/.agents" "$TMP/dev-checkout/lib"
printf 'keep me\n' > "$TMP/dev-checkout/lib/mine.sh"
ln -s "$TMP/dev-checkout" "$H/.agents/stride-codex-ideation"
run_sh "$H"
if [ "$RC" -eq 0 ] && [ -f "$TMP/dev-checkout/lib/mine.sh" ] && [ ! -L "$H/.agents/stride-codex-ideation" ] && [ -f "$H/.agents/stride-codex-ideation/lib/ship.py" ]; then
  pass "symlink: a symlinked helper root is replaced; its target is never deleted"
else
  fail "symlink: linked helper root handled wrongly (rc=$RC)" "$OUT"
fi

# A helper root linked to the very checkout being installed from is replaced as
# a link; the checkout is untouched (install.ps1 agrees).
H="$TMP/root-linked-to-source"
DEVSRC="$TMP/dev-source"
mkdir -p "$H/.agents" "$DEVSRC"
(cd "$PLUGIN_ROOT" && tar --exclude .git -cf - .) | (cd "$DEVSRC" && tar -xf -)
ln -s "$DEVSRC" "$H/.agents/stride-codex-ideation"
OUT="$(cd "$H" && HOME="$H" INSTALL_SOURCE_DIR="$DEVSRC" bash "$INSTALL_SH" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] && [ -f "$DEVSRC/install.sh" ] && [ ! -L "$H/.agents/stride-codex-ideation" ]; then
  pass "symlink: a helper root linked to the source checkout is replaced; the checkout is intact"
else
  fail "symlink: helper root linked to the source handled wrongly (rc=$RC)" "$OUT"
fi

# A source reached through a link into the target is still refused.
H="$TMP/self-via-link"
INNER="$H/.agents/stride-codex-ideation/src-copy"
mkdir -p "$INNER"
(cd "$PLUGIN_ROOT" && tar --exclude .git -cf - .) | (cd "$INNER" && tar -xf -)
ln -s "$INNER" "$TMP/src-link"
OUT="$(cd "$H" && HOME="$H" INSTALL_SOURCE_DIR="$TMP/src-link" bash "$INSTALL_SH" 2>&1)"
RC=$?
if [ "$RC" -ne 0 ] && [ -f "$INNER/install.sh" ]; then
  pass "self-install: a source reached through a link into the target is refused"
else
  fail "self-install: a linked source inside the target was not refused (rc=$RC)" "$OUT"
fi

# A hostile repository can commit .agents as a link; the clear must never
# follow it out of the project.
R="$TMP/hostile-repo"
mkdir -p "$R" "$TMP/outside/stride-codex-ideation"
printf 'not yours\n' > "$TMP/outside/stride-codex-ideation/keep.txt"
ln -s "$TMP/outside" "$R/.agents"
CWD="$R" run_sh "$TMP/hostile-home" --project
if [ "$RC" -ne 0 ] && [ -f "$TMP/outside/stride-codex-ideation/keep.txt" ]; then
  pass "symlink: --project refuses a symlinked .agents and deletes nothing outside the project"
else
  fail "symlink: --project followed a symlinked .agents (rc=$RC)" "$OUT"
fi

H="$TMP/linked-skill"
run_sh "$H"
printf 'precious\n' > "$TMP/precious-skill"
rm -f "$H/.agents/skills/stride-ideation/SKILL.md"
ln -s "$TMP/precious-skill" "$H/.agents/skills/stride-ideation/SKILL.md"
run_sh "$H"
if [ "$RC" -eq 0 ] && [ "$(cat "$TMP/precious-skill")" = "precious" ] && [ ! -L "$H/.agents/skills/stride-ideation/SKILL.md" ]; then
  pass "symlink: a linked SKILL.md is replaced, never written through"
else
  fail "symlink: wrote through a linked SKILL.md (rc=$RC)"
fi

# --- project mode, in a path containing spaces --------------------------------------

P="$TMP/my project"
mkdir -p "$P"
CWD="$P" run_sh "$TMP/project-home" --project
if [ "$RC" -eq 0 ] && cmp -s "$BLOCK" "$P/AGENTS.md" && [ -f "$P/.agents/stride-codex-ideation/lib/ship.py" ] && [ -d "$P/.agents/skills/stride-ideation-stridify" ]; then
  pass "project: --project installs into ./.agents and ./AGENTS.md, in a path with spaces"
else
  fail "project: --project install wrong (rc=$RC)" "$OUT"
fi
if [ ! -e "$TMP/project-home/.agents" ]; then pass "project: --project leaves the home directory alone"; else fail "project: --project wrote to the home directory"; fi

# --- install.sh and install.ps1 agree byte for byte ---------------------------------

if [ "$HAVE_PWSH" = true ]; then
  H="$TMP/ps-fresh"
  run_ps "$H"
  if [ "$RC" -eq 0 ]; then pass "pwsh: install.ps1 runs in global mode with USERPROFILE unset"; else fail "pwsh: install.ps1 failed with USERPROFILE unset (rc=$RC)" "$OUT"; fi
  if diff -r "$TMP/fresh/.agents/skills" "$H/.agents/skills" >/dev/null && diff -r "$TMP/fresh/.agents/agents" "$H/.agents/agents" >/dev/null \
     && diff -r "$PLUGIN_ROOT/lib" "$H/.agents/stride-codex-ideation/lib" >/dev/null && cmp -s "$BLOCK" "$H/.agents/AGENTS.md"; then
    pass "pwsh: install.ps1 produces the same layout and AGENTS.md as install.sh"
  else
    fail "pwsh: install.ps1 layout differs from install.sh"
  fi
  for c in user noeol empty refresh endfirst strayend beginonly midline crlf latin1 bom; do
    H="$TMP/case-ps-$c"
    mkdir -p "$H/.agents"
    cp "$TMP/seed-$c.md" "$H/.agents/AGENTS.md"
    run_ps "$H"
    if [ "$RC" -eq 0 ] && cmp -s "$TMP/case-sh-$c/.agents/AGENTS.md" "$H/.agents/AGENTS.md"; then
      pass "pwsh [$c]: install.ps1 and install.sh produce byte-identical AGENTS.md"
    else
      fail "pwsh [$c]: install.ps1 result differs from install.sh (rc=$RC)" "$(diff "$TMP/case-sh-$c/.agents/AGENTS.md" "$H/.agents/AGENTS.md" | head -8)"
    fi
  done
else
  printf 'SKIP  pwsh not found: install.ps1 agreement cases not run (lib/test-install.ps1 covers it)\n'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
