#!/usr/bin/env bash
# classify-observation.sh — Tag memory observations with mutability tier.
# Uses mind MCP to add concept tags: immutable, append-only, overwritable.
#
# Usage:
#   classify-observation <id> <tier>
#   classify-observation <id> immutable     — Constitutional, never pruned
#   classify-observation <id> append-only   — History, summarized only
#   classify-observation <id> overwritable  — Working state, freely pruned

set -euo pipefail

id="${1:-}"
tier="${2:-}"

if [ -z "$id" ] || [ -z "$tier" ]; then
  echo "Usage: classify-observation <id> <immutable|append-only|overwritable>" >&2
  exit 1
fi

case "$tier" in
  immutable|append-only|overwritable)
    # Valid tier
    ;;
  *)
    echo "Invalid tier: $tier. Must be: immutable, append-only, overwritable" >&2
    exit 1
    ;;
esac

# Output MCP-compatible instruction for mind observation tagging
# This script is meant to be called as a utility; the actual MCP call
# happens through Claude Code's tool use.
echo "Tag observation $id with concept:$tier"
echo "Use: mcp__mind__remember concepts=[\"$tier\"] to classify"
