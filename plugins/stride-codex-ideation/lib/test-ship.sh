#!/usr/bin/env bash
# Tests for lib/ship.py (the stride-ideation-stridify skill's Step 3
# preflight, the --batch payload check, and Steps 9-10 POST + render) and for
# the shell-safe output of lib/read_auth.py.
#
# curl is replaced by a PATH-prepended fake (a small Python script) that
# records its argv and environment, captures the -K config it reads from
# stdin, copies the --data-binary payload it was handed and reports its file
# mode, and answers with a canned status/body/stderr/exit taken from FAKE_*
# env vars. No network access is needed. Every run of ship.py gets its own
# TMPDIR so the tests can assert that no temp file outlives the script.
#
# lib/test-ship.ps1 is the PowerShell twin and runs the same cases.
#
# Run:
#   ./lib/test-ship.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIP="${SCRIPT_DIR}/ship.py"
READ_AUTH="${SCRIPT_DIR}/read_auth.py"

# A fake value only — the tests assert it never escapes into argv or output.
TOKEN="stride_dev_SHIP_TEST_TOKEN_9f3k"

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

# --- fixtures -----------------------------------------------------------------

cat > "$TMP/auth.md" <<EOF
# Stride API Authentication

- **API URL:** \`https://stride.example\`
- **Local API Token:** \`stride_dev_LOCAL_TOKEN_SHOULD_NOT_MATCH\`
- **API Token:** \`$TOKEN\`
EOF

cat > "$TMP/auth-local-only.md" <<'EOF'
- **API URL:** `https://stride.example`
- **Local API Token:** `stride_dev_LOCAL_ONLY_TOKEN_abc`
EOF

cat > "$TMP/batch.json" <<'EOF'
{
  "source_spec": "docs/ideation/x-requirements.md",
  "source_spec_sha256": "abc123",
  "decomposition_notes": "claim order: G1 first",
  "goals": [
    {
      "title": "Goal one",
      "type": "goal",
      "created_by_agent": "Codex CLI",
      "tasks": [{"title": "Task one", "type": "work"}]
    }
  ]
}
EOF

# The shape the server really returns (docs/api/post_tasks_batch.md).
cat > "$TMP/created.json" <<'EOF'
{"success": true, "total": 1, "goals": [
  {"goal": {"id": 1, "identifier": "G77", "title": "Goal one", "type": "goal"},
   "child_tasks": [{"id": 2, "identifier": "W901", "title": "Task one"},
                   {"id": 3, "identifier": "D12", "title": "Task two"}]}]}
EOF

# The flat shape older responses and the old Step 10 renderer used.
cat > "$TMP/created-flat.json" <<'EOF'
{"data": {"goals": [{"identifier": "G78", "title": "Flat goal",
  "tasks": [{"identifier": "W902", "title": "Flat task"}]}]}}
EOF

printf '{"success": true, "total": 0, "goals": []}' > "$TMP/empty-goals.json"
printf '{"success": true, "goals": [{"goal": {"title": "no identifier"}, "child_tasks": []}]}' > "$TMP/no-ident.json"

# A dev server's debug error page echoes the request headers, token included.
printf '<html><dt>authorization</dt><dd>Bearer %s</dd><p>raw %s</p><p>other Bearer abc.DEF-123</p></html>' "$TOKEN" "$TOKEN" > "$TMP/500-debug.html"

printf '{"error":"Validation failed","details":{"goals":["is invalid"]}}' > "$TMP/422.json"
printf '<html>Bad gateway</html>' > "$TMP/502.html"
printf '<html>moved</html>' > "$TMP/302.html"
printf 'OK, but this is not JSON' > "$TMP/notjson.txt"
printf '[1, 2, 3]' > "$TMP/list.json"
python3 -c 'import sys; sys.stdout.write("{\"error\":\"" + "x" * 200000 + "\"}")' > "$TMP/big.json"

# --- fake curl ----------------------------------------------------------------

mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env python3
# Fake curl for lib/test-ship.sh. Behaviour comes from FAKE_* env vars.
import os, shutil, sys, time
log = os.environ["FAKE_LOG_DIR"]
args = sys.argv[1:]
with open(os.path.join(log, "argv"), "w") as fp:
    fp.write("".join(a + "\n" for a in args))
out = cfg = data = ""
i = 0
while i < len(args):
    if args[i] in ("-o", "-K", "--data-binary") and i + 1 < len(args):
        if args[i] == "-o": out = args[i + 1]
        elif args[i] == "-K": cfg = args[i + 1]
        else: data = args[i + 1]
        i += 1
    i += 1
