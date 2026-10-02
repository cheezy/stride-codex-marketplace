# PowerShell mirror of test-validate-batch.sh -- exercises validate_batch.py
# against known-good and known-broken JSON inputs.
#
# Every bash case has a one-for-one PowerShell counterpart, in the same order,
# with the same label text (em dashes in bash labels are written "--" here so
# this file stays ASCII-only) and the same needle. Needles are matched as
# case-sensitive literal substrings, like bash's `grep -F`.

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
$PluginRoot = Split-Path -Parent $ScriptDir
$Validator = Join-Path $ScriptDir 'validate_batch.py'

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-validate-batch.ps1 -- exercises validate_batch.py'
Write-Host ''

# Run the validator on a file; returns @{ rc; stdout; stderr } (strings, never $null).
function Invoke-ValidatorFile([string]$Path) {
    $errFile = New-TemporaryFile
    try {
        $stdout = & python3 $Validator $Path 2>$errFile.FullName
        $rc = $LASTEXITCODE
        $errText = Get-Content -Raw -LiteralPath $errFile.FullName -ErrorAction SilentlyContinue
        if ($null -eq $errText) { $errText = '' }
        return @{ rc = $rc; stdout = (@($stdout) -join "`n"); stderr = $errText }
    } finally {
        Remove-Item -Force $errFile.FullName -ErrorAction SilentlyContinue
    }
}

# Write JSON text to a temp fixture and run the validator on it.
function Invoke-Validator([string]$JsonText) {
    $tmp = New-TemporaryFile
    try {
        Set-Utf8NoBom $tmp.FullName $JsonText
        return Invoke-ValidatorFile $tmp.FullName
    } finally {
        Remove-Item -Force $tmp.FullName -ErrorAction SilentlyContinue
    }
}

# The five review-queue scored fields as a reusable JSON fragment, so a task
# under a length test does not also trip the advisory scored-field pass.
$Scored = '"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"security_considerations":["None - test fixture"],"pitfalls":["none"],"patterns_to_follow":"existing"'

function Assert-Ok($label, $json) {
    # Validator must exit 0 (structurally valid + within length bounds).
    # Advisory scored-field warnings on stderr are tolerated -- only the exit
    # code is asserted here.
    $r = Invoke-Validator $json
    if ($r.rc -eq 0) { Pass $label } else { Fail $label ("exit code != 0; stderr: $($r.stderr)") }
}

function Assert-OkFile($label, $path) {
    # Validate a file path directly; exit 0 (advisory stderr warnings tolerated).
    $r = Invoke-ValidatorFile $path
    if ($r.rc -eq 0) { Pass $label } else { Fail $label ("exit code != 0; stderr: $($r.stderr)") }
}

function Assert-Silent($label, $json) {
    # Validator must exit 0 with NO output at all -- no warnings, no errors,
    # on either stream (bash checks the combined 2>&1 output).
    $r = Invoke-Validator $json
    if ($r.rc -ne 0) {
        Fail $label ("exit code != 0; output: $($r.stdout)$($r.stderr)")
    } elseif ($r.stdout.Length -gt 0 -or $r.stderr.Length -gt 0) {
        Fail $label ("expected silence but got: $($r.stdout)$($r.stderr)")
    } else {
        Pass $label
    }
}

function Assert-FailsWith($label, $json, $needle) {
    # Validator must exit non-zero AND stderr must contain the substring.
    $r = Invoke-Validator $json
    if ($r.rc -eq 0) {
        Fail $label 'expected exit != 0 but got 0'
    } elseif ($r.stderr.Contains($needle)) {
        Pass $label
    } else {
        Fail $label ("expected substring: $needle; actual stderr: $($r.stderr)")
    }
}

function Assert-WarnsWith($label, $json, $needle) {
    # Validator must exit 0 AND stderr must contain the advisory warning.
    $r = Invoke-Validator $json
    if ($r.rc -ne 0) {
        Fail $label ("expected exit 0 but got non-zero; stderr: $($r.stderr)")
    } elseif ($r.stderr.Contains($needle)) {
        Pass $label
    } else {
        Fail $label ("expected stderr substring: $needle; actual stderr: $($r.stderr)")
    }
}

# --- (a) parse_error -------------------------------------------------------

Assert-FailsWith '(a) parse error -- invalid JSON exits with parse failure' `
    '{ this is not json' `
    'JSON parse failed'

# --- (b) wrong_root_key ----------------------------------------------------

Assert-FailsWith '(b) wrong root key ''tasks'' -- dedicated error message' `
    '{"tasks": [{"title": "x"}]}' `
    'root key ''tasks'' is the most common batch-API mistake'

Assert-FailsWith '(b) wrong root key ''batch'' -- named in error' `
    '{"batch": []}' `
    'missing the required ''goals'' array'

# --- (c) empty_goals -------------------------------------------------------

Assert-FailsWith '(c) empty goals array exits with under-specification hint' `
    '{"goals": []}' `
    'empty array'

