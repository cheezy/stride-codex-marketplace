#!/usr/bin/env bash
# Tests for the stride-ideation-ideate argument parse documented in
# skills/stride-ideation-ideate/SKILL.md Step 1: the --input <file> brain-dump
# seed, the --continue <path> / --continue=<path> forms and the --profile
# values (W2198; ported from stride-copilot-ideation, plus the --profile
# cases). The platform file-read / question UI is only available inside a
# live Codex CLI session, so this test embeds reference shell implementations
# of the documented Step 1 parse, the file-exists validation, and the Step 4c
# read-only invariant, and exercises them.
#
# The reference implementations MUST stay consistent with Step 1 (the flag
# parse + validation) and Step 4c (the read-only seed read) in
# skills/stride-ideation-ideate/SKILL.md, and with the PowerShell mirror
# lib/test-ideate-input.ps1. If you edit one, edit all.
#
# Run:
#   ./lib/test-ideate-input.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

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

# --- reference flag parser -------------------------------------------------
#
# Mirrors SKILL.md Step 1: parse --continue and --input (each in both
# `--flag <value>` and `--flag=<value>` forms), consuming their tokens;
# everything left over is the TOPIC remainder. Prints four lines:
#   line 1 = CONTINUE_PATH, line 2 = INPUT_PATH, line 3 = trimmed remainder,
#   line 4 = error (continue-missing when --continue has no value: bare and
#            trailing, `--continue=`, or followed by another flag).

parse_flags() {
  local args="$1"
  local continue_path="" input_path="" out="" err=""
  # shellcheck disable=SC2206
  local toks=( $args )
  local n=${#toks[@]} i=0
  while [ "$i" -lt "$n" ]; do
    local t="${toks[$i]}"
    case "$t" in
      --continue)
        if [ $(( i + 1 )) -lt "$n" ] && [ "${toks[$(( i + 1 ))]#--}" = "${toks[$(( i + 1 ))]}" ]; then
          i=$(( i + 1 )); continue_path="${toks[$i]}"
        else
          err=continue-missing
        fi
        ;;
      --continue=*)
        continue_path="${t#--continue=}"
        [ -n "$continue_path" ] || err=continue-missing
        ;;
      --input)
        i=$(( i + 1 ))
        if [ "$i" -lt "$n" ]; then input_path="${toks[$i]}"; fi
        ;;
      --input=*)
        input_path="${t#--input=}"
        ;;
      *)
        out="${out:+$out }$t"
        ;;
    esac
    i=$(( i + 1 ))
  done
  printf '%s\n%s\n%s\n%s\n' "$continue_path" "$input_path" "$out" "$err"
}

# --- reference --input validation ------------------------------------------
#
# Mirrors SKILL.md Step 1's INPUT_PATH existence check: unset is OK (no seed);
# a set-but-missing path is a one-line error + non-zero stop; an existing
# regular file is OK.

validate_input_path() {
  local path="$1"
  if [ -z "$path" ]; then
    return 0
  fi
  if [ ! -f "$path" ]; then
    echo "stride-ideation: --input file not found: $path" >&2
    return 1
  fi
  return 0
}

# --- reference read-only seed read -----------------------------------------
#
# Mirrors SKILL.md Step 4c: read the file read-only into a variable. It MUST
# NOT write, move, or modify the file in any way.

read_input_notes() {
  local path="$1"
  if [ -z "$path" ]; then
    printf ''
    return 0
  fi
  cat "$path"
}

# === fixtures ==============================================================

NOTES="$TMP/notes.md"
cat > "$NOTES" <<'EOF'
# Rough notes

We want a daily digest so approvers stop missing requests.
Assume people read email. SMTP relay is fine.
EOF
NOTES_SHA_BEFORE="$(shasum -a 256 "$NOTES" | awk '{print $1}')"

EMPTY_NOTES="$TMP/empty.md"
: > "$EMPTY_NOTES"

# The parse-only cases pass these relative names, not the temp-dir fixtures:
# the reference parser never touches the filesystem, and a temp dir whose path
# holds a space would split into two tokens.
ARG_NOTES="notes.md"
ARG_PRIOR="docs/ideation/2026-05-12T120000-thing-requirements.md"

# === case 1: --input <path> and --input=<path> both parse =================

p_space="$(parse_flags "--input $ARG_NOTES my topic here")"
p_equals="$(parse_flags "--input=$ARG_NOTES my topic here")"

if [ "$(printf '%s' "$p_space" | sed -n 2p)" = "$ARG_NOTES" ] \
   && [ "$(printf '%s' "$p_equals" | sed -n 2p)" = "$ARG_NOTES" ]; then
  pass "case 1: --input <path> and --input=<path> both parse to INPUT_PATH (AC1)"