if cfg == "-":
    with open(os.path.join(log, "config"), "wb") as fp:
        fp.write(sys.stdin.buffer.read())
with open(os.path.join(log, "env-token"), "w") as fp:
    fp.write("yes\n" if "STRIDE_API_TOKEN" in os.environ else "no\n")
if data.startswith("@"):
    shutil.copyfile(data[1:], os.path.join(log, "payload"))
    with open(os.path.join(log, "payload.mode"), "w") as fp:
        fp.write(oct(os.stat(data[1:]).st_mode & 0o777) + "\n")
open(os.path.join(log, "started"), "w").close()
if os.environ.get("FAKE_SLEEP"):
    time.sleep(float(os.environ["FAKE_SLEEP"]))
if os.environ.get("FAKE_STDERR"):
    sys.stderr.write(os.environ["FAKE_STDERR"] + "\n")
if out and os.environ.get("FAKE_BODY"):
    shutil.copyfile(os.environ["FAKE_BODY"], out)
sys.stdout.write(os.environ.get("FAKE_CODE", "200"))
sys.exit(int(os.environ.get("FAKE_EXIT", "0")))
EOF
chmod +x "$TMP/bin/curl"

# run_ship <case> <args...> — runs ship.py against the fake curl with an
# isolated TMPDIR. Leaves $C/out, $C/err, $C/rc, $C/log/* and $C/tmpdir.
run_ship() {
  local name="$1"; shift
  C="$TMP/case-$name"
  mkdir -p "$C/log" "$C/tmpdir"
  PATH="$TMP/bin:$PATH" TMPDIR="$C/tmpdir" FAKE_LOG_DIR="$C/log" \
    STRIDE_AUTH_FILE="${AUTH_FILE_OVERRIDE:-$TMP/auth.md}" \
    python3 "$SHIP" "$@" > "$C/out" 2> "$C/err"
  echo "$?" > "$C/rc"
}

rc_is() {
  local label="$1" want="$2" got
  got="$(cat "$C/rc")"
  if [ "$got" = "$want" ]; then pass "$label"; else fail "$label" "exit $got, want $want; stderr: $(head -c 400 "$C/err")"; fi
}

contains() {
  local label="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file"; then pass "$label"; else fail "$label" "missing '$needle' in $(basename "$file")"; fi
}

lacks() {
  local label="$1" file="$2" needle="$3"
  if [ -f "$file" ] && grep -qF -- "$needle" "$file"; then fail "$label" "found '$needle' in $(basename "$file")"; else pass "$label"; fi
}

no_temp_left() {
  local left
  left="$(ls -A "$C/tmpdir")"
  if [ -z "$left" ]; then pass "$1"; else fail "$1" "left behind: $left"; fi
}

never_posted() {
  if [ ! -s "$C/log/argv" ]; then pass "$1"; else fail "$1" "curl ran"; fi
}

no_token_anywhere() {
  if grep -qF -- "$TOKEN" "$C/out" "$C/err" "$C/log/argv" 2>/dev/null; then
    fail "$1" "token found in stdout, stderr or curl argv"
  else
    pass "$1"
  fi
}

# verbatim_body <label> <header-line> <body-file>: stderr is exactly the
# header line, the body bytes, and one newline.
verbatim_body() {
  { printf '%s\n' "$2"; cat "$3"; echo; } > "$C/expected.err"
  if cmp -s "$C/expected.err" "$C/err"; then pass "$1"; else fail "$1" "stderr is not header + verbatim body"; fi
}

# --- read_auth.py: shell-safe output -------------------------------------------

mkdir -p "$TMP/evaldir"
cat > "$TMP/auth-amp.md" <<'EOF'
- **API URL:** `https://stride.example/p?a=1&b=2`
- **API Token:** `stride_dev_AMP_abc`
EOF
out="$(cd "$TMP/evaldir" && eval "$(python3 "$READ_AUTH" "$TMP/auth-amp.md")" && printf '%s' "$STRIDE_API_URL")"
if [ "$out" = "https://stride.example/p?a=1&b=2" ]; then
  pass "read_auth: a URL containing & evals back unchanged"
else
  fail "read_auth: & URL did not round-trip" "$out"
fi

cat > "$TMP/auth-subst.md" <<'EOF'
- **API URL:** `https://stride.example/$(touch${IFS}pwned)x;touch${IFS}pwned2`
- **API Token:** `stride_dev_SUBST_abc`
EOF
out="$(cd "$TMP/evaldir" && eval "$(python3 "$READ_AUTH" "$TMP/auth-subst.md")" && printf '%s' "$STRIDE_API_URL")"
# shellcheck disable=SC2016  # the literal string is the point
if [ "$out" = 'https://stride.example/$(touch${IFS}pwned)x;touch${IFS}pwned2' ]; then
  pass "read_auth: command-substitution and ; in a URL eval back literally"
