# PowerShell mirror of test-stridify-per-goal.sh — exercises the
# Sti-ResolveGoal, Sti-ExtractSeams, and Sti-ScopeDocToSeam cmdlets that
# the stride-ideation-stridify skill's --goal flow depends on.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'filename.ps1')

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-stridify-per-goal.ps1 — exercises Sti-ResolveGoal + Sti-ExtractSeams + Sti-ScopeDocToSeam'
Write-Host ''

# Build a synthetic requirements doc with a Decomposition seams section.
$tmp = New-TemporaryFile
$docPath = "$($tmp.FullName).md"
Move-Item -LiteralPath $tmp.FullName -Destination $docPath
Set-Content -LiteralPath $docPath -Encoding UTF8 -Value @'
# Test doc

## Goal
A goal.

## Decomposition seams

The surfaces:

1. **Kanban app** — owns the JSON contract for the workflow
2. **stride plugin** — adapter for the Claude reference workflow
3. **stride-copilot** — adapter for GitHub Copilot

Shared notes:
- All three surfaces ship independently
- Coordination via SemVer

## Other section
Unaffected.
'@

try {
    # Stage 1: Sti-ExtractSeams emits 3 tuples in order.
    $seams = @(Sti-ExtractSeams -Path $docPath)
    if ($LASTEXITCODE -eq 0 -and $seams.Count -eq 3) {
        Pass "Sti-ExtractSeams emits 3 tuples"
    } else {
        Fail "Sti-ExtractSeams unexpected count" "rc=$LASTEXITCODE count=$($seams.Count)"
    }

    if ($seams.Count -ge 1 -and ($seams[0] -split "`t")[0] -eq '1') { Pass "first tuple has index 1" } else { Fail "first tuple index wrong" }
    if ($seams.Count -ge 1 -and ($seams[0] -split "`t")[2] -ceq 'kanban-app') { Pass "first tuple slug is 'kanban-app'" } else { Fail "first tuple slug wrong" "[$($seams[0])]" }
    if ($seams.Count -ge 3 -and ($seams[2] -split "`t")[2] -ceq 'stride-copilot') { Pass "third tuple slug is 'stride-copilot'" } else { Fail "third tuple slug wrong" }

    # Stage 2: Sti-ResolveGoal with digit input resolves by index.
    $r = Sti-ResolveGoal -Path $docPath -GoalArg '2'
    if ($LASTEXITCODE -eq 0 -and ($r -split "`t")[1] -ceq 'stride plugin') {
        Pass "digit '2' resolves to second seam"
    } else {
        Fail "digit resolution failed" "rc=$LASTEXITCODE r=[$r]"
    }

    # Stage 3: Sti-ResolveGoal with slug input resolves by slug.
    $r = Sti-ResolveGoal -Path $docPath -GoalArg 'stride-copilot'
    if ($LASTEXITCODE -eq 0 -and ($r -split "`t")[0] -eq '3') {
        Pass "slug 'stride-copilot' resolves to index 3"
    } else {
        Fail "slug resolution failed" "rc=$LASTEXITCODE r=[$r]"
    }

    # Stage 4: Sti-ResolveGoal with name input (will slugify) resolves.
    $r = Sti-ResolveGoal -Path $docPath -GoalArg 'Kanban app'
    if ($LASTEXITCODE -eq 0 -and ($r -split "`t")[0] -eq '1') {
        Pass "name 'Kanban app' resolves via slugify"
    } else {
        Fail "name slugify resolution failed" "rc=$LASTEXITCODE r=[$r]"
    }

    # Stage 5: No-match returns rc=3.
    $null = Sti-ResolveGoal -Path $docPath -GoalArg 'nonexistent'
    if ($LASTEXITCODE -eq 3) { Pass "no-match returns rc=3" } else { Fail "no-match should return 3" "rc=$LASTEXITCODE" }

    # Stage 6: Sti-ScopeDocToSeam keeps only the matched item in the seams section.
    $scoped = @(Sti-ScopeDocToSeam -Path $docPath -Target 2)
    $scopedText = $scoped -join "`n"
    if ($scopedText -match 'Scoped to a single surface') { Pass "scoped doc has scoped-notice line" } else { Fail "scoped notice missing" }
    if ($scopedText -match 'stride plugin') { Pass "scoped doc retains item 2" } else { Fail "scoped doc dropped target item" }
    # Other items should be absent.
    if ($scopedText -notmatch 'Kanban app' -and $scopedText -notmatch 'stride-copilot') {
        Pass "scoped doc drops non-target items"
    } else {
        Fail "scoped doc retained non-target items"
    }
    # Other sections preserved.
    if ($scopedText -match 'Other section') { Pass "scoped doc preserves other sections" } else { Fail "scoped doc dropped other sections" }

    # Stage 7: doc without Decomposition seams -> Sti-ExtractSeams rc=2.
    $noSeams = "$($docPath).noseams.md"
    Set-Content -LiteralPath $noSeams -Encoding UTF8 -Value "# foo`n## Goal`nA"
    $null = Sti-ExtractSeams -Path $noSeams
    if ($LASTEXITCODE -eq 2) { Pass "Sti-ExtractSeams returns rc=2 when section absent" } else { Fail "section-absent should return rc=2" "rc=$LASTEXITCODE" }
    Remove-Item -Force $noSeams -ErrorAction SilentlyContinue
} finally {
    Remove-Item -Force $docPath -ErrorAction SilentlyContinue
}

