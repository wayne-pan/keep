#!/bin/bash
# review-queue-inject.sh — Surface staged observation count on PreCompact
# Reminds the user to review staged observations before context compaction.

set -euo pipefail

DB="$HOME/.mind/memory.db"
FLAG="$HOME/.mind/onboarded"

# Skip if no DB
[ -f "$DB" ] || exit 0

# Count staged observations
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM observations WHERE lifecycle = 'staged'" 2>/dev/null || echo 0)

if [ "$COUNT" -gt 0 ]; then
    echo ""
    echo "[REVIEW QUEUE] $COUNT staged observation(s) pending review."
    echo "  Run: review_queue(status='staged') to see them."
    echo "  Or: lifecycle_transition(id=N, new_state='accepted') to accept."
    echo ""
fi
