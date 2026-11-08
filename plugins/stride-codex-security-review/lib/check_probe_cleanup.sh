#!/usr/bin/env bash
# Executed check of the probe block's cleanup on macOS (W2669).
#
# check_agent_contract.sh pins the probe block's text, line for line. This
# script runs that text: it takes the fenced block from the reproduction mode
# file with the pin's own awk, puts a harmless snippet of its own where the
# placeholder is, and runs it from a scratch git repository under /tmp with
# bash, sh and zsh (zsh -f), each started in a new session so no shell has a
# terminal, with BASH_ENV and ENV unset.
#
#   - Controls first. A sleep this script starts is seen alive, then gone once
#     killed by its recorded PID, so a "gone" result proves something; a
#     recorded sleep whose start time no longer matches the recorded one is not
#     signalled, and is once it matches again; zsh with
#     no terminal is shown unable to turn on job control, so the zsh case runs
#     the shell the block must not depend on; and the setsid snippet's probes,
#     run outside the box, are all allowed, so a "denied" inside it proves
#     something.
#   - A background snippet: the snippet starts a sleep in the background and
#     exits. Under every shell the sleep must be gone once the command exits.
#   - A locking snippet (W2671, from upstream 275e87a): it makes a nested
#     directory pair in the copy and takes every permission off both. Under
#     every shell the copy must still be gone once the command exits, which
#     only the trap's unlock, run inside the box, makes possible.
#   - A setsid snippet: the snippet forks a child that calls setsid() and so
#     leaves the snippet's process group. The mode file records that child as
#     an accepted residual, so this checks the residual and its stated reason:
#     the child outlives the command, and from inside the box it is refused a
#     write outside the copy, a read under HOME, a connection to the loopback
#     address and a signal to this script. It may create the copy's directory
#     again; this script removes that one directory, and ends the child by its
#     recorded PID if it is still alive.
#   - The perl guard: with the block's /usr/bin/perl test pointed at a path
#     that does not exist, the block must refuse to probe and run nothing.
#   - PATH (W2671, from upstream dc648f3): run from a scratch repository
#     holding planted tools named for the ones the block runs, with `.`, an
#     empty entry and relative entries on PATH, under every shell no planted
#     tool may run and the snippet must see only the absolute entries; with only
#     relative entries the block must refuse and run nothing. With the PATH line
#     taken out, the trap's cd / and its system PATH must keep a planted rm in
#     the copy from running, and with an absolute PATH entry holding a planted
#     rm first, the trap must not run it.
#   - TMPDIR (W2671 round 3, from upstream 97a3e32): with a relative TMPDIR
#     naming a directory in the scratch repository, under every shell the block
#     must refuse, run nothing and leave no copy there.
#   - The Linux socket search's decision, not the search: the block's search
#     line runs under sh with a stand-in `timeout` that prints a socket path,
#     prints nothing, or exits 124 or 1, and with a HOME holding a `*`, `?` or
#     `[`. Only the empty, successful search under a plain HOME may go on. The real GNU find under bwrap is not run here; the Linux run is a
#     separate manual task.
#
# Break-its (skipped with CHECK_PROBE_CLEANUP_CHILD set), on copies of the mode
# file made by a fixed-string replace (index and substr, never gsub, which
# would read an & in the replacement as the match): a mode file whose box
# starts the snippet without the perl process-group step, and one whose box
# does not exec sandbox-exec, must each fail the background case under bash,
# sh and zsh; one whose search ignores the search's own status must fail the
# timed-out search case, one that ignores what the search found must fail the
# socket case, and one that searches a home holding a pattern character must
# fail the glob-HOME case; one whose trap drops the unlock must fail the
# locked-directory case; one whose perl guard never refuses must fail the
# perl-guard case; one that keeps PATH's relative entries, or pipes to a bare
# cat, must fail the PATH case, one whose trap drops both its cd / and its
# system PATH must fail the trap case, one whose trap drops its system PATH must
# fail the absolute-entry case, and one without the TMPDIR refusal must fail the
# TMPDIR case (the trap's cd / alone is pinned by check_agent_contract.sh, since
# the system PATH already keeps the copy's planted rm from running); one whose
# profile drops (deny network*), and each one that
# turns the write-outside-the-copy, home-read or outside-signal deny into an
# allow, must fail that setsid denial; and a PATH with no sandbox-exec must print a skipped
# line, exit 0 and print no ok: line.
#
# Skipped, never passed, where sandbox-exec is absent (Linux), where
# /usr/bin/perl is absent (the box needs it, and it is the setsid snippet's
# interpreter), on a git older than 2.44, and when the block refuses because of
# HOME; any other refusal fails. Offline: the one connection is to 127.0.0.1
# port 9, and inside the box it is refused. Writes only under a mktemp -d
# directory under /tmp and, at most, the probe copies the block itself makes
# under $TMPDIR (else /tmp), removed on exit. Signals only PIDs it recorded and
# has not yet seen gone, and only while a PID is alive and its start time
# (ps -o lstart) still equals the one recorded with it, so a PID the system
# handed out again is never signalled; never a process by name. A process a
# snippet starts is recorded while the snippet still holds the command open,
# so its PID cannot yet have been handed out again; the snippet then waits for
# this script's release file, never more than 10 s. CI is unset for the block's
# runs: the snippets are this script's own, never reviewed code.
#
# Usage:
#   bash lib/check_probe_cleanup.sh [reproduction-mode-file]
#
# Exit code: 0 when every case holds or the check is skipped; 1 otherwise.
# Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="$SCRIPT_DIR/.."
MODE="${1:-$ROOT/skills/stride-security-review/modes/reproduction.md}"
PLACEHOLDER='<the one test or snippet that settles the question>'

