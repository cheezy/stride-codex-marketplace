<#
.SYNOPSIS
    Structure smoke test for the stride-codex-exploratory-testing plugin (PowerShell twin).

.DESCRIPTION
    Asserts the plugin ships every file the Codex CLI edition requires: a
    valid manifest with the four Codex keys, all five command-skills, all
    five doctrine skills, both agents, the three README-referenced fixtures,
    and the root docs (including AGENTS.md and both installers). Codex ships
    NO command files, so there is no commands/ check. JSON is parsed with
    ConvertFrom-Json — no network, no jq. Mirrors lib/test-structure.sh.

    Exit code: 0 if every check passes; 1 if any check fails.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$script:Pass = 0
$script:Fail = 0

function Test-Ok([string]$msg) {
    $script:Pass++
    Write-Host ("  [PASS]  {0}" -f $msg)
}
function Test-Nope([string]$msg, [string]$detail = '') {
    $script:Fail++
    Write-Host ("  [FAIL]  {0}" -f $msg)
    if ($detail) { Write-Host ("          {0}" -f $detail) }
}

Write-Host "stride-codex-exploratory-testing structure smoke test"
Write-Host ("plugin root: {0}" -f $PluginRoot)
Write-Host ""

# --- Manifest --------------------------------------------------------------

$Manifest = Join-Path $PluginRoot '.codex-plugin/plugin.json'
if (Test-Path -LiteralPath $Manifest -PathType Leaf) {
    $parsed = $null
    $jsonOk = $false
    try {
        $raw = Get-Content -LiteralPath $Manifest -Raw
        $parsed = $raw | ConvertFrom-Json
        # ConvertFrom-Json returns $null WITHOUT throwing for empty / whitespace /
        # literal `null` content — treat that as invalid so this twin agrees with the
        # bash python3 json.load check instead of silently skipping the key check.
        if ($null -ne $parsed) { $jsonOk = $true }
    }
    catch {
        $jsonOk = $false
    }

    if ($jsonOk) {
        Test-Ok ".codex-plugin/plugin.json exists and is valid JSON"
        # A valid manifest must be a JSON object; a top-level array/scalar is rejected
        # (matches the bash isinstance(d, dict) guard).
        if ($parsed -is [pscustomobject]) {
            $missing = @()
            foreach ($k in @('name', 'description', 'version', 'skills')) {
                if (-not ($parsed.PSObject.Properties.Name -contains $k)) { $missing += $k }
            }
            if ($missing.Count -eq 0) {
                Test-Ok "plugin.json has the four Codex keys (name, description, version, skills)"
            }
            else {
                Test-Nope ("plugin.json is missing key(s): {0}" -f ($missing -join ', '))
            }
        }
        else {
            Test-Nope "plugin.json is not a JSON object (expected an object with the four Codex keys)"
        }
    }
    else {
        Test-Nope "plugin.json is not valid JSON (empty, null, or malformed)"
    }
}
else {
    Test-Nope ".codex-plugin/plugin.json not found" $Manifest
}

# --- Command-skills (Codex has no commands/; entry is skill activation) -----

$CommandSkills = @(
    'stride-exploratory-testing-charter',
    'stride-exploratory-testing-nightmare-headline',
    'stride-exploratory-testing-explore',
    'stride-exploratory-testing-recon',
    'stride-exploratory-testing-debrief'
)
foreach ($skill in $CommandSkills) {
    $p = Join-Path $PluginRoot ("skills/{0}/SKILL.md" -f $skill)
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("skills/{0}/SKILL.md exists" -f $skill) }
    else { Test-Nope ("skills/{0}/SKILL.md is missing" -f $skill) }
}

# --- Doctrine skills --------------------------------------------------------

$DoctrineSkills = @('stride-exploratory-testing', 'chartering', 'heuristics', 'oracles', 'session')
foreach ($skill in $DoctrineSkills) {
    $p = Join-Path $PluginRoot ("skills/{0}/SKILL.md" -f $skill)
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("skills/{0}/SKILL.md exists" -f $skill) }
    else { Test-Nope ("skills/{0}/SKILL.md is missing" -f $skill) }
}

# Count only real SKILL.md files at the Codex layout depth (skills/<name>/SKILL.md):
# 5 command-skills + 5 doctrine skills = 10. Fixed depth (not -Recurse) so this twin
# matches the bash `skills/*/SKILL.md` glob and ignores the .gitkeep placeholder.
$skillCount = @(Get-ChildItem -Path (Join-Path $PluginRoot 'skills/*/SKILL.md') -File -ErrorAction SilentlyContinue).Count
if ($skillCount -eq 10) { Test-Ok "exactly 10 SKILL.md files present (.gitkeep ignored)" }
else { Test-Nope ("expected 10 SKILL.md files, found {0}" -f $skillCount) }

# --- Agents (Codex: bare *.md files, no commands/ directory) -----------------

foreach ($agent in @('charter-generator', 'explorer')) {
    $p = Join-Path $PluginRoot ("agents/{0}.md" -f $agent)
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("agents/{0}.md exists" -f $agent) }
    else { Test-Nope ("agents/{0}.md is missing" -f $agent) }
}

$agentCount = @(Get-ChildItem -Path (Join-Path $PluginRoot 'agents') -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
if ($agentCount -eq 2) { Test-Ok "exactly 2 agent files present (.gitkeep ignored)" }
else { Test-Nope ("expected 2 agent files, found {0}" -f $agentCount) }

# Codex ships no command files: assert there is no commands/ directory.
if (Test-Path -LiteralPath (Join-Path $PluginRoot 'commands') -PathType Container) {
    Test-Nope "unexpected commands/ directory (Codex ships no command files)" (Join-Path $PluginRoot 'commands')
}
else {
    Test-Ok "no commands/ directory (correct for Codex)"
}

# --- Fixtures (referenced by README.md) ------------------------------------

foreach ($fixture in @('example-charters.md', 'example-session-sheet.md', 'example-debrief.md')) {
    $p = Join-Path $PluginRoot ("fixtures/{0}" -f $fixture)
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("fixtures/{0} exists" -f $fixture) }
    else { Test-Nope ("fixtures/{0} is missing" -f $fixture) }
}

# --- Root docs and installers ----------------------------------------------

foreach ($doc in @('README.md', 'HEURISTICS.md', 'CHANGELOG.md', 'LICENSE', 'AGENTS.md', 'install.sh', 'install.ps1')) {
    $p = Join-Path $PluginRoot $doc
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("{0} exists" -f $doc) }
    else { Test-Nope ("{0} is missing" -f $doc) }
}

# --- summary ----------------------------------------------------------------

Write-Host ""
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
