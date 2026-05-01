"""Entity extraction and resolution.

Regex-based extraction of named entities from observation text.
No LLM needed — patterns cover file paths, functions, tools, errors, projects.
"""

import json
import re
import sqlite3
from datetime import datetime, timezone

# Entity extraction patterns (ordered by specificity)
ENTITY_PATTERNS = [
    # File paths: src/module/file.py, hooks/safety-guard.sh
    (r'(?:^|[\s(])([a-zA-Z0-9_./-]+\.[a-zA-Z]{1,6}(?::\d+)?)', "file"),
    # Function/method calls: function_name(), ClassName.method()
    (r'\b([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)?\(\))', "function"),
    # Error patterns: Error:, Exception:, FAILED, segfault
    (r'\b((?:Error|Exception|FAILED|SEGFAULT|Timeout|Refused|denied|not found)[^\n]*)', "error"),
    # Tool names: mcp__xxx, smart_search, add_observation
    (r'\b(mcp__[a-zA-Z_]+|smart_[a-zA-Z_]+|[a-z]+_[a-zA-Z_]+)\b', "tool"),
    # MCP tool pattern
    (r'(mcp__[a-zA-Z_-]+)', "mcp_tool"),
    # Shell commands: git commit, npm install, pip install
    (r'\b(git\s+\w+|npm\s+\w+|pip\s+\w+|bun\s+\w+|make\s+\w+)', "command"),
    # Version strings: v1.2.3, 2.0.0
    (r'\b(v?\d+\.\d+(?:\.\d+)?)\b', "version"),
    # Project names: usually lowercase single words after "project" or "in"
    (r'(?:project|in)\s+([a-zA-Z][a-zA-Z0-9_-]{2,20})', "project"),
]

# Dedup: longer matches win, filter trivial matches
MIN_ENTITY_LEN = 3
IGNORE_WORDS = frozenset({
    "the", "and", "for", "not", "but", "are", "was", "has", "its", "can",
    "all", "use", "get", "set", "put", "add", "run", "new", "old", "out",
    "see", "say", "she", "how", "too", "any", "her", "him", "let", "may",
    "did", "got", "had", "has", "our", "way", "who", "did", "but", "and",
})


def extract_entities(text: str) -> list[dict]:
    """Extract named entities from text using regex patterns.

    Returns list of {"name": str, "entity_type": str} dicts, deduplicated.
    """
    if not text:
        return []

    seen = set()
    entities = []

    for pattern, etype in ENTITY_PATTERNS:
        for match in re.finditer(pattern, text, re.MULTILINE):
            name = match.group(1).strip()
            # Filter trivial matches
            if len(name) < MIN_ENTITY_LEN or name.lower() in IGNORE_WORDS:
                continue
            # Normalize
            name = name.rstrip(".,;:!?)")
            if not name or name.lower() in IGNORE_WORDS:
                continue
            key = (name.lower(), etype)
            if key not in seen:
                seen.add(key)
                entities.append({"name": name, "entity_type": etype})

    return entities


def store_entities(conn: sqlite3.Connection, observation_id: int, text: str) -> int:
    """Extract entities from text and store them, linking to the observation.

    Returns count of new entity mentions created.
    """
    entities = extract_entities(text)
    if not entities:
        return 0

    now = datetime.now(timezone.utc).isoformat()
    now_epoch = int(datetime.now(timezone.utc).timestamp() * 1000)
    count = 0

    for ent in entities:
        name = ent["name"]
        etype = ent["entity_type"]

        # Upsert entity
        existing = conn.execute(
            "SELECT id, mention_count FROM entities WHERE name = ?", (name,)
        ).fetchone()

        if existing:
            eid = existing["id"]
            conn.execute(
                "UPDATE entities SET mention_count = mention_count + 1, last_seen = ? WHERE id = ?",
                (now, eid),
            )
        else:
            cursor = conn.execute(
                "INSERT OR IGNORE INTO entities (name, entity_type, first_seen, last_seen) VALUES (?, ?, ?, ?)",
                (name, etype, now, now),
            )
            eid = cursor.lastrowid

        # Link to observation (skip if already linked)
        if eid:
            try:
                conn.execute(
                    "INSERT OR IGNORE INTO entity_mentions (entity_id, observation_id) VALUES (?, ?)",
                    (eid, observation_id),
                )
                count += 1
            except sqlite3.IntegrityError:
                pass

    conn.commit()
    return count


def search_entities(conn: sqlite3.Connection, query: str,
                    entity_type: str | None = None, limit: int = 20) -> list[dict]:
    """Search entities by name, optionally filtered by type."""
    if entity_type:
        rows = conn.execute(
            """SELECT e.id, e.name, e.entity_type, e.mention_count, e.last_seen
               FROM entities e WHERE e.name LIKE ? AND e.entity_type = ?
               ORDER BY e.mention_count DESC LIMIT ?""",
            (f"%{query}%", entity_type, limit),
        ).fetchall()
    else:
        rows = conn.execute(
            """SELECT e.id, e.name, e.entity_type, e.mention_count, e.last_seen
               FROM entities e WHERE e.name LIKE ?
               ORDER BY e.mention_count DESC LIMIT ?""",
            (f"%{query}%", limit),
        ).fetchall()

    return [dict(r) for r in rows]


def get_observation_entities(conn: sqlite3.Connection, observation_id: int) -> list[dict]:
    """Get all entities linked to an observation."""
    rows = conn.execute(
        """SELECT e.id, e.name, e.entity_type, e.mention_count
           FROM entities e
           JOIN entity_mentions em ON e.id = em.entity_id
           WHERE em.observation_id = ?""",
        (observation_id,),
    ).fetchall()
    return [dict(r) for r in rows]


def rebuild_entity_index(conn: sqlite3.Connection) -> int:
    """Rebuild entity index from all observations. Returns entity count."""
    conn.execute("DELETE FROM entity_mentions")
    conn.execute("DELETE FROM entities")

    rows = conn.execute(
        "SELECT id, title, narrative, facts, concepts FROM observations"
    ).fetchall()

    total = 0
    for r in rows:
        text = " ".join(str(r[k] or "") for k in ["title", "narrative", "facts", "concepts"])
        total += store_entities(conn, r["id"], text)

    conn.commit()
    return conn.execute("SELECT COUNT(*) as c FROM entities").fetchone()["c"]
