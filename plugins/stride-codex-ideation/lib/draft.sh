#!/usr/bin/env bash
# stride-ideation intra-session draft autosave helpers.
#
# Pure functions used by the stride-ideation-ideate skill to persist an
# in-progress ideation draft (answered sections + round state) to a gitignored
# scratch file under .stride/, so an interruption mid-session is recoverable and
# a later session can offer to resume it:
#
#   sti_draft_path  <dir> <ts> <slug>   -> <dir>/<ts>-<slug>-draft.md
#   sti_draft_find  <dir> <slug>        -> path of the latest NON-EMPTY draft
#                                          for <slug> (any timestamp), or
#                                          non-zero if none
#   sti_draft_save  <path> [<content>]  -> writes <content> to <path>, or
#                                          stdin when <content> is omitted
#                                          (creating its scratch dir)
#   sti_draft_dir   <dir>               -> creates <dir>; when this call
#                                          created it or it is named .stride,
#                                          and <dir>/.gitignore is absent,
#                                          writes one holding `*`
#   sti_draft_load  <path>              -> emits the draft content to stdout
#   sti_draft_exists <path>             -> exit 0 if the draft exists and is
#                                          non-empty, non-zero otherwise
#   sti_draft_clear <path>              -> removes the draft (no error if gone)
#
# A PowerShell mirror lives at lib/draft.ps1 (PascalCase-with-hyphen cmdlets).
#
# Filename rule: the scratch path pairs with the eventual requirements doc by
# reusing the <ts>-<slug>-<artifact> convention from sti_unique_path, with the
# artifact token `draft`. Half-finished, possibly sensitive ideation must never
# be committed, and the user's own .gitignore is not ours to edit, so the
# scratch dir ignores itself: sti_draft_dir writes <dir>/.gitignore
# containing `*` when the file is absent and the dir is the scratch dir (this
# call created it, or it is named .stride) — an existing .gitignore is never
# touched, and none is dropped into some other pre-existing directory.
# The helper never serializes any secret — it only writes the content it is
# handed. Pass that content on stdin: arbitrary prose then needs no shell
# quoting at all.
#
# Resume keys on the SLUG, not the session timestamp: a fresh session has a new
# timestamp, so sti_draft_find looks at every <ts>-<slug>-draft.md under the
# scratch dir and returns the latest match (ISO timestamps sort lexically).
# <ts> must have the exact YYYY-MM-DDTHHMMSS shape, so a different slug never
# matches — not even one that ends in this slug (`toggle` vs
# `dark-mode-toggle`), because the slug must follow the timestamp directly.
#
# All non-error output is written to stdout. Errors go to stderr with a
# non-zero exit code. Source this file, or call functions directly via:
#   bash -c '. lib/draft.sh; sti_draft_path .stride 2026-05-12T103000 foo'

set -u

sti_draft_path() {
  local dir="${1:-}"
  local ts="${2:-}"
  local slug="${3:-}"
  if [ -z "$dir" ] || [ -z "$ts" ] || [ -z "$slug" ]; then
    echo "sti_draft_path: usage: sti_draft_path <dir> <ts> <slug>" >&2
    return 1
  fi
  printf '%s' "${dir%/}/${ts}-${slug}-draft.md"
}

sti_draft_find() {
  # Find the latest NON-EMPTY scratch draft for <slug> under <dir>, regardless
  # of session timestamp. Returns its path on stdout, or non-zero (no stdout)
  # when the directory is absent or no non-empty draft matches. Empty draft
  # files are ignored so a zero-length scratch never triggers a resume offer.
  local dir="${1:-}"
  local slug="${2:-}"
  if [ -z "$dir" ] || [ -z "$slug" ]; then
    echo "sti_draft_find: usage: sti_draft_find <dir> <slug>" >&2
    return 1
  fi
  [ -d "$dir" ] || return 1
  local latest=""
  local f
  # A draft git already tracks is never resumed: autosave would write new
  # prose into a committed file, which the next `git commit -a` would record.
  local in_repo=no
  if command -v git >/dev/null 2>&1 && [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    in_repo=yes
  fi
  # Anchor the timestamp shape (YYYY-MM-DDTHHMMSS) so the slug must follow it
  # directly: slug `toggle` never matches a `dark-mode-toggle` draft. The slug
  # is quoted, so it matches literally. With no match (and nullglob unset),
  # the loop iterates once over the literal unexpanded pattern; the
  # `[ -e "$f" ]` guard skips it.
  for f in "${dir%/}/"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]"-${slug}-draft.md"; do
    # A symbolic link is never a draft: in a repository it could point at any
    # file of the user's, which a resume would read and later overwrite.
    [ -L "$f" ] && continue
    [ -e "$f" ] || continue
    [ -s "$f" ] || continue
    if [ "$in_repo" = yes ] && git -C "$dir" ls-files --error-unmatch -- "$(basename "$f")" >/dev/null 2>&1; then
      continue
    fi
    # Bash expands globs in collation order, but compare explicitly so the
    # "latest ISO timestamp wins" contract does not depend on locale ordering.
    if [ -z "$latest" ] || [ "$f" \> "$latest" ]; then
      latest="$f"
    fi
  done
  if [ -z "$latest" ]; then
    return 1
  fi
  printf '%s' "$latest"
}

