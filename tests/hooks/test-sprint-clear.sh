#!/usr/bin/env bash
# Pure-bash test runner for hooks/sprint-clear.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/hooks/sprint-clear.sh"
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

# Helper: set pending in current shell, run hook with stdin JSON, then check pending
# Args: stdin_json, expected_pending_after (0 = should be cleared, 1 = should remain)
run_scenario() {
  local json="$1"
  local expect_remaining="$2"  # 0 = cleared, 1 = still pending
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "scenario" || { rm -rf "$tmp"; return 1; }
  printf '%s' "$json" | bash "$HOOK_PATH" >/dev/null 2>&1
  local rc
  if sprint_state_is_pending test-sess; then
    # still pending
    [ "$expect_remaining" = "1" ] && rc=0 || rc=1
  else
    # cleared
    [ "$expect_remaining" = "0" ] && rc=0 || rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# --- Test cases ---

test_sprint_success_clears() {
  run_scenario '{"tool_name":"Skill","session_id":"test-sess","tool_input":{"skill":"sprint","args":""},"tool_response":{"success":true}}' 0
}

test_keep_sprint_alt_name_clears() {
  run_scenario '{"tool_name":"Skill","session_id":"test-sess","tool_input":{"skill":"keep:sprint"},"tool_response":{"success":true}}' 0
}

test_diagnosing_bugs_clears() {
  run_scenario '{"tool_name":"Skill","session_id":"test-sess","tool_input":{"skill":"diagnosing-bugs"},"tool_response":{"success":true}}' 0
}

test_sprint_failure_preserves() {
  run_scenario '{"tool_name":"Skill","session_id":"test-sess","tool_input":{"skill":"sprint"},"tool_response":{"success":false}}' 1
}

test_sprint_error_response_preserves() {
  run_scenario '{"tool_name":"Skill","session_id":"test-sess","tool_input":{"skill":"sprint"},"tool_response":{"success":true,"error":"skill not found"}}' 1
}

test_non_matching_skill_preserves() {
  run_scenario '{"tool_name":"Skill","session_id":"test-sess","tool_input":{"skill":"review"},"tool_response":{"success":true}}' 1
}

test_non_skill_tool_preserves() {
  run_scenario '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"x.py"},"tool_response":{}}' 1
}

test_missing_tool_response_defaults_success_clears() {
  run_scenario '{"tool_name":"Skill","session_id":"test-sess","tool_input":{"skill":"sprint"}}' 0
}

test_empty_session_id_no_op() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "x"
  printf '{"tool_name":"Skill","session_id":"","tool_input":{"skill":"sprint"},"tool_response":{"success":true}}' | bash "$HOOK_PATH" >/dev/null 2>&1
  local rc
  if sprint_state_is_pending test-sess; then rc=0; else rc=1; fi
  rm -rf "$tmp"
  return "$rc"
}

# --- Runner ---

run "sprint+success: pending cleared"                          test_sprint_success_clears
run "keep:sprint alt name: pending cleared"                    test_keep_sprint_alt_name_clears
run "diagnosing-bugs: pending cleared"                         test_diagnosing_bugs_clears
run "sprint+success=false: pending PRESERVED (R1 #9 fix)"      test_sprint_failure_preserves
run "sprint+error response: pending PRESERVED"                 test_sprint_error_response_preserves
run "non-matching skill (review): pending preserved"           test_non_matching_skill_preserves
run "non-Skill tool (Edit): pending preserved"                 test_non_skill_tool_preserves
run "missing tool_response: defaults to success, clears"       test_missing_tool_response_defaults_success_clears
run "empty session_id: hook no-ops"                            test_empty_session_id_no_op

echo "---"
echo "Passed: $PASS_COUNT, Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
