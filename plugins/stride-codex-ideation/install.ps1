<#
.SYNOPSIS
    Install Stride ideation skills and agents for Codex CLI.

.DESCRIPTION
    Installs the Stride ideation skills (skills/), agents (agents/), lib/
    helpers, and fixtures/ for use with the Codex CLI. By default installs
    globally to $env:USERPROFILE\.agents\ so the skills and agents are
    available in all projects. Use -Project to install to .\.agents\ in
    the current directory instead.

.PARAMETER Project
    Install into .\.agents\ in the current directory instead of the global
    per-user location.

.PARAMETER Help
    Print usage information and exit.

.EXAMPLE
    irm https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.ps1 | iex

    Installs globally to $env:USERPROFILE\.agents\.

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.ps1))) -Project

    Installs into .\.agents\ in the current directory.

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
    Write-Host "  (default)   Install globally to `$env:USERPROFILE\.agents\ (available in all projects)"
    Write-Host "  -Project    Install to .\.agents\ in the current directory"
    exit 0
}

$Repo = 'https://github.com/cheezy/stride-codex-ideation.git'

if ($Project) {
    $InstallDir = Join-Path (Get-Location).Path '.agents'
    Write-Host "Installing Stride Ideation for Codex CLI into .agents\ (project-local)..."
}
else {
    $InstallDir = Join-Path $env:USERPROFILE '.agents'
    Write-Host "Installing Stride Ideation for Codex CLI into ~\.agents\ (global)..."
}

# Ensure git is available before doing any filesystem work.
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Error "git was not found on PATH. Install Git for Windows (https://git-scm.com/download/win) and re-run this script."
    exit 1
}

# Create destination directories. The ideation plugin ships skills, agents,
# lib/ helpers (referenced by the stridify skill), and fixtures (calibration
# references documented in fixtures/README.md and exercised by the smoke
# test suite).
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'skills')   | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'agents')   | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'lib')      | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'fixtures') | Out-Null

# Clone into a temp dir; always clean up.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("stride-codex-ideation-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$cloneDir = Join-Path $tempRoot 'stride-codex-ideation'

try {
    Write-Host "Downloading from $Repo..."
    & git clone --quiet --depth 1 $Repo $cloneDir
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }

    # Copy skills (each skill is a directory containing SKILL.md).
    $skillSrcRoot = Join-Path $cloneDir 'skills'
    $skillDirs = @(Get-ChildItem -Path $skillSrcRoot -Directory)
    Write-Host ("Installing {0} skills..." -f $skillDirs.Count)
    foreach ($skillDir in $skillDirs) {
        $destSkillDir = Join-Path (Join-Path $InstallDir 'skills') $skillDir.Name
        New-Item -ItemType Directory -Force -Path $destSkillDir | Out-Null
        $srcSkill = Join-Path $skillDir.FullName 'SKILL.md'
        Copy-Item -Path $srcSkill -Destination (Join-Path $destSkillDir 'SKILL.md') -Force
    }

    # Copy agents (each agent is a bare .md file per Codex naming convention).
    $agentSrcRoot = Join-Path $cloneDir 'agents'
    $agentFiles = @(Get-ChildItem -Path $agentSrcRoot -Filter '*.md' -File)
    Write-Host ("Installing {0} agents..." -f $agentFiles.Count)
    foreach ($agentFile in $agentFiles) {
        Copy-Item -Path $agentFile.FullName -Destination (Join-Path $InstallDir 'agents') -Force
    }

    # Copy lib/ helpers (.sh, .ps1, .py). The stridify skill body and the
    # smoke test invoke them directly.
    $libSrcRoot = Join-Path $cloneDir 'lib'
    $libDest = Join-Path $InstallDir 'lib'
    Write-Host "Installing lib/ helpers..."
    Copy-Item -Path (Join-Path $libSrcRoot '*') -Destination $libDest -Recurse -Force

    # Copy fixtures. Required by lib/run_smoke_test.sh and by the
    # calibration references the README and SMOKE-TEST-NOTE.md point at.
    $fixSrcRoot = Join-Path $cloneDir 'fixtures'
    $fixDest = Join-Path $InstallDir 'fixtures'
    Write-Host "Installing fixtures..."
    Copy-Item -Path (Join-Path $fixSrcRoot '*') -Destination $fixDest -Recurse -Force

    # Copy AGENTS.md to the destination. Preserve any existing user-authored
    # AGENTS.md by confining our content to an idempotent, clearly delimited
    # managed block: a fresh file gets the block; an existing file keeps ALL of
    # its content and only the block is inserted or refreshed in place (never
    # clobbered, never duplicated). Mirrors install.sh exactly.
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
    $Bundle      = (Get-Content -Raw $agentsMdSrc).TrimEnd("`r", "`n")
    $Block       = $BeginMarker + "`n" + $NoteMarker + "`n" + $Bundle + "`n" + $EndMarker

    if (-not (Test-Path $DestAgents)) {
        Set-Content -Path $DestAgents -Value ($Block + "`n") -NoNewline
        Write-Host "Created AGENTS.md at $DestAgents"
    }
    else {
        # Read as plain text; never evaluate or source the destination contents.
        $Existing = Get-Content -Raw $DestAgents
        $startIdx = $Existing.IndexOf($BeginMarker)
        $endIdx   = $Existing.IndexOf($EndMarker)
        if (($startIdx -ge 0) -and ($endIdx -ge $startIdx)) {
            $before = $Existing.Substring(0, $startIdx)
            $after  = $Existing.Substring($endIdx + $EndMarker.Length)
            Set-Content -Path $DestAgents -Value ($before + $Block + $after) -NoNewline
            Write-Host "Updated the stride-ideation managed block in $DestAgents (your content preserved)"
        }
        else {
            $sep = if ($Existing.EndsWith("`n")) { "`n" } else { "`n`n" }
            Add-Content -Path $DestAgents -Value ($sep + $Block + "`n") -NoNewline
            Write-Host "Appended the stride-ideation managed block to $DestAgents (your content preserved)"
        }
    }

    if (-not $Project) {
        Write-Host ""
        Write-Host "Note: Copy the managed block from ~\.agents\AGENTS.md into each project's"
        Write-Host "AGENTS.md, or run this installer with -Project from the project root."
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force -Path $tempRoot -ErrorAction SilentlyContinue
    }
}

$installedSkills   = @(Get-ChildItem -Path (Join-Path $InstallDir 'skills')   -Directory          -ErrorAction SilentlyContinue).Count
$installedAgents   = @(Get-ChildItem -Path (Join-Path $InstallDir 'agents')   -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
$installedHelpers  = @(Get-ChildItem -Path (Join-Path $InstallDir 'lib')      -File                -ErrorAction SilentlyContinue).Count
$installedFixtures = @(Get-ChildItem -Path (Join-Path $InstallDir 'fixtures') -File                -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Host "Stride Ideation for Codex CLI installed successfully!"
Write-Host ""
Write-Host "Installed:"
Write-Host ("  Skills:   {0} skills"        -f $installedSkills)
Write-Host ("  Agents:   {0} agents"        -f $installedAgents)
Write-Host ("  Helpers:  {0} files in lib/" -f $installedHelpers)
Write-Host ("  Fixtures: {0} files in fixtures/" -f $installedFixtures)
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Create .stride_auth.md in your project root with your Stride API"
Write-Host "     credentials (see the README). Required only for stride-ideation-stridify."
Write-Host "  2. Add .stride_auth.md to .gitignore - it contains a secret."
Write-Host "  3. Activate the stride-ideation-ideate skill to drive an ideation session."
