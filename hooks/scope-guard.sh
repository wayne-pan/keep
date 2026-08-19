#!/usr/bin/env bash
# scope-guard.sh — PostToolUse hook: track tool budget, file drift, and tool loops
# Maintains ${SCOPE_STATE_DIR:-/tmp}/claude-scope-{session} state file.
# Injects warnings via additionalContext (non-blocking).

set -uo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // empty' | head -c 500)

# State file
STATE_FILE="${SCOPE_STATE_DIR:-/tmp}/claude-scope-${SESSION_ID}"
# Symlinked state file = /tmp pre-create attack; refuse read AND write
[ -L "$STATE_FILE" ] && exit 0
SOFT_BUDGET=30
DRIFT_THRESHOLD=10
LOOP_THRESHOLD=3          # ECC parity: 3+ consecutive identical calls = stuck
COMPACT_HINT_AT=25        # 5-turn runway before SOFT_BUDGET bites

# Increment turn counter
count=0
files_touched=""
last_hash=""
loop_n=0
compact_hint=0
if [ -f "$STATE_FILE" ]; then
  count=$(grep '^count=' "$STATE_FILE" 2>/dev/null | cut -d= -f2); count=${count:-0}
  files_touched=$(grep '^files=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-); files_touched=${files_touched:-}
  last_hash=$(grep '^last_hash=' "$STATE_FILE" 2>/dev/null | cut -d= -f2); last_hash=${last_hash:-}
  loop_n=$(grep '^loop_n=' "$STATE_FILE" 2>/dev/null | cut -d= -f2); loop_n=${loop_n:-0}
  compact_hint=$(grep '^compact_hint=' "$STATE_FILE" 2>/dev/null | cut -d= -f2); compact_hint=${compact_hint:-0}
fi

count=$((count + 1))

# Tool loop detection: hash tool_name + tool_input (response excluded — retries differ)
CALL_SIG=$(printf '%s' "$INPUT" | jq -Sc '{t:.tool_name, i:.tool_input}' | sha256sum | cut -c1-12)
if [ -n "$last_hash" ] && [ "$CALL_SIG" = "$last_hash" ]; then
  loop_n=$((loop_n + 1))
else
  loop_n=1
fi

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

# Build warning message
msg=""

# Loop warning (takes precedence in position; budget/drift append)
if [ "$loop_n" -ge "$LOOP_THRESHOLD" ]; then
  msg="[Loop] ⚠️ ${loop_n} consecutive identical calls — stuck. Change approach or escalate to user."
fi

# One-shot compact suggestion at a logical boundary (before soft budget bites)
if [ "$count" -ge "$COMPACT_HINT_AT" ] && [ "$compact_hint" != "1" ]; then
  msg="${msg:+$msg }[Compact] 💡 Turn $count — logical boundary. Consider /compact before the next phase."
  compact_hint=1
fi

# Budget warnings
if [ "$count" -ge "$SOFT_BUDGET" ]; then
  msg="${msg:+$msg }[Scope] ⚠️ Turn $count/$SOFT_BUDGET. Files: $file_count. Soft budget passed — compress context, narrow focus."
fi

# Drift detection
if [ "$file_count" -ge "$DRIFT_THRESHOLD" ]; then
  if [ -n "$msg" ]; then
    msg="$msg "
  fi
  msg="${msg}[Drift] ⚠️ $file_count files touched — scope expanding. Consider: split task or delegate to Agent subagent."
fi

# Save state (after msg build — one-shot flags mutated above must persist)
cat > "$STATE_FILE" << STATE
count=$count
files=$files_touched
last_hash=$CALL_SIG
loop_n=$loop_n
compact_hint=$compact_hint
STATE

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
