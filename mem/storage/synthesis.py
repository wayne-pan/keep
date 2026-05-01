"""Compiled Truth CRUD (gbrain pattern).

Writes also append to ~/.mind/synthesis.jsonl for durability.
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

JSONL_PATH = Path.home() / ".mind" / "synthesis.jsonl"

# Escalation thresholds (chars, ~4 chars/token)
_L1_MAX_CHARS = 2000  # ~500 tokens — full structured summary
_L2_MAX_CHARS = 1000  # ~250 tokens — bullet points only
_L3_MAX_CHARS = 500  # ~125 tokens — deterministic head+tail


def _row_to_dict(row) -> dict:
    """Convert a sqlite3.Row to a plain dict."""
    return dict(row) if row else {}


def _build_structured_truth(topic: str, obs_rows: list) -> str:
    """Build structured Markdown truth from evidence observations.

    Format: summary line + key facts + applicable scenarios.
    Inspired by EvoAgentBench skill extraction format.
    """
    if not obs_rows:
        return f"(no evidence yet) {topic}"

    # Collect facts from all observations
    facts = []
    scenarios = []
    for obs in obs_rows:
        title = obs["title"] or ""
        narrative = obs["narrative"] or ""
        obs_type = obs["type"] or "discovery"

        # Extract key facts from narrative (first 2 sentences)
        sentences = [
            s.strip() for s in narrative.replace("\n", ". ").split(".") if s.strip()
        ]
        for s in sentences[:2]:
            if s and len(s) > 10:
                facts.append(s)

        # Type-based scenario hints
        if obs_type in ("decision", "solution"):
            scenarios.append(f"When encountering: {title[:80]}")
        elif obs_type == "error":
            scenarios.append(f"Avoid: {title[:80]}")

    # Limit output size
    facts = facts[:8]
    scenarios = scenarios[:4]

    # Build summary from highest-salience observation
    best = max(obs_rows, key=lambda r: r["salience"] or 0.5)
    summary = best["title"] or topic

    parts = [f"## {summary}"]
    if facts:
        parts.append("\n### Key Facts")
        for f in facts:
            parts.append(f"- {f}")
    if scenarios:
        parts.append("\n### When to Apply")
        for s in scenarios:
            parts.append(f"- {s}")

    return "\n".join(parts)


def _escalate_truncate(text: str, max_chars: int) -> str:
    """Level 3: deterministic truncation — no LLM, guaranteed convergence.

    Takes head and tail portions to preserve start context and recent state.
    """
    if len(text) <= max_chars:
        return text
    head_budget = int(max_chars * 0.4)
    tail_budget = int(max_chars * 0.4)
    middle = "\n[...truncated — details available via get_observations...]\n"
    return text[:head_budget] + middle + text[-tail_budget:]


def _escalate_l2(text: str) -> str:
    """Level 2: extract only bullet points from structured truth.

    Drops prose, keeps '- ' lines. No LLM needed — deterministic.
    """
    lines = text.split("\n")
    bullets = [l for l in lines if l.strip().startswith("- ")]
    # Also keep ## header
    headers = [l for l in lines if l.strip().startswith("## ")]
    parts = headers[:1] + bullets[:10]
    result = "\n".join(parts)
    if len(result) > _L2_MAX_CHARS:
        return _escalate_truncate(result, _L2_MAX_CHARS)
    return result


def synthesize_with_escalation(topic: str, obs_rows: list) -> str:
    """3-level escalation for synthesis truth generation.

    L1: Full structured truth (facts + scenarios) — up to _L1_MAX_CHARS
    L2: Bullet points only — up to _L2_MAX_CHARS
    L3: Deterministic head+tail truncation — up to _L3_MAX_CHARS

    Guarantees convergence: L3 is pure string ops, always succeeds.
    """
    truth = _build_structured_truth(topic, obs_rows)

    # L1: check if fits
    if len(truth) <= _L1_MAX_CHARS:
        return truth

    logger.debug("Synthesis L1 overflow (%d chars), escalating to L2", len(truth))

    # L2: bullet-point extraction
    truth = _escalate_l2(truth)
    if len(truth) <= _L2_MAX_CHARS:
        return truth

    logger.debug("Synthesis L2 overflow (%d chars), escalating to L3", len(truth))

    # L3: deterministic truncation (guaranteed to converge)
    return _escalate_truncate(truth, _L3_MAX_CHARS)


def _append_jsonl(record: dict) -> None:
    """Append a record dict as one JSON line to the JSONL file."""
    JSONL_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(JSONL_PATH, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")


def get_synthesis(conn, topic: str) -> dict | None:
    """Fetch a single compiled truth by topic. Returns dict or None."""
    row = conn.execute(
        "SELECT * FROM synthesis WHERE topic = ?",
        (topic,),
    ).fetchone()
    return _row_to_dict(row) if row else None


def update_synthesis(conn, topic: str, new_obs_ids: list[int]) -> None:
    """Create or update a compiled truth for the given topic.

    If topic exists: merge evidence_ids, rebuild truth from all evidence
    observations, increment confidence by 0.1 (max 1.0), bump updated_count.

    If new: create with confidence 0.3, truth built from the given obs_ids.
    """
    now_iso = datetime.now(timezone.utc).isoformat()
    now_epoch = int(datetime.now(timezone.utc).timestamp())

    existing = conn.execute(
        "SELECT * FROM synthesis WHERE topic = ?",
        (topic,),
    ).fetchone()

    if existing:
        # Merge evidence IDs
        old_ids = json.loads(existing["evidence_ids"])
        merged_ids = list(dict.fromkeys(old_ids + new_obs_ids))  # dedup, preserve order
    else:
        merged_ids = list(dict.fromkeys(new_obs_ids))

    # Fetch all evidence observations to build truth
    if merged_ids:
        placeholders = ",".join("?" for _ in merged_ids)
        obs_rows = conn.execute(
            f"SELECT type, title, narrative, salience FROM observations WHERE id IN ({placeholders})",
            merged_ids,
        ).fetchall()
        truth = synthesize_with_escalation(topic, obs_rows)
    else:
        truth = f"(no evidence yet) {topic}"

    evidence_json = json.dumps(merged_ids, ensure_ascii=False)
    evidence_count = len(merged_ids)

    if existing:
        # Salience-aware confidence merge (borrowed from oh-my-codex append-only):
        # Take max of existing confidence and salience-weighted average of evidence.
        # High-salience evidence pushes confidence up; low-salience doesn't lower it.
        if obs_rows:
            salience_avg = sum(r["salience"] or 0.5 for r in obs_rows) / len(obs_rows)
            new_confidence = min(1.0, max(existing["confidence"], salience_avg * 1.2))
        else:
            new_confidence = existing["confidence"]
        conn.execute(
            """
            UPDATE synthesis SET
                truth = ?,
                evidence_ids = ?,
                evidence_count = ?,
                confidence = ?,
                last_updated = ?,
                last_epoch = ?,
                updated_count = updated_count + 1
            WHERE topic = ?
            """,
            (
                truth,
                evidence_json,
                evidence_count,
                new_confidence,
                now_iso,
                now_epoch,
                topic,
            ),
        )
    else:
        new_confidence = 0.3
        conn.execute(
            """
            INSERT INTO synthesis
                (topic, truth, evidence_ids, evidence_count, confidence,
                 first_seen, last_updated, last_epoch, updated_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
            """,
            (
                topic,
                truth,
                evidence_json,
                evidence_count,
                new_confidence,
                now_iso,
                now_iso,
                now_epoch,
            ),
        )

    conn.commit()

    _append_jsonl(
        {
            "op": "update",
            "topic": topic,
            "evidence_ids": merged_ids,
            "evidence_count": evidence_count,
            "confidence": new_confidence if existing else 0.3,
            "updated_at": now_iso,
        }
    )


def search_synthesis(conn, query: str, limit: int = 20) -> list[dict]:
    """FTS5 search on synthesis_fts. Returns list of dicts."""
    # Escape double quotes in query for FTS5
    safe_query = query.replace('"', '""')
    fts_expr = f'"{safe_query}"'

    try:
        rows = conn.execute(
            """
            SELECT s.*, bm25(synthesis_fts) as rank
            FROM synthesis_fts f
            JOIN synthesis s ON s.id = f.rowid
            WHERE synthesis_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """,
            (fts_expr, limit),
        ).fetchall()
    except Exception:
        # FTS5 can throw on malformed queries; fall back to LIKE
        rows = conn.execute(
            """
            SELECT *, 0.0 as rank FROM synthesis
            WHERE topic LIKE ? OR truth LIKE ?
            ORDER BY last_epoch DESC
            LIMIT ?
            """,
            (f"%{query}%", f"%{query}%", limit),
        ).fetchall()

    return [_row_to_dict(r) for r in rows]


def list_topics(conn) -> list[str]:
    """Return all synthesis topics ordered by last_epoch DESC."""
    rows = conn.execute(
        "SELECT topic FROM synthesis ORDER BY last_epoch DESC"
    ).fetchall()
    return [r["topic"] for r in rows]


def delete_synthesis(conn, topic: str) -> bool:
    """Delete a synthesis entry by topic. Returns True if removed."""
    cursor = conn.execute("DELETE FROM synthesis WHERE topic = ?", (topic,))
    conn.commit()
    _append_jsonl({"op": "delete", "topic": topic})
    return cursor.rowcount > 0
