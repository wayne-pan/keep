#!/usr/bin/env bash
# Pure-bash test runner for hooks/handoff-gate.sh — PreCompact gate decisions.
# Cases: fresh doc, missing doc (block), overflow escape, recovered overflow
# (block), non-overflow API error (block), stale doc (block).

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

usage_line() { # input_tokens
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"output_tokens":10}}}\n' "$1"
}

err_line() { # error text
  jq -cn --arg t "$1" '{type:"assistant",isApiErrorMessage:true,message:{content:[{type:"text",text:$t}]}}'
}

test_fresh_doc_allows() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local doc="$tmp/keep-handoff-test.md"; echo "# handoff" > "$doc"
  local out rc
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && ! echo "$out" | grep -q handoff-gate
}

test_missing_doc_blocks() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local out rc
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Run /keep:handoff first'
}

test_stale_doc_blocks() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local doc="$tmp/keep-handoff-old.md"; echo "# handoff" > "$doc"
  touch -d '2 hours ago' "$doc"
  local out rc
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 2 ]
}

test_overflow_after_last_success_yields() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 195000
    err_line 'API Error: 400 ... prompt is too long: 210323 tokens > 200000 maximum'
  } > "$tp"
  local out rc
  out=$(hook_run "$(payload "$tp")"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "$out" | grep -q yielding
}

test_cn_overflow_yields() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 190000
    err_line 'API Error: 请求超出上下文长度限制 (maximum context length 131072)'
  } > "$tp"
  local out rc
  out=$(hook_run "$(payload "$tp")"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "$out" | grep -q yielding
}

test_recovered_overflow_blocks() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 195000
    err_line 'API Error: 400 ... prompt is too long: 210323 tokens > 200000 maximum'
    usage_line 4200    # model succeeded again after the error
  } > "$tp"
  local out rc
  out=$(hook_run "$(payload "$tp")"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 2 ]
}

test_nonoverflow_error_blocks() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  local tp="$tmp/transcript.jsonl"
  { usage_line 195000
    err_line 'API Error: 429 rate limit exceeded, please retry'
  } > "$tp"
  local out rc
  out=$(hook_run "$(payload "$tp")"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 2 ]
}

test_symlink_doc_ignored() {
  local tmp; tmp=$(fresh); export KEEP_HANDOFF_DIR="$tmp"
  echo "# evil" > "$tmp/real.md"
  ln -s "$tmp/real.md" "$tmp/keep-handoff-sneaky.md"
  local out rc
  out=$(hook_run "$(payload /nonexistent.jsonl)"); rc=$?
  unset KEEP_HANDOFF_DIR; rm -rf "$tmp"
  [ "$rc" -eq 2 ]
}

run "fresh doc allows compact"            test_fresh_doc_allows
run "missing doc blocks (manual escape shown)" test_missing_doc_blocks
run "stale doc (>60min) blocks"           test_stale_doc_blocks
run "overflow after last success yields"  test_overflow_after_last_success_yields
run "CN overflow wording yields"          test_cn_overflow_yields
run "recovered overflow (success after error) blocks" test_recovered_overflow_blocks
run "non-overflow API error (429) blocks" test_nonoverflow_error_blocks
run "symlink handoff doc ignored"         test_symlink_doc_ignored

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