else
  fail "read_auth: substitution URL did not round-trip" "$out"
fi
if [ ! -e "$TMP/evaldir/pwned" ] && [ ! -e "$TMP/evaldir/pwned2" ]; then
  pass "read_auth: eval of a hostile URL executes nothing"
else
  fail "read_auth: eval of the auth output executed a command"
fi

auth_out="$(python3 "$READ_AUTH" "$TMP/auth.md")"
if [ "$auth_out" = "$(printf 'STRIDE_API_URL=https://stride.example\nSTRIDE_API_TOKEN=%s' "$TOKEN")" ]; then
  pass "read_auth: plain values are still printed unquoted"
else
  fail "read_auth: plain-value output changed" "$auth_out"
fi

# --- usage --------------------------------------------------------------------

run_ship usage
rc_is "ship: no argument is a usage error (exit 2)" 2
contains "ship: usage error names every form" "$C/err" "ship.py --check-auth | ship.py --check-payload <batch.json> | ship.py --preview <batch.json> | ship.py <batch.json>"

run_ship flagonly --yes
rc_is "ship: an unknown flag is a usage error (exit 2)" 2
never_posted "ship: an unknown flag never reaches curl"

run_ship missing "$TMP/does-not-exist.json"
rc_is "ship: a missing batch file exits 1" 1
contains "ship: missing batch file is named" "$C/err" "batch JSON not found at"
never_posted "ship: a missing batch file never reaches curl"

# --- --check-auth ---------------------------------------------------------------

run_ship check-ok --check-auth
rc_is "check-auth: valid auth exits 0" 0
contains "check-auth: reports the API URL" "$C/out" "API URL https://stride.example"
no_token_anywhere "check-auth: token is not printed"
never_posted "check-auth: makes no request"

AUTH_FILE_OVERRIDE="$TMP/auth-local-only.md" run_ship check-local --check-auth
rc_is "check-auth: a file with only a Local API Token exits 1" 1
contains "check-auth: Local-only file reports the missing token" "$C/err" "STRIDE_API_TOKEN not found"
lacks "check-auth: Local token value is not echoed" "$C/err" "stride_dev_LOCAL_ONLY_TOKEN_abc"

AUTH_FILE_OVERRIDE="$TMP/no-such-auth.md" run_ship check-missing --check-auth
rc_is "check-auth: a missing auth file exits 1" 1
contains "check-auth: read_auth.py's not-found message is shown" "$C/err" ".stride_auth.md not found at $TMP/no-such-auth.md"
contains "check-auth: missing auth file is named" "$C/err" "failed to read auth from $TMP/no-such-auth.md"

# The default location is the project directory, then the current directory.
mkdir -p "$TMP/proj"
cp "$TMP/auth.md" "$TMP/proj/.stride_auth.md"
C="$TMP/case-check-cwd"
mkdir -p "$C/log" "$C/tmpdir"
(cd "$TMP/proj" && env -u STRIDE_AUTH_FILE PATH="$TMP/bin:$PATH" TMPDIR="$C/tmpdir" \
  FAKE_LOG_DIR="$C/log" python3 "$SHIP" --check-auth > "$C/out" 2> "$C/err"; echo "$?" > "$C/rc")
rc_is "check-auth: finds .stride_auth.md in the current directory" 0
contains "check-auth: names the cwd auth file" "$C/out" "proj/.stride_auth.md"

# From a subdirectory of a git repository the project root's file is used.
mkdir -p "$TMP/gitproj/sub/dir"
git -C "$TMP/gitproj" init -q
cp "$TMP/auth.md" "$TMP/gitproj/.stride_auth.md"
C="$TMP/case-check-toplevel"
mkdir -p "$C/log" "$C/tmpdir"
(cd "$TMP/gitproj/sub/dir" && env -u STRIDE_AUTH_FILE PATH="$TMP/bin:$PATH" TMPDIR="$C/tmpdir" \
  FAKE_LOG_DIR="$C/log" python3 "$SHIP" --check-auth > "$C/out" 2> "$C/err"; echo "$?" > "$C/rc")
rc_is "check-auth: from a subdirectory, finds .stride_auth.md at the git project root" 0
contains "check-auth: names the project-root auth file" "$C/out" "gitproj/.stride_auth.md"

# --- --check-payload --------------------------------------------------------------

