#!/usr/bin/env bash
# mem-record.sh — Record tool usage as observations (PostToolUse hook)
# Appends to ~/.mind/observations.jsonl

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty' | head -c 500)

if [ -z "$TOOL" ]; then
  exit 0
fi

# Skip trivial tools to avoid noise
case "$TOOL" in
  Bash|Read|Edit|Write|Glob|Grep) ;;
  *) exit 0 ;;  # Only record core tool usage
esac

# Extract command/file for filtering and recording
COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // .file_path // .pattern // .query // empty' | head -c 200)

# Skip if no meaningful content
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Skip trivial Bash commands
if [ "$TOOL" = "Bash" ]; then
  case "$COMMAND" in
    ls*|pwd|whoami|hostname|echo*|true|:*) exit 0 ;;
  esac
  # Skip if command is <5 chars (likely trivial)
  if [ ${#COMMAND} -lt 5 ]; then
    exit 0
  fi
fi

MEM_DIR="$HOME/.mind"
mkdir -p "$MEM_DIR"

# Build JSONL entry (deterministic — no LLM needed)
EPOCH=$(date +%s%3N 2>/dev/null || date +%s000)
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")

# Capture active file for encoding specificity
ACTIVE_FILE=$(echo "$TOOL_INPUT" | jq -r '.file_path // .pattern // empty' | head -c 200)

# Build JSON using jq for safety
jq -n \
  --arg epoch "$EPOCH" \
  --arg session "$SESSION_ID" \
  --arg project "$PROJECT" \
  --arg tool "$TOOL" \
  --arg cmd "$COMMAND" \
  --arg af "$ACTIVE_FILE" \
  '{
    epoch: ($epoch | tonumber),
    session_id: $session,
    project: $project,
    type: "tool-usage",
    title: ($tool + ": " + ($cmd | split("\n")[0])),
    narrative: "",
    facts: [],
    concepts: [$tool],
    files_read: [],
    files_modified: [],
    context_tags: {active_file: $af, tool: $tool}
  }' >> "$MEM_DIR/observations.jsonl"

# Working memory: fast /tmp buffer for zero-latency recall
WM_FILE="/tmp/claude-wm-${CLAUDE_SESSION_ID:-default}.jsonl"
jq -n \
  --arg epoch "$EPOCH" \
  --arg tool "$TOOL" \
  --arg cmd "$COMMAND" \
  '{id: 0, title: ($tool + ": " + ($cmd | split("\n")[0])), summary: "", salience: 0.5, epoch: ($epoch | tonumber)}' \
  >> "$WM_FILE" 2>/dev/null

exit 0