if ! command -v sandbox-exec >/dev/null 2>&1; then
  echo "skipped: sandbox-exec is absent, so the macOS box cannot run here (not passed)"
  exit 0
fi
if [ ! -x /usr/bin/perl ]; then
  echo "skipped: /usr/bin/perl is absent; the macOS box needs it (not passed)"
  exit 0
fi
if ! git --no-lazy-fetch version >/dev/null 2>&1; then
  echo "skipped: git is older than 2.44, where the block refuses to probe (not passed)"
  exit 0
fi

fail=0
T="$(mktemp -d /tmp/stride-probe-cleanup.XXXXXX)" || { echo "FAIL: could not create a scratch directory"; exit 1; }
PIDS=
cleanup() {
  local p
  for p in $PIDS; do kill_recorded "$p"; done
  rm -rf "$T"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

record() { # $1=pid [$2=start time] -- noted with its start time, so a reused PID is never signalled
  PIDS="$PIDS $1"
  if [ "$#" -ge 2 ]; then
    printf '%s' "$2" > "$T/start.$1"
  else # taken now, while the process is the one meant: see run_held
    LC_ALL=C ps -o lstart= -p "$1" > "$T/start.$1" 2>/dev/null
  fi
}
forget() { # $1=pid -- seen gone, so never signalled again
  local p kept=
  for p in $PIDS; do [ "$p" = "$1" ] || kept="$kept $p"; done
  PIDS="$kept"
}
alive() { # $1=pid -- true while it runs (a zombie counts as gone)
  local s
  s="$(ps -o stat= -p "$1" 2>/dev/null)" || return 1
  case "$s" in *Z*|'') return 1 ;; esac
  return 0
}
same_start() { # $1=pid -- true while it is the process record() saw
  local now
  now="$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null)" || return 1
  [ -n "$now" ] && [ "$now" = "$(cat "$T/start.$1" 2>/dev/null)" ]
}
kill_recorded() { # $1=pid -- SIGKILL it only while it is alive and still the process recorded
  alive "$1" && same_start "$1" && kill -KILL "$1" 2>/dev/null
}
gone_within() { # $1=pid -- true once it has gone, polling for up to 3 s
  local i=0
  while [ "$i" -lt 30 ]; do
    if ! alive "$1"; then forget "$1"; return 0; fi
    sleep 0.1; i=$(( i + 1 ))
  done
  return 1
}
run_held() { # $@=a command writing $T/out -- runs it in the background, records the PID its
  # "started <pid>" line names while the snippet still holds the command open, then releases it
  local j i=0
  rm -f "$T/release" "$T/out"; STARTED=
  "$@" & j=$!
  while [ "$i" -lt 100 ] && kill -0 "$j" 2>/dev/null && ! grep -q '^started [0-9]' "$T/out" 2>/dev/null; do
    sleep 0.1; i=$(( i + 1 ))
  done
  STARTED="$(sed -n 's/^started \([0-9][0-9]*\)$/\1/p' "$T/out" 2>/dev/null)"
  [ -z "$STARTED" ] || record "$STARTED"
  : > "$T/release"
  wait "$j"
}
nosession() { # run $@ in a new session, with no terminal and no start-up file
  env -u CI -u BASH_ENV -u ENV /usr/bin/perl -e 'use POSIX (); POSIX::setsid(); exec { $ARGV[0] } @ARGV' "$@"
}
shell_argv() { # $1=bash|sh|zsh -- the shell's argv for -c
  case "$1" in zsh) echo "zsh -f" ;; *) echo "$1" ;; esac
}

block="$(awk '/^- \*\*Reproduce only in a temporary copy/ { f = 1; next }
  f && !b && /^  ```bash$/ { b = 1; next } b && /^  ```$/ { exit } b' "$MODE")"
case "$block" in
  *"$PLACEHOLDER"*) ;;
  *) echo "FAIL: the reproduction mode file holds a probe block with its snippet placeholder"; exit 1 ;;
esac

mkdir "$T/repo" "$T/outside" "$T/bin" && git -C "$T/repo" init -q && echo probe > "$T/repo/f.txt" || {
  echo "FAIL: could not make the scratch repository"; exit 1; }

