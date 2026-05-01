#!/usr/bin/env bash
# sync-memory-rules.sh — Extract top synthesis insights to rules file for session-start injection
# Registered as Stop hook: queries mind synthesis table, writes top insights
# to ~/.claude/rules/learnings.md (auto-loaded at every session start).

set -euo pipefail

DB="$HOME/.mind/memory.db"
OUTPUT_FILE="$HOME/.claude/rules/learnings.md"

[ -f "$DB" ] || exit 0

python3 - "$DB" "$OUTPUT_FILE" <<'PYEOF' 2>/dev/null || true
import sqlite3, sys

db_path, output_file = sys.argv[1], sys.argv[2]

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row

# Get top synthesis by confidence, most recently updated
rows = conn.execute("""
    SELECT topic, truth, confidence, updated_count
    FROM synthesis
    WHERE confidence >= 0.7
    ORDER BY confidence DESC, last_epoch DESC
    LIMIT 3
""").fetchall()

if not rows:
    conn.close()
    sys.exit(0)

# Get observation count for context
obs_count = conn.execute("SELECT COUNT(*) as c FROM observations").fetchone()["c"]
conn.close()

# Generate compact markdown
lines = ["## Active Learnings (auto-synced from synthesis)", ""]
for r in rows:
    conf = f"{r['confidence']:.1f}"
    topic = r["topic"][:60]
    truth = r["truth"].split("\n")[0][:120]
    updates = r["updated_count"]
    lines.append(f"- [{conf}] **{topic}** ({updates}x): {truth}")

lines.append("")
lines.append(f"<!-- synced from mind, {len(rows)} synthesis, {obs_count} observations -->")

with open(output_file, "w") as f:
    f.write("\n".join(lines) + "\n")
PYEOF

exit 0
