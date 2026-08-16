#!/usr/bin/env bash
# metrics-log.sh — Stop hook: append session cost/token metrics to costs.jsonl
# Longitudinal log for benchmark + loop budget data. Never blocks the Stop chain:
# every failure path exits 0.
#
# Row schema: {ts, session_id, project, model, tokens:{in,out,cache_w,cache_r},
#              cost_usd, tool_calls, estimated:true}
# cost_usd is an estimate (model substring match against pricing.json).

set -u

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
PROJECT="unknown"
[ -n "$CWD" ] && [ "$CWD" != "null" ] && PROJECT=$(basename "$CWD")

METRICS_DIR="${METRICS_DIR:-$HOME/.claude/metrics}"
mkdir -p "$METRICS_DIR" 2>/dev/null || exit 0
OUT_FILE="$METRICS_DIR/costs.jsonl"

# Pricing resolution: explicit override respected as-is; fallback only when unset
if [ -z "${PRICING_FILE:-}" ]; then
  PRICING_FILE=""
  for p in "$HOME/.local/share/keep/scripts/pricing.json" "$HOME/.claude/scripts/pricing.json"; do
    if [ -f "$p" ]; then PRICING_FILE="$p"; break; fi
  done
fi

# --- Token usage + model from transcript (jq -s over JSONL lines) ---
T_IN=0 T_OUT=0 T_CW=0 T_CR=0
MODEL="null"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  SUMS=$(jq -s '
    [ .[] | select(.message.usage != null) | .message.usage ] as $u |
    {
      in:  ([$u[].input_tokens // 0] | add // 0),
      out: ([$u[].output_tokens // 0] | add // 0),
      cw:  ([$u[].cache_creation_input_tokens // 0] | add // 0),
      cr:  ([$u[].cache_read_input_tokens // 0] | add // 0)
    }' "$TRANSCRIPT" 2>/dev/null) || SUMS=""
  if [ -n "$SUMS" ]; then
    T_IN=$(echo "$SUMS" | jq -r '.in'); T_IN=${T_IN:-0}
    T_OUT=$(echo "$SUMS" | jq -r '.out'); T_OUT=${T_OUT:-0}
    T_CW=$(echo "$SUMS" | jq -r '.cw'); T_CW=${T_CW:-0}
    T_CR=$(echo "$SUMS" | jq -r '.cr'); T_CR=${T_CR:-0}
  fi
  MODEL=$(jq -s '[ .[] | select(.message.model != null) | .message.model ] | last // "null"' "$TRANSCRIPT" 2>/dev/null)
  [ -n "$MODEL" ] || MODEL="null"
fi

# --- Cost estimate via pricing.json (substring: model id ↔ pricing key) ---
COST="null"
if [ -n "$PRICING_FILE" ] && [ -f "$PRICING_FILE" ] && [ "$MODEL" != "null" ]; then
  KEY=$(jq -r --arg m "$MODEL" '.models | to_entries[] | .key as $k | select($m | test($k)) | $k' "$PRICING_FILE" 2>/dev/null | head -1)
  if [ -n "$KEY" ] && [ "$KEY" != "null" ]; then
    COST=$(jq -n \
      --argjson i "$T_IN" --argjson o "$T_OUT" --argjson cw "$T_CW" --argjson cr "$T_CR" \
      --argjson pin "$(jq -r --arg k "$KEY" '.models[$k].in' "$PRICING_FILE")" \
      --argjson pout "$(jq -r --arg k "$KEY" '.models[$k].out' "$PRICING_FILE")" \
      --argjson wm "$(jq -r '._cache.write_mult // 0' "$PRICING_FILE")" \
      --argjson rm "$(jq -r '._cache.read_mult // 0' "$PRICING_FILE")" \
      '(($i/1e6)*$pin) + (($o/1e6)*$pout) + (($cw/1e6)*$pin*$wm) + (($cr/1e6)*$pin*$rm)' 2>/dev/null) || COST="null"
    [ -n "$COST" ] || COST="null"
  fi
fi

# --- Tool call count from scope-guard state (if present) ---
TOOL_CALLS="null"
SCOPE_FILE="${SCOPE_STATE_DIR:-/tmp}/claude-scope-${SESSION_ID}"
if [ -f "$SCOPE_FILE" ]; then
  TC=$(grep '^count=' "$SCOPE_FILE" 2>/dev/null | cut -d= -f2)
  TC=${TC:-}
  if [ -n "$TC" ]; then TOOL_CALLS="$TC"; fi
fi

# --- Append row ---
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -cn \
  --arg ts "$TS" --arg sid "$SESSION_ID" --arg proj "$PROJECT" --argjson model "$MODEL" \
  --argjson ti "$T_IN" --argjson to "$T_OUT" --argjson tcw "$T_CW" --argjson tcr "$T_CR" \
  --argjson cost "$COST" --argjson tcalls "$TOOL_CALLS" \
  '{ts:$ts, session_id:$sid, project:$proj, model:$model,
    tokens:{in:$ti, out:$to, cache_w:$tcw, cache_r:$tcr},
    cost_usd:$cost, tool_calls:$tcalls, estimated:true}' >> "$OUT_FILE" 2>/dev/null

exit 0
