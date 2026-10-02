# PowerShell twin of test-stridify-retry.sh -- exercises the Step 7 retry
# contract documented in skills/stride-ideation-stridify/SKILL.md: the 7a
# classifier that buckets agent-run outcomes into success / transient /
# terminal, AND a PowerShell REFERENCE retry loop (mirroring the bash
# `dispatch_with_retry`; 7b cap MAX_ATTEMPTS=3, backoffs zeroed for tests)
# driven by a scriptblock mock agent with a counter.
#
# The reference implementations below MUST stay consistent with SKILL.md
# Step 7 AND with the bash twin. If you edit one, edit all three.
# This file is ASCII-only: non-ASCII label characters use [char] codes.

Set-StrictMode -Version Latest

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-stridify-retry.ps1 -- Step 7 retry classifier and retry loop'
Write-Host ''

# Mirror of the bash classify() function the skill body inlines. Inputs
# are the subagent dispatch result string; outputs are one of:
#   success | transient | terminal
function Classify-Result {
    param([string]$Result)
    if ([string]::IsNullOrEmpty($Result)) { return 'terminal' }
    # success: contains a single fenced ```json block with a parseable object.
    if ($Result -match '(?s)```json\s*\n(\{.*?\})\s*\n```') {
        try {
            $null = $matches[1] | ConvertFrom-Json -ErrorAction Stop
            return 'success'
        } catch {
            return 'terminal'
        }
    }
    # transient (SKILL.md 7a): HTTP 429, any 5xx, an "overloaded" /
    # "rate limit" / "capacity" body, or a network error (DNS resolution,
    # connection refused, timeout, TLS handshake). Same rules as the bash
    # twin's classify_dispatch_error.
    if ($Result -match '(?<![0-9])(429|5[0-9][0-9])(?![0-9])' -or
        $Result -match '(?i)overloaded' -or $Result -match '(?i)rate limit' -or
        $Result -match '(?i)capacity' -or
        $Result -match '(?i)connection refused' -or $Result -match '(?i)could not resolve' -or
        $Result -match '(?i)timeout' -or $Result -match '(?i)tls handshake') {
        return 'transient'
    }
    # terminal: everything else (agent file missing, contract violation, other 4xx).
    return 'terminal'
}

# Stage 1: well-formed success.
$ok = @'
```json
{"source_spec": "x", "goals": [{"title": "G", "type": "goal", "tasks": []}]}
```
'@
if ((Classify-Result $ok) -ceq 'success') { Pass "well-formed JSON -> success" } else { Fail "well-formed JSON should be success" }

# Stage 2: HTTP 529 (transient).
if ((Classify-Result 'HTTP 529: Overloaded') -ceq 'transient') { Pass "HTTP 529 -> transient" } else { Fail "HTTP 529 should be transient" }

# Stage 3: overloaded string (transient).
if ((Classify-Result 'API is overloaded right now') -ceq 'transient') { Pass "overloaded string -> transient" } else { Fail "overloaded should be transient" }

# Stage 4: network errors (transient).
if ((Classify-Result 'Connection refused on port 443') -ceq 'transient') { Pass "Connection refused -> transient" } else { Fail }
if ((Classify-Result 'Could not resolve host api.anthropic.com') -ceq 'transient') { Pass "DNS failure -> transient" } else { Fail }
if ((Classify-Result 'Request timeout after 30s') -ceq 'transient') { Pass "timeout -> transient" } else { Fail }
if ((Classify-Result 'TLS handshake error') -ceq 'transient') { Pass "TLS handshake -> transient" } else { Fail }

# Stage 5: bad agent name (terminal).
if ((Classify-Result 'agent type does-not-exist not found') -ceq 'terminal') { Pass "bad agent name -> terminal" } else { Fail }

# Stage 6: hard 4xx other than 529 (terminal).
if ((Classify-Result 'HTTP 400: Bad Request') -ceq 'terminal') { Pass "HTTP 400 -> terminal" } else { Fail }
if ((Classify-Result 'HTTP 401: Unauthorized') -ceq 'terminal') { Pass "HTTP 401 -> terminal" } else { Fail }

# Stage 7: contract violation (no fenced JSON) (terminal).
if ((Classify-Result 'Here is your decomposition... no JSON anywhere') -ceq 'terminal') { Pass "no fenced JSON -> terminal" } else { Fail }

# Stage 8: malformed JSON inside fence (terminal).
$bad = @'
```json
not valid json {{
```
'@
if ((Classify-Result $bad) -ceq 'terminal') { Pass "malformed JSON in fence -> terminal" } else { Fail "malformed JSON should be terminal" }

# Stage 9: empty result (terminal).
if ((Classify-Result '') -ceq 'terminal') { Pass "empty result -> terminal" } else { Fail }