run_text() { # $1=shell $2=block text $3=snippet -- output in $T/out
  local cmd
  cmd="$(SNIPPET="$3" PH="$PLACEHOLDER" awk '{ i = index($0, ENVIRON["PH"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["SNIPPET"] substr($0, i + length(ENVIRON["PH"])); print }' <<EOF
$2
EOF
)"
  # shellcheck disable=SC2046
  ( cd "$T/repo" && nosession $(shell_argv "$1") -c "$cmd" </dev/null >"$T/out" 2>&1 )
}
run_block() { run_text "$1" "$block" "$2"; }
refusal() { # prints the refusal line, if the block refused to probe
  grep -m1 'grading by reading' "$T/out"
}
home_refusal() { # true when the refusal is one about HOME, which is the caller's
  refusal | grep -qE 'HOME is unusable|HOME is not your home directory|probe copy is under HOME'
}
flat() { tr '\n' ' ' < "$T/out"; }

# --- controls -----------------------------------------------------------------
sleep 60 </dev/null >/dev/null 2>&1 & c=$!; record "$c"
if alive "$c" && { kill_recorded "$c" && wait "$c"; } 2>/dev/null; gone_within "$c"; then
  echo "ok: control: a recorded sleep is seen alive, then gone once killed"
else
  echo "FAIL: control: a recorded sleep is seen alive, then gone once killed"; fail=1
fi
# A PID whose start time no longer matches stands for one the system handed out
# again: it must not be signalled. The EXIT cleanup ends this sleep if the
# second half fails, since its start file then matches again.
sleep 60 </dev/null >/dev/null 2>&1 & c=$!; record "$c" 'not its start time'
kill_recorded "$c"; sleep 0.2
if alive "$c"; then
  echo "ok: control: a recorded PID whose start time no longer matches is not signalled"
else
  echo "FAIL: control: a recorded PID whose start time no longer matches is not signalled"; fail=1
fi
record "$c"
if { kill_recorded "$c" && wait "$c"; } 2>/dev/null; gone_within "$c"; then
  echo "ok: control: the same PID is signalled once its start time matches again"
else
  echo "FAIL: control: the same PID is signalled once its start time matches again"; fail=1
fi
SHELLS="bash sh"
if command -v zsh >/dev/null 2>&1; then
  if nosession zsh -f -c '(set -m) 2>/dev/null' </dev/null >/dev/null 2>&1; then
    echo "FAIL: control: zsh with no terminal cannot turn on job control -- it could, so the zsh case would prove nothing"; fail=1
  else
    echo "ok: control: zsh with no terminal cannot turn on job control"
    SHELLS="$SHELLS zsh"
  fi
else
  echo "skipped: zsh is absent, so the zsh case does not run (not passed)"
fi

# --- a background snippet -------------------------------------------------------
HOLD="i=0; while [ ! -e $T/release ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i+1)); done"
BG="/bin/sh -c 'sleep 60 </dev/null >/dev/null 2>&1 & echo \"started \$!\"; $HOLD'"
bg_case() { # $1=shell
  local s
  run_held run_block "$1" "$BG"
  if home_refusal; then
    echo "skipped: $1: the block refused to probe here: $(refusal) (not passed)"; return
  fi
  s="$STARTED"
  if [ -z "$s" ] || ! grep -qx 'snippet exit: 0' "$T/out"; then
    echo "FAIL: $1: the background snippet ran in the box -- output: $(flat)"; fail=1; return
  fi
  if [ ! -s "$T/start.$s" ]; then
    echo "FAIL: $1: the background snippet's process was recorded while the command was held open -- PID $s"; fail=1; return
  fi
  if gone_within "$s"; then
    echo "ok: $1: a background snippet's process is gone when the command exits"
  else
    echo "FAIL: $1: a background snippet's process is gone when the command exits -- PID $s survived"; fail=1
  fi
}
for sh in $SHELLS; do bg_case "$sh"; done

# --- a snippet that locks directories in the copy -------------------------------
# The trap must unlock them, inside the box, before rm -rf, or the copy stays.
LOCK="/bin/sh -c 'mkdir -p locked/inner && touch locked/inner/f && chmod 0 locked/inner && chmod 0 locked && echo \"copy \$TMPDIR\"'"
lock_case() { # $1=shell
  local c tmp
  run_block "$1" "$LOCK"
  if home_refusal; then
    echo "skipped: $1: the block refused to probe here: $(refusal) (not passed)"; return
  fi
  c="$(sed -n 's/^copy \(.*\)$/\1/p' "$T/out")"
  tmp="$(CDPATH= cd -P -- "${TMPDIR:-/tmp}" && pwd -P)"
  case "$c" in
    "$tmp"/stride-security-probe.??????) ;;
    *) echo "FAIL: $1: the locking snippet ran in the box -- output: $(flat)"; fail=1; return ;;
  esac
  if [ ! -e "$c" ] && grep -qx 'snippet exit: 0' "$T/out"; then
    echo "ok: $1: a copy holding locked directories is removed when the command exits"
  else
    echo "FAIL: $1: a copy holding locked directories is removed when the command exits -- $c is still there"; fail=1
    # Ours alone: it holds the scratch repository's file and the locked pair.
    [ ! -d "$c" ] || { find "$c" -type d -exec chmod u+rwx {} \; 2>/dev/null; rm -rf "$c"; }
  fi
}
for sh in $SHELLS; do lock_case "$sh"; done

