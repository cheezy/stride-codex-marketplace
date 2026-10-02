# PowerShell mirror of test-commit-scope.sh — verifies that the artifact
# commits in the ideate (Step 9) and stridify (Step 8d) skills commit ONLY the
# artifact when another file was staged before the session.
#
# On a PowerShell-only host the skills tell the model to run the same two git
# commands as the bash block. This test reads those commands from each skill's
# block — the `git add` line and every `git commit` line — and runs them from
# PowerShell in a scratch repository (with and without prior history) whose
# index already holds an unrelated staged file.
#
# Run:
#   pwsh -NoProfile -File lib/test-commit-scope.ps1
#
# Exits 0 if all tests pass, non-zero otherwise.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-commit-scope.ps1 — the artifact commit leaves pre-staged files alone'
Write-Host ''

$ReqDoc = 'docs/ideation/2026-05-12T103000-dark-mode-toggle-requirements.md'
$Batch  = 'docs/ideation/2026-05-12T120000-dark-mode-toggle-stride-batch.json'
$Staged = 'docs/ideation/unrelated-notes.md'
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('sti-commit-scope-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null

# Get-BlockLines <skill> - every line of the skill's commit block.
function Get-BlockLines([string]$Skill) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PluginRoot "skills/$Skill/SKILL.md"))
    $blocks = [regex]::Matches($text, '(?ms)^```bash[ \t]*\r?\n(.*?)^```') |
        Where-Object { $_.Groups[1].Value.Contains('git add -- "$TARGET_PATH"') }
    if (@($blocks).Count -ne 1) { throw "expected one commit block in $Skill, found $(@($blocks).Count)" }
    return @($blocks[0].Groups[1].Value -split "\r?\n")
}

# Get-CommitLines <skill> - the `git commit` lines of the skill's commit block.
function Get-CommitLines([string]$Skill) {
    return @((Get-BlockLines $Skill) | Where-Object { $_ -match '^\s*git commit ' })
}

# Get-CommitSubject <skill> <flagSet> - the commit subject the skill's block
# would record, read from the block text: the `git commit -m "..."` line of the
# `if [ -n "${VAR:-}" ]` branch when the flag (--continue / --goal) is set,
# else the one of the `else` branch, with $SLUG filled from the fixture and the
# (unset) $GOAL_SLUG empty, exactly as the bash test fills the placeholders.
function Get-CommitSubject([string]$Skill, [bool]$FlagSet) {
    $lines = Get-BlockLines $Skill
    $ifAt = -1; $elseAt = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($ifAt -lt 0 -and $lines[$i] -match '^\s*if \[ -n "\$\{[A-Z_]+:-\}" \]; then\s*$') { $ifAt = $i; continue }
        if ($ifAt -ge 0 -and $elseAt -lt 0 -and $lines[$i] -match '^\s*else\s*$') { $elseAt = $i }
    }
    if ($ifAt -lt 0 -or $elseAt -lt 0) { throw "no if/else commit branches in the $Skill block" }
    $from = if ($FlagSet) { $ifAt + 1 } else { $elseAt + 1 }
    $commit = $lines[$from..($lines.Count - 1)] | Where-Object { $_ -match '^\s*git commit ' } | Select-Object -First 1
    $m = [regex]::Match([string]$commit, 'git commit -m "([^"]*)"')
    if (-not $m.Success) { throw "no git commit -m line in the selected $Skill branch" }
    $values = @{ SLUG = 'dark-mode-toggle'; GOAL_SLUG = '' }
    return [regex]::Replace($m.Groups[1].Value, '\$([A-Z_]+)', { param($v) $values[$v.Groups[1].Value] })
}

# New-Repo <dir> <withHistory> — scratch repo with an unrelated staged file.
function New-Repo([string]$Dir, [bool]$WithHistory) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'docs/ideation') | Out-Null
    & git -C $Dir init -q
    & git -C $Dir config user.email test@example.com
    & git -C $Dir config user.name test
    if ($WithHistory) {
        Set-Content -LiteralPath (Join-Path $Dir 'README.md') -Value 'seed'
        & git -C $Dir add README.md
        & git -C $Dir commit -q -m seed
    }
    Set-Content -LiteralPath (Join-Path $Dir $Staged) -Value 'private scratch notes, not for this commit'
    & git -C $Dir add $Staged
    Set-Content -LiteralPath (Join-Path $Dir $ReqDoc) -Value '# Dark mode toggle'
    Copy-Item -LiteralPath (Join-Path $PluginRoot 'fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json') -Destination (Join-Path $Dir $Batch)
}

