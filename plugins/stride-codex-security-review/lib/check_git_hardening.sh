#!/usr/bin/env bash
# Offline integration check for the git hardening (upstream D377, W2643).
#
# check_agent_contract.sh pins the text of the five git forms, the probe's
# guard line and its copy step. This script runs that text against a real git.
# Ported from the Copilot port's scripts/check_git_hardening.sh
# (stride-copilot-security-review 69f3c67), with three additions:
#
#   - a sparse partial clone whose remote URL is an ssh:// URL and whose
#     core.sshCommand is a marker program, so a lazy fetch would run it;
#   - a stand-in for a git older than 2.44 (a shim that rejects
#     --no-lazy-fetch with exit 129 and reports 2.43.0), against which the
#     guard line must refuse to probe and every form must run nothing;
#   - every inherited GIT_* variable, PAGER and SSH_ASKPASS unset first, so a
#     caller's GIT_DIR, GIT_EXTERNAL_DIFF or GIT_NO_LAZY_FETCH cannot change
#     what the controls show.
#
# The main scratch repository's own config names a marker program for
# core.fsmonitor, diff.external, a diff driver command, a textconv driver and
# gpg.program (with log.showSignature and a signed commit). Each of the five
# forms runs exactly as the README lists them, and the guard and the copy step
# exactly as the agent's probe block has them; the check fails if any marker
# program ran. Unflagged controls must make every marker program run, so a
# scratch repository that could not have caught a configured program fails the
# check instead of passing it.
#
# Not covered: core.pager (no terminal is attached, so git never pages) and a
# submodule's diff programs. The forms carry --no-pager and --submodule=short
# for those, pinned as text by check_agent_contract.sh. The shim stands in for
# an old git; no real git older than 2.44 was run.
#
# Needs git 2.44 or later (--no-lazy-fetch); with an older git it prints a
# skip line and exits 0, as the agent itself would run nothing there. Offline:
# no network (the ssh:// remote is never contacted; its sshCommand is the
# marker), no Codex CLI, no token. It runs git directly, not through Codex.
# Writes only under a mktemp -d directory, removed on exit, with HOME and the
# global and system git config pointed away from the caller's. It runs only
# text from this plugin's own README and agent, which check_agent_contract.sh
# pins.
#
# Usage:
#   bash lib/check_git_hardening.sh [reproduction-mode-file] [readme-file]
#   (defaults: skills/stride-security-review/modes/reproduction.md and
#    README.md beside this lib/)
#
# Exit code: 0 when no marker ran and every control fired (or git is too
# old); 1 otherwise. Bash 3.2 compatible.

set -u

for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset PAGER SSH_ASKPASS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="$SCRIPT_DIR/.."
# W2636: the probe block moved from the agent core into the reproduction mode
# file the command skill sends.
AGENT="${1:-$ROOT/skills/stride-security-review/modes/reproduction.md}"
README="${2:-$ROOT/README.md}"
fail=0

for f in "$AGENT" "$README"; do
  [ -f "$f" ] && [ -r "$f" ] || { echo "FAIL: file not found or not readable: $f"; exit 1; }
done

gv="$(git --version 2>/dev/null)" || { echo "FAIL: git is not installed"; exit 1; }
gv="${gv#git version }"
IFS=. read -r gmaj gmin _ <<EOF
$gv
EOF
case "$gmaj:$gmin" in
  ( *[!0-9:]* | :* | *: ) echo "FAIL: cannot read the git version: $gv"; exit 1 ;;
esac
if [ "$gmaj" -lt 2 ] || { [ "$gmaj" -eq 2 ] && [ "$gmin" -lt 44 ]; }; then
  echo "skip: git $gv is older than 2.44, which rejects --no-lazy-fetch; the agent runs nothing there"
  exit 0
fi
REALGIT="$(command -v git)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-git-hardening.XXXXXX")" || { echo "FAIL: no temporary directory"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM

# The five forms, as the README lists them, and the probe's two git lines, as
# the agent's probe block has them.
forms="$(grep -F 'and five git forms' "$README" | grep -oE '`git --no-pager[^`]*`' | tr -d '`')"
nforms="$(printf '%s\n' "$forms" | grep -c .)"
if [ "$nforms" -ne 5 ]; then
  echo "FAIL: the README lists five git forms -- found $nforms"; fail=1
fi
probe="$(awk '/^- \*\*Reproduce only in a temporary copy/ { f = 1; next }
  f && !b && /^  ```bash$/ { b = 1; next } b && /^  ```$/ { exit } b' "$AGENT")"