run_ship payload-ok --check-payload "$TMP/batch.json"
rc_is "check-payload: a clean batch exits 0" 0
never_posted "check-payload: makes no request"

# The configured token pasted into task text is refused.
python3 - "$TMP/batch.json" "$TMP/token-batch.json" "$TOKEN" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["goals"][0]["tasks"][0]["description"] = "auth is " + sys.argv[3]
json.dump(doc, open(sys.argv[2], "w"))
PY
python3 - "$TMP/batch.json" "$TMP/token-notes.json" "$TOKEN" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["decomposition_notes"] = "token " + sys.argv[3]
json.dump(doc, open(sys.argv[2], "w"))
PY
run_ship payload-token --check-payload "$TMP/token-batch.json"
rc_is "check-payload: a batch holding the token exits 1" 1
contains "check-payload: says the file holds the token" "$C/err" "contains the configured Stride API token; nothing was sent"
no_token_anywhere "check-payload: the token is not printed"
never_posted "check-payload: nothing is POSTed"

run_ship payload-notes --check-payload "$TMP/token-notes.json"
rc_is "check-payload: the token in decomposition_notes (stripped before POST) is still refused" 1

# A token spelled with a JSON \u escape decodes to the token the moment
# anything parses the file, so the screen must catch it too.
python3 - "$TMP/batch.json" "$TMP/token-escaped.json" "$TOKEN" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["goals"][0]["type"] = "@@TOKEN@@"
text = json.dumps(doc).replace("@@TOKEN@@", "\\u%04x" % ord(sys.argv[3][0]) + sys.argv[3][1:])
open(sys.argv[2], "w").write(text)
PY
run_ship payload-escaped --check-payload "$TMP/token-escaped.json"
rc_is "check-payload: a token written with a JSON \\u escape is refused" 1
no_token_anywhere "check-payload: the escaped token is not printed"

run_ship payload-missing --check-payload "$TMP/does-not-exist.json"
rc_is "check-payload: a missing batch file exits 1" 1
contains "check-payload: missing batch file is named" "$C/err" "batch JSON not found at"

# --- 2xx with a renderable body --------------------------------------------------

FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship ok "$TMP/batch.json"
rc_is "2xx: exits 0" 0
contains "2xx: renders the goal row" "$C/out" "     G77  Goal one"
contains "2xx: renders a task row under its goal" "$C/out" "    W901    Task one"
contains "2xx: renders a defect row" "$C/out" "     D12    Task two"
contains "2xx: prints the terminal message" "$C/out" "Batch shipped successfully."
no_token_anywhere "2xx: token is absent from argv, stdout and stderr"
contains "2xx: token reached curl through the -K config on stdin" "$C/log/config" "header = \"Authorization: Bearer $TOKEN\""
if grep -qx -- '-K' "$C/log/argv" && [ "$(grep -A1 -x -- '-K' "$C/log/argv" | tail -n 1)" = "-" ]; then
  pass "2xx: curl reads its config from stdin (-K -), not a file"
else
  fail "2xx: curl config is not read from stdin" "$(tr '\n' ' ' < "$C/log/argv")"
fi
if grep -qx -- '-g' "$C/log/argv"; then pass "2xx: URL globbing is off (-g)"; else fail "2xx: curl run without -g"; fi
if [ "$(cat "$C/log/payload.mode")" = "0o600" ]; then pass "2xx: payload file is mode 600"; else fail "2xx: payload mode" "$(cat "$C/log/payload.mode")"; fi
if grep -qx -- '--data-binary' "$C/log/argv" && grep -q '^@' "$C/log/argv"; then
  pass "2xx: payload is sent with --data-binary @file"
else
  fail "2xx: payload was not sent with --data-binary @file" "$(tr '\n' ' ' < "$C/log/argv")"
fi
if grep -qx -- '-d' "$C/log/argv" || grep -qx -- '--data' "$C/log/argv"; then
  fail "2xx: payload passed with -d/--data"
else
  pass "2xx: no -d/--data argument"
fi
if [ "$(head -n 1 "$C/log/argv")" = "-q" ]; then pass "2xx: -q is curl's first argument (no ~/.curlrc)"; else fail "2xx: -q is not first" "$(head -n 1 "$C/log/argv")"; fi
if grep -qx -- '-v' "$C/log/argv" || grep -qx -- '--verbose' "$C/log/argv"; then fail "2xx: curl run verbose"; else pass "2xx: curl is never run verbose"; fi
contains "2xx: POSTs to the batch endpoint" "$C/log/argv" "https://stride.example/api/tasks/batch"
lacks "2xx: source_spec is stripped from the payload" "$C/log/payload" "source_spec"
lacks "2xx: decomposition_notes is stripped from the payload" "$C/log/payload" "decomposition_notes"
contains "2xx: created_by_agent survives the strip" "$C/log/payload" '"created_by_agent": "Codex CLI"'
if grep -q '"source_spec"' "$TMP/batch.json"; then pass "2xx: the on-disk batch JSON is not modified"; else fail "2xx: on-disk batch JSON lost its audit fields"; fi
no_temp_left "2xx: every temp file is removed"

