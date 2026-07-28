#!/usr/bin/env bash
# sprint-gate.sh — PreToolUse:Edit|Write|MultiEdit hook
# Hard gate: when pending sprint state is active for this session, deny edits
# to non-whitelisted files. Forces Complex work to go through /keep:sprint.
#
# Early-exit allow conditions (in order):
#   1. empty session_id → degraded mode
#   2. no pending state for session → gate inactive
#   3. empty file_path → cannot determine target
# Whitelist (allow even when pending): *.md, rules/, docs/, .sprint/, .keep/, tests/

set -uo pipefail

# Escape hatch for CI / scripted runs
[ "${SPRINT_ENFORCE:-1}" = "0" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="$SCRIPT_DIR/lib/sprint-state.sh"
# shellcheck disable=SC1090
[ -r "$LIB_PATH" ] && source "$LIB_PATH"

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"

# Early exit 1: no session_id → degraded mode
[ -n "$SESSION_ID" ] || exit 0

# Early exit 2: no pending state → gate inactive
sprint_state_is_pending "$SESSION_ID" || exit 0

# Early exit 3: empty file_path → cannot determine target
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
[ -n "$FILE_PATH" ] || exit 0

# Whitelist (documentation-like and meta paths)
# Note: rules/ is whitelisted because rules are documentation-like; this is an
# accepted tradeoff (model could edit rules to bypass — see SPRINT_ENFORCEMENT.md).
case "$FILE_PATH" in
  *.md)                                            exit 0 ;;
  */rules/*|*/docs/*|*/.sprint/*|*/.keep/*|*/tests/*) exit 0 ;;
  rules/*|docs/*|.sprint/*|.keep/*|tests/*)        exit 0 ;;
esac

# Deny — pending required
REASON="$(sprint_state_get_reason "$SESSION_ID" 2>/dev/null || echo unknown)"
cat >&2 <<EOF
[sprint-gate] Pending sprint required (reason: $REASON).
Call /keep:sprint first, then retry this edit.
To override: prefix your next prompt with "--no-sprint" or "trivial:" / "standard:".
EOF
exit 2
