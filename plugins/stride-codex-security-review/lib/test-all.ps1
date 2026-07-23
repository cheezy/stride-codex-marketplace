<#
.SYNOPSIS
    Top-level smoke-test runner for the stride-codex-security-review plugin (PowerShell twin).

.DESCRIPTION
    Runs the offline gate and aggregates the result:
      - test-structure.ps1      plugin layout (manifest, skill, agent, lib/, fixtures/)
      - test-frontmatter.ps1    skill/agent YAML frontmatter (Codex tools contract)
    and, when `bash` and `jq` are available on the host (e.g. Git Bash on Windows),
    also the deterministic transform + eval bash checks for full parity with
    lib/test-all.sh:
      - run_transform_tests.sh  SARIF/dedup/fail-on transforms vs golden
      - check_fixtures.sh       every fixture has exactly one EXPECTED.md row
    When bash/jq are absent, those two are reported as SKIPPED (not failed) — run
    lib/test-all.sh under bash to gate them. The live-agent eval (run_eval.sh,
    needs a Codex model) is a separate step. No network.

      pwsh ./lib/test-all.ps1

    Exit code: 0 only if every sub-script that ran passes; 1 if any fails.
    Mirrors lib/test-all.sh.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PsTests = @('test-structure.ps1', 'test-frontmatter.ps1')
$BashTests = @('run_transform_tests.sh', 'check_fixtures.sh')

$ran = 0
$failed = 0
$skipped = 0

foreach ($t in $PsTests) {
    Write-Host ("=== {0} ===" -f $t)
    $ran++
    $scriptPath = Join-Path $PSScriptRoot $t
    & pwsh -NoProfile -File $scriptPath
    if ($LASTEXITCODE -ne 0) { $failed++ }
    Write-Host ""
}

$bash = Get-Command bash -ErrorAction SilentlyContinue
$jq = Get-Command jq -ErrorAction SilentlyContinue
foreach ($t in $BashTests) {
    Write-Host ("=== {0} ===" -f $t)
    if ($null -eq $bash -or $null -eq $jq) {
        $skipped++
        Write-Host "  SKIPPED (requires bash + jq; run lib/test-all.sh to gate this check)"
        Write-Host ""
        continue
    }
    $ran++
    $scriptPath = Join-Path $PSScriptRoot $t
    & bash $scriptPath
    if ($LASTEXITCODE -ne 0) { $failed++ }
    Write-Host ""
}

Write-Host "================================"
if ($skipped -gt 0) {
    Write-Host ("{0} bash-only check(s) SKIPPED (no bash/jq on PATH)" -f $skipped)
}
if ($failed -gt 0) {
    Write-Host ("{0} of {1} smoke-test script(s) FAILED" -f $failed, $ran)
    exit 1
}
Write-Host ("All {0} smoke-test scripts passed" -f $ran)
exit 0