# --- a setsid snippet: the accepted residual and its reason -----------------
# probes <write-target> <home> <pid> -- the perl body, run in a child that has
# left its parent's process group. Each probe prints allowed or denied, and
# denied only on EPERM, the sandbox's answer.
probes() {
  printf '%s' "use POSIX (); use Socket; use Errno; \$| = 1; defined(my \$c = fork) or die; if (\$c) { print \"started \$c\\n\"; my \$i = 0; select(undef, undef, undef, 0.1) while ! -e \"$T/release\" && \$i++ < 100; exit 0 } POSIX::setsid(); sleep 2; print -e \$ENV{TMPDIR} ? \"copy: present\\n\" : \"copy: removed\\n\"; print open(my \$f, \">\", \"$1\") || !\$!{EPERM} ? \"write: allowed\\n\" : \"write: denied\\n\"; print opendir(my \$d, \"$2\") || !\$!{EPERM} ? \"home: allowed\\n\" : \"home: denied\\n\"; socket(my \$s, PF_INET, SOCK_STREAM, 0) or die; print connect(\$s, sockaddr_in(9, INADDR_LOOPBACK)) || !\$!{EPERM} ? \"network: allowed\\n\" : \"network: denied\\n\"; print kill(0, $3) || !\$!{EPERM} ? \"signal: allowed\\n\" : \"signal: denied\\n\"; print mkdir(\$ENV{TMPDIR}) ? \"recreated: \$ENV{TMPDIR}\\n\" : \"recreated: no\\n\""
}
# The control: the same probes outside the box must all be allowed.
control_probes() { TMPDIR="$T/control-copy" /usr/bin/perl -e "$(probes "$T/control-write" "$HOME" "$$")" </dev/null >"$T/out" 2>&1; }
run_held control_probes
s="$STARTED"; [ -z "$s" ] || gone_within "$s" >/dev/null
if grep -qx 'write: allowed' "$T/out" && grep -qx 'home: allowed' "$T/out" \
  && grep -qx 'network: allowed' "$T/out" && grep -qx 'signal: allowed' "$T/out"; then
  echo "ok: control: outside the box the setsid probes are all allowed"
else
  echo "FAIL: control: outside the box the setsid probes are all allowed -- output: $(flat)"; fail=1
fi
rm -rf "$T/control-write" "$T/control-copy"

SETSID="/usr/bin/perl -e '$(probes "$T/outside/escaped" "$HOME" "$$")'"
run_held run_block bash "$SETSID"
if home_refusal; then
  echo "skipped: setsid: the block refused to probe here: $(refusal) (not passed)"
else
  s="$STARTED"
  if [ -n "$s" ] && [ -s "$T/start.$s" ]; then
    echo "ok: setsid: the survivor was recorded while the command was held open"
  else
    echo "FAIL: setsid: the survivor was recorded while the command was held open -- output: $(flat)"; fail=1
  fi
  if grep -qx 'snippet exit: 0' "$T/out" && grep -qx 'copy: removed' "$T/out"; then
    echo "ok: setsid: the survivor outlives the command (the accepted residual)"
  else
    echo "FAIL: setsid: the survivor outlives the command (the accepted residual) -- output: $(flat)"; fail=1
  fi
  for want in 'write: denied' 'home: denied' 'network: denied' 'signal: denied'; do
    if grep -qx "$want" "$T/out"; then
      echo "ok: setsid: the survivor reports $want"
    else
      echo "FAIL: setsid: the survivor reports $want -- output: $(flat)"; fail=1
    fi
  done
  [ ! -e "$T/outside/escaped" ] || { echo "FAIL: setsid: the survivor wrote outside the copy"; fail=1; }
  rec="$(sed -n 's/^recreated: \(.*\)$/\1/p' "$T/out")"
  tmp="$(CDPATH= cd -P -- "${TMPDIR:-/tmp}" && pwd -P)"
  case "$rec" in
    no|'') ;;
    "$tmp"/stride-security-probe.??????)
      rmdir "$rec" 2>/dev/null; echo "ok: setsid: the survivor could create only the copy's own directory again, now removed" ;;
    *) echo "FAIL: setsid: the survivor created $rec"; fail=1 ;;
  esac
  if [ -n "$s" ] && gone_within "$s"; then
    echo "ok: setsid: the survivor ended on its own, and this script holds no process"
  elif [ -n "$s" ]; then
    kill_recorded "$s"; forget "$s"
    echo "FAIL: setsid: the survivor did not end on its own; killed PID $s"; fail=1
  fi
fi

# --- the perl guard ---------------------------------------------------------------
noperl="$(printf '%s\n' "$block" | sed 's|\[ -x /usr/bin/perl \] |[ -x /nonexistent/perl ] |')"
if [ "$noperl" = "$block" ]; then
  echo "FAIL: the block holds the /usr/bin/perl guard"; fail=1
