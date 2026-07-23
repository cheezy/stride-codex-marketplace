<#
.SYNOPSIS
    Structure smoke test for the stride-codex-security-review plugin (PowerShell twin).

.DESCRIPTION
    Asserts the plugin ships every file the Codex CLI edition requires: a valid
    manifest with the four Codex keys, the one command-equivalent skill, the one
    security-reviewer agent, the lib/ transform + eval tooling, the fixtures/ tree
    (EXPECTED.md, golden/, and the considerations positive/negative controls), and
    the root docs (including AGENTS.md and both installers). Codex ships NO command
    files, so there is no commands/ check. JSON is parsed with ConvertFrom-Json —
    no network, no jq. Mirrors lib/test-structure.sh.

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

Write-Host "stride-codex-security-review structure smoke test"
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

# --- Skills (Codex has no commands/; entry is skill activation) -------------
# The command-equivalent skill (stride-security-review) and the doctrine skill
# (security-review-essentials, the front-door surface stride-codex detects).

foreach ($skill in @('stride-security-review', 'security-review-essentials')) {
    $p = Join-Path $PluginRoot ("skills/{0}/SKILL.md" -f $skill)
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("skills/{0}/SKILL.md exists" -f $skill) }
    else { Test-Nope ("skills/{0}/SKILL.md is missing" -f $skill) }
}

# Count only real SKILL.md files at the Codex layout depth; ignore any .gitkeep.
$skillCount = @(Get-ChildItem -Path (Join-Path $PluginRoot 'skills/*/SKILL.md') -File -ErrorAction SilentlyContinue).Count
if ($skillCount -eq 2) { Test-Ok "exactly 2 SKILL.md files present (.gitkeep ignored)" }
else { Test-Nope ("expected 2 SKILL.md files, found {0}" -f $skillCount) }

# --- Agent (Codex: bare *.md file, no commands/ directory) ------------------

$agentMd = Join-Path $PluginRoot 'agents/security-reviewer.md'
if (Test-Path -LiteralPath $agentMd -PathType Leaf) { Test-Ok "agents/security-reviewer.md exists" }
else { Test-Nope "agents/security-reviewer.md is missing" }

$agentCount = @(Get-ChildItem -Path (Join-Path $PluginRoot 'agents') -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
if ($agentCount -eq 1) { Test-Ok "exactly 1 agent file present (.gitkeep ignored)" }
else { Test-Nope ("expected 1 agent file, found {0}" -f $agentCount) }

# Codex ships no command files: assert there is no commands/ directory.
if (Test-Path -LiteralPath (Join-Path $PluginRoot 'commands') -PathType Container) {
    Test-Nope "unexpected commands/ directory (Codex ships no command files)" (Join-Path $PluginRoot 'commands')
}
else {
    Test-Ok "no commands/ directory (correct for Codex)"
}

# --- lib/ tooling (transform + eval + self-tests) --------------------------

foreach ($script in @('sarif_transform.sh', 'run_eval.sh', 'run_transform_tests.sh', 'check_fixtures.sh', 'test-all.sh', 'test-structure.sh', 'test-frontmatter.sh')) {
    $p = Join-Path $PluginRoot ("lib/{0}" -f $script)
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("lib/{0} exists" -f $script) }
    else { Test-Nope ("lib/{0} is missing" -f $script) }
}

# --- fixtures/ (eval corpus + golden + considerations controls) ------------

$expected = Join-Path $PluginRoot 'fixtures/EXPECTED.md'
if (Test-Path -LiteralPath $expected -PathType Leaf) { Test-Ok "fixtures/EXPECTED.md exists" }
else { Test-Nope "fixtures/EXPECTED.md is missing" }

foreach ($golden in @('input_findings.json', 'dedup.golden.json', 'fingerprint.golden', 'sarif.golden.json')) {
    $p = Join-Path $PluginRoot ("fixtures/golden/{0}" -f $golden)
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("fixtures/golden/{0} exists" -f $golden) }
    else { Test-Nope ("fixtures/golden/{0} is missing" -f $golden) }
}

# Considerations-mode controls: a fully-mitigated positive control and an
# unmitigated negative control, each a .considerations + .diff pair.
foreach ($stem in @('parameterized_query_all_mitigated', 'token_logging_unmitigated')) {
    foreach ($ext in @('considerations', 'diff')) {
        $p = Join-Path $PluginRoot ("fixtures/considerations/{0}.{1}" -f $stem, $ext)
        if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("fixtures/considerations/{0}.{1} exists" -f $stem, $ext) }
        else { Test-Nope ("fixtures/considerations/{0}.{1} is missing" -f $stem, $ext) }
    }
}

# --- Root docs and installers ----------------------------------------------

foreach ($doc in @('README.md', 'CHANGELOG.md', 'LICENSE', 'AGENTS.md', 'install.sh', 'install.ps1')) {
    $p = Join-Path $PluginRoot $doc
    if (Test-Path -LiteralPath $p -PathType Leaf) { Test-Ok ("{0} exists" -f $doc) }
    else { Test-Nope ("{0} is missing" -f $doc) }
}

# --- summary ----------------------------------------------------------------

Write-Host ""
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
