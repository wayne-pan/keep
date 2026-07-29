#!/usr/bin/env bash
# sprint-session-stop.sh — SessionEnd hook
# Cleans up any pending sprint state for this session.
# Always exits 0 — cleanup must not block session exit.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="$SCRIPT_DIR/lib/sprint-state.sh"
# shellcheck disable=SC1090
[ -r "$LIB_PATH" ] && source "$LIB_PATH"

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"

# Always exit 0 — even on missing session_id, lib failure, etc.
[ -n "$SESSION_ID" ] || exit 0

sprint_state_clear "$SESSION_ID"
exit 0