Assert-FailsWith '(c) goals as object -- must be an array' `
    '{"goals": {"title": "oops"}}' `
    'must be an array'

# --- (d) goal_missing_field ------------------------------------------------

Assert-FailsWith '(d) goal missing title -- names the field' `
    '{"goals": [{"type": "goal", "tasks": []}]}' `
    'goals[0] is missing required field ''title'''

Assert-FailsWith '(d) goal missing tasks -- names the field' `
    '{"goals": [{"title": "T", "type": "goal"}]}' `
    'goals[0] is missing required field ''tasks'''

Assert-FailsWith '(d) goal with empty tasks array fails' `
    '{"goals": [{"title": "T", "type": "goal", "tasks": []}]}' `
    'goals[0].tasks is empty'

# --- (e) bad_dependency_index ---------------------------------------------

Assert-FailsWith '(e) dependency index out of range -- names the failing path' @'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": []},
        {"title": "Second", "type": "work", "dependencies": [5]}
      ]
    }
  ]
}
'@ 'goals[0].tasks[1].dependencies references index 5 but goal only has 2 tasks'

Assert-FailsWith '(e) forward-reference dependency fails' @'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": [1]},
        {"title": "Second", "type": "work", "dependencies": []}
      ]
    }
  ]
}
'@ 'must point to an earlier sibling'

Assert-FailsWith '(e) self-reference dependency fails' @'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": [0]}
      ]
    }
  ]
}
'@ 'must point to an earlier sibling'

Assert-FailsWith '(e) negative dependency index fails' @'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": [-1]}
      ]
    }
  ]
}
'@ 'is negative'

# --- happy paths -----------------------------------------------------------

Assert-Ok 'valid minimal document with one goal and one task' @'
{
  "decomposition_notes": "Single goal; no cross-goal deps.",
  "goals": [
    {
      "title": "Minimal goal",
      "type": "goal",
      "tasks": [
        {"title": "First task", "type": "work", "dependencies": []}
      ]
    }
  ]
}
'@

Assert-Ok 'valid document with chained sibling dependencies' @'
{
  "goals": [
    {
      "title": "Chained deps",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": []},
        {"title": "Second", "type": "work", "dependencies": [0]},
        {"title": "Third", "type": "work", "dependencies": [0, 1]}
      ]
    }
  ]
}
'@

Assert-Ok 'valid: string identifier dependencies are not bounds-checked' @'
{
  "goals": [
    {
      "title": "String identifier dep",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": ["W47"]}
      ]
    }
  ]
}
'@

# --- (f) length_limit -------------------------------------------------------
#
# The server binds title (goal and task) and each security_considerations
# element to varchar(255), which limits by Unicode CODE POINT -- not bytes.
# Length-test tasks carry the five scored fields so the length pass -- not
# the advisory pass -- is under test.

$t256 = 'x' * 256
Assert-FailsWith '(f) 256-char task title fails with its path and length' `
    ('{"goals":[{"title":"Goal","type":"goal","tasks":[{"title":"' + $t256 + '","type":"work","dependencies":[],' + $Scored + '}]}]}') `
    'goals[0].tasks[0].title is 256 characters'

$t255 = 'x' * 255
Assert-Silent '(f) boundary: exactly 255 characters passes silently' `
    ('{"goals":[{"title":"Goal","type":"goal","tasks":[{"title":"' + $t255 + '","type":"work","dependencies":[],' + $Scored + '}]}]}')

$g256 = 'g' * 256
Assert-FailsWith '(f) 256-char goal title fails with its path' `
    ('{"goals":[{"title":"' + $g256 + '","type":"goal","tasks":[{"title":"Task","type":"work","dependencies":[],' + $Scored + '}]}]}') `
    'goals[0].title is 256 characters'

$sec271 = 'y' * 271
Assert-FailsWith '(f) oversized security_considerations element names its element path' `
    ('{"goals":[{"title":"Goal","type":"goal","tasks":[{"title":"Task","type":"work","dependencies":[],"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"security_considerations":["fine","' + $sec271 + '"],"pitfalls":["none"],"patterns_to_follow":"existing"}]}]}') `
    'goals[0].tasks[0].security_considerations[1] is 271 characters'

$goalSec260 = 'z' * 260
Assert-FailsWith '(f) goal-level security_considerations element is also checked' `
    ('{"goals":[{"title":"Goal","type":"goal","tasks":[{"title":"Task","type":"work","dependencies":[],' + $Scored + '}],"security_considerations":["' + $goalSec260 + '"]}]}') `
    'goals[0].security_considerations[0] is 260 characters'

# Multibyte: 255 CJK chars is 765 UTF-8 bytes but exactly 255 code points --
# it must PASS, proving the check counts code points, not bytes. U+4E2D is
# built from its code point so this file stays ASCII-only.
$Cjk = [string][char]0x4E2D
$cjk255 = $Cjk * 255
Assert-Silent '(f) multibyte: 255 CJK code points (765 UTF-8 bytes) passes -- code points, not bytes' `
    ('{"goals":[{"title":"Goal","type":"goal","tasks":[{"title":"' + $cjk255 + '","type":"work","dependencies":[],' + $Scored + '}]}]}')

