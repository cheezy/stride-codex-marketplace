# PowerShell mirror of test-draft.sh — unit tests for lib/draft.ps1, the
# stride-ideation-ideate intra-session draft autosave/resume helpers (W1145).
#
# Run:
#   pwsh -File lib/test-draft.ps1
#
# Exits 0 if all tests pass, non-zero otherwise.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'draft.ps1')

$script:PASS = 0
$script:FAIL = 0
function Pass([string]$msg) { $script:PASS++; Write-Host "  PASS  $msg" }
function Fail([string]$msg, [string]$detail = '') {
    $script:FAIL++
    Write-Host "  FAIL  $msg"
    if ($detail) { Write-Host "        $detail" }
}
function Assert-Equal([string]$name, [string]$expected, [string]$actual) {
    if ($expected -ceq $actual) { Pass $name } else { Fail $name "expected=[$expected] actual=[$actual]" }
}

Write-Host 'test-draft.ps1 — exercises Sti-DraftPath/Find/Save/Load/Exists/Clear'
Write-Host ''

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "sti-draft-test-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    # --- draft_path: deterministic for a given ts+slug --------------------
    Assert-Equal 'draft_path: <dir>/<ts>-<slug>-draft.md' `
        '.stride/2026-05-12T103000-add-notifications-draft.md' `
        (Sti-DraftPath .stride 2026-05-12T103000 add-notifications)

    Assert-Equal 'draft_path: trailing slash on dir is normalized' `
        '.stride/2026-05-12T103000-foo-draft.md' `
        (Sti-DraftPath .stride/ 2026-05-12T103000 foo)

    $p1 = Sti-DraftPath $tmpDir 2026-05-12T103000 foo
    $p2 = Sti-DraftPath $tmpDir 2026-05-12T103000 foo
    Assert-Equal 'draft_path: deterministic for a given SESSION_TS+slug' $p1 $p2

    $bad = Sti-DraftPath $tmpDir 2026-05-12T103000 '' 2>$null
    if ([string]::IsNullOrEmpty($bad)) { Pass 'draft_path: missing slug -> empty stdout + error' }
    else { Fail 'draft_path: missing slug leaked output' "[$bad]" }

    # --- save then load: round-trips content ------------------------------
    $draft = Sti-DraftPath (Join-Path $tmpDir '.stride') 2026-05-12T103000 round-trip
    $content = "## Goal`nShip the digest.`n`n## Problem`nApprovals rot in inboxes.`n__round_state__: 2"

    Sti-DraftSave $draft $content 2>$null
    if ($LASTEXITCODE -eq 0) { Pass 'draft_save: writes the scratch file (and creates .stride/ parent)' }
    else { Fail 'draft_save: failed to write' "rc=$LASTEXITCODE" }

    if (Test-Path -LiteralPath $draft) { Pass 'draft_save: scratch file exists at the computed path' }
    else { Fail 'draft_save: scratch file missing after save' }

    Assert-Equal 'draft_load: round-trips the saved content byte-for-byte' $content (Sti-DraftLoad $draft)

    # --- exists: predicate on non-empty draft -----------------------------
    if (Sti-DraftExists $draft) { Pass 'draft_exists: true for a non-empty draft' }
    else { Fail 'draft_exists: false for a non-empty draft (should be true)' }

    $empty = Sti-DraftPath (Join-Path $tmpDir '.stride') 2026-05-12T103000 empty-draft
    New-Item -ItemType File -Path $empty -Force | Out-Null
    if (Sti-DraftExists $empty) { Fail 'draft_exists: true for an empty draft (should be false)' }
    else { Pass 'draft_exists: false for an empty/zero-length draft (partial -> fresh)' }

    if (Sti-DraftExists (Join-Path $tmpDir '.stride/nope-draft.md')) { Fail 'draft_exists: true for an absent draft (should be false)' }
    else { Pass 'draft_exists: false for an absent draft' }

    # --- load: absent file -> error, no crash -----------------------------
    $loadBad = Sti-DraftLoad (Join-Path $tmpDir '.stride/missing-draft.md') 2>$null
    if ([string]::IsNullOrEmpty($loadBad)) { Pass 'draft_load: absent file -> empty stdout + error (safe, no crash)' }
    else { Fail 'draft_load: absent file leaked output' "[$loadBad]" }

    # --- save: write-failure branch returns non-zero, no crash ------------
    $blocker = Join-Path $tmpDir 'blocker'
    New-Item -ItemType File -Path $blocker -Force | Out-Null
    $blockedDraft = "$blocker/sub/2026-05-12T103000-x-draft.md"
    $saveErr = (Sti-DraftSave $blockedDraft 'body' 2>&1 | Out-String)
    Sti-DraftSave $blockedDraft 'body' 2>$null
    if ($LASTEXITCODE -ne 0) { Pass 'draft_save: returns non-zero when the parent dir cannot be created (no crash)' }
    else { Fail 'draft_save: succeeded despite an unmakeable parent dir (should fail)' }
    if ($saveErr -match 'cannot write scratch draft') { Pass 'draft_save: write failure emits a diagnostic to stderr' }
    else { Fail 'draft_save: write failure produced no diagnostic' "[$saveErr]" }

    # --- clear: removes the scratch file (idempotent) ---------------------
    Sti-DraftClear $draft
    if (Test-Path -LiteralPath $draft) { Fail 'draft_clear: scratch file still present after clear' }
    else { Pass 'draft_clear: removes the scratch file' }
    Sti-DraftClear $draft
    if ($LASTEXITCODE -eq 0) { Pass 'draft_clear: idempotent (no error when already gone)' }
    else { Fail 'draft_clear: errored on an already-absent file' "rc=$LASTEXITCODE" }

    # --- find: resume detection matches only the same slug ----------------
    $fdir = Join-Path $tmpDir 'find-stride'
    New-Item -ItemType Directory -Path $fdir | Out-Null
    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T100000 alpha) 'alpha draft body' 2>$null
    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T110000 beta)  'beta draft body'  2>$null
    New-Item -ItemType File -Path (Sti-DraftPath $fdir 2026-05-12T120000 gamma) -Force | Out-Null  # empty -> ignored

    Assert-Equal 'draft_find: returns the matching-slug draft only (two slugs in flight)' `
        "$fdir/2026-05-12T100000-alpha-draft.md" `
        (Sti-DraftFind $fdir alpha)

    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T130000 oauth) 'oauth body' 2>$null
    $noauth = Sti-DraftFind $fdir auth 2>$null
    if ([string]::IsNullOrEmpty($noauth)) { Pass "draft_find: slug 'auth' does not match 'oauth' (dash-delimited suffix)" }
    else { Fail 'draft_find: auth cross-matched a different slug' "[$noauth]" }

    $none = Sti-DraftFind $fdir does-not-exist 2>$null
    if ([string]::IsNullOrEmpty($none)) { Pass 'draft_find: no matching draft -> empty stdout + non-zero (fresh session)' }
    else { Fail 'draft_find: leaked output for a slug with no draft' "[$none]" }

    $emptyOnly = Sti-DraftFind $fdir gamma 2>$null
    if ([string]::IsNullOrEmpty($emptyOnly)) { Pass 'draft_find: an empty-only draft is not offered for resume (partial -> fresh)' }
    else { Fail 'draft_find: offered an empty draft for resume' "[$emptyOnly]" }

    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T090000 multi) 'older' 2>$null
    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T140000 multi) 'newer' 2>$null
    Assert-Equal 'draft_find: latest ISO timestamp wins for a repeated slug' `
        "$fdir/2026-05-12T140000-multi-draft.md" `
        (Sti-DraftFind $fdir multi)

    $abs = Sti-DraftFind (Join-Path $tmpDir 'no-such-dir') anything 2>$null
    if ([string]::IsNullOrEmpty($abs)) { Pass 'draft_find: absent scratch dir -> empty stdout + non-zero (no crash)' }
    else { Fail 'draft_find: leaked output for an absent dir' "[$abs]" }

    # --- exact-slug discovery (D339) ---------------------------------------
    $xdir = Join-Path $tmpDir 'exact'
    Sti-DraftSave (Sti-DraftPath $xdir 2026-05-12T120000 dark-mode-toggle) 'dark mode' 2>$null
    $x = Sti-DraftFind $xdir toggle 2>$null
    if ([string]::IsNullOrEmpty($x)) { Pass "draft_find: slug 'toggle' does not match a 'dark-mode-toggle' draft" }
    else { Fail "draft_find: slug 'toggle' matched another topic's draft" "[$x]" }
    Assert-Equal "draft_find: 'dark-mode-toggle' still finds its own draft" `
        "$xdir/2026-05-12T120000-dark-mode-toggle-draft.md" (Sti-DraftFind $xdir dark-mode-toggle)
    Sti-DraftSave (Sti-DraftPath $xdir 2026-05-12T110000 toggle) 'toggle' 2>$null
    Assert-Equal "draft_find: 'toggle' finds its own draft even when a longer slug's draft is newer" `
        "$xdir/2026-05-12T110000-toggle-draft.md" (Sti-DraftFind $xdir toggle)
    [System.IO.File]::WriteAllText((Join-Path $xdir 'notes-toggle-draft.md'), 'x')
    [System.IO.File]::WriteAllText((Join-Path $xdir '2026-05-12-toggle-draft.md'), 'x')
    Assert-Equal 'draft_find: a name without the YYYY-MM-DDTHHMMSS timestamp shape is never a candidate' `
        "$xdir/2026-05-12T110000-toggle-draft.md" (Sti-DraftFind $xdir toggle)

    # --- content piped in (D339) -------------------------------------------
    $sdir = Join-Path (Join-Path $tmpDir 'stdin') '.stride'
    $sp = Sti-DraftPath $sdir 2026-05-12T103000 tricky
    $tricky = "He said `"it's `$HOME, ``whoami`` and `$(id)`" \ done`n`nline 3`n"
    $tricky | Sti-DraftSave $sp 2>$null
    Assert-Equal 'draft_save: piped content (quotes, $, backticks, $(...)) round-trips verbatim' $tricky ([System.IO.File]::ReadAllText($sp))
    Sti-DraftSave $sp 'argv content' 2>$null
    Assert-Equal 'draft_save: the argument form still works' 'argv content' ([System.IO.File]::ReadAllText($sp))
    'stdin wins?' | Sti-DraftSave $sp 'argv content 2' 2>$null
    Assert-Equal 'draft_save: with both an argument and piped content, the argument wins (as in bash)' 'argv content 2' ([System.IO.File]::ReadAllText($sp))
    @() | Sti-DraftSave $sp 2>$null
    if ((Test-Path -LiteralPath $sp) -and (Get-Item -LiteralPath $sp).Length -eq 0 -and [string]::IsNullOrEmpty((Sti-DraftFind $sdir tricky 2>$null))) {
        Pass 'draft_save: an empty pipeline writes an empty draft, which is never offered for resume'
    } else { Fail 'draft_save: empty pipeline mishandled' }
    Sti-DraftSave $sp 2>$null
    if ($LASTEXITCODE -ne 0) { Pass 'draft_save: no content and no pipeline is a usage error' }
    else { Fail 'draft_save: no content and no pipeline did not fail' }

    # --- the scratch dir ignores itself (D339) -------------------------------
    Assert-Equal "draft_dir: creating the scratch dir writes .stride/.gitignore holding '*'" "*`n" ([System.IO.File]::ReadAllText((Join-Path $sdir '.gitignore')))
    [System.IO.File]::WriteAllText((Join-Path $sdir '.gitignore'), "# mine`nkeep-this`n")
    Sti-DraftSave $sp 'again' 2>$null
    Assert-Equal 'draft_dir: an existing .gitignore is never overwritten' "# mine`nkeep-this`n" ([System.IO.File]::ReadAllText((Join-Path $sdir '.gitignore')))
    $notes = Join-Path $tmpDir 'existing-notes'
    New-Item -ItemType Directory -Path $notes | Out-Null
    Sti-DraftSave (Join-Path $notes '2026-05-12T103000-x-draft.md') 'x' 2>$null
    if (-not (Test-Path -LiteralPath (Join-Path $notes '.gitignore'))) { Pass 'draft_dir: no .gitignore is dropped into some other pre-existing directory' }
    else { Fail 'draft_dir: wrote a .gitignore into a pre-existing non-scratch directory' }
    $pre = Join-Path (Join-Path $tmpDir 'pre') '.stride'
    New-Item -ItemType Directory -Path $pre -Force | Out-Null
    Sti-DraftDir $pre
    Assert-Equal 'draft_dir: a pre-existing .stride dir without one gets the .gitignore' "*`n" ([System.IO.File]::ReadAllText((Join-Path $pre '.gitignore')))

    $repo = Join-Path $tmpDir 'repo'
    New-Item -ItemType Directory -Path $repo | Out-Null
    & git -C $repo init -q
    Push-Location $repo
    try { Sti-DraftSave (Sti-DraftPath .stride 2026-05-12T103000 secret-plan) 'half-finished, possibly sensitive' 2>$null } finally { Pop-Location }
    $status = (& git -C $repo status --porcelain) -join ' '
    if ([string]::IsNullOrEmpty($status)) { Pass 'draft_save: in a fresh git repo, git status shows nothing under .stride/ after a save' }
    else { Fail 'draft_save: the draft is visible to git' $status }
    & git -C $repo add -A 2>$null
    $staged = (& git -C $repo diff --cached --name-only) -join ' '
    if ([string]::IsNullOrEmpty($staged)) { Pass 'draft_save: a later git add -A stages nothing from .stride/' }
    else { Fail 'draft_save: git add -A staged the draft' $staged }

    # --- links and an existing .gitignore that does not cover drafts (D339) --
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        Write-Host '  SKIP  symlink cases need POSIX ln (Windows symlinks require elevation)'
    } else {
        $ldir = Join-Path (Join-Path $tmpDir 'links') '.stride'
        New-Item -ItemType Directory -Path $ldir -Force | Out-Null
        $secret = Join-Path (Join-Path $tmpDir 'links') 'secret'
        [System.IO.File]::WriteAllText($secret, "credentials`n")
        & ln -s $secret (Join-Path $ldir '2026-05-12T120000-auth-draft.md')
        $l = Sti-DraftFind $ldir auth 2>$null
        if ([string]::IsNullOrEmpty($l)) { Pass 'draft_find: a symbolic link is never offered as a draft' } else { Fail 'draft_find: offered a symlink for resume' "[$l]" }
        Sti-DraftSave (Join-Path $ldir '2026-05-12T120000-auth-draft.md') 'overwrite' 2>$null
        Assert-Equal 'draft_save: refuses a symlinked draft path and leaves its target alone' "credentials`n" ([System.IO.File]::ReadAllText($secret))
        $docs = Join-Path (Join-Path $tmpDir 'links') 'docs'
        New-Item -ItemType Directory -Path $docs | Out-Null
        & ln -s $docs (Join-Path (Join-Path $tmpDir 'links') 'linked-stride')
        Sti-DraftDir (Join-Path (Join-Path $tmpDir 'links') 'linked-stride') 2>$null
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $docs '.gitignore'))) { Pass 'draft_dir: a symlinked scratch dir is refused and nothing is written at its target' }
        else { Fail 'draft_dir: wrote through a symlinked dir' }
    }

    $grepo = Join-Path $tmpDir 'gitrepo'
    New-Item -ItemType Directory -Path (Join-Path $grepo '.stride') -Force | Out-Null
    & git -C $grepo init -q
    [System.IO.File]::WriteAllText((Join-Path $grepo '.stride/.gitignore'), "*.json`n")
    Sti-DraftDir (Join-Path $grepo '.stride') 2>$null
    if ($LASTEXITCODE -eq 2 -and [System.IO.File]::ReadAllText((Join-Path $grepo '.stride/.gitignore')) -eq "*.json`n") { Pass 'draft_dir: an existing .gitignore that does not cover drafts returns 2 and is left untouched' }
    else { Fail 'draft_dir: uncovered drafts not reported' "rc=$LASTEXITCODE" }
    [System.IO.File]::WriteAllText((Join-Path $grepo '.stride/.gitignore'), "*`n")
    Sti-DraftDir (Join-Path $grepo '.stride') 2>$null
    if ($LASTEXITCODE -eq 0) { Pass 'draft_dir: once the .gitignore covers drafts it succeeds' } else { Fail 'draft_dir: failed although drafts are ignored' }
    & git -C $grepo config user.email t@example.com
    & git -C $grepo config user.name t
    [System.IO.File]::WriteAllText((Join-Path $grepo '.stride/2026-05-12T120000-plan-draft.md'), "committed prose`n")
    & git -C $grepo add -f .stride/2026-05-12T120000-plan-draft.md
    & git -C $grepo commit -q -m tracked
    $t = Sti-DraftFind (Join-Path $grepo '.stride') plan 2>$null
    if ([string]::IsNullOrEmpty($t)) { Pass 'draft_find: a draft git already tracks is never offered for resume' } else { Fail 'draft_find: offered a tracked draft' "[$t]" }
    New-Item -ItemType Directory -Path (Join-Path $grepo 'sub') -Force | Out-Null
    Push-Location (Join-Path $grepo 'sub')
    try { Sti-DraftSave '2026-05-12T120000-bare-draft.md' 'x' 2>$null } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $grepo 'sub/2026-05-12T120000-bare-draft.md'))) { Pass 'draft_save: a bare file name in an un-ignored repo directory is refused, not written' }
    else { Fail 'draft_save: wrote the bare-name draft' "rc=$LASTEXITCODE" }
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