guard="$(printf '%s\n' "$probe" | grep -E '^    git .*version ' | sed 's/^    //')"
copy="$(printf '%s\n' "$probe" | grep -E '^    git .*ls-files .*tar ' | sed 's/^    //')"
[ -n "$guard" ] || { echo "FAIL: the probe block has a git version guard line"; fail=1; }
[ -n "$copy" ] || { echo "FAIL: the probe block has a git ls-files copy step"; fail=1; }

# The scratch repository and its marker programs. HOME and the global and
# system config are moved away, so only the repository's own config applies.
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
M="$TMP/markers"; mkdir "$M"
for k in fsmonitor external diffcmd textconv gpg; do
  printf '#!/bin/sh\necho ran >> "%s/%s"\nexit 0\n' "$M" "$k" > "$TMP/$k.sh"
  chmod +x "$TMP/$k.sh"
done
# The lazy fetch's marker fails, so a fetch it starts goes no further.
printf '#!/bin/sh\necho ran >> "%s/ssh"\nexit 1\n' "$M" > "$TMP/ssh.sh"
chmod +x "$TMP/ssh.sh"
R="$TMP/repo"; mkdir "$R"
(
  cd "$R" || exit 1
  git init -q &&
  git config user.email check@example.invalid && git config user.name check &&
  git config commit.gpgsign false &&
  printf 'a\n' > f.txt && printf 'b\n' > g.y &&
  printf '*.txt diff=x\n*.y diff=z\n' > .gitattributes &&
  git add -A && git commit -q -m one &&
  printf 'a2\n' > f.txt && printf 'b2\n' > g.y && git add -A &&
  tree="$(git write-tree)" && parent="$(git rev-parse HEAD)" &&
  # A second commit carrying a signature header, so log.showSignature would
  # call gpg.program on it.
  obj="$(printf 'tree %s\nparent %s\nauthor check <c> 1700000000 +0000\ncommitter check <c> 1700000000 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n iQEzBAABCAAdFiEE\n -----END PGP SIGNATURE-----\n\ntwo\n' "$tree" "$parent" | git hash-object -t commit -w --stdin)" &&
  git update-ref HEAD "$obj" &&
  printf 'a3\n' > f.txt && git add f.txt &&
  git config core.fsmonitor "$TMP/fsmonitor.sh" &&
  git config diff.external "$TMP/external.sh" &&
  git config diff.z.command "$TMP/diffcmd.sh" &&
  git config diff.x.textconv "$TMP/textconv.sh" &&
  git config gpg.program "$TMP/gpg.sh" &&
  git config log.showSignature true
) || { echo "FAIL: could not build the scratch repository"; exit 1; }
C1="$(git -C "$R" rev-parse HEAD~1)"; C2="$(git -C "$R" rev-parse HEAD)"

# The sparse partial clone. A clean source repository is cloned with
# --filter=blob:none --sparse, so the blobs under sub/ (a skip-worktree
# .gitignore among them) are never fetched; only then is the clone's remote
# pointed at an ssh:// URL whose core.sshCommand is the marker, so any lazy
# fetch runs it and fails.
S="$TMP/source"; P="$TMP/partial"; mkdir "$S"
(
  cd "$S" || exit 1
  git init -q &&
  git config user.email check@example.invalid && git config user.name check &&
  git config commit.gpgsign false && git config uploadpack.allowFilter true &&
  mkdir sub && printf 'x\n' > top.txt && printf '*.log\n' > sub/.gitignore && printf 'h\n' > sub/h.txt &&
  git add -A && git commit -q -m one
) &&
git clone -q --no-local --filter=blob:none --sparse "file://$S" "$P" >/dev/null 2>&1 &&
git -C "$P" config remote.origin.url "ssh://stride-check.invalid/r.git" &&
git -C "$P" config core.sshCommand "$TMP/ssh.sh" ||
  { echo "FAIL: could not build the sparse partial clone"; exit 1; }
if [ -e "$P/sub/h.txt" ]; then
  echo "FAIL: the sparse partial clone checked out sub/, so it cannot show a lazy fetch"; fail=1
fi
# An untracked file under sub/ makes --others walk sub/, so --exclude-standard
# reads the skip-worktree sub/.gitignore, whose blob the clone lacks.
mkdir -p "$P/sub" && printf 'u\n' > "$P/sub/u.txt"

markers() { ls "$M" | tr '\n' ' ' | sed 's/ $//'; }
# No glob: the form loop below runs with globbing off.
reset_markers() { rm -rf "$M" && mkdir "$M"; }

