#!/usr/bin/env bash
# scope-guard.sh — PostToolUse hook: track tool budget and file drift
# Maintains /tmp/claude-scope-{session} state file.
# Injects warnings via additionalContext (non-blocking).

set -uo pipefail

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // empty' | head -c 500)

# State file
STATE_FILE="/tmp/claude-scope-${SESSION_ID}"
SOFT_BUDGET=30
HARD_BUDGET=80
DRIFT_THRESHOLD=10

# Increment turn counter
count=0
files_touched=""
if [ -f "$STATE_FILE" ]; then
  count=$(grep '^count=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
  files_touched=$(grep '^files=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-)
fi

count=$((count + 1))

# Track unique files
if [ -n "$FILE_PATH" ] && [ "$FILE_PATH" != "null" ]; then
  # Extract actual file path from commands like "cat foo.py"
  actual_file=$(echo "$FILE_PATH" | grep -oP '[\w./_-]+\.\w+' | head -1)
  if [ -n "$actual_file" ] && echo "$files_touched" | grep -qvF "$actual_file"; then
    [ -n "$files_touched" ] && files_touched="$files_touched|$actual_file" || files_touched="$actual_file"
  fi
fi

# Count unique files
file_count=0
if [ -n "$files_touched" ]; then
  file_count=$(echo "$files_touched" | tr '|' '\n' | sort -u | wc -l)
fi

# Save state
cat > "$STATE_FILE" << STATE
count=$count
files=$files_touched
STATE

# Build warning message
msg=""

# Budget warnings
if [ "$count" -ge "$HARD_BUDGET" ]; then
  msg="[Scope] ⛔ Turn $count/$HARD_BUDGET. Files: $file_count. HARD LIMIT reached. STOP, summarize progress, suggest fresh session."
elif [ "$count" -ge "$SOFT_BUDGET" ]; then
  msg="[Scope] ⚠️ Turn $count/$HARD_BUDGET. Files: $file_count. Soft budget passed — compress context, narrow focus."
fi

# Drift detection
if [ "$file_count" -ge "$DRIFT_THRESHOLD" ] && [ "$count" -lt "$HARD_BUDGET" ]; then
  if [ -n "$msg" ]; then
    msg="$msg "
  fi
  msg="${msg}[Drift] ⚠️ $file_count files touched — scope expanding. Consider: split task or delegate to Agent subagent."
fi

# Output
if [ -n "$msg" ]; then
  jq -n --arg msg "$msg" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $msg
    }
  }'
fi

exit 0