else
  run_text bash "$noperl" "/bin/sh -c 'echo ran'"
  if grep -q 'no /usr/bin/perl to give the snippet its own process group: grading by reading' "$T/out" \
    && ! grep -q 'snippet exit:' "$T/out" && ! grep -qx 'ran' "$T/out"; then
    echo "ok: without /usr/bin/perl the block refuses to probe and runs nothing"
  else
    echo "FAIL: without /usr/bin/perl the block refuses to probe and runs nothing -- output: $(flat)"; fail=1
  fi
fi

# --- PATH: no lookup reaches a file in the repository or the copy (W2671) -------
# The block finds every tool it runs outside the box on PATH: mktemp, git, tar
# and find from the project root, then tr, getent, cut, id, sed, sandbox-exec
# and, in its trap, rm from inside the copy; the cat at the end of its pipe
# would be found from the project root before the PATH line runs. Each scratch repository here holds
# planted tools of those names that leave a mark under $T and fail (the rm and
# cat also do their jobs, so the copy still goes and no write meets a closed pipe); the shells run by absolute path, since PATH
# holds relative entries. A planted tool is this script's own, never reviewed code.
abs_shell() { # $1=bash|sh|zsh
  case "$1" in bash) echo /bin/bash ;; sh) echo /bin/sh ;; zsh) echo "$(command -v zsh) -f" ;; esac
}
run_path() { # $1=shell $2=PATH $3=repository $4=block text $5=snippet -- output in $T/out
  local cmd
  cmd="$(SNIPPET="$5" PH="$PLACEHOLDER" awk '{ i = index($0, ENVIRON["PH"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["SNIPPET"] substr($0, i + length(ENVIRON["PH"])); print }' <<EOF
$4
EOF
)"
  # shellcheck disable=SC2046
  ( cd "$3" && /usr/bin/env -u CI -u BASH_ENV -u ENV PATH="$2" /usr/bin/perl -e 'use POSIX (); POSIX::setsid(); exec { $ARGV[0] } @ARGV' $(abs_shell "$1") -c "$cmd" </dev/null >"$T/out" 2>&1 )
}
plant() { # $1=path of a tool that marks $T/planted.<name> when it runs
  mkdir -p "$(dirname "$1")" || return 1
  case "$1" in
    */rm) printf '#!/bin/sh\n: > "%s/planted.rm"\nexec /bin/rm "$@"\n' "$T" > "$1" ;;
    */cat) printf '#!/bin/sh\n: > "%s/planted.cat"\nexec /bin/cat\n' "$T" > "$1" ;;
    *) printf '#!/bin/sh\n: > "%s/planted.%s"\nexit 1\n' "$T" "$(basename "$1")" > "$1" ;;
  esac
  chmod +x "$1"
}
planted() { # prints the planted tools that ran, if any
  local m
  for m in "$T"/planted.*; do [ -e "$m" ] && printf '%s ' "${m##*/planted.}"; done
}
mkdir "$T/prepo" "$T/trepo" && git -C "$T/prepo" init -q && git -C "$T/trepo" init -q \
  && echo probe > "$T/prepo/f.txt" && echo probe > "$T/trepo/f.txt" || {
  echo "FAIL: could not make the PATH scratch repositories"; exit 1; }
for t in cat mktemp git tar find tr getent cut id sed sandbox-exec rm bin/cat bin/mktemp bin/git '~/t/mktemp' '~/t/git'; do
  plant "$T/prepo/$t" || { echo "FAIL: could not plant $t"; exit 1; }
done
plant "$T/trepo/rm" || { echo "FAIL: could not plant rm"; exit 1; }
# The oracle: the harness's own absolute entries, taken without the block's loop.
want_path="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep '^/' | paste -sd: -)"
mixed=".:bin::~/t:$PATH:"
path_case() { # $1=shell
  local got
  rm -f "$T"/planted.*
  run_path "$1" "$mixed" "$T/prepo" "$block" "/bin/sh -c 'echo \"path \$PATH\"'"
  if home_refusal; then
    echo "skipped: $1: the block refused to probe here: $(refusal) (not passed)"; return
  fi
  got="$(sed -n 's/^path //p' "$T/out")"
  if [ -z "$(planted)" ] && grep -qx 'snippet exit: 0' "$T/out" && [ -n "$got" ] && [ "$got" = "$want_path" ]; then
    echo "ok: $1: relative PATH entries run nothing from the repository or the copy"
  else
    echo "FAIL: $1: relative PATH entries run nothing from the repository or the copy -- ran: $(planted)output: $(flat)"; fail=1
  fi
  rm -f "$T"/planted.*
  run_path "$1" ".:bin::~/t" "$T/prepo" "$block" "/bin/sh -c 'echo ran'"
  if [ -z "$(planted)" ] && grep -qx 'PATH holds no absolute entry: grading by reading' "$T/out" \
    && ! grep -q 'snippet exit:' "$T/out" && ! grep -qx 'ran' "$T/out"; then
    echo "ok: $1: a PATH with no absolute entry refuses to probe and runs nothing"
  else
    echo "FAIL: $1: a PATH with no absolute entry refuses to probe and runs nothing -- ran: $(planted)output: $(flat)"; fail=1
  fi
}
for sh in $SHELLS; do path_case "$sh"; done
# The trap's own defences: with the PATH line taken out, `.` stays on PATH, and
# only the trap's cd / and its system PATH keep the copy's planted rm from
# running.
keep_path="$(printf '%s\n' "$block" | sed '/PATH holds no absolute entry: grading by reading/d')"
if [ "$keep_path" = "$block" ]; then
  echo "FAIL: the block holds the PATH line"; fail=1