# run_quiet <label> <command...> -- in the scratch repository the command must
# exit 0 and run no marker
run_quiet() {
  local label="$1" rc got; shift
  reset_markers
  ( cd "$R" && "$@" ) </dev/null >/dev/null 2>&1; rc=$?
  got="$(markers)"
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: $label -- exit $rc"; fail=1
  elif [ -n "$got" ]; then
    echo "FAIL: $label -- ran a repository-configured program: $got"; fail=1
  else
    echo "ok: $label"
  fi
}

# run_no_marker <dir> <label> <command...> -- the command must run no marker;
# its exit status is not judged, because a blob the clone lacks is an error
# once lazy fetching is off
run_no_marker() {
  local dir="$1" label="$2" got; shift 2
  reset_markers
  ( cd "$dir" && "$@" ) </dev/null >/dev/null 2>&1
  got="$(markers)"
  if [ -n "$got" ]; then
    echo "FAIL: $label -- ran a repository-configured program: $got"; fail=1
  else
    echo "ok: $label"
  fi
}

# run_control <dir> <label> <want-markers> <command...> -- every named marker
# must run
run_control() {
  local dir="$1" label="$2" want="$3" k miss=""; shift 3
  reset_markers
  ( cd "$dir" && "$@" ) </dev/null >/dev/null 2>&1
  for k in $want; do [ -e "$M/$k" ] || miss="$miss $k"; done
  if [ -n "$miss" ]; then
    echo "FAIL: control: $label -- did not run:$miss, so the check could not see it"; fail=1
  else
    echo "ok: control: $label"
  fi
}

# The controls first: without them a quiet form proves nothing.
run_control "$R" "an unflagged commit-to-commit diff runs diff.external and the diff driver" "external diffcmd" git diff "$C1" "$C2"
run_control "$R" "an unflagged log -p runs textconv and gpg.program" "textconv gpg" git -c diff.external= log -p -2
run_control "$R" "an unflagged ls-files -m runs core.fsmonitor" "fsmonitor" git ls-files -m
# W2668: --modified, ls-files' long form of -m, and --modif, an abbreviation
# of it, run core.fsmonitor as -m does.
run_control "$R" "an unflagged ls-files --modified runs core.fsmonitor" "fsmonitor" git ls-files --modified
run_control "$R" "an unflagged ls-files --modif runs core.fsmonitor" "fsmonitor" git ls-files --modif
# The marker cannot show that git took a spelling: a spelling git rejects
# (--modifx) runs core.fsmonitor too, before its option parser exits. The exit
# status can: with core.fsmonitor off, each spelling git takes exits 0, and the
# rejected one does not, so an exit 0 here is git taking the spelling.
for sp in --modified --modif --m; do
  if ( cd "$R" && git -c core.fsmonitor=false ls-files "$sp" ) </dev/null >/dev/null 2>&1; then
    echo "ok: git takes ls-files $sp"
  else
    echo "FAIL: git takes ls-files $sp -- it exited non-zero"; fail=1
  fi
done
if ( cd "$R" && git -c core.fsmonitor=false ls-files --modifx ) </dev/null >/dev/null 2>&1; then
  echo "FAIL: git rejects ls-files --modifx -- it exited 0, so an exit 0 shows nothing"; fail=1
else
  echo "ok: git rejects ls-files --modifx, so an exit 0 above is git taking the spelling"
fi
run_control "$R" "the pre-D377 copy step runs core.fsmonitor" "fsmonitor" \
  sh -c 'git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -xf - -C "$1"' sh "$(mktemp -d "$TMP/copy.XXXXXX")"
run_control "$P" "an unflagged read of a blob the partial clone lacks runs core.sshCommand" "ssh" git cat-file -p HEAD:sub/h.txt
run_control "$P" "an unflagged show in the partial clone runs core.sshCommand" "ssh" git show HEAD
run_control "$P" "the pre-D377 copy step in the partial clone runs core.sshCommand" "ssh" \
  sh -c 'git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -xf - -C "$1"' sh "$(mktemp -d "$TMP/copy.XXXXXX")"

# The five README forms. Each is split into words with globbing off; the
# placeholder <commit> <commit> becomes two real commits, and log gets -p so
# it prints a patch, the shape a reviewer would run.
# form_args <form> <c1> <c2> -- sets args to the form's words, with globbing
# already off in the caller
form_args() {
  local w c1="$2" c2="$3"
  args=()
  for w in $1; do
    case "$w" in
      ( '<commit>' ) if [ "${#args[@]}" -gt 0 ] && [ "${args[${#args[@]}-1]}" = "$c1" ] && [ "$c1" != "$c2" ]; then args+=("$c2"); else args+=("$c1"); fi ;;
      ( * ) args+=("$w") ;;
    esac
  done
}
short() { printf '%s' "$1" | sed 's/.*gpg.x509.program=false //'; }

