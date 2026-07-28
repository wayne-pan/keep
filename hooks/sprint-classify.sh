#!/usr/bin/env bash
# sprint-classify.sh — UserPromptSubmit hook
# Classifies user prompt as Complex / Not-Complex / Ambiguous.
# Complex → writes pending state (downstream sprint-gate will block Edit/Write).
# Not-Complex / Ambiguous → no-op.
#
# Conservative bias: only set pending on unambiguous Complex signals.
# Override (only at prompt start): `--no-sprint`, `trivial:`, `standard:`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="$SCRIPT_DIR/lib/sprint-state.sh"
# shellcheck disable=SC1090
[ -r "$LIB_PATH" ] && source "$LIB_PATH"

INPUT="$(cat)"
PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // empty')"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"

# Bail on missing session_id (degraded mode — cannot attribute state)
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Cap prompt size (60s hook timeout safety)
PROMPT="${PROMPT:0:2000}"

LOWER="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')"

NEGATION=0
VERB=0
SCOPE=0

# --- Negation signal 1: prefix override ---
case "$PROMPT" in
  trivial:*|standard:*|"--no-sprint "*|"--no-sprint") NEGATION=1 ;;
esac

# --- Negation signal 2: keyword substring list ---
if [ "$NEGATION" -eq 0 ]; then
  for kw in trivial simple quick "one-line" "single file" "small fix"; do
    if [[ "$LOWER" == *"$kw"* ]]; then
      NEGATION=1
      break
    fi
  done
fi

# --- Affirmative signal 1: verb keyword ---
if [ "$NEGATION" -eq 0 ]; then
  for kw in build implement refactor "add feature" ship rewrite migrate; do
    if [[ "$LOWER" == *"$kw"* ]]; then
      VERB=1
      break
    fi
  done
fi

# --- Affirmative signal 2: scope hint ---
# Either ≥3 distinct file paths OR explicit quantifier
if [ "$NEGATION" -eq 0 ] && [ "$VERB" -eq 1 ]; then
  FILE_COUNT="$(printf '%s' "$PROMPT" | grep -oE '[A-Za-z][A-Za-z0-9_/.-]*\.[a-z]{1,5}' 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  [ -n "$FILE_COUNT" ] || FILE_COUNT=0
  if [ "$FILE_COUNT" -ge 3 ]; then
    SCOPE=1
  fi
  if [ "$SCOPE" -eq 0 ]; then
    for q in "several" "multiple" "all the" "3+" "three or more"; do
      if [[ "$LOWER" == *"$q"* ]]; then
        SCOPE=1
        break
      fi
    done
  fi
fi

# --- Decision ---
ADVISORY=""
if [ "$NEGATION" -eq 1 ]; then
  ADVISORY="[sprint-classify] Not-Complex (override or negation). No sprint required."
elif [ "$VERB" -eq 1 ] && [ "$SCOPE" -eq 1 ]; then
  if sprint_state_set "$SESSION_ID" "complex-match"; then
    ADVISORY="[sprint-classify] Pending SET (Complex). Call /keep:sprint before Edit/Write."
  else
    ADVISORY="[sprint-classify] Complex detected but state write failed."
  fi
else
  ADVISORY="[sprint-classify] Ambiguous. If Complex, call /keep:sprint; otherwise proceed."
fi

jq -n --arg ctx "$ADVISORY" '{additionalContext: $ctx}'
exit 0
