#!/usr/bin/env bash
# install.sh — Install Stride ideation skills and agents for Codex CLI
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex-ideation/main/install.sh | bash
#
# Or clone and run locally:
#   ./install.sh
#
# Installs globally to ~/.agents/ so skills and agents are available in all projects.
# Use --project to install into the current project directory instead.
#
# Layout: skills/ and agents/ go where Codex discovers them; the lib/ helpers
# and fixtures/ go under a directory of their own, <install-dir>/stride-codex-ideation/,
# so no other tool installing into the same .agents/ can overwrite them. That
# directory is the plugin's helper root: it is cleared and rewritten on every
# install, so files dropped by a newer release disappear. Nothing outside it is
# ever deleted.
#
# INSTALL_SOURCE_DIR=<checkout> installs from a local checkout instead of
# cloning (used by lib/test-install.sh so the tests run offline).

set -euo pipefail

REPO="https://github.com/cheezy/stride-codex-ideation.git"
GLOBAL_DIR="$HOME/.agents"
MODE="global"

for arg in "$@"; do
  case "$arg" in
    --project) MODE="project" ;;
    --help|-h)
      echo "Usage: install.sh [--project]"
      echo ""
      echo "  (default)   Install globally to ~/.agents/ (available in all projects)"
      echo "  --project   Install to .agents/ in the current directory"
      exit 0
      ;;
  esac
done

if [ "$MODE" = "project" ]; then
  INSTALL_DIR=".agents"
  echo "Installing Stride Ideation for Codex CLI into .agents/ (project-local)..."
else
  INSTALL_DIR="$GLOBAL_DIR"
  echo "Installing Stride Ideation for Codex CLI into ~/.agents/ (global)..."
fi

# Create destination directories. The ideation plugin ships skills, agents,
# lib/ helpers (referenced by the stridify skill), and fixtures (calibration
# references documented in fixtures/README.md and exercised by the smoke
# test suite).
HELPER_ROOT="$INSTALL_DIR/stride-codex-ideation"

# In project mode the install directory lives in a repository the user may not
# control. A committed symlink there (.agents -> .., say) would redirect every
# write -- and the helper-root clear below -- outside the project, so refuse
# unless .agents and its skills/ and agents/ are real directories where they
# appear to be.
if [ "$MODE" = "project" ]; then
  for d in .agents .agents/skills .agents/agents; do
    if [ -L "$d" ]; then
      echo "Error: $d is a symbolic link; refusing to install through it. Replace it with a real directory." >&2
      exit 1
    fi
  done
  if [ -d .agents ] && [ "$(cd .agents && pwd -P)" != "$(pwd -P)/.agents" ]; then
    echo "Error: .agents does not resolve to $(pwd -P)/.agents; refusing to install through it." >&2
    exit 1
  fi
fi

mkdir -p \
  "$INSTALL_DIR/skills" \
  "$INSTALL_DIR/agents"

# Clone to a temp directory; clean up on exit regardless of success/failure.
# SRC is the plugin source; INSTALL_SOURCE_DIR points it at a local checkout.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if [ -n "${INSTALL_SOURCE_DIR:-}" ]; then
  SRC="$INSTALL_SOURCE_DIR"
  echo "Installing from local checkout $SRC..."
else
  SRC="$TMPDIR/stride-codex-ideation"
  echo "Downloading from $REPO..."
  git clone --quiet --depth 1 "$REPO" "$SRC"
fi

