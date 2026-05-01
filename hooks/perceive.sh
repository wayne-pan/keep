#!/usr/bin/env bash
# perceive.sh — Project state scanner (Stop hook)
# Generates ~/.claude/rules/project-state.md for next-session awareness.
# Supersedes env-bootstrap.sh (includes all its functionality + project state).
#
# Token cost: ~200 tokens/session. Value: eliminates 2-4 exploratory turns.

set -uo pipefail

RULES_DIR="$HOME/.claude/rules"
OUTPUT="$RULES_DIR/project-state.md"
mkdir -p "$RULES_DIR"

PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

_snapshot() {
  echo "## Project State (auto-generated)"
  echo "Do not edit — regenerated each session. Use for quick project awareness."
  echo ""

  # ── Environment (from env-bootstrap) ──
  echo "### Env"
  echo "- OS: $(uname -s) $(uname -r) ($(uname -m))"

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

  local pms=""
  for cmd in npm pip pip3 bun cargo yarn pnpm brew; do
    command -v "$cmd" &>/dev/null && pms="$pms $cmd"
  done
  [ -n "$pms" ] && echo "- Pkg:${pms}"

  local dev=""
  for cmd in claude rtk jq make cmake gcc gh docker; do
    command -v "$cmd" &>/dev/null && dev="$dev $cmd"
  done
  [ -n "$dev" ] && echo "- Tools:${dev}"

  local avail
  avail=$(df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2{print $4}')
  [ -n "$avail" ] && echo "- Disk: ${avail}B free"

  # ── Git state ──
  echo ""
  echo "### Git"
  if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    local branch commit dirty staged
    branch=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "?")
    commit=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
    dirty=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l)
    staged=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | wc -l)
    echo "- Branch: $branch @ $commit"
    echo "- Dirty: $dirty, Staged: $staged"

    # Recent commits (compact oneline)
    local recent
    recent=$(git -C "$PROJECT_DIR" log --oneline -5 2>/dev/null)
    if [ -n "$recent" ]; then
      echo "- Recent:"
      echo "$recent" | sed 's/^/  /'
    fi

    # Health indicators
    if [ "$dirty" -gt 20 ]; then
      echo "- Health: ⚠️ $dirty uncommitted changes"
    fi
  else
    echo "- (not a git repo)"
  fi

  # ── Project type ──
  echo ""
  echo "### Type"
  local types=""
  [ -f "$PROJECT_DIR/package.json" ] && types="$types Node"
  [ -f "$PROJECT_DIR/pyproject.toml" ] && types="$types Python"
  [ -f "$PROJECT_DIR/requirements.txt" ] && types="$types Python"
  [ -f "$PROJECT_DIR/Cargo.toml" ] && types="$types Rust"
  [ -f "$PROJECT_DIR/go.mod" ] && types="$types Go"
  [ -f "$PROJECT_DIR/pom.xml" ] && types="$types Java"
  [ -f "$PROJECT_DIR/Gemfile" ] && types="$types Ruby"
  [ -f "$PROJECT_DIR/composer.json" ] && types="$types PHP"
  [ -f "$PROJECT_DIR/mix.exs" ] && types="$types Elixir"
  [ -z "$types" ] && types=" Unknown"
  echo "-${types}"

  # ── Test status ──
  echo ""
  echo "### Tests"
  local test_result=""
  if [ -f "$PROJECT_DIR/pyproject.toml" ] && command -v pytest &>/dev/null; then
    test_result=$(cd "$PROJECT_DIR" && timeout 10 pytest --tb=no -q 2>&1 | tail -1)
  elif [ -f "$PROJECT_DIR/package.json" ] && command -v npx &>/dev/null; then
    test_result=$(cd "$PROJECT_DIR" && timeout 10 npx test --silent 2>&1 | tail -1)
  elif [ -f "$PROJECT_DIR/Makefile" ] && grep -q "^test:" "$PROJECT_DIR/Makefile" 2>/dev/null; then
    test_result=$(cd "$PROJECT_DIR" && timeout 10 make test 2>&1 | tail -1)
  fi

  if [ -n "$test_result" ]; then
    echo "- $test_result"
  else
    echo "- (no test runner detected)"
  fi

  # ── Structure ──
  echo ""
  echo "### Structure"
  echo -n "- "
  ls -1 "$PROJECT_DIR" 2>/dev/null | head -12 | tr '\n' ' '
  echo ""

  echo ""
  echo "<!-- state (auto-updated, no timestamp to preserve cache) -->"
}

_snapshot > "$OUTPUT"
exit 0
