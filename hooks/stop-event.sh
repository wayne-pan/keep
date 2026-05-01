#!/usr/bin/env bash
# stop-event.sh — Cooperative stop event for cross-process coordination.
# Uses file-based signal: /tmp/keep-stop-{session_id}
#
# Usage:
#   Set stop:     touch /tmp/keep-stop-$(cat .sprint/SESSION_ID 2>/dev/null || echo default)
#   Check stop:   test -f /tmp/keep-stop-$(cat .sprint/SESSION_ID 2>/dev/null || echo default)
#   Clear stop:   rm -f /tmp/keep-stop-$(cat .sprint/SESSION_ID 2>/dev/null || echo default)
#
# Sprint checks stop signal at each phase boundary.
# Safety-guard sets stop on CRITICAL severity violations.
# Grace period: 30 seconds (subagents can finish current work before stopping).

SESSION_ID=$(cat .sprint/SESSION_ID 2>/dev/null || echo "default")
STOP_FILE="/tmp/keep-stop-${SESSION_ID}"
GRACE_SECONDS=30

# Check if stop is requested
if [ -f "$STOP_FILE" ]; then
  # Read reason from stop file
  REASON=$(cat "$STOP_FILE" 2>/dev/null || echo "Unknown reason")
  jq -n --arg reason "$REASON" --arg grace "$GRACE_SECONDS" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("STOP EVENT: Sprint coordination stop requested: " + $reason + ". Grace period: " + $grace + "s")
    }
  }'
  exit 0
fi

# No stop requested — pass through
exit 0
