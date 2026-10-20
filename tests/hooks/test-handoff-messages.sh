#!/usr/bin/env bash
# Pure-bash test runner for the handoff continuity contract — the behavioral
# text lives in 4 surfaces (handoff-early-warning.sh, handoff-enforce.sh,
# post-compact-bridge.sh, skills/handoff/SKILL.md) and must not drift back to
# the removed "tell the user to run /compact" interruption flow.
# Contract: hook-triggered or mid-task handoff → agent resumes in-session;
# native auto-compact fires on its own; zero human intervention.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WARN_HOOK="$REPO_ROOT/hooks/handoff-early-warning.sh"
ENFORCE_HOOK="$REPO_ROOT/hooks/handoff-enforce.sh"
BRIDGE_HOOK="$REPO_ROOT/hooks/post-compact-bridge.sh"
SKILL_MD="$REPO_ROOT/skills/handoff/SKILL.md"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq required"; exit 0; }

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
  jq -cn --arg tp "$1" '{transcript_path:$tp}'
}

usage_line() {
  printf '{"type":"assistant","message":{"usage":{"input_tokens":250000,"output_tokens":2000}}}\n'
}

# Shared env: 252k usage / 300k window = 84% > WARN_PCT — pipeline armed.
# Usage: hook_env <handoff_dir> <cmd...> — execs cmd with the pinned env.
hook_env() { # handoff_dir cmd...
  local hd="$1"; shift
  env -u DISABLE_AUTO_COMPACT \
    KEEP_HANDOFF_DIR="$hd" \
    CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 \
    "$@"
}

test_early_warning_directs_continue() {
  local tp_hd; tp_hd=$(fresh); local tp="$tp_hd/t.jsonl" hd="$tp_hd/hd"
  mkdir -p "$hd"; usage_line > "$tp"
  local out
  out=$(payload "$tp" | hook_env "$hd" bash "$WARN_HOOK" 2>/dev/null); local rc=$?
  rm -rf "$tp_hd"
  [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | grep -q 'CONTINUE the interrupted task' \
    && ! printf '%s' "$out" | grep -q 'tell the user to run'
}

test_enforce_blocks_with_resume_directive() {
  local tp_hd; tp_hd=$(fresh); local tp="$tp_hd/t.jsonl" hd="$tp_hd/hd"
  mkdir -p "$hd"; usage_line > "$tp"
  local out
  out=$(printf '{"transcript_path":"%s","tool_input":{"command":"echo hi"}}' "$tp" \
    | hook_env "$hd" bash "$ENFORCE_HOOK" 2>&1); local rc=$?
  rm -rf "$tp_hd"
  [ "$rc" -eq 2 ] \
    && printf '%s' "$out" | grep -q 'resume the interrupted task' \
    && ! printf '%s' "$out" | grep -q 'tell the user to run'
}

test_enforce_opens_with_fresh_doc() {
  local tp_hd; tp_hd=$(fresh); local tp="$tp_hd/t.jsonl" hd="$tp_hd/hd"
  mkdir -p "$hd"; usage_line > "$tp"; echo "# handoff" > "$hd/keep-handoff-x.md"
  printf '{"transcript_path":"%s","tool_input":{"command":"echo hi"}}' "$tp" \
    | hook_env "$hd" bash "$ENFORCE_HOOK" >/dev/null 2>&1; local rc=$?
  rm -rf "$tp_hd"
  [ "$rc" -eq 0 ]
}

test_bridge_directs_continue_with_ask_escape() {
  local hd; hd=$(fresh); echo "# snapshot" > "$hd/keep-handoff-b.md"
  local out
  out=$(printf '{}' | KEEP_HANDOFF_DIR="$hd" bash "$BRIDGE_HOOK" 2>/dev/null); local rc=$?
  rm -rf "$hd"
  [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | grep -q 'Continue the interrupted task' \
    && printf '%s' "$out" | grep -q 'genuine user decision' \
    && ! printf '%s' "$out" | grep -q 'do not stop to ask'
}

test_skill_closes_by_intent() {
  grep -q 'Close by intent' "$SKILL_MD" \
    && grep -q 'Continuity mode' "$SKILL_MD" \
    && grep -q 'Fork mode' "$SKILL_MD" \
    && ! grep -q 'tell the user to run' "$SKILL_MD"
}

test_freshness_windows_pinned() { # dwell fix: 60min keeps mid-band dwells unblocked
  grep -q 'DOC_FRESH_MIN=60' "$WARN_HOOK" \
    && grep -q 'DOC_FRESH_MIN=60' "$ENFORCE_HOOK" \
    && grep -q 'GATE_FRESH_MIN=60' "$REPO_ROOT/hooks/handoff-gate.sh"
}

run "early-warning directs CONTINUE, no manual /compact" test_early_warning_directs_continue
run "enforce block carries resume directive"            test_enforce_blocks_with_resume_directive
run "enforce opens with fresh doc"                      test_enforce_opens_with_fresh_doc
run "bridge: continue + ask-escape, no blanket no-ask"  test_bridge_directs_continue_with_ask_escape
run "SKILL.md closes by intent (both modes)"            test_skill_closes_by_intent
run "freshness windows pinned at 60min"                 test_freshness_windows_pinned

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
