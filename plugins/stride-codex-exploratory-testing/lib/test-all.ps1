<#
.SYNOPSIS
    Top-level smoke-test runner for the stride-codex-exploratory-testing plugin (PowerShell twin).

.DESCRIPTION
    Runs every lib/test-*.ps1 check (structure + frontmatter) and aggregates
    the result. No network, no jq. Use this as the single entry point to gate
    a release on a PowerShell host:

      pwsh ./lib/test-all.ps1

    Exit code: 0 only if every sub-script passes; 1 if any sub-script fails.
    Mirrors lib/test-all.sh.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Tests = @('test-structure.ps1', 'test-frontmatter.ps1')

$ran = 0
$failed = 0

foreach ($t in $Tests) {
    Write-Host ("=== {0} ===" -f $t)
    $ran++
    $scriptPath = Join-Path $PSScriptRoot $t
    & pwsh -NoProfile -File $scriptPath
    if ($LASTEXITCODE -ne 0) { $failed++ }
    Write-Host ""
}

Write-Host "================================"
if ($failed -gt 0) {
    Write-Host ("{0} of {1} smoke-test script(s) FAILED" -f $failed, $ran)
    exit 1
}
Write-Host ("All {0} smoke-test scripts passed" -f $ran)
exit 0
