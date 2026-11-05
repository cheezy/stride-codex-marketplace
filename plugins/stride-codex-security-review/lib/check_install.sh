#!/usr/bin/env bash
# check_install.sh -- install from a local clone and check where the rule files land.
#
# W2636 (upstream W2285): the stride-security-review command skill reads its
# eleven packs and three mode files from its own directory and sends them to
# the agent, so both installers must copy skills/stride-security-review/packs/
# and modes/ beside the installed SKILL.md. This script copies this plugin's
# tree into a scratch git repository, points the installer's hard-coded GitHub
# URL at it with a url.<base>.insteadOf entry held in git's environment, runs
# install.sh --project, re-runs it, then runs it in global mode under a scratch
# HOME, and compares every installed rule file byte for byte with its source.
# When pwsh is on PATH it does the same with install.ps1 -Project; otherwise it
# says SKIPPED. A self-test removes the rule-file loop from a copy of install.sh
# and checks that this script then fails.
#
# Offline: no network (the URL is rewritten to a file:// clone), no Codex CLI.
# Writes only under one mktemp -d directory, removed on exit, with HOME and
# git's global and system config pointed away from the caller's.
#
# Usage:  bash lib/check_install.sh [plugin-root]   (default: the parent of lib/)
# Exit code: 0 when every check holds; 1 otherwise.
set -u
export LC_ALL=C

for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
SRC_ROOT="$(cd "${1:-$SCRIPT_DIR/..}" && pwd)"
URL="https://github.com/cheezy/stride-codex-security-review.git"
SK="skills/stride-security-review"
RULE_NAMES="packs/android.md packs/django.md packs/express.md packs/ios.md packs/phoenix.md packs/rails.md packs/react-nextjs.md packs/web-defense.md packs/supply-chain.md packs/ci-cd.md packs/agentic.md modes/considerations.md modes/result-file.md modes/reproduction.md"
fail=0

command -v git > /dev/null 2>&1 || { echo "FAIL: git not found"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/check-install.XXXXXX")" || { echo "FAIL: could not create a temporary directory"; exit 1; }
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

# make_src <dest> -- a committed scratch repository holding this plugin's tree
make_src() {
  local dest="$1" p
  mkdir -p "$dest"
  for p in .codex-plugin agents skills lib fixtures README.md AGENTS.md CHANGELOG.md LICENSE install.sh install.ps1; do
    [ -e "$SRC_ROOT/$p" ] && cp -R "$SRC_ROOT/$p" "$dest/"
  done
  git -C "$dest" init -q && git -C "$dest" add -A &&
    git -C "$dest" -c user.name=check-install -c user.email=check-install@example.invalid \
      -c commit.gpgsign=false commit -q -m snapshot
}

# in_env <src> <home> <cmd...> -- run with the clone URL rewritten to <src>
in_env() {
  local src="$1" home="$2"
  shift 2
  HOME="$home" USERPROFILE="$home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$src/.insteadOf" GIT_CONFIG_VALUE_0="$URL" \
    "$@"
}

# check_dest <label> <installed-skills-dir> <src> -- every rule file landed, unchanged
check_dest() {
  local label="$1" dir="$2" src="$3" rn missing=0
  for rn in $RULE_NAMES; do
    if ! cmp -s "$src/$SK/$rn" "$dir/stride-security-review/$rn"; then
      echo "FAIL: $label -- $rn missing or different"; missing=1
    fi
  done
  [ -f "$dir/stride-security-review/SKILL.md" ] || { echo "FAIL: $label -- SKILL.md missing"; missing=1; }
  [ ! -e "$dir/stride-security-review/packs/packs" ] || { echo "FAIL: $label -- nested packs/packs"; missing=1; }
  [ ! -e "$dir/security-review-essentials/packs" ] || { echo "FAIL: $label -- the essentials skill gained packs/"; missing=1; }
  [ "$missing" -eq 0 ] && echo "ok: $label"
  return "$missing"
}

# run_sh <src> -- project install, re-install, global install
run_sh() {
  local src="$1" proj home out
  proj="$(mktemp -d "$T/proj.XXXXXX")"; home="$(mktemp -d "$T/home.XXXXXX")"
  out="$(cd "$proj" && in_env "$src" "$home" bash "$src/install.sh" --project 2>&1)" ||
    { echo "FAIL: install.sh --project exits 0 -- $(printf '%s' "$out" | tail -n 1)"; return 1; }
  check_dest "install.sh --project installs every pack and mode file beside the skill" "$proj/.agents/skills" "$src" || return 1
  out="$(cd "$proj" && in_env "$src" "$home" bash "$src/install.sh" --project 2>&1)" ||
    { echo "FAIL: a second install.sh --project exits 0"; return 1; }
  check_dest "a second install.sh --project leaves the same files" "$proj/.agents/skills" "$src" || return 1
  out="$(cd "$proj" && in_env "$src" "$home" bash "$src/install.sh" 2>&1)" ||
    { echo "FAIL: install.sh (global) exits 0"; return 1; }
  check_dest "install.sh (global) installs every pack and mode file beside the skill" "$home/.agents/skills" "$src" || return 1
}

make_src "$T/src" || { echo "FAIL: could not build the scratch clone"; exit 1; }
run_sh "$T/src" || fail=1

if command -v pwsh > /dev/null 2>&1; then
  proj="$(mktemp -d "$T/proj.XXXXXX")"; home="$(mktemp -d "$T/home.XXXXXX")"
  if out="$(cd "$proj" && in_env "$T/src" "$home" pwsh -NoProfile -NonInteractive -File "$T/src/install.ps1" -Project 2>&1)"; then
    check_dest "install.ps1 -Project installs every pack and mode file beside the skill" "$proj/.agents/skills" "$T/src" || fail=1
  else
    echo "FAIL: install.ps1 -Project exits 0 -- $(printf '%s' "$out" | tail -n 1)"; fail=1
  fi
else
  echo "SKIPPED: install.ps1 -Project (pwsh not on PATH)"
fi

# Self-test: an install.sh without the rule-file loop must fail this script.
if [ -z "${CHECK_INSTALL_CHILD:-}" ]; then
  make_src "$T/broken" >/dev/null 2>&1 || { echo "FAIL: self-test: could not build the broken clone"; exit 1; }
  awk '/^  for sub in packs modes; do$/ { print "  for sub in; do"; next } { print }' \
    "$T/broken/install.sh" > "$T/broken/install.sh.new" && mv "$T/broken/install.sh.new" "$T/broken/install.sh"
  git -C "$T/broken" -c user.name=check-install -c user.email=check-install@example.invalid \
    -c commit.gpgsign=false commit -q -am broken
  if grep -qF 'for sub in packs modes; do' "$T/broken/install.sh"; then
    echo "FAIL: self-test: the broken install.sh still holds the rule-file loop"; fail=1
  elif out="$(CHECK_INSTALL_CHILD=1 bash "$SELF" "$T/broken" 2>&1)"; then
    echo "FAIL: self-test: an install.sh without the rule-file loop fails -- exit 0, wanted 1"; fail=1
  elif ! printf '%s\n' "$out" | grep -qF "FAIL: install.sh --project installs every pack and mode file"; then
    echo "FAIL: self-test: an install.sh without the rule-file loop fails -- output lacks the install.sh FAIL line"; fail=1
  else
    echo "ok: self-test: an install.sh without the rule-file loop fails"
  fi
fi

if [ "$fail" -eq 0 ]; then echo "install check: all checks passed"; else echo "install check: FAILED"; fi
exit "$fail"
