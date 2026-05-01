#!/usr/bin/env bash
# mem-precompact.sh — PreCompact hook: emergency save before context compression
# MemPalace pattern: prevent memory loss during context window compression
# Triggered by Claude Code's PreCompact event

MEM_DIR="$HOME/.mind"

if [ ! -d "$MEM_DIR" ]; then
  exit 0
fi

DB="$MEM_DIR/memory.db"
if [ ! -f "$DB" ]; then
  exit 0
fi

# Save a compact snapshot of recent observations to survive context compression
# Uses direct SQLite — no MCP dependency
EPOCH=$(date +%s000)
ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Count recent observations (last 10 minutes)
RECENT=$(sqlite3 "$DB" "
  SELECT COUNT(*) FROM observations
  WHERE created_epoch > ($EPOCH - 600000);
" 2>/dev/null || echo "0")

# Log the precompact event
sqlite3 "$DB" "
  INSERT INTO dream_log (operation, details, ran_at, ran_epoch)
  VALUES ('precompact', '{\"recent_obs\": $RECENT, \"trigger\": \"context-compress\"}', '$ISO', $EPOCH);
" 2>/dev/null

# Ensure recent observations have links (fast, limited batch)
python3 -c "
import sys; sys.path.insert(0, '$HOME/.mind')
from mem.storage.database import get_db
from mem.storage.links import auto_link_observations
db = get_db()
stats = auto_link_observations(db, batch_size=100)
if stats.get('total', 0) > 0:
    print(f'PreCompact linked: {stats}')
" 2>/dev/null || true

exit 0
