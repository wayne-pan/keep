#!/usr/bin/env bash
# Pure-bash test runner for hooks/handoff-gate.sh — PreCompact gate decisions.
# Contract (auto-snapshot era): fresh doc passes clean; overflow yields with a
# note; anything else writes a keep-handoff-auto-*.md snapshot and yields.
# Gate NEVER exits 2 — a block can't self-chain into "handoff then compact".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/hooks/handoff-gate.sh"

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

fresh() { mktemp -d; }

payload() { # transcript_path
  jq -cn --arg tp "$1" '{transcript_path:$tp, trigger:"auto"}'
}

hook_run() { # payload
  printf '%s' "$1" | bash "$HOOK_PATH" 2>&1
}

autos() { # dir -> count of auto snapshots written
  ls "$1"/keep-handoff-auto-*.md 2>/dev/null | wc -l
}

usage_line() { # input_tokens
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"output_tokens":10}}}\n' "$1"
}

err_line() { # error text
  jq -cn --arg t "$1" '{type:"assistant",isApiErrorMessage:true,message:{content:[{type:"text",text:$t}]}}'
}

test_fresh_doc_allows() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local doc="$tmp/keep-handoff-test.md"; echo "# handoff" > "$doc"
  local out rc n
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  n=$(autos "$tmp")
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && ! echo "$out" | grep -q handoff-gate && [ "$n" -eq 0 ]
}

test_missing_doc_autosnap() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local out rc n mode
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  n=$(autos "$tmp")
  mode=$(stat -c %a "$tmp"/keep-handoff-auto-*.md 2>/dev/null || echo 000)
  local has_tp
  has_tp=$(grep -c '/nonexistent.jsonl' "$tmp"/keep-handoff-auto-*.md 2>/dev/null || echo 0)
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "$out" | grep -q 'auto-snapshot written' \
    && [ "$n" -eq 1 ] && [ "$mode" -eq 600 ] && [ "$has_tp" -ge 1 ]
}

test_stale_doc_autosnap() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local doc="$tmp/keep-handoff-old.md"; echo "# handoff" > "$doc"
  touch -d '2 hours ago' "$doc"
  local out rc n
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  n=$(autos "$tmp")
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && [ "$n" -eq 1 ]
}

test_overflow_after_last_success_yields() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 195000
    err_line 'API Error: 400 ... prompt is too long: 210323 tokens > 200000 maximum'
  } > "$tp"
  local out rc n
  out=$(hook_run "$(payload "$tp")"); rc=$?
  n=$(autos "$tmp")
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "$out" | grep -q yielding && [ "$n" -eq 0 ]
}

test_cn_overflow_yields() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 190000
    err_line 'API Error: 请求超出上下文长度限制 (maximum context length 131072)'
  } > "$tp"
  local out rc n
  out=$(hook_run "$(payload "$tp")"); rc=$?
  n=$(autos "$tmp")
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "$out" | grep -q yielding && [ "$n" -eq 0 ]
}

test_recovered_overflow_autosnap() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 195000
    err_line 'API Error: 400 ... prompt is too long: 210323 tokens > 200000 maximum'
    usage_line 4200    # model succeeded again after the error
  } > "$tp"
  local out rc n
  out=$(hook_run "$(payload "$tp")"); rc=$?
  n=$(autos "$tmp")
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "$out" | grep -q 'auto-snapshot written' && [ "$n" -eq 1 ]
}

test_nonoverflow_error_autosnap() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 195000
    err_line 'API Error: 429 rate limit exceeded, please retry'
  } > "$tp"
  local out rc n
  out=$(hook_run "$(payload "$tp")"); rc=$?
  n=$(autos "$tmp")
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && [ "$n" -eq 1 ]
}

test_symlink_doc_ignored_autosnap() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  echo "# evil" > "$tmp/real.md"
  ln -s "$tmp/real.md" "$tmp/keep-handoff-sneaky.md"
  local out rc n
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  n=$(autos "$tmp")
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && [ "$n" -eq 1 ]
}

test_missing_dir_autosnap() {
  local tmp; tmp=$(fresh)
  local absent="$tmp/handoffs-absent"
  export KEEP_HANDOFF_DIR="$absent"
  local out rc
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  local ok=0
  [ "$rc" -eq 0 ] && [ -s "$absent/keep-handoff-auto-"*.md ] && ok=1
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$ok" -eq 1 ]
}

test_unwritable_dir_failopen() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  chmod 555 "$tmp"
  local out rc n
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  n=$(autos "$tmp")
  chmod 700 "$tmp"   # restore before cleanup
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "$out" | grep -q 'write failed' && [ "$n" -eq 0 ]
}

run "fresh doc allows compact, no snapshot"        test_fresh_doc_allows
run "missing doc auto-snapshots (mode 600 + tp)"   test_missing_doc_autosnap
run "stale doc (>60min) auto-snapshots"            test_stale_doc_autosnap
run "overflow after last success yields"           test_overflow_after_last_success_yields
run "CN overflow wording yields"                   test_cn_overflow_yields
run "recovered overflow auto-snapshots"            test_recovered_overflow_autosnap
run "non-overflow API error (429) auto-snapshots"  test_nonoverflow_error_autosnap
run "symlink handoff doc ignored, auto-snapshots"  test_symlink_doc_ignored_autosnap
run "missing handoff dir is created (mkdir -p)"    test_missing_dir_autosnap
run "unwritable dir fails open"                    test_unwritable_dir_failopen

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
