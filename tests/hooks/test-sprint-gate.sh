#!/usr/bin/env bash
# Pure-bash test runner for hooks/sprint-gate.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/hooks/sprint-gate.sh"
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

# Helper: set pending in current shell, invoke hook with stdin, assert exit code.
# Args: stdin_json  expected_exit (0 or 2)
run_with_pending() {
  local json="$1"
  local expected_exit="$2"
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "complex-match" || { rm -rf "$tmp"; return 1; }
  printf '%s' "$json" | bash "$HOOK_PATH" >/dev/null 2>&1
  local actual=$?
  local rc
  [ "$actual" = "$expected_exit" ] && rc=0 || rc=1
  rm -rf "$tmp"
  return "$rc"
}

# --- Test cases ---

test_pending_src_denied() {
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"src/main.py","old_string":"a","new_string":"b"}}' 2
}

test_pending_write_denied() {
  run_with_pending '{"tool_name":"Write","session_id":"test-sess","tool_input":{"file_path":"src/new.py","content":"x"}}' 2
}

test_pending_multiedit_denied() {
  run_with_pending '{"tool_name":"MultiEdit","session_id":"test-sess","tool_input":{"file_path":"src/main.py","edits":[{"old_string":"a","new_string":"b"}]}}' 2
}

test_pending_md_allowed() {
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"README.md"}}' 0
}

test_pending_claude_md_allowed() {
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"CLAUDE.md"}}' 0
}

test_pending_subpath_md_allowed() {
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"/abs/path/docs/intro.md"}}' 0
}

test_pending_tests_allowed() {
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"tests/hooks/x.sh"}}' 0
}

test_pending_rules_allowed() {
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"rules/core.md"}}' 0
}

test_pending_docs_allowed() {
  run_with_pending '{"tool_name":"Write","session_id":"test-sess","tool_input":{"file_path":"docs/architecture.md"}}' 0
}

test_pending_keep_state_allowed() {
  # Editing state files themselves should not be blocked (no infinite loop)
  run_with_pending '{"tool_name":"Write","session_id":"test-sess","tool_input":{"file_path":".keep/state/sprint-pending-x.json"}}' 0
}

test_no_pending_any_allowed() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  # intentionally do NOT set pending
  printf '%s' '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"src/main.py"}}' | bash "$HOOK_PATH" >/dev/null 2>&1
  local rc=$?
  rm -rf "$tmp"
  [ "$rc" = "0" ] && return 0 || return 1
}

test_empty_filepath_allowed() {
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{}}' 0
}

test_empty_session_id_allowed() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set real-sess "x"
  printf '%s' '{"tool_name":"Edit","session_id":"","tool_input":{"file_path":"src/main.py"}}' | bash "$HOOK_PATH" >/dev/null 2>&1
  local rc=$?
  rm -rf "$tmp"
  [ "$rc" = "0" ] && return 0 || return 1
}

test_stderr_contains_override_hint() {
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "x"
  local stderr
  stderr=$(printf '%s' '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"src/main.py"}}' | bash "$HOOK_PATH" 2>&1 1>/dev/null)
  local rc=1
  if echo "$stderr" | grep -q "override" && echo "$stderr" | grep -q "no-sprint"; then
    rc=0
  fi
  rm -rf "$tmp"
  return "$rc"
}

test_sprint_enforce_zero_bypasses_gate() {
  # Escape hatch: SPRINT_ENFORCE=0 must allow even with pending active
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  export SPRINT_ENFORCE=0
  # shellcheck disable=SC1090
  source "$LIB_PATH"
  sprint_state_set test-sess "x"
  printf '%s' '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"src/main.py"}}' | bash "$HOOK_PATH" >/dev/null 2>&1
  local rc=$?
  unset SPRINT_ENFORCE
  rm -rf "$tmp"
  [ "$rc" = "0" ] && return 0 || return 1
}

test_nested_docs_path_denied() {
  # REGRESSION H2: src/docs/x.py must NOT match whitelist (was matching
  # */docs/* overreach). Only top-level docs/ is whitelisted.
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"src/docs/evil.py"}}' 2
}

test_nested_tests_path_denied() {
  # REGRESSION H2: vendor/tests/payload.py must NOT match whitelist
  run_with_pending '{"tool_name":"Edit","session_id":"test-sess","tool_input":{"file_path":"vendor/tests/payload.py"}}' 2
}

test_lib_missing_fails_closed() {
  # REGRESSION H1: if lib is unreadable, gate MUST fail closed (exit 2),
  # not silently allow.
  local tmp; tmp="$(mktemp -d)" || return 1
  export KEEP_STATE_DIR="$tmp"
  # Move lib aside to simulate missing/unreadable
  mv "$REPO_ROOT/hooks/lib/sprint-state.sh" "$tmp/sprint-state.sh.bak"
  local rc
  printf '%s' '{"tool_name":"Edit","session_id":"x","tool_input":{"file_path":"src/main.py"}}' \
    | bash "$HOOK_PATH" >/dev/null 2>&1
  rc=$?
  # Restore lib
  mv "$tmp/sprint-state.sh.bak" "$REPO_ROOT/hooks/lib/sprint-state.sh"
  rm -rf "$tmp"
  [ "$rc" = "2" ] && return 0 || return 1
}

# --- Runner ---

run "pending+Edit src/: denied"                          test_pending_src_denied
run "pending+Write src/: denied"                         test_pending_write_denied
run "pending+MultiEdit src/: denied"                     test_pending_multiedit_denied
run "pending+README.md: allowed (whitelist)"             test_pending_md_allowed
run "pending+CLAUDE.md: allowed (whitelist)"             test_pending_claude_md_allowed
run "pending+subpath docs/x.md: allowed (whitelist)"     test_pending_subpath_md_allowed
run "pending+tests/: allowed (whitelist)"                test_pending_tests_allowed
run "pending+rules/: allowed (whitelist, accepted risk)" test_pending_rules_allowed
run "pending+docs/: allowed (whitelist)"                 test_pending_docs_allowed
run "pending+.keep/state/: allowed (no self-block)"      test_pending_keep_state_allowed
run "no-pending+src/: allowed (gate inactive)"           test_no_pending_any_allowed
run "empty-filepath: allowed (cannot determine)"         test_empty_filepath_allowed
run "empty-session_id: allowed (degraded mode)"          test_empty_session_id_allowed
run "deny stderr contains override hint"                 test_stderr_contains_override_hint
run "SPRINT_ENFORCE=0 bypass: allowed even with pending" test_sprint_enforce_zero_bypasses_gate
run "REGRESSION H2: src/docs/x.py DENIED (whitelist anchored)"      test_nested_docs_path_denied
run "REGRESSION H2: vendor/tests/x.py DENIED (whitelist anchored)"  test_nested_tests_path_denied
run "REGRESSION H1: missing lib → fail closed (exit 2)"             test_lib_missing_fails_closed

echo "---"
echo "Passed: $PASS_COUNT, Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
