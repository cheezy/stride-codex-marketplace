# PowerShell mirror of test-filename.sh — smoke tests for filename.ps1
# cmdlets. Verifies the same slugify rules + unique-path collision logic
# the bash version covers, against the same inputs.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'filename.ps1')

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

Write-Host 'test-filename.ps1 — Sti-Slugify + Sti-UniquePath + Sti-SlugFromPath'
Write-Host ''

# --- Sti-Slugify rules -----------------------------------------------------

Assert-Equal "slugify lowercases" "add-notifications" (Sti-Slugify -InputText "Add Notifications")
Assert-Equal "slugify dash-separates" "dark-mode-toggle" (Sti-Slugify -InputText "Dark mode toggle")
Assert-Equal "slugify collapses runs" "foo-bar"           (Sti-Slugify -InputText "foo   bar")
Assert-Equal "slugify trims leading" "abc"                (Sti-Slugify -InputText "---abc")
Assert-Equal "slugify trims trailing" "abc"               (Sti-Slugify -InputText "abc---")
Assert-Equal "slugify replaces punct" "what-the-heck"     (Sti-Slugify -InputText "what?the/heck!")
Assert-Equal "slugify preserves digits" "v0-1-prerelease" (Sti-Slugify -InputText "v0.1 prerelease")
# The bash suite's own slugify inputs, one for one.
Assert-Equal "slugify lowercases and dash-separates words" "add-notifications" (Sti-Slugify -InputText 'Add Notifications')
Assert-Equal "slugify collapses runs of dashes" "foo-bar-baz" (Sti-Slugify -InputText 'foo   bar---baz')
Assert-Equal "slugify trims leading and trailing dashes" "hello-world" (Sti-Slugify -InputText '---Hello World---')
Assert-Equal "slugify replaces non-alphanumerics with dashes (not deleted)" "add-push-notifications" (Sti-Slugify -InputText 'Add Push! Notifications?')
Assert-Equal "slugify preserves numbers" "oauth2-login" (Sti-Slugify -InputText 'oauth2 login')

# Empty / whitespace-only input should error (returns $null + writes Error).
$emptyOut = Sti-Slugify -InputText '' -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($emptyOut)) { Pass "slugify empty input returns null/empty" } else { Fail "slugify empty input should fail" }

$wsOut = Sti-Slugify -InputText '   ' -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($wsOut)) { Pass "slugify whitespace-only returns null/empty" } else { Fail "slugify whitespace-only should fail" }

# --- Sti-UniquePath collision discriminator -------------------------------

$tmpDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "sti-test-$(Get-Random)") -Force
try {
    $p1 = Sti-UniquePath -Dir $tmpDir.FullName -Timestamp '2026-05-12T103000' -Slug 'add-notifications' -Artifact 'requirements' -Extension 'md'
    Assert-Equal "fresh timestamp produces base name" "$($tmpDir.FullName)/2026-05-12T103000-add-notifications-requirements.md" $p1

    # Create the file at $p1 so the next call discriminates.
    New-Item -ItemType File -Path $p1 -Force | Out-Null
    $p2 = Sti-UniquePath -Dir $tmpDir.FullName -Timestamp '2026-05-12T103000' -Slug 'add-notifications' -Artifact 'requirements' -Extension 'md'
    Assert-Equal "collision produces -2 suffix" "$($tmpDir.FullName)/2026-05-12T103000-add-notifications-requirements-2.md" $p2

    New-Item -ItemType File -Path $p2 -Force | Out-Null
    $p3 = Sti-UniquePath -Dir $tmpDir.FullName -Timestamp '2026-05-12T103000' -Slug 'add-notifications' -Artifact 'requirements' -Extension 'md'
    Assert-Equal "double collision produces -3 suffix" "$($tmpDir.FullName)/2026-05-12T103000-add-notifications-requirements-3.md" $p3

    # Hard invariant: the helper must never return a path that already exists.
    New-Item -ItemType File -Path $p3 -Force | Out-Null
    $next = Sti-UniquePath -Dir $tmpDir.FullName -Timestamp '2026-05-12T103000' -Slug 'add-notifications' -Artifact 'requirements' -Extension 'md'
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($next) -and -not (Test-Path -LiteralPath $next)) {
        Pass "HARD INVARIANT: returned path does not exist ($(Split-Path -Leaf $next))"
    } else {
        Fail "HARD INVARIANT: returned an existing path: $next" "rc=$LASTEXITCODE"
    }

    # Sti-Slugify + Sti-UniquePath together produce the normalized slug from a
    # noisy human-typed input, for the stride-batch/json artifact.
    $slugFromHuman = Sti-Slugify -InputText 'Add Notifications'
    Assert-Equal "slug with spaces normalizes correctly through unique_path" `
        "$($tmpDir.FullName)/2026-05-12T110000-add-notifications-stride-batch.json" `
        (Sti-UniquePath -Dir $tmpDir.FullName -Timestamp '2026-05-12T110000' -Slug $slugFromHuman -Artifact 'stride-batch' -Extension 'json')
} finally {
    Remove-Item -Recurse -Force $tmpDir.FullName -ErrorAction SilentlyContinue
}

