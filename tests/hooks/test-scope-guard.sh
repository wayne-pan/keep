#!/usr/bin/env bash
# Pure-bash test runner for hooks/scope-guard.sh — loop detection + registration.
# Cases: A identical-call loop, B alternating calls, C legacy state file, D compact hint (Task 3).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/hooks/scope-guard.sh"
INSTALL_SH="$REPO_ROOT/scripts/install.sh"

PASS_COUNT=0
FAIL_COUNT=0

run() {
  local name="$1" fn="$2"
  if "$fn"; then
    echo "PASS: $name"; PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name"; FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

payload() { # tool_name command session
  jq -cn --arg t "$1" --arg c "$2" --arg s "$3" '{tool_name:$t, session_id:$s, tool_input:{command:$c}}'
}

hook_out() { # payload json
  printf '%s' "$1" | bash "$HOOK_PATH" 2>/dev/null
}

fresh() { mktemp -d; }

test_loop_on_third_identical() {
  local tmp; tmp=$(fresh); export SCOPE_STATE_DIR="$tmp"
  local p; p=$(payload Bash "echo hi" t-loop)
  hook_out "$p" >/dev/null
  hook_out "$p" >/dev/null
  local out; out=$(hook_out "$p")
  rm -rf "$tmp"
  echo "$out" | grep -q '\[Loop\]'
}

test_no_loop_on_alternating() {
  local tmp; tmp=$(fresh); export SCOPE_STATE_DIR="$tmp"
  local a b out
  a=$(payload Bash "echo one" t-alt)
  b=$(payload Read "src/main.py" t-alt)
  hook_out "$a" >/dev/null; hook_out "$b" >/dev/null; hook_out "$a" >/dev/null
  out=$(hook_out "$b")
  rm -rf "$tmp"
  ! echo "$out" | grep -q '\[Loop\]'
}

test_legacy_state_no_crash() {
  local tmp; tmp=$(fresh); export SCOPE_STATE_DIR="$tmp"
  printf 'count=5\nfiles=src/a.py\n' > "$tmp/claude-scope-t-legacy"
  local p out rc
  p=$(payload Bash "ls -la" t-legacy)
  out=$(hook_out "$p"); rc=$?
  rm -rf "$tmp"
  [ "$rc" -eq 0 ] && ! echo "$out" | grep -q '\[Loop\]'
}

test_state_has_hash_fields() {
  local tmp; tmp=$(fresh); export SCOPE_STATE_DIR="$tmp"
  hook_out "$(payload Bash "echo x" t-state)" >/dev/null
  local ok=1
  grep -q '^last_hash=' "$tmp/claude-scope-t-state" || ok=0
  grep -q '^loop_n=' "$tmp/claude-scope-t-state" || ok=0
  rm -rf "$tmp"
  [ "$ok" -eq 1 ]
}

test_registered_in_installer() {
  grep -q 'scope-guard' "$INSTALL_SH"
}

# --- Run ---
run "loop warning on 3rd identical call" test_loop_on_third_identical
run "no loop warning on alternating calls" test_no_loop_on_alternating
run "legacy state file does not crash" test_legacy_state_no_crash
run "state file persists hash fields" test_state_has_hash_fields
run "scope-guard registered in install.sh" test_registered_in_installer

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
