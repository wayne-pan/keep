"""Auto-routing recall — unified search entry point (Cognee pattern).

Tries multiple search strategies in parallel, merges and ranks results.
Users call a single `recall(query)` instead of choosing between search,
search_entities, search_synthesis, and timeline.
"""

from __future__ import annotations

from mem.search.fts import fts_search
from mem.search.dedup import _rrf_fuse, dedup_results
from mem.search.expansion import expand_query
from mem.storage.database import get_db


def recall(
    query: str,
    limit: int = 15,
    project: str | None = None,
    obs_type: str | None = None,
) -> list[dict]:
    """Auto-routing recall: tries FTS, entity, synthesis strategies.

    Returns deduplicated, ranked list of result dicts with a `source` field
    indicating which strategy found each result.
    """
    db = get_db()
    result_sets: list[list[dict]] = []

    # Strategy 1: FTS5 BM25 search (with query expansion)
    variants = expand_query(query)
    fts_results: list[dict] = []
    for v in variants:
        try:
            rs = fts_search(db, v, limit=limit, project=project, obs_type=obs_type)
            fts_results.extend(rs)
        except Exception:
            continue
    if fts_results:
        fused_fts = _rrf_fuse([fts_results])
        for r in fused_fts:
            r["source"] = "fts"
        result_sets.append(fused_fts)

    # Strategy 2: Entity-based search
    try:
        from mem.storage.entities import search_entities as _search_ent

        entity_results = _search_ent(db, query, limit=limit)
        if entity_results:
            # Resolve entity matches to observations
            obs_ids = _resolve_entities_to_obs(db, entity_results)
            if obs_ids:
                from mem.storage.observations import get_observations

                obs = get_observations(db, obs_ids[:limit])
                for o in obs:
                    o["source"] = "entity"
                result_sets.append(obs)
    except Exception:
        pass

    # Strategy 3: Synthesis search (compiled truths)
    try:
        from mem.storage.synthesis import search_synthesis as _search_syn

        syn_results = _search_syn(db, query, limit=5)
        if syn_results:
            # Resolve synthesis to evidence observations
            import json

            for s in syn_results:
                s["source"] = "synthesis"
                s["id"] = -s["id"]  # Negative IDs to distinguish from observations
                s["type"] = "synthesis"
                s["title"] = s.get("topic", "")
                s["narrative"] = s.get("truth", "")[:200]
            result_sets.append(syn_results)
    except Exception:
        pass

    # Strategy 4: Recent observations fallback (if few results)
    total_results = sum(len(rs) for rs in result_sets)
    if total_results < 3:
        try:
            recent = _recent_observations(db, query, limit=5, project=project)
            if recent:
                for r in recent:
                    r["source"] = "recent"
                result_sets.append(recent)
        except Exception:
            pass

    if not result_sets:
        return []

    # RRF fusion across all strategies
    fused = _rrf_fuse(result_sets)
    final = dedup_results(fused[: limit * 2])[:limit]

    # Hierarchical drill-down: expand top anchors via 1-hop graph traversal
    # Inspired by HyperMem's coarse-to-fine retrieval pattern
    if final:
        final = _expand_anchors(db, final, limit)

    return final


def _resolve_entities_to_obs(
    db, entity_results: list[dict], limit: int = 20
) -> list[int]:
    """Resolve entity search results to observation IDs."""
    obs_ids: list[int] = []
    for ent in entity_results[:5]:
        rows = db.execute(
            "SELECT observation_id FROM entity_mentions WHERE entity_id = ? "
            "ORDER BY observation_id DESC LIMIT ?",
            (ent["id"], limit),
        ).fetchall()
        for r in rows:
            oid = r["observation_id"]
            if oid not in obs_ids:
                obs_ids.append(oid)
    return obs_ids


def _expand_anchors(db, results: list[dict], limit: int) -> list[dict]:
    """Expand top anchors via 1-hop graph traversal (HyperMem coarse-to-fine).

    For each of the top-3 results, find linked observations via
    memory_links and merge into results.
    """
    existing_ids = {abs(r.get("id", 0)) for r in results}
    expanded = []

    for r in results[:3]:
        obs_id = abs(r.get("id", 0))
        if obs_id <= 0:
            continue

        # 1-hop via memory_links (bidirectional)
        try:
            linked = db.execute(
                "SELECT target_id FROM memory_links WHERE source_id = ? "
                "UNION "
                "SELECT source_id FROM memory_links WHERE target_id = ? "
                "LIMIT 5",
                (obs_id, obs_id),
            ).fetchall()
            link_ids = [row[0] for row in linked if row[0] not in existing_ids]
        except Exception:
            link_ids = []

        if not link_ids:
            continue

        # Fetch linked observations
        try:
            from mem.storage.observations import get_observations

            linked_obs = get_observations(db, link_ids[:3])
            for lo in linked_obs:
                if lo.get("id") not in existing_ids:
                    lo["source"] = "graph"
                    expanded.append(lo)
                    existing_ids.add(lo["id"])
        except Exception:
            pass

    if not expanded:
        return results

    # Merge expanded into results, cap at limit
    merged = results + expanded
    return dedup_results(merged)[:limit]


def _recent_observations(
    db, query: str, limit: int = 5, project: str | None = None
) -> list[dict]:
    """Fallback: recent observations matching query terms via LIKE."""
    terms = query.split()
    if not terms:
        return []

    conditions = []
    params: list = []
    for t in terms[:3]:
        conditions.append("(title LIKE ? OR narrative LIKE ?)")
        params.extend([f"%{t}%", f"%{t}%"])

    where = " AND ".join(conditions)
    if project:
        where += " AND project = ?"
        params.append(project)

    params.append(limit)
    rows = db.execute(
        f"SELECT id, type, title, narrative, project, created_at, created_epoch "
        f"FROM observations WHERE {where} "
        f"ORDER BY created_epoch DESC LIMIT ?",
        params,
    ).fetchall()
    return [dict(r) for r in rows]
