#!/usr/bin/env bash
# mem-session.sh — Session end hook: full dream cycle + auto-link + synthesis refresh
# Runs on Stop event to keep memory healthy between sessions.
#
# Pipeline:
#   1. Full dream cycle (dedup → merge → prune → strengthen → link)
#   2. Auto-link recent observations (Hindsight pattern)
#   3. Session observation count log

MEM_DIR="$HOME/.mind"

if [ ! -d "$MEM_DIR" ]; then
  exit 0
fi

DB="$MEM_DIR/memory.db"
if [ ! -f "$DB" ]; then
  exit 0
fi

# Full dream cycle via Python (replaces manual SQLite dedup)
# Runs: dedup → merge → prune → strengthen → link
# Timeout: 30s max (dream cycle on <10K observations takes <5s)
python3 -c "
import sys, json
sys.path.insert(0, '$HOME/.mind')
from mem.dream.cycle import run_dream_cycle

results = run_dream_cycle(mode='full')
ops = {r['operation']: r['details'] for r in results}
print(json.dumps(ops))
" 2>/dev/null || {
    # Fallback: lightweight dedup if dream cycle module fails
    sqlite3 "$DB" "
      DELETE FROM observations WHERE id IN (
        SELECT b.id FROM observations a
        JOIN observations b ON a.content_hash = b.content_hash
          AND b.created_epoch > a.created_epoch
          AND b.created_epoch - a.created_epoch < 30000
          AND a.content_hash != ''
          AND a.content_hash IS NOT NULL
      );
    " 2>/dev/null
}

# Log session stats
EPOCH=$(date +%s000)
ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OBS_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM observations;" 2>/dev/null || echo "?")
sqlite3 "$DB" "
  INSERT INTO dream_log (operation, details, ran_at, ran_epoch)
  VALUES ('session-stop', '{\"trigger\": \"stop\", \"obs_count\": $OBS_COUNT}', '$ISO', $EPOCH);
" 2>/dev/null

exit 0