# A second fixture set for the seam-shape cases (D340, ported from
# stride-opencode-ideation D321), each doc built in its own temp dir.
$TMP = Join-Path ([System.IO.Path]::GetTempPath()) ("sti-seams-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TMP | Out-Null
$docPath = Join-Path $TMP 'three-surfaces.md'
[System.IO.File]::WriteAllText($docPath, "# Test doc`n`n## Goal`nA goal.`n`n## Decomposition seams`n`nThe surfaces:`n`n1. **Kanban app** — owns the JSON contract for the workflow`n2. **stride plugin** — adapter for the Claude reference workflow`n3. **stride-copilot** — adapter for GitHub Copilot`n`nShared notes:`n- All three surfaces ship independently`n- Coordination via SemVer`n`n## Other section`n")
try {

    # === cases 1-15: the bash suite's fixtures and reference snippets, one ===
    # === for one (labels match test-stridify-per-goal.sh).                 ===

    # Non-ASCII characters are built from code points so this file stays ASCII.
    $EM = [string][char]0x2014   # em dash, as in the bash fixtures
    $AR = [string][char]0x2192   # right arrow, as in the bash labels

    function Write-Fixture([string]$Name, [string[]]$Lines) {
        $f = Join-Path $TMP $Name
        [System.IO.File]::WriteAllText($f, (($Lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
        return $f
    }

    # A realistic seven-surface requirements doc.
    $seven = Write-Fixture 'seven-surfaces.md' @(
        '# Some Feature', '', '## Problem', '', 'A description of the problem.', '',
        '## Goal', '', 'The goal.', '', '## Outcome', '', 'The outcome.', '',
        '## Decomposition seams', '',
        '**This document must be decomposed into seven independent goals.**', '',
        'The seven surfaces:', '',
        "1. **Kanban app** (this repo: ``lib/kanban_web/...``) $EM defines the contract.",
        "2. **stride plugin** (this repo: ``stride/``) $EM reference workflow.",
        "3. **stride-copilot** (separate repo) $EM Copilot CLI adapter.",
        "4. **stride-gemini** (separate repo) $EM Gemini CLI adapter.",
        "5. **stride-codex** (separate repo) $EM Codex adapter.",
        "6. **stride-opencode** (separate repo) $EM OpenCode adapter.",
        "7. **stride-pi** (separate repo) $EM Pi Coding Agent adapter.",
        '', '## Assumptions', '', 'Assumptions go here.'
    )
    # A doc WITHOUT a Decomposition seams section.
    $noSeamsDoc = Write-Fixture 'no-seams.md' @(
        '# Some Feature', '', '## Problem', '', 'Just one goal, no seams.', '',
        '## Goal', '', 'A single goal.', '', '## Outcome', '', 'Done.'
    )
    # Seams section present but the numbered list is empty.
    $emptySeamsDoc = Write-Fixture 'empty-seams.md' @(
        '# Some Feature', '', '## Problem', '', 'Foo.', '', '## Decomposition seams', '',
        'This section was added but no surfaces have been enumerated yet.', '',
        '## Outcome', '', 'Outcome.'
    )
    # Item 2 has a multi-line body.
    $multilineDoc = Write-Fixture 'multiline-body.md' @(
        '# Doc', '', '## Decomposition seams', '',
        "1. **First** $EM one-liner.",
        "2. **Second** $EM line one of the body.",
        '   Continuation line two.',
        '   Continuation line three.',
        "3. **Third** $EM back to one-liners."
    )
    # A seam literally named "1".
    $seamOneDoc = Write-Fixture 'seam-named-one.md' @(
        '# Doc', '', '## Decomposition seams', '',
        "1. **Alpha** $EM first surface.",
        "2. **1** $EM second surface, literally named `"1`".",
        "3. **Gamma** $EM third surface."
    )
    # Items missing the **bold** marker.
    $missingBoldDoc = Write-Fixture 'missing-bold.md' @(
        '# Doc', '', '## Decomposition seams', '',
        "1. **Valid** $EM has bold name.",
        "2. Plain Name $EM missing bold; should be skipped.",
        "3. **Also valid** $EM has bold name."
    )

    # Reference Step 1 parser (mirrors the bash parse_goal_arg and the stridify
    # SKILL Step 1 --goal parse): whitespace-split the argument string;
    # `--goal <v>` takes the NEXT token and drops both, `--goal=<v>` takes the
    # text after the leading `--goal=` (the FIRST `=`, so a value holding `=`
    # is kept whole) and drops the single token; every other token is the
    # remainder, re-joined with single spaces.
    function ConvertFrom-GoalArg([string]$ArgString) {
        $tokens = @($ArgString -split '\s+' | Where-Object { $_ -ne '' })
        $goal = ''
        $rest = New-Object System.Collections.Generic.List[string]
        $i = 0
        while ($i -lt $tokens.Count) {
            $t = $tokens[$i]
            if ($t -ceq '--goal') {
                $i++
                $goal = if ($i -lt $tokens.Count) { $tokens[$i] } else { '' }
                $i++
                continue
            }
            if ($t.StartsWith('--goal=', [System.StringComparison]::Ordinal)) {
                $goal = $t.Substring('--goal='.Length)
            } else {
                $rest.Add($t)
            }
            $i++
        }
        return @{ Goal = $goal; Rest = ($rest -join ' ') }
    }

    # Reference Step 5 slug composition (mirrors the bash SLUG_FOR_PATH_test).
    function Get-SlugForPath([string]$DocSlug, [string]$GoalSlug = '') {
        if ($GoalSlug) { return "$DocSlug-$GoalSlug" }
        return $DocSlug
    }

    # Reference Step 8d commit-message composition (mirrors commit_msg_test).
    function Get-CommitMessage([string]$DocSlug, [string]$GoalSlug = '') {
        if ($GoalSlug) { return "stride-ideation: decomposition for $DocSlug goal $GoalSlug" }
        return "stride-ideation: decomposition for $DocSlug"
    }

    function Get-Fields($tuple) { if ($tuple) { @(([string]$tuple) -split "`t") } else { @('', '', '') } }

    # === case 1: --goal absent on a doc without seams stays in "all goals" ===
    $c1 = ConvertFrom-GoalArg '/path/to/no-seams.md'
    if ($c1.Goal -ceq '' -and $c1.Rest -ceq '/path/to/no-seams.md') {
        Pass "case 1: --goal absent $AR empty GOAL_ARG, remainder is the path (AC8)"
    } else { Fail 'case 1: parse with no flag' "goal='$($c1.Goal)' rest='$($c1.Rest)'" }

    # === case 2: --goal "Kanban app" resolves to seam 1 by slug ===============
    $c2 = Sti-ResolveGoal -Path $seven -GoalArg 'Kanban app'
    $c2rc = $LASTEXITCODE
    if ($c2rc -eq 0) {
        $f = Get-Fields $c2
        if ($f[0] -ceq '1' -and $f[1] -ceq 'Kanban app' -and $f[2] -ceq 'kanban-app') {
            Pass "case 2: --goal 'Kanban app' $AR index=1 name='Kanban app' slug=kanban-app (AC1, AC2)"
        } else { Fail 'case 2: wrong resolution' "idx=$($f[0]) name='$($f[1])' slug=$($f[2])" }
    } else { Fail "case 2: Sti-ResolveGoal exited rc=$c2rc (expected 0)" }

    # === case 3: --goal 3 resolves to seam 3 by integer index =================
    $c3 = Sti-ResolveGoal -Path $seven -GoalArg '3'
    if ($LASTEXITCODE -eq 0) {
        $f = Get-Fields $c3
        if ($f[0] -ceq '3' -and $f[2] -ceq 'stride-copilot') {
            Pass "case 3: --goal 3 $AR integer-index resolves to stride-copilot (AC2)"
        } else { Fail 'case 3: wrong integer resolution' "idx=$($f[0]) slug=$($f[2])" }
    } else { Fail 'case 3: Sti-ResolveGoal exited non-zero on integer arg' }

    # === case 4: hyphenated slug resolves correctly ===========================
    $c4 = Sti-ResolveGoal -Path $seven -GoalArg 'stride-pi'
    if ($LASTEXITCODE -eq 0) {
        $f = Get-Fields $c4
        if ($f[0] -ceq '7') {
            Pass 'case 4: --goal stride-pi resolves to seam 7 (hyphenated slug, no integer collision)'
        } else { Fail 'case 4: hyphenated slug resolved to wrong index' "idx=$($f[0])" }
    } else { Fail 'case 4: Sti-ResolveGoal exited non-zero on hyphenated slug' }

    # === case 5: --goal=<value> form parses identically =======================
    $c5a = (ConvertFrom-GoalArg '--goal kanban-app /path/to/doc.md').Goal
    $c5b = (ConvertFrom-GoalArg '--goal=kanban-app /path/to/doc.md').Goal
    if ($c5a -ceq 'kanban-app' -and $c5b -ceq 'kanban-app') {
        Pass 'case 5: --goal <v> and --goal=<v> parse to identical GOAL_ARG (AC1)'
    } else { Fail 'case 5: dual-form parser disagrees' "form1='$c5a' form2='$c5b'" }

    # === case 6: unresolved --goal errors with seam listing ===================
    $null = Sti-ResolveGoal -Path $seven -GoalArg 'nonexistent' 2>$null
    $c6rc = $LASTEXITCODE
    if ($c6rc -eq 3) { Pass 'case 6: unresolved --goal returns rc=3 (AC4)' } else { Fail "case 6: expected rc=3, got rc=$c6rc" }
    # The CALLER prints the available-seams list; Sti-ExtractSeams gives the data.
    $c6count = @(Sti-ExtractSeams -Path $seven).Count
    if ($c6count -eq 7) { Pass 'case 6: sti_extract_seams returns 7 seams for the listing (AC4 evidence)' } else { Fail "case 6: expected 7 seams, got $c6count" }

    # === case 7: absent seams section returns rc=2 ============================
    $c7 = Sti-ResolveGoal -Path $noSeamsDoc -GoalArg 'anything' 2>$null
    $rc7 = $LASTEXITCODE
    if ($rc7 -eq 0) { Fail 'case 7: resolver returned 0 on doc without seams section' }
    elseif ($rc7 -eq 2 -and -not $c7) { Pass "case 7: doc without seams section $AR rc=2 (AC3)" }
    else { Fail "case 7: expected rc=2 got rc=$rc7" }

    # === case 8: empty seams section returns rc=4 =============================
    $c8 = Sti-ResolveGoal -Path $emptySeamsDoc -GoalArg 'anything' 2>$null
    $rc8 = $LASTEXITCODE
    if ($rc8 -eq 0) { Fail 'case 8: resolver returned 0 on doc with empty seams list' }
    elseif ($rc8 -eq 4 -and -not $c8) { Pass "case 8: empty seams list $AR rc=4 (testing_strategy edge)" }
    else { Fail "case 8: expected rc=4 got rc=$rc8" }

    # === case 9: path-suffix construction =====================================
    $targetNoGoal = Sti-UniquePath -Dir $TMP -Timestamp '2026-05-15T210800' -Slug (Get-SlugForPath 'review-queue-code-diffs') -Artifact 'stride-batch' -Extension 'json'
    $expectedNoGoal = "$TMP/2026-05-15T210800-review-queue-code-diffs-stride-batch.json"
    if ($targetNoGoal -ceq $expectedNoGoal) { Pass 'case 9a: target path without --goal matches historical format (AC8)' }
    else { Fail 'case 9a: target path mismatch' "got=$targetNoGoal want=$expectedNoGoal" }
    $targetWithGoal = Sti-UniquePath -Dir $TMP -Timestamp '2026-05-15T210800' -Slug (Get-SlugForPath 'review-queue-code-diffs' 'kanban-app') -Artifact 'stride-batch' -Extension 'json'
    $expectedWithGoal = "$TMP/2026-05-15T210800-review-queue-code-diffs-kanban-app-stride-batch.json"
    if ($targetWithGoal -ceq $expectedWithGoal) { Pass 'case 9b: target path with --goal embeds goal slug between doc-slug and artifact (AC6)' }
    else { Fail 'case 9b: target path mismatch' "got=$targetWithGoal want=$expectedWithGoal" }

    # === case 10: commit-message construction =================================
    $m10a = Get-CommitMessage 'review-queue-code-diffs'
    $m10b = Get-CommitMessage 'review-queue-code-diffs' 'kanban-app'
    if ($m10a -ceq 'stride-ideation: decomposition for review-queue-code-diffs') { Pass 'case 10a: commit message without --goal unchanged (AC8)' }
    else { Fail 'case 10a: commit message mismatch' $m10a }
    if ($m10b -ceq 'stride-ideation: decomposition for review-queue-code-diffs goal kanban-app') { Pass 'case 10b: commit message with --goal includes goal slug (AC6)' }
    else { Fail 'case 10b: commit message mismatch' $m10b }

    # === case 11: same --goal invoked twice produces -2 sibling ===============
    $firstPath = "$TMP/2026-05-15T210800-review-queue-code-diffs-kanban-app-stride-batch.json"
    New-Item -ItemType File -Path $firstPath -Force | Out-Null
    $secondPath = Sti-UniquePath -Dir $TMP -Timestamp '2026-05-15T210800' -Slug 'review-queue-code-diffs-kanban-app' -Artifact 'stride-batch' -Extension 'json'
    $expectedSecond = "$TMP/2026-05-15T210800-review-queue-code-diffs-kanban-app-stride-batch-2.json"
    if ($secondPath -ceq $expectedSecond) { Pass 'case 11: re-invoking --goal on same doc produces -2 sibling (AC7)' }
    else { Fail 'case 11: second-invocation path mismatch' "got=$secondPath want=$expectedSecond" }
    Remove-Item -LiteralPath $firstPath -Force -ErrorAction SilentlyContinue

    # === case 12: seam literally named "1" - integer wins =====================
    $f = Get-Fields (Sti-ResolveGoal -Path $seamOneDoc -GoalArg '1')
    if ($f[0] -ceq '1' -and $f[1] -ceq 'Alpha') { Pass "case 12: --goal 1 on doc with literal-1 seam $AR integer-index 1 wins (Alpha)" }
    else { Fail 'case 12: integer-vs-slug heuristic wrong' "idx=$($f[0]) name=$($f[1])" }

    # === case 13: multi-line item bodies - extractor uses first line only =====
    $c13 = @(Sti-ExtractSeams -Path $multilineDoc)
    $c13names = (@($c13 | ForEach-Object { ($_ -split "`t")[1] }) -join '|') + '|'
    if ($c13.Count -eq 3 -and $c13names -ceq 'First|Second|Third|') {
        Pass "case 13: multi-line item bodies $EM extractor uses bold-name from first line only (parser robustness)"
    } else { Fail 'case 13: multi-line extraction wrong' "count=$($c13.Count) names=$c13names" }

    # === case 14: items missing **bold** are silently skipped =================
    $c14 = @(Sti-ExtractSeams -Path $missingBoldDoc)
    $c14names = (@($c14 | ForEach-Object { ($_ -split "`t")[1] }) -join '|') + '|'
    if ($c14.Count -eq 2 -and $c14names -ceq 'Valid|Also valid|') { Pass 'case 14: items lacking **bold** are skipped (parser robustness)' }
    else { Fail 'case 14: missing-bold handling wrong' "count=$($c14.Count) names=$c14names" }

    # === case 15: prompt scoping - drops other surfaces, keeps matched ========
    $scoped15 = @(Sti-ScopeDocToSeam -Path $seven -Target 1)
    if (@($scoped15 | Where-Object { $_ -cmatch '^1\. \*\*Kanban app\*\*' }).Count -gt 0) {
        Pass 'case 15a: scoped prompt contains the matched item (Kanban app)'
    } else { Fail 'case 15a: scoped prompt missing matched item' (($scoped15 | Select-Object -Last 20) -join ' / ') }
    $others15 = @($scoped15 | Where-Object { $_ -cmatch '^[2-9]\. \*\*' })
    if ($others15.Count -gt 0) { Fail 'case 15b: scoped prompt still contains other surface items' ($others15 -join ' / ') }
    else { Pass 'case 15b: scoped prompt drops the other six surface items (AC5)' }
    if (@($scoped15 | Where-Object { $_ -cmatch '^## Assumptions' }).Count -gt 0) {
        Pass 'case 15c: scoped prompt preserves sections outside seams (## Assumptions still present)'
    } else { Fail 'case 15c: scoped prompt dropped a section outside seams' }
    if (($scoped15 -join "`n").Contains('**Scoped to a single surface for this dispatch.**')) {
        Pass 'case 15d: scoped prompt includes the dispatch-scoping notice'
    } else { Fail 'case 15d: scoped prompt missing dispatch-scoping notice' }

    # === cases 16-22: one seam definition for count, resolve and scope ======

    function New-SeamsDoc([string]$Name, [string]$Body) {
        $f = Join-Path $TMP $Name
        $text = "# Doc`n`n## Problem`n`np`n`n## Decomposition seams`n`nIntro prose.`n`n" + $Body + "`n## Assumptions`n`na`n"
        [System.IO.File]::WriteAllText($f, $text)
        return $f
    }
    function Get-SeamNames([string]$f) { ((@(Sti-ExtractSeams -Path $f) | ForEach-Object { ($_ -split "`t")[1] }) -join '|') + '|' }
    function Get-SeamCount([string]$f) { @(Sti-ExtractSeams -Path $f).Count }
    # The Step 2.4 advisory's count, computed exactly as the stridify skill does.
    function Get-AdvisoryCount([string]$f) { @(Sti-ExtractSeams -Path $f).Count }
    function Get-Field([string]$tuple, [int]$n) { if ($tuple) { ($tuple -split "`t")[$n] } else { '' } }

    $bulleted = New-SeamsDoc 'bulleted.md' @"
- **Kanban app** — owns the JSON contract
- **stride plugin** — adapter
  - nested note that is not a seam
- **stride-copilot** — port
* **Docs site** — guides

"@
    if (((Get-SeamCount $bulleted) -eq 4) -and ((Get-SeamNames $bulleted) -ceq 'Kanban app|stride plugin|stride-copilot|Docs site|')) {
        Pass 'case 16a: four bulleted bold seams are extracted (nested bullets are not seams)'
    } else { Fail 'case 16a: bulleted extraction' "count=$(Get-SeamCount $bulleted) names=$(Get-SeamNames $bulleted)" }
    $case16ok = $true
    foreach ($i in 1..4) { Sti-ResolveGoal -Path $bulleted -GoalArg "$i" | Out-Null; if ($LASTEXITCODE -ne 0) { $case16ok = $false } }
    if ($case16ok -and ((Get-AdvisoryCount $bulleted) -eq 4)) { Pass 'case 16b: the advisory counts 4 and --goal 1..4 all resolve (rc 0)' }
    else { Fail 'case 16b: advisory and resolver disagree on bulleted seams' }
    $scoped16 = @(Sti-ScopeDocToSeam -Path $bulleted -Target 2)
    if (($scoped16 -contains '- **stride plugin** — adapter') -and ($scoped16 -contains '  - nested note that is not a seam') -and
        -not ($scoped16 | Where-Object { $_ -match '\*\*(Kanban app|stride-copilot|Docs site)\*\*' }) -and
        ($scoped16 | Where-Object { $_ -match '^## Assumptions' })) {
        Pass 'case 16c: scoping a bulleted doc to item 2 keeps only that item (with its nested lines)'
    } else { Fail 'case 16c: bulleted scoping' ($scoped16 -join ' / ') }

    $headings = New-SeamsDoc 'headings.md' @"
### Kanban app

Owns the JSON contract.

#### Detail that stays with the item

### stride plugin

Adapter.

"@
    if ((Get-SeamNames $headings) -ceq 'Kanban app|stride plugin|') { Pass 'case 17a: ### headings are seams when there are no bold items (#### is not)' }
    else { Fail 'case 17a: heading extraction' "names=$(Get-SeamNames $headings)" }
    $case17idx = Get-Field (Sti-ResolveGoal -Path $headings -GoalArg '2') 1
    $case17slug = Get-Field (Sti-ResolveGoal -Path $headings -GoalArg 'kanban-app') 0
    if (($case17idx -ceq 'stride plugin') -and ($case17slug -eq '1')) { Pass 'case 17b: heading seams resolve by index and by slug' }
    else { Fail 'case 17b: heading resolution' "idx2=$case17idx slug->$case17slug" }
    $scoped17 = @(Sti-ScopeDocToSeam -Path $headings -Target 1)
    if (($scoped17 -contains '#### Detail that stays with the item') -and -not ($scoped17 -contains '### stride plugin')) {
        Pass 'case 17c: scoping a heading doc keeps the item and its sub-headings only'
    } else { Fail 'case 17c: heading scoping' ($scoped17 -join ' / ') }

    $mixed = New-SeamsDoc 'mixed.md' @"
1. **Kanban app** — contract
2. **stride plugin** — adapter
3. **stride-copilot** — port

Shared contract:
- **JSON schema** — cross-cutting
- **Auth** — cross-cutting
- **Versioning** — cross-cutting
- **Telemetry** — cross-cutting
- **Docs** — cross-cutting

"@
    if (((Get-AdvisoryCount $mixed) -eq 3) -and ((Get-SeamNames $mixed) -ceq 'Kanban app|stride plugin|stride-copilot|')) {
        Pass "case 18: a numbered list's secondary bullets are not counted as seams (advisory stays quiet at 3)"
    } else { Fail 'case 18: mixed numbered + bullets' "count=$(Get-AdvisoryCount $mixed) names=$(Get-SeamNames $mixed)" }

    $dashName = New-SeamsDoc 'dash-name.md' @"
- **front-end — web** — the UI
- **back-end** — the API

"@
    if ((Get-Field (Sti-ResolveGoal -Path $dashName -GoalArg '1') 1) -ceq 'front-end — web') { Pass 'case 19: a bold name containing dashes is kept verbatim' }
    else { Fail 'case 19: dashed name' (Sti-ResolveGoal -Path $dashName -GoalArg '1') }

    $emptySection = New-SeamsDoc 'empty-section.md' ''
    Sti-ResolveGoal -Path $emptySection -GoalArg '1' | Out-Null
    $case20rc = $LASTEXITCODE
    if (($case20rc -eq 4) -and ((Get-AdvisoryCount $emptySection) -eq 0)) { Pass 'case 20: an empty seams section counts 0 and resolves rc 4 (contract unchanged)' }
    else { Fail 'case 20: empty section' "rc=$case20rc" }

    $skew = New-SeamsDoc 'skew.md' @"
1. **???** — not addressable
2. **Real** — the only real surface

"@
    $case21name = Get-Field (Sti-ResolveGoal -Path $skew -GoalArg '1') 1
    $scoped21 = @(Sti-ScopeDocToSeam -Path $skew -Target 1)
    if (($case21name -ceq 'Real') -and ($scoped21 | Where-Object { $_.Contains('2. **Real**') }) -and -not ($scoped21 | Where-Object { $_.Contains('**???**') })) {
        Pass "case 21: scoping uses the resolver's index (an unaddressable item does not shift it)"
    } else { Fail 'case 21: index skew' "resolved=$case21name scoped=$($scoped21 -join ' / ')" }

    $nestedSteps = New-SeamsDoc 'nested-steps.md' @"
- **Kanban app** — owns the contract
    1. **Schema** — a step, not a seam
    2. **Migration** — a step, not a seam
- **stride plugin** — adapter

"@
    Sti-ResolveGoal -Path $nestedSteps -GoalArg 'stride plugin' | Out-Null
    if (((Get-SeamNames $nestedSteps) -ceq 'Kanban app|stride plugin|') -and ($LASTEXITCODE -eq 0)) {
        Pass 'case 23: a nested numbered sub-list under bulleted seams does not take over the section'
    } else { Fail 'case 23: nested numbered steps' "names=$(Get-SeamNames $nestedSteps)" }

    $case22ok = $true
    foreach ($doc in @($docPath, $seven, $bulleted, $headings, $mixed, $dashName)) {
        foreach ($tuple in @(Sti-ExtractSeams -Path $doc)) {
            $parts = $tuple -split "`t"
            $text = (@(Sti-ScopeDocToSeam -Path $doc -Target ([int]$parts[0])) -join "`n")
            if (-not $text.Contains($parts[1])) { $case22ok = $false; Fail "case 22: $(Split-Path -Leaf $doc) index $($parts[0]) does not scope to '$($parts[1])'" }
        }
    }
    if ($case22ok) { Pass 'case 22: for every shape, each extracted index scopes to the seam it names' }

    # === case 24: --goal 01 is index 1 (compared as a number) ===============
    if ((Get-Field (Sti-ResolveGoal -Path $docPath -GoalArg '01') 0) -eq '1') { Pass 'case 24: --goal 01 resolves to index 1' }
    else { Fail 'case 24: --goal 01' "rc=$LASTEXITCODE" }

    # === case 25: numbered seams are top level only (0-3 leading spaces) =====
    $indent3 = New-SeamsDoc 'indent3.md' "   1. **Three spaces** — still a top-level item`n   2. **Also three** — still a top-level item`n"
    $indent4 = New-SeamsDoc 'indent4.md' "- **Bulleted** — the real seam`n    1. **Four spaces** — a nested step`n"
    if (((Get-SeamNames $indent3) -ceq 'Three spaces|Also three|') -and ((Get-SeamNames $indent4) -ceq 'Bulleted|')) {
        Pass 'case 25: a numbered item indented 3 spaces is a seam; one indented 4 is not'
    } else { Fail 'case 25: indentation boundary' "3sp=$(Get-SeamNames $indent3) 4sp=$(Get-SeamNames $indent4)" }

    # === case 26: a tab-indented numbered sub-list under bulleted seams ======
    $tabSteps = New-SeamsDoc 'tab-steps.md' "- **Kanban app** — contract`n`t1. **Schema** — a step`n- **stride plugin** — adapter`n"
    if (((Get-SeamNames $tabSteps) -ceq 'Kanban app|stride plugin|') -and ((Get-AdvisoryCount $tabSteps) -eq 2)) {
        Pass 'case 26: a tab-indented numbered sub-list neither adds seams nor switches the section to numbered mode'
    } else { Fail 'case 26: tab-indented steps' "names=$(Get-SeamNames $tabSteps)" }

    # === case 27: a 2- or 3-space numbered sub-list under bulleted seams =====
    foreach ($sp in @('  ', '   ')) {
        $nested = New-SeamsDoc "nested-$($sp.Length).md" "- **Kanban app** — contract`n$($sp)1. **Schema** — a step`n$($sp)2. **Migration** — a step`n- **stride plugin** — adapter`n"
        $scoped = (Sti-ScopeDocToSeam -Path $nested -Target 1) -join "`n"
        if (((Get-SeamNames $nested) -ceq 'Kanban app|stride plugin|') -and ((Get-AdvisoryCount $nested) -eq 2) -and
            $scoped.Contains('**Schema**') -and -not $scoped.Contains('stride plugin')) {
            Pass "case 27: a $($sp.Length)-space numbered sub-list under bulleted seams stays inside its seam"
        } else { Fail "case 27: $($sp.Length)-space nested steps" "names=$(Get-SeamNames $nested)" }
    }

    # === case 28: a sub-list indented deeper than the numbered seams ==========
    $numNested = New-SeamsDoc 'num-nested.md' "1. **Schema** — the data model`n   1. **Columns** — a sub-step, not a seam`n2. **API** — the endpoints`n"
    if (((Get-SeamNames $numNested) -ceq 'Schema|API|') -and ((Get-AdvisoryCount $numNested) -eq 2)) {
        Pass 'case 28: a numbered sub-list indented deeper than its numbered seam is not a seam'
    } else { Fail 'case 28: nested numbered under numbered' "names=$(Get-SeamNames $numNested)" }

    # === case 29: the section heading is matched case-sensitively =============
    $wrongCase = Join-Path $TMP 'wrong-case.md'
    [System.IO.File]::WriteAllText($wrongCase, "# Doc`n`n## Decomposition Seams`n`n1. **Only** — x`n", (New-Object System.Text.UTF8Encoding($false)))
    Sti-ExtractSeams -Path $wrongCase 2>$null | Out-Null; $rcX = $LASTEXITCODE
    Sti-ResolveGoal -Path $wrongCase -GoalArg '1' 2>$null | Out-Null; $rcR = $LASTEXITCODE
    if (($rcX -eq 2) -and ($rcR -eq 2)) { Pass "case 29: '## Decomposition Seams' is not the seams section (rc 2 from extract and resolve)" }
    else { Fail 'case 29: heading case' "extract rc=$rcX resolve rc=$rcR" }
} finally {
    Remove-Item -Recurse -Force $TMP -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
