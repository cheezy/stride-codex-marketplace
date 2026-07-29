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
mkdir -p \
  "$INSTALL_DIR/skills" \
  "$INSTALL_DIR/agents" \
  "$INSTALL_DIR/lib" \
  "$INSTALL_DIR/fixtures"

# Clone to a temp directory; clean up on exit regardless of success/failure.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading from $REPO..."
git clone --quiet --depth 1 "$REPO" "$TMPDIR/stride-codex-ideation"

# Copy skills (each skill is a directory with SKILL.md).
echo "Installing 3 skills..."
for skill_dir in "$TMPDIR/stride-codex-ideation/skills"/*/; do
  skill_name=$(basename "$skill_dir")
  mkdir -p "$INSTALL_DIR/skills/$skill_name"
  cp "$skill_dir/SKILL.md" "$INSTALL_DIR/skills/$skill_name/SKILL.md"
done

# Copy agents (each agent is a bare .md file per Codex naming convention).
echo "Installing 2 agents..."
cp "$TMPDIR/stride-codex-ideation/agents/"*.md "$INSTALL_DIR/agents/"

# Copy lib/ helpers (.sh, .ps1, .py). Use cp -a to preserve the executable
# bit on the .sh files — the stridify skill body and the smoke test invoke
# them directly.
echo "Installing lib/ helpers..."
cp -a "$TMPDIR/stride-codex-ideation/lib/." "$INSTALL_DIR/lib/"

# Copy fixtures. Required by lib/run_smoke_test.sh and by the calibration
# references the README and SMOKE-TEST-NOTE.md point at.
echo "Installing fixtures..."
cp -a "$TMPDIR/stride-codex-ideation/fixtures/." "$INSTALL_DIR/fixtures/"

# Copy AGENTS.md to the destination (project root in project mode, or the
# global install dir in global mode). Preserve any existing user-authored
# AGENTS.md by confining our content to an idempotent, clearly delimited
# managed block -- mirrors the stride-opencode-ideation installer exactly:
# a fresh file is created with the block; an existing file keeps ALL of its
# content and only the block is inserted or refreshed in place, so re-running
# the installer never clobbers the user's own notes and never duplicates the
# guidance.
SRC_AGENTS="$TMPDIR/stride-codex-ideation/AGENTS.md"
if [ "$MODE" = "project" ]; then
  DEST_AGENTS="./AGENTS.md"
else
  DEST_AGENTS="$INSTALL_DIR/AGENTS.md"
fi

BEGIN_MARKER="<!-- BEGIN stride-ideation -->"
END_MARKER="<!-- END stride-ideation -->"
NOTE_MARKER="<!-- Managed by the stride-codex-ideation installer; content between these markers is regenerated on each install. Add your own notes outside this block. -->"

# Build the managed block (markers fence the bundle content). Use a temp file
# so the destination is never read as a script -- we only ever pattern-match it.
MANAGED_BLOCK="$(mktemp)"
{
  printf '%s\n' "$BEGIN_MARKER"
  printf '%s\n' "$NOTE_MARKER"
  cat "$SRC_AGENTS"
  printf '%s\n' "$END_MARKER"
} > "$MANAGED_BLOCK"

# Locate a WELL-FORMED managed block: the first BEGIN marker line and the first
# END marker line, where END follows BEGIN. Only a well-formed pair triggers an
# in-place refresh -- an orphaned or malformed marker (e.g. BEGIN with no END)
# must NEVER truncate user content, so it falls through to the append path.
# `|| true` keeps a no-match grep (exit 1) from tripping `set -euo pipefail`.
BEGIN_LINE=""
END_LINE=""
if [ -f "$DEST_AGENTS" ]; then
  BEGIN_LINE="$(grep -nxF "$BEGIN_MARKER" "$DEST_AGENTS" | head -1 | cut -d: -f1 || true)"
  END_LINE="$(grep -nxF "$END_MARKER" "$DEST_AGENTS" | head -1 | cut -d: -f1 || true)"
fi

if [ ! -f "$DEST_AGENTS" ]; then
  cp "$MANAGED_BLOCK" "$DEST_AGENTS"
  echo "Created AGENTS.md at $DEST_AGENTS"
elif [ -n "$BEGIN_LINE" ] && [ -n "$END_LINE" ] && [ "$END_LINE" -gt "$BEGIN_LINE" ]; then
  UPDATED="$(mktemp)"
  {
    head -n "$((BEGIN_LINE - 1))" "$DEST_AGENTS"
    cat "$MANAGED_BLOCK"
    tail -n "+$((END_LINE + 1))" "$DEST_AGENTS"
  } > "$UPDATED"
  mv "$UPDATED" "$DEST_AGENTS"
  echo "Updated the stride-ideation managed block in $DEST_AGENTS (your content preserved)"
else
  [ -s "$DEST_AGENTS" ] && [ -n "$(tail -c1 "$DEST_AGENTS")" ] && printf '\n' >> "$DEST_AGENTS"
  printf '\n' >> "$DEST_AGENTS"
  cat "$MANAGED_BLOCK" >> "$DEST_AGENTS"
  echo "Appended the stride-ideation managed block to $DEST_AGENTS (your content preserved)"
fi
rm -f "$MANAGED_BLOCK"

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
echo "  Helpers:  $(ls "$INSTALL_DIR/lib/" 2>/dev/null | wc -l | tr -d ' ') files in lib/"
echo "  Fixtures: $(ls "$INSTALL_DIR/fixtures/" 2>/dev/null | wc -l | tr -d ' ') files in fixtures/"
echo ""
echo "Next steps:"
echo "  1. Create .stride_auth.md in your project root with your Stride API"
echo "     credentials (see the README). Required only for stride-ideation-stridify."
echo "  2. Add .stride_auth.md to .gitignore — it contains a secret."
echo "  3. Activate the stride-ideation-ideate skill to drive an ideation session."
