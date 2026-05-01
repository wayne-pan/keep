#!/usr/bin/env bash
# checkpoint.sh — PreToolUse hook: auto-checkpoint before risky operations
# Creates git stash when working tree is dirty and command is high-risk.
# Non-blocking — just creates a safety net the LLM can use to rollback.

set -uo pipefail

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' | head -c 2000)
[[ -z "$COMMAND" ]] && exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')

# Check if inside a git repo
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# High-risk command patterns
risky=false
case "$COMMAND" in
  "rm "*|*\ rm\ *|*\ rm|rmdir*|*"rm -"*|*\ rm\ -*) risky=true ;;
  *git\ reset*|*git\ checkout\ --*) risky=true ;;
  *DROP\ *|*TRUNCATE\ *|*DELETE\ FROM*) risky=true ;;
  *pip\ install*|*pip3\ install*|*npm\ install*) risky=true ;;
  *docker\ rm*|*docker\ rmi*|*kubectl\ apply*|*kubectl\ delete*) risky=true ;;
esac

[[ "$risky" == "false" ]] && exit 0

# Check if working tree has uncommitted changes
dirty=$(git status --porcelain 2>/dev/null | wc -l)
[ "$dirty" -eq 0 ] && exit 0

# Check if we already checkpointed recently (avoid spam)
CHECKPOINT_FILE="/tmp/claude-checkpoint-${SESSION_ID}"
if [ -f "$CHECKPOINT_FILE" ]; then
  last_ts=$(cat "$CHECKPOINT_FILE" 2>/dev/null)
  now=$(date +%s)
  # Skip if last checkpoint was < 60s ago
  [ $((now - last_ts)) -lt 60 ] && exit 0
fi

# Create checkpoint
result=$(git stash push -m "auto-checkpoint-$(date +%Y%m%d-%H%M%S)" 2>&1) || true

if echo "$result" | grep -q "Saved working directory"; then
  # Record timestamp
  date +%s > "$CHECKPOINT_FILE"

  jq -n --arg msg "[Checkpoint] Auto-stash created before risky operation. Rollback with: git stash pop" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": $msg
    }
  }'
fi

exit 0
