#!/usr/bin/env bash
# recursion-guard.sh — Track recursion depth across sub-agent dispatches.
# Uses /tmp/keep-recursion-{SESSION_ID} counter file.
# Default cap: 3 (yoyo-evolve standard).
#
# Usage:
#   recursion-enter            — Increment depth, exit 1 if over cap
#   recursion-exit             — Decrement depth
#   recursion-depth            — Print current depth
#   recursion-cap [N]          — Set cap (default 3)

set -euo pipefail

SESSION_ID="${KEEP_SESSION_ID:-${SESSION_ID:-default}}"
DEPTH_FILE="/tmp/keep-recursion-${SESSION_ID}"
CAP_FILE="/tmp/keep-recursion-cap-${SESSION_ID}"
DEFAULT_CAP=3

get_cap() {
  if [ -f "$CAP_FILE" ]; then
    cat "$CAP_FILE"
  else
    echo "$DEFAULT_CAP"
  fi
}

get_depth() {
  if [ -f "$DEPTH_FILE" ]; then
    cat "$DEPTH_FILE"
  else
    echo 0
  fi
}

cmd="${1:-}"
shift || true

case "$cmd" in
  recursion-enter)
    mkdir -p "$(dirname "$DEPTH_FILE")"
    current=$(get_depth)
    cap=$(get_cap)
    new=$((current + 1))
    if [ "$new" -gt "$cap" ]; then
      echo "RECURSION_LIMIT: depth=$new cap=$cap" >&2
      exit 1
    fi
    echo "$new" > "$DEPTH_FILE"
    ;;

  recursion-exit)
    if [ -f "$DEPTH_FILE" ]; then
      current=$(get_depth)
      new=$((current - 1))
      if [ "$new" -le 0 ]; then
        rm -f "$DEPTH_FILE"
      else
        echo "$new" > "$DEPTH_FILE"
      fi
    fi
    ;;

  recursion-depth)
    echo "$(get_depth)/$(get_cap)"
    ;;

  recursion-cap)
    cap="${1:-$DEFAULT_CAP}"
    mkdir -p "$(dirname "$CAP_FILE")"
    echo "$cap" > "$CAP_FILE"
    ;;

  *)
    echo "Usage: recursion-guard.sh {recursion-enter|recursion-exit|recursion-depth|recursion-cap [N]}" >&2
    exit 1
    ;;
esac
