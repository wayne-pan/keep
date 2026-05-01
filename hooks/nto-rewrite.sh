#!/usr/bin/env bash
# nto-rewrite.sh — Native Token Optimizer rewrite hook
# Replaces rtk-rewrite.sh dependency. Pure bash + jq, zero external deps.
#
# Rewrites common CLI commands to token-efficient equivalents.
# Inspired by rtk-ai/rtk, fully self-contained.
#
# Exit codes:
#   0 + stdout  Rewrite found → auto-allow with modified command
#   (no output) No rewrite → pass through unchanged

if ! command -v jq &>/dev/null; then exit 0; fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

REWRITTEN=""

# ── Parse command ──
# Extract first word (command) and rest (args)
FIRST="${CMD%% *}"
REST="${CMD#* }"
[ "$FIRST" = "$REST" ] && REST=""

# ── Git rewrites ──
if [ "$FIRST" = "git" ]; then
  SUBCMD="${REST%% *}"
  SUBARGS="${REST#* }"
  [ "$SUBCMD" = "$SUBARGS" ] && SUBARGS=""

  case "$SUBCMD" in
    status)
      # Compact: short format + branch name only
      REWRITTEN="git status --short --branch"
      ;;
    diff)
      # Show stat summary instead of full diff (unless user explicitly wants detail)
      if [[ "$SUBARGS" != *"--stat"* ]] && [[ "$SUBARGS" != *"--name-only"* ]] && [[ "$SUBARGS" != *"--name-status"* ]] && [[ "$SUBARGS" != *"--word-diff"* ]]; then
        REWRITTEN="git diff --stat $SUBARGS"
      fi
      ;;
    log)
      # Add --oneline if not already present
      if [[ "$SUBARGS" != *"--oneline"* ]]; then
        REWRITTEN="git log --oneline $SUBARGS"
      fi
      ;;
    add|stash|restore|switch)
      # Mute success-only commands
      REWRITTEN="$CMD && echo ok"
      ;;
    branch)
      # Keep delete/create output, mute list
      if [[ "$SUBARGS" == *"-d"* ]] || [[ "$SUBARGS" == *"-D"* ]] || [[ "$SUBARGS" == *"--delete"* ]]; then
        REWRITTEN="$CMD && echo ok"
      fi
      ;;
  esac

# ── ls rewrites ──
elif [ "$FIRST" = "ls" ]; then
  # Compact: one-per-line, show hidden, no size/perm/date details, limit output
  # Strip existing flags (-la, -l, etc.) — replace with -1A
  LS_ARGS=$(echo "$REST" | sed -E 's/^-[^ ]*//; s/ -[^ ]*//g')
  [ -n "$LS_ARGS" ] && REWRITTEN="ls -1A $LS_ARGS 2>/dev/null | head -50" || REWRITTEN="ls -1A 2>/dev/null | head -50"

# ── find rewrites ──
elif [ "$FIRST" = "find" ]; then
  # Add noise dir filtering + head limit (if not already present)
  if [[ "$CMD" != *"head"* ]]; then
    NOISE_FILTER="-not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/__pycache__/*' -not -path '*/target/*' -not -path '*/.next/*' -not -path '*/dist/*'"
    REWRITTEN="$CMD $NOISE_FILTER 2>/dev/null | head -50"
  fi

# ── cat/head rewrites (encourage Read tool usage) ──
elif [ "$FIRST" = "cat" ]; then
  # Limit cat output, add line numbers
  REWRITTEN="$CMD | head -100"
fi

# ── No rewrite found → pass through ──
[ -z "$REWRITTEN" ] && exit 0

# ── Build hook response ──
UPDATED_INPUT=$(echo "$INPUT" | jq -c '.tool_input.command = $cmd' --arg cmd "$REWRITTEN")

jq -n \
  --argjson updated "$UPDATED_INPUT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "permissionDecisionReason": "NTO auto-rewrite",
      "updatedInput": $updated
    }
  }'
