<#
.SYNOPSIS
    Install Stride ideation skills and agents for Codex CLI.

.DESCRIPTION
    Installs the Stride ideation skills (skills/), agents (agents/), lib/
    helpers, and fixtures/ for use with the Codex CLI. By default installs
    globally to ~/.agents/ (the user's home directory, on Windows, macOS and
    Linux alike) so the skills and agents are available in all projects. Use
    -Project to install to ./.agents/ in the current directory instead.

    skills/ and agents/ go where Codex discovers them; the lib/ helpers and
    fixtures/ go under a directory of their own, <install-dir>/stride-codex-ideation/,
    so no other tool installing into the same .agents/ can overwrite them.
    That directory is the plugin's helper root: it is cleared and rewritten on
    every install, so files dropped by a newer release disappear. Nothing
    outside it is ever deleted.

    Behaves identically to install.sh: the same layout, and the same managed
    AGENTS.md block, byte for byte, for the same input.

    Set INSTALL_SOURCE_DIR to a local checkout to install from it instead of
    cloning (used by lib/test-install.ps1 so the tests run offline).

.PARAMETER Project
    Install into ./.agents/ in the current directory instead of the global
    per-user location.

.PARAMETER Help
    Print usage information and exit.

.EXAMPLE
    irm https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.ps1 | iex

    Installs globally to ~/.agents/.

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.ps1))) -Project

    Installs into ./.agents/ in the current directory.

.EXAMPLE
    .\install.ps1 -Project

    Runs a locally downloaded copy of the installer in project mode.
#>

[CmdletBinding()]
param(
    [switch]$Project,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Usage: install.ps1 [-Project] [-Help]"
    Write-Host ""
    Write-Host "  (default)   Install globally to ~/.agents/ (available in all projects)"
    Write-Host "  -Project    Install to ./.agents/ in the current directory"
    exit 0
}

$Repo = 'https://github.com/cheezy/stride-codex-ideation.git'

# The user's home directory. USERPROFILE is set on Windows only; pwsh on macOS
# and Linux has HOME instead, and the .NET lookup covers a host with neither.
function Resolve-HomeDir {
    foreach ($candidate in @($env:USERPROFILE, $env:HOME, [Environment]::GetFolderPath('UserProfile'))) {
        if (-not [string]::IsNullOrEmpty($candidate)) { return $candidate }
    }
    throw "Could not determine your home directory: USERPROFILE and HOME are unset. Re-run with -Project from a project directory instead."
}

if ($Project) {
    $InstallDir = Join-Path (Get-Location).Path '.agents'
    Write-Host "Installing Stride Ideation for Codex CLI into .agents/ (project-local)..."
}
else {
    $InstallDir = Join-Path (Resolve-HomeDir) '.agents'
    Write-Host "Installing Stride Ideation for Codex CLI into ~/.agents/ (global)..."
}
$HelperRoot = Join-Path $InstallDir 'stride-codex-ideation'

# AGENTS.md is handled as bytes, exactly as install.sh handles it: Latin-1
# maps every byte to one character and back, so whatever encoding the user's
# file is in (UTF-8, with or without a BOM, or a legacy ANSI code page) survives
# untouched, and the bundle's UTF-8 bytes are copied verbatim. The markers are
# ASCII, so matching them is unaffected. (Get-Content -Raw returns $null for
# an empty file, and Set-Content would re-encode on Windows PowerShell 5.1.)
$ByteText = [System.Text.Encoding]::GetEncoding(28591)

# Read a file's bytes as text: '' for an empty file, and never evaluated --
# only pattern-matched.
function Read-Text([string]$Path) {
    return $ByteText.GetString([System.IO.File]::ReadAllBytes($Path))
}

