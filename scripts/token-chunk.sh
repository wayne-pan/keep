#!/usr/bin/env bash
# token-chunk.sh — Token-aware chunking for large artifacts.
# Estimates token count from file size and decides chunking strategy.
#
# Formula: estimated_tokens = file_size_bytes / 4
# Thresholds:
#   <30k tokens → direct (read as-is)
#   30k-100k    → chunk at 20k tokens with 2k overlap
#   >100k       → reject (warn, suggest splitting)
#
# Usage:
#   token-estimate <file>              — Print estimated token count
#   token-strategy <file>              — Print: direct|chunk|reject
#   token-chunk <file> [chunk_tokens]  — Split file, print chunk file paths
#                                        Default chunk: 20000 tokens (80KB)
#                                        Overlap: 2000 tokens (8KB)

set -euo pipefail

BYTES_PER_TOKEN=4
DIRECT_THRESHOLD=30000    # tokens
CHUNK_SIZE=20000          # tokens per chunk
OVERLAP=2000              # tokens overlap
REJECT_THRESHOLD=100000   # tokens

file_size() {
  wc -c < "$1" 2>/dev/null || echo 0
}

estimate_tokens() {
  local size
  size=$(file_size "$1")
  echo $((size / BYTES_PER_TOKEN))
}

cmd="${1:-}"
shift || true

case "$cmd" in
  token-estimate)
    [ -z "${1:-}" ] && { echo "Usage: token-estimate <file>" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File not found: $1" >&2; exit 1; }
    estimate_tokens "$1"
    ;;

  token-strategy)
    [ -z "${1:-}" ] && { echo "Usage: token-strategy <file>" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File not found: $1" >&2; exit 1; }
    tokens=$(estimate_tokens "$1")
    if [ "$tokens" -lt "$DIRECT_THRESHOLD" ]; then
      echo "direct"
    elif [ "$tokens" -lt "$REJECT_THRESHOLD" ]; then
      echo "chunk"
    else
      echo "reject"
    fi
    ;;

  token-chunk)
    [ -z "${1:-}" ] && { echo "Usage: token-chunk <file> [chunk_tokens]" >&2; exit 1; }
    [ ! -f "$1" ] && { echo "File not found: $1" >&2; exit 1; }
    file="$1"
    chunk_tok="${2:-$CHUNK_SIZE}"
    chunk_bytes=$((chunk_tok * BYTES_PER_TOKEN))
    overlap_bytes=$((OVERLAP * BYTES_PER_TOKEN))
    step=$((chunk_bytes - overlap_bytes))

    total_tokens=$(estimate_tokens "$file")
    if [ "$total_tokens" -le "$chunk_bytes" ]; then
      # Fits in one chunk — just output the file
      echo "$file"
      exit 0
    fi

    # Create temp dir for chunks
    chunk_dir=$(mktemp -d "/tmp/keep-chunks-XXXXXX")
    file_size_bytes=$(file_size "$file")
    offset=0
    idx=0

    while [ "$offset" -lt "$file_size_bytes" ]; do
      chunk_file="$chunk_dir/chunk-$(printf '%03d' $idx)"
      # Extract chunk using dd
      dd if="$file" of="$chunk_file" bs=1 skip="$offset" count="$chunk_bytes" 2>/dev/null
      echo "$chunk_file"
      offset=$((offset + step))
      idx=$((idx + 1))
    done
    ;;

  *)
    echo "Usage: token-chunk.sh {token-estimate|token-strategy|token-chunk} <file> [args]" >&2
    exit 1
    ;;
esac
