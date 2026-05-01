#!/usr/bin/env bash
# codedb-reindex.sh — PostToolUse hook: incremental reindex after file edits.
# Triggers when Write/Edit modifies a source file, updates the symbol index.
set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]] && exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0

# Only reindex source files
ext="${file_path##*.}"
[[ ! "$ext" =~ ^(sh|py|js|ts|go|rs|rb|java)$ ]] && exit 0

# Skip if no .codedb directory exists (project not indexed)
project_root="$PWD"
while [[ "$project_root" != "/" ]]; do
  if [[ -d "$project_root/.codedb" ]]; then
    break
  fi
  project_root=$(dirname "$project_root")
done
[[ "$project_root" == "/" ]] && exit 0

# Incremental reindex in background (don't block Claude)
(
  python3 -c "
import sys
sys.path.insert(0, '$project_root')
from mem.codeparse.indexer import ProjectIndex
idx = ProjectIndex('$project_root')
idx.update_file('$file_path')
" 2>/dev/null
) &

exit 0
