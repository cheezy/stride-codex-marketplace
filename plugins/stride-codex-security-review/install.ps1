<#
.SYNOPSIS
    Install Stride security-review skills and agents for Codex CLI.

.DESCRIPTION
    Installs Stride security-review skills (skills/) and agents (agents/) for
    use with the Codex CLI. By default installs globally to
    $env:USERPROFILE\.agents\ so skills and agents are available in all projects.
    Use -Project to install to .\.agents\ in the current directory instead.

.PARAMETER Project
    Install into .\.agents\ in the current directory instead of the global
    per-user location.

.PARAMETER Help
    Print usage information and exit.

.EXAMPLE
    irm https://raw.githubusercontent.com/cheezy/stride-codex-security-review/main/install.ps1 | iex

    Installs globally to $env:USERPROFILE\.agents\.

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/cheezy/stride-codex-security-review/main/install.ps1))) -Project

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

$Repo = 'https://github.com/cheezy/stride-codex-security-review.git'

if ($Project) {
    $InstallDir = Join-Path (Get-Location).Path '.agents'
    Write-Host "Installing Stride security review for Codex CLI into .agents\ (project-local)..."
}
else {
    $InstallDir = Join-Path $env:USERPROFILE '.agents'
    Write-Host "Installing Stride security review for Codex CLI into ~\.agents\ (global)..."
}

# Ensure git is available before doing any filesystem work.
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Error "git was not found on PATH. Install Git for Windows (https://git-scm.com/download/win) and re-run this script."
    exit 1
}

# Create destination directories.
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'skills') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'agents') | Out-Null

# Clone into a temp dir; always clean up.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("stride-codex-security-review-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$cloneDir = Join-Path $tempRoot 'stride-codex-security-review'

try {
    Write-Host "Downloading from $Repo..."
    & git clone --quiet --depth 1 $Repo $cloneDir
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }

    # Copy skills (each skill is a directory containing SKILL.md).
    # @() forces array semantics so .Count is correct even for a single result on PS 5.1.
    $skillSrcRoot = Join-Path $cloneDir 'skills'
    $skillDirs = @(Get-ChildItem -Path $skillSrcRoot -Directory)
    Write-Host ("Installing {0} skills..." -f $skillDirs.Count)
    foreach ($skillDir in $skillDirs) {
        $destSkillDir = Join-Path (Join-Path $InstallDir 'skills') $skillDir.Name
        New-Item -ItemType Directory -Force -Path $destSkillDir | Out-Null
        $srcSkill = Join-Path $skillDir.FullName 'SKILL.md'
        Copy-Item -Path $srcSkill -Destination (Join-Path $destSkillDir 'SKILL.md') -Force
    }

    # Copy agents (each agent is a bare .md file, per Codex naming convention).
    $agentSrcRoot = Join-Path $cloneDir 'agents'
    $agentFiles = @(Get-ChildItem -Path $agentSrcRoot -Filter '*.md' -File)
    Write-Host ("Installing {0} agents..." -f $agentFiles.Count)
    foreach ($agentFile in $agentFiles) {
        Copy-Item -Path $agentFile.FullName -Destination (Join-Path $InstallDir 'agents') -Force
    }

    # Copy AGENTS.md to the appropriate location.
    $agentsMdSrc = Join-Path $cloneDir 'AGENTS.md'
    if ($Project) {
        Copy-Item -Path $agentsMdSrc -Destination (Join-Path (Get-Location).Path 'AGENTS.md') -Force
        Write-Host "Copied AGENTS.md to project root"
    }
    else {
        Copy-Item -Path $agentsMdSrc -Destination (Join-Path $InstallDir 'AGENTS.md') -Force
        Write-Host "Copied AGENTS.md to $InstallDir\"
        Write-Host ""
        Write-Host "Note: Copy AGENTS.md to each project that uses Stride security review:"
        Write-Host "  Copy-Item ~\.agents\AGENTS.md .\AGENTS.md"
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force -Path $tempRoot -ErrorAction SilentlyContinue
    }
}

$installedSkills = (Get-ChildItem -Path (Join-Path $InstallDir 'skills') -Directory -ErrorAction SilentlyContinue).Count
$installedAgents = (Get-ChildItem -Path (Join-Path $InstallDir 'agents') -Filter '*.md' -File -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Host "Stride security review for Codex CLI installed successfully!"
Write-Host ""
Write-Host "Installed:"
Write-Host ("  Skills: {0} skills" -f $installedSkills)
Write-Host ("  Agents: {0} agents" -f $installedAgents)
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. In any git repository, activate the security-review skill before merging security-sensitive changes"
Write-Host "  2. See the README for diff-mode, full-tree, and considerations-mode reviews"
