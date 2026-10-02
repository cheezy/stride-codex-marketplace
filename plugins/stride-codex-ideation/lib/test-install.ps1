# PowerShell twin of test-install.sh — exercises install.ps1 (and, when bash is
# available, its agreement with install.sh): the home-directory fallback, the
# namespaced helper layout, stale-file cleanup, and the managed AGENTS.md
# block — fresh, existing, empty, malformed-marker and re-run cases.
#
# Fully offline: every run sets INSTALL_SOURCE_DIR to this checkout and puts a
# fake git that fails loudly first on PATH, so nothing is ever cloned. Every
# run gets its own temp HOME (and USERPROFILE), so nothing outside the test's
# temp dir is touched.
#
# Run:
#   pwsh -NoProfile -File lib/test-install.ps1
#
# Exits 0 if all tests pass, non-zero otherwise.

Set-StrictMode -Version Latest

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir
$InstallPs1 = Join-Path $PluginRoot 'install.ps1'
$InstallSh  = Join-Path $PluginRoot 'install.sh'
$PwshExe    = (Get-Process -Id $PID).Path
$OnWindows  = [System.IO.Path]::DirectorySeparatorChar -eq '\'

$script:PASS = 0
$script:FAIL = 0
$script:SKIP = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }
function Skip($m) { $script:SKIP++; Write-Host "  SKIP  $m" }
function Check([string]$Label, [bool]$Cond, [string]$Detail = '') { if ($Cond) { Pass $Label } else { Fail $Label $Detail } }

Write-Host 'test-install.ps1 — exercises install.ps1'
Write-Host ''

$BeginMarker = '<!-- BEGIN stride-ideation -->'
$EndMarker   = '<!-- END stride-ideation -->'
$NoteMarker  = '<!-- Managed by the stride-codex-ideation installer; content between these markers is regenerated on each install. Add your own notes outside this block. -->'

# A space in the temp path exercises quoting in every installer path.
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("sti install " + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
function J([string]$Name) { Join-Path $Tmp $Name }
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Raw([string]$Path, [string]$Text) { [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom) }
# Byte-level seeds: Latin-1 maps each char 0-255 to the same byte.
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)
function Write-Bytes([string]$Path, [string]$Text) { [System.IO.File]::WriteAllBytes($Path, $Latin1.GetBytes($Text)) }
function Read-Raw([string]$Path) { [System.IO.File]::ReadAllText($Path) }
function Same-Bytes([string]$A, [string]$B) {
    if (-not ((Test-Path -LiteralPath $A) -and (Test-Path -LiteralPath $B))) { return $false }
    $x = [System.IO.File]::ReadAllBytes($A); $y = [System.IO.File]::ReadAllBytes($B)
    if ($x.Length -ne $y.Length) { return $false }
    for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { return $false } }
    return $true
}

