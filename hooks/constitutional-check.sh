#!/usr/bin/env bash
# constitutional-check.sh — PostToolUse hook for Read on constitutional files.
# Compares SHA256 hash, warns on mismatch (does not block).
#
# Installed as PostToolUse hook in settings.json.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check Read operations on constitutional files
[ "$TOOL" != "Read" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HASH_FILE="$PROJECT_DIR/.claude/hashes.json"

# Check if this is a constitutional file
CONSTITUTIONAL_FILES=("CLAUDE.md" "rules/core.md" "hooks/safety-guard.sh")
is_constitutional=false
for cf in "${CONSTITUTIONAL_FILES[@]}"; do
  if [ "$FILE_PATH" = "$PROJECT_DIR/$cf" ] || echo "$FILE_PATH" | grep -q "/$cf$"; then
    is_constitutional=true
    rel_path="$cf"
    break
  fi
done

[ "$is_constitutional" = false ] && exit 0
[ ! -f "$HASH_FILE" ] && exit 0

# Compare hash
stored=$(jq -r ".[\"$rel_path\"] // empty" "$HASH_FILE" 2>/dev/null)
[ -z "$stored" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

current=$(sha256sum "$FILE_PATH" | cut -d' ' -f1)

if [ "$current" != "$stored" ]; then
  jq -n --arg file "$rel_path" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("[constitutional] WARNING: " + $file + " has been modified since last hash snapshot. If intentional, run: hash-snapshot update")
    }
  }'
fi

exit 0
