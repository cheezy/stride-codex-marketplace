# PowerShell twin of test-ship.sh -- exercises lib/ship.py (the
# stride-ideation-stridify skill's Step 3 preflight, the --batch payload check,
# and Steps 9-10 POST + render) and the output of lib/read_auth.py, the way a
# Windows host without bash runs them.
#
# ship.py is one Python script both shells call, so this suite drives the same
# file test-ship.sh does. curl is replaced by a PATH-prepended fake (a Python
# script, wrapped as `curl` on POSIX and `curl.cmd` on Windows) that records
# its argv and environment, captures the -K config it reads from stdin, copies
# the --data-binary payload, and answers with a canned status/body/stderr/exit
# taken from FAKE_* env vars. No network access is needed. Every run gets its
# own TMPDIR/TMP/TEMP so the suite can assert no temp file outlives ship.py.
#
# Run:
#   pwsh -NoProfile -File lib/test-ship.ps1
#
# Exits 0 if all tests pass, non-zero otherwise.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Ship      = Join-Path $ScriptDir 'ship.py'
$ReadAuth  = Join-Path $ScriptDir 'read_auth.py'
$OnWindows = [System.IO.Path]::DirectorySeparatorChar -eq '\'

# python3 may be named python on Windows; use whichever exists.
$Python = (Get-Command python3 -ErrorAction SilentlyContinue)
if (-not $Python) { $Python = Get-Command python -ErrorAction Stop }
$Python = $Python.Source

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }
function Check([string]$Label, [bool]$Cond, [string]$Detail = '') { if ($Cond) { Pass $Label } else { Fail $Label $Detail } }
# A case that cannot run on this platform is reported, never counted as passed.
$script:SKIP = 0
function Skip($m) { $script:SKIP++; Write-Host "  SKIP  $m" }

Write-Host 'test-ship.ps1 -- exercises ship.py and read_auth.py'
Write-Host ''

# A fake value only -- the tests assert it never escapes into argv or output.
$Token = 'stride_dev_SHIP_TEST_TOKEN_9f3k'

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) "sti-ship-ps1-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
function J([string]$Name) { Join-Path $Tmp $Name }
function Write-Text([string]$Path, [string]$Text) { [System.IO.File]::WriteAllText($Path, $Text) }