else
  trap_case() { # $1=shell
    local c tmp
    rm -f "$T"/planted.*
    run_path "$1" ".:$PATH" "$T/trepo" "$keep_path" "/bin/sh -c 'echo \"copy \$TMPDIR\"'"
    if home_refusal; then
      echo "skipped: $1: the block refused to probe here: $(refusal) (not passed)"; return
    fi
    c="$(sed -n 's/^copy \(.*\)$/\1/p' "$T/out")"
    tmp="$(CDPATH= cd -P -- "${TMPDIR:-/tmp}" && pwd -P)"
    case "$c" in
      "$tmp"/stride-security-probe.??????) ;;
      *) echo "FAIL: $1: the trap's move to / and its system PATH keep a planted rm in the copy from running -- the snippet did not run: $(flat)"; fail=1; return ;;
    esac
    if [ -z "$(planted)" ] && [ ! -e "$c" ] && grep -qx 'snippet exit: 0' "$T/out"; then
      echo "ok: $1: the trap's move to / and its system PATH keep a planted rm in the copy from running"
    else
      echo "FAIL: $1: the trap's move to / and its system PATH keep a planted rm in the copy from running -- ran: $(planted)output: $(flat)"; fail=1
      [ ! -d "$c" ] || rm -rf "$c"
    fi
  }
  for sh in $SHELLS; do trap_case "$sh"; done
fi
rm -f "$T"/planted.*

# The trap's system PATH: an absolute entry, first on PATH, holding a planted rm.
# Only the trap runs rm, so the plant must stay unrun while the copy still goes.
plant "$T/abin/rm" || { echo "FAIL: could not plant rm in an absolute entry"; exit 1; }
abs_trap_case() { # $1=shell
  local c tmp
  rm -f "$T"/planted.*
  run_path "$1" "$T/abin:$PATH" "$T/repo" "$block" "/bin/sh -c 'echo \"copy \$TMPDIR\"'"
  if home_refusal; then
    echo "skipped: $1: the block refused to probe here: $(refusal) (not passed)"; return
  fi
  c="$(sed -n 's/^copy \(.*\)$/\1/p' "$T/out")"
  tmp="$(CDPATH= cd -P -- "${TMPDIR:-/tmp}" && pwd -P)"
  case "$c" in
    "$tmp"/stride-security-probe.??????) ;;
    *) echo "FAIL: $1: the trap runs no tool from an absolute PATH entry -- the snippet did not run: $(flat)"; fail=1; return ;;
  esac
  if [ -z "$(planted)" ] && [ ! -e "$c" ] && grep -qx 'snippet exit: 0' "$T/out"; then
    echo "ok: $1: the trap runs no tool from an absolute PATH entry"
  else
    echo "FAIL: $1: the trap runs no tool from an absolute PATH entry -- ran: $(planted)output: $(flat)"; fail=1
    [ ! -d "$c" ] || rm -rf "$c"
  fi
}
for sh in $SHELLS; do abs_trap_case "$sh"; done
rm -f "$T"/planted.*

# --- TMPDIR: a relative one is refused (W2671 round 3) ---------------------------
# mktemp would name the copy relative to the project root, and the trap, from /,
# would then miss it and leave it in the working tree.
mkdir -p "$T/drepo/rel" && git -C "$T/drepo" init -q && echo probe > "$T/drepo/f.txt" || {
  echo "FAIL: could not make the TMPDIR scratch repository"; exit 1; }
tmpdir_case() { # $1=shell
  local cmd left
  cmd="$(SNIPPET="/bin/sh -c 'echo ran'" PH="$PLACEHOLDER" awk '{ i = index($0, ENVIRON["PH"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["SNIPPET"] substr($0, i + length(ENVIRON["PH"])); print }' <<EOF
$block
EOF
)"
  # shellcheck disable=SC2046
  ( cd "$T/drepo" && /usr/bin/env -u CI -u BASH_ENV -u ENV TMPDIR=rel /usr/bin/perl -e 'use POSIX (); POSIX::setsid(); exec { $ARGV[0] } @ARGV' $(abs_shell "$1") -c "$cmd" </dev/null >"$T/out" 2>&1 )
  left="$(ls -A "$T/drepo/rel")"
  if grep -qx 'TMPDIR is not an absolute path: grading by reading' "$T/out" && ! grep -q 'snippet exit:' "$T/out" \
    && ! grep -qx 'ran' "$T/out" && [ -z "$left" ]; then
    echo "ok: $1: a relative TMPDIR refuses to probe and leaves no copy in the repository"
  else
    echo "FAIL: $1: a relative TMPDIR refuses to probe and leaves no copy in the repository -- left: $left output: $(flat)"; fail=1
    rm -rf "$T/drepo/rel" && mkdir "$T/drepo/rel"
  fi
}
for sh in $SHELLS; do tmpdir_case "$sh"; done