# Stage 10: backoff schedule sanity -- 3 attempts total, sleep 30s then 90s.
# The bash test checks the documented schedule strings against the body of
# the stridify command. For the .ps1 mirror we confirm the schedule
# values are present in the skill body file via grep.
$skillBody = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '../skills/stride-ideation-stridify/SKILL.md') -ErrorAction SilentlyContinue
if ($skillBody -and $skillBody -match 'sleep 30' -and $skillBody -match 'sleep 90' -and $skillBody -match 'MAX_ATTEMPTS=3') {
    Pass "skill body documents 3-attempt retry with 30s/90s backoff"
} else {
    Fail "skill body retry-schedule sentinels missing or skill file not found"
}

# --- SKILL 7a transient rows the original classifier missed ------------------
# Same inputs and labels as the bash twin's case 9.
function Assert-Class($label, $text, $expected) {
    $got = Classify-Result $text
    if ($got -ceq $expected) { Pass $label } else { Fail $label "'$text' classified as $got (expected $expected)" }
}
Assert-Class 'case 9: HTTP 429 classifies as transient' 'HTTP 429: Too Many Requests' 'transient'
Assert-Class 'case 9: HTTP 500 classifies as transient' 'HTTP 500: Internal Server Error' 'transient'
Assert-Class 'case 9: HTTP 503 classifies as transient' 'HTTP 503: Service Unavailable' 'transient'
Assert-Class "case 9: 'rate limit' body classifies as transient" 'Error: rate limit exceeded, retry later' 'transient'
Assert-Class "case 9: 'capacity' body classifies as transient" 'Error: model at capacity' 'transient'
Assert-Class 'case 9: HTTP 404 (other 4xx) classifies as terminal' 'HTTP 404: Not Found' 'terminal'
# Bash cases 5-7 (classifier strings), same inputs and labels.
Assert-Class "case 5: 'overloaded' string in error body classifies as transient" 'API returned: overloaded; try again later' 'transient'
Assert-Class 'case 6: unknown subagent type classifies as terminal' 'unknown subagent type: foo' 'terminal'
Assert-Class "case 7: 'Connection refused' classifies as transient" 'curl: (7) Failed to connect: Connection refused' 'transient'

# --- mock agent ---------------------------------------------------------------
# Mirrors the bash mock_agent.sh: fails the first N calls (counter), in the
# given mode, then succeeds with a fenced ```json block. Returns
# @{ ok; out; err } -- err is what the bash mock writes to stderr.
$EmDash = [string][char]0x2014
$Times = [string][char]0x00D7

function New-MockAgent([int]$Remaining, [string]$Mode) {
    $state = @{ remaining = $Remaining; mode = $Mode; calls = 0; prompts = @() }
    $sb = {
        param([string]$Prompt)
        $state.calls++
        $state.prompts += $Prompt
        if ($state.remaining -gt 0) {
            $state.remaining--
            switch ($state.mode) {
                'transient' {
                    return @{ ok = $false; out = ''; err = ('Error: HTTP 529 Overloaded ' + [string][char]0x2014 + " Anthropic API capacity (remaining=$($state.remaining))") }
                }
                'terminal' {
                    return @{ ok = $false; out = ''; err = 'Error: subagent returned non-JSON response (contract violation)' }
                }
                default {
                    return @{ ok = $false; out = ''; err = "Error: unknown mode $($state.mode)" }
                }
            }
        }
        return @{ ok = $true; err = ''; out = ('```json' + "`n" + '{"goals":[{"title":"G1","type":"goal","tasks":[{"title":"T1","type":"work"}]}]}' + "`n" + '```') }
    }.GetNewClosure()
    return @{ invoke = $sb; state = $state }
}

# --- reference retry loop -------------------------------------------------------
# Mirrors the bash dispatch_with_retry and SKILL.md 7b/7c. Backoffs default to
# 0 (as in bash) so the suite runs fast; the documented schedule is 30s / 90s.
$MaxAttempts = 3
$Backoff1 = if ($env:BACKOFF_1) { [int]$env:BACKOFF_1 } else { 0 }
$Backoff2 = if ($env:BACKOFF_2) { [int]$env:BACKOFF_2 } else { 0 }

# Returns @{ rc; out; log } where log is the list of lines the bash reference
# writes to stderr: one header per attempt, plus TERMINAL:/EXHAUSTED: lines.
function Invoke-DispatchWithRetry([scriptblock]$Mock, [string]$Prompt = '') {
    $log = New-Object System.Collections.Generic.List[string]
    $attempt = 1
    while ($attempt -le $MaxAttempts) {
        $log.Add(("dispatching attempt {0}/{1}" -f $attempt, $MaxAttempts))
        $r = & $Mock $Prompt
        if ($r.ok) { return @{ rc = 0; out = $r.out; log = $log } }
        $lastError = $r.err
        if ((Classify-Result $lastError) -ceq 'terminal') {
            $log.Add("TERMINAL: $lastError")
            return @{ rc = 1; out = ''; log = $log }
        }
        if ($attempt -lt $MaxAttempts) {
            switch ($attempt) {
                1 { Start-Sleep -Seconds $Backoff1 }
                2 { Start-Sleep -Seconds $Backoff2 }
            }
            $attempt++
            continue
        }
        $log.Add("EXHAUSTED: $lastError")
        return @{ rc = 1; out = ''; log = $log }
    }
    return @{ rc = 1; out = ''; log = $log }
}