FAKE_CODE=201 FAKE_BODY="$TMP/created-flat.json" run_ship flat "$TMP/batch.json"
rc_is "2xx flat shape: exits 0" 0
contains "2xx flat shape: renders the goal row" "$C/out" "     G78  Flat goal"
contains "2xx flat shape: renders the task row" "$C/out" "    W902    Flat task"

FAKE_CODE=201 FAKE_BODY="$TMP/no-ident.json" run_ship noident "$TMP/batch.json"
rc_is "2xx without identifiers: exits 0" 0
contains "2xx without identifiers: prints the do-not-re-run notice" "$C/err" "do NOT re-run stride-ideation-stridify"
if [ ! -s "$C/out" ]; then pass "2xx without identifiers: prints no placeholder table"; else fail "2xx without identifiers: stdout not empty" "$(cat "$C/out")"; fi

FAKE_CODE=201 FAKE_BODY="$TMP/empty-goals.json" run_ship emptygoals "$TMP/batch.json"
rc_is "2xx listing no goals: exits 0" 0
contains "2xx listing no goals: says no goals were listed" "$C/err" "listed no created goals"
lacks "2xx listing no goals: does not claim goals already exist" "$C/err" "already exist"

# --- failures before any request ------------------------------------------------

FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship tokenbatch "$TMP/token-batch.json"
rc_is "token in batch: exits 1" 1
contains "token in batch: says nothing was sent" "$C/err" "contains the configured Stride API token; nothing was sent"
never_posted "token in batch: nothing is POSTed"
no_token_anywhere "token in batch: the token is not printed"
no_temp_left "token in batch: every temp file is removed"

# ship.py validates the exact payload it sends, in its own process.
printf '{"tasks": [{"title": "t", "type": "work"}]}\n' > "$TMP/invalid-batch.json"
FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship invalidbatch "$TMP/invalid-batch.json"
rc_is "invalid batch: exits 1" 1
contains "invalid batch: says nothing was sent" "$C/err" "failed validation; nothing was sent"
contains "invalid batch: the validator's reason is shown" "$C/err" "root key 'tasks'"
never_posted "invalid batch: nothing is POSTed"
no_temp_left "invalid batch: every temp file is removed"

# The validator quotes a goal's type; one holding the token must be
# scrubbed, because the token screen runs only after validation.
printf '{"goals": [{"title": "G", "type": "%s", "tasks": [{"title": "t", "type": "work"}]}]}\n' "$TOKEN" > "$TMP/token-key.json"
FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship tokenkey "$TMP/token-key.json"
rc_is "invalid batch quoting the token: exits 1" 1
contains "invalid batch quoting the token: the validator's reason is still shown" "$C/err" "goals[0].type must be 'goal'"
no_token_anywhere "invalid batch quoting the token: the token is scrubbed from the validator's message"
contains "invalid batch quoting the token: shown as [REDACTED]" "$C/err" "[REDACTED]"
never_posted "invalid batch quoting the token: nothing is POSTed"

printf '{"goals": [' > "$TMP/broken.json"
FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship badpayload "$TMP/broken.json"
rc_is "unparseable batch: exits 1" 1
contains "unparseable batch: names the payload failure" "$C/err" "failed to prepare API payload from $TMP/broken.json"
never_posted "unparseable batch: nothing is POSTed"
no_token_anywhere "unparseable batch: token is not printed"
no_temp_left "unparseable batch: every temp file is removed"

AUTH_FILE_OVERRIDE="$TMP/auth-local-only.md" FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship postlocal "$TMP/batch.json"
rc_is "POST with only a Local API Token: exits 1" 1
never_posted "POST with only a Local API Token: nothing is POSTed"
no_temp_left "POST with only a Local API Token: every temp file is removed"