# Invoke-SkillCommit <dir> <artifact> <message> <usePathspec> — the two
# commands the skill's block runs, issued from PowerShell.
# Like the block, pathspecs are literal (GIT_LITERAL_PATHSPECS=1) and a failed
# `git add` stops before the commit.
function Invoke-SkillCommit([string]$Dir, [string]$Artifact, [string]$Message, [bool]$UsePathspec) {
    $prior = $env:GIT_LITERAL_PATHSPECS
    $env:GIT_LITERAL_PATHSPECS = '1'
    try {
        & git -C $Dir add -- $Artifact
        if ($LASTEXITCODE -ne 0) { return $LASTEXITCODE }
        if ($UsePathspec) {
            & git -C $Dir commit -q -m $Message -- $Artifact
        } else {
            & git -C $Dir commit -q -m $Message
        }
        return $LASTEXITCODE
    } finally {
        $env:GIT_LITERAL_PATHSPECS = $prior
    }
}

try {
    # Subject = the subject the bash test expects (hard-coded, as there); the
    # message actually committed is read from the skill block (FlagSet picks
    # the --continue / --goal branch), so a reworded block fails the format check.
    $cases = @(
        @{ Label = 'ideate Step 9'; Skill = 'stride-ideation-ideate'; Artifact = $ReqDoc; FlagSet = $false; StaticCheck = $true; Subject = 'stride-ideation: requirements for dark-mode-toggle' },
        @{ Label = 'ideate Step 9 --continue'; Skill = 'stride-ideation-ideate'; Artifact = $ReqDoc; FlagSet = $true; StaticCheck = $false; Subject = 'stride-ideation: refine requirements for dark-mode-toggle' },
        @{ Label = 'stridify Step 8d'; Skill = 'stride-ideation-stridify'; Artifact = $Batch; FlagSet = $false; StaticCheck = $true; Subject = 'stride-ideation: decomposition for dark-mode-toggle' }
    )
    foreach ($case in $cases) {
        $commitLines = Get-CommitLines $case.Skill
        $withPathspec = @($commitLines | Where-Object { $_.Contains('-- "$TARGET_PATH"') })
        if ($case.StaticCheck) {
            if ($commitLines.Count -ge 2 -and $withPathspec.Count -eq $commitLines.Count) {
                Pass "$($case.Label): every git commit line passes the artifact as a pathspec"
            } else {
                Fail "$($case.Label): a git commit line has no -- `"`$TARGET_PATH`" pathspec" ($commitLines -join ' | ')
            }
        }
        $message = Get-CommitSubject $case.Skill $case.FlagSet

        foreach ($history in @($true, $false)) {
            $tag = "$($case.Label) (history: $(if ($history) { 'yes' } else { 'no' }))"
            $dir = Join-Path $Tmp ([guid]::NewGuid())
            New-Repo $dir $history
            $rc = Invoke-SkillCommit $dir $case.Artifact $message ($withPathspec.Count -gt 0)
            if ($rc -eq 0) { Pass "${tag}: the commit exits 0" } else { Fail "${tag}: the commit exited $rc"; continue }
            $committed = @((& git -C $dir show --name-only --pretty=format: HEAD) | Where-Object { $_ })
            if ($committed.Count -eq 1 -and $committed[0] -eq $case.Artifact) {
                Pass "${tag}: the new commit contains only the artifact"
            } else {
                Fail "${tag}: the new commit contains more than the artifact" ($committed -join ' ')
            }
            $stillStaged = @(& git -C $dir diff --cached --name-only) -contains $Staged
            if ($stillStaged) { Pass "${tag}: the pre-staged file is still staged" } else { Fail "${tag}: the pre-staged file is no longer staged" }
            if ($committed -contains $Staged) { Fail "${tag}: the pre-staged file was swept into the commit" } else { Pass "${tag}: the pre-staged file is absent from the commit" }
            $subject = (& git -C $dir log -1 --pretty=%s) -join "`n"
            if ($subject -ceq $case.Subject) {
                Pass "${tag}: the commit message format is unchanged"
            } else {
                Fail "${tag}: unexpected commit message" $subject
            }
        }
    }

    # Control: without the pathspec, git commit records the pre-staged file too.
    $dir = Join-Path $Tmp 'control'
    New-Repo $dir $true
    $null = Invoke-SkillCommit $dir $ReqDoc 'stride-ideation: requirements for dark-mode-toggle' $false
    if (@(& git -C $dir show --name-only --pretty=format: HEAD) -contains $Staged) {
        Pass 'control: without the pathspec the pre-staged file is swept in'
    } else {
        Fail 'control: the no-pathspec commit did not sweep, so the cases above prove nothing'
    }
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
