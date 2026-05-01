#!/usr/bin/env bash
# pr-gate.sh — PreToolUse (Bash): gate PR creation on passing lint + tests
# Intercepts `gh pr create` and runs quality checks first.
# If checks fail, blocks the PR and shows the errors.
# Exit 2 = block, Exit 0 = allow.
set -uo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept gh pr create
[[ "$CMD" != *"gh pr create"* ]] && exit 0

# Find project root (look for .git)
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
[[ -z "$PROJECT_DIR" ]] && exit 0

cd "$PROJECT_DIR"

FAILURES=""
TOTAL_CHECKS=0
FAILED_CHECKS=0

# ── Check 1: Python lint (ruff) ──
PY_FILES=$(git diff --name-only --diff-filter=ACMR main 2>/dev/null | grep '\.py$' || true)
if [[ -n "$PY_FILES" ]]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if command -v ruff >/dev/null 2>&1; then
        ruff_result=$(echo "$PY_FILES" | xargs ruff check 2>&1) && ruff_result="" || true
        if [[ -n "$ruff_result" ]]; then
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            FAILURES="${FAILURES}[pr-gate] Ruff lint failed:"$'\n'"$(echo "$ruff_result" | head -15)"$'\n'$'\n'
        fi
    fi
fi

# ── Check 2: Shell lint (shellcheck) ──
SH_FILES=$(git diff --name-only --diff-filter=ACMR main 2>/dev/null | grep '\.sh$' || true)
if [[ -n "$SH_FILES" ]]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if command -v shellcheck >/dev/null 2>&1; then
        sh_result=$(echo "$SH_FILES" | xargs shellcheck 2>&1) || true
        if [[ -n "$sh_result" ]]; then
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            FAILURES="${FAILURES}[pr-gate] ShellCheck failed:"$'\n'"$(echo "$sh_result" | head -15)"$'\n'$'\n'
        fi
    fi
fi

# ── Check 3: Shell syntax (bash -n) ──
if [[ -n "$SH_FILES" ]]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    syntax_errors=""
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        err=$(bash -n "$f" 2>&1) || true
        if [[ -n "$err" ]]; then
            syntax_errors="${syntax_errors}  $f: $err"$'\n'
        fi
    done <<< "$SH_FILES"
    if [[ -n "$syntax_errors" ]]; then
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        FAILURES="${FAILURES}[pr-gate] Shell syntax errors:"$'\n'"$syntax_errors"$'\n'
    fi
fi

# ── Check 4: Python tests (if pytest available and tests exist) ──
if [[ -n "$PY_FILES" ]] && command -v pytest >/dev/null 2>&1; then
    TEST_DIR="$PROJECT_DIR/tests"
    if [[ -d "$TEST_DIR" ]]; then
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        pytest_result=$(timeout 30 pytest "$TEST_DIR" -x -q 2>&1) || true
        pytest_exit=$?
        if [[ $pytest_exit -ne 0 ]]; then
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            FAILURES="${FAILURES}[pr-gate] Tests failed:"$'\n'"$(echo "$pytest_result" | tail -10)"$'\n'$'\n'
        fi
    fi
fi

# ── Gate decision ──
if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo "BLOCKED: PR creation gated on quality checks ($FAILED_CHECKS/$TOTAL_CHECKS failed)."$'\n'$'\n'"$FAILURES"
    echo "Fix the issues above before creating a PR."
    exit 2
fi

if [[ $TOTAL_CHECKS -gt 0 ]]; then
    # Pass — show summary as info (non-blocking)
    jq -n --arg checks "$TOTAL_CHECKS" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: ("[pr-gate] All " + $checks + " quality checks passed. PR allowed.")
        }
    }'
fi

exit 0
