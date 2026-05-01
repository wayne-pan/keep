#!/usr/bin/env bash
# Temporary test script for safety-guard.sh validation
# Usage: bash scripts/test-safety-guard.sh

PASS=0
FAIL=0

assert_deny() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(echo "$cmd" | bash hooks/safety-guard.sh 2>/dev/null)
  if echo "$result" | grep -q '"deny"'; then
    echo "  PASS (deny): $desc"
    ((PASS++))
  else
    echo "  FAIL (should deny): $desc"
    ((FAIL++))
  fi
}

assert_allow() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(echo "$cmd" | bash hooks/safety-guard.sh 2>/dev/null)
  if echo "$result" | grep -q '"deny"'; then
    echo "  FAIL (should allow): $desc"
    ((FAIL++))
  else
    echo "  PASS (allow): $desc"
    ((PASS++))
  fi
}

echo "=== KNOWN BYPASSES (should DENY but currently PASS through) ==="
assert_deny "Extra whitespace" '{"tool_input":{"command":"rm   -rf   /"}}'
assert_deny "Backslash escape" '{"tool_input":{"command":"r\\m -rf /"}}'
assert_deny "Tab separation" '{"tool_input":{"command":"rm\t-rf\t/"}}'
assert_deny "eval+base64" '{"tool_input":{"command":"eval $(echo cm0g | base64 -d)"}}'
assert_deny "printf obfuscation" '{"tool_input":{"command":"$(printf rm) -rf /"}}'

echo ""
echo "=== EXISTING BLOCKS (regression — must still DENY) ==="
assert_deny "Direct rm -rf /" '{"tool_input":{"command":"rm -rf /"}}'
assert_deny "Semicolon chain" '{"tool_input":{"command":"cd /tmp ; rm -rf /"}}'
assert_deny "AND chain" '{"tool_input":{"command":"echo ok && rm -rf /"}}'
assert_deny "printenv" '{"tool_input":{"command":"printenv"}}'
assert_deny "cat .env" '{"tool_input":{"command":"cat .env"}}'

echo ""
echo "=== LEGITIMATE COMMANDS (must ALLOW) ==="
assert_allow "git status" '{"tool_input":{"command":"git status"}}'
assert_allow "cd && make" '{"tool_input":{"command":"cd foo && make"}}'
assert_allow "echo with substitution" '{"tool_input":{"command":"echo $(git rev-parse HEAD)"}}'
assert_allow "cat with pipe" '{"tool_input":{"command":"cat file.txt | grep pattern"}}'
assert_allow "npm install" '{"tool_input":{"command":"npm install"}}'
assert_allow "Empty command" '{"tool_input":{"command":""}}'

echo ""
echo "=== RESULTS ==="
echo "PASS: $PASS  FAIL: $FAIL"