$cjk256 = $Cjk * 256
Assert-FailsWith '(f) multibyte: 256 CJK code points fails as 256 characters' `
    ('{"goals":[{"title":"Goal","type":"goal","tasks":[{"title":"' + $cjk256 + '","type":"work","dependencies":[],' + $Scored + '}]}]}') `
    'is 256 characters'

# --- advisory scored-field completeness (warnings on stderr, exit 0) --------
#
# Missing OR empty scored fields warn on stderr and never change the exit
# code. Both the missing-key and empty-array shapes are pinned.

Assert-WarnsWith 'advisory: missing scored-field KEY warns but validation passes' `
    '{"goals":[{"title":"Warn goal","type":"goal","tasks":[{"title":"Task without security_considerations","type":"work","dependencies":[],"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"pitfalls":["none"],"patterns_to_follow":"existing"}]}]}' `
    'goals[0].tasks[0].security_considerations is empty or missing'

Assert-WarnsWith 'advisory: EMPTY-ARRAY scored field warns the same as a missing key' `
    '{"goals":[{"title":"Warn goal","type":"goal","tasks":[{"title":"Task with empty pitfalls array","type":"work","dependencies":[],"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"security_considerations":["None - test fixture"],"pitfalls":[],"patterns_to_follow":"existing"}]}]}' `
    'goals[0].tasks[0].pitfalls is empty or missing'

Assert-Silent 'advisory: all five scored fields populated -- validator is completely silent' `
    ('{"goals":[{"title":"Fully populated goal","type":"goal","tasks":[{"title":"Fully populated task","type":"work","dependencies":[],' + $Scored + '}]}]}')

# Ordering pin: a fatal check must exit BEFORE any advisory warning prints.
# This fixture is both structurally invalid (self dep) and missing every
# scored field; the fatal exit must win and NO "warning:" line appears.
$r = Invoke-Validator '{"goals":[{"title":"Ordering goal","type":"goal","tasks":[{"title":"First","type":"work","dependencies":[0]}]}]}'
if ($r.rc -ne 0 -and -not $r.stderr.Contains('warning:')) {
    Pass 'advisory: warnings never precede a fatal failure (no warning on fatal exit)'
} else {
    Fail 'advisory: warnings never precede a fatal failure' ("exit: $($r.rc) stderr: $($r.stderr)")
}

# --- (b)/(d) task-level fields and a stray root 'tasks' key (D341) -----------

Assert-FailsWith '(d) task missing title fails with its path' `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"Ok","type":"work"},{"type":"work"}]}]}' `
    'goals[0].tasks[1] is missing required field ''title'''

Assert-FailsWith '(d) task with a whitespace-only title fails with its path' `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"   ","type":"work"}]}]}' `
    'goals[0].tasks[0].title must be a non-empty string'

Assert-FailsWith '(d) task with a non-string title fails with its path' `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":42,"type":"work"}]}]}' `
    'goals[0].tasks[0].title must be a non-empty string'

Assert-FailsWith '(d) task missing type fails with its path' `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T"}]}]}' `
    'goals[0].tasks[0] is missing required field ''type'''

Assert-FailsWith '(d) task type ''goal'' fails with its path' `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T","type":"goal"}]}]}' `
    'goals[0].tasks[0].type must be ''work'' or ''defect'', got ''goal'''

Assert-FailsWith '(d) task that is a string instead of an object fails with its path' `
    '{"goals":[{"title":"G","type":"goal","tasks":["just a title"]}]}' `
    'goals[0].tasks[0] must be an object, got str'

Assert-FailsWith '(b) root with both goals and tasks fails' `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"T","type":"work"}]}],"tasks":[{"title":"Stray","type":"work"}]}' `
    'root has both ''goals'' and ''tasks'''

Assert-Silent '(d) a defect task with every scored field passes silently' `
    '{"goals":[{"title":"G","type":"goal","tasks":[{"title":"Fix it","type":"defect","dependencies":[],"acceptance_criteria":"It works","testing_strategy":{"unit_tests":["one"]},"security_considerations":["None - test fixture"],"pitfalls":["none"],"patterns_to_follow":"existing"}]}]}'

# Real repo fixtures: every batch must be structurally valid and within the
# varchar(255) length bounds (exit 0). Advisory scored-field warnings are
# tolerated -- the notifications/replace-test-suite fixtures intentionally
# omit pitfalls/patterns_to_follow on their tasks.
Get-ChildItem (Join-Path $PluginRoot 'fixtures') -Filter '*-stride-batch.json' | ForEach-Object {
    Assert-OkFile "repo fixture is structurally valid and within length bounds: $($_.Name)" $_.FullName
}

# --- summary --------------------------------------------------------------

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