# --- the Linux socket search's decision -------------------------------------
search="$(printf '%s\n' "$block" | grep -m1 '^      case "$h" in ')"
if [ -z "$search" ]; then
  echo "FAIL: the block holds the Linux socket search line"; fail=1
else
  cat > "$T/bin/timeout" <<'EOF'
#!/bin/sh
[ "$1 $2 $3 $4 $5" = "-k 2 10 find /" ] || { echo "timeout stand-in: unexpected argv: $*" >&2; exit 99; }
case "$STAND_IN" in
  socket) echo /nix/var/nix/daemon-socket/socket; exit 0 ;;
  empty) exit 0 ;;
  timedout) exit 124 ;;
  failed) exit 1 ;;
esac
exit 98
EOF
  chmod +x "$T/bin/timeout"
  for c in 'empty proceed /nonexistent-home' 'socket refuse /nonexistent-home' 'timedout refuse /nonexistent-home' \
           'failed refuse /nonexistent-home' 'empty refuse /nonexistent-home*' 'empty refuse /nonexistent-home?' \
           'empty refuse /nonexistent-[home]'; do
    set -- $c
    out="$(STAND_IN="$1" PATH="$T/bin:$PATH" h="$3" sh -c "$search
echo proceed" 2>&1)"
    case "$2:$out" in
      proceed:proceed) echo "ok: socket search: an empty, finished search goes on" ;;
      refuse:'a socket, a named pipe or a second path to HOME outside the hidden trees, or a search that did not finish: grading by reading')
        echo "ok: socket search: refuses to probe (search: $1, HOME $3)" ;;
      *) echo "FAIL: socket search (search: $1, HOME $3) -- wanted $2, got: $out"; fail=1 ;;
    esac
  done
fi

