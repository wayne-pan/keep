#!/usr/bin/env bash
# validate-edit.sh — PostToolUse hook: validate + lint files after Write/Edit
# Phase 1: syntax check (fast, catches parse errors)
# Phase 2: lint check (ruff for Python, shellcheck for shell if available)
# Output shown to Claude as feedback.
set -euo pipefail

# Read tool call JSON from stdin
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

# Only validate Write and Edit tool calls
[[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]] && exit 0

# Extract file path
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0

ext="${file_path##*.}"
errors=""

# ── Phase 1: Syntax check ──
syntax_result=""
case "$ext" in
    sh|bash)
        syntax_result=$(bash -n "$file_path" 2>&1) || true
        ;;
    py)
        syntax_result=$(python3 -c "import ast; ast.parse(open('$file_path').read())" 2>&1) || true
        ;;
    js)
        syntax_result=$(node --check "$file_path" 2>&1) || true
        ;;
    json)
        syntax_result=$(python3 -m json.tool "$file_path" > /dev/null 2>&1) || syntax_result="Invalid JSON"
        ;;
    yaml|yml)
        syntax_result=$(python3 -c "import yaml; yaml.safe_load(open('$file_path'))" 2>&1) || true
        ;;
    *)
        # No auto-validation for this file type
        exit 0
        ;;
esac

if [[ -n "$syntax_result" ]]; then
    errors="[validate-edit] SYNTAX ERROR in $file_path:"$'\n'"$syntax_result"
fi

# ── Phase 2: Lint check (skip if syntax already failed) ──
lint_result=""
if [[ -z "$errors" ]]; then
    case "$ext" in
        py)
            # ruff: fast Python linter (replaces flake8, isort, pyupgrade)
            if command -v ruff >/dev/null 2>&1; then
                lint_result=$(ruff check "$file_path" 2>&1) && lint_result="" || true
            fi
            ;;
        sh|bash)
            # shellcheck: static analysis for shell scripts
            if command -v shellcheck >/dev/null 2>&1; then
                lint_result=$(shellcheck "$file_path" 2>&1) && lint_result="" || true
            fi
            ;;
    esac

    if [[ -n "$lint_result" ]]; then
        # Truncate to 20 lines to avoid flooding Claude's context
        truncated=$(echo "$lint_result" | head -20)
        line_count=$(echo "$lint_result" | wc -l)
        if [[ "$line_count" -gt 20 ]]; then
            truncated="$truncated"$'\n'"... ($((line_count - 20)) more lines)"
        fi
        errors="[validate-edit] LINT WARNING in $file_path:"$'\n'"$truncated"
    fi
fi

# ── Report ──
if [[ -n "$errors" ]]; then
    echo "$errors"
    exit 1
fi
