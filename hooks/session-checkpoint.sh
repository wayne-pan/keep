#!/usr/bin/env bash
# session-checkpoint.sh — Capture session state on stop for cross-session resume.
# Runs before session-stop-guard.sh in the Stop hook chain.
# Creates a session-checkpoint observation with git state and modified files.

MEM_DIR="$HOME/.mind"
DB="$MEM_DIR/memory.db"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")

[ ! -f "$DB" ] && exit 0

# Collect git state
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
DIRTY_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
MODIFIED_FILES=$(git diff --name-only HEAD 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')

# Build JSON narrative
NARRATIVE=$(jq -n \
  --arg sid "$SESSION_ID" \
  --arg proj "$PROJECT" \
  --arg branch "$GIT_BRANCH" \
  --argjson dirty "$DIRTY_COUNT" \
  --arg modified "$MODIFIED_FILES" \
  --arg untracked "$UNTRACKED" \
  '{session_id: $sid, project: $proj, git_branch: $branch, dirty_files: $dirty, modified_files: $modified, untracked_files: $untracked}')

# Create session-checkpoint observation via Python
python3 -c "
import sys, json
sys.path.insert(0, '$HOME/.mind')
from mem.storage.database import get_db
from mem.storage.observations import add_observation

db = get_db()
narrative = json.loads('''$NARRATIVE''')
add_observation(
    db,
    session_id='$SESSION_ID',
    project='$PROJECT',
    obs_type='session-checkpoint',
    title='Session checkpoint: $GIT_BRANCH ($DIRTY_COUNT dirty)',
    narrative=json.dumps(narrative),
    facts=[],
    concepts=['session-checkpoint', 'concept:append-only'],
)
" 2>/dev/null

exit 0
