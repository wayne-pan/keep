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

# Escape hatch for CI / scripted runs — accepts common falsy values.
case "${SPRINT_ENFORCE:-1}" in
  0|false|FALSE|no|NO|off|OFF) exit 0 ;;
esac

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

# Cap prompt size (60s hook timeout safety; 2000 chars is well under the
# limit and longer prompts rarely change classification outcome).
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
  sprint_state_clear "$SESSION_ID"
fi

# --- Negation signal 2: keyword list (word-boundary, context-filtered) ---
if [ "$NEGATION" -eq 0 ]; then
  # Strip "not X" / "non-X" / "isn't X" / "is not X" contexts — user is
  # EMPHASIZING complexity, not signalling simplicity.
  # Normalize apostrophles (ASCII ' and Unicode U+2018/2019) via sed so the
  # substring patterns below can match apostrophe-free forms.
  # (bash `${var//pat/}` with apostrophe in `pat` triggers parser error.)
  LOWER_FILT="$(printf '%s' "$LOWER" | sed "s/'/ /g; s/$(printf '\xe2\x80\x98')/ /g; s/$(printf '\xe2\x80\x99')/ /g")"
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
# 3 paths = heuristic threshold above which work is clearly multi-file.
# Pre-filter URLs (http(s)://) so they don't inflate file count via the
# path regex (which requires a slash — URLs contain slashes too).
if [ "$NEGATION" -eq 0 ] && [ "$VERB" -eq 1 ]; then
  PROMPT_NO_URL="$(printf '%s' "$PROMPT_LSTRIPPED" | sed -E 's|https?://[^ )]+||g')"
  FILE_COUNT="$(printf '%s' "$PROMPT_NO_URL" | grep -oE '[A-Za-z][A-Za-z0-9_/.-]*/[A-Za-z0-9_/.-]+\.[a-z]{1,5}' 2>/dev/null | sort -u | wc -l | tr -d ' ')"
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
