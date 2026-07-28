#!/usr/bin/env bash
# sprint-classify.sh — UserPromptSubmit hook
# Classifies user prompt as Complex / Not-Complex / Ambiguous.
# Complex → writes pending state (downstream sprint-gate will block Edit/Write).
# Not-Complex / Ambiguous → no-op.
#
# Conservative bias: only set pending on unambiguous Complex signals.
# Override (only at prompt start): `--no-sprint`, `trivial:`, `standard:`.
# Negation keywords use word-boundary matching with "not X" / "non-X" context
# filtering to avoid false negatives (e.g. "this is not trivial" → still Complex).

set -uo pipefail

# Escape hatch for CI / scripted runs
[ "${SPRINT_ENFORCE:-1}" = "0" ] && exit 0

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

# Strip leading whitespace (defeats prefix override if user pastes with indent)
PROMPT_LSTRIPPED="${PROMPT#"${PROMPT%%[![:space:]]*}"}"

LOWER="$(printf '%s' "$PROMPT_LSTRIPPED" | tr '[:upper:]' '[:lower:]')"

NEGATION=0
VERB=0
SCOPE=0
OVERRIDE=0  # explicit prefix override — also clears existing pending

# --- Negation signal 1: prefix override (after whitespace strip) ---
# OVERRIDE=1 means user explicitly said "skip sprint" — clear any existing
# pending too, so the override takes effect immediately (not just on next write).
case "$PROMPT_LSTRIPPED" in
  trivial:*|standard:*) NEGATION=1; OVERRIDE=1 ;;
esac
# --no-sprint as first token, with space OR tab OR end-of-string boundary
if [ "$NEGATION" -eq 0 ]; then
  case "$PROMPT_LSTRIPPED" in
    --no-sprint|--no-sprint[[:space:]]*) NEGATION=1; OVERRIDE=1 ;;
  esac
fi

# If user explicitly overrode, clear any existing pending for this session.
# (Keyword-based negation below does NOT clear — too easy to false-positive.)
if [ "$OVERRIDE" -eq 1 ]; then
  sprint_state_clear "$SESSION_ID" 2>/dev/null || true
fi

# --- Negation signal 2: keyword list (word-boundary, context-filtered) ---
if [ "$NEGATION" -eq 0 ]; then
  # Strip "not X" / "non-X" / "isn't X" / "is not X" contexts — user is
  # EMPHASIZING complexity, not signalling simplicity.
  # NOTE: bash `${var//pat/}` with an apostrophe in `pat` triggers a parser
  # error ("unexpected EOF while looking for matching '"), so we normalize
  # apostrophes via `tr` first and match apostrophe-free patterns.
  LOWER_FILT="$(printf '%s' "$LOWER" | tr -d "'")"
  for ctx in "not trivial" "non-trivial" "isnt trivial" "is not trivial" \
             "not simple" "non-simple" "not quick" "non-quick"; do
    LOWER_FILT="${LOWER_FILT//"$ctx"/}"
  done
  # Word-boundary match. Single-word + hyphenated compound keywords only;
  # phrase keywords ("single file", "small fix") dropped — too many false
  # positives when user is describing scope, not signalling simplicity.
  if printf '%s' "$LOWER_FILT" | grep -qwE 'trivial|simple|quick|one-liner|one-line'; then
    NEGATION=1
  fi
fi

# --- Affirmative signal 1: verb keyword (word-boundary) ---
# Single-word verbs matched via grep -wE; "add feature" as phrase substring.
if [ "$NEGATION" -eq 0 ]; then
  if printf '%s' "$LOWER" | grep -qwE 'build|implement|refactor|ship|rewrite|migrate'; then
    VERB=1
  fi
  if [ "$VERB" -eq 0 ] && [[ "$LOWER" == *"add feature"* ]]; then
    VERB=1
  fi
fi

# --- Affirmative signal 2: scope hint ---
# Either ≥3 distinct file paths OR explicit quantifier.
# Path regex requires a slash to avoid matching URLs/hostnames (review CONCERN #4).
if [ "$NEGATION" -eq 0 ] && [ "$VERB" -eq 1 ]; then
  FILE_COUNT="$(printf '%s' "$PROMPT_LSTRIPPED" | grep -oE '[A-Za-z][A-Za-z0-9_/.-]*/[A-Za-z0-9_/.-]+\.[a-z]{1,5}' 2>/dev/null | sort -u | wc -l | tr -d ' ')"
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
