"""Working Memory — session-level hot cache for zero-latency recall.

Implements the working memory concept from cognitive science:
- Limited capacity (7±2 items, Miller's Law)
- Fast access (no DB query, /tmp file)
- Decays quickly (1 hour staleness)
- Consolidation: frequently accessed items get permanent boost on session end
"""

import json
import os
import time
from pathlib import Path

WM_PATH = Path(f"/tmp/claude-wm-{os.environ.get('CLAUDE_SESSION_ID', 'default')}.jsonl")
WM_MAX = 10  # Miller's 7±2
WM_STALE_S = 3600  # 1 hour


def wm_push(obs_id: int, title: str, summary: str, salience: float = 0.5):
    """Push an observation into working memory."""
    _ensure_dir()
    entry = {
        "id": obs_id,
        "title": title,
        "summary": summary,
        "salience": salience,
        "epoch": int(time.time()),
    }
    with open(WM_PATH, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    _trim()


def wm_recall(query: str = "", limit: int = 5) -> list[dict]:
    """Recall from working memory. Zero-latency (no DB query)."""
    if not WM_PATH.exists():
        return []
    entries = []
    for line in WM_PATH.read_text().strip().split("\n"):
        if not line:
            continue
        try:
            e = json.loads(line)
            # Filter stale entries
            if int(time.time()) - e.get("epoch", 0) > WM_STALE_S:
                continue
            if (
                query
                and query.lower()
                not in (e.get("title", "") + e.get("summary", "")).lower()
            ):
                continue
            entries.append(e)
        except (json.JSONDecodeError, KeyError):
            continue

    # Sort by salience desc, then recency
    entries.sort(key=lambda x: (-x.get("salience", 0.5), -x.get("epoch", 0)))
    return entries[:limit]


def wm_boost_permanent(conn, threshold: int = 2) -> int:
    """On session end: boost observations accessed >= threshold times.

    Simulates memory consolidation: frequently accessed working memory
    items get a permanent ease_factor boost in long-term memory.
    Returns number of observations boosted.
    """
    if not WM_PATH.exists():
        return 0
    counts: dict[int, int] = {}
    for line in WM_PATH.read_text().strip().split("\n"):
        try:
            e = json.loads(line)
            oid = e.get("id")
            if oid and oid > 0:
                counts[oid] = counts.get(oid, 0) + 1
        except (json.JSONDecodeError, KeyError):
            continue

    boosted = 0
    for oid, count in counts.items():
        if count >= threshold:
            conn.execute(
                "UPDATE observations SET ease_factor = MIN(3.0, ease_factor + 0.1) WHERE id = ?",
                (oid,),
            )
            boosted += 1
    if boosted:
        conn.commit()
    return boosted


def wm_clear():
    """Clear working memory (e.g. on session end)."""
    if WM_PATH.exists():
        WM_PATH.unlink(missing_ok=True)


def _trim():
    """Keep only WM_MAX most recent entries."""
    if not WM_PATH.exists():
        return
    lines = WM_PATH.read_text().strip().split("\n")
    if len(lines) > WM_MAX:
        WM_PATH.write_text("\n".join(lines[-WM_MAX:]) + "\n")


def _ensure_dir():
    WM_PATH.parent.mkdir(parents=True, exist_ok=True)
