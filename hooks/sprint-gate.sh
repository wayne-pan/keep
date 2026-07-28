#!/usr/bin/env bash
# sprint-gate.sh — PreToolUse:Edit|Write|MultiEdit hook
# Hard gate: when pending sprint state is active for this session, deny edits
# to non-whitelisted files. Forces Complex work to go through /keep:sprint.
#
# Early-exit allow conditions (in order):
#   1. SPRINT_ENFORCE=0|false|no|off (env escape hatch)
#   2. empty session_id → degraded mode
#   3. no pending state for session → gate inactive
#   4. empty file_path → cannot determine target
# Whitelist (allow even when pending): *.md, and paths whose first
# repo-relative segment is rules/, docs/, .sprint/, .keep/, or tests/.
#
# FAIL-CLOSED: if lib fails to load or jq is missing, exit 2 (deny).
# This is a security gate — failing open defeats the entire mechanism.

set -uo pipefail

# Escape hatch for CI / scripted runs — accepts common falsy values.
case "${SPRINT_ENFORCE:-1}" in
  0|false|FALSE|no|NO|off|OFF) exit 0 ;;
esac

# Fail-closed: jq is required for payload parsing.
command -v jq >/dev/null 2>&1 || {
  echo "[sprint-gate] jq missing — failing closed (gate active, deny edit)." >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="$SCRIPT_DIR/lib/sprint-state.sh"
# Fail-closed: lib must load successfully.
# shellcheck disable=SC1090
if [ ! -r "$LIB_PATH" ]; then
  echo "[sprint-gate] lib missing at $LIB_PATH — failing closed." >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$LIB_PATH"
if ! declare -F sprint_state_is_pending >/dev/null 2>&1; then
  echo "[sprint-gate] lib loaded but sprint_state_is_pending undefined — failing closed." >&2
  exit 2
fi

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"

# Early exit 1: no session_id → degraded mode (cannot attribute state)
[ -n "$SESSION_ID" ] || exit 0

# Early exit 2: no pending state → gate inactive
sprint_state_is_pending "$SESSION_ID" || exit 0

# Early exit 3: empty file_path → cannot determine target
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
[ -n "$FILE_PATH" ] || exit 0

# Normalize FILE_PATH to repo-relative: strip $CLAUDE_PROJECT_DIR prefix if present,
# so absolute paths get evaluated by their position within the project.
REL_PATH="$FILE_PATH"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  case "$FILE_PATH" in
    "$CLAUDE_PROJECT_DIR"/*) REL_PATH="${FILE_PATH#"$CLAUDE_PROJECT_DIR"/}" ;;
  esac
fi

# Whitelist (documentation-like and meta paths).
# Anchored to the FIRST repo-relative path segment to prevent bypass via
# paths like src/docs/evil.py or vendor/tests/payload.py.
# `*.md` remains broad — documentation files anywhere.
case "$REL_PATH" in
  *.md) exit 0 ;;
  rules/*|docs/*|.sprint/*|.keep/*|tests/*) exit 0 ;;
esac

# Deny — pending required
REASON="$(sprint_state_get_reason "$SESSION_ID" 2>/dev/null || echo unknown)"
cat >&2 <<EOF
[sprint-gate] Pending sprint required (reason: $REASON).
Call /keep:sprint first, then retry this edit.
To override: prefix your next prompt with "--no-sprint" or "trivial:" / "standard:".
EOF
exit 2
