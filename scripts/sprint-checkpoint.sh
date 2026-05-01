#!/usr/bin/env bash
# sprint-checkpoint.sh — Sprint state persistence with resume capability.
# Manages .sprint/CHECKPOINT.yaml for checkpoint-restart.
#
# Usage:
#   sprint-checkpoint save [phase] [step]  — Save checkpoint
#   sprint-checkpoint resume               — Print resume info (or "none")
#   sprint-checkpoint status               — Show checkpoint status
#   sprint-checkpoint clear                — Delete checkpoint

set -euo pipefail

SPRINT_DIR=".sprint"
CHECKPOINT="$SPRINT_DIR/CHECKPOINT.yaml"

cmd="${1:-}"
shift || true

case "$cmd" in
  save)
    phase="${1:-unknown}"
    step="${2:-}"
    files_modified="${3:-}"
    mkdir -p "$SPRINT_DIR"
    cat > "$CHECKPOINT" << EOF
phase: $phase
step: "$step"
files_modified: "$(git diff --name-only 2>/dev/null | tr '\n' ',' || echo '')"
timestamp: "$(date -Iseconds)"
remaining: []
pending_decisions: []
EOF
    echo "Checkpoint saved: phase=$phase step=$step"
    ;;

  resume)
    if [ -f "$CHECKPOINT" ]; then
      cat "$CHECKPOINT"
    else
      echo "none"
    fi
    ;;

  status)
    if [ -f "$CHECKPOINT" ]; then
      echo "Checkpoint exists:"
      cat "$CHECKPOINT"
    else
      echo "No checkpoint found"
    fi
    ;;

  clear)
    rm -f "$CHECKPOINT"
    echo "Checkpoint cleared"
    ;;

  *)
    echo "Usage: sprint-checkpoint.sh {save|resume|status|clear}" >&2
    echo "  save [phase] [step]  Save checkpoint at current state" >&2
    echo "  resume               Print checkpoint (or 'none')" >&2
    echo "  status               Show detailed checkpoint" >&2
    echo "  clear                Delete checkpoint" >&2
    exit 1
    ;;
esac
