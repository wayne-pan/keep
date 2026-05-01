#!/usr/bin/env bash
# todo-check.sh — PreToolUse (Bash): warn about TODO/FIXME in staged files before commit.
# Installed as PreToolUse hook for Bash tool in settings.json.
set -uo pipefail

INPUT=$(cat)

# Only intercept git commit commands
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ "$CMD" != *git\ commit* ]] && exit 0

# Skip amend commits (user explicitly amending)
echo "$CMD" | grep -q '\--amend' && exit 0

# Get list of staged files (text files only)
FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null) || exit 0
[ -z "$FILES" ] && exit 0

# Scan each staged file for newly added TODO/FIXME lines
WARNINGS=""
COUNT=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  MATCHES=$(git diff --cached --unified=0 -- "$file" 2>/dev/null \
    | grep '^+' \
    | grep -v '^+++' \
    | grep -iE '(TODO|FIXME)' \
    || true)
  [ -z "$MATCHES" ] && continue
  while IFS= read -r match; do
    CLEAN=$(echo "$match" | sed 's/^+[[:space:]]*//')
    COUNT=$((COUNT + 1))
    WARNINGS="${WARNINGS}  ${COUNT}. ${file}: ${CLEAN}"$'\n'
    [ "$COUNT" -ge 10 ] && break 2
  done <<< "$MATCHES"
done <<< "$FILES"

[ "$COUNT" -eq 0 ] && exit 0

# Non-blocking warning via additionalContext (exit 0 = allow commit)
jq -n --arg w "$WARNINGS" --argjson c "$COUNT" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("[todo-check] " + ($c | tostring) + " TODO/FIXME item(s) in staged files:\n" + $w)
  }
}'
