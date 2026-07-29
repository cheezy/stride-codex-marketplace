# PowerShell mirror of test-validate-batch.sh — exercises validate_batch.py
# against known-good and known-broken JSON inputs.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir
$Validator = Join-Path $ScriptDir 'validate_batch.py'

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-validate-batch.ps1 — exercises validate_batch.py'
Write-Host ''

function Invoke-Validator([string]$JsonText) {
    $tmp = New-TemporaryFile
    Set-Content -LiteralPath $tmp.FullName -Value $JsonText -Encoding UTF8
    $errFile = New-TemporaryFile
    $stdout = & python3 $Validator $tmp.FullName 2>$errFile.FullName
    $rc = $LASTEXITCODE
    $errText = Get-Content -Raw -LiteralPath $errFile.FullName -ErrorAction SilentlyContinue
    Remove-Item -Force $tmp.FullName, $errFile.FullName -ErrorAction SilentlyContinue
    return @{ rc = $rc; stderr = $errText }
}

# The five review-queue scored fields as a reusable JSON fragment, so a task
# under a length test does not also trip the advisory scored-field pass.
$Scored = '"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"security_considerations":["None - test fixture"],"pitfalls":["none"],"patterns_to_follow":"existing"'

function Assert-FailsWith($label, $json, $needle) {
    # Validator must exit non-zero AND stderr must contain the substring.
    $r = Invoke-Validator $json
    if ($r.rc -ne 0 -and ($r.stderr -match [regex]::Escape($needle))) {
        Pass $label
    } else {
        Fail $label ("rc=$($r.rc) stderr=$($r.stderr)")
    }
}

function Assert-WarnsWith($label, $json, $needle) {
    # Validator must exit 0 AND stderr must contain the advisory warning.
    $r = Invoke-Validator $json
    if ($r.rc -eq 0 -and ($r.stderr -match [regex]::Escape($needle))) {
        Pass $label
    } else {
        Fail $label ("rc=$($r.rc) stderr=$($r.stderr)")
    }
}

function Assert-Silent($label, $json) {
    # Validator must exit 0 with no output at all — no warnings, no errors.
    $r = Invoke-Validator $json
    if ($r.rc -eq 0 -and [string]::IsNullOrEmpty($r.stderr)) {
        Pass $label
    } else {
        Fail $label ("rc=$($r.rc) stderr=$($r.stderr)")
    }
}

function Assert-OkFile($label, $path) {
    # Validate a file path directly; exit 0 (advisory stderr warnings tolerated).
    $errFile = New-TemporaryFile
    & python3 $Validator $path 2>$errFile.FullName | Out-Null
    $rc = $LASTEXITCODE
    Remove-Item -Force $errFile.FullName -ErrorAction SilentlyContinue
    if ($rc -eq 0) { Pass $label } else { Fail $label "rc=$rc" }
}

# Stage 1: a well-formed minimal batch passes.
$ok = @'
{"goals": [{"title": "Test goal", "type": "goal", "tasks": [{"title": "T1", "type": "work"}]}]}
'@
$r = Invoke-Validator $ok
if ($r.rc -eq 0) { Pass "well-formed batch accepted" } else { Fail "well-formed batch rejected" $r.stderr }

# Stage 2: malformed JSON triggers parse_error.
$r = Invoke-Validator 'not json at all {{'
if ($r.rc -ne 0 -and ($r.stderr -match 'parse|JSON')) { Pass "parse_error reported on bad JSON" } else { Fail "parse_error not detected" $r.stderr }

# Stage 3: wrong root key (tasks instead of goals) reports the common mistake.
$wrongRoot = '{"tasks": [{"title": "x", "type": "work"}]}'
$r = Invoke-Validator $wrongRoot
if ($r.rc -ne 0 -and ($r.stderr -match "(?i)root.*key|tasks|goals")) {
    Pass "wrong_root_key detected"
} else {
    Fail "wrong_root_key not detected" $r.stderr
}

# Stage 4: empty goals array.
$r = Invoke-Validator '{"goals": []}'
if ($r.rc -ne 0 -and ($r.stderr -match "empty|goals")) { Pass "empty_goals detected" } else { Fail "empty_goals not detected" $r.stderr }

# Stage 5: goal missing required field (title).
$missingField = '{"goals": [{"type": "goal", "tasks": []}]}'
$r = Invoke-Validator $missingField
if ($r.rc -ne 0 -and ($r.stderr -match "title|required|missing")) {
    Pass "goal_missing_field detected"
} else {
    Fail "goal_missing_field not detected" $r.stderr
}