try {

# --- fixtures -----------------------------------------------------------------

Write-Text (J 'auth.md') @"
# Stride API Authentication

- **API URL:** ``https://stride.example``
- **Local API Token:** ``stride_dev_LOCAL_TOKEN_SHOULD_NOT_MATCH``
- **API Token:** ``$Token``
"@
Write-Text (J 'auth-local-only.md') "- **API URL:** ``https://stride.example```n- **Local API Token:** ``stride_dev_LOCAL_ONLY_TOKEN_abc```n"

Write-Text (J 'batch.json') @'
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
'@
Write-Text (J 'created.json') '{"success": true, "total": 1, "goals": [{"goal": {"id": 1, "identifier": "G77", "title": "Goal one", "type": "goal"}, "child_tasks": [{"id": 2, "identifier": "W901", "title": "Task one"}, {"id": 3, "identifier": "D12", "title": "Task two"}]}]}'
Write-Text (J 'created-flat.json') '{"data": {"goals": [{"identifier": "G78", "title": "Flat goal", "tasks": [{"identifier": "W902", "title": "Flat task"}]}]}}'
Write-Text (J 'empty-goals.json') '{"success": true, "total": 0, "goals": []}'
Write-Text (J 'no-ident.json') '{"success": true, "goals": [{"goal": {"title": "no identifier"}, "child_tasks": []}]}'
Write-Text (J '500-debug.html') "<html><dt>authorization</dt><dd>Bearer $Token</dd><p>raw $Token</p><p>other Bearer abc.DEF-123</p></html>"
Write-Text (J '422.json') '{"error":"Validation failed","details":{"goals":["is invalid"]}}'
Write-Text (J '502.html') '<html>Bad gateway</html>'
Write-Text (J '302.html') '<html>moved</html>'
Write-Text (J 'notjson.txt') 'OK, but this is not JSON'
Write-Text (J 'list.json') '[1, 2, 3]'
Write-Text (J 'invalid-batch.json') '{"tasks": [{"title": "t", "type": "work"}]}'
Write-Text (J 'broken.json') '{"goals": ['
$batchDoc = Get-Content -Raw (J 'batch.json') | ConvertFrom-Json
$batchDoc.goals[0].tasks[0] | Add-Member -NotePropertyName description -NotePropertyValue "auth is $Token"
Write-Text (J 'token-batch.json') ($batchDoc | ConvertTo-Json -Depth 10)
$notesDoc = Get-Content -Raw (J 'batch.json') | ConvertFrom-Json
$notesDoc.decomposition_notes = "token $Token"
Write-Text (J 'token-notes.json') ($notesDoc | ConvertTo-Json -Depth 10)
Write-Text (J 'big.json') ('{"error":"' + ('x' * 200000) + '"}')

# --- fake curl ----------------------------------------------------------------

$Bin = J 'bin'
New-Item -ItemType Directory -Force -Path $Bin | Out-Null
Write-Text (Join-Path $Bin 'fake_curl.py') @'
# Fake curl for lib/test-ship.ps1. Behaviour comes from FAKE_* env vars.
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
'@
if ($OnWindows) {
    Write-Text (Join-Path $Bin 'curl.cmd') "@`"$Python`" `"%~dp0fake_curl.py`" %*`r`n"
} else {
    Write-Text (Join-Path $Bin 'curl') "#!/bin/sh`nexec '$Python' '$Bin/fake_curl.py' `"`$@`"`n"
    & chmod +x (Join-Path $Bin 'curl')
}

# Invoke-Ship <case> <args> [-Env @{...}] [-Auth file] [-Cwd dir] -- runs ship.py
# against the fake curl with an isolated temp dir. Sets $script:C (case dir),
# $script:Rc, $script:Out, $script:Err.
# Quote arguments for ProcessStartInfo.Arguments (Windows command-line rules).
# ProcessStartInfo.ArgumentList would be simpler, but Windows PowerShell 5.1 runs
# on .NET Framework, which does not have it.
function Join-ProcessArgs([string[]]$Values) {
    $quoted = foreach ($v in $Values) {
        if ($v -ne '' -and $v -notmatch '[\s"]') { $v; continue }
        $out = '"'; $bs = 0
        foreach ($ch in $v.ToCharArray()) {
            if ($ch -eq '\') { $bs++; continue }
            if ($ch -eq '"') { $out += ('\' * ($bs * 2 + 1)) + '"' } else { $out += ('\' * $bs) + $ch }
            $bs = 0
        }
        $out + ('\' * ($bs * 2)) + '"'
    }
    return ($quoted -join ' ')
}

function Start-Ship {
    param([string]$Case, [string[]]$ShipArgs, [hashtable]$Env = @{}, [string]$Auth = (J 'auth.md'), [string]$Cwd = $Tmp)
    $script:C = J "case-$Case"
    New-Item -ItemType Directory -Force -Path (Join-Path $script:C 'log'), (Join-Path $script:C 'tmpdir') | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Python
    $psi.Arguments = Join-ProcessArgs (@($Ship) + @($ShipArgs))
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Cwd
    $psi.EnvironmentVariables['PATH'] = $Bin + [System.IO.Path]::PathSeparator + $env:PATH
    foreach ($v in 'TMPDIR', 'TMP', 'TEMP') { $psi.EnvironmentVariables[$v] = (Join-Path $script:C 'tmpdir') }
    $psi.EnvironmentVariables['FAKE_LOG_DIR'] = (Join-Path $script:C 'log')
    foreach ($v in 'STRIDE_API_TOKEN', 'STRIDE_API_URL', 'FAKE_CODE', 'FAKE_BODY', 'FAKE_EXIT', 'FAKE_STDERR', 'FAKE_SLEEP') {
        $psi.EnvironmentVariables.Remove($v)
    }
    if ($Auth) { $psi.EnvironmentVariables['STRIDE_AUTH_FILE'] = $Auth } else { $psi.EnvironmentVariables.Remove('STRIDE_AUTH_FILE') }
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $script:OutTask = $p.StandardOutput.ReadToEndAsync()
    $script:ErrTask = $p.StandardError.ReadToEndAsync()
    return $p
}
function Wait-Ship($p) {
    $p.WaitForExit()
    $script:Out = $script:OutTask.Result
    $script:Err = $script:ErrTask.Result
    $script:Rc = $p.ExitCode
}
function Invoke-Ship {
    param([string]$Case, [string[]]$ShipArgs, [hashtable]$Env = @{}, [string]$Auth = (J 'auth.md'), [string]$Cwd = $Tmp)
    Wait-Ship (Start-Ship -Case $Case -ShipArgs $ShipArgs -Env $Env -Auth $Auth -Cwd $Cwd)
}
function Log([string]$Name) {
    $f = Join-Path (Join-Path $script:C 'log') $Name
    if (Test-Path -LiteralPath $f) { return [System.IO.File]::ReadAllText($f) }
    return ''
}
function LogLines([string]$Name) { @((Log $Name) -split "`n" | Where-Object { $_ -ne '' }) }

function Assert-Rc($Label, $Want) { Check $Label ($script:Rc -eq $Want) "exit $($script:Rc), want $Want; stderr: $($script:Err)" }
function Assert-Contains($Label, $Text, $Needle) { Check $Label ($Text.Contains($Needle)) "missing '$Needle'" }
function Assert-Lacks($Label, $Text, $Needle) { Check $Label (-not $Text.Contains($Needle)) "found '$Needle'" }
function Assert-NoTempLeft($Label) {
    $left = @(Get-ChildItem -Force -LiteralPath (Join-Path $script:C 'tmpdir'))
    Check $Label ($left.Count -eq 0) ("left behind: " + (($left | ForEach-Object { $_.Name }) -join ', '))
}
function Assert-NeverPosted($Label) { Check $Label ((Log 'argv') -eq '') 'curl ran' }
function Assert-NoToken($Label) {
    $hit = $script:Out.Contains($Token) -or $script:Err.Contains($Token) -or (Log 'argv').Contains($Token)
    Check $Label (-not $hit) 'token found in stdout, stderr or curl argv'
}
function Assert-Verbatim($Label, $Header, $BodyFile) {
    $want = $Header + "`n" + [System.IO.File]::ReadAllText($BodyFile) + "`n"
    Check $Label (($script:Err -replace "`r`n", "`n") -eq $want) 'stderr is not header + verbatim body'
}

# --- read_auth.py: shell-safe output -------------------------------------------

Write-Text (J 'auth-amp.md') "- **API URL:** ``https://stride.example/p?a=1&b=2```n- **API Token:** ``stride_dev_AMP_abc```n"
$o = (& $Python $ReadAuth (J 'auth-amp.md')) -join "`n"
Check 'read_auth: a URL containing & is shell-quoted' ($o -match "^STRIDE_API_URL='https://stride\.example/p\?a=1&b=2'`n") $o

Write-Text (J 'auth-subst.md') "- **API URL:** ``https://stride.example/`$(touch`${IFS}pwned)x;touch`${IFS}pwned2```n- **API Token:** ``stride_dev_SUBST_abc```n"
$o = (& $Python $ReadAuth (J 'auth-subst.md')) -join "`n"
Check 'read_auth: command-substitution and ; in a URL are single-quoted literally' ($o.StartsWith("STRIDE_API_URL='https://stride.example/`$(touch`${IFS}pwned)x;touch`${IFS}pwned2'")) $o

$o = (& $Python $ReadAuth (J 'auth.md')) -join "`n"
Check 'read_auth: plain values are still printed unquoted' ($o -eq "STRIDE_API_URL=https://stride.example`nSTRIDE_API_TOKEN=$Token") $o

# --- usage --------------------------------------------------------------------

Invoke-Ship usage @()
Assert-Rc 'ship: no argument is a usage error (exit 2)' 2
Assert-Contains 'ship: usage error names every form' $script:Err 'ship.py --check-auth | ship.py --check-payload <batch.json> | ship.py --preview <batch.json> | ship.py <batch.json>'

Invoke-Ship flagonly @('--yes')
Assert-Rc 'ship: an unknown flag is a usage error (exit 2)' 2
Assert-NeverPosted 'ship: an unknown flag never reaches curl'

Invoke-Ship missing @((J 'does-not-exist.json'))
Assert-Rc 'ship: a missing batch file exits 1' 1
Assert-Contains 'ship: missing batch file is named' $script:Err 'batch JSON not found at'
Assert-NeverPosted 'ship: a missing batch file never reaches curl'

# --- --check-auth ---------------------------------------------------------------

Invoke-Ship check-ok @('--check-auth')
Assert-Rc 'check-auth: valid auth exits 0' 0
Assert-Contains 'check-auth: reports the API URL' $script:Out 'API URL https://stride.example'
Assert-NoToken 'check-auth: token is not printed'
Assert-NeverPosted 'check-auth: makes no request'

Invoke-Ship check-local @('--check-auth') -Auth (J 'auth-local-only.md')
Assert-Rc 'check-auth: a file with only a Local API Token exits 1' 1
Assert-Contains 'check-auth: Local-only file reports the missing token' $script:Err 'STRIDE_API_TOKEN not found'
Assert-Lacks 'check-auth: Local token value is not echoed' $script:Err 'stride_dev_LOCAL_ONLY_TOKEN_abc'

Invoke-Ship check-missing @('--check-auth') -Auth (J 'no-such-auth.md')
Assert-Rc 'check-auth: a missing auth file exits 1' 1
Assert-Contains "check-auth: read_auth.py's not-found message is shown" $script:Err ".stride_auth.md not found at $(J 'no-such-auth.md')"
Assert-Contains 'check-auth: missing auth file is named' $script:Err "failed to read auth from $(J 'no-such-auth.md')"

$proj = J 'proj'
New-Item -ItemType Directory -Force -Path $proj | Out-Null
Copy-Item (J 'auth.md') (Join-Path $proj '.stride_auth.md')
Invoke-Ship check-cwd @('--check-auth') -Auth '' -Cwd $proj
Assert-Rc 'check-auth: finds .stride_auth.md in the current directory' 0
Assert-Contains 'check-auth: names the cwd auth file' $script:Out '.stride_auth.md'

# From a subdirectory of a git repository the project root's file is used.
$gp = J 'gitproj'
New-Item -ItemType Directory -Force -Path (Join-Path $gp 'sub/dir') | Out-Null
& git -C $gp init -q
Copy-Item (J 'auth.md') (Join-Path $gp '.stride_auth.md')
Invoke-Ship check-toplevel @('--check-auth') -Auth '' -Cwd (Join-Path $gp 'sub/dir')
Assert-Rc 'check-auth: from a subdirectory, finds .stride_auth.md at the git project root' 0
Assert-Contains 'check-auth: names the project-root auth file' $script:Out (Join-Path 'gitproj' '.stride_auth.md')

# --- --check-payload --------------------------------------------------------------

Invoke-Ship payload-ok @('--check-payload', (J 'batch.json'))
Assert-Rc 'check-payload: a clean batch exits 0' 0
Assert-NeverPosted 'check-payload: makes no request'

Invoke-Ship payload-token @('--check-payload', (J 'token-batch.json'))
Assert-Rc 'check-payload: a batch holding the token exits 1' 1
Assert-Contains 'check-payload: says the file holds the token' $script:Err 'contains the configured Stride API token; nothing was sent'
Assert-NoToken 'check-payload: the token is not printed'
Assert-NeverPosted 'check-payload: nothing is POSTed'

Invoke-Ship payload-notes @('--check-payload', (J 'token-notes.json'))
Assert-Rc 'check-payload: the token in decomposition_notes (stripped before POST) is still refused' 1

# A token spelled with a JSON \u escape decodes to the token the moment
# anything parses the file, so the screen must catch it too.
$escDoc = Get-Content -Raw (J 'batch.json') | ConvertFrom-Json
$escDoc.goals[0].type = '@@TOKEN@@'
Write-Text (J 'token-escaped.json') (($escDoc | ConvertTo-Json -Depth 10 -Compress).Replace('@@TOKEN@@', ('\u{0:x4}' -f [int][char]$Token[0]) + $Token.Substring(1)))
Invoke-Ship payload-escaped @('--check-payload', (J 'token-escaped.json'))
Assert-Rc 'check-payload: a token written with a JSON \u escape is refused' 1
Assert-NoToken 'check-payload: the escaped token is not printed'

Invoke-Ship payload-missing @('--check-payload', (J 'does-not-exist.json'))
Assert-Rc 'check-payload: a missing batch file exits 1' 1
Assert-Contains 'check-payload: missing batch file is named' $script:Err 'batch JSON not found at'

# --- 2xx with a renderable body --------------------------------------------------

Invoke-Ship ok @((J 'batch.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc '2xx: exits 0' 0
Assert-Contains '2xx: renders the goal row' $script:Out '     G77  Goal one'
Assert-Contains '2xx: renders a task row under its goal' $script:Out '    W901    Task one'
Assert-Contains '2xx: renders a defect row' $script:Out '     D12    Task two'
Assert-Contains '2xx: prints the terminal message' $script:Out 'Batch shipped successfully.'
Assert-NoToken '2xx: token is absent from argv, stdout and stderr'
Assert-Contains '2xx: token reached curl through the -K config on stdin' (Log 'config') "header = `"Authorization: Bearer $Token`""
$argv = LogLines 'argv'
$k = [array]::IndexOf($argv, '-K')
Check '2xx: curl reads its config from stdin (-K -), not a file' ($k -ge 0 -and $argv[$k + 1] -eq '-') ($argv -join ' ')
Check '2xx: URL globbing is off (-g)' ($argv -contains '-g')
if ($OnWindows) {
    Skip '2xx: payload file is mode 600 (POSIX file modes; not applicable on Windows)'
} else {
    Check '2xx: payload file is mode 600' ((Log 'payload.mode').Trim() -eq '0o600') (Log 'payload.mode')
}
Check '2xx: payload is sent with --data-binary @file' (($argv -contains '--data-binary') -and @($argv | Where-Object { $_.StartsWith('@') }).Count -eq 1) ($argv -join ' ')
Check '2xx: no -d/--data argument' (-not (($argv -contains '-d') -or ($argv -contains '--data')))
Check "2xx: -q is curl's first argument (no ~/.curlrc)" ($argv[0] -eq '-q') $argv[0]
Check '2xx: curl is never run verbose' (-not (($argv -contains '-v') -or ($argv -contains '--verbose')))
Assert-Contains '2xx: POSTs to the batch endpoint' (Log 'argv') 'https://stride.example/api/tasks/batch'
Assert-Lacks '2xx: source_spec is stripped from the payload' (Log 'payload') 'source_spec'
Assert-Lacks '2xx: decomposition_notes is stripped from the payload' (Log 'payload') 'decomposition_notes'
Assert-Contains '2xx: created_by_agent survives the strip' (Log 'payload') '"created_by_agent": "Codex CLI"'
Assert-Contains '2xx: the on-disk batch JSON is not modified' ([System.IO.File]::ReadAllText((J 'batch.json'))) '"source_spec"'
Assert-NoTempLeft '2xx: every temp file is removed'

Invoke-Ship flat @((J 'batch.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created-flat.json') }
Assert-Rc '2xx flat shape: exits 0' 0
Assert-Contains '2xx flat shape: renders the goal row' $script:Out '     G78  Flat goal'
Assert-Contains '2xx flat shape: renders the task row' $script:Out '    W902    Flat task'

Invoke-Ship noident @((J 'batch.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'no-ident.json') }
Assert-Rc '2xx without identifiers: exits 0' 0
Assert-Contains '2xx without identifiers: prints the do-not-re-run notice' $script:Err 'do NOT re-run stride-ideation-stridify'
Check '2xx without identifiers: prints no placeholder table' ($script:Out -eq '') $script:Out

Invoke-Ship emptygoals @((J 'batch.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'empty-goals.json') }
Assert-Rc '2xx listing no goals: exits 0' 0
Assert-Contains '2xx listing no goals: says no goals were listed' $script:Err 'listed no created goals'
Assert-Lacks '2xx listing no goals: does not claim goals already exist' $script:Err 'already exist'

# --- failures before any request ------------------------------------------------

Invoke-Ship tokenbatch @((J 'token-batch.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc 'token in batch: exits 1' 1
Assert-Contains 'token in batch: says nothing was sent' $script:Err 'contains the configured Stride API token; nothing was sent'
Assert-NeverPosted 'token in batch: nothing is POSTed'
Assert-NoToken 'token in batch: the token is not printed'
Assert-NoTempLeft 'token in batch: every temp file is removed'

Invoke-Ship invalidbatch @((J 'invalid-batch.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc 'invalid batch: exits 1' 1
Assert-Contains 'invalid batch: says nothing was sent' $script:Err 'failed validation; nothing was sent'
Assert-Contains "invalid batch: the validator's reason is shown" $script:Err "root key 'tasks'"
Assert-NeverPosted 'invalid batch: nothing is POSTed'
Assert-NoTempLeft 'invalid batch: every temp file is removed'

# The validator quotes a goal's type; one holding the token must be
# scrubbed, because the token screen runs only after validation.
Write-Text (J 'token-key.json') ('{"goals": [{"title": "G", "type": "' + $Token + '", "tasks": [{"title": "t", "type": "work"}]}]}')
Invoke-Ship tokenkey @((J 'token-key.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc 'invalid batch quoting the token: exits 1' 1
Assert-Contains "invalid batch quoting the token: the validator's reason is still shown" $script:Err "goals[0].type must be 'goal'"
Assert-NoToken "invalid batch quoting the token: the token is scrubbed from the validator's message"
Assert-Contains 'invalid batch quoting the token: shown as [REDACTED]' $script:Err '[REDACTED]'
Assert-NeverPosted 'invalid batch quoting the token: nothing is POSTed'

Invoke-Ship badpayload @((J 'broken.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc 'unparseable batch: exits 1' 1
Assert-Contains 'unparseable batch: names the payload failure' $script:Err "failed to prepare API payload from $(J 'broken.json')"
Assert-NeverPosted 'unparseable batch: nothing is POSTed'
Assert-NoToken 'unparseable batch: token is not printed'
Assert-NoTempLeft 'unparseable batch: every temp file is removed'

Invoke-Ship postlocal @((J 'batch.json')) -Auth (J 'auth-local-only.md') -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc 'POST with only a Local API Token: exits 1' 1
Assert-NeverPosted 'POST with only a Local API Token: nothing is POSTed'
Assert-NoTempLeft 'POST with only a Local API Token: every temp file is removed'

Invoke-Ship envtoken @((J 'batch.json')) -Env @{ STRIDE_API_TOKEN = 'stride_dev_INHERITED_ENV_TOKEN'; FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc 'inherited STRIDE_API_TOKEN: still ships' 0
Check "inherited STRIDE_API_TOKEN: curl's environment carries no token" ((Log 'env-token').Trim() -eq 'no')
Assert-Contains "inherited STRIDE_API_TOKEN: the auth file's token is the one sent" (Log 'config') "Bearer $Token"

# --- 2xx with a body that cannot be rendered --------------------------------------

Invoke-Ship notjson @((J 'batch.json')) -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'notjson.txt') }
Assert-Rc '2xx non-JSON: exits 0 (the batch exists)' 0
Assert-Contains '2xx non-JSON: prints the do-not-re-run notice' $script:Err 'do NOT re-run stride-ideation-stridify'
Assert-Contains '2xx non-JSON: says the batch was created' $script:Err 'the batch was created (HTTP 201), but the response could not be rendered'
Assert-Contains '2xx non-JSON: shows the body verbatim' $script:Err 'OK, but this is not JSON'
Assert-Lacks '2xx non-JSON: no Python traceback' $script:Err 'Traceback'
Assert-Lacks '2xx non-JSON: no success message' $script:Out 'Batch shipped successfully.'
Assert-NoTempLeft '2xx non-JSON: every temp file is removed'

Invoke-Ship listroot @((J 'batch.json')) -Env @{ FAKE_CODE = '200'; FAKE_BODY = (J 'list.json') }
Assert-Rc '2xx JSON list: exits 0' 0
Assert-Contains '2xx JSON list: prints the do-not-re-run notice' $script:Err 'do NOT re-run stride-ideation-stridify'
Assert-Lacks '2xx JSON list: no Python traceback' $script:Err 'Traceback'
Check '2xx JSON list: prints no partial table' ($script:Out -eq '') $script:Out

# --- non-2xx --------------------------------------------------------------------

Invoke-Ship 422 @((J 'batch.json')) -Env @{ FAKE_CODE = '422'; FAKE_BODY = (J '422.json') }
Assert-Rc '422: exits 1' 1
Assert-Verbatim '422: header line then the body verbatim' 'stride-ideation: Stride API rejected the batch (HTTP 422). Response body:' (J '422.json')
Assert-NoToken '422: token is not printed'
Assert-NoTempLeft '422: every temp file is removed'

Invoke-Ship 502 @((J 'batch.json')) -Env @{ FAKE_CODE = '502'; FAKE_BODY = (J '502.html') }
Assert-Rc '5xx: exits 1' 1
Assert-Verbatim '5xx: header line then the body verbatim' 'stride-ideation: Stride API returned HTTP 502. Response body:' (J '502.html')
Assert-NoTempLeft '5xx: every temp file is removed'

Invoke-Ship debug500 @((J 'batch.json')) -Env @{ FAKE_CODE = '500'; FAKE_BODY = (J '500-debug.html') }
Assert-Rc '5xx debug page: exits 1' 1
Assert-NoToken '5xx debug page: the echoed token is scrubbed from stderr'
Assert-Contains '5xx debug page: the token is shown as [REDACTED]' $script:Err '<dd>Bearer [REDACTED]</dd><p>raw [REDACTED]</p>'
Assert-Contains '5xx debug page: any other Bearer value is scrubbed too' $script:Err 'other Bearer [REDACTED]</p>'

Invoke-Ship 302 @((J 'batch.json')) -Env @{ FAKE_CODE = '302'; FAKE_BODY = (J '302.html') }
Assert-Rc '3xx: exits 1' 1
Assert-Verbatim '3xx: header line then the body verbatim' 'stride-ideation: unexpected HTTP status 302. Response body:' (J '302.html')

Invoke-Ship big @((J 'batch.json')) -Env @{ FAKE_CODE = '422'; FAKE_BODY = (J 'big.json') }
Assert-Rc 'large 422 body: exits 1' 1
Assert-Verbatim 'large 422 body: printed verbatim in full' 'stride-ideation: Stride API rejected the batch (HTTP 422). Response body:' (J 'big.json')

# --- transport failures -----------------------------------------------------------

Invoke-Ship dns @((J 'batch.json')) -Env @{ FAKE_CODE = '000'; FAKE_EXIT = '6'; FAKE_STDERR = 'curl: (6) Could not resolve host: stride.example' }
Assert-Rc 'transport failure: exits 1' 1
Check 'transport failure: curl stderr is printed verbatim' (($script:Err -replace "`r`n", "`n") -eq "stride-ideation: HTTP request failed before the Stride API responded:`ncurl: (6) Could not resolve host: stride.example`n") $script:Err
Assert-NoToken 'transport failure: token is not printed'
Assert-NoTempLeft 'transport failure: every temp file is removed'

Invoke-Ship silent @((J 'batch.json')) -Env @{ FAKE_CODE = '000'; FAKE_EXIT = '28' }
Assert-Rc 'silent transport failure: exits 1' 1
Assert-Contains "silent transport failure: names curl's exit status" $script:Err 'curl exited with status 28 and no stderr output.'

# A token with the Base64 characters real Stride tokens carry, echoed back in
# transformed forms a server or proxy might use.
$SlashToken = 'stride_dev_Ab/Cd+Ef=Gh/IjKl'
Write-Text (J 'auth-slash.md') "- **API URL:** ``https://stride.example```n- **API Token:** ``$SlashToken```n"
$q = [System.Uri]::EscapeDataString($SlashToken)
$qLower = $q.Replace('%2F', '%2f').Replace('%2B', '%2b').Replace('%3D', '%3d')
Write-Text (J '500-encoded.html') ("json-escaped: " + $SlashToken.Replace('/', '\/') + "`n" + "percent-upper: $q`n" + "percent-lower: $qLower`n" + "truncated: " + $SlashToken.Substring(0, 20) + "`n" + "header: Bearer%20$q`n")
Invoke-Ship encoded @((J 'batch.json')) -Auth (J 'auth-slash.md') -Env @{ FAKE_CODE = '500'; FAKE_BODY = (J '500-encoded.html') }
Assert-Rc '5xx encoded echoes: exits 1' 1
$leaks = @($SlashToken, $SlashToken.Replace('/', '\/'), $q, $qLower, $SlashToken.Substring(0, 20), 'Ab/Cd', 'Ab%2FCd') | Where-Object { $script:Err.Contains($_) }
Check '5xx encoded echoes: JSON-escaped, percent-encoded and truncated token forms are all scrubbed' (@($leaks).Count -eq 0) ($leaks -join ', ')
Assert-Contains '5xx encoded echoes: the surrounding text is kept' $script:Err 'json-escaped: [REDACTED]'
Assert-Contains '5xx encoded echoes: a token with / and + reaches curl intact' (Log 'config') "Bearer $SlashToken`""

# --- interrupt mid-POST (POSIX signals; Windows has no SIGINT/SIGTERM to send) ------

foreach ($sig in 'INT', 'TERM', 'HUP', 'QUIT') {
    if ($OnWindows) {
        Skip "SIG$sig mid-POST: no POSIX signals on Windows"
        continue
    }
    $p = Start-Ship -Case "sig-$sig" -ShipArgs @((J 'batch.json')) -Env @{ FAKE_SLEEP = '3'; FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
    $started = Join-Path (Join-Path $script:C 'log') 'started'
    for ($i = 0; $i -lt 100 -and -not (Test-Path -LiteralPath $started); $i++) { Start-Sleep -Milliseconds 100 }
    & kill "-$sig" $p.Id
    Wait-Ship $p
    $want = @{ INT = 130; TERM = 143; HUP = 129; QUIT = 131 }[$sig]
    Assert-Rc "SIG$sig mid-POST: exits $want" $want
    Assert-NoTempLeft "SIG$sig mid-POST: every temp file is removed"
    Assert-Lacks "SIG$sig mid-POST: does not render or claim success" $script:Out 'Batch shipped successfully.'
    Assert-Lacks "SIG$sig mid-POST: no Python traceback" $script:Err 'Traceback'
    Assert-Contains "SIG$sig mid-POST: warns the batch may already exist" $script:Err 'the batch may already exist'
}

# --- --batch: the stridify Step 1b sequence ships an existing file as-is ----------
#
# Step 1b is skill prose; this drives the exact helper sequence it runs
# (ship.py --check-payload, validate_batch.py, the Step 8.5a ship.py --preview,
# then the Step 9 ship.py call)
# against a committed batch, and asserts nothing is decomposed, rewritten or
# committed along the way.

$Repo = J 'batch-repo'
$BatchName = '2026-05-12T103000-x-stride-batch.json'
New-Item -ItemType Directory -Force -Path $Repo | Out-Null
& git -C $Repo init -q
& git -C $Repo config user.email test@example.com
& git -C $Repo config user.name test
Copy-Item (J 'batch.json') (Join-Path $Repo $BatchName)
& git -C $Repo add .
& git -C $Repo commit -q -m 'stride-ideation: decomposition for x'
$beforeSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Repo $BatchName)).Hash
$beforeCount = (& git -C $Repo rev-list --count HEAD)

Invoke-Ship batch-check @('--check-payload', $BatchName) -Cwd $Repo
Assert-Rc '--batch: ship.py --check-payload passes' 0
& $Python (Join-Path $ScriptDir 'validate_batch.py') (Join-Path $Repo $BatchName) 2>$null | Out-Null
Check '--batch: the committed batch passes validate_batch.py' ($LASTEXITCODE -eq 0)
Invoke-Ship batch-preview @('--preview', $BatchName) -Cwd $Repo
Assert-Rc '--batch: the Step 8.5a preview exits 0' 0
Assert-Contains '--batch: the preview names the goal and its task count' $script:Out '  Goal: Goal one  (1 task)'
Assert-Contains '--batch: the preview lists the task' $script:Out '    - Task one'
Assert-Contains '--batch: the preview shows the claim order' $script:Out 'claim order: G1 first'
Assert-NoToken '--batch: the preview prints no token'
Assert-NeverPosted '--batch: the preview sends nothing'
Invoke-Ship batch-ship @($BatchName) -Cwd $Repo -Env @{ FAKE_CODE = '201'; FAKE_BODY = (J 'created.json') }
Assert-Rc '--batch: ship.py ships the file' 0
Assert-Contains '--batch: the created identifiers are rendered' $script:Out '     G77  Goal one'
Check '--batch: the batch file is byte-for-byte unchanged' ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Repo $BatchName)).Hash -eq $beforeSha)
Check '--batch: no commit is created' ((& git -C $Repo rev-list --count HEAD) -eq $beforeCount)
Check '--batch: the working tree stays clean' ([string]::IsNullOrEmpty((& git -C $Repo status --porcelain) -join ''))

Invoke-Ship preview-missing @('--preview', (J 'does-not-exist.json'))
Assert-Rc '--preview: a missing batch file exits 1' 1
Invoke-Ship preview-broken @('--preview', (J 'broken.json'))
Assert-Rc '--preview: an unparseable batch exits 1 without a traceback' 1
Assert-Lacks '--preview: no Python traceback' $script:Err 'Traceback'

# --- the stridify skill documents the ship.py flow, not the old fragments ---------

$Skill = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $ScriptDir) 'skills/stride-ideation-stridify/SKILL.md'))
Assert-Contains 'SKILL: Step 3 preflight calls ship.py --check-auth' $Skill 'lib/ship.py" --check-auth || exit 1'
Assert-Contains 'SKILL: Step 9 ships through one ship.py call' $Skill 'python3 "$HELPER_ROOT/lib/ship.py" ''<value of BATCH_PATH>'''
Assert-Lacks 'SKILL: no <plugin-root> placeholder remains' $Skill '<plugin-root>'
Assert-Lacks 'SKILL: no CLAUDE_PROJECT_DIR reference remains' $Skill 'CLAUDE_PROJECT_DIR'
Assert-Contains 'SKILL: --batch accepts the --batch=<value> form' $Skill '`--batch=<value>`'
Assert-Contains 'SKILL: --batch with --goal is rejected' $Skill 'cannot be combined with --goal'
Assert-Contains 'SKILL: --batch screens the file with --check-payload' $Skill 'ship.py" --check-payload'
Assert-Contains 'SKILL: the Step 8.5a preview is one ship.py call' $Skill "lib/ship.py`" --preview '<value of BATCH_PATH>'"
Assert-Contains 'SKILL: --batch warns about shipping a batch twice' $Skill 'shipping it again creates every goal and task a second time'
Assert-Contains 'SKILL: the decline message points at --batch' $Skill 'Ship it later, unchanged, by activating stride-ideation-stridify with: --batch'
Assert-Lacks 'SKILL: no eval of read_auth.py output remains' $Skill 'eval "$AUTH_OUT"'
Assert-Lacks "SKILL: no token on curl's command line" $Skill 'Bearer $STRIDE_API_TOKEN'
Assert-Lacks 'SKILL: no payload passed with -d' $Skill '-d "$API_PAYLOAD"'
Assert-Lacks 'SKILL: no claim that curl -H hides the token' $Skill 'is fine because curl'
Assert-Lacks 'SKILL: the Step 7.5 recovery no longer asks for a manual POST' $Skill 'manual POST'

} finally {
    Remove-Item -Recurse -Force -LiteralPath $Tmp -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:SKIP -gt 0) { Write-Host ("{0} skipped (not applicable on this platform)" -f $script:SKIP) }
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 }
exit 0