function Get-AttemptCount($log) { @($log | Where-Object { $_ -cmatch '^dispatching attempt' }).Count }

# --- case 1: success on first attempt (no retry path exercised) ---------------
$m1 = New-MockAgent 0 'transient'
$r1 = Invoke-DispatchWithRetry $m1.invoke
if ($r1.rc -eq 0) {
    if ($r1.out.Contains('```json')) { Pass 'case 1: succeeds on first attempt with valid fenced JSON' }
    else { Fail 'case 1: succeeded but output lacked fenced JSON' $r1.out }
} else {
    Fail 'case 1: dispatch_with_retry returned non-zero on first-attempt success' ($r1.log -join ' | ')
}
$a1 = Get-AttemptCount $r1.log
if ($a1 -eq 1 -and $m1.state.calls -eq 1) { Pass 'case 1: exactly 1 attempt logged (no retry on success)' }
else { Fail "case 1: expected 1 attempt, got $a1 (mock calls: $($m1.state.calls))" }

# --- case 2: 2x transient then success on attempt 3 -----------------------------
$m2 = New-MockAgent 2 'transient'
$r2 = Invoke-DispatchWithRetry $m2.invoke
if ($r2.rc -eq 0) {
    if ($r2.out.Contains('```json')) { Pass "case 2: 2$Times transient then success on attempt 3" }
    else { Fail 'case 2: succeeded but output lacked fenced JSON' $r2.out }
} else {
    Fail "case 2: failed after 2$Times transient + 1$Times success" ($r2.log -join ' | ')
}
$a2 = Get-AttemptCount $r2.log
if ($a2 -eq 3 -and $m2.state.calls -eq 3) { Pass 'case 2: exactly 3 attempts logged' }
else { Fail "case 2: expected 3 attempts, got $a2 (mock calls: $($m2.state.calls))" }

# --- case 3: 3x transient -> exhaust + surface LAST error verbatim ---------------
$m3 = New-MockAgent 3 'transient'
$r3 = Invoke-DispatchWithRetry $m3.invoke
if ($r3.rc -eq 0) {
    Fail "case 3: returned 0 after 3$Times transient (expected non-zero)"
} else {
    if (@($r3.log | Where-Object { $_ -cmatch '^EXHAUSTED' }).Count -gt 0) { Pass 'case 3: exhausts retries and exits non-zero' }
    else { Fail 'case 3: failed but did not log EXHAUSTED' ($r3.log -join ' | ') }
    # Each transient error carries the mock's remaining count, so the LAST
    # attempt's error is the one with remaining=0 -- match that line exactly.
    $lastLine = "EXHAUSTED: Error: HTTP 529 Overloaded $EmDash Anthropic API capacity (remaining=0)"
    if ($r3.log.Contains($lastLine) -and -not (($r3.log -join "`n").Contains('remaining=2'))) {
        Pass "case 3: surfaces LAST attempt's error verbatim"
    } else {
        Fail 'case 3: terminal output did not include last error verbatim' ($r3.log -join ' | ')
    }
}
$a3 = Get-AttemptCount $r3.log
if ($a3 -eq 3 -and $m3.state.calls -eq 3) { Pass "case 3: cap honored $EmDash exactly 3 attempts" }
else { Fail "case 3: expected 3 attempts, got $a3 (cap not honored)" }

# --- case 4: contract violation -> fail fast, no retry ---------------------------
$m4 = New-MockAgent 5 'terminal'   # would fail 5x if it kept retrying
$r4 = Invoke-DispatchWithRetry $m4.invoke
if ($r4.rc -eq 0) {
    Fail 'case 4: returned 0 on contract violation (expected non-zero)'
} else {
    if (@($r4.log | Where-Object { $_ -cmatch '^TERMINAL' }).Count -gt 0) { Pass 'case 4: classifies contract violation as terminal' }
    else { Fail 'case 4: terminal classification not logged' ($r4.log -join ' | ') }
}
$a4 = Get-AttemptCount $r4.log
if ($a4 -eq 1 -and $m4.state.calls -eq 1) { Pass 'case 4: fails fast on attempt 1 (terminal does NOT retry)' }
else { Fail "case 4: expected 1 attempt, got $a4 $EmDash terminal retried!" }

# --- case 8: attempt headers must NOT include the full prompt -------------------
$prompt8 = @(
    'Requirements document:'
    ''
    '```'
    '# PROMPT_MARKER_W2198 full requirements doc text'
    '```'
) -join "`n"
$m8 = New-MockAgent 2 'transient'
$r8 = Invoke-DispatchWithRetry $m8.invoke $prompt8
$logLines = $r8.log.Count
$prompted = @($m8.state.prompts | Where-Object { $_ -ceq $prompt8 }).Count
if ($logLines -le 8 -and -not (($r8.log -join "`n").Contains('PROMPT_MARKER_W2198')) -and $prompted -eq 3) {
    Pass "case 8: retry log is concise $EmDash no prompt echoed ($logLines lines)"
} else {
    Fail "case 8: retry log too long ($logLines lines) $EmDash prompt may be leaking" ($r8.log -join ' | ')
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
