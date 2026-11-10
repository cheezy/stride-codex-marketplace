#!/usr/bin/env bash
# Interrupt smoke test for the stride-codex-exploratory-testing plugin.
#
# Runs lib/test-structure.ps1 in the background against scratch copies of the
# plugin and checks its exit status: a completed run keeps its own 0 or 1,
# and a run interrupted with SIGINT (during its first check, mid-run with no
# failure, after a failing check, or after its last check) or ended with
# SIGTERM never exits 0. An interrupted run must also leave nothing in its
# TMPDIR. Each signal is sent when a line the run prints appears, not after a
# fixed delay; the after-the-last-check case pauses its own copy before the
# summary. Skipped, exiting 0, when pwsh is not installed or on Windows,
# which has no SIGINT to send. Mirrors lib/test-interrupt.ps1.
#
# Exit code: 0 if every check passes or the test is skipped; 1 if any check
# fails; 130 if interrupted (INT); 143 if terminated (TERM).

set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

ok()   { PASS=$(( PASS + 1 )); printf '  ✓  %s\n' "$1"; }
nope() { FAIL=$(( FAIL + 1 )); printf '  ✗  %s\n     %s\n' "$1" "${2:-}"; }

printf 'stride-codex-exploratory-testing interrupt smoke test\n'
printf 'plugin root: %s\n\n' "$PLUGIN_ROOT"

case "${OSTYPE:-}" in
  msys* | cygwin* | win32*) printf 'skipped: no SIGINT to send on Windows\n'; exit 0 ;;
esac
if ! command -v pwsh >/dev/null 2>&1; then
  printf 'skipped: pwsh is not installed\n'
  exit 0
fi

CHILD=''
SCET_INT=$(mktemp -d "${TMPDIR:-/tmp}/scet-int.XXXXXX") || { printf 'could not create a scratch directory\n' >&2; exit 1; }
trap '[ -n "$CHILD" ] && kill -KILL "$CHILD" 2>/dev/null; rm -rf -- "$SCET_INT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Copies the plugin, without its .git directory, to $1.
copy_plugin() {
  mkdir -- "$1" && cp -R -- "$PLUGIN_ROOT/." "$1/" && rm -rf -- "$1/.git"
}

CLEAN="$SCET_INT/clean"
FAILING="$SCET_INT/failing"
PAUSED="$SCET_INT/paused"
copy_plugin "$CLEAN" || { printf 'could not copy the plugin\n' >&2; exit 1; }
copy_plugin "$FAILING" || { printf 'could not copy the plugin\n' >&2; exit 1; }
copy_plugin "$PAUSED" || { printf 'could not copy the plugin\n' >&2; exit 1; }
# One missing command-skill makes the failing copy fail an early check.
rm -f -- "$FAILING/skills/stride-exploratory-testing-charter/SKILL.md"
# The paused copy stops for ten seconds after its last check, before the
# summary, so a signal can land there.
PAUSE_LINE="Write-Host 'scet-int: paused before the summary'; Start-Sleep -Seconds 10"
awk -v p="$PAUSE_LINE" '/^# --- summary -/ { print p; next } { print }' \
  "$CLEAN/lib/test-structure.ps1" > "$PAUSED/lib/test-structure.ps1"

# Runs the copy at $1 with TMPDIR set to the new directory $2. With a trigger
# line $3 and a signal $4, sends the signal once that text appears in the
# run's output. Sets RUN_RC, RUN_OUT (the output file) and RUN_NOTE (empty
# unless the trigger was missed).
run_suite() {
  local root=$1 tmp=$2 trigger=${3:-} sig=${4:-} out="$2.out" i=0
  mkdir -- "$tmp" || return 1
  RUN_NOTE=''
  RUN_OUT=$out
  # Job control on for the launch: without it bash starts a background job
  # with SIGINT ignored, and the run would never see the interrupt.
  set -m
  TMPDIR="$tmp" pwsh -NoProfile -File "$root/lib/test-structure.ps1" > "$out" 2>&1 &
  CHILD=$!
  set +m
  if [ -n "$trigger" ]; then
    while ! grep -qF -- "$trigger" "$out"; do
      if ! kill -0 "$CHILD" 2>/dev/null; then RUN_NOTE='the run ended before the trigger line'; break; fi
      i=$(( i + 1 ))
      if [ "$i" -gt 600 ]; then RUN_NOTE='the trigger line did not appear within 30 seconds'; break; fi
      sleep 0.05
    done
    if [ -z "$RUN_NOTE" ]; then kill -s "$sig" "$CHILD" 2>/dev/null; fi
  fi
  wait "$CHILD"
  RUN_RC=$?
  CHILD=''
}

# Judges the last run for label $1. $2 is zero or one for a completed run,
# which must print its summary and exit with that status, or interrupted,
# which must print no summary (so the signal did stop it) and exit non-zero.
judge() {
  local label=$1 want=$2 summary=no
  if [ -n "$RUN_NOTE" ]; then nope "$label" "$RUN_NOTE (exit $RUN_RC)"; return; fi
  if grep -qE '^[0-9]+ passed, [0-9]+ failed$' "$RUN_OUT"; then summary=yes; fi
  case "$want" in
    zero) [ "$summary" = yes ] && [ "$RUN_RC" -eq 0 ] ;;
    one) [ "$summary" = yes ] && [ "$RUN_RC" -eq 1 ] ;;
    interrupted) [ "$summary" = no ] && [ "$RUN_RC" -ne 0 ] ;;
  esac && ok "$label" || nope "$label" "exit $RUN_RC, summary printed: $summary"
}

run_suite "$CLEAN" "$SCET_INT/t1"
judge 'a completed run of test-structure.ps1 exits 0 when every check passes' zero

run_suite "$FAILING" "$SCET_INT/t2"
judge 'a completed run of test-structure.ps1 exits 1 when a check fails' one

run_suite "$CLEAN" "$SCET_INT/t3" 'plugin root:' INT
judge 'test-structure.ps1 interrupted during its first check exits non-zero' interrupted

run_suite "$CLEAN" "$SCET_INT/t4" 'explorer card has exactly one start and one end marker' INT
judge 'test-structure.ps1 interrupted with no failure exits non-zero' interrupted

run_suite "$FAILING" "$SCET_INT/t5" 'is missing' INT
judge 'test-structure.ps1 interrupted after a failing check exits non-zero' interrupted

run_suite "$PAUSED" "$SCET_INT/t6" 'scet-int: paused before the summary' INT
judge 'test-structure.ps1 interrupted after its last check exits non-zero' interrupted

L='an interrupted test-structure.ps1 leaves nothing in its TMPDIR'
LEFT=''
for d in t3 t4 t5 t6; do
  for f in "$SCET_INT/$d"/* "$SCET_INT/$d"/.[!.]*; do
    [ -e "$f" ] && LEFT="$LEFT ${d}/${f##*/}"
  done
done
if [ -z "$LEFT" ]; then ok "$L"; else nope "$L" "left:${LEFT}"; fi

run_suite "$CLEAN" "$SCET_INT/t8" 'explorer card has exactly one start and one end marker' TERM
judge 'test-structure.ps1 ended by SIGTERM exits non-zero' interrupted

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