STRIDE_API_TOKEN="stride_dev_INHERITED_ENV_TOKEN" FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship envtoken "$TMP/batch.json"
rc_is "inherited STRIDE_API_TOKEN: still ships" 0
if [ "$(cat "$C/log/env-token")" = "no" ]; then pass "inherited STRIDE_API_TOKEN: curl's environment carries no token"; else fail "inherited STRIDE_API_TOKEN: curl saw STRIDE_API_TOKEN in its environment"; fi
contains "inherited STRIDE_API_TOKEN: the auth file's token is the one sent" "$C/log/config" "Bearer $TOKEN"

# --- 2xx with a body that cannot be rendered --------------------------------------

FAKE_CODE=201 FAKE_BODY="$TMP/notjson.txt" run_ship notjson "$TMP/batch.json"
rc_is "2xx non-JSON: exits 0 (the batch exists)" 0
contains "2xx non-JSON: prints the do-not-re-run notice" "$C/err" "do NOT re-run stride-ideation-stridify"
contains "2xx non-JSON: says the batch was created" "$C/err" "the batch was created (HTTP 201), but the response could not be rendered"
contains "2xx non-JSON: shows the body verbatim" "$C/err" "OK, but this is not JSON"
lacks "2xx non-JSON: no Python traceback" "$C/err" "Traceback"
lacks "2xx non-JSON: no success message" "$C/out" "Batch shipped successfully."
no_temp_left "2xx non-JSON: every temp file is removed"

FAKE_CODE=200 FAKE_BODY="$TMP/list.json" run_ship listroot "$TMP/batch.json"
rc_is "2xx JSON list: exits 0" 0
contains "2xx JSON list: prints the do-not-re-run notice" "$C/err" "do NOT re-run stride-ideation-stridify"
lacks "2xx JSON list: no Python traceback" "$C/err" "Traceback"
if [ ! -s "$C/out" ]; then pass "2xx JSON list: prints no partial table"; else fail "2xx JSON list: stdout not empty" "$(cat "$C/out")"; fi

# --- non-2xx --------------------------------------------------------------------

FAKE_CODE=422 FAKE_BODY="$TMP/422.json" run_ship 422 "$TMP/batch.json"
rc_is "422: exits 1" 1
verbatim_body "422: header line then the body verbatim" "stride-ideation: Stride API rejected the batch (HTTP 422). Response body:" "$TMP/422.json"
no_token_anywhere "422: token is not printed"
no_temp_left "422: every temp file is removed"

FAKE_CODE=502 FAKE_BODY="$TMP/502.html" run_ship 502 "$TMP/batch.json"
rc_is "5xx: exits 1" 1
verbatim_body "5xx: header line then the body verbatim" "stride-ideation: Stride API returned HTTP 502. Response body:" "$TMP/502.html"
no_temp_left "5xx: every temp file is removed"

FAKE_CODE=500 FAKE_BODY="$TMP/500-debug.html" run_ship debug500 "$TMP/batch.json"
rc_is "5xx debug page: exits 1" 1
no_token_anywhere "5xx debug page: the echoed token is scrubbed from stderr"
contains "5xx debug page: the token is shown as [REDACTED]" "$C/err" "<dd>Bearer [REDACTED]</dd><p>raw [REDACTED]</p>"
contains "5xx debug page: any other Bearer value is scrubbed too" "$C/err" "other Bearer [REDACTED]</p>"

FAKE_CODE=302 FAKE_BODY="$TMP/302.html" run_ship 302 "$TMP/batch.json"
rc_is "3xx: exits 1" 1
verbatim_body "3xx: header line then the body verbatim" "stride-ideation: unexpected HTTP status 302. Response body:" "$TMP/302.html"

FAKE_CODE=422 FAKE_BODY="$TMP/big.json" run_ship big "$TMP/batch.json"
rc_is "large 422 body: exits 1" 1
verbatim_body "large 422 body: printed verbatim in full" "stride-ideation: Stride API rejected the batch (HTTP 422). Response body:" "$TMP/big.json"

# --- transport failures -----------------------------------------------------------

FAKE_CODE=000 FAKE_EXIT=6 FAKE_STDERR="curl: (6) Could not resolve host: stride.example" run_ship dns "$TMP/batch.json"
rc_is "transport failure: exits 1" 1
{ printf 'stride-ideation: HTTP request failed before the Stride API responded:\n'; printf 'curl: (6) Could not resolve host: stride.example\n'; } > "$C/expected.err"
if cmp -s "$C/expected.err" "$C/err"; then pass "transport failure: curl stderr is printed verbatim"; else fail "transport failure: stderr mismatch" "$(cat "$C/err")"; fi
no_token_anywhere "transport failure: token is not printed"
no_temp_left "transport failure: every temp file is removed"

