#!/usr/bin/env bash
# sprint-state.sh — Shared state protocol for sprint-enforcement hooks.
# Manages $KEEP_STATE_DIR/sprint-pending-<session_id>.json with atomic writes,
# epoch-based TTL, and per-session file isolation (no cross-session overwrite).
#
# Public functions:
#   sprint_state_set <session_id> <reason>
#   sprint_state_clear <session_id>
#   sprint_state_is_pending <session_id>    (exit 0 if active, 1 otherwise)
#   sprint_state_get_reason <session_id>    (echoes reason, exit 1 if not active)

set -uo pipefail

# Default state dir (override via KEEP_STATE_DIR — used by tests).
KEEP_STATE_DIR="${KEEP_STATE_DIR:-.keep/state}"
# TTL: 1800s = 30 minutes. Long enough for model to invoke sprint skill
# between turns; short enough that a forgotten pending doesn't stall forever.
# Override via SPRINT_PENDING_TTL (must be positive integer).
TTL_SECONDS="${SPRINT_PENDING_TTL:-1800}"
case "$TTL_SECONDS" in
  ''|*[!0-9]*) TTL_SECONDS=1800 ;;
esac
[ "$TTL_SECONDS" -gt 0 ] || TTL_SECONDS=1800

# _pending_file_for <session_id>
# Sanitizes session_id into a filename-safe segment and prints the full path.
_pending_file_for() {
  local sid="$1"
  local safe_sid
  safe_sid="$(printf '%s' "$sid" | tr -c '[:alnum:]_.-' '_')"
  printf '%s/sprint-pending-%s.json\n' "$KEEP_STATE_DIR" "$safe_sid"
}

# sprint_state_set <session_id> <reason>
# Atomic write via tmpfile + mv. Returns 0 on success, 1 on error.
sprint_state_set() {
  local session_id="$1"
  local reason="$2"
  [ -n "$session_id" ] || return 1

  local now_epoch expires_at file tmp
  now_epoch="$(date +%s)" || return 1
  expires_at=$((now_epoch + TTL_SECONDS))
  file="$(_pending_file_for "$session_id")"

  mkdir -p "$KEEP_STATE_DIR" || return 1
  tmp="${file}.tmp.$$"

  if jq -n \
    --arg sid "$session_id" \
    --argjson set "$now_epoch" \
    --argjson exp "$expires_at" \
    --arg reason "$reason" \
    '{session_id:$sid, set_at_epoch:$set, expires_at_epoch:$exp, reason:$reason}' \
    > "$tmp"; then
    mv "$tmp" "$file"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# sprint_state_clear <session_id>
# Idempotent delete. Verifies stored session_id matches before deleting,
# preventing cross-session deletion via sanitization collisions
# (e.g. "abc!" and "abc@" sanitize to same filename). Always returns 0.
sprint_state_clear() {
  local session_id="$1"
  [ -n "$session_id" ] || return 0
  local file file_sid
  file="$(_pending_file_for "$session_id")"
  [ -f "$file" ] || return 0
  file_sid="$(jq -r '.session_id // empty' "$file" 2>/dev/null)" || return 0
  [ "$file_sid" = "$session_id" ] || return 0
  rm -f "$file"
  return 0
}

# sprint_state_is_pending <session_id>
# Exit 0 iff: file exists AND session_id matches AND TTL not expired.
# Exit 1 otherwise (including jq parse failure, expired, wrong session).
sprint_state_is_pending() {
  local session_id="$1"
  [ -n "$session_id" ] || return 1

  local file file_sid exp now_epoch
  file="$(_pending_file_for "$session_id")"
  [ -f "$file" ] || return 1

  file_sid="$(jq -r '.session_id // empty' "$file" 2>/dev/null)" || return 1
  [ -n "$file_sid" ] || return 1
  [ "$file_sid" = "$session_id" ] || return 1

  exp="$(jq -r '.expires_at_epoch // 0' "$file" 2>/dev/null)" || return 1
  case "$exp" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$exp" -gt 0 ] || return 1

  now_epoch="$(date +%s)" || return 1
  [ "$now_epoch" -lt "$exp" ] || return 1

  return 0
}

# sprint_state_get_reason <session_id>
# Echoes reason field; exit 1 if not is_pending. Single caller: sprint-gate.sh.
# Kept as a function for testability — see test-sprint-state.sh.
sprint_state_get_reason() {
  local session_id="$1"
  sprint_state_is_pending "$session_id" || return 1
  local file
  file="$(_pending_file_for "$session_id")"
  jq -r '.reason // "unknown"' "$file"
}