set -f
while IFS= read -r form; do
  [ -n "$form" ] || continue
  form_args "$form" "$C1" "$C2"
  case " $form " in ( *' log '* ) args+=("-p" "-2") ;; esac
  run_quiet "the README form runs no repository-configured program: $(short "$form")" "${args[@]}"
done <<EOF
$forms
EOF

# The same forms in the sparse partial clone, on its one commit: none may
# start a lazy fetch.
PC="$(git -C "$P" rev-parse HEAD)"
while IFS= read -r form; do
  [ -n "$form" ] || continue
  form_args "$form" "$PC" "$PC"
  case " $form " in ( *' log '* | *' show '* ) args+=("-p" "-1") ;; esac
  run_no_marker "$P" "the README form starts no lazy fetch in a sparse partial clone: $(short "$form")" "${args[@]}"
done <<EOF
$forms
EOF
set +f

# The probe's guard line and copy step, as the agent has them.
if [ -n "$guard" ]; then
  run_quiet "the probe's guard line passes and runs no repository-configured program" sh -c "$guard"
fi
if [ -n "$copy" ]; then
  D="$(mktemp -d "$TMP/copy.XXXXXX")"
  run_quiet "the probe's copy step runs no repository-configured program" env d="$D" sh -c "$copy"
  if [ -f "$D/f.txt" ] && [ -f "$D/.gitattributes" ]; then
    echo "ok: the probe's copy step copies the files"
  else
    echo "FAIL: the probe's copy step copies the files -- the copy is missing files"; fail=1
  fi
  run_no_marker "$P" "the probe's copy step starts no lazy fetch in a sparse partial clone" \
    env d="$(mktemp -d "$TMP/copy.XXXXXX")" sh -c "$copy"
fi

# A git older than 2.44, by a shim: it reports 2.43.0, rejects --no-lazy-fetch
# the way such a git rejects an unknown option (exit 129, running nothing),
# and hands every other call to the real git.
O="$TMP/oldgit"; mkdir "$O"
cat > "$O/git" <<SHIM
#!/bin/sh
for a in "\$@"; do
  case "\$a" in --no-lazy-fetch) echo 'unknown option: --no-lazy-fetch' >&2; exit 129 ;; esac
done
case "\${1:-}" in --version|version) echo 'git version 2.43.0'; exit 0 ;; esac
exec '$REALGIT' "\$@"
SHIM
chmod +x "$O/git"
if [ -n "$guard" ]; then
  out="$(cd "$R" && PATH="$O:$PATH" sh -c "$guard" </dev/null 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qxF 'git before 2.44: grading by reading'; then
    echo "ok: the probe's guard line refuses a git before 2.44"
  else
    echo "FAIL: the probe's guard line refuses a git before 2.44 -- exit $rc"; fail=1
  fi
fi
set -f
while IFS= read -r form; do
  [ -n "$form" ] || continue
  form_args "$form" "$C1" "$C2"
  reset_markers
  ( cd "$R" && PATH="$O:$PATH" "${args[@]}" ) </dev/null >/dev/null 2>&1; rc=$?
  got="$(markers)"
  if [ "$rc" -ne 0 ] && [ -z "$got" ]; then
    echo "ok: the README form runs nothing on a git before 2.44: $(short "$form")"
  else
    echo "FAIL: the README form runs nothing on a git before 2.44: $(short "$form") -- exit $rc, markers: ${got:-none}"; fail=1
  fi
done <<EOF
$forms
EOF
set +f