# Stage 6: bad dependency index (forward reference).
$badDep = @'
{"goals": [{"title": "G", "type": "goal", "tasks": [
    {"title": "T1", "type": "work", "dependencies": [5]}
]}]}
'@
$r = Invoke-Validator $badDep
if ($r.rc -ne 0 -and ($r.stderr -match "dependency|dependencies|index|references")) {
    Pass "bad_dependency_index detected"
} else {
    Fail "bad_dependency_index not detected" $r.stderr
}

# Stage 7: (f) length_limit — title and security_considerations are bound to
# varchar(255), measured in Unicode code points (not bytes). Length-test tasks
# carry the five scored fields so the length pass — not the advisory pass — is
# under test.
$t256 = 'x' * 256
Assert-FailsWith "(f) 256-char task title fails with its path" `
    ('{"goals":[{"title":"G","type":"goal","tasks":[{"title":"' + $t256 + '","type":"work","dependencies":[],' + $Scored + '}]}]}') `
    "goals[0].tasks[0].title is 256 characters"

$t255 = 'x' * 255
Assert-Silent "(f) boundary: exactly 255 characters passes silently" `
    ('{"goals":[{"title":"G","type":"goal","tasks":[{"title":"' + $t255 + '","type":"work","dependencies":[],' + $Scored + '}]}]}')

$g256 = 'g' * 256
Assert-FailsWith "(f) 256-char goal title fails with its path" `
    ('{"goals":[{"title":"' + $g256 + '","type":"goal","tasks":[{"title":"T","type":"work","dependencies":[],' + $Scored + '}]}]}') `
    "goals[0].title is 256 characters"

$sec271 = 'y' * 271
Assert-FailsWith "(f) oversized security_considerations element names its path" `
    ('{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T","type":"work","dependencies":[],"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"security_considerations":["fine","' + $sec271 + '"],"pitfalls":["none"],"patterns_to_follow":"existing"}]}]}') `
    "goals[0].tasks[0].security_considerations[1] is 271 characters"

$cjk255 = '中' * 255
Assert-Silent "(f) multibyte: 255 CJK code points (765 UTF-8 bytes) passes — code points, not bytes" `
    ('{"goals":[{"title":"G","type":"goal","tasks":[{"title":"' + $cjk255 + '","type":"work","dependencies":[],' + $Scored + '}]}]}')

$cjk256 = '中' * 256
Assert-FailsWith "(f) multibyte: 256 CJK code points fails as 256 characters" `
    ('{"goals":[{"title":"G","type":"goal","tasks":[{"title":"' + $cjk256 + '","type":"work","dependencies":[],' + $Scored + '}]}]}') `
    "is 256 characters"

# Stage 8: advisory scored-field completeness — warnings on stderr, exit 0.
Assert-WarnsWith "advisory: missing scored-field key warns but validation passes" `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T","type":"work","dependencies":[],"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"pitfalls":["none"],"patterns_to_follow":"existing"}]}]}' `
    "goals[0].tasks[0].security_considerations is empty or missing"

Assert-WarnsWith "advisory: empty-array scored field warns the same as a missing key" `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T","type":"work","dependencies":[],"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"security_considerations":["ok"],"pitfalls":[],"patterns_to_follow":"existing"}]}]}' `
    "goals[0].tasks[0].pitfalls is empty or missing"

Assert-Silent "advisory: all five scored fields populated — validator is completely silent" `
    ('{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T","type":"work","dependencies":[],' + $Scored + '}]}]}')

# Ordering pin: a fatal check must exit BEFORE any advisory warning prints.
$r = Invoke-Validator '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T","type":"work","dependencies":[0]}]}]}'
if ($r.rc -ne 0 -and ($r.stderr -notmatch 'warning:')) {
    Pass "advisory: warnings never precede a fatal failure (no warning on fatal exit)"
} else {
    Fail "advisory: fatal must beat warning" ("rc=$($r.rc) stderr=$($r.stderr)")
}

# Stage 9: real repo fixtures are structurally valid and within length bounds.
Get-ChildItem (Join-Path $PluginRoot 'fixtures') -Filter '*-stride-batch.json' | ForEach-Object {
    Assert-OkFile "repo fixture valid + within length bounds: $($_.Name)" $_.FullName
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
