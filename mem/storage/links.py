"""Memory links — connect related observations with typed relationships.

Hindsight-inspired pattern: observations are linked by shared concepts,
topics, and temporal proximity. Enables graph traversal via related() tool.
"""

import sqlite3
import json
import time
from collections import defaultdict


def create_link(
    conn: sqlite3.Connection,
    source_id: int,
    target_id: int,
    link_type: str,
    strength: float = 1.0,
    valid_from: int | None = None,
) -> bool:
    """Create a link between two observations. Returns True if created.

    valid_from: epoch in ms when this relationship becomes valid (defaults to now).
    valid_to defaults to max int (forever).
    """
    if source_id == target_id:
        return False
    # Ensure source < target for consistency
    a, b = min(source_id, target_id), max(source_id, target_id)
    now_epoch = int(time.time())
    vf = valid_from or now_epoch
    try:
        conn.execute(
            """INSERT OR IGNORE INTO memory_links
               (source_id, target_id, link_type, strength, created_epoch, valid_from, valid_to)
               VALUES (?, ?, ?, ?, ?, ?, 9223372036854775807)""",
            (a, b, link_type, strength, now_epoch, vf),
        )
        conn.commit()
        return True
    except sqlite3.IntegrityError:
        return False


def get_links(
    conn: sqlite3.Connection,
    observation_id: int,
    link_type: str | None = None,
    as_of: int | None = None,
) -> list[dict]:
    """Get all links for an observation.

    as_of: epoch in ms. If provided, only return links valid at that time
    (valid_from <= as_of < valid_to).
    """
    if as_of is not None:
        time_cond = "AND ml.valid_from <= ? AND ml.valid_to > ?"
        time_params = [as_of, as_of]
    else:
        time_cond = ""
        time_params = []

    if link_type:
        rows = conn.execute(
            f"""SELECT ml.*, o.title, o.type, o.project
               FROM memory_links ml
               JOIN observations o ON o.id = CASE
                   WHEN ml.source_id = ? THEN ml.target_id
                   ELSE ml.source_id END
               WHERE (ml.source_id = ? OR ml.target_id = ?) AND ml.link_type = ?
               {time_cond}""",
            [observation_id, observation_id, observation_id, link_type] + time_params,
        ).fetchall()
    else:
        rows = conn.execute(
            f"""SELECT ml.*, o.title, o.type, o.project
               FROM memory_links ml
               JOIN observations o ON o.id = CASE
                   WHEN ml.source_id = ? THEN ml.target_id
                   ELSE ml.source_id END
               WHERE ml.source_id = ? OR ml.target_id = ?
               {time_cond}""",
            [observation_id, observation_id, observation_id] + time_params,
        ).fetchall()
    return [dict(r) for r in rows]


def get_related(
    conn: sqlite3.Connection,
    observation_id: int,
    depth: int = 2,
    max_results: int = 20,
    as_of: int | None = None,
) -> list[dict]:
    """Traverse links graph from an observation, returning related observations.

    BFS traversal up to `depth` hops. Returns observations with their
    link type and distance from origin.

    as_of: epoch in ms. If provided, only traverse links valid at that time.
    """
    visited = {observation_id}
    results = []
    current_level = [observation_id]

    for d in range(1, depth + 1):
        next_level = []
        for oid in current_level:
            links = get_links(conn, oid, as_of=as_of)
            for link in links:
                linked_id = (
                    link["source_id"] if link["target_id"] == oid else link["target_id"]
                )
                if linked_id in visited:
                    continue
                visited.add(linked_id)
                next_level.append(linked_id)
                results.append(
                    {
                        "id": linked_id,
                        "title": link["title"],
                        "type": link["type"],
                        "project": link["project"],
                        "link_type": link["link_type"],
                        "strength": link["strength"],
                        "distance": d,
                    }
                )
                if len(results) >= max_results:
                    return results
        current_level = next_level
        if not next_level:
            break

    return results