# Self-tests: each break must make this script fail with the named line.
if [ -z "${CHECK_GIT_HARDENING_CHILD:-}" ]; then
  B="$TMP/broken"; mkdir "$B"
  expect_fail() { # $1=label $2=needle $3=agent $4=readme
    local out rc
    out="$(CHECK_GIT_HARDENING_CHILD=1 bash "$SELF" "$3" "$4" </dev/null 2>&1)"; rc=$?
    if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF -- "$2"; then
      echo "ok: self-test: $1"
    else
      echo "FAIL: self-test: $1 -- exit $rc, or output lacks: $2"; fail=1
    fi
  }
  # bre <file> <from> <to> <out> -- fixed-string replace, refusing a no-op
  bre() {
    FROM="$2" TO="$3" awk 'BEGIN { from = ENVIRON["FROM"]; to = ENVIRON["TO"] }
      { l = $0; o = ""
        while ((i = index(l, from)) > 0) { o = o substr(l, 1, i - 1) to; l = substr(l, i + length(from)) }
        print o l }' "$1" > "$4"
    ! cmp -s "$1" "$4" || { echo "FAIL: self-test: the break did not land: $2"; fail=1; }
  }
  RAN=' -- ran a repository-configured program:'
  bre "$README" 'diff --cached --no-ext-diff --no-textconv --submodule=short`' 'diff --cached --no-ext-diff --submodule=short`' "$B/r1.md"
  expect_fail "a README diff --cached form without --no-textconv fails" \
    "program: diff --cached --no-ext-diff --submodule=short$RAN" "$AGENT" "$B/r1.md"
  # log and show run no external diff unless asked (git's --ext-diff), so the
  # break that shows is the flag added, not --no-ext-diff dropped.
  bre "$README" 'show --no-ext-diff --no-textconv' 'show --ext-diff --no-textconv' "$B/r2.md"
  expect_fail "a README show form with --ext-diff fails" \
    "program: show --ext-diff --no-textconv --submodule=short --no-show-signature$RAN" "$AGENT" "$B/r2.md"
  # The gpg.program override alone already keeps the marker from running, so
  # the log break takes both layers away: the override and --no-show-signature.
  bre "$README" '-c gpg.x509.program=false log --no-ext-diff --no-textconv --submodule=short --no-show-signature`' '-c gpg.x509.program=false log --no-ext-diff --no-textconv --submodule=short --show-signature`' "$B/r3a.md"
  bre "$B/r3a.md" '-c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false log' '-c gpg.ssh.program=false -c gpg.x509.program=false log' "$B/r3.md"
  expect_fail "a README log form with --show-signature and no gpg.program override fails" \
    "program: log --no-ext-diff --no-textconv --submodule=short --show-signature$RAN gpg" "$AGENT" "$B/r3.md"
  bre "$README" '`git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false ls-files`' '`git --no-pager --no-lazy-fetch -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false ls-files`' "$B/r4.md"
  expect_fail "a README ls-files form without the core.fsmonitor override fails" \
    "program: ls-files$RAN fsmonitor" "$AGENT" "$B/r4.md"
  bre "$README" 'git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false show' 'git --no-pager -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false show' "$B/r5.md"
  expect_fail "a README show form without --no-lazy-fetch fails in the partial clone" \
    "FAIL: the README form starts no lazy fetch in a sparse partial clone: show --no-ext-diff --no-textconv --submodule=short --no-show-signature$RAN ssh" "$AGENT" "$B/r5.md"
  bre "$AGENT" 'git --no-lazy-fetch -c core.fsmonitor=false ls-files -z' 'git ls-files -z' "$B/a1.md"
  expect_fail "the pre-D377 copy step fails" \
    "FAIL: the probe's copy step runs no repository-configured program$RAN fsmonitor" "$B/a1.md" "$README"
  bre "$AGENT" 'git --no-lazy-fetch -c core.fsmonitor=false ls-files -z' 'git -c core.fsmonitor=false ls-files -z' "$B/a4.md"
  expect_fail "a copy step without --no-lazy-fetch fails in the partial clone" \
    "FAIL: the probe's copy step starts no lazy fetch in a sparse partial clone$RAN ssh" "$B/a4.md" "$README"
  grep -vF 'git --no-lazy-fetch version' "$AGENT" > "$B/a2.md"
  expect_fail "a probe block without the guard line fails" \
    "FAIL: the probe block has a git version guard line" "$B/a2.md" "$README"
  bre "$AGENT" 'git --no-lazy-fetch version >/dev/null' 'git version >/dev/null' "$B/a3.md"
  expect_fail "a guard line that an old git passes fails" \
    "FAIL: the probe's guard line refuses a git before 2.44 -- exit 0" "$B/a3.md" "$README"
  out="$(PATH="$O:$PATH" CHECK_GIT_HARDENING_CHILD=1 bash "$SELF" </dev/null 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF 'skip: git 2.43.0 is older than 2.44'; then
    echo "ok: self-test: a git before 2.44 skips the check"
  else
    echo "FAIL: self-test: a git before 2.44 skips the check -- exit $rc"; fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "git hardening: FAILED"
  exit 1
fi
echo "git hardening: no repository-configured program ran"
