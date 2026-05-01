#!/usr/bin/env bash
# kv-store.sh — File-based KV store for sub-agent shared state.
# Uses /tmp/keep-kv-{SESSION_ID}/ for isolation.
#
# Usage:
#   kv-set <key> <value>     — Set a key
#   kv-set <key> -           — Set key from stdin
#   kv-get <key>             — Get a key (empty if missing)
#   kv-ls                    — List all keys
#   kv-rm <key>              — Remove a key
#   kv-clear                 — Clear all keys for this session

set -euo pipefail

SESSION_ID="${KEEP_SESSION_ID:-${SESSION_ID:-default}}"
KV_DIR="/tmp/keep-kv-${SESSION_ID}"

cmd="${1:-}"
shift || true

case "$cmd" in
  kv-set)
    [ -z "${1:-}" ] && { echo "Usage: kv-set <key> <value>" >&2; exit 1; }
    key="$1"; shift || true
    mkdir -p "$KV_DIR"
    # Sanitize key: replace slashes with underscores
    safe_key=$(echo "$key" | tr '/' '_')
    if [ "${1:-}" = "-" ]; then
      cat > "$KV_DIR/$safe_key"
    else
      printf '%s' "$*" > "$KV_DIR/$safe_key"
    fi
    ;;

  kv-get)
    [ -z "${1:-}" ] && { echo "Usage: kv-get <key>" >&2; exit 1; }
    safe_key=$(echo "$1" | tr '/' '_')
    if [ -f "$KV_DIR/$safe_key" ]; then
      cat "$KV_DIR/$safe_key"
    fi
    ;;

  kv-ls)
    if [ -d "$KV_DIR" ]; then
      ls -1 "$KV_DIR/" 2>/dev/null
    fi
    ;;

  kv-rm)
    [ -z "${1:-}" ] && { echo "Usage: kv-rm <key>" >&2; exit 1; }
    safe_key=$(echo "$1" | tr '/' '_')
    rm -f "$KV_DIR/$safe_key"
    ;;

  kv-clear)
    rm -rf "$KV_DIR"
    ;;

  *)
    echo "Usage: kv-store.sh {kv-set|kv-get|kv-ls|kv-rm|kv-clear}" >&2
    echo "  kv-set <key> <value|->  Set key (use - for stdin)" >&2
    echo "  kv-get <key>            Get value" >&2
    echo "  kv-ls                   List keys" >&2
    echo "  kv-rm <key>             Remove key" >&2
    echo "  kv-clear                Clear all" >&2
    exit 1
    ;;
esac