# Copy skills (each skill is a directory with SKILL.md).
echo "Installing 3 skills..."
# An existing link at a destination is removed, never written through.
for skill_dir in "$SRC/skills"/*/; do
  skill_name=$(basename "$skill_dir")
  dest_skill="$INSTALL_DIR/skills/$skill_name"
  [ -L "$dest_skill" ] && rm -f -- "$dest_skill"
  mkdir -p "$dest_skill"
  rm -f -- "$dest_skill/SKILL.md"
  cp "$skill_dir/SKILL.md" "$dest_skill/SKILL.md"
done

# Copy agents (each agent is a bare .md file per Codex naming convention).
echo "Installing 2 agents..."
for agent_file in "$SRC/agents/"*.md; do
  rm -f -- "$INSTALL_DIR/agents/$(basename "$agent_file")"
  cp "$agent_file" "$INSTALL_DIR/agents/"
done

# Clear the namespaced helper root, then recreate it, so files a newer release
# no longer ships do not linger. HELPER_ROOT is always <install-dir>/
# stride-codex-ideation — this plugin's own directory — so nothing else is
# ever removed. A helper root that is itself a link (to a dev checkout, say)
# is removed as a link -- its target is never touched, so there is nothing to
# guard. Otherwise refuse when the source checkout is that directory or lives
# inside it (links resolved): clearing it would delete what is about to be
# copied. install.ps1 takes the same two branches.
if [ -L "$HELPER_ROOT" ]; then
  rm -f -- "$HELPER_ROOT"
elif [ -d "$HELPER_ROOT" ]; then
  SRC_REAL="$(cd "$SRC" && pwd -P)"
  HELPER_REAL="$(cd "$HELPER_ROOT" && pwd -P)"
  case "$SRC_REAL/" in
    "$HELPER_REAL/"*)
      echo "Error: the source checkout $SRC is inside the install target $HELPER_ROOT; install from a separate checkout." >&2
      exit 1
      ;;
  esac
  rm -rf -- "$HELPER_ROOT"
fi
mkdir -p "$HELPER_ROOT/lib" "$HELPER_ROOT/fixtures" "$HELPER_ROOT/agents"

# Copy lib/ helpers (.sh, .ps1, .py). Use cp -a to preserve the executable
# bit on the .sh files — the stridify skill body and the smoke test invoke
# them directly.
echo "Installing lib/ helpers..."
cp -a "$SRC/lib/." "$HELPER_ROOT/lib/"

# Copy fixtures. Required by lib/run_smoke_test.sh and by the calibration
# references the README and SMOKE-TEST-NOTE.md point at.
echo "Installing fixtures..."
cp -a "$SRC/fixtures/." "$HELPER_ROOT/fixtures/"

# A second copy of the agent files beside the helpers: the skills locate an
# agent's instructions at <helper root>/agents/<name>.md, the same relative
# path a marketplace plugin directory has, so one lookup serves every install.
cp "$SRC/agents/"*.md "$HELPER_ROOT/agents/"

# Copy AGENTS.md to the destination (project root in project mode, or the
# global install dir in global mode). Preserve any existing user-authored
# AGENTS.md by confining our content to an idempotent, clearly delimited
# managed block -- mirrors the stride-opencode-ideation installer exactly:
# a fresh file is created with the block; an existing file keeps ALL of its
# content and only the block is inserted or refreshed in place, so re-running
# the installer never clobbers the user's own notes and never duplicates the
# guidance.
SRC_AGENTS="$SRC/AGENTS.md"
if [ "$MODE" = "project" ]; then
  DEST_AGENTS="./AGENTS.md"
else
  DEST_AGENTS="$INSTALL_DIR/AGENTS.md"
fi

# Never write through a symbolic link: a project's AGENTS.md could point at any
# file the user can write (a shell rc file, say). -L also catches a dangling
# link, which `cp` would otherwise follow to create its target.
if [ -L "$DEST_AGENTS" ]; then
  echo "Error: $DEST_AGENTS is a symbolic link; refusing to write through it. Replace it with a regular file, or add the managed block by hand." >&2
  exit 1
fi

BEGIN_MARKER="<!-- BEGIN stride-ideation -->"
END_MARKER="<!-- END stride-ideation -->"
NOTE_MARKER="<!-- Managed by the stride-codex-ideation installer; content between these markers is regenerated on each install. Add your own notes outside this block. -->"

# Build the managed block (markers fence the bundle content). Use a temp file
# so the destination is never read as a script -- we only ever pattern-match it.
# The bundle is copied verbatim; a missing final newline is supplied so the END
# marker always starts its own line. install.ps1 builds the identical bytes.
MANAGED_BLOCK="$(mktemp)"
{
  printf '%s\n' "$BEGIN_MARKER"
  printf '%s\n' "$NOTE_MARKER"
  cat "$SRC_AGENTS"
  [ -s "$SRC_AGENTS" ] && [ -n "$(tail -c1 "$SRC_AGENTS")" ] && printf '\n'
  printf '%s\n' "$END_MARKER"
} > "$MANAGED_BLOCK"

# Locate a WELL-FORMED managed block: markers count only as whole lines (exact,
# case-sensitive; a CRLF line ending is allowed, so a block checked out with
# Windows line endings is still refreshed rather than duplicated), and the
# block is the first END line paired with the nearest
# BEGIN line before it -- the first BEGIN/END pair with no other marker between.
# Only such a pair triggers an in-place refresh. An orphaned or out-of-order
# marker (BEGIN with no END, END before any BEGIN, a marker quoted mid-line)
# must NEVER truncate user content, so it falls through to the append path --
# and because the appended block is then the first adjacent pair, a re-run
# refreshes that block instead of appending another. install.ps1 locates the
# block identically.
BEGIN_LINE=""
END_LINE=""
if [ -f "$DEST_AGENTS" ]; then
  # LC_ALL=C: compare bytes, so a file in a legacy encoding cannot make a
  # multibyte-aware awk abort mid-scan.
  PAIR="$(LC_ALL=C awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { open = NR; next }
    line == e && open { print open " " NR; exit }
  ' "$DEST_AGENTS")"
  if [ -n "$PAIR" ]; then
    BEGIN_LINE="${PAIR%% *}"
    END_LINE="${PAIR##* }"
  fi
fi

if [ ! -f "$DEST_AGENTS" ]; then
  cp "$MANAGED_BLOCK" "$DEST_AGENTS"
  echo "Created AGENTS.md at $DEST_AGENTS"
elif [ -n "$BEGIN_LINE" ] && [ -n "$END_LINE" ]; then
  UPDATED="$(mktemp)"
  {
    # BSD head rejects -n 0, so a block on line 1 has no prefix to copy.
    [ "$BEGIN_LINE" -gt 1 ] && head -n "$((BEGIN_LINE - 1))" "$DEST_AGENTS"
    cat "$MANAGED_BLOCK"
    tail -n "+$((END_LINE + 1))" "$DEST_AGENTS"
  } > "$UPDATED"
  mv "$UPDATED" "$DEST_AGENTS"
  echo "Updated the stride-ideation managed block in $DEST_AGENTS (your content preserved)"
else
  # Separate the block from existing content by one blank line; an empty
  # file gets the block alone.
  if [ -s "$DEST_AGENTS" ]; then
    [ -n "$(tail -c1 "$DEST_AGENTS")" ] && printf '\n' >> "$DEST_AGENTS"
    printf '\n' >> "$DEST_AGENTS"
  fi
  cat "$MANAGED_BLOCK" >> "$DEST_AGENTS"
  echo "Appended the stride-ideation managed block to $DEST_AGENTS (your content preserved)"
fi
rm -f "$MANAGED_BLOCK"

# Releases before the namespaced layout copied the helpers straight into
# <install-dir>/lib and <install-dir>/fixtures. Those shared directories may
# hold other tools' files, so they are never deleted here -- only pointed out.
if [ -f "$INSTALL_DIR/lib/filename.sh" ] && [ -f "$INSTALL_DIR/lib/validate_batch.py" ]; then
  echo ""
  echo "Note: an earlier release installed helpers into $INSTALL_DIR/lib and"
  echo "$INSTALL_DIR/fixtures. They are no longer used; remove them by hand if no"
  echo "other tool needs them."
fi

if [ "$MODE" != "project" ]; then
  echo ""
  echo "Note: Copy the managed block from ~/.agents/AGENTS.md into each project's"
  echo "AGENTS.md, or run this installer with --project from the project root."
fi

echo ""
echo "Stride Ideation for Codex CLI installed successfully!"
echo ""
echo "Installed:"
echo "  Skills:   $(ls "$INSTALL_DIR/skills/" | wc -l | tr -d ' ') skills"
echo "  Agents:   $(ls "$INSTALL_DIR/agents/"*.md 2>/dev/null | wc -l | tr -d ' ') agents"
echo "  Helpers:  $(ls "$HELPER_ROOT/lib/" 2>/dev/null | wc -l | tr -d ' ') files in lib/"
echo "  Fixtures: $(ls "$HELPER_ROOT/fixtures/" 2>/dev/null | wc -l | tr -d ' ') files in fixtures/"
echo "  Helper root: $(cd "$HELPER_ROOT" && pwd)"
echo ""
echo "Next steps:"
echo "  1. Create .stride_auth.md in your project root with your Stride API"
echo "     credentials (see the README). Required only for stride-ideation-stridify."
echo "  2. Add .stride_auth.md to .gitignore — it contains a secret."
echo "  3. Activate the stride-ideation-ideate skill to drive an ideation session."
