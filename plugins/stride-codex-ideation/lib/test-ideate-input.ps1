# PowerShell mirror of test-ideate-input.sh - exercises the
# stride-ideation-ideate argument parse documented in
# skills/stride-ideation-ideate/SKILL.md Step 1: the --input <file> brain-dump
# seed, the --continue <path> / --continue=<path> forms and the --profile
# values (W2198).
#
# The platform file-read / question UI is only available inside a live Codex
# CLI session, so this test embeds reference implementations of the documented
# Step 1 flag parse, the file-exists validation, and the Step 4c read-only
# invariant, and exercises them. The reference implementations MUST stay
# consistent with Step 1 / Step 4c in skills/stride-ideation-ideate/SKILL.md
# and with the bash mirror lib/test-ideate-input.sh - if you edit one, edit all.
#
# Run:
#   pwsh -File lib/test-ideate-input.ps1
#
# Exits 0 if all tests pass, non-zero otherwise.

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

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-ideate-input.ps1 - exercises the --input parse + read-only seed'
Write-Host ''

# --- reference flag parser -------------------------------------------------
# Mirrors SKILL.md Step 1. Returns @{ Continue; Input; Remainder }.
function Parse-Flags([string]$ArgString) {
    $tokens = @($ArgString -split '\s+' | Where-Object { $_ -ne '' })
    $continuePath = ''
    $inputPath = ''
    $err = ''
    $rest = @()
    $i = 0
    while ($i -lt $tokens.Count) {
        $t = $tokens[$i]
        if ($t -eq '--continue') {
            if ($i + 1 -lt $tokens.Count -and -not $tokens[$i + 1].StartsWith('--')) {
                $i++
                $continuePath = $tokens[$i]
            } else {
                $err = 'continue-missing'
            }
        } elseif ($t -like '--continue=*') {
            $continuePath = $t.Substring('--continue='.Length)
            if (-not $continuePath) { $err = 'continue-missing' }
        } elseif ($t -eq '--input') {
            $i++
            if ($i -lt $tokens.Count) { $inputPath = $tokens[$i] }
        } elseif ($t -like '--input=*') {
            $inputPath = $t.Substring('--input='.Length)
        } else {
            $rest += $t
        }
        $i++
    }
    return @{ Continue = $continuePath; Input = $inputPath; Remainder = ($rest -join ' '); Error = $err }
}

# --- reference --input validation ------------------------------------------
# Mirrors SKILL.md Step 1's INPUT_PATH existence check. Returns '' when OK
# (unset or existing file), or the one-line error naming the path when it is
# set but missing (the bash twin prints it to stderr and returns 1).
function Get-InputPathError([string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return '' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "stride-ideation: --input file not found: $Path"
    }
    return ''
}

# --- reference read-only seed read -----------------------------------------
# Mirrors SKILL.md Step 4c. Reads read-only; MUST NOT modify the file.
function Read-InputNotes([string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return '' }
    return (Get-Content -LiteralPath $Path -Raw)
}