# Write text back as the same bytes, with no BOM and no newline translation.
function Write-Text([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllBytes($Path, $ByteText.GetBytes($Text))
}

$SourceDir = $env:INSTALL_SOURCE_DIR
$tempRoot = $null
if ([string]::IsNullOrEmpty($SourceDir)) {
    # Ensure git is available before doing any filesystem work.
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Error "git was not found on PATH. Install Git (https://git-scm.com/downloads) and re-run this script."
        exit 1
    }
}

function Test-ReparsePoint([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return [bool]($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint))
}

# The path with every symbolic link and junction along it resolved, like
# install.sh's `pwd -P`. Resolve-Path leaves links in place, so walk the
# components and substitute each link's target (PowerShell 7: LinkTarget;
# Windows PowerShell 5.1: Target).
function Get-RealPath([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    $current = [System.IO.Path]::GetPathRoot($full)
    $queue = New-Object System.Collections.Generic.List[string]
    $queue.AddRange([string[]]$full.Substring($current.Length).Split([char[]]@('/', '\'), [System.StringSplitOptions]::RemoveEmptyEntries))
    $hops = 0
    while ($queue.Count -gt 0) {
        $name = $queue[0]
        $queue.RemoveAt(0)
        if ($name -eq '.') { continue }
        if ($name -eq '..') {
            $parent = Split-Path -Parent $current
            if ($parent) { $current = $parent }
            continue
        }
        $next = Join-Path $current $name
        $target = $null
        if ((Test-ReparsePoint $next) -and $hops -lt 40) {
            $item = Get-Item -LiteralPath $next -Force
            if ($item.PSObject.Properties['LinkTarget'] -and $item.LinkTarget) { $target = [string]$item.LinkTarget }
            elseif ($item.PSObject.Properties['Target'] -and $item.Target) { $target = [string](@($item.Target)[0]) }
        }
        if ($target) {
            # A relative target resolves against the link's own directory.
            $hops++
            if ([System.IO.Path]::IsPathRooted($target)) {
                $current = [System.IO.Path]::GetPathRoot($target)
                $target = $target.Substring($current.Length)
            }
            $queue.InsertRange(0, [string[]]$target.Split([char[]]@('/', '\'), [System.StringSplitOptions]::RemoveEmptyEntries))
        }
        else {
            $current = $next
        }
    }
    return $current
}

# Split text into lines that keep their "`n" terminator; a final line without
# one is kept as-is. Concatenating the result reproduces the input exactly.
function Split-Lines([string]$Text) {
    $lines = New-Object System.Collections.Generic.List[string]
    $start = 0
    while ($start -lt $Text.Length) {
        $nl = $Text.IndexOf("`n", $start)
        if ($nl -lt 0) { $lines.Add($Text.Substring($start)); break }
        $lines.Add($Text.Substring($start, $nl - $start + 1))
        $start = $nl + 1
    }
    return ,$lines
}

# The managed block's (begin, end) 0-based line indexes, or $null. Markers
# count only as whole lines (exact, case-sensitive; a CRLF line ending is
# allowed, so a block checked out with Windows line endings is still refreshed
# rather than duplicated); the block is the first END
# line paired with the nearest BEGIN line before it -- the first BEGIN/END pair
# with no other marker between. Identical to install.sh's awk scan.
function Find-ManagedBlock($Lines, [string]$Begin, [string]$End) {
    $open = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line.EndsWith("`n")) { $line = $line.Substring(0, $line.Length - 1) }
        if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }
        if ($line -ceq $Begin) { $open = $i }
        elseif (($line -ceq $End) -and ($open -ge 0)) { return @($open, $i) }
    }
    return $null
}

# In project mode the install directory lives in a repository the user may not
# control. A committed symlink or junction there (.agents -> .., say) would
# redirect every write -- and the helper-root clear below -- outside the
# project, so refuse unless .agents and its skills/ and agents/ are real
# directories where they appear to be.
if ($Project) {
    foreach ($d in @($InstallDir, (Join-Path $InstallDir 'skills'), (Join-Path $InstallDir 'agents'))) {
        if (Test-ReparsePoint $d) {
            throw "$d is a symbolic link; refusing to install through it. Replace it with a real directory."
        }
    }
    if (Test-Path -LiteralPath $InstallDir) {
        $expected = Join-Path (Get-RealPath (Get-Location).Path) '.agents'
        if ((Get-RealPath $InstallDir) -ne $expected) {
            throw ".agents does not resolve to $expected; refusing to install through it."
        }
    }
}

# Remove a link at a destination so the copy that follows never writes through
# it (a directory link is removed as a link; its target is never touched).
function Remove-LinkAt([string]$Path) {
    if (Test-ReparsePoint $Path) { (Get-Item -LiteralPath $Path -Force).Delete() }
}

# Create destination directories. The ideation plugin ships skills, agents,
# lib/ helpers (referenced by the stridify skill), and fixtures (calibration
# references documented in fixtures/README.md and exercised by the smoke
# test suite).
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'skills') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'agents') | Out-Null

try {
    if ([string]::IsNullOrEmpty($SourceDir)) {
        # Clone into a temp dir; always clean up.
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("stride-codex-ideation-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
        $cloneDir = Join-Path $tempRoot 'stride-codex-ideation'
        Write-Host "Downloading from $Repo..."
        & git clone --quiet --depth 1 $Repo $cloneDir
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed with exit code $LASTEXITCODE"
        }
    }
    else {
        # .NET file APIs resolve relative paths against the process directory,
        # not PowerShell's location, so pin the checkout to an absolute path.
        $cloneDir = (Resolve-Path -LiteralPath $SourceDir).Path
        Write-Host "Installing from local checkout $cloneDir..."
    }

    # Copy skills (each skill is a directory containing SKILL.md).
    $skillSrcRoot = Join-Path $cloneDir 'skills'
    $skillDirs = @(Get-ChildItem -LiteralPath $skillSrcRoot -Directory)
    Write-Host ("Installing {0} skills..." -f $skillDirs.Count)
    foreach ($skillDir in $skillDirs) {
        $destSkillDir = Join-Path (Join-Path $InstallDir 'skills') $skillDir.Name
        Remove-LinkAt $destSkillDir
        New-Item -ItemType Directory -Force -Path $destSkillDir | Out-Null
        $srcSkill = Join-Path $skillDir.FullName 'SKILL.md'
        $destSkill = Join-Path $destSkillDir 'SKILL.md'
        Remove-LinkAt $destSkill
        Copy-Item -LiteralPath $srcSkill -Destination $destSkill -Force
    }

    # Copy agents (each agent is a bare .md file per Codex naming convention).
    $agentSrcRoot = Join-Path $cloneDir 'agents'
    $agentFiles = @(Get-ChildItem -LiteralPath $agentSrcRoot -Filter '*.md' -File)
    Write-Host ("Installing {0} agents..." -f $agentFiles.Count)
    foreach ($agentFile in $agentFiles) {
        $destAgent = Join-Path (Join-Path $InstallDir 'agents') $agentFile.Name
        Remove-LinkAt $destAgent
        Copy-Item -LiteralPath $agentFile.FullName -Destination $destAgent -Force
    }

    # Clear the namespaced helper root, then recreate it, so files a newer
    # release no longer ships do not linger. $HelperRoot is always
    # <install-dir>/stride-codex-ideation -- this plugin's own directory -- so
    # nothing else is ever removed.
    # A helper root that is itself a link (to a dev checkout, say) is removed
    # as a link -- its target is never touched. Otherwise refuse when the
    # source checkout is that directory or lives inside it (links resolved, as
    # install.sh does with pwd -P): clearing it would delete what is about to
    # be copied. Directory.Delete removes nested links without recursing into
    # their targets, which Remove-Item -Recurse does not guarantee on Windows
    # PowerShell 5.1.
    if (Test-ReparsePoint $HelperRoot) {
        (Get-Item -LiteralPath $HelperRoot -Force).Delete()
    }
    elseif (Test-Path -LiteralPath $HelperRoot) {
        $srcReal = (Get-RealPath $cloneDir).TrimEnd('/', '\') + [IO.Path]::DirectorySeparatorChar
        $helperReal = (Get-RealPath $HelperRoot).TrimEnd('/', '\') + [IO.Path]::DirectorySeparatorChar
        if ($srcReal.StartsWith($helperReal, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The source checkout $cloneDir is inside the install target $HelperRoot; install from a separate checkout."
        }
        [System.IO.Directory]::Delete($HelperRoot, $true)
    }
    $libDest = Join-Path $HelperRoot 'lib'
    $fixDest = Join-Path $HelperRoot 'fixtures'
    New-Item -ItemType Directory -Force -Path $libDest | Out-Null
    New-Item -ItemType Directory -Force -Path $fixDest | Out-Null
    $agentsDest = Join-Path $HelperRoot 'agents'
    New-Item -ItemType Directory -Force -Path $agentsDest | Out-Null

    # Copy lib/ helpers (.sh, .ps1, .py). The stridify skill body and the
    # smoke test invoke them directly.
    Write-Host "Installing lib/ helpers..."
    foreach ($item in @(Get-ChildItem -LiteralPath (Join-Path $cloneDir 'lib') -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $libDest -Recurse -Force
    }

    # Copy fixtures. Required by lib/run_smoke_test.sh and by the
    # calibration references the README and SMOKE-TEST-NOTE.md point at.
    Write-Host "Installing fixtures..."
    foreach ($item in @(Get-ChildItem -LiteralPath (Join-Path $cloneDir 'fixtures') -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $fixDest -Recurse -Force
    }

    # A second copy of the agent files beside the helpers: the skills locate
    # an agent's instructions at <helper root>/agents/<name>.md, the same
    # relative path a marketplace plugin directory has, so one lookup serves
    # every install.
    foreach ($agentFile in $agentFiles) {
        Copy-Item -LiteralPath $agentFile.FullName -Destination $agentsDest -Force
    }

    # Copy AGENTS.md to the destination. Preserve any existing user-authored
    # AGENTS.md by confining our content to an idempotent, clearly delimited
    # managed block: a fresh file gets the block; an existing file keeps ALL of
    # its content and only the block is inserted or refreshed in place (never
    # clobbered, never duplicated). Mirrors install.sh exactly, byte for byte.
    $agentsMdSrc = Join-Path $cloneDir 'AGENTS.md'
    if ($Project) {
        $DestAgents = Join-Path (Get-Location).Path 'AGENTS.md'
    }
    else {
        $DestAgents = Join-Path $InstallDir 'AGENTS.md'
    }

    $BeginMarker = '<!-- BEGIN stride-ideation -->'
    $EndMarker   = '<!-- END stride-ideation -->'
    $NoteMarker  = '<!-- Managed by the stride-codex-ideation installer; content between these markers is regenerated on each install. Add your own notes outside this block. -->'
    # The bundle is copied verbatim; a missing final newline is supplied so the
    # END marker always starts its own line.
    $Bundle = Read-Text $agentsMdSrc
    if ($Bundle.Length -gt 0 -and -not $Bundle.EndsWith("`n")) { $Bundle += "`n" }
    $Block = $BeginMarker + "`n" + $NoteMarker + "`n" + $Bundle + $EndMarker + "`n"

    # Never write through a symbolic link: a project's AGENTS.md could point
    # at any file the user can write (a shell rc file, say).
    if (Test-ReparsePoint $DestAgents) {
        throw "$DestAgents is a symbolic link; refusing to write through it. Replace it with a regular file, or add the managed block by hand."
    }

    if (-not (Test-Path -LiteralPath $DestAgents)) {
        Write-Text $DestAgents $Block
        Write-Host "Created AGENTS.md at $DestAgents"
    }
    else {
        # Locate a WELL-FORMED managed block (see Find-ManagedBlock). An
        # orphaned or out-of-order marker (BEGIN with no END, END before any
        # BEGIN, a marker quoted mid-line) must NEVER truncate user content,
        # so it falls through to the append path -- and because the appended
        # block is then the first adjacent pair, a re-run refreshes it.
        $Existing = Read-Text $DestAgents
        $lines = Split-Lines $Existing
        $pair = Find-ManagedBlock $lines $BeginMarker $EndMarker
        if ($null -ne $pair) {
            $before = -join @($lines | Select-Object -First $pair[0])
            $after  = -join @($lines | Select-Object -Skip ($pair[1] + 1))
            Write-Text $DestAgents ($before + $Block + $after)
            Write-Host "Updated the stride-ideation managed block in $DestAgents (your content preserved)"
        }
        else {
            # Separate the block from existing content by one blank line; an
            # empty file gets the block alone.
            $sep = ''
            if ($Existing.Length -gt 0) {
                $sep = if ($Existing.EndsWith("`n")) { "`n" } else { "`n`n" }
            }
            Write-Text $DestAgents ($Existing + $sep + $Block)
            Write-Host "Appended the stride-ideation managed block to $DestAgents (your content preserved)"
        }
    }

    # Releases before the namespaced layout copied the helpers straight into
    # <install-dir>/lib and <install-dir>/fixtures. Those shared directories may
    # hold other tools' files, so they are never deleted here -- only pointed out.
    $legacyLib = Join-Path $InstallDir 'lib'
    if ((Test-Path -LiteralPath (Join-Path $legacyLib 'filename.sh')) -and (Test-Path -LiteralPath (Join-Path $legacyLib 'validate_batch.py'))) {
        Write-Host ""
        Write-Host "Note: an earlier release installed helpers into $legacyLib and"
        Write-Host "$(Join-Path $InstallDir 'fixtures'). They are no longer used; remove them by hand if no"
        Write-Host "other tool needs them."
    }

    if (-not $Project) {
        Write-Host ""
        Write-Host "Note: Copy the managed block from ~/.agents/AGENTS.md into each project's"
        Write-Host "AGENTS.md, or run this installer with -Project from the project root."
    }
}
finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -Recurse -Force -LiteralPath $tempRoot -ErrorAction SilentlyContinue
    }
}

$installedSkills   = @(Get-ChildItem -LiteralPath (Join-Path $InstallDir 'skills') -Directory           -ErrorAction SilentlyContinue).Count
$installedAgents   = @(Get-ChildItem -LiteralPath (Join-Path $InstallDir 'agents') -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
$installedHelpers  = @(Get-ChildItem -LiteralPath (Join-Path $HelperRoot 'lib')                         -ErrorAction SilentlyContinue).Count
$installedFixtures = @(Get-ChildItem -LiteralPath (Join-Path $HelperRoot 'fixtures')                    -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Host "Stride Ideation for Codex CLI installed successfully!"
Write-Host ""
Write-Host "Installed:"
Write-Host ("  Skills:   {0} skills"        -f $installedSkills)
Write-Host ("  Agents:   {0} agents"        -f $installedAgents)
Write-Host ("  Helpers:  {0} files in lib/" -f $installedHelpers)
Write-Host ("  Fixtures: {0} files in fixtures/" -f $installedFixtures)
Write-Host ("  Helper root: {0}" -f (Resolve-Path -LiteralPath $HelperRoot).Path)
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Create .stride_auth.md in your project root with your Stride API"
Write-Host "     credentials (see the README). Required only for stride-ideation-stridify."
Write-Host "  2. Add .stride_auth.md to .gitignore - it contains a secret."
Write-Host "  3. Activate the stride-ideation-ideate skill to drive an ideation session."
