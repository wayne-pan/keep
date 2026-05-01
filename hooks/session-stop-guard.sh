#!/usr/bin/env bash
# session-stop-guard.sh — Capture session summary as observation on session end.
# Borrowed from oh-my-codex lifecycle: auto-capture session-log on stop.
# Note: mem-session.sh handles dream cycle; this hook only creates the log entry.

MEM_DIR="$HOME/.mind"
DB="$MEM_DIR/memory.db"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")

[ ! -f "$DB" ] && exit 0

# Collect session stats from DB
STATS=$(sqlite3 "$DB" "
  SELECT COUNT(*), GROUP_CONCAT(DISTINCT type), GROUP_CONCAT(DISTINCT project)
  FROM observations WHERE session_id = '$SESSION_ID';
" 2>/dev/null)

# Extract count (first field)
OBS_COUNT=$(echo "$STATS" | cut -d'|' -f1 2>/dev/null || echo "0")
[ "$OBS_COUNT" = "0" ] && exit 0

# Get git changes summary
GIT_DIFF=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | head -c 200 || echo "no changes")

# Create session-log observation
python3 -c "
import sys
sys.path.insert(0, '$HOME/.mind')
from mem.storage.database import get_db
from mem.storage.observations import add_observation

db = get_db()
add_observation(
    db,
    session_id='$SESSION_ID',
    project='$PROJECT',
    obs_type='session-log',
    title='Session completed: $OBS_COUNT observations',
    narrative='Session $SESSION_ID ended with $OBS_COUNT observations. Git: $GIT_DIFF',
    facts=[],
    concepts=['session-log'],
)
" 2>/dev/null

exit 0
