#!/usr/bin/env bash
# audit-log.sh — PreToolUse hook for Bash
# Logs all Bash commands to audit log with timestamp, session, cwd.
# Always exits 0 (non-blocking, pure recording).
# Log location: $XDG_CACHE_HOME/claude-hooks/audit.log

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# No command — nothing to log
[ -z "$CMD" ] && exit 0

SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
TS=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-hooks"
mkdir -p "$LOG_DIR"
printf '[%s] [%s] [%s] %s\n' "$TS" "$SESSION" "$CWD" "$CMD" >> "$LOG_DIR/audit.log"

# Rotate when > 5MB
if [ -f "$LOG_DIR/audit.log" ] && [ "$(wc -c < "$LOG_DIR/audit.log")" -gt 5242880 ]; then
  mv "$LOG_DIR/audit.log" "$LOG_DIR/audit.log.old"
fi

exit 0
