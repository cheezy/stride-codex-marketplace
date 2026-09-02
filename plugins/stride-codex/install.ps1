<#
.SYNOPSIS
    Install Stride skills and agents for Codex CLI.

.DESCRIPTION
    Installs Stride skills (skills/) and agents (agents/) for use with the
    Codex CLI. By default installs globally to $env:USERPROFILE\.agents\ so
    skills and agents are available in all projects. Use -Project to install
    to .\.agents\ in the current directory instead.

.PARAMETER Project
    Install into .\.agents\ in the current directory instead of the global
    per-user location.

.PARAMETER Help
    Print usage information and exit.

.EXAMPLE
    irm https://raw.githubusercontent.com/cheezy/stride-codex/main/install.ps1 | iex

    Installs globally to $env:USERPROFILE\.agents\.

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/cheezy/stride-codex/main/install.ps1))) -Project

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

$Repo = 'https://github.com/cheezy/stride-codex.git'

if ($Project) {
    $InstallDir = Join-Path (Get-Location).Path '.agents'
    Write-Host "Installing Stride for Codex CLI into .agents\ (project-local)..."
}
else {
    $InstallDir = Join-Path $env:USERPROFILE '.agents'
    Write-Host "Installing Stride for Codex CLI into ~\.agents\ (global)..."
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
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'hooks') | Out-Null

# Clone into a temp dir; always clean up.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("stride-codex-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$cloneDir = Join-Path $tempRoot 'stride-codex'

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

    # Copy the hook surface (W2141). Only the two runtime files ship - the test
    # script stays in the repo. Codex discovers a plugin-bundled hooks/hooks.json
    # by default, so without this copy the hook surface would be inert.
    #
    # NOTE: this port ships no stride-hook.ps1 twin yet, so on native Windows
    # without a bash on PATH the hook records no loop state. The .sh is copied
    # regardless because Git Bash and WSL run it directly.
    Write-Host "Installing hooks..."
    $hookSrcRoot = Join-Path $cloneDir 'hooks'
    $hookDest = Join-Path $InstallDir 'hooks'
    foreach ($hookFile in @('stride-hook.sh', 'stride-stop-gate.sh', 'hooks.json')) {
        Copy-Item -Path (Join-Path $hookSrcRoot $hookFile) -Destination (Join-Path $hookDest $hookFile) -Force
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
        Write-Host "Note: Copy AGENTS.md to each project that uses Stride:"
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
$installedHooks = (Get-ChildItem -Path (Join-Path $InstallDir 'hooks') -File -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Host "Stride for Codex CLI installed successfully!"
Write-Host ""
Write-Host "Installed:"
Write-Host ("  Skills: {0} skills" -f $installedSkills)
Write-Host ("  Agents: {0} agents" -f $installedAgents)
Write-Host ("  Hooks:  {0} files" -f $installedHooks)
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Add to .gitignore FIRST: .stride_auth.md, .stride/, and .exploratory/"
Write-Host "     (.gitignore is inert for a path git already tracks, so do this before"
Write-Host "      your first session; .exploratory/ applies when the exploratory-testing"
Write-Host "      plugin is installed and its artifacts arrive untracked)"
Write-Host "  2. Create .stride_auth.md with your API credentials (see README)"
Write-Host "  3. Create .stride.md with your hook commands"
Write-Host "  4. Register the hook. This is a loose .agents\ install, NOT a plugin"
Write-Host ("     bundle, so {0}\hooks\hooks.json is not auto-discovered." -f $InstallDir)
if ($Project) {
    Write-Host "     Add this to .codex\hooks.json in this repo:"
}
else {
    Write-Host "     Add this to ~\.codex\hooks.json:"
}
Write-Host ""
Write-Host '       {"hooks":{'
Write-Host '         "PostToolUse":[{"matcher":"Bash","hooks":[{'
Write-Host '           "type":"command","async":false,"timeout":60,'
Write-Host ("           ""command"":""{0}/hooks/stride-hook.sh post""}}]}}]," -f ($InstallDir -replace '\\','/'))
Write-Host '         "Stop":[{"hooks":[{'
Write-Host '           "type":"command","async":false,"timeout":10,'
Write-Host ("           ""command"":""{0}/hooks/stride-stop-gate.sh""}}]}}]}}}}" -f ($InstallDir -replace '\\','/'))
Write-Host ""
Write-Host "  5. Approve the hook when Codex prompts. Hook definitions are trust-hash"
Write-Host "     pinned, so a fresh approval is required after any update that changes"
Write-Host "     hooks/stride-hook.sh, hooks/stride-stop-gate.sh or hooks/hooks.json."