FAKE_CODE=000 FAKE_EXIT=28 run_ship silent "$TMP/batch.json"
rc_is "silent transport failure: exits 1" 1
contains "silent transport failure: names curl's exit status" "$C/err" "curl exited with status 28 and no stderr output."

# A token with the Base64 characters real Stride tokens carry, echoed back in
# transformed forms a server or proxy might use.
SLASH_TOKEN="stride_dev_Ab/Cd+Ef=Gh/IjKl"
cat > "$TMP/auth-slash.md" <<EOF
- **API URL:** \`https://stride.example\`
- **API Token:** \`$SLASH_TOKEN\`
EOF
python3 - "$SLASH_TOKEN" "$TMP/500-encoded.html" <<'PY'
import sys, urllib.parse
tok, out = sys.argv[1], sys.argv[2]
body = ("json-escaped: " + tok.replace("/", "\\/") + "\n"
        + "percent-upper: " + urllib.parse.quote(tok, safe="") + "\n"
        + "percent-lower: " + urllib.parse.quote(tok, safe="").replace("%2F", "%2f").replace("%2B", "%2b").replace("%3D", "%3d") + "\n"
        + "truncated: " + tok[:20] + "\n"
        + "header: Bearer%20" + urllib.parse.quote(tok, safe="") + "\n")
open(out, "w").write(body)
PY
AUTH_FILE_OVERRIDE="$TMP/auth-slash.md" FAKE_CODE=500 FAKE_BODY="$TMP/500-encoded.html" run_ship encoded "$TMP/batch.json"
rc_is "5xx encoded echoes: exits 1" 1
if python3 - "$SLASH_TOKEN" "$C/err" <<'PY'
import sys, urllib.parse
tok, err = sys.argv[1], open(sys.argv[2]).read()
q = urllib.parse.quote(tok, safe="")
leaks = [f for f in (tok, tok.replace("/", "\\/"), q, q.lower(), tok[:20], "Ab/Cd", "Ab%2FCd") if f in err]
sys.exit(1 if leaks else 0)
PY
then
  pass "5xx encoded echoes: JSON-escaped, percent-encoded and truncated token forms are all scrubbed"
else
  fail "5xx encoded echoes: a transformed token form reached stderr"
fi
contains "5xx encoded echoes: the surrounding text is kept" "$C/err" "json-escaped: [REDACTED]"
contains "5xx encoded echoes: a token with / and + reaches curl intact" "$C/log/config" "Bearer $SLASH_TOKEN\""

# --- interrupt mid-POST -------------------------------------------------------------

for sig in INT TERM HUP QUIT; do
  C="$TMP/case-sig-$sig"
  mkdir -p "$C/log" "$C/tmpdir"
  (
    # No `set -m`: a non-interactive shell starts this background job with
    # SIGINT and SIGQUIT ignored, exactly as an agent harness may; ship.py
    # must reinstate its own handlers.
    PATH="$TMP/bin:$PATH" TMPDIR="$C/tmpdir" FAKE_LOG_DIR="$C/log" STRIDE_AUTH_FILE="$TMP/auth.md" \
      FAKE_SLEEP=3 FAKE_CODE=201 FAKE_BODY="$TMP/created.json" \
      python3 "$SHIP" "$TMP/batch.json" > "$C/out" 2> "$C/err" &
    pid=$!
    i=0
    while [ ! -e "$C/log/started" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$(( i + 1 )); done
    kill "-$sig" "$pid"
    wait "$pid"
    echo "$?" > "$C/rc"
  )
  case "$sig" in INT) want=130 ;; TERM) want=143 ;; HUP) want=129 ;; QUIT) want=131 ;; esac
  rc_is "SIG$sig mid-POST: exits $want" "$want"
  no_temp_left "SIG$sig mid-POST: every temp file is removed"
  lacks "SIG$sig mid-POST: does not render or claim success" "$C/out" "Batch shipped successfully."
  lacks "SIG$sig mid-POST: no Python traceback" "$C/err" "Traceback"
  contains "SIG$sig mid-POST: warns the batch may already exist" "$C/err" "the batch may already exist"
done

# --- --batch: the stridify Step 1b sequence ships an existing file as-is ----------
#
# Step 1b is skill prose; this drives the exact helper sequence it runs
# (ship.py --check-payload, validate_batch.py, the Step 8.5a ship.py --preview,
# then the Step 9 ship.py call)
# against a committed batch, and asserts nothing is decomposed, rewritten or
# committed along the way.

REPO="$TMP/batch-repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
cp "$TMP/batch.json" "$REPO/2026-05-12T103000-x-stride-batch.json"
git -C "$REPO" add . && git -C "$REPO" commit -q -m "stride-ideation: decomposition for x"
BEFORE_SHA="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REPO/2026-05-12T103000-x-stride-batch.json")"
BEFORE_COUNT="$(git -C "$REPO" rev-list --count HEAD)"

cd "$REPO" || exit 1
run_ship batch-check --check-payload "2026-05-12T103000-x-stride-batch.json"
rc_is "--batch: ship.py --check-payload passes" 0
if python3 "$SCRIPT_DIR/validate_batch.py" "2026-05-12T103000-x-stride-batch.json" 2>/dev/null; then
  pass "--batch: the committed batch passes validate_batch.py"
else
  fail "--batch: validate_batch.py rejected the committed batch"
fi
run_ship batch-preview --preview "2026-05-12T103000-x-stride-batch.json"
rc_is "--batch: the Step 8.5a preview exits 0" 0
contains "--batch: the preview names the goal and its task count" "$C/out" "  Goal: Goal one  (1 task)"
contains "--batch: the preview lists the task" "$C/out" "    - Task one"
contains "--batch: the preview shows the claim order" "$C/out" "claim order: G1 first"
no_token_anywhere "--batch: the preview prints no token"
never_posted "--batch: the preview sends nothing"
FAKE_CODE=201 FAKE_BODY="$TMP/created.json" run_ship batch-ship "2026-05-12T103000-x-stride-batch.json"
cd - > /dev/null || exit 1
rc_is "--batch: ship.py ships the file" 0
contains "--batch: the created identifiers are rendered" "$C/out" "     G77  Goal one"
AFTER_SHA="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REPO/2026-05-12T103000-x-stride-batch.json")"
if [ "$BEFORE_SHA" = "$AFTER_SHA" ]; then pass "--batch: the batch file is byte-for-byte unchanged"; else fail "--batch: the batch file was rewritten"; fi
if [ "$(git -C "$REPO" rev-list --count HEAD)" = "$BEFORE_COUNT" ]; then pass "--batch: no commit is created"; else fail "--batch: a commit was created"; fi
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then pass "--batch: the working tree stays clean"; else fail "--batch: the working tree changed" "$(git -C "$REPO" status --porcelain)"; fi

run_ship preview-missing --preview "$TMP/does-not-exist.json"
rc_is "--preview: a missing batch file exits 1" 1
run_ship preview-broken --preview "$TMP/broken.json"
rc_is "--preview: an unparseable batch exits 1 without a traceback" 1
lacks "--preview: no Python traceback" "$C/err" "Traceback"

# --- the stridify skill documents the ship.py flow, not the old fragments ---------

SKILL="$SCRIPT_DIR/../skills/stride-ideation-stridify/SKILL.md"
contains "SKILL: Step 3 preflight calls ship.py --check-auth" "$SKILL" 'lib/ship.py" --check-auth || exit 1'
contains "SKILL: Step 9 ships through one ship.py call" "$SKILL" "python3 \"\$HELPER_ROOT/lib/ship.py\" '<value of BATCH_PATH>'"
lacks "SKILL: no <plugin-root> placeholder remains" "$SKILL" "<plugin-root>"
lacks "SKILL: no CLAUDE_PROJECT_DIR reference remains" "$SKILL" "CLAUDE_PROJECT_DIR"
contains "SKILL: --batch accepts the --batch=<value> form" "$SKILL" '`--batch=<value>`'
contains "SKILL: --batch with --goal is rejected" "$SKILL" "cannot be combined with --goal"
contains "SKILL: --batch screens the file with --check-payload" "$SKILL" "ship.py\" --check-payload"
contains "SKILL: the Step 8.5a preview is one ship.py call" "$SKILL" "lib/ship.py\" --preview '<value of BATCH_PATH>'"
contains "SKILL: --batch warns about shipping a batch twice" "$SKILL" "shipping it again creates every goal and task a second time"
contains "SKILL: the decline message points at --batch" "$SKILL" "Ship it later, unchanged, by activating stride-ideation-stridify with: --batch"
lacks "SKILL: no eval of read_auth.py output remains" "$SKILL" 'eval "$AUTH_OUT"'
lacks "SKILL: no token on curl's command line" "$SKILL" 'Bearer $STRIDE_API_TOKEN'
lacks "SKILL: no payload passed with -d" "$SKILL" '-d "$API_PAYLOAD"'
lacks "SKILL: no claim that curl -H hides the token" "$SKILL" "is fine because curl"
lacks "SKILL: the Step 7.5 recovery no longer asks for a manual POST" "$SKILL" "manual POST"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
