#!/usr/bin/env bash
# test-todo-check.sh — Validation for todo-check.sh hook
# Usage: bash scripts/test-todo-check.sh
# Requires: git repo with staged files

set -uo pipefail

PASS=0
FAIL=0
HOOK="hooks/todo-check.sh"
TMPDIR=""

cleanup() {
  [ -n "$TMPDIR" ] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Create temp git repo for isolated testing
setup_repo() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
}

assert_warn() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(echo "$cmd" | bash "$OLDPWD/$HOOK" 2>/dev/null)
  if echo "$result" | grep -q '\[todo-check\]'; then
    echo "  PASS (warn): $desc"
    ((PASS++))
  else
    echo "  FAIL (should warn): $desc — got: $(echo "$result" | head -1)"
    ((FAIL++))
  fi
}

assert_silent() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(echo "$cmd" | bash "$OLDPWD/$HOOK" 2>/dev/null)
  if [ -z "$result" ] || ! echo "$result" | grep -q '\[todo-check\]'; then
    echo "  PASS (silent): $desc"
    ((PASS++))
  else
    echo "  FAIL (should be silent): $desc — got: $result"
    ((FAIL++))
  fi
}

setup_repo

echo "=== NON-COMMIT COMMANDS (must be silent) ==="
assert_silent "git status" '{"tool_input":{"command":"git status"}}'
assert_silent "git diff" '{"tool_input":{"command":"git diff"}}'
assert_silent "git log" '{"tool_input":{"command":"git log --oneline"}}'
assert_silent "npm test" '{"tool_input":{"command":"npm test"}}'
assert_silent "make build" '{"tool_input":{"command":"make build"}}'

echo ""
echo "=== NO STAGED FILES (must be silent) ==="
assert_silent "git commit with empty staging" '{"tool_input":{"command":"git commit -m test"}}'

echo ""
echo "=== STAGED FILES WITHOUT TODO/FIXME (must be silent) ==="
echo "clean code" > clean.txt
git add clean.txt
assert_silent "commit clean file" '{"tool_input":{"command":"git commit -m clean"}}'

echo ""
echo "=== STAGED FILES WITH TODO/FIXME (must warn) ==="
echo "// TODO: fix this later" > todo.txt
git add todo.txt
assert_warn "commit file with TODO" '{"tool_input":{"command":"git commit -m todo"}}'

echo "// FIXME: broken logic" > fixme.txt
git add fixme.txt
assert_warn "commit file with FIXME" '{"tool_input":{"command":"git commit -m fixme"}}'

echo ""
echo "=== AMEND COMMIT (must be silent) ==="
assert_silent "git commit --amend" '{"tool_input":{"command":"git commit --amend -m fixme"}}'

echo ""
echo "=== BINARY FILES (must be silent) ==="
git reset HEAD -- . >/dev/null 2>&1
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' > image.png
git add image.png
# Binary files may or may not trigger — diff-filter=ACMR handles renames but
# git still diffs binary content as text in small files. This is a known edge case.
assert_silent "commit binary file" '{"tool_input":{"command":"git commit -m img"}}' || true

echo ""
echo "=== MULTIPLE TODOs (must warn with count) ==="
printf "TODO: one\nFIXME: two\nTODO: three\n" > multi.txt
git add multi.txt
result=$(echo '{"tool_input":{"command":"git commit -m multi"}}' | bash "$OLDPWD/$HOOK" 2>/dev/null)
count=$(echo "$result" | grep -oP '\d+(?= TODO/FIXME)' || echo "0")
if [ "$count" -ge 3 ]; then
  echo "  PASS (warn): multiple TODOs count=$count"
  ((PASS++))
else
  echo "  FAIL (warn): expected count>=3, got=$count"
  ((FAIL++))
fi

echo ""
echo "=== RESULTS ==="
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
