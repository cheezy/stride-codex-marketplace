# PowerShell mirror of test-challenge-gate.sh — asserts the challenge-gate
# output contract documented in skills/stride-ideation/SKILL.md (W1370) and the
# Step-6 "## Design challenge" template in skills/stride-ideation-ideate/SKILL.md
# (W1370). The gate is an interactive Codex CLI question step that cannot be
# driven from a non-interactive runner, so this test asserts the *output
# contract* — the shape a committed requirements doc must exhibit once the gate
# has run — against the committed fixture
# fixtures/2026-05-12T120300-saved-filters-challenge-gate-requirements.md.
#
# Keep these assertions consistent with the .sh mirror and the documented gate
# output. If you change the documented gate output, update this test, the .sh
# mirror, and the fixture together.
#
# Run:
#   pwsh -File lib/test-challenge-gate.ps1
#
# Exits 0 if all tests pass, non-zero otherwise. No network, no external deps.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir
$Fixture = Join-Path $PluginRoot 'fixtures/2026-05-12T120300-saved-filters-challenge-gate-requirements.md'

$script:PASS = 0
$script:FAIL = 0
function Pass([string]$msg) { $script:PASS++; Write-Host "  PASS  $msg" }
function Fail([string]$msg, [string]$detail = '') {
    $script:FAIL++
    Write-Host "  FAIL  $msg"
    if ($detail) { Write-Host "        $detail" }
}

# --- reference shape assertions --------------------------------------------
#
# Each takes a requirements-doc path and returns $true when the file exhibits
# the gate output shape, $false otherwise. Pure line matching — no external deps.

# A "## Design challenge" H2 section is present.
function Gate-HasDesignChallengeSection([string]$path) {
    $lines = Get-Content -LiteralPath $path
    return [bool]($lines | Where-Object { $_ -match '^## Design challenge\s*$' })
}

# The Design challenge section names at least two distinct alternatives.
function Gate-HasTwoAlternatives([string]$path) {
    $lines = Get-Content -LiteralPath $path
    $count = @($lines | Where-Object { $_ -match '\*\*Alternative [A-Z]' }).Count
    return ($count -ge 2)
}

# The trade-off comparison covers all four dimensions: cost, risk, complexity,
# timeline (case-insensitive). Scoped to the trade-off TABLE — each dimension
# must appear as the first cell of a table row (e.g. "| Cost | ... |"), not
# merely somewhere in the prose.
function Gate-HasTradeOffDimensions([string]$path) {
    $lines = Get-Content -LiteralPath $path
    foreach ($dim in @('Cost', 'Risk', 'Complexity', 'Timeline')) {
        if (-not ($lines | Where-Object { $_ -match "^\s*\|\s*$dim\s*\|" })) {
            return $false
        }
    }
    return $true
}

# The Assumptions section carries at least one (high)/(medium)/(low) confidence
# rating produced by the assumption-confidence audit.
function Gate-HasConfidenceRatings([string]$path) {
    $lines = Get-Content -LiteralPath $path
    $inAssumptions = $false
    foreach ($line in $lines) {
        if ($line -match '^## Assumptions\s*$') { $inAssumptions = $true; continue }
        if ($inAssumptions -and $line -match '^## ') { $inAssumptions = $false }
        if ($inAssumptions -and $line -match '\((high|medium|low)\)') { return $true }
    }
    return $false
}

Write-Host 'test-challenge-gate.ps1 — asserts the challenge-gate output contract'
Write-Host ''

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "sti-gate-test-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    # === case 0: the fixture exists ===========================================
    if (Test-Path -LiteralPath $Fixture) {
        Pass "case 0: challenge-gate fixture exists at fixtures/$(Split-Path -Leaf $Fixture)"
    } else {
        Fail "case 0: challenge-gate fixture missing" $Fixture
        Write-Host ''
        Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
        exit 1
    }

    # === case 1: Design challenge section present (AC1) ========================
    if (Gate-HasDesignChallengeSection $Fixture) {
        Pass "case 1: fixture has a '## Design challenge' section"
    } else {
        Fail "case 1: fixture is missing the '## Design challenge' section"
    }

    # === case 2: two alternatives (AC1) =======================================
    if (Gate-HasTwoAlternatives $Fixture) {
        Pass "case 2: Design challenge names at least two alternatives"
    } else {
        Fail "case 2: fewer than two alternatives in the fixture"
    }

    # === case 3: trade-off covers cost/risk/complexity/timeline (AC1) =========
    if (Gate-HasTradeOffDimensions $Fixture) {
        Pass "case 3: trade-off comparison covers cost, risk, complexity, and timeline"
    } else {
        Fail "case 3: trade-off comparison is missing one of the four dimensions"
    }

    # === case 4: Assumptions carry confidence ratings (AC2) ===================
    if (Gate-HasConfidenceRatings $Fixture) {
        Pass "case 4: Assumptions section shows per-assumption confidence ratings"
    } else {
        Fail "case 4: no (high)/(medium)/(low) confidence ratings under Assumptions"
    }

    # === case 5: negative control — a doc with no alternatives must FAIL =======
    $noAlts = Join-Path $tmpDir 'no-alternatives-requirements.md'
    @'
# Bad fixture — gate output without alternatives

## Assumptions
- Users want this (R) (low)

## Design challenge
- **Blind spots:** we never considered the support team.
- **Trade-off comparison:** cost, risk, complexity, timeline — but no alternatives to compare against.
'@ | Set-Content -LiteralPath $noAlts -Encoding utf8

    if (Gate-HasTwoAlternatives $noAlts) {
        Fail "case 5: two-alternatives assertion wrongly passed a doc with no alternatives"
    } else {
        Pass "case 5: two-alternatives assertion correctly fails a doc with no alternatives (negative control)"
    }

    # === case 6: negative control — a doc with no confidence ratings must FAIL =
    $noConf = Join-Path $tmpDir 'no-confidence-requirements.md'
    @'
# Bad fixture — assumptions without confidence ratings

## Assumptions
- Users want this (R)
- Storage is cheap

## Constraints
- Reuse existing storage (low effort)
'@ | Set-Content -LiteralPath $noConf -Encoding utf8

    if (Gate-HasConfidenceRatings $noConf) {
        Fail "case 6: confidence-rating assertion wrongly passed unrated Assumptions" `
            "the '(low effort)' under Constraints must not be mistaken for an Assumptions rating"
    } else {
        Pass "case 6: confidence-rating assertion correctly fails unrated Assumptions, scoped to the Assumptions section (negative control)"
    }

    # === case 7: negative control — prose dimensions but no table must FAIL ====
    $noTable = Join-Path $tmpDir 'no-trade-off-table-requirements.md'
    @'
# Bad fixture — trade-off words in prose, no table

## Assumptions
- Users want this (R) (low)

## Design challenge
- **Alternative A:** do it one way.
- **Alternative B:** do it another way.
- **Trade-off comparison:** we weighed cost, risk, complexity, and timeline in our heads but never tabulated them.
'@ | Set-Content -LiteralPath $noTable -Encoding utf8

    if (Gate-HasTradeOffDimensions $noTable) {
        Fail "case 7: trade-off-dimensions assertion wrongly passed prose-only dimensions with no table"
    } else {
        Pass "case 7: trade-off-dimensions assertion correctly fails when the comparison table is absent (negative control)"
    }
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
