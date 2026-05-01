#!/usr/bin/env bash
# update-code-map.sh — PostToolUse hook: incremental code map update
# Maintains .sprint/CODE_MAP.md with function/class locations.
# Only re-scans files that were just edited.
set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]] && exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0

# Only scan source files
ext="${file_path##*.}"
[[ ! "$ext" =~ ^(sh|py|js|ts|go|rs|rb|java)$ ]] && exit 0

map_file=".sprint/CODE_MAP.md"
mkdir -p .sprint

# Extract symbols from the edited file
symbols=""
case "$ext" in
    sh)
        symbols=$(grep -n -E "^(function\s+\w+|^\w+\(\))" "$file_path" 2>/dev/null \
            | sed 's/^\([0-9]*\):function\s\+\(\w\+\).*/\2():\1/' \
            | sed 's/^\([0-9]*\):\(\w\+\)().*/\2():\1/' || true)
        ;;
    py)
        symbols=$(grep -n -E "^(def |class |async def )" "$file_path" 2>/dev/null \
            | sed 's/^\([0-9]*\):async def \(\w\+\).*/\2():\1/' \
            | sed 's/^\([0-9]*\):def \(\w\+\).*/\2():\1/' \
            | sed 's/^\([0-9]*\):class \(\w\+\).*/\2:\1/' || true)
        ;;
    js|ts)
        symbols=$(grep -n -E "(function\s+\w+|const\s+\w+\s*=\s*(\(|async)|class\s+\w+|export\s+(function|class|const))" "$file_path" 2>/dev/null \
            | sed -E 's/^[0-9]+:(function |const |class |export function |export class |export const )//' \
            | sed -E 's/[(\s=:].*//' \
            | paste -d':' - <(grep -n -E "(function\s+\w+|const\s+\w+\s*=\s*(\(|async)|class\s+\w+|export)" "$file_path" 2>/dev/null | sed 's/:.*//') \
            | sed 's/\(..*\):\(..*\)/\1():\2/' || true)
        ;;
esac

[[ -z "$symbols" ]] && exit 0

# Remove old entry for this file from the map, then append new
rel_path="${file_path#$PWD/}"
if [ -f "$map_file" ]; then
    # Remove the section for this file (## path → next ## or EOF)
    sed -i "/^## ${rel_path//\//\\/}$/,/^## /{ /^## ${rel_path//\//\\/}$/d; /^## /!d }" "$map_file" 2>/dev/null || true
fi

# Append new entry
{
    echo ""
    echo "## $rel_path"
    while IFS= read -r line; do
        [[ -n "$line" ]] && echo "- $line"
    done <<< "$symbols"
} >> "$map_file"

# Keep map under 200 lines
if [ "$(wc -l < "$map_file")" -gt 200 ]; then
    head -200 "$map_file" > "$map_file.tmp" && mv "$map_file.tmp" "$map_file"
fi
