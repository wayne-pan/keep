#!/usr/bin/env bash
# auto-verify.sh — PostToolUse hook: run relevant tests after source file edits
# Fires after validate-edit.sh. Only runs tests when a matching test file exists.
# Output injected via additionalContext (non-blocking).

set -uo pipefail

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Only source code files
ext="${FILE_PATH##*.}"
case "$ext" in
  py|ts|tsx|js|jsx|go|rs|rb|java) ;;
  *) exit 0 ;;  # Skip non-source files
esac

# Find test file
base=$(basename "$FILE_PATH")
dir=$(dirname "$FILE_PATH")
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

test_file=""

case "$ext" in
  py)
    # foo.py → test_foo.py or tests/test_foo.py
    name="${base%.py}"
    for candidate in \
      "${dir}/test_${name}.py" \
      "${dir}/tests/test_${name}.py" \
      "${dir}/../tests/test_${name}.py" \
      "${root}/tests/test_${name}.py" \
      "${root}/test_${name}.py"; do
      if [ -f "$candidate" ]; then
        test_file="$candidate"
        break
      fi
    done
    ;;
  ts|tsx|js|jsx)
    # foo.ts → foo.test.ts or __tests__/foo.test.ts
    name="${base%.*}"
    for candidate in \
      "${dir}/${name}.test.${ext}" \
      "${dir}/__tests__/${name}.test.${ext}" \
      "${dir}/../__tests__/${name}.test.${ext}" \
      "${dir}/test/${name}.test.${ext}"; do
      if [ -f "$candidate" ]; then
        test_file="$candidate"
        break
      fi
    done
    ;;
  go)
    # foo.go → foo_test.go
    name="${base%.go}"
    for candidate in \
      "${dir}/${name}_test.go" \
      "${dir}/../${name}_test.go"; do
      if [ -f "$candidate" ]; then
        test_file="$candidate"
        break
      fi
    done
    ;;
  rs)
    # Rust tests are inline, just run cargo test for the module
    test_file="cargo"
    ;;
  rb)
    name="${base%.rb}"
    for candidate in \
      "${dir}/test_${name}.rb" \
      "${dir}/../test/test_${name}.rb" \
      "${root}/test/test_${name}.rb"; do
      if [ -f "$candidate" ]; then
        test_file="$candidate"
        break
      fi
    done
    ;;
  java)
    name="${base%.java}"
    for candidate in \
      "${dir}/../test/${name}Test.java" \
      "${dir}/../tests/${name}Test.java" \
      "${root}/src/test/java/${name}Test.java"; do
      if [ -f "$candidate" ]; then
        test_file="$candidate"
        break
      fi
    done
    ;;
esac

[ -z "$test_file" ] && exit 0

# Run test with 10s timeout
result=""
case "$ext" in
  py)
    if command -v pytest &>/dev/null; then
      result=$(timeout 10 pytest "$test_file" --tb=short -q 2>&1 | tail -5)
    fi
    ;;
  ts|tsx|js|jsx)
    if command -v npx &>/dev/null; then
      result=$(timeout 10 npx jest "$test_file" --no-coverage 2>&1 | tail -5)
    fi
    ;;
  go)
    if command -v go &>/dev/null; then
      result=$(cd "$root" && timeout 10 go test "./${dir#$root/}" 2>&1 | tail -5)
    fi
    ;;
  rs)
    if command -v cargo &>/dev/null; then
      result=$(cd "$root" && timeout 10 cargo test --quiet 2>&1 | tail -5)
    fi
    ;;
  rb)
    if command -v ruby &>/dev/null; then
      result=$(timeout 10 ruby "$test_file" 2>&1 | tail -5)
    fi
    ;;
  java)
    # Java needs full build, skip auto-verify
    exit 0
    ;;
esac

[ -z "$result" ] && exit 0

# Inject result
jq -n --arg res "[Auto-verify] $result" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $res
  }
}'

exit 0
