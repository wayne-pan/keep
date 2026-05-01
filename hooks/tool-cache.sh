#!/usr/bin/env bash
# tool-cache.sh — PreToolUse/PostToolUse hook for MCP tool result caching.
# Caches smart_outline/smart_search results to avoid redundant expensive calls.
#
# Cache location: /tmp/keep-cache-{SESSION_ID}/
# Cache key: tool_name + arguments hash
# TTL: session-scoped (auto-cleaned)
#
# PreToolUse: checks cache, provides cached result as additionalContext
# PostToolUse: stores result in cache

set -euo pipefail

SESSION_ID="${KEEP_SESSION_ID:-${SESSION_ID:-default}}"
CACHE_DIR="/tmp/keep-cache-${SESSION_ID}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only cache MCP tools
CACHEABLE_TOOLS=("mcp__mind__smart_outline" "mcp__mind__smart_search" "mcp__codedb__codedb_outline")
is_cacheable=false
for t in "${CACHEABLE_TOOLS[@]}"; do
  if [ "$TOOL" = "$t" ]; then
    is_cacheable=true
    break
  fi
done

[ "$is_cacheable" = false ] && exit 0

# Generate cache key from tool name + arguments
ARGS_JSON=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || echo '{}')
CACHE_KEY=$(echo -n "${TOOL}:${ARGS_JSON}" | sha256sum | cut -d' ' -f1)
CACHE_FILE="${CACHE_DIR}/${CACHE_KEY}.json"

cmd="${1:-}"

case "$cmd" in
  pre)
    # PreToolUse: check cache
    if [ -f "$CACHE_FILE" ]; then
      cached=$(cat "$CACHE_FILE")
      # Return cached result as additional context so the caller can skip
      jq -n --arg cached "$cached" '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "additionalContext": ("[tool-cache] Cached result available: " + $cached)
        }
      }'
    fi
    ;;

  post)
    # PostToolUse: store result
    mkdir -p "$CACHE_DIR"
    RESULT=$(echo "$INPUT" | jq -c '.tool_result // empty' 2>/dev/null || echo "")
    if [ -n "$RESULT" ]; then
      echo "$RESULT" > "$CACHE_FILE"
    fi
    ;;

  *)
    # Auto-detect: check if this is PreToolUse or PostToolUse
    EVENT=$(echo "$INPUT" | jq -r '.hook_event // empty')
    if [ "$EVENT" = "PreToolUse" ]; then
      if [ -f "$CACHE_FILE" ]; then
        cached=$(cat "$CACHE_FILE")
        jq -n --arg cached "$cached" '{
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": ("[tool-cache] Cached result: " + $cached)
          }
        }'
      fi
    elif [ "$EVENT" = "PostToolUse" ]; then
      mkdir -p "$CACHE_DIR"
      RESULT=$(echo "$INPUT" | jq -c '.tool_result // empty' 2>/dev/null || echo "")
      [ -n "$RESULT" ] && echo "$RESULT" > "$CACHE_FILE"
    fi
    ;;
esac

exit 0
