# PowerShell mirror of test-ship-helpers.sh -- exercises read_auth.py and
# strip_audit_fields.py with auth-file fixtures and stamped batch JSON.
#
# Every bash case has a one-for-one PowerShell counterpart with the same
# label text (em dashes in bash labels are written "--" here so this file
# stays ASCII-only), and the same assertion strength.

Set-StrictMode -Version Latest

function Set-Utf8NoBom([string]$Path, $Value) {
    # Write a fixture as UTF-8 without a BOM and with LF newlines on every
    # host (the same text Set-Content would write): Windows PowerShell 5.1's
    # Set-Content -Encoding UTF8 adds a BOM, which the Python helpers' utf-8
    # reads reject in a JSON or markdown file.
    $text = (@($Value) -join "`n") + "`n"
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    [System.IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($false)))
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReadAuth = Join-Path $ScriptDir 'read_auth.py'
$StripAudit = Join-Path $ScriptDir 'strip_audit_fields.py'

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

# Run a python helper with stdout and stderr captured separately.
# Returns @{ rc; stdout; stderr } with both streams as single strings.
function Invoke-Py([string]$Script, [string]$Arg) {
    $errFile = New-TemporaryFile
    try {
        $stdout = & python3 $Script $Arg 2>$errFile.FullName
        $rc = $LASTEXITCODE
        $stderr = Get-Content -Raw -LiteralPath $errFile.FullName
        if ($null -eq $stderr) { $stderr = '' }
        return @{ rc = $rc; stdout = (@($stdout) -join "`n"); stderr = $stderr }
    } finally {
        Remove-Item -Force $errFile.FullName -ErrorAction SilentlyContinue
    }
}

$Onboarding = 'https://www.stridelikeaboss.com/api/agent/onboarding'

Write-Host 'test-ship-helpers.ps1 -- exercises read_auth.py + strip_audit_fields.py'
Write-Host ''

