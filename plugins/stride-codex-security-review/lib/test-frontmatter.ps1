<#
.SYNOPSIS
    Frontmatter smoke test for the stride-codex-security-review plugin (PowerShell twin).

.DESCRIPTION
    Asserts every skill and agent carries the YAML frontmatter keys the
    Codex CLI needs to load it:
      - skills/*/SKILL.md : name, description
      - agents/*.md       : name, description, tools     (description may be
                            a `description: |` block scalar; tools MUST be a
                            lowercase JSON array, e.g. ["read","search","glob"])

    Codex ships NO command files, so there is no commands/ check and no
    allowed-tools key. The tools array is parsed with ConvertFrom-Json — no
    network, no jq. Mirrors lib/test-frontmatter.sh.

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

# Return the YAML frontmatter lines (between the first two `---` fences).
# Requires the file to open with `---` on line 1.
function Get-Frontmatter([string]$path) {
    $lines = Get-Content -LiteralPath $path
    $fences = 0
    $block = @()
    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            $fences++
            if ($fences -ge 2) { break }
            continue
        }
        if ($fences -eq 1) { $block += $line }
    }
    return $block
}

# True when the frontmatter declares KEY (matches `key:` at line start —
# works for inline values and `key: |` block scalars alike).
function Test-HasKey([string[]]$frontmatter, [string]$key) {
    foreach ($line in $frontmatter) {
        if ($line -match ("^{0}:" -f [regex]::Escape($key))) { return $true }
    }
    return $false
}

# Echo the raw value that follows `tools:` in the frontmatter (inline form).
function Get-ToolsValue([string[]]$frontmatter) {
    foreach ($line in $frontmatter) {
        if ($line -match '^tools:\s*(.*)$') { return $Matches[1] }
    }
    return ''
}

function Test-Keys([string]$label, [string]$file, [string[]]$keys) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Test-Nope ("{0} is missing" -f $label) $file
        return
    }
    $fm = Get-Frontmatter $file
    $missing = @()
    foreach ($key in $keys) {
        if (-not (Test-HasKey $fm $key)) { $missing += $key }
    }
    if ($missing.Count -eq 0) {
        Test-Ok ("{0} declares: {1}" -f $label, ($keys -join ' '))
    }
    else {
        Test-Nope ("{0} is missing frontmatter key(s): {1}" -f $label, ($missing -join ' '))
    }
}

# Validate that the agent's tools value is a lowercase JSON array of
# non-empty strings. A Claude-style comma string ("Read, Grep") is rejected.
function Test-ToolsArray([string]$label, [string]$file) {
    $fm = Get-Frontmatter $file
    $value = Get-ToolsValue $fm
    if ([string]::IsNullOrWhiteSpace($value)) {
        Test-Nope ("{0} tools value is empty or not inline" -f $label)
        return
    }
    # Must be a JSON array literal — a bare string like "Read, Grep" is rejected
    # (mirrors the bash isinstance(list) check; ConvertFrom-Json alone would happily
    # parse a scalar string).
    $trimmed = $value.Trim()
    if (-not ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
        Test-Nope ("{0} tools must be a lowercase JSON array like [`"read`",`"search`"]" -f $label) ("got: {0}" -f $value)
        return
    }
    $arr = $null
    # @(...) forces array semantics so a single-element array (["read"]) is NOT
    # unwrapped to a scalar by the pipeline — keeps this twin in step with the bash
    # json.loads / isinstance(list) check.
    try { $arr = @($trimmed | ConvertFrom-Json) }
    catch { Test-Nope ("{0} tools must be a lowercase JSON array like [`"read`",`"search`"]" -f $label) ("got: {0}" -f $value); return }

    $valid = $arr.Count -gt 0
    if ($valid) {
        foreach ($x in $arr) {
            if (($x -isnot [string]) -or [string]::IsNullOrEmpty($x) -or ($x -cne $x.ToLower())) {
                $valid = $false
                break
            }
        }
    }
    if ($valid) {
        Test-Ok ("{0} tools is a lowercase JSON array ({1})" -f $label, $value)
    }
    else {
        Test-Nope ("{0} tools must be a lowercase JSON array like [`"read`",`"search`"]" -f $label) ("got: {0}" -f $value)
    }
}

Write-Host "stride-codex-security-review frontmatter smoke test"
Write-Host ("plugin root: {0}" -f $PluginRoot)
Write-Host ""

# --- Skills: name + description --------------------------------------------

Write-Host "Skills (name, description)"
# Fixed depth (skills/<name>/SKILL.md), matching the bash `skills/*/SKILL.md` glob,
# so both twins validate exactly the same set of skill files.
$skillFiles = @(Get-ChildItem -Path (Join-Path $PluginRoot 'skills/*/SKILL.md') -File -ErrorAction SilentlyContinue)
if ($skillFiles.Count -eq 0) {
    Test-Nope "no SKILL.md files found under skills/"
}
foreach ($skillMd in $skillFiles) {
    $rel = "skills/{0}/SKILL.md" -f $skillMd.Directory.Name
    Test-Keys $rel $skillMd.FullName @('name', 'description')
}

# --- Agents: name + description + tools (tools = lowercase JSON array) ------

Write-Host ""
Write-Host "Agents (name, description, tools)"
$agentFiles = @(Get-ChildItem -Path (Join-Path $PluginRoot 'agents') -Filter '*.md' -File -ErrorAction SilentlyContinue)
if ($agentFiles.Count -eq 0) {
    Test-Nope "no *.md files found under agents/"
}
foreach ($agentMd in $agentFiles) {
    $rel = "agents/{0}" -f $agentMd.Name
    Test-Keys $rel $agentMd.FullName @('name', 'description', 'tools')
    Test-ToolsArray $rel $agentMd.FullName
}

# --- summary ----------------------------------------------------------------

Write-Host ""
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
