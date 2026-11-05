#!/usr/bin/env bash
# Model-free checks on how lib/run_eval.sh invokes the agent (W2640).
#
# Ported from upstream cheezy/stride-security-review scripts/check_eval_invocation.sh
# (W2274, ea06aeb). The eval is only worth running if the model answers under
# THIS checkout's security-reviewer prompt rather than Codex CLI's default
# coding-agent prompt. `codex exec` has no agent flag, so run_eval.sh passes
# the agent file as the session instructions (`-c model_instructions_file=...`).
# That is a property of the codex argv, so it can be checked without a model,
# credentials or network. Every case puts a fake `codex` first on a PATH inside
# this script's own temporary directory (removed on exit); a guard refuses to
# run if `codex` would resolve anywhere else, so the real CLI is never called.
#
#   1. --dry-run prints the exact invocation and exits 0 with no CLI call: the
#      agent file as model_instructions_file, --skip-git-repo-check, --cd into a
#      scratch directory, --sandbox read-only, --ephemeral, --ignore-user-config,
#      --color never, the shell tool, web search, subagents and image viewing
#      off, approvals never, the prompt on stdin (`-`), no --agent flag and no
#      sandbox bypass. It never runs or
#      even looks for the CLI, and writes no log directory.
#   2. A fake CLI records what run_eval.sh actually executed: the same argv, a
#      cwd that is empty and outside the repo, and the considerations-mode
#      prompt, whose first line is the agent's one tag `/security-review
#      invocation, mode: considerations` (and run_eval.sh's full_file prompt
#      opens with the full_file tag), with the fixture's diff byte for byte on
#      stdin, never in argv. A
#      canned verdict scores `ok`, with a saved login accepted.
#   3. CODEX_API_KEY is accepted as auth, `login status` is then not asked, and
#      the key is never printed or logged.
#   4. A CLI that is not logged in, with no key, exits 2 with a clear message
#      and never dispatches; a missing CLI exits 2 too.
#   5. A failing CLI fails the fixture, and its stderr is kept in .err.txt.
#   6. The score follows the instructions file: the fake answers only when the
#      file it is handed is this plugin's agent, so pointing EVAL_AGENT_FILE at
#      another prompt fails the fixture. A missing agent file, or a path with a
#      quote, exits 2; a relative path arrives absolute; EVAL_MODEL is passed
#      with -m and nothing is passed without it; and a dry run whose row has no
#      sidecar fails instead of skipping it.
#   7. --only <prefix> keeps exactly the matching rows; --only with no match
#      exits 2. A considerations row with no AND clause parses with the
#      explicit `U` marker (the tab-collapse fix).
#   8. Break-its on a scratch copy of the tree: deleting or rewriting any one
#      pinned piece of the copy's run_eval.sh makes this check, run on the
#      copy, exit 1 and name the pin. Not every check in sections 1-7 is
#      named by a break: the CHANGELOG lists the kinds that are not, and why.
#   9. check_fixtures.sh rejects a considerations .diff with no sidecar, a
#      sidecar with no .diff, a verdict-count mismatch, a fixture with no row
#      and a row with no fixture, against a scratch copy of the tree.
#
# Upstream's CI key-gate check does not apply: this variant has no CI workflow,
# so the eval runs locally only.
#
# Offline and read-only towards the repo. Resolves everything relative to this
# script's own location, so it works from any CWD. Sections 8 and 9 are skipped
# when CHECK_EVAL_INVOCATION_CHILD is set (the break-it children), which bounds
# the recursion at one level.
#
# Usage:  bash lib/check_eval_invocation.sh
# Exit code: 0 when every check passes, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_EVAL="$SCRIPT_DIR/run_eval.sh"
AGENT_FILE="$ROOT_DIR/agents/security-reviewer.md"
FIXTURE="considerations/token_logging_unmitigated.diff"
U_FIXTURE="considerations/credential_in_consideration_mitigated.diff"
KEY_SENTINEL="FAKE_CODEX_KEY_SENTINEL_not_a_real_key"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check_eval_invocation.XXXXXX")" || {
  echo "FAIL: mktemp could not create a scratch directory"
  exit 1
}
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  echo "FAIL: mktemp returned no scratch directory"
  exit 1
fi
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/tmpdir"

