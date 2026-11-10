<#
.SYNOPSIS
    Interrupt smoke test for the stride-codex-exploratory-testing plugin (PowerShell twin).

.DESCRIPTION
    Runs lib/test-structure.ps1 in the background against scratch copies of
    the plugin and checks its exit status: a completed run keeps its own 0 or
    1, and a run interrupted with SIGINT (during its first check, mid-run
    with no failure, after a failing check, or after its last check) or ended
    with SIGTERM never exits 0. An interrupted run must also leave nothing in
    its TMPDIR. Each signal is sent when a line the run prints appears, not
    after a fixed delay; the after-the-last-check case pauses its own copy
    before the summary. Skipped, exiting 0, on Windows, which has no SIGINT
    to send. Signals are sent with the system kill command. Mirrors
    lib/test-interrupt.sh.

    Exit code: 0 if every check passes or the test is skipped; 1 if any
    check fails.
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

Write-Host "stride-codex-exploratory-testing interrupt smoke test"
Write-Host ("plugin root: {0}" -f $PluginRoot)
Write-Host ""

if ($IsWindows) {
    Write-Host 'skipped: no SIGINT to send on Windows'
    exit 0
}

$tmpBase = if ($env:TMPDIR) { $env:TMPDIR } else { [IO.Path]::GetTempPath() }
$scratch = Join-Path $tmpBase ("scet-int." + [IO.Path]::GetRandomFileName())
$null = New-Item -ItemType Directory -Path $scratch
$script:Child = $null

try {
    # Copies the plugin, without its .git directory, to $dest.
    function Copy-Plugin([string]$dest) {
        $null = New-Item -ItemType Directory -Path $dest
        foreach ($item in (Get-ChildItem -LiteralPath $PluginRoot -Force)) {
            if ($item.Name -eq '.git') { continue }
            Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force
        }
    }

    $clean = Join-Path $scratch 'clean'
    $failing = Join-Path $scratch 'failing'
    $paused = Join-Path $scratch 'paused'
    Copy-Plugin $clean
    Copy-Plugin $failing
    Copy-Plugin $paused
    # One missing command-skill makes the failing copy fail an early check.
    Remove-Item -LiteralPath (Join-Path $failing 'skills/stride-exploratory-testing-charter/SKILL.md') -Force
    # The paused copy stops for ten seconds after its last check, before the
    # summary, so a signal can land there.
    $pauseLine = "Write-Host 'scet-int: paused before the summary'; Start-Sleep -Seconds 10"
    $suiteLines = [IO.File]::ReadAllLines((Join-Path $clean 'lib/test-structure.ps1'))
    $pausedLines = @($suiteLines | ForEach-Object { if ($_.StartsWith('# --- summary -', [StringComparison]::Ordinal)) { $pauseLine } else { $_ } })
    [IO.File]::WriteAllLines((Join-Path $paused 'lib/test-structure.ps1'), [string[]]$pausedLines)

    # Runs the copy at $root with TMPDIR set to the new directory $tmp. With
    # a trigger line and a signal, sends the signal once that text appears in
    # the run's output. Returns the exit code, the output file and a note
    # (empty unless the trigger was missed).
    function Invoke-Suite([string]$root, [string]$tmp, [string]$trigger = '', [string]$signal = '') {
        $null = New-Item -ItemType Directory -Path $tmp
        $out = "$tmp.out"
        $note = ''
        $savedTmpDir = $env:TMPDIR
        try {
            $env:TMPDIR = $tmp
            $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', (Join-Path $root 'lib/test-structure.ps1')) `
                -RedirectStandardOutput $out -RedirectStandardError "$out.err" -PassThru
        } finally {
            if ($null -ne $savedTmpDir) { $env:TMPDIR = $savedTmpDir } else { Remove-Item Env:TMPDIR -ErrorAction SilentlyContinue }
        }
        $null = $p.Handle
        $script:Child = $p
        if ($trigger) {
            $seen = $false
            for ($i = 0; $i -lt 600; $i++) {
                if ((Test-Path -LiteralPath $out) -and ([IO.File]::ReadAllText($out)).Contains($trigger)) { $seen = $true; break }
                if ($p.HasExited) { $note = 'the run ended before the trigger line'; break }
                Start-Sleep -Milliseconds 50
            }
            if (-not $seen -and -not $note) { $note = 'the trigger line did not appear within 30 seconds' }
            if ($seen) { & kill -s $signal $p.Id }
        }
        $p.WaitForExit()
        $script:Child = $null
        return [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Note = $note }
    }

    # Judges run $r for label $label. $want is zero or one for a completed
    # run, which must print its summary and exit with that status, or
    # interrupted, which must print no summary (so the signal did stop it)
    # and exit non-zero.
    function Test-Run([string]$label, $r, [string]$want) {
        if ($r.Note) { Test-Nope $label "$($r.Note) (exit $($r.Code))"; return }
        $summary = @([IO.File]::ReadAllLines($r.Out) | Where-Object { $_ -match '^[0-9]+ passed, [0-9]+ failed$' }).Count -gt 0
        $good = switch ($want) {
            'zero' { $summary -and $r.Code -eq 0 }
            'one' { $summary -and $r.Code -eq 1 }
            'interrupted' { (-not $summary) -and $r.Code -ne 0 }
        }
        $shown = if ($summary) { 'yes' } else { 'no' }
        if ($good) { Test-Ok $label } else { Test-Nope $label "exit $($r.Code), summary printed: $shown" }
    }

    $mid = 'explorer card has exactly one start and one end marker'
    Test-Run 'a completed run of test-structure.ps1 exits 0 when every check passes' (Invoke-Suite $clean (Join-Path $scratch 't1')) 'zero'
    Test-Run 'a completed run of test-structure.ps1 exits 1 when a check fails' (Invoke-Suite $failing (Join-Path $scratch 't2')) 'one'
    Test-Run 'test-structure.ps1 interrupted during its first check exits non-zero' (Invoke-Suite $clean (Join-Path $scratch 't3') 'plugin root:' 'INT') 'interrupted'
    Test-Run 'test-structure.ps1 interrupted with no failure exits non-zero' (Invoke-Suite $clean (Join-Path $scratch 't4') $mid 'INT') 'interrupted'
    Test-Run 'test-structure.ps1 interrupted after a failing check exits non-zero' (Invoke-Suite $failing (Join-Path $scratch 't5') 'is missing' 'INT') 'interrupted'
    Test-Run 'test-structure.ps1 interrupted after its last check exits non-zero' (Invoke-Suite $paused (Join-Path $scratch 't6') 'scet-int: paused before the summary' 'INT') 'interrupted'

    $l = 'an interrupted test-structure.ps1 leaves nothing in its TMPDIR'
    $left = @()
    foreach ($d in @('t3', 't4', 't5', 't6')) {
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $scratch $d) -Force)) { $left += "$d/$($f.Name)" }
    }
    if ($left.Count -eq 0) { Test-Ok $l } else { Test-Nope $l ("left: {0}" -f ($left -join ' ')) }

    Test-Run 'test-structure.ps1 ended by SIGTERM exits non-zero' (Invoke-Suite $clean (Join-Path $scratch 't8') $mid 'TERM') 'interrupted'
} finally {
    # No cmdlet here: an interrupt can stop a cmdlet inside a finally block,
    # which would leave the scratch copies behind.
    if ($null -ne $script:Child -and -not $script:Child.HasExited) { $script:Child.Kill() }
    try { [IO.Directory]::Delete($scratch, $true) } catch { }
}

# --- summary ----------------------------------------------------------------

Write-Host ""
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
