#!/usr/bin/env bash
# Pure-bash test runner for hooks/metrics-log.sh — costs.jsonl append on Stop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/hooks/metrics-log.sh"

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

make_transcript() { # path
  cat > "$1" <<'EOF'
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6-20260101","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":200,"cache_read_input_tokens":8000}}}
{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6-20260101","usage":{"input_tokens":3000,"output_tokens":1500,"cache_creation_input_tokens":0,"cache_read_input_tokens":20000}}}
EOF
}

make_pricing() { # path
  cat > "$1" <<'EOF'
{
  "models": {"opus": {"in": 15, "out": 75, "provider": "anthropic", "context": 200000}},
  "_cache": {"write_mult": 1.25, "read_mult": 0.10}
}
EOF
}

stdin_payload() { # session transcript cwd
  jq -cn --arg s "$1" --arg t "$2" --arg c "$3" '{session_id:$s, transcript_path:$t, cwd:$c, stop_hook_active:true}'
}

test_appends_valid_row() {
  local tmp; tmp=$(mktemp -d)
  make_transcript "$tmp/transcript.jsonl"; make_pricing "$tmp/pricing.json"
  printf '%s' "$(stdin_payload t-metrics "$tmp/transcript.jsonl" "$tmp/myproj")" \
    | METRICS_DIR="$tmp/metrics" PRICING_FILE="$tmp/pricing.json" SCOPE_STATE_DIR="$tmp" bash "$HOOK_PATH" >/dev/null 2>&1
  local rc=$? row
  row=$(tail -1 "$tmp/metrics/costs.jsonl" 2>/dev/null)
  local ok=1
  [ "$rc" -eq 0 ] || ok=0
  [ -n "$row" ] || ok=0
  echo "$row" | jq -e '.session_id == "t-metrics" and .project == "myproj" and .model == "claude-opus-4-6-20260101"' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.tokens.in == 4000 and .tokens.out == 2000 and .tokens.cache_w == 200 and .tokens.cache_r == 28000' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.cost_usd > 0.25 and .cost_usd < 0.26' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.tool_calls == null and .estimated == true' >/dev/null 2>&1 || ok=0
  rm -rf "$tmp"
  [ "$ok" -eq 1 ]
}

test_tool_calls_from_scope_state() {
  local tmp; tmp=$(mktemp -d)
  make_transcript "$tmp/transcript.jsonl"; make_pricing "$tmp/pricing.json"
  printf 'count=42\nfiles=\n' > "$tmp/claude-scope-t-tools"
  printf '%s' "$(stdin_payload t-tools "$tmp/transcript.jsonl" "$tmp/myproj")" \
    | METRICS_DIR="$tmp/metrics" PRICING_FILE="$tmp/pricing.json" SCOPE_STATE_DIR="$tmp" bash "$HOOK_PATH" >/dev/null 2>&1
  local row; row=$(tail -1 "$tmp/metrics/costs.jsonl" 2>/dev/null)
  rm -rf "$tmp"
  echo "$row" | jq -e '.tool_calls == 42' >/dev/null 2>&1
}

test_missing_pricing_null_cost() {
  local tmp; tmp=$(mktemp -d)
  make_transcript "$tmp/transcript.jsonl"
  printf '%s' "$(stdin_payload t-noprice "$tmp/transcript.jsonl" "$tmp/myproj")" \
    | METRICS_DIR="$tmp/metrics" PRICING_FILE="$tmp/nonexistent.json" bash "$HOOK_PATH" >/dev/null 2>&1
  local rc=$? row
  row=$(tail -1 "$tmp/metrics/costs.jsonl" 2>/dev/null)
  local ok=1
  [ "$rc" -eq 0 ] || ok=0
  echo "$row" | jq -e '.cost_usd == null and .estimated == true' >/dev/null 2>&1 || ok=0
  rm -rf "$tmp"
  [ "$ok" -eq 1 ]
}

test_appends_not_overwrites() {
  local tmp; tmp=$(mktemp -d)
  make_transcript "$tmp/transcript.jsonl"; make_pricing "$tmp/pricing.json"
  mkdir -p "$tmp/metrics"; printf '{"old":true}\n' > "$tmp/metrics/costs.jsonl"
  printf '%s' "$(stdin_payload t-append "$tmp/transcript.jsonl" "$tmp/myproj")" \
    | METRICS_DIR="$tmp/metrics" PRICING_FILE="$tmp/pricing.json" bash "$HOOK_PATH" >/dev/null 2>&1
  local lines; lines=$(wc -l < "$tmp/metrics/costs.jsonl")
  rm -rf "$tmp"
  [ "$lines" -eq 2 ]
}

test_registered_in_installer() {
  grep -q 'metrics-log' "$REPO_ROOT/scripts/install.sh"
}

test_poisoned_count_defaults_to_null() {
  local tmp; tmp=$(mktemp -d)
  make_transcript "$tmp/transcript.jsonl"; make_pricing "$tmp/pricing.json"
  printf 'count=abc123\nfiles=\n' > "$tmp/claude-scope-t-poison"
  printf '%s' "$(stdin_payload t-poison "$tmp/transcript.jsonl" "$tmp/myproj")" \
    | METRICS_DIR="$tmp/metrics" PRICING_FILE="$tmp/pricing.json" SCOPE_STATE_DIR="$tmp" bash "$HOOK_PATH" >/dev/null 2>&1
  local row; row=$(tail -1 "$tmp/metrics/costs.jsonl" 2>/dev/null)
  rm -rf "$tmp"
  echo "$row" | jq -e '.tool_calls == null' >/dev/null 2>&1
}

# --- Run ---
run "appends valid costs.jsonl row" test_appends_valid_row
run "tool_calls from scope state" test_tool_calls_from_scope_state
run "missing pricing → null cost, exit 0" test_missing_pricing_null_cost
run "appends, never overwrites" test_appends_not_overwrites
run "metrics-log registered in install.sh" test_registered_in_installer
run "poisoned non-numeric count → tool_calls null, row survives" test_poisoned_count_defaults_to_null

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
