#!/usr/bin/env bash
# nonce-wrap.sh — Wrap/unwrap/verify external content with nonce markers.
# Prevents prompt injection when processing untrusted content.
#
# Usage:
#   nonce-wrap              — Wrap stdin with nonce markers, print to stdout
#   nonce-wrap < content    — Same (pipe)
#   nonce-unwrap            — Extract content between nonce markers from stdin
#   nonce-verify            — Verify nonce markers match, exit 1 on mismatch

set -euo pipefail

generate_nonce() {
  # Short, unique nonce: timestamp + random suffix
  echo "nonce-$(date +%s)-$(head -c 4 /dev/urandom | xxd -p 2>/dev/null || echo $RANDOM)"
}

cmd="${1:-}"

case "$cmd" in
  nonce-wrap)
    nonce=$(generate_nonce)
    content=$(cat)
    echo "---BEGIN EXTERNAL [$nonce]---"
    printf '%s' "$content"
    echo ""
    echo "---END EXTERNAL [$nonce]---"
    ;;

  nonce-unwrap)
    # Extract content between BEGIN/END markers
    sed -n '/^---BEGIN EXTERNAL \[.*\]---$/,/^---END EXTERNAL \[.*\]---$/{ /^---BEGIN EXTERNAL/d; /^---END EXTERNAL/d; p; }'
    ;;

  nonce-verify)
    content=$(cat)
    begin_nonce=$(echo "$content" | grep -oP '^---BEGIN EXTERNAL \[\K[^\]]+' | head -1)
    end_nonce=$(echo "$content" | grep -oP '^---END EXTERNAL \[\K[^\]]+' | head -1)
    if [ -z "$begin_nonce" ] || [ -z "$end_nonce" ]; then
      echo "INVALID: missing nonce markers" >&2
      exit 1
    fi
    if [ "$begin_nonce" != "$end_nonce" ]; then
      echo "MISMATCH: begin=[$begin_nonce] end=[$end_nonce]" >&2
      exit 1
    fi
    echo "OK: [$begin_nonce]"
    ;;

  *)
    echo "Usage: nonce-wrap.sh {nonce-wrap|nonce-unwrap|nonce-verify}" >&2
    echo "  nonce-wrap    Wrap stdin with nonce markers" >&2
    echo "  nonce-unwrap  Extract content between markers" >&2
    echo "  nonce-verify  Check markers match" >&2
    exit 1
    ;;
esac
