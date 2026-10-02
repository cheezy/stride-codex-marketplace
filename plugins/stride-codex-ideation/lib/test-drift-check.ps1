# PowerShell mirror of test-drift-check.sh -- exercises drift_check.py
# against in-sync, drifted, unstamped, unresolvable and malformed batch JSON.
#
# Every bash case has a one-for-one PowerShell counterpart with the same
# label text and the same assertion strength. stderr is captured separately
# from stdout so the "stderr is empty" and stderr-needle cases are real.

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
$DriftChecker = Join-Path $ScriptDir 'drift_check.py'

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

# The stderr of the most recent Invoke-Drift run (mirrors bash's $TMP/last.err).
$script:LastErr = ''

# Run drift_check.py on a fixture; stdout is discarded, stderr is kept in
# $script:LastErr. Returns the exit code.
function Invoke-Drift([string]$Fixture) {
    $errFile = New-TemporaryFile
    try {
        & python3 $DriftChecker $Fixture 2>$errFile.FullName | Out-Null
        $rc = $LASTEXITCODE
        $text = Get-Content -Raw -LiteralPath $errFile.FullName
        if ($null -eq $text) { $text = '' }
        $script:LastErr = $text
        return $rc
    } finally {
        Remove-Item -Force $errFile.FullName -ErrorAction SilentlyContinue
    }
}

# Assert-Exit <label> <fixture> <expected-exit>
function Assert-Exit([string]$Label, [string]$Fixture, [int]$Expected) {
    $actual = Invoke-Drift $Fixture
    if ($actual -eq $Expected) {
        Pass $Label
    } else {
        Fail $Label "expected exit $Expected, got $actual; stderr: $($script:LastErr)"
    }
}

# Assert-ExitWithMsg <label> <fixture> <expected-exit> <stderr-substring>
function Assert-ExitWithMsg([string]$Label, [string]$Fixture, [int]$Expected, [string]$Needle) {
    $actual = Invoke-Drift $Fixture
    if ($actual -ne $Expected) {
        Fail $Label "expected exit $Expected, got $actual; stderr: $($script:LastErr)"
        return
    }
    if ($script:LastErr.Contains($Needle)) {
        Pass $Label
    } else {
        Fail $Label "expected substring: $Needle; actual stderr: $($script:LastErr)"
    }
}

Write-Host 'test-drift-check.ps1 -- exercises drift_check.py'
Write-Host ''

$Tmp = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "sti-drift-$(Get-Random)") -Force).FullName
try {

# --- fixture: a known source doc + its real SHA -----------------------------

$srcPath = Join-Path $Tmp 'requirements.md'
Set-Utf8NoBom $srcPath @'
# Fake requirements doc

## Problem
test
'@

$RealSha = (Get-FileHash -LiteralPath $srcPath -Algorithm SHA256).Hash.ToLowerInvariant()

# --- no drift: matching SHA ------------------------------------------------
# source_spec is RELATIVE here (as in the bash fixture): drift_check.py must
# resolve it against the batch JSON's directory, not the current directory
# (this script never sets its location to $Tmp).

$noDrift = Join-Path $Tmp 'no_drift.json'
Set-Utf8NoBom $noDrift @"
{
  "source_spec": "requirements.md",
  "source_spec_sha256": "$RealSha",
  "decomposition_notes": "",
  "goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work"}]}]
}
"@
Assert-Exit 'no drift: matching SHA exits 0 silently' $noDrift 0

# Verify stderr is empty on no-drift
if ($script:LastErr.Length -gt 0) {
    Fail 'no drift: stderr should be empty' $script:LastErr
} else {
    Pass 'no drift: stderr is empty'
}

# --- drift: mismatched SHA -------------------------------------------------

$drift = Join-Path $Tmp 'drift.json'
Set-Utf8NoBom $drift @'
{
  "source_spec": "requirements.md",
  "source_spec_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "decomposition_notes": "",
  "goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work"}]}]
}
'@
Assert-ExitWithMsg 'drift: mismatched SHA exits 1 with DRIFT DETECTED message' $drift 1 'DRIFT DETECTED'

# --- drift: stderr names both stamped and recomputed SHA -------------------

if ($script:LastErr.Contains('stamped SHA-256:') -and $script:LastErr.Contains('recomputed SHA-256:')) {
    Pass 'drift: stderr names both stamped and recomputed SHA values'
} else {
    Fail 'drift: stderr missing stamped/recomputed labels' $script:LastErr
}

# --- absent source_spec: hand-written-JSON path proceeds silently -----------

$noSourceSpec = Join-Path $Tmp 'no_source_spec.json'
Set-Utf8NoBom $noSourceSpec '{"goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work"}]}]}'
Assert-Exit 'absent source_spec: exits 0 (hand-written path)' $noSourceSpec 0
if ($script:LastErr.Length -gt 0) {
    Fail 'absent source_spec: stderr should be empty' $script:LastErr
} else {
    Pass 'absent source_spec: stderr is empty'
}

# --- present source_spec but absent SHA: proceed silently -------------------

$noSha = Join-Path $Tmp 'no_sha.json'
Set-Utf8NoBom $noSha @'
{
  "source_spec": "requirements.md",
  "goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work"}]}]
}
'@
Assert-Exit 'source_spec present but SHA absent: exits 0 (no baseline)' $noSha 0

# --- source_spec points at a missing file ----------------------------------

$missingSource = Join-Path $Tmp 'missing_source.json'
Set-Utf8NoBom $missingSource @'
{
  "source_spec": "does_not_exist.md",
  "source_spec_sha256": "abcdef",
  "goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work"}]}]
}
'@
Assert-ExitWithMsg 'missing source_spec file: exits 2 with resolution error' $missingSource 2 'could not be resolved'

# --- malformed batch JSON itself --------------------------------------------

$bad = Join-Path $Tmp 'bad.json'
Set-Utf8NoBom $bad 'not json'
Assert-ExitWithMsg 'malformed batch JSON: exits 2 with read/parse error' $bad 2 'could not read batch JSON'

# --- source_spec given as absolute path -------------------------------------
# ConvertTo-Json escapes the path (backslashes on Windows) into a JSON string.

$absSource = Join-Path $Tmp 'abs_source.json'
$absSpec = $srcPath | ConvertTo-Json
Set-Utf8NoBom $absSource @"
{
  "source_spec": $absSpec,
  "source_spec_sha256": "$RealSha",
  "goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work"}]}]
}
"@
Assert-Exit 'absolute source_spec path resolves correctly' $absSource 0

# --- PS-only extra: real drift by editing the source doc --------------------
# The bash suite fakes drift with a zero SHA; this also proves an actual edit
# to the source doc flips the in-sync absolute fixture above to drift.

Add-Content -LiteralPath $srcPath -Value "`nNew line" -Encoding UTF8
Assert-ExitWithMsg 'drift detected when source modified' $absSource 1 'DRIFT DETECTED'

} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

# --- summary ----------------------------------------------------------------

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