def invalidate_link(
    conn: sqlite3.Connection,
    source_id: int,
    target_id: int,
    link_type: str,
    invalidated_at: int | None = None,
) -> bool:
    """Mark a link as no longer valid by setting valid_to.

    MemPalace temporal pattern: relationships can expire or be invalidated.
    """
    now = invalidated_at or int(time.time())
    a, b = min(source_id, target_id), max(source_id, target_id)
    cursor = conn.execute(
        "UPDATE memory_links SET valid_to = ? "
        "WHERE source_id = ? AND target_id = ? AND link_type = ? "
        "AND valid_to > ?",
        (now, a, b, link_type, now),
    )
    conn.commit()
    return cursor.rowcount > 0


def auto_link_observations(conn: sqlite3.Connection, batch_size: int = 500) -> dict:
    """Auto-link observations based on shared concepts, topics, and session proximity.

    Processes observations in batches to avoid memory issues.
    Returns stats: {"same_concept": N, "chronological": N, "total": N}.
    """
    stats = defaultdict(int)

    # 1. Link observations sharing >1 concept tags
    rows = conn.execute(
        "SELECT id, concepts, session_id, project FROM observations ORDER BY id DESC LIMIT ?",
        (batch_size,),
    ).fetchall()

    concept_map = defaultdict(list)  # concept -> [obs_ids]
    session_map = defaultdict(list)  # session_id -> [obs_ids]

    for r in rows:
        try:
            concepts = json.loads(r["concepts"]) if r["concepts"] else []
        except (json.JSONDecodeError, TypeError):
            concepts = []
        for c in concepts:
            if c:
                concept_map[c].append(r["id"])
        if r["session_id"]:
            session_map[r["session_id"]].append(r["id"])

    # Create links for shared concepts
    for concept, ids in concept_map.items():
        if len(ids) < 2:
            continue
        for i in range(len(ids)):
            for j in range(i + 1, min(len(ids), i + 5)):  # Limit pairs
                if create_link(conn, ids[i], ids[j], "same_concept", 0.7):
                    stats["same_concept"] += 1

    # 2. Link consecutive observations in same session (chronological)
    for session_id, ids in session_map.items():
        ids.sort()
        for i in range(len(ids) - 1):
            if create_link(conn, ids[i], ids[i + 1], "chronological", 0.5):
                stats["chronological"] += 1

    stats["total"] = sum(stats.values())
    return dict(stats)


def auto_episode_links(conn: sqlite3.Connection, batch_size: int = 500) -> int:
    """Create episode links: group same-session observations sharing concepts.

    Chunking (Miller 7±2): when ≥3 observations in the same session share
    ≥2 concepts, they form an "episode". The earliest observation is the
    anchor; others link to it with type='episode'.
    Returns number of episode links created.
    """
    rows = conn.execute(
        "SELECT id, session_id, concepts FROM observations "
        "WHERE session_id IS NOT NULL "
        "ORDER BY session_id, created_epoch LIMIT ?",
        (batch_size,),
    ).fetchall()

    # Group by session
    session_obs: dict[str, list[tuple[int, set[str]]]] = defaultdict(list)
    for r in rows:
        try:
            concepts = set(json.loads(r["concepts"] or "[]"))
        except (json.JSONDecodeError, TypeError):
            concepts = set()
        if r["session_id"]:
            session_obs[r["session_id"]].append((r["id"], concepts))

    count = 0
    for session_id, obs_list in session_obs.items():
        if len(obs_list) < 3:
            continue

        # Find observations sharing ≥2 concepts with the anchor (earliest)
        anchor_id, anchor_concepts = obs_list[0]
        if not anchor_concepts:
            continue

        episode_members = [(anchor_id, anchor_concepts)]
        for obs_id, concepts in obs_list[1:]:
            shared = anchor_concepts & concepts
            if len(shared) >= 2:
                episode_members.append((obs_id, concepts))

        # Create episode links if enough members
        if len(episode_members) >= 3:
            for i in range(1, len(episode_members)):
                obs_id, concepts = episode_members[i]
                shared_count = len(anchor_concepts & concepts)
                union_count = len(anchor_concepts | concepts)
                strength = min(1.0, shared_count / max(union_count, 1))
                if create_link(conn, anchor_id, obs_id, "episode", strength):
                    count += 1

    return count
