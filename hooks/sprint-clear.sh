#!/usr/bin/env bash
# sprint-clear.sh — PostToolUse:Skill hook
# Clears pending state when a sprint/diagnosing-bugs skill call **successfully** completes.
# Preserves pending on: skill failure, error response, or non-matching skill.
# This is the critical timing fix (Round 1 finding #9): clear AFTER skill runs,
# not before — prevents "skill failed but pending gone" bypass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="$SCRIPT_DIR/lib/sprint-state.sh"
# shellcheck disable=SC1090
[ -r "$LIB_PATH" ] && source "$LIB_PATH"

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
[ "$TOOL_NAME" = "Skill" ] || exit 0

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
[ -n "$SESSION_ID" ] || exit 0

SKILL="$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty')"
case "$SKILL" in
  sprint|keep:sprint|diagnosing-bugs|keep:diagnosing-bugs) : ;;
  *) exit 0 ;;
esac

# Detect failure: explicit success == false OR non-empty error field.
# Note: jq's `//` treats `false` as falsy and falls through, so we use
# explicit `== false` comparison instead. Missing fields → null → not failure.
FAILURE_DETECTED="$(printf '%s' "$INPUT" | jq -r '
  (.tool_response.success == false) or
  (.tool_result.success == false) or
  ((.tool_response.error // .tool_result.error // "") != "")
')"

if [ "$FAILURE_DETECTED" = "true" ]; then
  echo "[sprint-clear] Skill=$SKILL failed; pending preserved for session=$SESSION_ID" >&2
  exit 0
fi

sprint_state_clear "$SESSION_ID"
echo "[sprint-clear] Cleared pending for session=$SESSION_ID skill=$SKILL" >&2
exit 0