else
  fail "case 1: --input parse wrong" \
    "space=$(printf '%s' "$p_space" | sed -n 2p) equals=$(printf '%s' "$p_equals" | sed -n 2p)"
fi

if [ "$(printf '%s' "$p_space" | sed -n 3p)" = "my topic here" ] \
   && [ "$(printf '%s' "$p_equals" | sed -n 3p)" = "my topic here" ]; then
  pass "case 1: the --input tokens are consumed and the TOPIC remainder is preserved"
else
  fail "case 1: remainder wrong after --input consumption" \
    "space=$(printf '%s' "$p_space" | sed -n 3p) equals=$(printf '%s' "$p_equals" | sed -n 3p)"
fi

# === case 2: absence leaves INPUT_PATH empty, topic intact ================

p_none="$(parse_flags "just a plain topic")"
if [ -z "$(printf '%s' "$p_none" | sed -n 2p)" ] \
   && [ "$(printf '%s' "$p_none" | sed -n 3p)" = "just a plain topic" ]; then
  pass "case 2: no --input leaves INPUT_PATH empty and TOPIC intact"
else
  fail "case 2: absence handling wrong" "$(printf '%s' "$p_none" | tr '\n' '|')"
fi

# === case 3: validation — existing file OK, missing file errors (AC1) =====

if validate_input_path "$NOTES" 2>/dev/null; then
  pass "case 3: validate accepts an existing --input file (rc 0)"
else
  fail "case 3: validate rejected an existing file"
fi

if validate_input_path "$TMP/does-not-exist.md" 2>"$TMP/verr"; then
  fail "case 3: validate accepted a missing file (should fail)"
else
  if grep -qF -- "--input file not found: $TMP/does-not-exist.md" "$TMP/verr"; then
    pass "case 3: missing --input file -> one-line error naming the path + non-zero (edge case)"
  else
    fail "case 3: missing-file error message wrong" "$(cat "$TMP/verr")"
  fi
fi

# === case 4: unset INPUT_PATH validates OK (no seed) ======================

if validate_input_path "" 2>/dev/null; then
  pass "case 4: unset INPUT_PATH validates cleanly (no-seed session)"
else
  fail "case 4: unset INPUT_PATH was rejected"
fi

# === case 5: read is read-only — file byte-for-byte unchanged (AC3) =======

seed="$(read_input_notes "$NOTES")"
NOTES_SHA_AFTER="$(shasum -a 256 "$NOTES" | awk '{print $1}')"
if [ "$NOTES_SHA_BEFORE" = "$NOTES_SHA_AFTER" ]; then
  pass "case 5: --input file is byte-for-byte unchanged after the read (read-only invariant)"
else
  fail "case 5: --input file was modified by the read (pitfall violated)"
fi
if printf '%s' "$seed" | grep -qF "daily digest"; then
  pass "case 5: read_input_notes returns the file contents as seed material"
else
  fail "case 5: seed content not returned" "$seed"
fi
if [ -f "$NOTES" ]; then
  pass "case 5: --input file still exists at its original path (not moved)"
else
  fail "case 5: --input file was moved/removed (pitfall violated)"
fi

# === case 6: --input and --continue parse independently (precedence, AC4) ==

p_both="$(parse_flags "--continue $ARG_PRIOR --input $ARG_NOTES leftover topic")"
b_continue="$(printf '%s' "$p_both" | sed -n 1p)"
b_input="$(printf '%s' "$p_both" | sed -n 2p)"
b_rem="$(printf '%s' "$p_both" | sed -n 3p)"
if [ "$b_continue" = "$ARG_PRIOR" ] && [ "$b_input" = "$ARG_NOTES" ] && [ "$b_rem" = "leftover topic" ]; then
  pass "case 6: --continue and --input populate independently when both passed (AC4)"
else
  fail "case 6: combined parse wrong" \
    "continue=$b_continue input=$b_input rem=$b_rem"
fi

# === case 7: empty --input file is valid (falls back to a full session) ===

if validate_input_path "$EMPTY_NOTES" 2>/dev/null; then
  empty_seed="$(read_input_notes "$EMPTY_NOTES")"
  if [ -z "$empty_seed" ]; then
    pass "case 7: empty --input file validates and yields empty seed (full session fallback, edge case)"
  else
    fail "case 7: empty file produced non-empty seed" "$empty_seed"
  fi
else
  fail "case 7: empty --input file was rejected by validation"
fi

# === case 8: --continue accepts both shapes, split on the first = only ======

