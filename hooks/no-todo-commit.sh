#!/usr/bin/env bash
# no-todo-commit.sh — block commits containing TODO/FIXME/HACK/empty bodies.
# Installed as PreToolUse:Bash hook.
# Constraints beat instructions — this is a hard gate, not a soft reminder.

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract the bash command from the JSON input
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only intercept git commit
if [[ "$CMD" != *"git commit"* ]]; then
  exit 0
fi

# Get staged diff
DIFF=$(git diff --cached 2>/dev/null) || exit 0

if [ -z "$DIFF" ]; then
  exit 0
fi

# Patterns that block commit
PATTERNS=(
  'TODO'
  'FIXME'
  'HACK'
  'XXX'
)

# Track violations
VIOLATIONS=""

# Check for marker patterns in added lines only
for pattern in "${PATTERNS[@]}"; do
  MATCHES=$(echo "$DIFF" | grep -n "^+" | grep "$pattern" | grep -v "^+++" || true)
  if [ -n "$MATCHES" ]; then
    while IFS= read -r line; do
      FILE_LINE=$(echo "$line" | sed 's/^+//' | head -1)
      VIOLATIONS="${VIOLATIONS}  ${pattern}: ${FILE_LINE}\n"
    done <<< "$MATCHES"
  fi
done

# Check for empty function bodies: standalone pass or NotImplementedError in added lines
EMPTY_BODY=$(echo "$DIFF" | grep -n "^+" | grep -E "^\+[0-9]*:\s*(pass\s*|#.*$)" | grep -v "^+++" || true)
if [ -n "$EMPTY_BODY" ]; then
  while IFS= read -r line; do
    VIOLATIONS="${VIOLATIONS}  empty body (pass): ${line}\n"
  done <<< "$EMPTY_BODY"
fi

NOT_IMPL=$(echo "$DIFF" | grep -n "^+" | grep "NotImplementedError" | grep -v "^+++" || true)
if [ -n "$NOT_IMPL" ]; then
  while IFS= read -r line; do
    VIOLATIONS="${VIOLATIONS}  stub (NotImplementedError): ${line}\n"
  done <<< "$NOT_IMPL"
fi

# If violations found, block the commit
if [ -n "$VIOLATIONS" ]; then
  MSG="BLOCKED: staged changes contain incomplete markers:\n${VIOLATIONS}\nRemove TODOs/FIXMEs/HACKs/empty bodies before committing."
  jq -n --arg msg "$MSG" '{decision: "block", reason: $msg}'
  exit 0
fi

exit 0
