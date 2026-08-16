#!/usr/bin/env bash
# Pure-bash test for the seedPaths snippet embedded in prototype + loop SKILL.md.
# Extracts the marked snippet and executes it against a fixture repo with a
# committed file, a modified file, and an untracked file.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROTO="$REPO_ROOT/skills/prototype/SKILL.md"
LOOP="$REPO_ROOT/skills/loop/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

run() {
  local name="$1" fn="$2"
  if "$fn"; then
    echo "PASS: $name"; PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name"; FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

extract_snippet() { # file -> stdout bash code
  sed -n '/<!-- seed-begin -->/,/<!-- seed-end -->/p' "$1" | sed '1d;$d' | grep -v '^```'
}

make_repo() { # dir
  git -C "$1" init -q
  git -C "$1" config user.email t@t && git -C "$1" config user.name t
  echo base > "$1/committed.txt"
  git -C "$1" add committed.txt && git -C "$1" commit -qm base
  echo changed > "$1/inflight.txt"
  git -C "$1" add inflight.txt && git -C "$1" commit -qm inflight
  echo dirty > "$1/inflight.txt"
  echo new > "$1/fresh-note.md"
  echo junk > "$1/scratch.log"
}

test_snippet_in_prototype() {
  [ "$(extract_snippet "$PROTO" | grep -c 'SEED_SRC')" -ge 1 ]
}

test_snippet_in_loop() {
  [ "$(extract_snippet "$LOOP" | grep -c 'SEED_SRC')" -ge 1 ]
}

test_snippet_copies_dirty_and_untracked() {
  local src dst code
  src=$(mktemp -d); dst=$(mktemp -d)
  make_repo "$src"
  mkdir -p "$src/notes" && echo draft > "$src/notes/draft.md"
  code=$(extract_snippet "$PROTO")
  [ -n "$code" ] || { rm -rf "$src" "$dst"; return 1; }
  SEED_SRC="$src" SEED_DST="$dst" bash -c "$code"
  local ok=1
  [ "$(cat "$dst/inflight.txt" 2>/dev/null)" = "dirty" ] || ok=0
  [ "$(cat "$dst/fresh-note.md" 2>/dev/null)" = "new" ] || ok=0
  [ "$(cat "$dst/notes/draft.md" 2>/dev/null)" = "draft" ] || ok=0
  [ ! -f "$dst/scratch.log" ] || ok=0
  [ ! -f "$dst/committed.txt" ] || ok=0
  rm -rf "$src" "$dst"
  [ "$ok" -eq 1 ]
}

# --- Run ---
run "seed snippet present in prototype SKILL.md" test_snippet_in_prototype
run "seed snippet present in loop SKILL.md" test_snippet_in_loop
run "snippet copies dirty + untracked, skips junk + clean" test_snippet_copies_dirty_and_untracked

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
