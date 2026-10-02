# stride-ideation intra-session draft autosave helpers
# (PowerShell mirror of lib/draft.sh).
#
# Six pure cmdlets used by the stride-ideation-ideate skill to persist an
# in-progress ideation draft to a gitignored scratch file under .stride/, so an
# interruption mid-session is recoverable and a later session can offer resume.
# PascalCase-with-hyphen cmdlet names mirror the snake_case bash functions
# one-to-one:
#
#   sti_draft_path   -> Sti-DraftPath
#   sti_draft_find   -> Sti-DraftFind
#   sti_draft_save   -> Sti-DraftSave   (content as an argument or piped in)
#   sti_draft_dir    -> Sti-DraftDir
#   sti_draft_load   -> Sti-DraftLoad
#   sti_draft_exists -> Sti-DraftExists
#   sti_draft_clear  -> Sti-DraftClear
#
# Filename rule: the scratch path is <dir>/<ts>-<slug>-draft.md, pairing with
# the eventual requirements doc by its <ts>-<slug> prefix. Half-finished,
# possibly sensitive ideation must never be committed, and the user's own
# .gitignore is not ours to edit, so the scratch dir ignores itself:
# Sti-DraftDir writes <dir>/.gitignore holding `*` when it is absent and the
# dir is the scratch dir (created by the call, or named .stride). The helper
# never serializes any secret — it only writes the content it is handed; pipe
# that content in, so arbitrary prose needs no quoting.
#
# Resume keys on the SLUG, not the session timestamp: Sti-DraftFind matches
# every <ts>-<slug>-draft.md whose <ts> has the exact YYYY-MM-DDTHHMMSS shape
# (any timestamp) and returns the latest (ISO timestamps sort lexically). The
# slug must follow the timestamp directly, so `toggle` never matches a
# `dark-mode-toggle` draft.
#
# Happy-path output goes to stdout via Write-Output. Errors are written via
# Write-Error; value cmdlets return $null and find/save/load/clear set
# $global:LASTEXITCODE. Source via dot-sourcing:
#   . path\to\lib\draft.ps1
#   Sti-DraftPath .stride 2026-05-12T103000 foo

Set-StrictMode -Version Latest

# True when <item> is a symbolic link or junction -- the same thing bash's
# `-L` tests. LinkType names it exactly; other reparse points (a cloud
# placeholder, say) are not links. Without LinkType (older hosts), fall back
# to the reparse-point attribute, which errs toward refusing.
function Test-StiLink($Item) {
    if (-not $Item) { return $false }
    if ($Item.PSObject.Properties['LinkType']) {
        return @('SymbolicLink', 'Junction') -contains [string]$Item.LinkType
    }
    return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Sti-DraftPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Dir,
        [Parameter(Mandatory = $true, Position = 1)][AllowEmptyString()][string]$Timestamp,
        [Parameter(Mandatory = $true, Position = 2)][AllowEmptyString()][string]$Slug
    )
    if ([string]::IsNullOrEmpty($Dir) -or [string]::IsNullOrEmpty($Timestamp) -or [string]::IsNullOrEmpty($Slug)) {
        Write-Error 'Sti-DraftPath: usage: Sti-DraftPath <dir> <ts> <slug>'
        return $null
    }
    $dirTrimmed = $Dir.TrimEnd([char]'/', [char]'\')
    # Forward-slash join to match the bash output exactly.
    Write-Output "$dirTrimmed/$Timestamp-$Slug-draft.md"
}