expect_continue() {  # expect_continue <label> <args> <want-path> <want-err>
  local p got_path got_err
  p="$(parse_flags "$2")"
  got_path="$(printf '%s\n' "$p" | sed -n 1p)"
  got_err="$(printf '%s\n' "$p" | sed -n 4p)"
  if [ "$got_path" = "$3" ] && [ "$got_err" = "$4" ]; then pass "$1"; else fail "$1" "path=[$got_path] err=[$got_err]"; fi
}
expect_continue "case 8a: --continue <path> sets CONTINUE_PATH" "--continue $ARG_PRIOR" "$ARG_PRIOR" ""
expect_continue "case 8b: --continue=<path> sets CONTINUE_PATH" "--continue=$ARG_PRIOR" "$ARG_PRIOR" ""
expect_continue "case 8c: --continue=<path> keeps an = inside the path" "--continue=docs/a=b-requirements.md" "docs/a=b-requirements.md" ""
expect_continue "case 8d: --continue= with an empty value is an error" "--continue= topic" "" "continue-missing"
expect_continue "case 8e: a bare trailing --continue is an error" "topic --continue" "" "continue-missing"
expect_continue "case 8f: --continue followed by a flag never takes the flag as its path" "--continue --input $ARG_NOTES" "" "continue-missing"
p8="$(parse_flags "--continue=$ARG_PRIOR --input=$ARG_NOTES")"
if [ "$(printf '%s\n' "$p8" | sed -n 1p)" = "$ARG_PRIOR" ] && [ "$(printf '%s\n' "$p8" | sed -n 2p)" = "$ARG_NOTES" ]; then
  pass "case 8g: --continue=<path> and --input=<path> parse together"
else
  fail "case 8g: combined = forms" "$p8"
fi

SKILL_MD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills/stride-ideation-ideate/SKILL.md"
if grep -qF 'for the `--continue=<path>` form' "$SKILL_MD" \
   && grep -qF 'stride-ideation: --continue requires a path to a prior -requirements.md doc' "$SKILL_MD"; then
  pass "case 8h: SKILL.md Step 1 documents --continue=<path> and the missing-value error"
else
  fail "case 8h: SKILL.md Step 1 is missing a --continue rule this test mirrors"
fi

# === case 9: --profile accepts the four values and fails fast otherwise ===
#
# Mirrors SKILL.md Step 1's --profile rule: both `--profile <name>` and
# `--profile=<name>`; anything other than lean, product, discovery or
# lean-startup (including a missing value) is a one-line error naming the
# value and the accepted set, and a stop before any session work. Prints the
# profile (empty when absent) or the error on stderr with rc 1.

parse_profile() {
  # shellcheck disable=SC2206
  local toks=( $1 )
  local n=${#toks[@]} i=0 profile="" seen=no
  while [ "$i" -lt "$n" ]; do
    case "${toks[$i]}" in
      --profile)
        seen=yes
        if [ $(( i + 1 )) -lt "$n" ] && [ "${toks[$(( i + 1 ))]#--}" = "${toks[$(( i + 1 ))]}" ]; then
          i=$(( i + 1 )); profile="${toks[$i]}"
        fi
        ;;
      --profile=*) seen=yes; profile="${toks[$i]#--profile=}" ;;
    esac
    i=$(( i + 1 ))
  done
  if [ "$seen" = yes ]; then
    case "$profile" in
      lean|product|discovery|lean-startup) ;;
      *)
        echo "stride-ideation: unknown --profile value '$profile'; expected one of: lean, product, discovery, lean-startup" >&2
        return 1
        ;;
    esac
  fi
  printf '%s\n' "$profile"
}

expect_profile() {
  local label="$1" args="$2" want="$3" got
  if got="$(parse_profile "$args" 2>/dev/null)" && [ "$got" = "$want" ]; then
    pass "$label"
  else
    fail "$label" "got=[$got]"
  fi
}
expect_profile "case 9a: --profile <name> sets PROFILE" "--profile product approval flows" "product"
expect_profile "case 9b: --profile=<name> sets PROFILE" "--profile=lean-startup approval flows" "lean-startup"
expect_profile "case 9c: no --profile leaves PROFILE empty (the recommendation question runs)" "approval flows" ""
for bad in "--profile=foo topic" "--profile Lean topic" "topic --profile" "--profile= topic"; do
  if err="$(parse_profile "$bad" 2>&1 >/dev/null)"; then
    fail "case 9d: an unknown or missing --profile value fails fast: $bad" "no error"
  elif printf '%s' "$err" | grep -q "^stride-ideation: unknown --profile value '.*'; expected one of: lean, product, discovery, lean-startup\$"; then
    pass "case 9d: an unknown or missing --profile value fails fast: $bad"
  else
    fail "case 9d: an unknown or missing --profile value fails fast: $bad" "$err"
  fi
done
if grep -qF "stride-ideation: unknown --profile value 'foo'; expected one of: lean, product, discovery, lean-startup" "$SKILL_MD"; then
  pass "case 9e: SKILL.md Step 1 documents the --profile error this test mirrors"
else
  fail "case 9e: SKILL.md Step 1 is missing the --profile error this test mirrors"
fi

# === summary ==============================================================

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