# --- Sti-SlugFromPath inverse ---------------------------------------------

Assert-Equal "slug_from_path: simple requirements artifact" "add-notifications" `
    (Sti-SlugFromPath -Path 'docs/ideation/2026-05-12T103000-add-notifications-requirements.md' -Artifact 'requirements')
Assert-Equal "slug_from_path with -N suffix" "add-notifications" `
    (Sti-SlugFromPath -Path 'docs/ideation/2026-05-12T103000-add-notifications-requirements-3.md' -Artifact 'requirements')
Assert-Equal "slug_from_path: multi-word artifact (stride-batch)" "add-notifications" `
    (Sti-SlugFromPath -Path '2026-05-12T103000-add-notifications-stride-batch.json' -Artifact 'stride-batch')

Assert-Equal "slug_from_path: works without a directory prefix" "add-notifications" `
    (Sti-SlugFromPath -Path '2026-05-12T103000-add-notifications-requirements.md' -Artifact 'requirements')
Assert-Equal "slug_from_path: strips a -2 collision discriminator" "add-notifications" `
    (Sti-SlugFromPath -Path '2026-05-12T103000-add-notifications-requirements-2.md' -Artifact 'requirements')
Assert-Equal "slug_from_path: strips a -10 collision discriminator" "add-notifications" `
    (Sti-SlugFromPath -Path '2026-05-12T103000-add-notifications-requirements-10.md' -Artifact 'requirements')
Assert-Equal "slug_from_path: preserves trailing slug digits when artifact follows them" "oauth2-login" `
    (Sti-SlugFromPath -Path '2026-05-12T103000-oauth2-login-requirements.md' -Artifact 'requirements')
Assert-Equal "slug_from_path: multi-word artifact with collision discriminator" "add-notifications" `
    (Sti-SlugFromPath -Path '2026-05-12T103000-add-notifications-stride-batch-3.json' -Artifact 'stride-batch')

# Path that doesn't match the family should error.
$badPath = Sti-SlugFromPath -Path 'random.md' -Artifact 'requirements' -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($badPath)) { Pass "slug_from_path rejects non-family paths" } else { Fail "slug_from_path should reject non-family paths" "got=[$badPath]" }

# The bash suite's malformed input: no output, and the failure is signalled
# (Sti-SlugFromPath reports it as an error record, its non-zero-exit analogue).
$badErr = $null
$badOut = Sti-SlugFromPath -Path 'not-a-timestamped-filename.md' -Artifact 'requirements' -ErrorAction SilentlyContinue -ErrorVariable badErr
if ([string]::IsNullOrEmpty($badOut) -and @($badErr).Count -gt 0) {
    Pass "slug_from_path: malformed path produces empty stdout (non-zero exit)"
} else {
    Fail "slug_from_path: malformed path leaked output: $badOut" "errors=$(@($badErr).Count)"
}

# --- summary ---------------------------------------------------------------

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