try {

# The exact managed block both installers must write.
$bundle = Read-Raw (Join-Path $PluginRoot 'AGENTS.md')
if ($bundle.Length -gt 0 -and -not $bundle.EndsWith("`n")) { $bundle += "`n" }
$Block = $BeginMarker + "`n" + $NoteMarker + "`n" + $bundle + $EndMarker + "`n"
Write-Raw (J 'expected-block.md') $Block
# The same block as raw bytes (char per byte), for the byte-level seeds.
$BlockBytes = $Latin1.GetString([System.IO.File]::ReadAllBytes((J 'expected-block.md')))

$HaveBash = [bool](Get-Command bash -ErrorAction SilentlyContinue)

# A fake git that fails loudly: INSTALL_SOURCE_DIR must mean no clone at all.
$Bin = J 'bin'
New-Item -ItemType Directory -Force -Path $Bin | Out-Null
if ($OnWindows) {
    Write-Raw (Join-Path $Bin 'git.cmd') "@echo fake git: the installer tried to clone 1>&2`r`n@exit /b 97`r`n"
} else {
    Write-Raw (Join-Path $Bin 'git') "#!/bin/sh`necho 'fake git: the installer tried to clone' >&2`nexit 97`n"
    & chmod +x (Join-Path $Bin 'git')
}

# Invoke-Installer -Home <dir> [-Cwd <dir>] [-Project] [-UserProfile <dir>|$null] [-Sh]
# Runs install.ps1 (or install.sh with -Sh) in a child process. USERPROFILE is
# unset unless given, so the HOME fallback is what resolves the global dir.
# Quote arguments for ProcessStartInfo.Arguments (Windows command-line rules).
# ProcessStartInfo.ArgumentList would be simpler, but Windows PowerShell 5.1 runs
# on .NET Framework, which does not have it.
function Join-ProcessArgs([string[]]$Values) {
    $quoted = foreach ($v in $Values) {
        if ($v -ne '' -and $v -notmatch '[\s"]') { $v; continue }
        $out = '"'; $bs = 0
        foreach ($ch in $v.ToCharArray()) {
            if ($ch -eq '\') { $bs++; continue }
            if ($ch -eq '"') { $out += ('\' * ($bs * 2 + 1)) + '"' } else { $out += ('\' * $bs) + $ch }
            $bs = 0
        }
        $out + ('\' * ($bs * 2)) + '"'
    }
    return ($quoted -join ' ')
}

function Invoke-Installer {
    param([string]$HomeDir, [string]$Cwd = '', [switch]$Project, [string]$UserProfile = '', [switch]$Sh, [string]$SourceDir = $PluginRoot)
    New-Item -ItemType Directory -Force -Path $HomeDir | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($Sh) {
        $psi.FileName = 'bash'
        $argv = @($InstallSh)
        if ($Project) { $argv += '--project' }
    } else {
        $psi.FileName = $PwshExe
        $argv = @('-NoProfile', '-NonInteractive', '-File', $InstallPs1)
        if ($Project) { $argv += '-Project' }
    }
    $psi.Arguments = Join-ProcessArgs $argv
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = if ($Cwd) { $Cwd } else { $HomeDir }
    $psi.EnvironmentVariables['PATH'] = $Bin + [System.IO.Path]::PathSeparator + $env:PATH
    $psi.EnvironmentVariables['HOME'] = $HomeDir
    $psi.EnvironmentVariables['INSTALL_SOURCE_DIR'] = $SourceDir
    if ($UserProfile) { $psi.EnvironmentVariables['USERPROFILE'] = $UserProfile } else { $psi.EnvironmentVariables.Remove('USERPROFILE') }
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $script:Out = $o.Result + $e.Result
    $script:Rc = $p.ExitCode
}

function Count-Begin([string]$Path) { @((Read-Raw $Path) -split "`n" | Where-Object { $_ -ceq $BeginMarker }).Count }

# --- fresh global install, USERPROFILE unset ------------------------------------

$H = J 'fresh'
Invoke-Installer -HomeDir $H
$A = Join-Path $H '.agents'
$HR = Join-Path $A 'stride-codex-ideation'
Check 'fresh: install.ps1 runs in global mode with USERPROFILE unset (HOME fallback)' ($script:Rc -eq 0) $script:Out
Check 'fresh: AGENTS.md is exactly the managed block' (Same-Bytes (J 'expected-block.md') (Join-Path $A 'AGENTS.md'))
Check 'fresh: 3 skills and 2 agents land where Codex discovers them' ((@(Get-ChildItem -LiteralPath (Join-Path $A 'skills') -Directory).Count -eq 3) -and (@(Get-ChildItem -LiteralPath (Join-Path $A 'agents') -Filter '*.md' -File).Count -eq 2))
Check 'fresh: helpers and fixtures install under the namespaced stride-codex-ideation/ dir' ((Test-Path -LiteralPath (Join-Path $HR 'lib/ship.py')) -and (Test-Path -LiteralPath (Join-Path $HR 'lib/filename.sh')) -and (Test-Path -LiteralPath (Join-Path $HR 'fixtures/README.md')))
Check 'fresh: agent files are also installed under the helper root, where the skills look them up' ((Test-Path -LiteralPath (Join-Path $HR 'agents/requirements-decomposer.md')) -and (Test-Path -LiteralPath (Join-Path $HR 'agents/requirements-reviewer.md')))
Check 'fresh: nothing is written to the shared .agents/lib or .agents/fixtures' (-not (Test-Path -LiteralPath (Join-Path $A 'lib')) -and -not (Test-Path -LiteralPath (Join-Path $A 'fixtures')))
Check 'fresh: the resolved helper root is printed' ($script:Out.Contains('Helper root: ' + (Resolve-Path -LiteralPath $HR).Path)) $script:Out
Check 'fresh: INSTALL_SOURCE_DIR installs from the checkout without cloning' (-not $script:Out.Contains('fake git'))
Check 'fresh: no legacy-helpers note on a clean home' (-not $script:Out.Contains('an earlier release installed helpers'))

# USERPROFILE, when set, still wins over HOME.
$UP = J 'userprofile'
Invoke-Installer -HomeDir (J 'home-ignored') -UserProfile $UP
Check 'home: a set USERPROFILE takes precedence over HOME' (($script:Rc -eq 0) -and (Test-Path -LiteralPath (Join-Path $UP '.agents/AGENTS.md')) -and -not (Test-Path -LiteralPath (Join-Path (J 'home-ignored') '.agents'))) $script:Out

# --- re-run: idempotent, stale helpers removed, nothing outside touched ---------

Copy-Item -LiteralPath (Join-Path $A 'AGENTS.md') -Destination (J 'fresh-agents.md')
Write-Raw (Join-Path $HR 'lib/dropped-by-a-newer-release.sh') "stale`n"
Write-Raw (Join-Path $HR 'fixtures/dropped.md') "stale`n"
New-Item -ItemType Directory -Force -Path (Join-Path $A 'lib'), (Join-Path $A 'fixtures') | Out-Null
Write-Raw (Join-Path $A 'lib/other-tool.sh') "other tool`n"
Write-Raw (Join-Path $A 'lib/filename.sh') "legacy`n"
Write-Raw (Join-Path $A 'lib/validate_batch.py') "legacy`n"
Write-Raw (Join-Path $A 'fixtures/other-tool.md') "other tool`n"
Invoke-Installer -HomeDir $H
Check 're-run: install.ps1 exits 0' ($script:Rc -eq 0) $script:Out
Check 're-run: AGENTS.md is unchanged (one block, refreshed in place)' (Same-Bytes (J 'fresh-agents.md') (Join-Path $A 'AGENTS.md'))
Check 're-run: helper files no longer shipped are removed' (-not (Test-Path -LiteralPath (Join-Path $HR 'lib/dropped-by-a-newer-release.sh')) -and -not (Test-Path -LiteralPath (Join-Path $HR 'fixtures/dropped.md')))
Check 're-run: nothing outside the namespaced dir is deleted' ((Test-Path -LiteralPath (Join-Path $A 'lib/other-tool.sh')) -and (Test-Path -LiteralPath (Join-Path $A 'lib/filename.sh')) -and (Test-Path -LiteralPath (Join-Path $A 'fixtures/other-tool.md')))
Check 're-run: legacy helpers in .agents/lib are pointed out, not deleted' ($script:Out.Contains('an earlier release installed helpers')) $script:Out

# --- the clear step never deletes the source -------------------------------------

$H = J 'self'
$srcCopy = Join-Path $H '.agents/stride-codex-ideation/src-copy'
New-Item -ItemType Directory -Force -Path $srcCopy | Out-Null
foreach ($item in @(Get-ChildItem -LiteralPath $PluginRoot -Force | Where-Object { $_.Name -ne '.git' })) {
    Copy-Item -LiteralPath $item.FullName -Destination $srcCopy -Recurse -Force
}
Invoke-Installer -HomeDir $H -SourceDir $srcCopy
Check 'self-install: a source inside the install target is refused and left intact' (($script:Rc -ne 0) -and (Test-Path -LiteralPath (Join-Path $srcCopy 'install.ps1'))) $script:Out

# --- existing AGENTS.md shapes ----------------------------------------------------

$Seeds = [ordered]@{
    user      = "# My project`n`nMy own notes.`n"
    noeol     = "# My project`n`nNo trailing newline"
    empty     = ''
    refresh   = "# Mine before`n`n$BeginMarker`nold managed text`n$EndMarker`n`n# Mine after`n"
    endfirst  = "intro`n$EndMarker`nmiddle`n$BeginMarker`noutro`n"
    strayend  = "intro`n$EndMarker`n$BeginMarker`nold managed text`n$EndMarker`noutro`n"
    beginonly = "intro`n$BeginMarker`norphan begin, no end`n"
    midline   = "Our docs mention $BeginMarker and $EndMarker inline.`n"
    crlf      = "# Windows file`r`n$BeginMarker`r`nold`r`n$EndMarker`r`nafter`r`n"
    latin1    = "# Caf$([char]0xE9) notes (Windows-1252)`n`n$BeginMarker`nold`n$EndMarker`n"
    bom       = "$([char]0xEF)$([char]0xBB)$([char]0xBF)# Notes with a UTF-8 BOM $([char]0xE2)$([char]0x80)$([char]0x94) kept`n"
}
function Expected-For([string]$Name, [string]$Seed) {
    switch ($Name) {
        'empty'    { return $Block }
        'refresh'  { return "# Mine before`n`n" + $Block + "`n# Mine after`n" }
        'noeol'    { return $Seed + "`n`n" + $Block }
        'crlf'     { return "# Windows file`r`n" + $Block + "after`r`n" }
        'strayend' { return "intro`n$EndMarker`n" + $Block + "outro`n" }
        'latin1'   { return "# Caf$([char]0xE9) notes (Windows-1252)`n`n" + $BlockBytes }
        'bom'      { return $Seed + "`n" + $BlockBytes }
        default    { return $Seed + "`n" + $Block }
    }
}

foreach ($name in $Seeds.Keys) {
    $seed = $Seeds[$name]
    $expected = J "expected-$name.md"
    $exp = Expected-For $name $seed
    if ($name -in @('latin1', 'bom')) { Write-Bytes $expected $exp } else { Write-Raw $expected $exp }
    $H = J "case-ps-$name"
    New-Item -ItemType Directory -Force -Path (Join-Path $H '.agents') | Out-Null
    $dest = Join-Path $H '.agents/AGENTS.md'
    Write-Bytes $dest $seed
    Invoke-Installer -HomeDir $H
    Check "AGENTS.md [$name]: install.ps1 writes the expected result" (($script:Rc -eq 0) -and (Same-Bytes $expected $dest)) $script:Out
    Copy-Item -LiteralPath $dest -Destination (J "after-first-$name.md")
    Invoke-Installer -HomeDir $H
    Check "AGENTS.md [$name]: a second install.ps1 run changes nothing" (((Count-Begin $dest) -ge 1) -and (Same-Bytes (J "after-first-$name.md") $dest))
    if ($name -in @('endfirst', 'beginonly', 'midline', 'bom')) {
        $after = $Latin1.GetString([System.IO.File]::ReadAllBytes($dest))
        Check "AGENTS.md [$name]: user content (malformed markers, legacy encodings, a BOM) survives byte for byte" ($after.StartsWith($seed, [StringComparison]::Ordinal))
    }
    if ($HaveBash) {
        $Hs = J "case-sh-$name"
        New-Item -ItemType Directory -Force -Path (Join-Path $Hs '.agents') | Out-Null
        Write-Bytes (Join-Path $Hs '.agents/AGENTS.md') $seed
        Invoke-Installer -HomeDir $Hs -Sh
        Check "bash [$name]: install.sh and install.ps1 produce byte-identical AGENTS.md" (($script:Rc -eq 0) -and (Same-Bytes (Join-Path $Hs '.agents/AGENTS.md') $dest)) $script:Out
    } else {
        Skip "bash [$name]: bash not found, install.sh agreement not checked (lib/test-install.sh covers it)"
    }
}

# --- a bundle AGENTS.md without a final newline still ends the block cleanly ------

$Src2 = J 'source-noeol'
New-Item -ItemType Directory -Force -Path $Src2 | Out-Null
foreach ($item in @(Get-ChildItem -LiteralPath $PluginRoot -Force | Where-Object { $_.Name -ne '.git' })) {
    Copy-Item -LiteralPath $item.FullName -Destination $Src2 -Recurse -Force
}
[System.IO.File]::WriteAllBytes((Join-Path $Src2 'AGENTS.md'), $Latin1.GetBytes($Latin1.GetString([System.IO.File]::ReadAllBytes((Join-Path $PluginRoot 'AGENTS.md'))).TrimEnd("`n")))
$H = J 'noeol-bundle'
Invoke-Installer -HomeDir $H -SourceDir $Src2
Check 'bundle: an AGENTS.md source without a final newline still puts END on its own line' (($script:Rc -eq 0) -and (Same-Bytes (J 'expected-block.md') (Join-Path $H '.agents/AGENTS.md'))) $script:Out

# --- never write through a symlinked AGENTS.md, never delete through a link -------

if ($OnWindows) {
    Skip 'symlink: symlink cases need POSIX ln (Windows symlinks require elevation)'
} else {
    $H = J 'symlink-agents'
    New-Item -ItemType Directory -Force -Path (Join-Path $H '.agents') | Out-Null
    Write-Raw (J 'precious-rc') "precious`n"
    & ln -s (J 'precious-rc') (Join-Path $H '.agents/AGENTS.md')
    Invoke-Installer -HomeDir $H
    Check 'symlink: a symlinked AGENTS.md is refused and its target left untouched' (($script:Rc -ne 0) -and ((Read-Raw (J 'precious-rc')) -eq "precious`n")) $script:Out

    $H = J 'dangling-agents'
    New-Item -ItemType Directory -Force -Path (Join-Path $H '.agents') | Out-Null
    & ln -s (J 'never-created') (Join-Path $H '.agents/AGENTS.md')
    Invoke-Installer -HomeDir $H
    Check 'symlink: a dangling AGENTS.md link is refused and nothing is created at its target' (($script:Rc -ne 0) -and -not (Test-Path -LiteralPath (J 'never-created'))) $script:Out

    $R = J 'hostile-repo'
    New-Item -ItemType Directory -Force -Path $R, (J 'outside/stride-codex-ideation') | Out-Null
    Write-Raw (J 'outside/stride-codex-ideation/keep.txt') "not yours`n"
    & ln -s (J 'outside') (Join-Path $R '.agents')
    Invoke-Installer -HomeDir (J 'hostile-home') -Cwd $R -Project
    Check 'symlink: -Project refuses a symlinked .agents and deletes nothing outside the project' (($script:Rc -ne 0) -and (Test-Path -LiteralPath (J 'outside/stride-codex-ideation/keep.txt'))) $script:Out

    $H = J 'linked-skill'
    Invoke-Installer -HomeDir $H
    Write-Raw (J 'precious-skill') "precious`n"
    $skillMd = Join-Path $H '.agents/skills/stride-ideation/SKILL.md'
    Remove-Item -LiteralPath $skillMd -Force
    & ln -s (J 'precious-skill') $skillMd
    Invoke-Installer -HomeDir $H
    Check 'symlink: a linked SKILL.md is replaced, never written through' (($script:Rc -eq 0) -and ((Read-Raw (J 'precious-skill')) -eq "precious`n") -and -not ((Get-Item -LiteralPath $skillMd -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) $script:Out

    $H = J 'linked-root'
    New-Item -ItemType Directory -Force -Path (Join-Path $H '.agents'), (J 'dev-checkout/lib') | Out-Null
    Write-Raw (J 'dev-checkout/lib/mine.sh') "keep me`n"
    & ln -s (J 'dev-checkout') (Join-Path $H '.agents/stride-codex-ideation')
    Invoke-Installer -HomeDir $H
    $hr = Join-Path $H '.agents/stride-codex-ideation'
    Check 'symlink: a symlinked helper root is replaced; its target is never deleted' (($script:Rc -eq 0) -and (Test-Path -LiteralPath (J 'dev-checkout/lib/mine.sh')) -and -not ((Get-Item -LiteralPath $hr -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Test-Path -LiteralPath (Join-Path $hr 'lib/ship.py'))) $script:Out

    # A helper root linked to the very checkout being installed from is
    # replaced as a link; the checkout is untouched (install.sh agrees).
    $H = J 'root-linked-to-source'
    $devSrc = J 'dev-source'
    New-Item -ItemType Directory -Force -Path (Join-Path $H '.agents'), $devSrc | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $PluginRoot -Force | Where-Object { $_.Name -ne '.git' })) {
        Copy-Item -LiteralPath $item.FullName -Destination $devSrc -Recurse -Force
    }
    & ln -s $devSrc (Join-Path $H '.agents/stride-codex-ideation')
    Invoke-Installer -HomeDir $H -SourceDir $devSrc
    Check 'symlink: a helper root linked to the source checkout is replaced; the checkout is intact' (($script:Rc -eq 0) -and (Test-Path -LiteralPath (Join-Path $devSrc 'install.ps1')) -and -not ((Get-Item -LiteralPath (Join-Path $H '.agents/stride-codex-ideation') -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) $script:Out
    if ($HaveBash) {
        $Hs = J 'root-linked-to-source-sh'
        New-Item -ItemType Directory -Force -Path (Join-Path $Hs '.agents') | Out-Null
        & ln -s $devSrc (Join-Path $Hs '.agents/stride-codex-ideation')
        $psRc = $script:Rc
        Invoke-Installer -HomeDir $Hs -SourceDir $devSrc -Sh
        Check 'bash: install.sh takes the same branch for a helper root linked to the source' (($script:Rc -eq $psRc) -and (Test-Path -LiteralPath (Join-Path $devSrc 'install.sh'))) $script:Out
    }

    # A source reached through a link into the target is still refused.
    $H = J 'self-via-link'
    $inner = Join-Path $H '.agents/stride-codex-ideation/src-copy'
    New-Item -ItemType Directory -Force -Path $inner | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $PluginRoot -Force | Where-Object { $_.Name -ne '.git' })) {
        Copy-Item -LiteralPath $item.FullName -Destination $inner -Recurse -Force
    }
    & ln -s $inner (J 'src-link')
    Invoke-Installer -HomeDir $H -SourceDir (J 'src-link')
    Check 'self-install: a source reached through a link into the target is refused' (($script:Rc -ne 0) -and (Test-Path -LiteralPath (Join-Path $inner 'install.ps1'))) $script:Out
}

# --- project mode, in a path containing spaces --------------------------------------

$P = J 'my project'
New-Item -ItemType Directory -Force -Path $P | Out-Null
Invoke-Installer -HomeDir (J 'project-home') -Cwd $P -Project
Check 'project: -Project installs into ./.agents and ./AGENTS.md, in a path with spaces' (($script:Rc -eq 0) -and (Same-Bytes (J 'expected-block.md') (Join-Path $P 'AGENTS.md')) -and (Test-Path -LiteralPath (Join-Path $P '.agents/stride-codex-ideation/lib/ship.py')) -and (Test-Path -LiteralPath (Join-Path $P '.agents/skills/stride-ideation-stridify'))) $script:Out
Check 'project: -Project leaves the home directory alone' (-not (Test-Path -LiteralPath (Join-Path (J 'project-home') '.agents')))

} finally {
    Remove-Item -Recurse -Force -LiteralPath $Tmp -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:SKIP -gt 0) { Write-Host ("{0} skipped (not applicable on this host)" -f $script:SKIP) }
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 }
exit 0
