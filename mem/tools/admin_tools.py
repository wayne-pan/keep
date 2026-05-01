"""Admin tools: dream_cycle, stats, workflow instructions, lifecycle, dashboard."""

import json
import os
import time as _time
from mem.storage.database import get_db, MEM_DIR
from mem.dream.cycle import run_dream_cycle
from mem.tools import _trim


def register_admin_tools(mcp):
    @mcp.tool()
    def dream_cycle(mode: str = "full") -> str:
        """Execute dream cycle maintenance: dedup, merge, prune, strengthen compiled truths.

        Modes: 'full' (all), 'dedup', 'merge', 'prune', 'strengthen'.
        Run periodically or at session end to keep memory healthy."""
        db = get_db()
        results = run_dream_cycle(db, mode=mode)
        lines = [f"Dream cycle ({mode}) completed:"]
        for r in results:
            lines.append(f"  {r.get('operation', '?')}: {r}")
        return _trim("\n".join(lines))

    @mcp.tool()
    def stats() -> str:
        """Show memory system statistics: observation count, sessions, synthesis topics, DB size."""
        db = get_db()
        obs_count = db.execute("SELECT COUNT(*) as c FROM observations").fetchone()["c"]
        syn_count = db.execute("SELECT COUNT(*) as c FROM synthesis").fetchone()["c"]
        sess_count = db.execute("SELECT COUNT(*) as c FROM sessions").fetchone()["c"]
        dream_count = db.execute("SELECT COUNT(*) as c FROM dream_log").fetchone()["c"]

        db_size = 0
        db_path = MEM_DIR / "memory.db"
        if db_path.exists():
            db_size = db_path.stat().st_size / (1024 * 1024)

        lines = [
            f"Observations:  {obs_count}",
            f"Synthesis:     {syn_count} topics",
            f"Sessions:      {sess_count}",
            f"Dream cycles:  {dream_count}",
            f"DB size:       {db_size:.1f} MB",
            f"Storage:       {MEM_DIR}",
        ]
        return _trim("\n".join(lines))

    @mcp.tool()
    def wakeup(project: str = None) -> str:
        """Wake-up layer: load critical memory context for session start.

        MemPalace pattern: ~250 token blob with top synthesis truths
        + recent high-salience observations, giving immediate project awareness.
        Run once at session start."""
        from mem.search.wakeup import generate_wake_up

        blob = generate_wake_up(project=project, max_tokens=250)
        return (
            blob
            if blob
            else "No synthesis truths available yet. Run dream_cycle first."
        )

    @mcp.tool()
    def lifecycle_transition(
        id: int, new_state: str, reason: str = None, decided_by: str = "human"
    ) -> str:
        """Transition an observation's lifecycle state.

        Valid transitions: staged→accepted, staged→rejected, accepted→archived, rejected→accepted.
        All transitions are logged to decision_log for audit trail."""
        from mem.storage.observations import lifecycle_transition as _lt

        db = get_db()
        ok = _lt(db, id, new_state, reason=reason, decided_by=decided_by)
        if ok:
            return f"#{id} → {new_state}"
        return f"Invalid transition: #{id} → {new_state}"

    @mcp.tool()
    def review_queue(status: str = "staged", limit: int = 20, offset: int = 0) -> str:
        """Show observations pending review by lifecycle state.

        Default shows staged observations. Use status='rejected' for rejected items."""
        from mem.storage.observations import get_review_queue

        db = get_db()
        queue = get_review_queue(db, status=status, limit=limit, offset=offset)
        if not queue:
            return f"No {status} observations."

        lines = [f"## {status.title()} Queue ({len(queue)})"]
        for i, obs in enumerate(queue, 1):
            summary = obs.get("summary") or obs.get("title", "")
            salience = obs.get("salience", 0)
            lines.append(
                f"### {i}. [{obs.get('type', '?')}] #{obs['id']} {summary[:80]}"
            )
            if obs.get("narrative"):
                lines.append(f"  {obs['narrative'][:200]}")
            lines.append(
                f"  Salience: {salience:.1f} | {obs.get('created_at', '')[:10]}"
            )
            lines.append(
                f"  Accept: lifecycle_transition(id={obs['id']}, new_state='accepted') | "
                f"Reject: lifecycle_transition(id={obs['id']}, new_state='rejected')"
            )
            lines.append("")
        return _trim("\n".join(lines))

    @mcp.tool()
    def decision_history(id: int) -> str:
        """Show lifecycle decision history for an observation."""
        db = get_db()
        rows = db.execute(
            "SELECT * FROM decision_log WHERE observation_id = ? ORDER BY decided_epoch",
            (id,),
        ).fetchall()
        if not rows:
            return f"No decision history for #{id}."

        lines = [f"Decision history for #{id}:"]
        for r in rows:
            lines.append(
                f"  {r['from_state']} → {r['to_state']} by {r['decided_by']} "
                f"at {r.get('decided_at', '?')[:16]}"
            )
            if r.get("reason"):
                lines.append(f"    Reason: {r['reason']}")
        return _trim("\n".join(lines))

    @mcp.tool()
    def onboard_status() -> str:
        """Check onboarding status. Returns current state and flag file path."""
        flag_file = MEM_DIR / "onboarded"
        if flag_file.exists():
            return "Already onboarded."
        return "Not onboarded yet. Run /onboard to set up personal preferences."

    @mcp.tool()
    def dashboard() -> str:
        """Terminal dashboard: brain state visualization.

        Shows MEMORY, DREAM, REVIEW, and ACTIVITY panels."""
        db = get_db()

        # MEMORY panel
        obs_count = db.execute("SELECT COUNT(*) as c FROM observations").fetchone()["c"]
        syn_count = db.execute("SELECT COUNT(*) as c FROM synthesis").fetchone()["c"]
        ent_count = db.execute("SELECT COUNT(*) as c FROM entities").fetchone()["c"]
        lifecycle_rows = db.execute(
            "SELECT lifecycle, COUNT(*) as c FROM observations GROUP BY lifecycle"
        ).fetchall()
        lifecycle_map = {r["lifecycle"] or "accepted": r["c"] for r in lifecycle_rows}

        # DREAM panel
        last_dream = db.execute(
            "SELECT ran_at, operation FROM dream_log ORDER BY ran_epoch DESC LIMIT 1"
        ).fetchone()
        dream_count = db.execute("SELECT COUNT(*) as c FROM dream_log").fetchone()["c"]

        # REVIEW panel
        staged_count = lifecycle_map.get("staged", 0)
        rejected_count = lifecycle_map.get("rejected", 0)

        # ACTIVITY panel (observations/day, last 14 days)
        now_epoch = int(_time.time())
        day_buckets = [0] * 14
        for i in range(14):
            day_start = now_epoch - (13 - i) * 86400
            day_end = day_start + 86400
            cnt = db.execute(
                "SELECT COUNT(*) as c FROM observations WHERE created_epoch BETWEEN ? AND ?",
                (day_start, day_end),
            ).fetchone()["c"]
            day_buckets[i] = cnt

        lines = [
            "## MEMORY",
            f"  Observations: {obs_count}  Synthesis: {syn_count}  Entities: {ent_count}",
            f"  Lifecycle: accepted={lifecycle_map.get('accepted', 0)}  "
            f"staged={staged_count}  rejected={rejected_count}  "
            f"archived={lifecycle_map.get('archived', 0)}",
            "",
            "## DREAM",
            f"  Total runs: {dream_count}  Last: "
            + (
                f"{last_dream['ran_at'][:16]} ({last_dream['operation']})"
                if last_dream
                else "never"
            ),
            "",
            "## REVIEW",
            f"  Staged: {staged_count}  Rejected: {rejected_count}",
            "",
            "## ACTIVITY (observations/day, last 14 days)",
        ]

        # Sparkline using Unicode block chars
        max_val = max(day_buckets) if day_buckets else 1
        if max_val == 0:
            max_val = 1
        blocks = " ▁▂▃▄▅▆▇█"
        spark = ""
        for v in day_buckets:
            idx = min(8, int(v * 8 / max_val))
            spark += blocks[idx]
        lines.append(f"  {spark}")
        lines.append(f"  {day_buckets[0]} ... {day_buckets[-1]} (per day)")

        return _trim("\n".join(lines))

    @mcp.tool()
    def __IMPORTANT() -> str:
        """3-LAYER WORKFLOW (ALWAYS FOLLOW):
        1. search(query) → Get index with IDs (~50-100 tokens/result)
        2. timeline(anchor=ID) → Get context around interesting results
        3. get_observations([IDs]) → Fetch full details ONLY for filtered IDs
        NEVER fetch full details without filtering first. 10x token savings."""
        return (
            "3-LAYER WORKFLOW (ALWAYS FOLLOW):\n"
            "1. search(query) → Get index with IDs (~50-100 tokens/result)\n"
            "2. timeline(anchor=ID) → Get context around interesting results\n"
            "3. get_observations([IDs]) → Fetch full details ONLY for filtered IDs\n"
            "NEVER fetch full details without filtering first. 10x token savings."
        )