# === temp dir + fixtures ===================================================

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('stiideinput_' + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmpDir | Out-Null

$notes = Join-Path $tmpDir 'notes.md'
Set-Utf8NoBom $notes @'
# Rough notes

We want a daily digest so approvers stop missing requests.
Assume people read email. SMTP relay is fine.
'@
$notesShaBefore = (Get-FileHash -LiteralPath $notes -Algorithm SHA256).Hash


$emptyNotes = Join-Path $tmpDir 'empty.md'
# A truly zero-byte file (Set-Utf8NoBom would write a trailing newline).
New-Item -ItemType File -Path $emptyNotes -Force | Out-Null

# The parse-only cases pass these relative names, not the temp-dir fixtures:
# the reference parser never touches the filesystem, and a temp dir whose path
# holds a space (a Windows profile name, say) would split into two tokens.
$argNotes = 'notes.md'
$argPrior = 'docs/ideation/2026-05-12T120000-thing-requirements.md'

try {
    # === case 1: --input <path> and --input=<path> both parse =============
    $pSpace = Parse-Flags "--input $argNotes my topic here"
    $pEquals = Parse-Flags "--input=$argNotes my topic here"
    if ($pSpace.Input -ceq $argNotes -and $pEquals.Input -ceq $argNotes) {
        Pass 'case 1: --input <path> and --input=<path> both parse to INPUT_PATH (AC1)'
    } else {
        Fail 'case 1: --input parse wrong' "space=[$($pSpace.Input)] equals=[$($pEquals.Input)]"
    }
    if ($pSpace.Remainder -ceq 'my topic here' -and $pEquals.Remainder -ceq 'my topic here') {
        Pass 'case 1: the --input tokens are consumed and the TOPIC remainder is preserved'
    } else {
        Fail 'case 1: remainder wrong after --input consumption' "space=[$($pSpace.Remainder)] equals=[$($pEquals.Remainder)]"
    }

    # === case 2: absence leaves INPUT_PATH empty, topic intact ============
    $pNone = Parse-Flags 'just a plain topic'
    if ([string]::IsNullOrEmpty($pNone.Input) -and $pNone.Remainder -ceq 'just a plain topic') {
        Pass 'case 2: no --input leaves INPUT_PATH empty and TOPIC intact'
    } else {
        Fail 'case 2: absence handling wrong' "input=[$($pNone.Input)] rem=[$($pNone.Remainder)]"
    }

    # === case 3: validation - existing file OK, missing file errors (AC1) ==
    if ((Get-InputPathError $notes) -ceq '') {
        Pass 'case 3: validate accepts an existing --input file (rc 0)'
    } else {
        Fail 'case 3: validate rejected an existing file'
    }
    $missing = Join-Path $tmpDir 'does-not-exist.md'
    $missingErr = Get-InputPathError $missing
    if ($missingErr -ceq '') {
        Fail 'case 3: validate accepted a missing file (should fail)'
    } elseif ($missingErr.Contains("--input file not found: $missing")) {
        Pass 'case 3: missing --input file -> one-line error naming the path + non-zero (edge case)'
    } else {
        Fail 'case 3: missing-file error message wrong' $missingErr
    }

    # === case 4: unset INPUT_PATH validates OK (no seed) ==================
    if ((Get-InputPathError '') -ceq '') {
        Pass 'case 4: unset INPUT_PATH validates cleanly (no-seed session)'
    } else {
        Fail 'case 4: unset INPUT_PATH was rejected'
    }

    # === case 5: read is read-only - file byte-for-byte unchanged (AC3) ===
    $seed = Read-InputNotes $notes
    $notesShaAfter = (Get-FileHash -LiteralPath $notes -Algorithm SHA256).Hash
    if ($notesShaBefore -ceq $notesShaAfter) {
        Pass 'case 5: --input file is byte-for-byte unchanged after the read (read-only invariant)'
    } else {
        Fail 'case 5: --input file was modified by the read (pitfall violated)'
    }
    if ($seed -match 'daily digest') {
        Pass 'case 5: Read-InputNotes returns the file contents as seed material'
    } else {
        Fail 'case 5: seed content not returned' $seed
    }
    if (Test-Path -LiteralPath $notes) {
        Pass 'case 5: --input file still exists at its original path (not moved)'
    } else {
        Fail 'case 5: --input file was moved/removed (pitfall violated)'
    }

    # === case 6: --input and --continue parse independently (precedence, AC4) ==
    $pBoth = Parse-Flags "--continue $argPrior --input $argNotes leftover topic"
    if ($pBoth.Continue -ceq $argPrior -and $pBoth.Input -ceq $argNotes -and $pBoth.Remainder -ceq 'leftover topic') {
        Pass 'case 6: --continue and --input populate independently when both passed (AC4)'
    } else {
        Fail 'case 6: combined parse wrong' "continue=[$($pBoth.Continue)] input=[$($pBoth.Input)] rem=[$($pBoth.Remainder)]"
    }

    # === case 7: empty --input file is valid (falls back to a full session) ===
    if ((Get-InputPathError $emptyNotes) -ceq '') {
        $emptySeed = Read-InputNotes $emptyNotes
        if ([string]::IsNullOrEmpty($emptySeed)) {
            Pass 'case 7: empty --input file validates and yields empty seed (full session fallback, edge case)'
        } else {
            Fail 'case 7: empty file produced non-empty seed' $emptySeed
        }
    } else {
        Fail 'case 7: empty --input file was rejected by validation'
    }

    # === case 8: --continue accepts both shapes, split on the first = only ===
    $continueCases = @(
        @('case 8a: --continue <path> sets CONTINUE_PATH', "--continue $argPrior", $argPrior, ''),
        @('case 8b: --continue=<path> sets CONTINUE_PATH', "--continue=$argPrior", $argPrior, ''),
        @('case 8c: --continue=<path> keeps an = inside the path', '--continue=docs/a=b-requirements.md', 'docs/a=b-requirements.md', ''),
        @('case 8d: --continue= with an empty value is an error', '--continue= topic', '', 'continue-missing'),
        @('case 8e: a bare trailing --continue is an error', 'topic --continue', '', 'continue-missing'),
        @('case 8f: --continue followed by a flag never takes the flag as its path', "--continue --input $argNotes", '', 'continue-missing')
    )
    foreach ($c in $continueCases) {
        $pc = Parse-Flags $c[1]
        if ($pc.Continue -ceq $c[2] -and $pc.Error -ceq $c[3]) { Pass $c[0] } else { Fail $c[0] "path=[$($pc.Continue)] err=[$($pc.Error)]" }
    }
    $p8 = Parse-Flags "--continue=$argPrior --input=$argNotes"
    if ($p8.Input -ceq $argNotes -and $p8.Continue -ceq $argPrior) {
        Pass 'case 8g: --continue=<path> and --input=<path> parse together'
    } else {
        Fail 'case 8g: combined = forms' "continue=[$($p8.Continue)] input=[$($p8.Input)]"
    }
    $skillMd = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'skills/stride-ideation-ideate/SKILL.md'
    $skillText = [System.IO.File]::ReadAllText($skillMd)
    if ($skillText.Contains('for the `--continue=<path>` form') -and $skillText.Contains('stride-ideation: --continue requires a path to a prior -requirements.md doc')) {
        Pass 'case 8h: SKILL.md Step 1 documents --continue=<path> and the missing-value error'
    } else {
        Fail 'case 8h: SKILL.md Step 1 is missing a --continue rule this test mirrors'
    }

    # === case 9: --profile accepts the four values and fails fast otherwise ==
    # Mirrors SKILL.md Step 1's --profile rule (both shapes; anything other
    # than the four names, or a missing value, is a one-line error and a stop).
    # Returns @{ Profile; Error }.
    function Parse-Profile([string]$ArgString) {
        $tokens = @($ArgString -split '\s+' | Where-Object { $_ -ne '' })
        $profileName = ''
        $seen = $false
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $t = $tokens[$i]
            if ($t -ceq '--profile') {
                $seen = $true
                if ($i + 1 -lt $tokens.Count -and -not $tokens[$i + 1].StartsWith('--')) { $i++; $profileName = $tokens[$i] }
            } elseif ($t.StartsWith('--profile=')) {
                $seen = $true
                $profileName = $t.Substring('--profile='.Length)
            }
        }
        if ($seen -and -not (@('lean', 'product', 'discovery', 'lean-startup') -ccontains $profileName)) {
            return @{ Profile = ''; Error = "stride-ideation: unknown --profile value '$profileName'; expected one of: lean, product, discovery, lean-startup" }
        }
        return @{ Profile = $profileName; Error = '' }
    }
    function Expect-Profile([string]$Label, [string]$ArgString, [string]$Want) {
        $r = Parse-Profile $ArgString
        if (-not $r.Error -and $r.Profile -ceq $Want) { Pass $Label } else { Fail $Label "got=[$($r.Profile)] err=[$($r.Error)]" }
    }
    Expect-Profile 'case 9a: --profile <name> sets PROFILE' '--profile product approval flows' 'product'
    Expect-Profile 'case 9b: --profile=<name> sets PROFILE' '--profile=lean-startup approval flows' 'lean-startup'
    Expect-Profile 'case 9c: no --profile leaves PROFILE empty (the recommendation question runs)' 'approval flows' ''
    foreach ($bad in @('--profile=foo topic', '--profile Lean topic', 'topic --profile', '--profile= topic')) {
        $r = Parse-Profile $bad
        if ($r.Error -cmatch "^stride-ideation: unknown --profile value '.*'; expected one of: lean, product, discovery, lean-startup$") {
            Pass "case 9d: an unknown or missing --profile value fails fast: $bad"
        } else {
            Fail "case 9d: an unknown or missing --profile value fails fast: $bad" "err=[$($r.Error)]"
        }
    }
    if ($skillText.Contains("stride-ideation: unknown --profile value 'foo'; expected one of: lean, product, discovery, lean-startup")) {
        Pass 'case 9e: SKILL.md Step 1 documents the --profile error this test mirrors'
    } else {
        Fail 'case 9e: SKILL.md Step 1 is missing the --profile error this test mirrors'
    }
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
