"""Memory tools: search, timeline, get_observations, add_observation, search_synthesis,
recall, remember, forget, feedback."""

import json
import time
from mem.storage.database import get_db
from mem.tools import _trim
from mem.storage.observations import (
    add_observation as _add_obs,
    get_observations as _get_obs,
    increment_relevance as _inc_rel,
    delete_observation as _delete_obs,
    generate_summary,
)
from mem.storage.synthesis import (
    get_synthesis as _get_syn,
    search_synthesis as _search_syn,
    update_synthesis as _update_syn,
)
from mem.search.fts import fts_search
from mem.search.expansion import expand_query
from mem.search.dedup import dedup_results


def _staleness_tag(created_epoch: int | None) -> str:
    """Return freshness label: [fresh]<7d, [recent]<30d, [stale]<90d."""
    if not created_epoch:
        return "[stale]"
    age_days = (int(time.time()) - created_epoch) / 86400
    if age_days < 7:
        return "[fresh]"
    if age_days < 30:
        return "[recent]"
    return "[stale]"


def _verified_tag(obs: dict) -> str:
    """Return verification badge: [verified] or empty."""
    return "[verified] " if obs.get("verified") else ""


def register_memory_tools(mcp):
    @mcp.tool()
    def search(
        query: str,
        limit: int = 20,
        project: str = None,
        obs_type: str = None,
        dateStart: str = None,
        dateEnd: str = None,
        offset: int = 0,
        orderBy: str = "relevance",
    ) -> str:
        """Step 1: Search memory. Returns index with IDs (~50-100 tokens/result)."""
        db = get_db()
        variants = expand_query(query)
        result_sets = []
        for v in variants:
            try:
                rs = fts_search(
                    db,
                    v,
                    limit=limit,
                    project=project,
                    obs_type=obs_type,
                    date_start=dateStart,
                    date_end=dateEnd,
                    offset=offset,
                )
                result_sets.append(rs)
            except Exception:
                continue

        if not result_sets:
            return "No results found."

        # RRF fusion across variants
        from mem.search.dedup import _rrf_fuse

        fused = _rrf_fuse(result_sets)
        final = dedup_results(fused[: limit * 2])[:limit]

        if not final:
            return "No results found."

        lines = [f"Found {len(final)} results:"]
        for r in final:
            proj = f" [{r.get('project', '')}]" if r.get("project") else ""
            tag = _staleness_tag(r.get("created_epoch"))
            summary = (r.get("summary") or r.get("title", ""))[:150]
            lines.append(f"  {r['id']}\t{r.get('type', '?')}\t{summary}{proj}\t{tag}")
        return _trim("\n".join(lines))

    @mcp.tool()
    def timeline(
        anchor: int = None,
        query: str = None,
        depth_before: int = 3,
        depth_after: int = 3,
        project: str = None,
    ) -> str:
        """Step 2: Get context around results. Params: anchor (observation ID) OR query."""
        db = get_db()
        if anchor is None and query:
            results = fts_search(db, query, limit=1)
            if not results:
                return "No anchor found for query."
            anchor = results[0]["id"]

        if anchor is None:
            return "Provide anchor (ID) or query."

        obs = _get_obs(db, [anchor])
        if not obs:
            return f"Observation {anchor} not found."

        center = obs[0]
        center_epoch = center.get("created_epoch", 0)
        context = db.execute(
            "SELECT id, type, title, created_at FROM observations "
            "WHERE created_epoch BETWEEN ? AND ? "
            "AND (project = ? OR ? IS NULL) "
            "ORDER BY created_epoch ASC",
            (
                center_epoch - depth_before * 86400,
                center_epoch + depth_after * 86400,
                project,
                project,
            ),
        ).fetchall()

        lines = [f"Timeline around #{anchor}:"]
        for row in context:
            marker = ">>>" if row["id"] == anchor else "   "
            lines.append(
                f"  {marker} {row['id']}\t{row['type']}\t{row['title'][:60]}\t{row['created_at'][:10]}"
            )
        return _trim("\n".join(lines))

    @mcp.tool()
    def get_observations(
        ids: list[int], project: str = None, detail: bool = False
    ) -> str:
        """Step 3: Fetch details for filtered IDs.
        detail=False (default): summary only. detail=True: full narrative + facts + files."""
        db = get_db()
        observations = _get_obs(db, ids)
        if not observations:
            return "No observations found."

        for obs in observations:
            _inc_rel(db, obs["id"])

        lines = []
        for obs in observations:
            tag = _staleness_tag(obs.get("created_epoch"))
            vtag = _verified_tag(obs)
            lines.append(
                f"## #{obs['id']} [{obs.get('type', '?')}] {vtag}{obs.get('title', '')}\t{tag}"
            )
            if detail and obs.get("narrative"):
                lines.append(obs["narrative"][:500])
            elif obs.get("summary"):
                lines.append(f"  Summary: {obs['summary']}")
            if detail:
                if obs.get("facts"):
                    try:
                        facts = (
                            json.loads(obs["facts"])
                            if isinstance(obs["facts"], str)
                            else obs["facts"]
                        )
                        for f in facts[:5]:
                            lines.append(f"  - {f}")
                    except (json.JSONDecodeError, TypeError):
                        pass
                if obs.get("files_read"):
                    try:
                        fr = (
                            json.loads(obs["files_read"])
                            if isinstance(obs["files_read"], str)
                            else obs["files_read"]
                        )
                        if fr:
                            lines.append(f"  Files: {', '.join(fr[:5])}")
                    except (json.JSONDecodeError, TypeError):
                        pass
            lines.append(
                f"  Project: {obs.get('project', '?')} | {obs.get('created_at', '')[:10]}"
            )
            lines.append("")
        return _trim("\n".join(lines))

    @mcp.tool()
    def add_observation(
        type: str = "discovery",
        title: str = "",
        narrative: str = None,
        facts: list[str] = None,
        concepts: list[str] = None,
        files_read: list[str] = None,
        files_modified: list[str] = None,
    ) -> str:
        """Add an observation to memory."""
        if not title:
            return "Error: title is required."

        db = get_db()
        obs_id = _add_obs(
            db,
            session_id="cli",
            project="",
            obs_type=type,
            title=title,
            narrative=narrative or "",
            facts=facts or [],
            concepts=concepts or [],
            files_read=files_read or [],
            files_modified=files_modified or [],
        )

        # Auto-update synthesis for each concept
        if concepts:
            for topic in concepts:
                _update_syn(db, topic, [obs_id])

        return f"Observation #{obs_id} created."

    @mcp.tool()
    def search_synthesis(query: str, limit: int = 10) -> str:
        """Search compiled truths (synthesized knowledge per topic)."""
        db = get_db()
        results = _search_syn(db, query, limit)
        if not results:
            return "No compiled truths found."

        lines = [f"Found {len(results)} compiled truths:"]
        for r in results:
            conflicts = ""
            try:
                cf = json.loads(r.get("conflict_flags", "[]"))
                if cf:
                    conflicts = f" ⚠ {len(cf)} conflicts"
            except (json.JSONDecodeError, TypeError):
                pass
            lines.append(
                f"## {r['topic']} (confidence: {r.get('confidence', 0):.1f}, {r.get('evidence_count', 0)} evidence){conflicts}"
            )
            lines.append(r.get("truth", "")[:300])
            lines.append("")
        return _trim("\n".join(lines))

    @mcp.tool()
    def related(
        id: int, depth: int = 2, max_results: int = 15, as_of: int = None
    ) -> str:
        """Traverse memory graph from an observation. Returns linked observations up to N hops.
        as_of: epoch. If set, only traverse links valid at that time."""
        db = get_db()
        from mem.storage.links import get_related

        results = get_related(db, id, depth=depth, max_results=max_results, as_of=as_of)
        if not results:
            return f"No linked observations found for #{id}."

        lines = [f"Linked to #{id} ({len(results)} results, up to {depth} hops):"]
        for r in results:
            indent = "  " * r["distance"]
            lines.append(
                f"  {indent}[{r['link_type']}] #{r['id']} {r.get('title', '')[:60]} ({r.get('project', '?')})"
            )
        return _trim("\n".join(lines))

    @mcp.tool()
    def search_entities(query: str, entity_type: str = None, limit: int = 20) -> str:
        """Search extracted entities (files, functions, tools, errors, commands)."""
        db = get_db()
        from mem.storage.entities import search_entities as _search_ent

        results = _search_ent(db, query, entity_type=entity_type, limit=limit)
        if not results:
            return f"No entities matching '{query}'."

        lines = [f"Found {len(results)} entities:"]
        for r in results:
            lines.append(
                f"  [{r['entity_type']:8s}] {r['name']} ({r['mention_count']} mentions, last: {r.get('last_seen', '?')[:10]})"
            )
        return _trim("\n".join(lines))

    @mcp.tool()
    def recall(query: str, limit: int = 15, project: str = None) -> str:
        """Unified memory search. Auto-routes to best strategy (FTS, entities, synthesis)."""
        from mem.search.recall import recall as _recall
        from mem.storage.working_memory import wm_recall

        results = _recall(query, limit=limit, project=project)

        # Working memory: zero-latency cache results
        wm_results = wm_recall(query, limit=3)

        if not results and not wm_results:
            return f"No memories found for '{query}'."

        lines = []
        if wm_results:
            lines.append(f"Working Memory ({len(wm_results)}):")
            for r in wm_results:
                lines.append(f"  WM\t{r.get('title', '')[:80]}")

        if results:
            lines.append(f"Long-term Memory ({len(results)}):")
            for r in results:
                src = r.get("source", "?")
                proj = f" [{r.get('project', '')}]" if r.get("project") else ""
                tag = _staleness_tag(r.get("created_epoch"))
                vtag = "[v] " if r.get("verified") else ""
                summary = (r.get("summary") or r.get("title", ""))[:150]
                lines.append(
                    f"  {r['id']}\t{r.get('type', '?')}\t{vtag}{summary}{proj}\t({src})\t{tag}"
                )

        # Compound loop: file query as new observation for future recall
        try:
            result_ids = [r["id"] for r in (results or []) if "id" in r]
            if result_ids:
                obs_id = _add_obs(
                    get_db(),
                    session_id="cli",
                    project=project or "",
                    obs_type="query-log",
                    title=f"recall: {query[:80]}",
                    narrative=f"Query: {query}\nResults: {result_ids[:10]}",
                    facts=[f"queried: {query}"],
                    concepts=[],
                    files_read=[],
                    files_modified=[],
                    verified=False,
                )
        except Exception:
            pass

        return _trim("\n".join(lines))

    @mcp.tool()
    def remember(
        title: str,
        narrative: str = None,
        type: str = "discovery",
        facts: list[str] = None,
        concepts: list[str] = None,
        files_read: list[str] = None,
        files_modified: list[str] = None,
        project: str = None,
    ) -> str:
        """Store a memory observation. Prefer this over add_observation."""
        if not title:
            return "Error: title is required."

        db = get_db()
        obs_id = _add_obs(
            db,
            session_id="cli",
            project=project or "",
            obs_type=type,
            title=title,
            narrative=narrative or "",
            facts=facts or [],
            concepts=concepts or [],
            files_read=files_read or [],
            files_modified=files_modified or [],
        )

        if concepts:
            for topic in concepts:
                _update_syn(db, topic, [obs_id])

        return f"Remembered as #{obs_id}."

    @mcp.tool()
    def forget(id: int) -> str:
        """Delete a memory observation by ID. Cascades to links and mentions."""
        db = get_db()
        if _delete_obs(db, id):
            return f"Forgot #{id}."
        return f"#{id} not found."

    @mcp.tool()
    def verify(id: int) -> str:
        """Mark a memory observation as human-verified. Only use for facts you've confirmed."""
        db = get_db()
        obs = _get_obs(db, [id])
        if not obs:
            return f"#{id} not found."
        db.execute("UPDATE observations SET verified = 1 WHERE id = ?", (id,))
        db.commit()
        return f"#{id} marked as verified."

    @mcp.tool()
    def feedback(id: int, positive: bool = True) -> str:
        """Give feedback on a memory observation. Adjusts retrieval weight (+/-0.2).

        Retrieval practice effect: feedback also adjusts spaced repetition.
        Positive → ease_factor increases, next_review extended 50%.
        Negative → ease_factor decreases, memory deprioritized.
        """
        import time as _time

        db = get_db()
        obs = _get_obs(db, [id])
        if not obs:
            return f"#{id} not found."

        # Read current spaced repetition state
        row = db.execute(
            "SELECT ease_factor, next_review, feedback_score FROM observations WHERE id = ?",
            (id,),
        ).fetchone()
        ef = row["ease_factor"] or 2.5
        next_rev = row["next_review"]

        if positive:
            delta = 0.2
            ef = min(3.0, ef + 0.15)
            # Extend next_review by 50%
            if next_rev:
                remaining = max(0, next_rev - int(_time.time()))
                next_rev = int(_time.time()) + int(remaining * 1.5)
        else:
            delta = -0.2
            ef = max(1.3, ef - 0.2)

        db.execute(
            "UPDATE observations SET feedback_score = feedback_score + ?, ease_factor = ?, next_review = ? WHERE id = ?",
            (delta, ef, next_rev, id),
        )
        db.commit()
        new_score = db.execute(
            "SELECT feedback_score, ease_factor FROM observations WHERE id = ?",
            (id,),
        ).fetchone()
        sign = "+" if positive else "-"
        return f"#{id} feedback {sign}0.2 → score: {new_score['feedback_score']:.1f}, ease: {new_score['ease_factor']:.2f}"

    @mcp.tool()
    def inject(query: str, limit: int = 5) -> str:
        """Lightweight recall for hook/automated use. Returns compact results (<200 tokens).

        Use for programmatic memory injection, not interactive search.
        Prefer recall() for user-facing queries."""
        from mem.search.recall import recall as _recall

        results = _recall(query, limit=limit)
        if not results:
            return ""

        lines = []
        for r in results[:limit]:
            obs_id = r.get("id", 0)
            title = r.get("title", "")[:60]
            src = r.get("source", "?")
            lines.append(f"- [#{obs_id}] {title} ({src})")

        return _trim("\n".join(lines))
