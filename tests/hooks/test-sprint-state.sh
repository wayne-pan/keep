#!/usr/bin/env bash
# Pure-bash test runner for hooks/lib/sprint-state.sh.
# Usage: bash tests/hooks/test-sprint-state.sh
# No external test framework required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

# --- Test cases (each returns 0 on success, 1 on failure) ---

test_round_trip() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  if sprint_state_set test-sess "round-trip-test" && sprint_state_is_pending test-sess; then
    rc=0
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "${rc:-1}"
}

test_clear() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "clear-test"
  sprint_state_clear test-sess
  if sprint_state_is_pending test-sess; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_ttl_expired() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "ttl-test"
  local file="$tmp/sprint-pending-test-sess.json"
  [ -f "$file" ] || { rm -rf "$tmp"; return 1; }
  jq '.expires_at_epoch = (.set_at_epoch - 100)' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  if sprint_state_is_pending test-sess; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_session_isolation() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set sess-A "isolation-test"
  if sprint_state_is_pending sess-B; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

test_default_path() {
  local tmp; tmp="$(mktemp -d)" || return 1
  cd "$tmp" || { rm -rf "$tmp"; return 1; }
  unset KEEP_STATE_DIR
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "default-path-test"
  local rc
  if [ -f ".keep/state/sprint-pending-test-sess.json" ]; then rc=0; else rc=1; fi
  cd / || rc=1
  rm -rf "$tmp"
  return "$rc"
}

test_empty_session_id() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  local rc=0
  if sprint_state_set "" "empty-sid-test"; then rc=1; fi
  if sprint_state_is_pending ""; then rc=1; fi
  rm -rf "$tmp"
  return "$rc"
}

test_corrupted_json() {
  # Corrupted JSON in pending file → is_pending returns 1 (fail safe)
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "corrupt-test"
  local file="$tmp/sprint-pending-test-sess.json"
  echo '{not valid json' > "$file"
  if sprint_state_is_pending test-sess; then rc=1; else rc=0; fi
  rm -rf "$tmp"
  return "$rc"
}

# --- Runner ---

run "round-trip: set then is_pending returns 0"           test_round_trip
run "clear: makes is_pending return 1"                     test_clear
run "TTL: expired pending returns 1"                       test_ttl_expired
run "session-isolation: A's pending invisible to B"        test_session_isolation
run "default-path: writes to .keep/state/ when env unset"  test_default_path
run "empty-session-id: rejected by set and is_pending"     test_empty_session_id
run "corrupted-json: is_pending fails safe (returns 1)"    test_corrupted_json

echo "---"
echo "Passed: $PASS_COUNT, Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