function Sti-DraftFind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Dir,
        [Parameter(Mandatory = $true, Position = 1)][AllowEmptyString()][string]$Slug
    )
    # Latest NON-EMPTY draft for <slug> under <dir>, any timestamp. Writes the
    # path to stdout and sets LASTEXITCODE 0; on miss / absent dir sets
    # LASTEXITCODE 1 and writes nothing. Empty draft files are ignored so a
    # zero-length scratch never triggers a resume offer.
    if ([string]::IsNullOrEmpty($Dir) -or [string]::IsNullOrEmpty($Slug)) {
        Write-Error 'Sti-DraftFind: usage: Sti-DraftFind <dir> <slug>'
        $global:LASTEXITCODE = 1
        return
    }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        $global:LASTEXITCODE = 1
        return
    }
    # Anchor the timestamp shape so the slug must follow it directly: slug
    # `toggle` never matches a `dark-mode-toggle` draft. The match is
    # case-sensitive and the newest is picked by ordinal comparison, exactly
    # like lib/draft.sh's glob and byte-wise `[ \> ]`.
    $namePattern = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}-' + [regex]::Escape($Slug) + '-draft\.md\z'
    $candidates = @(
        Get-ChildItem -LiteralPath $Dir -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -cmatch $namePattern -and $_.Length -gt 0 -and -not (Test-StiLink $_) }
    )
    # A draft git already tracks is never resumed: autosave would write new
    # prose into a committed file, which the next `git commit -a` would record.
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($git -and $candidates.Count -gt 0) {
        $inside = & git -C $Dir rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0 -and $inside -eq 'true') {
            $candidates = @($candidates | Where-Object {
                & git -C $Dir ls-files --error-unmatch -- $_.Name 2>$null | Out-Null
                $LASTEXITCODE -ne 0
            })
        }
    }
    if ($candidates.Count -eq 0) {
        $global:LASTEXITCODE = 1
        return
    }
    $latest = $candidates[0].Name
    foreach ($candidate in $candidates) {
        if ([string]::CompareOrdinal($candidate.Name, $latest) -gt 0) { $latest = $candidate.Name }
    }
    $dirTrimmed = $Dir.TrimEnd([char]'/', [char]'\')
    Write-Output "$dirTrimmed/$latest"
    $global:LASTEXITCODE = 0
}

