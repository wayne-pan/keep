"""CRUD operations for observations.

All writes also append to ~/.mind/observations.jsonl for durability.
"""

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from .database import get_db

JSONL_PATH = Path.home() / ".mind" / "observations.jsonl"


def hash_content(text: str) -> str:
    """SHA256 of text, first 12 hex characters."""
    return hashlib.sha256(text.encode()).hexdigest()[:12]


def compute_pattern_id(title: str, narrative: str) -> str:
    """MD5 hash of normalized content for deterministic dedup.

    Normalizes: lowercase, strip, collapse whitespace.
    Returns 16-char hex string.
    """
    text = f"{title or ''} {narrative or ''}".lower().strip()
    text = re.sub(r"\s+", " ", text)
    return hashlib.md5(text.encode()).hexdigest()[:16]


def _row_to_dict(row) -> dict:
    """Convert a sqlite3.Row to a plain dict."""
    return dict(row) if row else {}


def _append_jsonl(record: dict) -> None:
    """Append a record dict as one JSON line to the JSONL file."""
    JSONL_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(JSONL_PATH, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")


def generate_summary(narrative: str, title: str = "", max_len: int = 150) -> str:
    """Generate a compressed summary for index-style retrieval.

    Pure heuristic: first sentence (10 < len < 150), else truncated prefix.
    Falls back to title if narrative is empty.
    """
    text = narrative or title or ""
    if not text:
        return ""

    # Try first sentence
    for sep in (". ", "! ", "? ", "。\n", "！\n"):
        idx = text.find(sep)
        if 10 < idx + len(sep) < max_len:
            return text[: idx + len(sep)].strip()

    # Truncate at word boundary
    if len(text) <= max_len:
        return text
    truncated = text[:max_len]
    space = truncated.rfind(" ")
    if space > max_len // 2:
        return truncated[:space].strip() + "..."
    return truncated.strip() + "..."


def _semantic_density_gate(
    title: str, narrative: str, facts: list, concepts: list
) -> bool:
    """Return False if observation is too low-density to store.

    Filters: empty narrative + no facts, generic titles, tool-only echoes.
    """
    text = f"{title} {narrative or ''}"
    # Skip if <20 chars of actual content
    if len(text.strip()) < 20 and not facts:
        return False
    # Skip generic titles with no narrative
    GENERIC = {"observation", "note", "finding", "discovery", "tool usage"}
    if title.lower().strip() in GENERIC and not narrative and not facts:
        return False
    return True


def _resolve_coreferences(
    title: str, narrative: str, files_read: list, files_modified: list
) -> str:
    """Detect vague references in narrative and append concrete file paths.

    Looks for: "this file", "the above", "上述", "该文件", "当前文件"
    Appends [Files: path1, path2] footer if references found and files available.
    """
    import re

    if not narrative:
        return narrative or ""

    COREF_PATTERNS = (
        r"\bthis file\b",
        r"\bthis function\b",
        r"\bthis module\b",
        r"\bthe above\b",
        r"\bthe following\b",
        "上述",
        "该文件",
        "当前文件",
        "这个函数",
        "该方法",
    )
    has_coref = any(re.search(p, narrative, re.IGNORECASE) for p in COREF_PATTERNS)
    if not has_coref:
        return narrative

    all_files = list(dict.fromkeys((files_read or []) + (files_modified or [])))
    if not all_files:
        return narrative

    # Only include short paths (last 2 components) to avoid noise
    short_paths = []
    for f in all_files[:3]:
        parts = Path(f).parts
        short_paths.append(str(Path(*parts[-2:])) if len(parts) >= 2 else f)

    return f"{narrative.rstrip()}\n[Files: {', '.join(short_paths)}]"


def _assess_salience(obs_type: str, title: str, narrative: str) -> float:
    """Assess emotional salience of an observation (0.0-1.0).

    High (0.8-1.0): errors, user corrections, security findings, critical decisions
    Medium (0.5-0.7): architecture decisions, new patterns, non-trivial discoveries
    Low (0.1-0.3): routine tool usage, trivial observations
    """
    text = f"{title} {(narrative or '')}".lower()

    # High salience signals
    HIGH_PATTERNS = (
        r"\b(?:critical|urgent|security|vulnerability|exploit|injection|escalation)\b",
        r"\b(?:wrong|incorrect|mistake|error|bug|crash|fail|broken)\b",
        r"\b(?:rollback|revert|undo|corrupted|data.?loss)\b",
        "严重|紧急|安全|漏洞|注入|提权|错误|崩溃|修复|回滚|数据丢失",
    )
    for p in HIGH_PATTERNS:
        if re.search(p, text):
            return 0.9

    # Medium salience: architecture/design decisions
    MED_PATTERNS = (
        r"\b(?:decision|architecture|design|refactor|migrate|strategy)\b",
        "重要|决定|架构|设计|重构|迁移|方案",
    )
    for p in MED_PATTERNS:
        if re.search(p, text):
            return 0.7

    # Type-based: solutions and corrections are inherently important
    if obs_type in ("solution", "correction", "preference"):
        return 0.8
    if obs_type in ("decision", "milestone"):
        return 0.7

    return 0.5  # Default: normal observation


def _check_similar(
    conn, title: str, narrative: str, threshold: float = 0.80
) -> int | None:
    """Return existing obs_id if a similar observation exists.

    Two-tier dedup:
      1. Deterministic: exact pattern_id match (MD5 of normalized content)
      2. Fuzzy: Jaccard similarity > threshold on recent 200 observations
    """
    # Tier 1: Deterministic pattern_id lookup
    pid = compute_pattern_id(title, narrative or "")
    exact = conn.execute(
        "SELECT id FROM observations WHERE pattern_id = ? LIMIT 1", (pid,)
    ).fetchone()
    if exact:
        return exact["id"]

    # Tier 2: Fuzzy Jaccard match
    from ..search.dedup import _jaccard, _tokenize

    new_tokens = _tokenize(title + " " + (narrative or ""))
    if len(new_tokens) < 3:
        return None

    rows = conn.execute(
        "SELECT id, title, narrative FROM observations ORDER BY id DESC LIMIT 200"
    ).fetchall()

    for row in rows:
        existing_tokens = _tokenize(
            (row["title"] or "") + " " + (row["narrative"] or "")
        )
        if _jaccard(new_tokens, existing_tokens) > threshold:
            return row["id"]
    return None


def add_observation(
    conn,
    session_id: str,
    project: str,
    obs_type: str,
    title: str,
    narrative: str,
    facts: list[str] | None = None,
    concepts: list[str] | None = None,
    files_read: list[str] | None = None,
    files_modified: list[str] | None = None,
    context_tags: dict | None = None,
    verified: bool = False,
) -> int:
    """Insert a new observation. Returns the row id."""
    now_iso = datetime.now(timezone.utc).isoformat()
    now_epoch = int(datetime.now(timezone.utc).timestamp())

    facts_json = json.dumps(facts or [], ensure_ascii=False)
    concepts_json = json.dumps(concepts or [], ensure_ascii=False)
    files_read_json = json.dumps(files_read or [], ensure_ascii=False)
    files_modified_json = json.dumps(files_modified or [], ensure_ascii=False)
    context_tags_json = json.dumps(context_tags or {}, ensure_ascii=False)

    # --- Admission gate: density filter + coreference + online merge ---
    if not _semantic_density_gate(title, narrative, facts or [], concepts or []):
        return 0  # Rejected by density gate

    # Assess emotional salience
    salience = _assess_salience(obs_type, title, narrative or "")

    # Resolve coreferences before similarity check
    narrative = _resolve_coreferences(title, narrative, files_read, files_modified)

    existing = _check_similar(conn, title, narrative or "")
    if existing:
        # Online merge: combine new facts/concepts/files into existing
        try:
            row = conn.execute(
                "SELECT facts, concepts, files_read, files_modified, narrative FROM observations WHERE id = ?",
                (existing,),
            ).fetchone()
            if row:
                existing_facts = set(json.loads(row["facts"] or "[]"))
                existing_concepts = set(json.loads(row["concepts"] or "[]"))
                existing_fr = set(json.loads(row["files_read"] or "[]"))
                existing_fm = set(json.loads(row["files_modified"] or "[]"))

                new_facts = set(facts or []) - existing_facts
                new_concepts = set(concepts or []) - existing_concepts
                new_fr = set(files_read or []) - existing_fr
                new_fm = set(files_modified or []) - existing_fm

                merged_facts = json.dumps(
                    sorted(existing_facts | new_facts), ensure_ascii=False
                )
                merged_concepts = json.dumps(
                    sorted(existing_concepts | new_concepts), ensure_ascii=False
                )
                merged_fr = json.dumps(sorted(existing_fr | new_fr), ensure_ascii=False)
                merged_fm = json.dumps(sorted(existing_fm | new_fm), ensure_ascii=False)

                # Append new narrative snippet if it adds content
                old_narr = row["narrative"] or ""
                if narrative and narrative not in old_narr:
                    merged_narr = (
                        f"{old_narr}\n---\n{narrative}" if old_narr else narrative
                    )
                else:
                    merged_narr = old_narr

                conn.execute(
                    """UPDATE observations SET
                        facts = ?, concepts = ?, files_read = ?, files_modified = ?,
                        narrative = ?, retrieval_weight = retrieval_weight + 0.1,
                        summary = ?
                    WHERE id = ?""",
                    (
                        merged_facts,
                        merged_concepts,
                        merged_fr,
                        merged_fm,
                        merged_narr,
                        generate_summary(merged_narr, title),
                        existing,
                    ),
                )
                conn.commit()
                _append_jsonl(
                    {
                        "op": "merge",
                        "id": existing,
                        "new_facts": list(new_facts),
                        "new_concepts": list(new_concepts),
                    }
                )
            else:
                # Fallback: just bump weight
                conn.execute(
                    "UPDATE observations SET retrieval_weight = retrieval_weight + 0.1 WHERE id = ?",
                    (existing,),
                )
                conn.commit()
        except Exception:
            pass
        return existing

    # Compute hash/summary after coreference resolution
    content_hash = hash_content(title + (narrative or ""))
    pattern_id = compute_pattern_id(title, narrative or "")

    # Auto-classify hall (MemPalace spatial pattern)
    hall = ""
    try:
        from ..search.hall import classify_hall

        hall = classify_hall(obs_type, title, narrative or "")
    except Exception:
        pass

    summary = generate_summary(narrative or "", title)

    # Initial next_review: 7 days from now (SM-2 starting interval)
    next_review = now_epoch + 7 * 86400

    cursor = conn.execute(
        """
        INSERT INTO observations
            (session_id, project, type, title, narrative, summary,
             facts, concepts, files_read, files_modified,
             content_hash, pattern_id, lifecycle,
             created_at, created_epoch, hall,
             salience, ease_factor, next_review, context_tags, verified)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'staged',
                ?, ?, ?, ?, 2.5, ?, ?, ?)
        """,
        (
            session_id,
            project,
            obs_type,
            title,
            narrative,
            summary,
            facts_json,
            concepts_json,
            files_read_json,
            files_modified_json,
            content_hash,
            pattern_id,
            now_iso,
            now_epoch,
            hall,
            salience,
            next_review,
            context_tags_json,
            1 if verified else 0,
        ),
    )
    conn.commit()
    obs_id = cursor.lastrowid

    _append_jsonl(
        {
            "op": "add",
            "id": obs_id,
            "session_id": session_id,
            "project": project,
            "type": obs_type,
            "title": title,
            "narrative": narrative,
            "facts": facts or [],
            "concepts": concepts or [],
            "files_read": files_read or [],
            "files_modified": files_modified or [],
            "content_hash": content_hash,
            "created_at": now_iso,
            "created_epoch": now_epoch,
        }
    )

    # Auto-extract entities (Hindsight pattern)
    try:
        from .entities import store_entities

        text = " ".join([title, narrative or ""] + (facts or []) + (concepts or []))
        store_entities(conn, obs_id, text)
    except Exception:
        pass  # Entity extraction is non-critical

    return obs_id


def get_observations(conn, ids: list[int]) -> list[dict]:
    """Fetch observations by id list. Returns list of dicts."""
    if not ids:
        return []
    placeholders = ",".join("?" for _ in ids)
    rows = conn.execute(
        f"""
        SELECT * FROM observations
        WHERE id IN ({placeholders})
        ORDER BY created_epoch DESC
        """,
        ids,
    ).fetchall()
    return [_row_to_dict(r) for r in rows]


def search_by_epoch(
    conn,
    center_epoch: int,
    before: int = 3600,
    after: int = 3600,
    project: str | None = None,
) -> list[dict]:
    """Return observations within [center_epoch - before, center_epoch + after].

    Used for timeline reconstruction around an anchor point.
    """
    epoch_min = center_epoch - before
    epoch_max = center_epoch + after
    if project:
        rows = conn.execute(
            """
            SELECT * FROM observations
            WHERE created_epoch BETWEEN ? AND ?
              AND project = ?
            ORDER BY created_epoch DESC
            """,
            (epoch_min, epoch_max, project),
        ).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT * FROM observations
            WHERE created_epoch BETWEEN ? AND ?
            ORDER BY created_epoch DESC
            """,
            (epoch_min, epoch_max),
        ).fetchall()
    return [_row_to_dict(r) for r in rows]


def increment_relevance(conn, obs_id: int) -> None:
    """Recall an observation: increment count + SM-2 spaced repetition.

    SM-2 algorithm adapts review interval based on recall history.
    High salience memories get longer intervals (remembered longer).
    """
    now = int(datetime.now(timezone.utc).timestamp())

    row = conn.execute(
        "SELECT relevance_count, ease_factor, salience FROM observations WHERE id = ?",
        (obs_id,),
    ).fetchone()
    if not row:
        return

    count = (row["relevance_count"] or 0) + 1
    ef = row["ease_factor"] or 2.5
    salience = row["salience"] or 0.5

    # SM-2: ease factor increases with successful recalls
    if count > 3:
        ef = min(3.0, ef + 0.1)

    # Calculate next interval (days): starts at 7, multiplied by ease_factor each recall
    base_interval = 7
    for _ in range(count):
        base_interval = int(base_interval * ef)
    # High salience -> longer retention (1.5x-2x)
    salience_boost = 1.0 + salience
    interval_days = int(base_interval * salience_boost)
    next_review = now + interval_days * 86400

    conn.execute(
        "UPDATE observations SET relevance_count = ?, ease_factor = ?, next_review = ? WHERE id = ?",
        (count, ef, next_review, obs_id),
    )
    conn.commit()


def delete_observation(conn, obs_id: int) -> bool:
    """Delete an observation by id. Returns True if a row was removed."""
    cursor = conn.execute("DELETE FROM observations WHERE id = ?", (obs_id,))
    conn.commit()
    _append_jsonl({"op": "delete", "id": obs_id})
    return cursor.rowcount > 0


def update_observation(conn, obs_id: int, **fields) -> bool:
    """Update arbitrary fields on an observation. Returns True if updated."""
    if not fields:
        return False
    set_clause = ", ".join(f"{k} = ?" for k in fields)
    values = list(fields.values()) + [obs_id]
    cursor = conn.execute(f"UPDATE observations SET {set_clause} WHERE id = ?", values)
    conn.commit()
    _append_jsonl({"op": "update", "id": obs_id, **fields})
    return cursor.rowcount > 0


def get_by_session(conn, session_id: str) -> list[dict]:
    """Fetch all observations for a given session."""
    rows = conn.execute(
        "SELECT * FROM observations WHERE session_id = ? ORDER BY created_epoch ASC",
        (session_id,),
    ).fetchall()
    return [_row_to_dict(r) for r in rows]


def count_by_project(conn, project: str) -> int:
    """Count observations for a project."""
    row = conn.execute(
        "SELECT COUNT(*) as cnt FROM observations WHERE project = ?",
        (project,),
    ).fetchone()
    return row["cnt"] if row else 0


# ---------------------------------------------------------------------------
# Lifecycle management (F1 + F2)
# ---------------------------------------------------------------------------

_VALID_LIFECYCLE = {"staged", "accepted", "rejected", "archived"}
_TRANSITIONS = {
    ("staged", "accepted"),
    ("staged", "rejected"),
    ("accepted", "archived"),
    ("rejected", "accepted"),
}


def lifecycle_transition(
    conn,
    obs_id: int,
    new_state: str,
    reason: str = None,
    decided_by: str = "auto",
) -> bool:
    """Transition an observation's lifecycle state and log the decision.

    Valid transitions: staged→accepted, staged→rejected, accepted→archived, rejected→accepted.
    Returns True if transition succeeded.
    """
    if new_state not in _VALID_LIFECYCLE:
        return False

    row = conn.execute(
        "SELECT lifecycle FROM observations WHERE id = ?", (obs_id,)
    ).fetchone()
    if not row:
        return False

    from_state = row["lifecycle"] or "accepted"

    # Allow same-state no-op (e.g. already accepted)
    if from_state == new_state:
        return True

    if (from_state, new_state) not in _TRANSITIONS:
        return False

    now_iso = datetime.now(timezone.utc).isoformat()
    now_epoch = int(datetime.now(timezone.utc).timestamp())

    conn.execute(
        "UPDATE observations SET lifecycle = ? WHERE id = ?",
        (new_state, obs_id),
    )
    conn.execute(
        "INSERT INTO decision_log (observation_id, from_state, to_state, reason, decided_by, decided_at, decided_epoch) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (obs_id, from_state, new_state, reason, decided_by, now_iso, now_epoch),
    )
    conn.commit()
    _append_jsonl(
        {
            "op": "lifecycle",
            "id": obs_id,
            "from": from_state,
            "to": new_state,
            "reason": reason,
            "by": decided_by,
        }
    )
    return True


def get_review_queue(
    conn, status: str = "staged", limit: int = 20, offset: int = 0
) -> list[dict]:
    """Query observations by lifecycle state for review."""
    rows = conn.execute(
        "SELECT id, type, title, narrative, summary, facts, salience, created_at "
        "FROM observations WHERE lifecycle = ? "
        "ORDER BY created_epoch DESC LIMIT ? OFFSET ?",
        (status, limit, offset),
    ).fetchall()
    return [_row_to_dict(r) for r in rows]