$Tmp = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "sti-shiphelpers-$(Get-Random)")
try {

# --- strip_audit_fields: happy path -----------------------------------------

$withAudit = Join-Path $Tmp 'with_audit.json'
Set-Utf8NoBom $withAudit @'
{
  "source_spec": "fixtures/x.md",
  "source_spec_sha256": "abc123",
  "decomposition_notes": "notes",
  "goals": [
    {"title": "G1", "type": "goal", "tasks": [{"title": "T1", "type": "work"}]}
  ]
}
'@

# Record the on-disk file's pre-strip SHA + contents so the
# "file is unchanged" assertion below has a fixed baseline.
$withAuditShaBefore = (Get-FileHash -LiteralPath $withAudit -Algorithm SHA256).Hash.ToLowerInvariant()
Copy-Item -LiteralPath $withAudit -Destination "$withAudit.before"

$r = Invoke-Py $StripAudit $withAudit
if ($r.rc -eq 0) {
    $s = $r.stdout
    if ($s -match 'source_spec') { Fail 'strip: did not remove source_spec' $s }
    elseif ($s -match 'source_spec_sha256') { Fail 'strip: did not remove source_spec_sha256' $s }
    elseif ($s -match 'decomposition_notes') { Fail 'strip: did not remove decomposition_notes' $s }
    elseif ($s -notmatch 'goals') { Fail 'strip: removes audit fields but lost goals' $s }
    else { Pass 'strip: removes all three audit fields; preserves goals' }
} else {
    Fail 'strip: exited non-zero on valid input' ($r.stdout + $r.stderr)
}

# AC: the on-disk file must be unchanged after stripping. This is the
# audit-trail guarantee -- the local-audit fields stay on disk so the
# drift check has something to compare against.
$withAuditShaAfter = (Get-FileHash -LiteralPath $withAudit -Algorithm SHA256).Hash.ToLowerInvariant()
if ($withAuditShaBefore -eq $withAuditShaAfter) {
    $beforeBytes = [System.IO.File]::ReadAllBytes("$withAudit.before")
    $afterBytes = [System.IO.File]::ReadAllBytes($withAudit)
    if ([Convert]::ToBase64String($beforeBytes) -ceq [Convert]::ToBase64String($afterBytes)) {
        Pass 'strip: on-disk file is byte-for-byte unchanged after run'
    } else {
        Fail 'strip: SHAs matched but byte comparison disagreed'
    }
} else {
    Fail 'strip: on-disk file was modified by the helper' "before SHA=$withAuditShaBefore after SHA=$withAuditShaAfter"
}

# --- strip_audit_fields: idempotent when fields already absent --------------

$noAudit = Join-Path $Tmp 'no_audit.json'
Set-Utf8NoBom $noAudit '{"goals": [{"title": "G1", "type": "goal", "tasks": [{"title": "T1", "type": "work"}]}]}'

$r = Invoke-Py $StripAudit $noAudit
if ($r.rc -eq 0) {
    if ($r.stdout -match 'goals') {
        Pass 'strip: idempotent -- passes through when audit fields absent'
    } else {
        Fail 'strip: passes through but lost goals' $r.stdout
    }
} else {
    Fail 'strip: failed on input that already lacked audit fields' $r.stderr
}

# --- strip_audit_fields: created_by_agent on goals survives the strip -------
# AC (W1535): created_by_agent is a per-goal create-payload field the Stride
# API persists for attribution in the /agents feed. strip_audit_fields.py
# removes only the three root-level local-audit fields
# (source_spec/source_spec_sha256/decomposition_notes); the per-goal
# created_by_agent MUST survive to the API payload.

$withCreatedBy = Join-Path $Tmp 'with_created_by.json'
Set-Utf8NoBom $withCreatedBy @'
{
  "source_spec": "fixtures/x.md",
  "source_spec_sha256": "abc123",
  "decomposition_notes": "notes",
  "goals": [
    {"title": "G1", "type": "goal", "created_by_agent": "Codex CLI", "tasks": [{"title": "T1", "type": "work"}]}
  ]
}
'@

$r = Invoke-Py $StripAudit $withCreatedBy
if ($r.rc -eq 0) {
    if ($r.stdout -match 'created_by_agent') {
        if ($r.stdout -notmatch 'source_spec|decomposition_notes') {
            Pass 'strip: preserves per-goal created_by_agent while removing the three audit fields'
        } else {
            Fail 'strip: created_by_agent survived but an audit field was not stripped' $r.stdout
        }
    } else {
        Fail 'strip: stripped created_by_agent (it must survive to the API payload)' $r.stdout
    }
} else {
    Fail 'strip: exited non-zero on input with created_by_agent' ($r.stdout + $r.stderr)
}

# --- strip_audit_fields: malformed JSON -------------------------------------

$badJson = Join-Path $Tmp 'bad.json'
Set-Utf8NoBom $badJson '{ not json'

$r = Invoke-Py $StripAudit $badJson
if ($r.rc -eq 0) {
    Fail 'strip: exited 0 on malformed JSON (expected non-zero)'
} elseif ($r.stderr.Contains('could not read')) {
    Pass 'strip: surfaces a read/parse error on malformed JSON'
} else {
    Fail 'strip: failed on malformed JSON but error message missing' $r.stderr
}

# --- read_auth: happy path --------------------------------------------------

$authFile = Join-Path $Tmp '.stride_auth.md'
Set-Utf8NoBom $authFile @'
# Stride API Authentication

## API Configuration

- **API URL:** `https://www.stridelikeaboss.com`
- **Local API Token:** `stride_dev_LOCAL_TOKEN_SHOULD_NOT_MATCH`
- **API Token:** `stride_dev_REAL_TOKEN_xyz123`
- **User Email:** `cheezy@example.com`
'@

$r = Invoke-Py $ReadAuth $authFile
if ($r.rc -eq 0) {
    $urlLine = @($r.stdout -split "`n" | Where-Object { $_ -like 'STRIDE_API_URL=*' }) -join "`n"
    $tokenLine = @($r.stdout -split "`n" | Where-Object { $_ -like 'STRIDE_API_TOKEN=*' }) -join "`n"
    if ($urlLine -ceq 'STRIDE_API_URL=https://www.stridelikeaboss.com') {
        Pass 'read_auth: extracts STRIDE_API_URL'
    } else {
        Fail 'read_auth: URL line mismatch' $urlLine
    }
    if ($tokenLine -ceq 'STRIDE_API_TOKEN=stride_dev_REAL_TOKEN_xyz123') {
        Pass 'read_auth: extracts API Token (NOT the Local API Token)'
    } else {
        Fail 'read_auth: token mismatch -- picked up wrong line' '(token line withheld)'
    }
} else {
    Fail 'read_auth: exited non-zero on a valid file' $r.stderr
}

# --- read_auth: missing URL --------------------------------------------------

$noUrl = Join-Path $Tmp 'no_url.md'
Set-Utf8NoBom $noUrl '- **API Token:** `stride_xxx`'

$noUrlResult = Invoke-Py $ReadAuth $noUrl
if ($noUrlResult.rc -eq 0) {
    Fail 'read_auth: exited 0 when URL missing'
} elseif ($noUrlResult.stderr.Contains('STRIDE_API_URL not found')) {
    Pass 'read_auth: errors on missing API URL with the right message'
} else {
    Fail 'read_auth: missing-URL error message wrong' $noUrlResult.stderr
}

# --- read_auth: missing token ----------------------------------------------

$noToken = Join-Path $Tmp 'no_token.md'
Set-Utf8NoBom $noToken '- **API URL:** `https://www.stridelikeaboss.com`'

$noTokenResult = Invoke-Py $ReadAuth $noToken
if ($noTokenResult.rc -eq 0) {
    Fail 'read_auth: exited 0 when token missing'
} elseif ($noTokenResult.stderr.Contains('STRIDE_API_TOKEN not found')) {
    Pass 'read_auth: errors on missing API Token with the right message'
} else {
    Fail 'read_auth: missing-token error message wrong' $noTokenResult.stderr
}

# --- read_auth: token MUST NOT appear in stderr (security pitfall) ----------

$withToken = Join-Path $Tmp 'with_token.md'
Set-Utf8NoBom $withToken @'
- **API URL:** `https://example.com`
- **API Token:** `stride_dev_SUPER_SECRET_TOKEN_xyz_DO_NOT_LEAK`
'@

# This is the happy-path file but we want to deliberately tickle the
# missing-URL branch by stripping the URL line, to confirm stderr never
# carries the token value if any other branch happened to surface text. The
# run must also fail with the missing-URL error, so a crash with empty stderr
# cannot pass vacuously.
$leakTest = Join-Path $Tmp 'leak_test.md'
$leakLines = Get-Content -LiteralPath $withToken | ForEach-Object { $_ -replace '- \*\*API URL.*', '' }
Set-Utf8NoBom $leakTest $leakLines

$r = Invoke-Py $ReadAuth $leakTest
if ($r.rc -eq 0) {
    Fail 'read_auth: token value NEVER appears in stderr (security)' 'exited 0 without an API URL'
} elseif ($r.stderr.Contains('stride_dev_SUPER_SECRET_TOKEN')) {
    # Never echo the leaked stderr: it carries the (fake) token.
    Fail 'read_auth: token value LEAKED in stderr' '(stderr withheld)'
} elseif (-not $r.stderr.Contains('STRIDE_API_URL not found')) {
    Fail 'read_auth: token value NEVER appears in stderr (security)' 'the missing-URL branch did not run'
} else {
    Pass 'read_auth: token value NEVER appears in stderr (security)'
}

# --- read_auth: nonexistent path --------------------------------------------

$missingResult = Invoke-Py $ReadAuth (Join-Path $Tmp 'does_not_exist.md')
if ($missingResult.rc -eq 0) {
    Fail 'read_auth: exited 0 on nonexistent file'
} elseif ($missingResult.stderr.Contains('.stride_auth.md not found')) {
    Pass 'read_auth: errors cleanly on missing file'
} else {
    Fail 'read_auth: missing-file error message wrong' $missingResult.stderr
}

# --- read_auth: missing file error includes setup-doc link ------------------

if ($missingResult.stderr.Contains($Onboarding)) {
    Pass 'read_auth: missing-file error links to the setup docs'
} else {
    Fail 'read_auth: missing-file error does not link to setup docs' $missingResult.stderr
}

# --- read_auth: missing-URL error also links to setup docs ------------------

if ($noUrlResult.stderr.Contains($Onboarding)) {
    Pass 'read_auth: missing-URL error links to the setup docs'
} else {
    Fail 'read_auth: missing-URL error does not link to setup docs' $noUrlResult.stderr
}

# --- read_auth: missing-token error also links to setup docs ----------------

if ($noTokenResult.stderr.Contains($Onboarding)) {
    Pass 'read_auth: missing-token error links to the setup docs'
} else {
    Fail 'read_auth: missing-token error does not link to setup docs' $noTokenResult.stderr
}

} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

# --- summary ----------------------------------------------------------------

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
