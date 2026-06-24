#!/usr/bin/env bash
# install.sh — Install Stride skills and agents for Codex CLI
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cheezy/stride-codex/main/install.sh | bash
#
# Or clone and run locally:
#   ./install.sh
#
# Installs globally to ~/.agents/ so skills and agents are available in all projects.
# Use --project to install into the current project directory instead.

set -euo pipefail

REPO="https://github.com/cheezy/stride-codex.git"
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
  echo "Installing Stride for Codex CLI into .agents/ (project-local)..."
else
  INSTALL_DIR="$GLOBAL_DIR"
  echo "Installing Stride for Codex CLI into ~/.agents/ (global)..."
fi

# Require git before touching the filesystem (mirrors install.ps1).
if ! command -v git > /dev/null 2>&1; then
  echo "Error: git not found. Install git and re-run." >&2
  exit 1
fi

# Create directories
mkdir -p "$INSTALL_DIR/skills" "$INSTALL_DIR/agents"

# Clone to temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading from $REPO..."
git clone --quiet --depth 1 "$REPO" "$TMPDIR/stride-codex"

# Copy skills (each skill is a directory with SKILL.md)
skill_count=$(find "$TMPDIR/stride-codex/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "Installing $skill_count skills..."
for skill_dir in "$TMPDIR/stride-codex/skills"/*/; do
  skill_name=$(basename "$skill_dir")
  mkdir -p "$INSTALL_DIR/skills/$skill_name"
  cp "$skill_dir/SKILL.md" "$INSTALL_DIR/skills/$skill_name/SKILL.md"
done

# Copy agents (each agent is a bare .md file, per Codex naming convention)
agent_count=$(find "$TMPDIR/stride-codex/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
echo "Installing $agent_count agents..."
cp "$TMPDIR/stride-codex/agents/"*.md "$INSTALL_DIR/agents/"

# Copy AGENTS.md to project root if --project, or to global dir
if [ "$MODE" = "project" ]; then
  cp "$TMPDIR/stride-codex/AGENTS.md" ./AGENTS.md
  echo "Copied AGENTS.md to project root"
else
  cp "$TMPDIR/stride-codex/AGENTS.md" "$INSTALL_DIR/AGENTS.md"
  echo "Copied AGENTS.md to $INSTALL_DIR/"
  echo ""
  echo "Note: Copy AGENTS.md to each project that uses Stride:"
  echo "  cp ~/.agents/AGENTS.md ./AGENTS.md"
fi

echo ""
echo "Stride for Codex CLI installed successfully!"
echo ""
echo "Installed:"
echo "  Skills: $(ls "$INSTALL_DIR/skills/" | wc -l | tr -d ' ') skills"
echo "  Agents: $(ls "$INSTALL_DIR/agents/"*.md 2>/dev/null | wc -l | tr -d ' ') agents"
echo ""
echo "Next steps:"
echo "  1. Create .stride_auth.md with your API credentials (see README)"
echo "  2. Create .stride.md with your hook commands"
echo "  3. Add .stride_auth.md to .gitignore"
