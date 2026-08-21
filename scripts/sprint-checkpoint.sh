#!/usr/bin/env bash
# sprint-checkpoint.sh — Sprint state persistence with resume capability.
# Manages .sprint/<task>/CHECKPOINT.yaml for checkpoint-restart (per-task dir,
# resolved via the sibling sprint-plan.sh anchor — see .sprint/CURRENT).
#
# Usage:
#   sprint-checkpoint save [phase] [step]  — Save checkpoint
#   sprint-checkpoint resume               — Print resume info (or "none")
#   sprint-checkpoint status               — Show checkpoint status
#   sprint-checkpoint clear                — Delete checkpoint

set -euo pipefail

# Active task dir comes from sprint-plan (single source of truth for the anchor).
PLAN_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sprint-plan.sh"
if ! TASK_DIR=$("$PLAN_SCRIPT" path); then
  echo "No active sprint task. Run: sprint-plan init <name>" >&2
  exit 1
fi
CHECKPOINT="$TASK_DIR/CHECKPOINT.yaml"

cmd="${1:-}"
shift || true

case "$cmd" in
  save)
    phase="${1:-unknown}"
    step="${2:-}"
    files_modified="${3:-}"
    mkdir -p "$TASK_DIR"
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