sti_draft_dir() {
  # Create the scratch dir <dir> and make it ignore itself: when
  # <dir>/.gitignore is absent and <dir> is the scratch dir — this call
  # created it, or it is named .stride — write one holding `*`, so nothing
  # under it can be committed by a later `git add`. An existing .gitignore is
  # never overwritten. lib/draft.ps1's Sti-DraftDir applies the same rule.
  #
  # Then, inside a git work tree, check the result: if a draft name in <dir>
  # would still not be ignored (an existing .gitignore there that does not
  # cover drafts), return 2 with a message and leave the user's file alone —
  # the caller turns autosave off rather than risk a commit. Symbolic links
  # are refused outright: <dir> or <dir>/.gitignore as a link would send the
  # ignore file, and the drafts, somewhere else.
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    echo "sti_draft_dir: usage: sti_draft_dir <dir>" >&2
    return 1
  fi
  if [ -L "${dir%/}" ] || [ -L "${dir%/}/.gitignore" ]; then
    echo "sti_draft_dir: $dir or its .gitignore is a symbolic link; refusing to write through it" >&2
    return 1
  fi
  local created=no
  [ -d "$dir" ] || created=yes
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "sti_draft_dir: cannot create scratch directory: $dir" >&2
    return 1
  fi
  local base
  base="$(basename "$dir")"
  if [ ! -e "$dir/.gitignore" ] && { [ "$created" = yes ] || [ "$base" = .stride ]; }; then
    if ! printf '*\n' > "$dir/.gitignore" 2>/dev/null; then
      echo "sti_draft_dir: cannot write $dir/.gitignore" >&2
      return 1
    fi
  fi
  if command -v git >/dev/null 2>&1 \
     && [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
     && ! git -C "$dir" check-ignore -q -- 0000-00-00T000000-probe-draft.md 2>/dev/null; then
    echo "sti_draft_dir: drafts in $dir would not be ignored by git ($dir/.gitignore exists but does not cover them); add a line containing * to it to enable autosave" >&2
    return 2
  fi
}

sti_draft_save() {
  # Persist the draft to <path>, creating the self-ignoring scratch dir if
  # needed. The content is <content> when given (the original argv form,
  # kept for compatibility) or stdin when <content> is omitted — stdin needs
  # no shell quoting, so it is the form to use for arbitrary prose.
  # The only side effects are that one file and sti_draft_dir's.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_save: usage: sti_draft_save <path> [<content>]  (content on stdin when omitted)" >&2
    return 1
  fi
  if [ -L "$path" ]; then
    echo "sti_draft_save: $path is a symbolic link; refusing to write through it" >&2
    return 1
  fi
  if [ "$#" -lt 2 ] && [ -t 0 ]; then
    # No content and nothing piped in: refuse rather than wait on a terminal.
    echo "sti_draft_save: usage: sti_draft_save <path> [<content>]  (content on stdin when omitted)" >&2
    return 1
  fi
  sti_draft_dir "$(dirname "$path")" || return 1
  if [ "$#" -ge 2 ]; then
    if ! printf '%s' "$2" > "$path" 2>/dev/null; then
      echo "sti_draft_save: cannot write scratch draft: $path" >&2
      return 1
    fi
  elif ! cat > "$path" 2>/dev/null; then
    echo "sti_draft_save: cannot write scratch draft: $path" >&2
    return 1
  fi
}

sti_draft_load() {
  # Emit the draft content at <path> to stdout. Errors if the file is absent.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_load: usage: sti_draft_load <path>" >&2
    return 1
  fi
  if [ ! -f "$path" ]; then
    echo "sti_draft_load: no scratch draft at: $path" >&2
    return 1
  fi
  cat "$path"
}

sti_draft_exists() {
  # Predicate: exit 0 if <path> is an existing NON-EMPTY draft, else non-zero.
  # No stdout. A zero-length scratch is treated as "no resumable draft".
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_exists: usage: sti_draft_exists <path>" >&2
    return 1
  fi
  [ -s "$path" ]
}

sti_draft_clear() {
  # Remove the scratch draft at <path>. Idempotent: no error if already gone.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_clear: usage: sti_draft_clear <path>" >&2
    return 1
  fi
  rm -f "$path"
}