# --- break-its ------------------------------------------------------------------
if [ -z "${CHECK_PROBE_CLEANUP_CHILD:-}" ]; then
  B="$T/break"; mkdir "$B"
  bre() { # $1=label $2=from $3=to $4=out -- a copy of the mode file with one fixed-string replace
    # index and substr only: gsub would read & and \ in TO as the match and an escape
    FROM="$2" TO="$3" awk '{ out = ""; s = $0
      while ((i = index(s, ENVIRON["FROM"])) > 0) { out = out substr(s, 1, i - 1) ENVIRON["TO"]; s = substr(s, i + length(ENVIRON["FROM"])) }
      print out s }' "$MODE" > "$4"
    if cmp -s "$MODE" "$4"; then echo "FAIL: break-it: $1 -- the replace changed nothing"; fail=1; return 1; fi
  }
  expect_bg_fail() { # $1=label $2=mode file -- every shell's background case must fail
    local out rc sh missing=
    out="$(CHECK_PROBE_CLEANUP_CHILD=1 bash "$SELF" "$2" 2>&1)"; rc=$?
    for sh in $SHELLS; do
      printf '%s\n' "$out" | grep -qF "FAIL: $sh: a background snippet's process is gone when the command exits" || missing="$missing $sh"
    done
    if [ "$rc" -eq 1 ] && [ -z "$missing" ]; then
      echo "ok: break-it: $1"
    else
      echo "FAIL: break-it: $1 -- exit $rc, no failure under:$missing"; fail=1
    fi
  }
  if bre "no perl step" " /usr/bin/env -i /usr/bin/perl -e 'setpgrp(0, 0); exec { \$ARGV[0] } @ARGV; exit 127' \"\$@\"; }" ' "$@"; }' "$B/no-pgrp.md"; then
    expect_bg_fail "a box without the perl process-group step fails the background case in every shell" "$B/no-pgrp.md"
  fi
  if bre "no exec" 'box() { exec sandbox-exec -p' 'box() { sandbox-exec -p' "$B/no-exec.md"; then
    expect_bg_fail "a box that does not exec sandbox-exec fails the background case in every shell" "$B/no-exec.md"
  fi
  expect_child_fail() { # $1=label $2=mode file $3=the FAIL line the child must print
    local out rc
    out="$(CHECK_PROBE_CLEANUP_CHILD=1 bash "$SELF" "$2" 2>&1)"; rc=$?
    if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF -- "$3"; then
      echo "ok: break-it: $1"
    else
      echo "FAIL: break-it: $1 -- exit $rc, no line: $3"; fail=1
    fi
  }
  if bre "search status ignored" ';; esac && [ -z "$s" ] ||' ';; esac; [ -z "$s" ] ||' "$B/search.md"; then
    expect_child_fail "a socket search whose failure is ignored fails the timed-out case" "$B/search.md" \
      "FAIL: socket search (search: timedout, HOME /nonexistent-home) -- wanted refuse"
  fi
  if bre "search result ignored" ';; esac && [ -z "$s" ] ||' ';; esac && true ||' "$B/found.md"; then
    expect_child_fail "a socket search whose result is ignored fails the socket case" "$B/found.md" \
      "FAIL: socket search (search: socket, HOME /nonexistent-home) -- wanted refuse"
  fi
  if bre "pattern home searched" 's=glob ;;' 's= ;;' "$B/glob.md"; then
    expect_child_fail "a home holding a pattern character searched anyway fails the glob-HOME case" "$B/glob.md" \
      "FAIL: socket search (search: empty, HOME /nonexistent-home*) -- wanted refuse"
  fi
  if bre "no unlock" ' ! command -v box >/dev/null 2>&1 || (box env -i PATH="$PATH" find "$r" -type d -exec chmod u+rwx {} \;) >/dev/null 2>&1;' '' "$B/unlock.md"; then
    expect_child_fail "a trap without the unlock fails the locked-directory case" "$B/unlock.md" \
      "FAIL: bash: a copy holding locked directories is removed when the command exits"
  fi
  if bre "perl guard defanged" "[ -x /usr/bin/perl ] || { echo" "[ -x /usr/bin/perl ] || true || { echo" "$B/guard.md"; then
    expect_child_fail "a perl guard that never refuses fails the perl-guard case" "$B/guard.md" \
      "FAIL: without /usr/bin/perl the block refuses to probe and runs nothing"
  fi
  if bre "no network denial" '(deny network*)' '' "$B/net.md"; then
    expect_child_fail "a profile without the network denial fails the setsid case" "$B/net.md" \
      "FAIL: setsid: the survivor reports network: denied"
  fi
  # Each allows only what the check's own snippet does: a write under $T, a
  # listing of HOME and a signal 0 to this script.
  for c in 'write|(deny file-write* (require-all|(allow file-write* (require-all' \
           'home|(deny file-read* (subpath|(allow file-read* (subpath' \
           'signal|(deny signal (require-not|(allow signal (require-not'; do
    k="${c%%|*}"; rest="${c#*|}"; from="${rest%%|*}"; to="${rest#*|}"
    if bre "no $k denial" "$from" "$to" "$B/$k.md"; then
      expect_child_fail "a profile that allows the $k probe fails the setsid case" "$B/$k.md" \
        "FAIL: setsid: the survivor reports $k: denied"
    fi
  done
  if bre "PATH kept" '[ -n "$x" ] && PATH="$x" ||' '[ -n "$x" ] ||' "$B/path.md"; then
    expect_child_fail "a block that keeps PATH's relative entries fails the PATH case" "$B/path.md" \
      "FAIL: bash: relative PATH entries run nothing from the repository or the copy"
  fi
  if bre "bare cat" '2>&1 | /bin/cat' '2>&1 | cat' "$B/cat.md"; then
    expect_child_fail "a pipe to a bare cat fails the PATH case" "$B/cat.md" \
      "FAIL: bash: relative PATH entries run nothing from the repository or the copy"
  fi
  if bre "trap stays in the copy" 'trap "" PIPE; cd /; PATH=/usr/bin:/bin:/usr/sbin:/sbin;' 'trap "" PIPE;' "$B/cd.md"; then
    expect_child_fail "a trap that starts its lookups in the copy on the caller's PATH fails the trap case" "$B/cd.md" \
      "FAIL: bash: the trap's move to / and its system PATH keep a planted rm in the copy from running"
  fi
  if bre "trap on the caller's PATH" 'cd /; PATH=/usr/bin:/bin:/usr/sbin:/sbin; [ -z' 'cd /; [ -z' "$B/syspath.md"; then
    expect_child_fail "a trap that searches the caller's PATH fails the absolute-entry case" "$B/syspath.md" \
      "FAIL: bash: the trap runs no tool from an absolute PATH entry"
  fi
  if bre "no TMPDIR refusal" "case \"\${TMPDIR:-/tmp}\" in /*) ;; *) echo 'TMPDIR is not an absolute path: grading by reading'; exit 1 ;; esac; " '' "$B/tmpdir.md"; then
    expect_child_fail "a block without the relative-TMPDIR refusal fails the TMPDIR case" "$B/tmpdir.md" \
      "FAIL: bash: a relative TMPDIR refuses to probe and leaves no copy in the repository"
  fi
  mkdir "$T/nosbx"
  ln -s /usr/bin/dirname "$T/nosbx/dirname" && ln -s /usr/bin/basename "$T/nosbx/basename"
  out="$(PATH="$T/nosbx" CHECK_PROBE_CLEANUP_CHILD=1 /bin/bash "$SELF" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF 'skipped: sandbox-exec is absent' \
    && ! printf '%s\n' "$out" | grep -q '^ok:' && ! printf '%s\n' "$out" | grep -q 'command not found'; then
    echo "ok: break-it: no sandbox-exec on PATH prints skipped, not passed"
  else
    echo "FAIL: break-it: no sandbox-exec on PATH prints skipped, not passed -- exit $rc: $out"; fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "probe cleanup: FAILED"
  exit 1
fi
echo "probe cleanup: every process the block can prove it started was gone, and the setsid survivor stayed in the box"