fail=0
check() { # $1=label; remaining args = a test command
  local label="$1"
  shift
  if "$@"; then
    echo "ok: $label"
  else
    echo "FAIL: $label"
    fail=1
  fi
}
contains() { grep -qF -- "$2" "$1" 2>/dev/null; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
has_line() { grep -qxF -- "$2" "$1" 2>/dev/null; }
fails() { ! "$@"; }
outside_repo() { case "$1" in "$ROOT_DIR"|"$ROOT_DIR"/*|'') return 1 ;; *) return 0 ;; esac; }
no_sentinel() { ! grep -rqF -- "$KEY_SENTINEL" "$@" 2>/dev/null; }
q() { printf '%q' "$1"; }

cd "$ROOT_DIR" || exit 1

# --- the fake CLI ---------------------------------------------------------------
# `codex login status` exits FAKE_LOGIN_RC (default 0) and prints an account
# line the runner must never echo. Any other call records argv (one per line),
# cwd, the number of entries in cwd and stdin, then answers with a fenced JSON
# document -- but only when the model_instructions_file it was handed starts
# with this plugin's agent frontmatter; with any other instructions it answers
# with no verdicts, as a model with a different prompt would. FAKE_EXEC_RC
# makes the call fail after writing to stderr.
FAKE="$TMP/bin/codex"
cat > "$FAKE" <<'FAKE_EOF'
#!/usr/bin/env bash
R="${FAKE_REC:?}"
printf '%s\n' "$*" >> "$R/calls"
if [ "${1:-}" = "login" ] && [ "${2:-}" = "status" ]; then
  echo "Logged in as fake-account@example.invalid"
  exit "${FAKE_LOGIN_RC:-0}"
fi
printf '%s\n' "$@" > "$R/argv"
pwd > "$R/pwd"
ls -A | wc -l | tr -d ' ' > "$R/cwd_count"
cat > "$R/stdin"
if [ "${FAKE_EXEC_RC:-0}" -ne 0 ]; then
  echo "fake codex: simulated failure" >&2
  exit "$FAKE_EXEC_RC"
fi
instr=""
for a in "$@"; do
  case "$a" in
    model_instructions_file=*) instr="${a#model_instructions_file=}"; instr="${instr#\'}"; instr="${instr%\'}" ;;
  esac
done
echo "fake codex: progress goes to stderr" >&2
if [ -n "$instr" ] && [ "$(sed -n 2p "$instr" 2>/dev/null)" = "name: security-reviewer" ]; then
  cat <<'JSON'
```json
{"findings":[{"severity":"critical","file":"app/users.py","line":12,"vulnerability_class":"injection","cwe":["CWE-89"],"owasp":["A03:2021"],"description":"fake","remediation":"fake","confidence":"high"}],
 "consideration_verdicts":[{"consideration":"a","status":"unmitigated"},{"consideration":"b","status":"mitigated"}]}
```
JSON
else
  printf '```json\n{"findings":[]}\n```\n'
fi
FAKE_EOF
chmod +x "$FAKE"

export PATH="$TMP/bin:$PATH"
if [ "$(command -v codex)" != "$FAKE" ]; then
  echo "FAIL: the fake codex is not first on PATH; refusing to risk the real CLI"
  exit 1
fi

# run_case <name> <args...>: a fresh record dir, logs under TMP, TMPDIR under
# TMP, output in $TMP/<name>.out, exit code in $TMP/<name>.rc. Extra env goes in
# CASE_ENV (space-separated assignments, no spaces inside a value).
run_case() {
  local name="$1"
  shift
  mkdir -p "$TMP/rec-$name"
  # shellcheck disable=SC2086
  env -u CODEX_API_KEY -u OPENAI_API_KEY -u EVAL_MODEL -u EVAL_AGENT_FILE FAKE_REC="$TMP/rec-$name" CODEX_CLI=codex TMPDIR="$TMP/tmpdir" \
    LOG_DIR="$TMP/logs-$name" ${CASE_ENV:-} \
    bash "$RUN_EVAL" "$@" > "$TMP/$name.out" 2>&1
  echo "$?" > "$TMP/$name.rc"
}
rc_is() { [ "$(cat "$TMP/$1.rc" 2>/dev/null)" = "$2" ]; }

# --- 1. dry-run prints the exact invocation, no CLI call ----------------------
CASE_ENV="" run_case dry --dry-run --fixture "$FIXTURE"
grep '^# invocation:' "$TMP/dry.out" > "$TMP/dry.inv" || true
INV="$TMP/dry.inv"

check "dry-run exits 0"                               rc_is dry 0
check "dry-run prints an invocation line"             test -s "$INV"
check "the invocation is codex exec"                  contains "$INV" "# invocation: codex exec "
check "the invocation passes this plugin's agent file" contains "$INV" "-c $(q "model_instructions_file='$AGENT_FILE'")"
check "the invocation runs outside a Git repository"  contains "$INV" " --skip-git-repo-check "
check "the invocation sets a scratch working root"    contains "$INV" " --cd "
check "the invocation uses a read-only sandbox"       contains "$INV" " --sandbox read-only "
check "the invocation saves no session files"         contains "$INV" " --ephemeral "
check "the invocation skips the user config.toml"     contains "$INV" " --ignore-user-config "
check "the invocation turns colour off"               contains "$INV" " --color never "
check "the invocation turns the shell tool off"       contains "$INV" " -c features.shell_tool=false "
check "the invocation turns web search off"           contains "$INV" " -c $(q 'web_search="disabled"') "
check "the invocation turns subagents off"            contains "$INV" " -c features.multi_agent=false "
check "the invocation turns image viewing off"        contains "$INV" " -c features.view_image=false "
check "the invocation never asks for approval"        contains "$INV" " -c $(q 'approval_policy="never"') "
check "the invocation reads the prompt from stdin"    grep -qE ' -$' "$INV"
check "the invocation has no --agent flag"            lacks "$INV" "--agent"
check "the invocation never bypasses the sandbox"     lacks "$INV" "dangerously"
check "dry-run reports its auth mode"                 contains "$TMP/dry.out" "# auth: dry-run"
check "dry-run skips the row instead of scoring it"   contains "$TMP/dry.out" "ok 1 - $FIXTURE (considerations: unmitigated,mitigated (F)) # SKIP dry run: no CLI call"
check "dry-run makes no CLI call"                     test ! -e "$TMP/rec-dry/calls"
check "dry-run writes no log directory"               test ! -e "$TMP/logs-dry"
cd_dir="$(awk '{ for (i = 1; i < NF; i++) if ($i == "--cd") { print $(i + 1); exit } }' "$INV")"
check "the scratch working root is outside the repo"  outside_repo "$cd_dir"
check "the scratch working root is removed on exit"   test ! -e "$cd_dir"

CASE_ENV="CODEX_CLI=$TMP/no-such-codex" run_case dry_nocli --dry-run --fixture "$FIXTURE"
check "dry-run does not need the CLI to exist"        rc_is dry_nocli 0

# --- 2. the fake CLI records what was really executed -------------------------
CASE_ENV="" run_case fake --fixture "$FIXTURE"
ARGV="$TMP/rec-fake/argv"
check "a canned verdict scores ok (exit 0)"           rc_is fake 0
check "the TAP line is ok"                            contains "$TMP/fake.out" "ok 1 - $FIXTURE (considerations: unmitigated,mitigated (F))"
check "a logged-in CLI is accepted without a key"     contains "$TMP/fake.out" "# auth: codex-login"
check "the login-status output is never printed"      lacks "$TMP/fake.out" "fake-account@example.invalid"
check "the CLI was asked for its login status"        has_line "$TMP/rec-fake/calls" "login status"
check "the CLI ran exec"                              test "$(sed -n 1p "$ARGV" 2>/dev/null)" = "exec"
check "the CLI received this plugin's agent file"     has_line "$ARGV" "model_instructions_file='$AGENT_FILE'"
check "the CLI received the shell tool off"           has_line "$ARGV" "features.shell_tool=false"
check "the CLI received the read-only sandbox"        has_line "$ARGV" "read-only"
check "the CLI received - as the prompt"              test "$(tail -n 1 "$ARGV" 2>/dev/null)" = "-"
check "the CLI received no --agent flag"              lacks "$ARGV" "--agent"
fake_pwd="$(cat "$TMP/rec-fake/pwd" 2>/dev/null)"
check "the CLI ran outside the repo"                  outside_repo "$fake_pwd"
check "the CLI ran in an empty directory"             test "$(cat "$TMP/rec-fake/cwd_count" 2>/dev/null)" = "0"
fake_cd="$(awk 'prev == "--cd" { print; exit } { prev = $0 }' "$ARGV")"
check "the CLI's --cd is the directory it ran in"     test -n "$fake_cd" -a "$(cd "$fake_cd" 2>/dev/null && pwd -P)" = "$(cd "$fake_pwd" 2>/dev/null && pwd -P)"
check "the prompt is in considerations mode"          test "$(sed -n 1p "$TMP/rec-fake/stdin" 2>/dev/null)" = "/security-review invocation, mode: considerations"
check "the full_file prompt opens with the tag"       contains "$RUN_EVAL" "printf '/security-review invocation, mode: full_file\n\n'"
check "the fixture's diff reaches stdin byte for byte" python3 -I -c 'import sys; sys.exit(0 if open(sys.argv[1],"rb").read() in open(sys.argv[2],"rb").read() else 1)' "$ROOT_DIR/fixtures/$FIXTURE" "$TMP/rec-fake/stdin"
check "the fixture's text is never in argv"           lacks "$ARGV" "request.args"
# W2636 (upstream W2285): the core reads no rule file, so the eval sends every
# pack and the considerations and reproduction mode files in keyed blocks, as
# the stride-security-review skill does, and never the result-file mode.
cat > "$TMP/blocks_check.py" <<'BLOCKS_CHECK_END'
import re,sys
# argv: mode(key|blocks|order|noresult) stdin rules_dir
mode,stdin,rules=sys.argv[1],sys.argv[2],sys.argv[3]
t=open(stdin,'rb').read().decode('utf-8')
keys=re.findall(r'^Rule-file key: ([0-9a-f]{16})$',t,re.M)
if mode=='key': sys.exit(0 if len(keys)==1 and len(re.findall(r'^Rule-file key:',t,re.M))==1 else 1)
if mode=='noresult': sys.exit(0 if 'modes/result-file.md' not in t else 1)
if len(keys)!=1: sys.exit(1)
k=keys[0]
names='packs/android.md packs/django.md packs/express.md packs/ios.md packs/phoenix.md packs/rails.md packs/react-nextjs.md packs/web-defense.md packs/supply-chain.md packs/ci-cd.md packs/agentic.md modes/considerations.md modes/reproduction.md'.split()
if mode=='blocks':
    for n in names:
        o='<<<STRIDE RULE FILE %s %s>>>\n'%(n,k); c='<<<END STRIDE RULE FILE %s %s>>>\n'%(n,k)
        if t.count(o)!=1 or t.count(c)!=1: sys.exit(1)
        body=t[t.index(o)+len(o):t.index(c)]
        if body!=open(rules+'/'+n,encoding='utf-8').read(): sys.exit(1)
    sys.exit(0)
if mode=='order':
    first=t.find('<<<STRIDE RULE FILE ')
    sys.exit(0 if 0 <= first < t.find('```diff\n') and t.find('Rule-file key:') < first else 1)
sys.exit(2)
BLOCKS_CHECK_END
RULES_SRC="$ROOT_DIR/skills/stride-security-review"
check "the prompt carries one Rule-file key line"     python3 -I "$TMP/blocks_check.py" key "$TMP/rec-fake/stdin" "$RULES_SRC"
check "the prompt sends every pack and mode file verbatim" python3 -I "$TMP/blocks_check.py" blocks "$TMP/rec-fake/stdin" "$RULES_SRC"
check "the rule-file blocks come before the diff"     python3 -I "$TMP/blocks_check.py" order "$TMP/rec-fake/stdin" "$RULES_SRC"
check "the prompt never sends the result-file mode"   python3 -I "$TMP/blocks_check.py" noresult "$TMP/rec-fake/stdin" "$RULES_SRC"
check "the CLI's stderr is kept in .err.txt"          contains "$TMP/logs-fake/considerations_token_logging_unmitigated_diff.err.txt" "progress goes to stderr"

# --- 3. an API key is accepted and never printed ------------------------------
CASE_ENV="CODEX_API_KEY=$KEY_SENTINEL" run_case key --fixture "$FIXTURE"
check "CODEX_API_KEY is accepted (exit 0)"            rc_is key 0
check "the auth mode is api-key"                      contains "$TMP/key.out" "# auth: api-key"
check "login status is not asked when a key is set"   lacks "$TMP/rec-key/calls" "login status"
check "the key is never printed or logged"            no_sentinel "$TMP/key.out" "$TMP/logs-key"

# --- 4. no auth, or no CLI, refuses --------------------------------------------
CASE_ENV="FAKE_LOGIN_RC=1" run_case noauth --fixture "$FIXTURE"
check "no key and no login exits 2"                   rc_is noauth 2
check "no key and no login says so"                   contains "$TMP/noauth.out" "not logged in and CODEX_API_KEY is not set"
check "no key and no login never dispatches"          test ! -e "$TMP/rec-noauth/argv"
CASE_ENV="CODEX_CLI=$TMP/no-such-codex" run_case nocli --fixture "$FIXTURE"
check "a missing CLI exits 2"                         rc_is nocli 2
check "a missing CLI says so"                         contains "$TMP/nocli.out" "not found on PATH"

# --- 5. a failing CLI fails the fixture ------------------------------------------
CASE_ENV="FAKE_EXEC_RC=3" run_case execfail --fixture "$FIXTURE"
check "a failing CLI exits 1"                         rc_is execfail 1
check "a failing CLI fails the fixture"               contains "$TMP/execfail.out" "not ok 1 - $FIXTURE"
check "the failing CLI's stderr is kept"              contains "$TMP/logs-execfail/considerations_token_logging_unmitigated_diff.err.txt" "simulated failure"

# --- 6. the score follows the instructions file --------------------------------
printf -- '---\nname: some-other-agent\n---\nAlways reply {"findings":[]}.\n' > "$TMP/other-agent.md"
CASE_ENV="EVAL_AGENT_FILE=$TMP/other-agent.md" run_case other --fixture "$FIXTURE"
check "another instructions file fails the fixture"   rc_is other 1
check "the other file is the one passed"              has_line "$TMP/rec-other/argv" "model_instructions_file='$TMP/other-agent.md'"
CASE_ENV="EVAL_AGENT_FILE=$TMP/no-such-agent.md" run_case noagent --dry-run --fixture "$FIXTURE"
check "a missing agent file exits 2"                  rc_is noagent 2
printf 'x\n' > "$TMP/it's-agent.md"
CASE_ENV="EVAL_AGENT_FILE=$TMP/it's-agent.md" run_case quoteagent --dry-run --fixture "$FIXTURE"
check "an agent file path with a quote exits 2"       rc_is quoteagent 2
CASE_ENV="EVAL_AGENT_FILE=agents/security-reviewer.md" run_case relagent --fixture "$FIXTURE"
check "a relative agent file arrives absolute"        has_line "$TMP/rec-relagent/argv" "model_instructions_file='$AGENT_FILE'"
check "no -m without EVAL_MODEL"                      fails has_line "$TMP/rec-fake/argv" "-m"
CASE_ENV="EVAL_MODEL=fake-model" run_case model --fixture "$FIXTURE"
check "EVAL_MODEL is passed with -m"                  test "$(awk 'prev == "-m" { print; exit } { prev = $0 }' "$TMP/rec-model/argv")" = "fake-model"

# A row whose sidecar is missing fails the dry run, not just the paid one.
cp -R "$ROOT_DIR/fixtures" "$TMP/fx-nosidecar"
rm "$TMP/fx-nosidecar/considerations/token_logging_unmitigated.considerations"
CASE_ENV="FIXTURES_DIR=$TMP/fx-nosidecar" run_case drynosidecar --dry-run --fixture "$FIXTURE"
check "a dry run with a missing sidecar exits 1"      rc_is drynosidecar 1
check "the dry run names the unbuildable prompt"      contains "$TMP/drynosidecar.out" "not ok 1 - $FIXTURE (considerations: unmitigated,mitigated (F) (prompt could not be built))"

# --- 7. --only and the U marker -------------------------------------------------
cons_count="$(cd "$ROOT_DIR/fixtures" && find considerations -type f -name '*.diff' | wc -l | tr -d ' ')"
CASE_ENV="" run_case only --dry-run --only considerations/
check "--only keeps every considerations row"         contains "$TMP/only.out" "1..$cons_count"
check "--only keeps nothing else"                     test "$(grep -c '^ok ' "$TMP/only.out")" = "$(grep -c '^ok [0-9]* - considerations/' "$TMP/only.out")"
CASE_ENV="" run_case only_none --dry-run --only no-such-prefix/
check "--only with no match exits 2"                  rc_is only_none 2
CASE_ENV="" run_case umark --dry-run --fixture "$U_FIXTURE"
check "a row with no AND clause parses with U"        contains "$TMP/umark.out" "ok 1 - $U_FIXTURE (considerations: mitigated,mitigated (U))"

# --- 8. break-its on a scratch copy of the tree ----------------------------------
# copy_tree <dir>: an explicit list of the files these checks read, never a
# glob of the root, so a local untracked file is never copied.
copy_tree() {
  mkdir -p "$1"
  cp -R "$ROOT_DIR/lib" "$ROOT_DIR/agents" "$ROOT_DIR/skills" "$ROOT_DIR/fixtures" "$ROOT_DIR/README.md" "$1/"
}
if [ -z "${CHECK_EVAL_INVOCATION_CHILD:-}" ]; then
  # break_it <label> <ERE of the run_eval.sh line to delete> <FAIL needle>
  break_it() {
    local label="$1" re="$2" needle="$3" t out rc
    t="$TMP/break-$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
    copy_tree "$t"
    if ! grep -qE -- "$re" "$t/lib/run_eval.sh"; then
      echo "FAIL: break-it: $label -- the line to delete is not in run_eval.sh"
      fail=1
      return
    fi
    grep -vE -- "$re" "$t/lib/run_eval.sh" > "$t/lib/run_eval.sh.new" && mv "$t/lib/run_eval.sh.new" "$t/lib/run_eval.sh"
    out="$(CHECK_EVAL_INVOCATION_CHILD=1 bash "$t/lib/check_eval_invocation.sh" 2>&1)"
    rc=$?
    if [ "$rc" -ne 1 ]; then
      echo "FAIL: break-it: $label -- exit $rc, wanted 1"
      fail=1
    elif ! printf '%s\n' "$out" | grep -qF -- "FAIL: $needle"; then
      echo "FAIL: break-it: $label -- output lacks: FAIL: $needle"
      fail=1
    else
      echo "ok: break-it: $label"
    fi
  }
  break_it "dropping the agent file fails"            '^ +-c "model_instructions_file='   "the invocation passes this plugin's agent file"
  break_it "dropping the shell-tool switch fails"     '^ +-c features\.shell_tool=false$' "the invocation turns the shell tool off"
  break_it "dropping the read-only sandbox fails"     '^ +--sandbox read-only$'           "the invocation uses a read-only sandbox"
  break_it "dropping the scratch working root fails"  '^ +--cd "\$WORK_DIR"$'            "the invocation sets a scratch working root"
  break_it "dropping the git-repo skip fails"         '^ +--skip-git-repo-check$'         "the invocation runs outside a Git repository"
  break_it "dropping the user-config skip fails"      '^ +--ignore-user-config$'          "the invocation skips the user config.toml"
  break_it "dropping web search off fails"            "^ +-c 'web_search=\"disabled\"'\$"  "the invocation turns web search off"
  break_it "dropping subagents off fails"             '^ +-c features\.multi_agent=false$' "the invocation turns subagents off"
  break_it "dropping the stdin prompt fails"          '^ +CODEX_ARGV\+=\(-\)$'            "the invocation reads the prompt from stdin"
  # break_sub <label> <literal to replace> <replacement> <FAIL needle>
  break_sub() {
    local label="$1" old="$2" new="$3" needle="$4" t out rc
    t="$TMP/break-$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
    copy_tree "$t"
    if ! python3 -I -c 'import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))' "$t/lib/run_eval.sh" "$old" "$new"; then
      echo "FAIL: break-it: $label -- the text to replace is not in run_eval.sh exactly once"
      fail=1
      return
    fi
    out="$(CHECK_EVAL_INVOCATION_CHILD=1 bash "$t/lib/check_eval_invocation.sh" 2>&1)"
    rc=$?
    if [ "$rc" -ne 1 ]; then
      echo "FAIL: break-it: $label -- exit $rc, wanted 1"
      fail=1
    elif ! printf '%s\n' "$out" | grep -qF -- "FAIL: $needle"; then
      echo "FAIL: break-it: $label -- output lacks: FAIL: $needle"
      fail=1
    else
      echo "ok: break-it: $label"
    fi
  }
  break_sub "running the CLI from the repo fails" \
    'if ! (cd "$WORK_DIR" && printf' 'if ! (printf' "the CLI ran outside the repo"
  break_sub "an empty scratch root that is not empty fails" \
    '  build_codex_argv

  local total=' '  build_codex_argv
  : > "$WORK_DIR/EXPECTED.md"

  local total=' "the CLI ran in an empty directory"
  break_sub "printing the login status fails" \
    'login status >/dev/null 2>&1 </dev/null' 'login status </dev/null' "the login-status output is never printed"
  break_sub "echoing the key fails" \
    'AUTH_MODE="api-key"' 'AUTH_MODE="api-key"; echo "key=$CODEX_API_KEY"' "the key is never printed or logged"
  break_sub "a dry run that calls the CLI fails" \
    'AUTH_MODE="dry-run"' 'AUTH_MODE="dry-run"; "$CODEX_CLI" login status >/dev/null 2>&1 || true' "dry-run makes no CLI call"
  break_sub "planting an --agent flag fails" \
    '    "$CODEX_CLI" exec
' '    "$CODEX_CLI" exec --agent security-reviewer
' "the invocation has no --agent flag"
  break_sub "accepting a CLI that is not logged in fails" \
    '  die "no Codex auth:' '  AUTH_MODE="codex-login"; return 0; die "no Codex auth:' "no key and no login exits 2"
  # Breaks for section 1-7 checks the breaks above do not name.
  break_it "dropping --ephemeral fails"               '^ +--ephemeral$'                   "the invocation saves no session files"
  break_it "dropping colour off fails"                '^ +--color never$'                 "the invocation turns colour off"
  break_it "dropping image viewing off fails"         '^ +-c features\.view_image=false$' "the invocation turns image viewing off"
  break_it "dropping approvals never fails"           "^ +-c 'approval_policy=\"never\"'\$" "the invocation never asks for approval"
  break_sub "always passing -m fails" \
    '  if [ -n "$MODEL" ]; then
    CODEX_ARGV+=(-m "$MODEL")' '  if true; then
    CODEX_ARGV+=(-m "${MODEL:-planted-model}")' "no -m without EVAL_MODEL"
  break_sub "putting the prompt in argv fails" \
    '"${CODEX_ARGV[@]}") > "$raw"' '"${CODEX_ARGV[@]}" "$prompt") > "$raw"' "the fixture's text is never in argv"
  break_sub "changing the prompt's mode line fails" \
    "      printf '/security-review invocation, mode: considerations\\n\\n'" "      printf '/security-review invocation, mode: diff\\n\\n'" "the prompt is in considerations mode"
  # W2278: a bare `mode:` line or the slash-less spelling is not the agent's tag.
  break_sub "a bare mode: considerations line fails" \
    "      printf '/security-review invocation, mode: considerations\\n\\n'" "      printf 'mode: considerations\\n\\n'" "the prompt is in considerations mode"
  break_sub "the slash-less considerations tag fails" \
    "      printf '/security-review invocation, mode: considerations\\n\\n'" "      printf 'security-review invocation, mode: considerations\\n\\n'" "the prompt is in considerations mode"
  break_sub "a bare mode: full_file line fails" \
    "  printf '/security-review invocation, mode: full_file\\n\\n'" "  printf 'mode: full_file\\n\\n'" "the full_file prompt opens with the tag"
  break_sub "skipping the login-status call fails" \
    '  if "$CODEX_CLI" login status >/dev/null 2>&1 </dev/null; then' '  if true; then' "the CLI was asked for its login status"
  break_it "not printing the invocation fails"        '^  print_invocation$'              "dry-run prints an invocation line"
  break_sub "planting a sandbox bypass fails" \
    '    --sandbox read-only
' '    --sandbox read-only
    --dangerously-bypass-approvals-and-sandbox
' "the invocation never bypasses the sandbox"
  break_sub "discarding the CLI's stderr fails" \
    '"${CODEX_ARGV[@]}") > "$raw" 2> "$err"; then' '"${CODEX_ARGV[@]}") > "$raw" 2>/dev/null; then' "the CLI's stderr is kept in .err.txt"
  break_sub "dropping EVAL_MODEL fails" \
    'CODEX_ARGV+=(-m "$MODEL")' ':' "EVAL_MODEL is passed with -m"
  break_sub "ignoring EVAL_AGENT_FILE fails" \
    'AGENT_FILE="${EVAL_AGENT_FILE:-$ROOT_DIR/agents/security-reviewer.md}"' 'AGENT_FILE="$ROOT_DIR/agents/security-reviewer.md"' "another instructions file fails the fixture"
  break_sub "leaving a relative agent file relative fails" \
    '    *) AGENT_FILE="$(cd "$(dirname "$AGENT_FILE")" && pwd)/$(basename "$AGENT_FILE")" ;;' '    *) ;;' "a relative agent file arrives absolute"
  break_sub "admitting a quoted agent path fails" \
    'die "agent file path must not contain a single quote or a line break: $AGENT_FILE"' ':' "an agent file path with a quote exits 2"
  break_sub "admitting a missing agent file fails" \
    '[ -f "$AGENT_FILE" ] || die "agent file not found' '[ -f "$AGENT_FILE" ] || : "agent file not found' "a missing agent file exits 2"
  break_sub "admitting a missing CLI fails" \
    'command -v "$CODEX_CLI" >/dev/null 2>&1 || die' 'command -v "$CODEX_CLI" >/dev/null 2>&1 || :' "a missing CLI says so"
  break_sub "dropping the Rule-file key line fails" \
    "  printf 'Rule-file key: %s\\n\\n' \"\$key\"" "  :" "the prompt carries one Rule-file key line"
  break_sub "sending a rule file edited fails" \
    '      cat "$EVAL_RULES_DIR/$name"' '      head -c 40 "$EVAL_RULES_DIR/$name"' "the prompt sends every pack and mode file verbatim"
  break_sub "sending the blocks after the diff fails" \
    "      printf '\\n'
      emit_rule_blocks \"\$abs\" 1
      printf '\`\`\`diff\\n'" "      printf '\\n\`\`\`diff\\n'
      emit_rule_blocks \"\$abs\" 1" "the rule-file blocks come before the diff"
  break_sub "sending the result-file mode fails" \
    '  names="$names modes/reproduction.md"' '  names="$names modes/reproduction.md modes/result-file.md"' "the prompt never sends the result-file mode"
  break_sub "truncating the fixture in the prompt fails" \
    '      cat "$abs"' '      head -c 20 "$abs"' "the fixture's diff reaches stdin byte for byte"
  break_sub "skipping the sidecar check fails" \
    '      [ -f "$cons" ] || return 1
' '' "a dry run with a missing sidecar exits 1"
  break_sub "asking login status despite a key fails" \
    '  if [ -n "${CODEX_API_KEY:-}" ]; then' '  if "$CODEX_CLI" login status >/dev/null 2>&1 </dev/null; [ -n "${CODEX_API_KEY:-}" ]; then' "login status is not asked when a key is set"
  break_sub "an --only that keeps every row fails" \
    '        "$prefix"*) kept+=("$r") ;;' '        *) kept+=("$r") ;;' "--only keeps every considerations row"
  break_sub "an --only with no match that does not exit 2 fails" \
    'die "no fixture in $EXPECTED_FILE matches --only $ONLY_PREFIX"' 'exit 0' "--only with no match exits 2"
  break_sub "a dry run that writes logs fails" \
    '  # A dry run writes no logs, so it leaves LOG_DIR alone.
  if [ "$DRY_RUN" -eq 0 ]; then' '  # A dry run writes no logs, so it leaves LOG_DIR alone.
  if true; then' "dry-run writes no log directory"
  break_sub "leaving the scratch root behind fails" \
    "  trap 'rm -rf \"\$WORK_DIR\"' EXIT" '  :' "the scratch working root is removed on exit"
  break_sub "a dry run that does not skip fails" \
    '(%s) # SKIP dry run: no CLI call\n' '(%s)\n' "dry-run skips the row instead of scoring it"
  break_sub "a dry run that exits 1 fails" \
    "    printf '# dry run: %d row(s) parsed, no CLI call\\n' \"\$total\"
    [ \"\$fails\" -eq 0 ] || exit 1
    exit 0" "    printf '# dry run: %d row(s) parsed, no CLI call\\n' \"\$total\"
    exit 1" "dry-run exits 0"
  break_sub "an empty unchecked marker fails" \
    'fexp = "U"' 'fexp = ""' "a row with no AND clause parses with U"

  # --- 9. check_fixtures.sh rejects broken considerations fixtures --------------
  # fixtures_case <label> <needle> <shell snippet run inside the copy's fixtures/>
  fixtures_case() {
    local label="$1" needle="$2" snippet="$3" t out rc
    t="$TMP/fx-$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
    copy_tree "$t"
    (cd "$t/fixtures" && eval "$snippet")
    out="$(bash "$t/lib/check_fixtures.sh" 2>&1)"
    rc=$?
    if [ "$rc" -ne 1 ]; then
      echo "FAIL: check_fixtures: $label -- exit $rc, wanted 1"
      fail=1
    elif ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
      echo "FAIL: check_fixtures: $label -- output lacks: $needle"
      fail=1
    else
      echo "ok: check_fixtures: $label"
    fi
  }
  fixtures_case "a .diff with no sidecar is refused" \
    "considerations/search_sort_partial.diff has no considerations/search_sort_partial.considerations sidecar" \
    'rm considerations/search_sort_partial.considerations'
  fixtures_case "a sidecar with no .diff is refused" \
    "considerations/orphan.considerations has no considerations/orphan.diff fixture" \
    'echo "An orphan consideration" > considerations/orphan.considerations'
  fixtures_case "a verdict-count mismatch is refused" \
    "considerations/search_sort_partial.diff: EXPECTED.md lists 2 verdict(s) but considerations/search_sort_partial.considerations has 3 consideration(s)" \
    'echo "A third consideration" >> considerations/search_sort_partial.considerations'
  fixtures_case "a fixture with no row is refused" \
    "Fixture files with no EXPECTED.md row" \
    'echo "x = 1" > unregistered_fixture.py'
  fixtures_case "a row with no fixture is refused" \
    "EXPECTED.md rows naming a fixture that does not exist" \
    'rm considerations/docs_only_none_mitigated.diff considerations/docs_only_none_mitigated.considerations'
fi

if [ "$fail" -ne 0 ]; then
  echo "eval invocation: FAILED"
  exit 1
fi
echo "eval invocation: all checks passed"