function Sti-DraftDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Dir
    )
    # Create the scratch dir <dir> if needed and make it ignore itself, by the
    # same rule as lib/draft.sh's sti_draft_dir: write <dir>/.gitignore
    # containing `*` when it is absent AND this call created <dir> or <dir> is
    # named `.stride`. Never overwrites an existing .gitignore.
    if ([string]::IsNullOrEmpty($Dir)) {
        Write-Error 'Sti-DraftDir: usage: Sti-DraftDir <dir>'
        $global:LASTEXITCODE = 1
        return
    }
    # Symbolic links are refused outright, as in lib/draft.sh: <dir> or
    # <dir>/.gitignore as a link would send the ignore file, and the drafts,
    # somewhere else.
    foreach ($candidate in @($Dir.TrimEnd([char]'/', [char]'\'), (Join-Path $Dir '.gitignore'))) {
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if (Test-StiLink $item) {
            Write-Error "Sti-DraftDir: $Dir or its .gitignore is a symbolic link; refusing to write through it"
            $global:LASTEXITCODE = 1
            return
        }
    }
    try {
        $created = -not (Test-Path -LiteralPath $Dir -PathType Container)
        New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop | Out-Null
        $ignoreFile = Join-Path $Dir '.gitignore'
        if (-not (Test-Path -LiteralPath $ignoreFile) -and ($created -or (Split-Path -Leaf $Dir.TrimEnd([char]'/', [char]'\')) -ceq '.stride')) {
            # Same bytes as lib/draft.sh writes: "*" and a newline, no BOM.
            # .NET resolves relative paths against the process directory, so
            # resolve against the PowerShell location first.
            $ignoreFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ignoreFile)
            [System.IO.File]::WriteAllText($ignoreFull, "*`n", (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch {
        Write-Error "Sti-DraftDir: cannot create scratch directory: $Dir"
        $global:LASTEXITCODE = 1
        return
    }
    # Inside a git work tree, check the result: if a draft name in <dir> would
    # still not be ignored (an existing .gitignore there that does not cover
    # drafts), return 2 and leave the user's file alone.
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($git) {
        $inside = & git -C $Dir rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0 -and $inside -eq 'true') {
            & git -C $Dir check-ignore -q -- '0000-00-00T000000-probe-draft.md' 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Sti-DraftDir: drafts in $Dir would not be ignored by git ($Dir/.gitignore exists but does not cover them); add a line containing * to it to enable autosave"
                $global:LASTEXITCODE = 2
                return
            }
        }
    }
    $global:LASTEXITCODE = 0
}

function Sti-DraftSave {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory = $false, Position = 1)][AllowEmptyString()][string]$Content,
        # Piped content binds here, never to -Content: one parameter taking both
        # an argument and the pipeline fails to bind the pipeline when both are
        # given. With both, the argument wins and the pipeline is ignored, as
        # in lib/draft.sh.
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, DontShow = $true)][AllowEmptyString()][AllowNull()][object]$InputObject
    )
    begin {
        $parts = New-Object System.Collections.Generic.List[string]
        $haveContent = $PSBoundParameters.ContainsKey('Content')
        if ($haveContent) { $parts.Add($Content) }
        $fromArgument = $haveContent
    }
    process {
        # Runs once per piped item, and not at all for an empty pipeline.
        if (-not $fromArgument -and $PSBoundParameters.ContainsKey('InputObject')) {
            $parts.Add([string]$InputObject)
            $haveContent = $true
        }
    }
    end {
        # Persist the content to <path>, creating the self-ignoring scratch
        # dir. Pipe the content in (no quoting needed), or pass it as the
        # second argument (the original form, kept for compatibility).
        if ([string]::IsNullOrEmpty($Path) -or (-not $haveContent -and -not $MyInvocation.ExpectingInput)) {
            # No content argument and no pipeline at all: a usage error, as in
            # lib/draft.sh, never an empty write over an existing draft. (An
            # empty pipeline still counts as input and writes an empty draft.)
            Write-Error 'Sti-DraftSave: usage: Sti-DraftSave <path> [<content>]  (or pipe the content in)'
            $global:LASTEXITCODE = 1
            return
        }
        $existing = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if (Test-StiLink $existing) {
            Write-Error "Sti-DraftSave: $Path is a symbolic link; refusing to write through it"
            $global:LASTEXITCODE = 1
            return
        }
        $text = ''
        if ($haveContent) { $text = $parts -join "`n" }
        # A bare file name lives in the current directory, which gets the same
        # Sti-DraftDir checks as any other, exactly as lib/draft.sh's
        # `dirname` returns `.` for it.
        $dir = Split-Path -Parent $Path
        if (-not $dir) { $dir = '.' }
        Sti-DraftDir $dir
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Sti-DraftSave: cannot write scratch draft: $Path"
            $global:LASTEXITCODE = 1
            return
        }
        try {
            # No trailing newline added, mirroring bash `printf '%s'`; no BOM
            # (Set-Content -Encoding UTF8 adds one on Windows PowerShell 5.1).
            # .NET resolves a relative path against the process directory, not
            # the PowerShell location, so resolve it first.
            $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            [System.IO.File]::WriteAllText($fullPath, $text, (New-Object System.Text.UTF8Encoding($false)))
            $global:LASTEXITCODE = 0
        } catch {
            Write-Error "Sti-DraftSave: cannot write scratch draft: $Path"
            $global:LASTEXITCODE = 1
        }
    }
}

function Sti-DraftLoad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path
    )
    # Emit the draft content at <path> to stdout. Errors if the file is absent.
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Error 'Sti-DraftLoad: usage: Sti-DraftLoad <path>'
        $global:LASTEXITCODE = 1
        return $null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Error "Sti-DraftLoad: no scratch draft at: $Path"
        $global:LASTEXITCODE = 1
        return $null
    }
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $global:LASTEXITCODE = 0
    Write-Output $content
}

function Sti-DraftExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path
    )
    # Predicate: $true if <path> is an existing NON-EMPTY draft, else $false.
    # A zero-length scratch is treated as "no resumable draft".
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Error 'Sti-DraftExists: usage: Sti-DraftExists <path>'
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    return ((Get-Item -LiteralPath $Path).Length -gt 0)
}

function Sti-DraftClear {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path
    )
    # Remove the scratch draft at <path>. Idempotent: no error if already gone.
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Error 'Sti-DraftClear: usage: Sti-DraftClear <path>'
        $global:LASTEXITCODE = 1
        return
    }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}
