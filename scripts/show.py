#!/usr/bin/env python3
"""Terminal dashboard for keep brain state visualization.

Usage:
  python3 scripts/show.py             # Full terminal dashboard
  python3 scripts/show.py --json      # JSON output
  python3 scripts/show.py --no-color  # Disable ANSI colors
"""

import json
import os
import sqlite3
import sys
import time
from pathlib import Path

MEM_DIR = Path.home() / ".claude" / "mem"
DB_PATH = MEM_DIR / "memory.db"

# Unicode block characters for sparklines
_BLOCKS = " ▁▂▃▄▅▆▇█"

# ANSI colors
_C = {
    "R": "\033[0;31m",
    "G": "\033[0;32m",
    "Y": "\033[1;33m",
    "C": "\033[0;36m",
    "B": "\033[1m",
    "DIM": "\033[2m",
    "NC": "\033[0m",
}


def _use_color():
    """Check if colors should be used."""
    if "--no-color" in sys.argv:
        return False
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


def _c(name):
    return _C.get(name, "") if _use_color() else ""


def _get_db():
    if not DB_PATH.exists():
        return None
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def _sparkline(values, width=14):
    """Generate Unicode sparkline from values list."""
    if not values:
        return ""
    max_val = max(max(values), 1)
    chars = []
    for v in values:
        idx = min(8, int(v * 8 / max_val))
        chars.append(_BLOCKS[idx])
    return "".join(chars)


def collect_data():
    """Collect all dashboard data from DB."""
    conn = _get_db()
    if not conn:
        return None

    data = {"memory": {}, "dream": {}, "review": {}, "activity": {}}

    # MEMORY
    data["memory"]["obs_count"] = conn.execute(
        "SELECT COUNT(*) as c FROM observations"
    ).fetchone()["c"]
    data["memory"]["syn_count"] = conn.execute(
        "SELECT COUNT(*) as c FROM synthesis"
    ).fetchone()["c"]
    data["memory"]["ent_count"] = conn.execute(
        "SELECT COUNT(*) as c FROM entities"
    ).fetchone()["c"]

    lifecycle = {}
    for row in conn.execute(
        "SELECT lifecycle, COUNT(*) as c FROM observations GROUP BY lifecycle"
    ):
        lifecycle[row["lifecycle"] or "accepted"] = row["c"]
    data["memory"]["lifecycle"] = lifecycle

    # DREAM
    data["dream"]["total"] = conn.execute(
        "SELECT COUNT(*) as c FROM dream_log"
    ).fetchone()["c"]
    last = conn.execute(
        "SELECT ran_at, operation FROM dream_log ORDER BY ran_epoch DESC LIMIT 1"
    ).fetchone()
    data["dream"]["last"] = dict(last) if last else None

    # REVIEW
    data["review"]["staged"] = lifecycle.get("staged", 0)
    data["review"]["rejected"] = lifecycle.get("rejected", 0)

    # ACTIVITY
    now = int(time.time())
    day_counts = []
    for i in range(14):
        day_start = now - (13 - i) * 86400
        day_end = day_start + 86400
        cnt = conn.execute(
            "SELECT COUNT(*) as c FROM observations WHERE created_epoch BETWEEN ? AND ?",
            (day_start, day_end),
        ).fetchone()["c"]
        day_counts.append(cnt)
    data["activity"]["days"] = day_counts

    conn.close()
    return data


def render_json(data):
    """Output as JSON."""
    print(json.dumps(data, indent=2, default=str))


def render_terminal(data):
    """Render colorful terminal dashboard."""
    if not data:
        print(f"{_c('R')}No memory database found at {DB_PATH}{_c('NC')}")
        return

    m = data["memory"]
    d = data["dream"]
    r = data["review"]
    a = data["activity"]

    lc = m["lifecycle"]

    lines = [
        "",
        f"{_c('B')}  ┌─ MEMORY ─────────────────────────────────────┐{_c('NC')}",
        f"{_c('B')}  │{_c('NC')} Observations: {_c('C')}{m['obs_count']:<8}{_c('NC')} "
        f"Synthesis: {_c('C')}{m['syn_count']:<6}{_c('NC')} "
        f"Entities: {_c('C')}{m['ent_count']}{_c('NC')}",
        f"{_c('B')}  │{_c('NC')} Lifecycle:  "
        f"accepted={lc.get('accepted', 0)}  "
        f"staged={_c('Y')}{lc.get('staged', 0)}{_c('NC')}  "
        f"rejected={_c('R')}{lc.get('rejected', 0)}{_c('NC')}  "
        f"archived={lc.get('archived', 0)}",
        f"{_c('B')}  └───────────────────────────────────────────────┘{_c('NC')}",
        "",
        f"{_c('B')}  ┌─ DREAM ───────────────────────────────────────┐{_c('NC')}",
        f"{_c('B')}  │{_c('NC')} Total runs: {_c('C')}{d['total']}{_c('NC')}  "
        + (
            f"Last: {_c('C')}{d['last']['ran_at'][:16]}{_c('NC')} ({d['last']['operation']})"
            if d["last"]
            else "Last: never"
        ),
        f"{_c('B')}  └───────────────────────────────────────────────┘{_c('NC')}",
        "",
        f"{_c('B')}  ┌─ REVIEW ──────────────────────────────────────┐{_c('NC')}",
        f"{_c('B')}  │{_c('NC')} Staged: {_c('Y')}{r['staged']}{_c('NC')}  "
        f"Rejected: {_c('R')}{r['rejected']}{_c('NC')}",
        f"{_c('B')}  └───────────────────────────────────────────────┘{_c('NC')}",
        "",
        f"{_c('B')}  ┌─ ACTIVITY (observations/day, last 14 days) ───┐{_c('NC')}",
        f"{_c('B')}  │{_c('NC')}  {_c('C')}{_sparkline(a['days'])}{_c('NC')}",
        f"{_c('B')}  │{_c('NC')}  {a['days'][0]} ... {a['days'][-1]} (per day)",
        f"{_c('B')}  └───────────────────────────────────────────────┘{_c('NC')}",
        "",
    ]
    print("\n".join(lines))


def main():
    if "--json" in sys.argv:
        data = collect_data()
        if data:
            render_json(data)
        else:
            print(json.dumps({"error": "No database found"}))
    else:
        render_terminal(collect_data())


if __name__ == "__main__":
    main()
