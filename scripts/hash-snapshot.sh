#!/usr/bin/env bash
# hash-snapshot.sh — Manage SHA256 hashes of constitutional files.
# Constitutional files: CLAUDE.md, rules/core.md, hooks/safety-guard.sh
#
# Usage:
#   hash-snapshot update   — Recompute hashes for all constitutional files
#   hash-snapshot verify   — Check all hashes, report mismatches
#   hash-snapshot diff     — Show which files changed since snapshot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HASH_FILE="$PROJECT_DIR/.claude/hashes.json"

CONSTITUTIONAL_FILES=(
  "CLAUDE.md"
  "rules/core.md"
  "hooks/safety-guard.sh"
)

ensure_hash_file() {
  mkdir -p "$(dirname "$HASH_FILE")"
  [ -f "$HASH_FILE" ] || echo '{}' > "$HASH_FILE"
}

cmd="${1:-}"

case "$cmd" in
  update)
    ensure_hash_file
    for f in "${CONSTITUTIONAL_FILES[@]}"; do
      filepath="$PROJECT_DIR/$f"
      if [ -f "$filepath" ]; then
        hash=$(sha256sum "$filepath" | cut -d' ' -f1)
        # Update JSON using jq
        tmp=$(mktemp)
        jq --arg file "$f" --arg hash "$hash" '.[$file] = $hash' "$HASH_FILE" > "$tmp" && mv "$tmp" "$HASH_FILE"
        echo "$f: $hash"
      fi
    done
    echo "Hashes updated: $HASH_FILE"
    ;;

  verify)
    ensure_hash_file
    mismatches=0
    for f in "${CONSTITUTIONAL_FILES[@]}"; do
      filepath="$PROJECT_DIR/$f"
      stored=$(jq -r ".[\"$f\"] // empty" "$HASH_FILE" 2>/dev/null || echo "")
      if [ -z "$stored" ]; then
        echo "NO_SNAPSHOT: $f (run hash-snapshot update)"
        continue
      fi
      if [ ! -f "$filepath" ]; then
        echo "MISSING: $f (file deleted)"
        mismatches=$((mismatches + 1))
        continue
      fi
      current=$(sha256sum "$filepath" | cut -d' ' -f1)
      if [ "$current" != "$stored" ]; then
        echo "MISMATCH: $f"
        echo "  stored:   $stored"
        echo "  current:  $current"
        mismatches=$((mismatches + 1))
      else
        echo "OK: $f"
      fi
    done
    if [ "$mismatches" -gt 0 ]; then
      echo "WARNING: $mismatches constitutional file(s) changed since last snapshot"
      exit 1
    fi
    ;;

  diff)
    ensure_hash_file
    for f in "${CONSTITUTIONAL_FILES[@]}"; do
      filepath="$PROJECT_DIR/$f"
      stored=$(jq -r ".[\"$f\"] // empty" "$HASH_FILE" 2>/dev/null || echo "")
      [ -z "$stored" ] && continue
      [ ! -f "$filepath" ] && { echo "DELETED: $f"; continue; }
      current=$(sha256sum "$filepath" | cut -d' ' -f1)
      [ "$current" != "$stored" ] && echo "CHANGED: $f"
    done
    ;;

  *)
    echo "Usage: hash-snapshot.sh {update|verify|diff}" >&2
    exit 1
    ;;
esac
