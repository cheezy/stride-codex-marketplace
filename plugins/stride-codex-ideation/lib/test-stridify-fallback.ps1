# PowerShell twin of test-stridify-fallback.sh -- tests for the
# stride-ideation-stridify Step 7.5 retry-exhaustion fallback documented in
# skills/stride-ideation-stridify/SKILL.md. The agent run is only available
# inside a live Codex session, so this suite embeds a PowerShell REFERENCE
# implementation of the documented retry loop + fallback (mirroring the bash
# reference in test-stridify-fallback.sh) and drives it with a mock agent
# scriptblock that always fails.
#
# The reference implementation below MUST stay consistent with SKILL.md
# Step 7.5 (7.5b file layout, 7.5c terminal summary) AND with the bash twin.
# If you edit one, edit all three.
#
# This file is ASCII-only: the em dash the SKILL headings use is written as
# [char]0x2014.
#
# Run:
#   pwsh -NoProfile -File lib/test-stridify-fallback.ps1

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'filename.ps1')
$SkillMd = Join-Path $ScriptDir '../skills/stride-ideation-stridify/SKILL.md'

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

$EmDash = [string][char]0x2014
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

Write-Host 'test-stridify-fallback.ps1 -- Step 7.5 retry-exhaustion fallback'
Write-Host ''

$tmpDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "sti-fallback-$(Get-Random)") -Force
$TMP = $tmpDir.FullName.TrimEnd([char]'/', [char]'\')
$script:FallbackSentinel = Join-Path $TMP 'sentinel'
$script:PostSentinel = Join-Path $TMP 'post_was_attempted'

# --- mock agents -------------------------------------------------------------
# A mock returns @{ ok; out; err }: ok=$false is a failed run whose error
# text is err (the bash mock's stderr); ok=$true is a successful run.

$MockAlwaysFail = {
    @{ ok = $false; out = ''; err = ('Error: HTTP 529 Overloaded ' + [string][char]0x2014 + ' Anthropic API capacity') }
}
$MockAlwaysSucceed = {
    @{ ok = $true; out = ('```json' + "`n" + '{"goals":[{"title":"G1","type":"goal","tasks":[]}]}' + "`n" + '```'); err = '' }
}

# --- reference fallback implementation --------------------------------------
#
# Mirrors SKILL.md Step 7.5 a/b/c. GoalMeta is either the literal string
# "(no --goal)" or "<name>|<index>|<slug>". Returns @{ rc; path; stderr }
# where stderr is the terminal-summary text the bash reference prints to
# stderr. Side effect: writes the saved-prompt markdown file next to the
# source path. The real implementation exits 1; the test wants control back,
# so it returns rc=99 (mirrors the bash `return 99`).

function Invoke-Step75SavePromptAndExit {
    param(
        [string]$Prompt, [string]$LastErr,
        [string]$SourcePath, [string]$SourceSha, [string]$SourceTs,
        [string]$SlugForPath, [string]$TargetBatchPath, [string]$GoalMeta
    )
    $sourceDir = Split-Path -Parent $SourcePath
    $promptPath = Sti-UniquePath -Dir $sourceDir -Timestamp $SourceTs -Slug $SlugForPath `
                                 -Artifact 'decomposer-prompt' -Extension 'md'

    if ($GoalMeta -ceq '(no --goal)') {
        $scopeLine = 'all goals (no --goal flag)'
    } else {
        $parts = $GoalMeta.Split('|')
        $scopeLine = "$($parts[0]) (index $($parts[1]), slug $($parts[2]))"
    }
    $savedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HHmmss'Z'")

    # Body layout, headings and wording mirror SKILL.md Step 7.5b verbatim.
    # <BATCH_TARGET_PATH> and <TARGET_PATH> are both the Step 5 target path.
    $t = $TargetBatchPath
    $lines = @(
        "# Decomposer Prompt $EmDash Saved After Retry Exhaustion"
        ''
        "- **Saved at:** $savedAt"
        "- **Source requirements doc:** $SourcePath"
        "- **Source SHA-256:** $SourceSha"
        "- **Per-goal scope:** $scopeLine"
        '- **Attempts before exhaustion:** 3'
        ''
        '## Last error from agent'
        ''
        $LastErr
        ''
        "## Agent prompt (literal $EmDash paste this into a fresh session)"
        ''
        '````'
        $Prompt
        '````'
        ''
        '## Recovery instructions'
        ''
        "Paste the prompt block above into a fresh session $EmDash any model capable"
        'of following the requirements-decomposer contract works (`agents/requirements-decomposer.md`'
        'documents the contract). The session does NOT need codebase access. Save the'
        ('resulting fenced ```json block as `' + $t + '` (the target path')
        'computed by Step 5; for the run that produced this file, that path was'
        ('`' + $t + '`). Then activate the stride-ideation-stridify skill with:')
        ''
        ('    --batch "' + $t + '"')
        ''
        "which checks the JSON against the validator's six named fatal checks"
        '(parse_error / wrong_root_key / empty_goals / goal_missing_field /'
        'bad_dependency_index / length_limit; advisory scored-field warnings on'
        'stderr do not block) and screens it for the API token, previews the goals'
        'and tasks, asks for approval, and ships it through `lib/ship.py`, which'
        'strips the audit fields, POSTs the result and renders the created'
        'identifiers in one process. Never hand-write an authenticated curl for it.'
        ''
        'This sibling file contains NO authentication material. The Stride API token'
        'never enters the decomposer prompt (the agent has no API access), so there'
        'is no token in the saved prompt or the recovery README.'
    )
    $body = ($lines -join "`n") + "`n"

    try {
        [System.IO.File]::WriteAllText($promptPath, $body, $Utf8NoBom)
    } catch {
        # Per Step 7.5c pitfall: surface the prompt if the write fails.
        $err = @(
            "stride-ideation: failed to write saved-prompt file:"
            $_.Exception.Message
            '--- in-memory prompt ---'
            $Prompt
            '--- last error ---'
            $LastErr
        ) -join "`n"
        return @{ rc = 1; path = $promptPath; stderr = $err }
    }

    # Terminal summary mirrors SKILL.md Step 7.5c verbatim.
    $firstErrLine = ($LastErr -split "`n")[0]
    $summary = @(
        'stride-ideation: retries exhausted (3/3 transient failures).'
        "Saved decomposer prompt to: $promptPath"
        'Last error from the final attempt:'
        "  $firstErrLine"
        ''
        'To recover: paste the prompt block from that file into a fresh session;'
        "save the JSON response as $t; then activate"
        ('stride-ideation-stridify with `--batch "' + $t + '"` to validate,')
        'preview and ship it.'
        ''
        'The Stride API POST was NOT attempted.'
    ) -join "`n"
    return @{ rc = 99; path = $promptPath; stderr = $summary }
}

# --- reference retry loop ----------------------------------------------------
# Cases 1-8 always fail through to the fallback; case 9 is the success control
# proving the POST sentinel is live.

function Invoke-StubPost {
    Set-Content -LiteralPath $script:PostSentinel -Value 'POST_REACHED' -Encoding ascii
}

function Test-PostWasAttempted { Test-Path -LiteralPath $script:PostSentinel }

function Invoke-DispatchAndFallback {
    param(
        [scriptblock]$Mock, [string]$Prompt,
        [string]$SourcePath, [string]$SourceSha, [string]$SourceTs,
        [string]$SlugForPath, [string]$TargetBatchPath, [string]$GoalMeta
    )
    $attempt = 1; $max = 3; $lastErr = ''
    while ($attempt -le $max) {
        $r = & $Mock
        if ($r.ok) {
            # Success path (case 9 control only): the real skill would continue
            # to Step 8 and the Step 9 POST; the stub records a POST was reached.
            Invoke-StubPost
            return @{ rc = 0; path = ''; stderr = '' }
        }
        $lastErr = $r.err
        $attempt++
    }
    # Sentinel: track that fallback was reached (and POST was NOT).
    Set-Content -LiteralPath $script:FallbackSentinel -Value 'FALLBACK_REACHED' -Encoding ascii
    return Invoke-Step75SavePromptAndExit -Prompt $Prompt -LastErr $lastErr `
        -SourcePath $SourcePath -SourceSha $SourceSha -SourceTs $SourceTs `
        -SlugForPath $SlugForPath -TargetBatchPath $TargetBatchPath -GoalMeta $GoalMeta
}

function Get-FileText($p) { [System.IO.File]::ReadAllText($p) }

try {
    # === fixtures =============================================================
    $SourcePath = "$TMP/2026-05-15T210800-review-queue-code-diffs-requirements.md"
    $fixture = @(
        '# Review Queue Code Diffs'
        ''
        '## Problem'
        'Some problem text.'
        ''
        '## Decomposition seams'
        ''
        "1. **Kanban app** $EmDash first surface."
        "2. **stride plugin** $EmDash second surface."
    ) -join "`n"
    [System.IO.File]::WriteAllText($SourcePath, $fixture + "`n", $Utf8NoBom)
    $SourceSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash.ToLowerInvariant()
    $SourceTs = '2026-05-15T210800'
    $TargetBatch = "$TMP/2026-05-15T210800-review-queue-code-diffs-stride-batch.json"
    $PromptBody = @(
        'Requirements document:'
        ''
        '```'
        '# Review Queue Code Diffs (full doc text would be here)'
        '```'
    ) -join "`n"

    # === case 1: fallback writes a file at the expected path ==================
    $run1 = Invoke-DispatchAndFallback -Mock $MockAlwaysFail -Prompt $PromptBody `
        -SourcePath $SourcePath -SourceSha $SourceSha -SourceTs $SourceTs `
        -SlugForPath 'review-queue-code-diffs' -TargetBatchPath $TargetBatch -GoalMeta '(no --goal)'
    $expectedPath = "$TMP/2026-05-15T210800-review-queue-code-diffs-decomposer-prompt.md"
    if (Test-Path -LiteralPath $expectedPath -PathType Leaf) {
        Pass 'case 1: fallback writes sibling file at expected path'
    } else {
        Fail 'case 1: expected file missing' "expected=$expectedPath actual=$($run1.path)"
    }
    if ((Test-Path -LiteralPath $script:FallbackSentinel) -and
        ((Get-FileText $script:FallbackSentinel) -cmatch 'FALLBACK_REACHED')) {
        Pass 'case 1: fallback branch was reached (sentinel set)'
    } else {
        Fail 'case 1: sentinel not set -- fallback path not taken'
    }
    if ($run1.rc -ne 0) {
        Pass 'case 1: fallback returns non-zero (never continues to Step 8)'
    } else {
        Fail 'case 1: fallback returned 0' "rc=$($run1.rc)"
    }

    # === case 2: file contains all required sections ==========================
    if (Test-Path -LiteralPath $expectedPath -PathType Leaf) {
        $text1 = Get-FileText $expectedPath
        $requiredSections = @(
            "# Decomposer Prompt $EmDash Saved After Retry Exhaustion"
            'Saved at'
            'Source requirements doc'
            'Source SHA-256'
            'Per-goal scope'
            'Attempts before exhaustion'
            '## Last error from agent'
            "## Agent prompt (literal $EmDash paste this into a fresh session)"
            '## Recovery instructions'
        )
        $missing = @($requiredSections | Where-Object { -not $text1.Contains($_) })
        if ($missing.Count -eq 0) {
            Pass 'case 2: file contains all required sections'
        } else {
            Fail 'case 2: missing sections:' ($missing -join ' | ')
        }

        # Drift guard: every required literal must also appear in SKILL.md 7.5b.
        $skillText = Get-FileText $SkillMd
        $skillMissing = @($requiredSections | Where-Object { -not $skillText.Contains($_) })
        if ($skillMissing.Count -eq 0) {
            Pass 'case 2: every required section literal matches SKILL.md Step 7.5b'
        } else {
            Fail 'case 2: required section literals drifted from SKILL.md:' ($skillMissing -join ' | ')
        }

        if ($text1.Contains($SourceSha)) { Pass 'case 2: file includes source SHA-256' }
        else { Fail 'case 2: file missing source SHA-256' }

        if ($text1.Contains('HTTP 529 Overloaded')) { Pass 'case 2: file includes last error verbatim' }
        else { Fail 'case 2: file missing last error verbatim' }

        if ($text1.Contains('Requirements document:')) { Pass 'case 2: file includes literal prompt body' }
        else { Fail 'case 2: file missing literal prompt body' }
    } else {
        Fail 'case 2: no saved file to inspect' "expected=$expectedPath"
    }

    # === case 3: POST is NOT attempted in fallback branch =====================
    if (Test-PostWasAttempted) {
        Fail 'case 3: POST was attempted despite fallback (regression)'
    } else {
        Pass 'case 3: POST is NOT attempted in fallback branch'
    }

    # === case 4: re-invocation produces -2 sibling (no overwrite) =============
    # Snapshot the first file's bytes BEFORE the second invocation.
    $firstBefore = [System.IO.File]::ReadAllBytes($expectedPath)
    $null = Invoke-DispatchAndFallback -Mock $MockAlwaysFail -Prompt $PromptBody `
        -SourcePath $SourcePath -SourceSha $SourceSha -SourceTs $SourceTs `
        -SlugForPath 'review-queue-code-diffs' -TargetBatchPath $TargetBatch -GoalMeta '(no --goal)'
    $secondPath = "$TMP/2026-05-15T210800-review-queue-code-diffs-decomposer-prompt-2.md"
    if (Test-Path -LiteralPath $secondPath -PathType Leaf) {
        Pass 'case 4: second invocation writes -2 sibling without overwriting'
    } else {
        Fail 'case 4: -2 sibling not created' "expected=$secondPath"
    }
    $firstAfter = if (Test-Path -LiteralPath $expectedPath) { [System.IO.File]::ReadAllBytes($expectedPath) } else { $null }
    if ($null -ne $firstAfter -and
        [System.Linq.Enumerable]::SequenceEqual([byte[]]$firstBefore, [byte[]]$firstAfter)) {
        Pass 'case 4: first file is unchanged by the second invocation'
    } else {
        Fail 'case 4: first file was modified or removed by the second invocation'
    }

    # === case 5: --goal scope reflected in saved file =========================
    $null = Invoke-DispatchAndFallback -Mock $MockAlwaysFail -Prompt "$PromptBody (scoped to Kanban app)" `
        -SourcePath $SourcePath -SourceSha $SourceSha -SourceTs $SourceTs `
        -SlugForPath 'review-queue-code-diffs-kanban-app' -TargetBatchPath $TargetBatch -GoalMeta 'Kanban app|1|kanban-app'
    $goalPath = "$TMP/2026-05-15T210800-review-queue-code-diffs-kanban-app-decomposer-prompt.md"
    if (Test-Path -LiteralPath $goalPath -PathType Leaf) {
        Pass 'case 5: per-goal fallback writes file with goal slug in filename'
        $goalText = Get-FileText $goalPath
    } else {
        Fail 'case 5: per-goal fallback path missing' "expected=$goalPath"
        $goalText = ''
    }
    if ($goalText.Contains('Kanban app (index 1, slug kanban-app)')) {
        Pass 'case 5: saved file reflects per-goal scope metadata'
    } else {
        $scope = @($goalText -split "`n" | Where-Object { $_ -match 'Per-goal scope' })
        Fail 'case 5: per-goal scope line missing or wrong' $(if ($scope.Count) { $scope[0] } else { '(no scope line)' })
    }
    if ($goalText.Contains('(scoped to Kanban app)')) {
        Pass 'case 5: saved file reflects scoped prompt body (not full doc)'
    } else {
        Fail 'case 5: scoped prompt body not in saved file'
    }

    # === case 6: recovery summary (the bash reference's stderr) ===============
    if ($run1.stderr.Contains('Saved decomposer prompt to:')) {
        Pass 'case 6: terminal summary names the saved-prompt path'
    } else {
        Fail "case 6: terminal summary missing 'Saved decomposer prompt to:' line"
    }
    if ($run1.stderr.Contains('The Stride API POST was NOT attempted')) {
        Pass 'case 6: terminal summary explicitly states POST was not attempted'
    } else {
        Fail "case 6: terminal summary missing 'POST NOT attempted' line"
    }
    if ($run1.stderr.Contains('Last error from the final attempt:') -and
        $run1.stderr.Contains('  Error: HTTP 529 Overloaded')) {
        Pass 'case 6: terminal summary surfaces the first line of the last error'
    } else {
        Fail 'case 6: terminal summary missing the last-error line' $run1.stderr
    }

    # === case 7: pitfall -- no token strings in the WRITTEN file ==============
    # Same regex as the bash twin; -cmatch mirrors grep -E's case sensitivity.
    if ((Get-FileText $expectedPath) -cmatch 'stride_(dev|prod)_|Bearer |Authorization:') {
        Fail 'case 7: saved file contains potential auth material (regression)'
    } else {
        Pass 'case 7: saved file contains no Bearer/token/Authorization strings (pitfall avoided)'
    }

    # === case 8: pitfall -- no partial batch JSON written =====================
    $batches = @(Get-ChildItem -LiteralPath $TMP -Recurse -File -Filter '*-stride-batch*.json' -ErrorAction SilentlyContinue)
    if ($batches.Count -gt 0) {
        Fail 'case 8: a stride-batch JSON file was written in the fallback branch (regression)' ($batches[0].FullName)
    } else {
        Pass 'case 8: no partial batch JSON written in fallback branch (pitfall avoided)'
    }

    # === case 9: control -- the POST sentinel is live =========================
    # Without this, case 3 could pass vacuously (a sentinel nothing ever writes).
    $run9 = Invoke-DispatchAndFallback -Mock $MockAlwaysSucceed -Prompt $PromptBody `
        -SourcePath $SourcePath -SourceSha $SourceSha -SourceTs $SourceTs `
        -SlugForPath 'review-queue-code-diffs' -TargetBatchPath $TargetBatch -GoalMeta '(no --goal)'
    if ($run9.rc -eq 0 -and (Test-PostWasAttempted)) {
        Pass ("case 9: control $EmDash success path reaches the POST stub (sentinel is live)")
    } else {
        Fail ("case 9: control $EmDash success path did not reach the POST stub") "rc=$($run9.rc)"
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $TMP -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
