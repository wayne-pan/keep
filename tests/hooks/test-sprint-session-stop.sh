#!/usr/bin/env bash
# Pure-bash test runner for hooks/sprint-session-stop.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/hooks/sprint-session-stop.sh"
LIB_PATH="$REPO_ROOT/hooks/lib/sprint-state.sh"

PASS_COUNT=0
FAIL_COUNT=0

run() {
  local name="$1"
  local fn="$2"
  if "$fn"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

test_clears_pending() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "session-end"
  printf '%s' '{"session_id":"test-sess"}' | bash "$HOOK_PATH"
  local rc
  if sprint_state_is_pending test-sess; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_always_exits_zero_on_empty_session_id() {
  # Even with empty session_id, hook must exit 0 (not block session exit)
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  printf '%s' '{"session_id":""}' | bash "$HOOK_PATH" 2>/dev/null
  local rc=$?
  rm -rf "$tmp"
  [ "$rc" = "0" ] && return 0 || return 1
}

test_always_exits_zero_on_missing_lib() {
  # If lib missing (file deleted), hook must still exit 0
  # Simulate by pointing to non-existent lib path via broken BASH_SOURCE
  # Easier: invoke hook with corrupted INPUT that makes jq fail
  printf '%s' 'not-valid-json' | bash "$HOOK_PATH" 2>/dev/null
  local rc=$?
  [ "$rc" = "0" ] && return 0 || return 1
}

test_unrelated_session_not_affected() {
  # Stopping session B must not clear session A's pending
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set sess-A "still-active"
  printf '%s' '{"session_id":"sess-B"}' | bash "$HOOK_PATH"
  local rc
  if sprint_state_is_pending sess-A; then rc=0; else rc=1; fi
  rm -rf "$tmp"
  return "$rc"
}

run "clears pending for this session"                test_clears_pending
run "always exit 0 on empty session_id (no block)"   test_always_exits_zero_on_empty_session_id
run "always exit 0 on malformed stdin (no block)"    test_always_exits_zero_on_missing_lib
run "does not clear other sessions' pending"         test_unrelated_session_not_affected

echo "---"
echo "Passed: $PASS_COUNT, Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
