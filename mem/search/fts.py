"""FTS5 BM25 query builder for observations.

Provides filtered full-text search with BM25 ranking and temporal boosting.
Robust handling of CJK, emoji, and FTS-special characters via LIKE fallback.
"""

from __future__ import annotations

import re
import time

# CJK Unicode ranges
_CJK_RE = re.compile(
    r"[\u3400-\u4dbf\u4e00-\u9fff\u3000-\u303f"
    r"\u3040-\u30ff\uac00-\ud7af\uff00-\uffef]"
)

# Emoji Unicode ranges
_EMOJI_RE = re.compile(r"[\u2600-\u27bf\U0001F300-\U0001FAFF]")

# Characters that break FTS5 phrase queries
_FTS_SPECIAL_RE = re.compile(r'[()[\]{}*:"\\]')

# Tokens with embedded punctuation that FTS5 tokenizer may mishandle
_RISKY_TOKEN_RE = re.compile(r"[A-Za-z0-9][\-:/][A-Za-z0-9]")


def _needs_like_fallback(query: str) -> bool:
    """Check if query contains characters that break FTS5 MATCH.

    Returns True when the query should use LIKE instead of FTS5 MATCH.
    """
    if not query or not query.strip():
        return True
    if _CJK_RE.search(query):
        return True
    if _EMOJI_RE.search(query):
        return True
    if _FTS_SPECIAL_RE.search(query):
        return True
    # Unmatched double quotes
    if query.count('"') % 2 != 0:
        return True
    # Tokens with embedded hyphens/colons/slashes
    if _RISKY_TOKEN_RE.search(query):
        return True
    return False


def _build_match_expr(query: str) -> str:
    """Build an FTS5 MATCH expression, escaping double quotes."""
    safe = query.replace('"', '""')
    return f'"{safe}"'


def _escape_like(text: str) -> str:
    """Escape LIKE wildcards in text."""
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _recency_score(created_epoch: int | None, now_s: int | None = None) -> float:
    """Compute recency score: 1/(1+log(1+age_days)).

    New observations get ~1.0, 1-day-old ~0.67, 30-day-old ~0.41, 1-year ~0.33.
    All epochs in seconds (matching observations.created_epoch).
    """
    if not created_epoch:
        return 0.5
    now = now_s or int(time.time())
    age_days = max(0, (now - created_epoch)) / 86400
    return 1.0 / (1.0 + __import__("math").log(1.0 + age_days))


def fts_search(
    conn,
    query: str,
    limit: int = 20,
    project: str | None = None,
    obs_type: str | None = None,
    date_start: str | None = None,
    date_end: str | None = None,
    offset: int = 0,
) -> list[dict]:
    """Full-text search over observations with BM25 ranking.

    Returns list of dicts with: id, type, title, created_at, project, rank.
    Additional columns from observations are included as well.
    """
    match_expr = _build_match_expr(query)

    where_clauses = ["f.obs_fts MATCH ?"]
    params: list = [match_expr]

    if project:
        where_clauses.append("o.project = ?")
        params.append(project)

    if obs_type:
        where_clauses.append("o.type = ?")
        params.append(obs_type)

    if date_start:
        where_clauses.append("o.created_at >= ?")
        params.append(date_start)

    if date_end:
        where_clauses.append("o.created_at <= ?")
        params.append(date_end)

    where_sql = " AND ".join(where_clauses)
    params.extend([limit, offset])

    # Skip FTS5 for queries with CJK/emoji/special chars — go straight to LIKE
    skip_fts = _needs_like_fallback(query)

    if not skip_fts:
        sql = f"""
            SELECT o.id, o.type, o.title, o.narrative, o.created_at,
                   o.project, o.session_id, o.relevance_count,
                   o.summary, o.created_epoch, o.feedback_score,
                   o.salience, o.next_review, o.ease_factor,
                   bm25(f) as rank
            FROM obs_fts f
            JOIN observations o ON o.id = f.rowid
            WHERE {where_sql}
            ORDER BY rank
            LIMIT ? OFFSET ?
        """
        try:
            rows = conn.execute(sql, params).fetchall()
        except Exception:
            skip_fts = True

    if skip_fts:
        # Fallback: LIKE search when FTS5 chokes on the query
        escaped = _escape_like(query)
        like_params: list = []
        fallback_where = ["(o.title LIKE ? OR o.narrative LIKE ? ESCAPE '\\')"]
        like_params.extend([f"%{escaped}%", f"%{escaped}%"])

        if project:
            fallback_where.append("o.project = ?")
            like_params.append(project)
        if obs_type:
            fallback_where.append("o.type = ?")
            like_params.append(obs_type)
        if date_start:
            fallback_where.append("o.created_at >= ?")
            like_params.append(date_start)
        if date_end:
            fallback_where.append("o.created_at <= ?")
            like_params.append(date_end)

        like_params.extend([limit, offset])
        fallback_sql = f"""
            SELECT o.id, o.type, o.title, o.narrative, o.created_at,
                   o.project, o.session_id, o.relevance_count,
                   o.summary, o.created_epoch, o.feedback_score,
                   o.salience, o.next_review, o.ease_factor,
                   0.0 as rank
            FROM observations o
            WHERE {" AND ".join(fallback_where)}
            ORDER BY o.created_epoch DESC
            LIMIT ? OFFSET ?
        """
        rows = conn.execute(fallback_sql, like_params).fetchall()

    # Apply temporal boosting + salience + spaced repetition weighting
    now_s = int(time.time())
    results = []
    for r in rows:
        d = dict(r)
        bm25 = d.get("rank", 0.0)
        recency = _recency_score(d.get("created_epoch"), now_s)

        # Emotional salience (0.0-1.0, default 0.5)
        salience = d.get("salience", 0.5) or 0.5

        # Review due boost: observation scheduled for review gets priority
        next_review = d.get("next_review")
        review_due = 1.0 if (next_review and next_review < now_s) else 0.0

        # Frequently recalled boost (capped at 1.0 for 10+ recalls)
        rel_count = d.get("relevance_count", 0) or 0
        rel_boost = min(1.0, rel_count / 10.0)

        d["bm25_score"] = bm25
        d["recency_score"] = round(recency, 3)
        d["salience_score"] = round(salience, 2)
        d["review_due_score"] = review_due
        d["rel_boost_score"] = rel_boost
        results.append(d)

    # Sort by blended score (negate bm25 since lower=better in FTS5)
    results.sort(
        key=lambda x: (
            (-x.get("bm25_score", 0)) * 0.65
            + x.get("recency_score", 0) * 0.15
            + x.get("salience_score", 0.5) * 0.10
            + x.get("review_due_score", 0) * 0.05
            + x.get("rel_boost_score", 0) * 0.05
        ),
        reverse=True,
    )
    return results
