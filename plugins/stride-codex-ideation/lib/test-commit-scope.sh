#!/usr/bin/env bash
# Tests that the artifact commits in the two surface skills commit ONLY the
# artifact: ideate Step 9 (the requirements doc) and stridify Step 8d (the
# batch JSON).
#
# The exact fenced blocks are extracted from the skills, their
# '<value of NAME>' placeholders filled with fixture values, and run in a
# scratch git repository where an unrelated file was staged before the
# session. A plain `git commit` would record that file too; the blocks pass
# the artifact as a pathspec after `--`, so it must stay staged and out of the
# new commit. Each case runs both in a repository with history and in one
# with no prior commits.
#
# Run:
#   ./lib/test-commit-scope.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

REQ_DOC="docs/ideation/2026-05-12T103000-dark-mode-toggle-requirements.md"
BATCH="docs/ideation/2026-05-12T120000-dark-mode-toggle-stride-batch.json"
STAGED="docs/ideation/unrelated-notes.md"

# extract_block <skill> <marker> <out> [continue-path] — write the fenced bash
# block of <skill> that contains <marker>, placeholders filled, to <out>.
extract_block() {
  python3 - "$PLUGIN_ROOT" "$1" "$2" "$3" "${4:-}" "$REQ_DOC" "$BATCH" <<'PY'
import os, re, sys
root, skill, marker, out, cont, req_doc, batch = sys.argv[1:8]
text = open(os.path.join(root, "skills", skill, "SKILL.md"), encoding="utf-8").read()
blocks = [m.group(2) for m in re.finditer(r"^([ \t]*)```bash[ \t]*\n(.*?)^\1```[ \t]*$", text, re.S | re.M)
          if marker in m.group(2)]
if len(blocks) != 1:
    sys.exit("expected exactly one block containing %r in %s, found %d" % (marker, skill, len(blocks)))
values = {
    "HELPER_ROOT": root,
    "TARGET_PATH": req_doc if skill == "stride-ideation-ideate" else batch,
    "SLUG": "dark-mode-toggle",
    "DRAFT_PATH": ".stride/2026-05-12T103000-dark-mode-toggle-draft.md",
    "CONTINUE_PATH": cont,
    "GOAL_SLUG": "",
}
def q(v):
    return "'" + v.replace("'", "'\\''") + "'"
body = re.sub(r"'<value of ([A-Za-z_]+)(, or empty)?>'", lambda m: q(values[m.group(1)]), blocks[0])
open(out, "w").write(body)
PY
}

# new_repo <dir> <with-history> — a scratch repo whose index already holds an
# unrelated staged file, plus the artifact the block is about to commit.
new_repo() {
  local d="$1"
  mkdir -p "$d/docs/ideation"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  if [ "$2" = yes ]; then
    printf 'seed\n' > "$d/README.md"
    git -C "$d" add README.md
    git -C "$d" commit -q -m seed
  fi
  printf 'private scratch notes, not for this commit\n' > "$d/$STAGED"
  git -C "$d" add "$STAGED"
  printf '# Dark mode toggle\n' > "$d/$REQ_DOC"
  cp "$PLUGIN_ROOT/fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json" "$d/$BATCH"
}

# check_case <label> <block-file> <artifact> <expected-subject>
check_case() {
  local label="$1" block="$2" artifact="$3" subject="$4" history
  for history in yes no; do
    local d="$TMP/repo-$RANDOM-$history"
    new_repo "$d" "$history"
    ( cd "$d" && bash -u "$block" > "$d.out" 2> "$d.err" )
    local rc=$? tag="$label (history: $history)"
    if [ "$rc" -eq 0 ]; then pass "$tag: the block exits 0"; else fail "$tag: the block exited $rc" "$(head -c 300 "$d.err")"; continue; fi

    local committed
    committed="$(git -C "$d" show --name-only --pretty=format: HEAD | sed '/^$/d')"
    if [ "$committed" = "$artifact" ]; then
      pass "$tag: the new commit contains only the artifact"
    else
      fail "$tag: the new commit contains more than the artifact" "$(printf '%s' "$committed" | tr '\n' ' ')"
    fi
    if git -C "$d" diff --cached --name-only | grep -qx "$STAGED"; then
      pass "$tag: the pre-staged file is still staged"
    else
      fail "$tag: the pre-staged file is no longer staged"
    fi
    if git -C "$d" show --name-only --pretty=format: HEAD | grep -qx "$STAGED"; then
      fail "$tag: the pre-staged file was swept into the commit"
    else
      pass "$tag: the pre-staged file is absent from the commit"
    fi
    if [ "$(git -C "$d" log -1 --pretty=%s)" = "$subject" ]; then
      pass "$tag: the commit message format is unchanged"
    else
      fail "$tag: unexpected commit message" "$(git -C "$d" log -1 --pretty=%s)"
    fi
  done
}

extract_block stride-ideation-ideate 'git add -- "$TARGET_PATH"' "$TMP/ideate.sh" || exit 1
extract_block stride-ideation-ideate 'git add -- "$TARGET_PATH"' "$TMP/ideate-continue.sh" \
  "docs/ideation/2026-05-12T090000-dark-mode-toggle-requirements.md" || exit 1
extract_block stride-ideation-stridify 'git add -- "$TARGET_PATH"' "$TMP/stridify.sh" || exit 1

check_case "ideate Step 9" "$TMP/ideate.sh" "$REQ_DOC" "stride-ideation: requirements for dark-mode-toggle"
check_case "ideate Step 9 --continue" "$TMP/ideate-continue.sh" "$REQ_DOC" "stride-ideation: refine requirements for dark-mode-toggle"
check_case "stridify Step 8d" "$TMP/stridify.sh" "$BATCH" "stride-ideation: decomposition for dark-mode-toggle"

# The fix is the pathspec: without it, git commit records the pre-staged file
# too. This control case proves the scenario above really would sweep.
sed 's/ -- "\$TARGET_PATH" || exit 1/ || exit 1/' "$TMP/ideate.sh" > "$TMP/ideate-nopathspec.sh"
d="$TMP/control"
new_repo "$d" yes
( cd "$d" && bash -u "$TMP/ideate-nopathspec.sh" > /dev/null 2>&1 )
if git -C "$d" show --name-only --pretty=format: HEAD | grep -qx "$STAGED"; then
  pass "control: without the pathspec the pre-staged file is swept in"
else
  fail "control: the no-pathspec commit did not sweep, so the cases above prove nothing"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
