#!/usr/bin/env bash
# env-bootstrap.sh — Generate compact environment snapshot for session-start injection
# Registered as Stop hook: writes snapshot to ~/.claude/rules/env-snapshot.md
# That file is auto-loaded at every session start as a rules file.
#
# Inspired by Meta-Harness paper (arxiv 2603.28052):
#   "Pre-run shell command to snapshot environment eliminates 2-4 exploratory turns"
#   Especially effective for tool-specific tasks (bioinformatics, rendering, crypto)
#
# Token cost: ~150 tokens/session. Value: saves 2-4 turns × ~500 tokens each.

set -uo pipefail

RULES_DIR="$HOME/.claude/rules"
OUTPUT_FILE="$RULES_DIR/env-snapshot.md"
mkdir -p "$RULES_DIR"

# Detect project directory
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

_snapshot() {
  echo "## Environment Snapshot (auto-generated)"
  echo "Do not edit — regenerated each session. Use for quick environment awareness."
  echo ""

  # OS
  echo "- OS: $(uname -s) $(uname -r) ($(uname -m))"

  # Shell
  local shell_ver=""
  if [ -n "${BASH_VERSION:-}" ]; then shell_ver="bash $BASH_VERSION"
  elif [ -n "${ZSH_VERSION:-}" ]; then shell_ver="zsh $ZSH_VERSION"
  else shell_ver="${SHELL##*/}"
  fi
  echo "- Shell: $shell_ver"

  # Languages (version only, compact)
  local langs=""
  _ver() {
    local v
    v=$(command -v "$1" &>/dev/null && { "$@" 2>/dev/null; } | head -1 | grep -oP '[\d]+\.[\d]+[\d.]*' | head -1)
    [ -n "$v" ] && langs="$langs $1:$v"
  }
  _ver python3 --version; _ver node --version; _ver bun --version
  _ver go version; _ver rustc --version; _ver java --version
  _ver ruby --version; _ver php --version; _ver deno --version
  [ -n "$langs" ] && echo "- Languages:${langs}"

  # Package managers
  local pms=""
  for cmd in npm pip pip3 bun cargo yarn pnpm brew; do
    command -v "$cmd" &>/dev/null && pms="$pms $cmd"
  done
  [ -n "$pms" ] && echo "- Pkg managers:${pms}"

  # Dev tools
  local dev=""
  for cmd in claude mx gh docker kubectl terraform jq yq sqlite3 make cmake gcc; do
    command -v "$cmd" &>/dev/null && dev="$dev $cmd"
  done
  [ -n "$dev" ] && echo "- Dev tools:${dev}"

  # Project info
  if [ -d "$PROJECT_DIR/.git" ]; then
    local branch commit
    branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    commit=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
    echo "- Project: $(basename "$PROJECT_DIR") ($branch @ $commit)"
  else
    echo "- Project: $(basename "$PROJECT_DIR")"
  fi

  # Top-level structure (max 15 entries)
  echo -n "- Structure: "
  ls -1 "$PROJECT_DIR" 2>/dev/null | head -15 | tr '\n' ' '
  echo ""

  # Disk
  local avail
  avail=$(df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2{print $4}')
  [ -n "$avail" ] && echo "- Disk: ${avail}B free"

  echo ""
  echo "<!-- snapshot (auto-updated, no timestamp to preserve cache) -->"
}

_snapshot > "$OUTPUT_FILE"

exit 0
