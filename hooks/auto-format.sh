#!/usr/bin/env bash
# auto-format.sh — PostToolUse hook for auto-formatting after Write/Edit
# Runs appropriate formatter based on file extension.
# Skips silently if formatter not available. Timeout: 5s.

set -euo pipefail

# Read hook input from stdin
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# Skip if no file path
[ -z "$file_path" ] && exit 0

ext="${file_path##*.}"
base=$(basename "$file_path")

# Skip non-code files and hidden files
case "$base" in
    .*|*.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.csv) exit 0 ;;
esac

case "$ext" in
    sh|bash)
        if command -v shfmt >/dev/null 2>&1; then
            timeout 5 shfmt -w "$file_path" 2>/dev/null || true
        fi
        ;;
    py)
        if command -v ruff >/dev/null 2>&1; then
            timeout 5 ruff format "$file_path" 2>/dev/null || true
        fi
        ;;
    js|jsx|ts|tsx|mjs|cjs)
        if command -v prettier >/dev/null 2>&1; then
            timeout 5 prettier --write "$file_path" 2>/dev/null || true
        fi
        ;;
    go)
        if command -v gofmt >/dev/null 2>&1; then
            timeout 5 gofmt -w "$file_path" 2>/dev/null || true
        fi
        ;;
    rs)
        if command -v rustfmt >/dev/null 2>&1; then
            timeout 5 rustfmt "$file_path" 2>/dev/null || true
        fi
        ;;
    css|scss|less)
        if command -v prettier >/dev/null 2>&1; then
            timeout 5 prettier --write "$file_path" 2>/dev/null || true
        fi
        ;;
    html|vue|svelte)
        if command -v prettier >/dev/null 2>&1; then
            timeout 5 prettier --write "$file_path" 2>/dev/null || true
        fi
        ;;
esac

exit 0
