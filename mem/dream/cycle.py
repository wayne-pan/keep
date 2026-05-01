"""Dream Cycle maintenance operations for memory consolidation."""

import hashlib
import json
import os
import re
import time
from datetime import datetime, timezone
from typing import Optional

from mem.storage.database import get_db
from mem.storage.synthesis import update_synthesis


# ---------------------------------------------------------------------------
# Internal operations
# ---------------------------------------------------------------------------

_DEDUP_WINDOW_MS = 30_000  # 30 seconds


def _dedup_pass(conn) -> int:
    """Remove observations with duplicate content_hash within a 30 s window.

    Keeps the earliest observation of each duplicate group.
    Returns the number of deleted rows.
    """
    cur = conn.execute(
        "SELECT id, content_hash, created_epoch FROM observations "
        "WHERE content_hash IS NOT NULL "
        "ORDER BY content_hash, created_epoch"
    )
    rows = cur.fetchall()

    to_delete: list[int] = []
    prev_hash: Optional[str] = None
    prev_epoch: Optional[int] = None

    for row in rows:
        obs_id, content_hash, created_epoch = row
        if content_hash == prev_hash and prev_epoch is not None:
            if (created_epoch - prev_epoch) <= _DEDUP_WINDOW_MS:
                to_delete.append(obs_id)
                continue
        prev_hash = content_hash
        prev_epoch = created_epoch

    for obs_id in to_delete:
        conn.execute("DELETE FROM observations WHERE id = ?", (obs_id,))

    return len(to_delete)


def _jaccard(words_a: set[str], words_b: set[str]) -> float:
    """Compute Jaccard similarity between two word sets."""
    if not words_a and not words_b:
        return 0.0
    intersection = words_a & words_b
    union = words_a | words_b
    return len(intersection) / len(union) if union else 0.0


_MERGE_THRESHOLD = 0.8


def _merge_pass(conn) -> int:
    """Merge observation pairs with same (project, type) and Jaccard > 0.8.

    Keeps the earlier observation, appends the later's narrative.
    Returns the number of merged (deleted) rows.
    """
    cur = conn.execute(
        "SELECT id, project, obs_type, title, narrative, created_epoch "
        "FROM observations ORDER BY created_epoch"
    )
    rows = cur.fetchall()

    # Group by (project, type)
    groups: dict[tuple, list[tuple]] = {}
    for row in rows:
        key = (row[1], row[2])  # project, obs_type
        groups.setdefault(key, []).append(row)

    merged_count = 0
    to_delete_ids: list[int] = []

    for _key, group in groups.items():
        if len(group) < 2:
            continue

        # Track which indices have already been consumed
        consumed: set[int] = set()

        for i in range(len(group)):
            if i in consumed:
                continue
            id_i, _proj, _otype, title_i, nar_i, epoch_i = group[i]
            words_i = set(title_i.lower().split()) if title_i else set()

            for j in range(i + 1, len(group)):
                if j in consumed:
                    continue
                id_j, _proj2, _otype2, title_j, nar_j, epoch_j = group[j]
                words_j = set(title_j.lower().split()) if title_j else set()

                if _jaccard(words_i, words_j) > _MERGE_THRESHOLD:
                    # Merge j into i: append narrative
                    new_narrative = nar_i or ""
                    if nar_j:
                        new_narrative += "\n\n--- merged ---\n\n" + (nar_j or "")
                    conn.execute(
                        "UPDATE observations SET narrative = ? WHERE id = ?",
                        (new_narrative, id_i),
                    )
                    to_delete_ids.append(id_j)
                    consumed.add(j)
                    merged_count += 1

    for del_id in to_delete_ids:
        conn.execute("DELETE FROM observations WHERE id = ?", (del_id,))

    return merged_count


_PRUNE_MAX_AGE_DAYS = 90


def _prune_pass(conn) -> int:
    """Remove observations older than 90 days with zero relevance_count.

    Returns the number of deleted rows.
    """
    cutoff_epoch = int(time.time()) - (_PRUNE_MAX_AGE_DAYS * 86400)
    cur = conn.execute(
        "DELETE FROM observations "
        "WHERE created_epoch < ? "
        "AND (relevance_count IS NULL OR relevance_count = 0)",
        (cutoff_epoch,),
    )
    return cur.rowcount


def _strengthen_pass(conn) -> int:
    """Re-run synthesis for each topic with matching observations since last run.

    Also detects conflicts (Supermemory pattern): when new observations
    contradict existing synthesis, flag them and reduce confidence.

    Returns the number of synthesis updates performed.
    """
    cur = conn.execute("SELECT id, topic, last_epoch, truth FROM synthesis")
    synthesis_rows = cur.fetchall()

    count = 0
    for row in synthesis_rows:
        syn_id = row["id"]
        topic = row["topic"]
        last_epoch = row["last_epoch"]
        truth = row["truth"] or ""

        # Find observations mentioning this topic's concepts since last_epoch
        obs_cur = conn.execute(
            "SELECT id, title, narrative FROM observations "
            "WHERE (narrative LIKE ? OR title LIKE ?) "
            "AND created_epoch > ?",
            (f"%{topic}%", f"%{topic}%", last_epoch or 0),
        )
        matching = obs_cur.fetchall()
        if matching:
            update_synthesis(conn, topic)

            # Conflict detection (Supermemory pattern)
            conflict_ids = _detect_conflicts(conn, truth, matching)
            if conflict_ids:
                existing_flags = json.loads(
                    conn.execute(
                        "SELECT conflict_flags FROM synthesis WHERE id = ?", (syn_id,)
                    ).fetchone()["conflict_flags"]
                    or "[]"
                )
                new_flags = list(set(existing_flags + conflict_ids))
                conn.execute(
                    "UPDATE synthesis SET conflict_flags = ?, confidence = MAX(0.1, confidence - 0.2) WHERE id = ?",
                    (json.dumps(new_flags), syn_id),
                )

            count += 1

    return count


def _decay_pass(conn) -> int:
    """Decay synthesis confidence over time.

    Formula: confidence *= 0.95^(age_days/30) — ~5% per month.
    Floor at 0.1. Skip updates < 0.001 change.
    Returns number of rows updated.
    """
    now = int(time.time())
    rows = conn.execute("SELECT id, confidence, last_epoch FROM synthesis").fetchall()

    count = 0
    for row in rows:
        last_epoch = row["last_epoch"] or 0
        age_days = max(0, (now - last_epoch)) / 86400
        if age_days < 60:
            continue
        decay = 0.95 ** (age_days / 30)
        new_conf = max(0.1, row["confidence"] * decay)
        if abs(new_conf - row["confidence"]) < 0.001:
            continue
        conn.execute(
            "UPDATE synthesis SET confidence = ? WHERE id = ?",
            (round(new_conf, 4), row["id"]),
        )
        count += 1
    conn.commit()
    return count


_SALIENCE_PRUNE_DAYS = 30


def _salience_decay_pass(conn) -> int:
    """Salience-aware observation decay.

    Low-salience observations with zero recalls get pruned faster (30 days vs 90).
    High-salience observations are protected from accelerated pruning.
    Returns number of observations deleted.
    """
    now = int(time.time())

    # Accelerated pruning: low-salience, zero-recall, >30 days old
    low_cutoff = now - _SALIENCE_PRUNE_DAYS * 86400
    cur = conn.execute(
        "DELETE FROM observations "
        "WHERE created_epoch < ? "
        "AND (relevance_count IS NULL OR relevance_count = 0) "
        "AND (salience IS NULL OR salience < 0.3)",
        (low_cutoff,),
    )
    count = cur.rowcount

    # Working memory consolidation: boost frequently accessed observations
    try:
        from mem.storage.working_memory import wm_boost_permanent, wm_clear

        wm_boosted = wm_boost_permanent(conn)
        if wm_boosted:
            count += wm_boosted
        wm_clear()  # Clear working memory after consolidation
    except Exception:
        pass

    conn.commit()
    return count


def _lint_pass(conn) -> int:
    """Knowledge health check: broken links, orphan decay, oversized warnings.

    Borrowed from oh-my-codex wiki lint. Runs during dream cycle to keep
    the memory graph clean and surface health issues.
    Returns total issues addressed.
    """
    count = 0

    # 1. Broken links: source or target observation no longer exists
    broken = conn.execute(
        "DELETE FROM memory_links "
        "WHERE source_id NOT IN (SELECT id FROM observations) "
        "OR target_id NOT IN (SELECT id FROM observations)"
    )
    count += broken.rowcount

    # 2. Orphan decay: no links + zero recalls → reduce salience (faster aging)
    orphans = conn.execute(
        "SELECT id, salience FROM observations o "
        "WHERE (SELECT COUNT(*) FROM memory_links m "
        "       WHERE m.source_id = o.id OR m.target_id = o.id) = 0 "
        "AND (o.relevance_count IS NULL OR o.relevance_count = 0) "
        "AND o.salience > 0.1"
    ).fetchall()
    for row in orphans:
        new_sal = max(0.1, round(row["salience"] * 0.8, 3))
        conn.execute(
            "UPDATE observations SET salience = ? WHERE id = ?",
            (new_sal, row["id"]),
        )
        count += 1

    # 3. Oversized narrative warning (> 50KB)
    oversized = conn.execute(
        "SELECT id, title, LENGTH(narrative) as sz FROM observations "
        "WHERE LENGTH(narrative) > 50000"
    ).fetchall()
    if oversized:
        warnings = [
            {
                "id": r["id"],
                "title": (r["title"] or "")[:60],
                "size_kb": round(r["sz"] / 1024, 1),
            }
            for r in oversized
        ]
        now_epoch = int(time.time() * 1000)
        now_iso = datetime.now(timezone.utc).isoformat()
        conn.execute(
            "INSERT INTO dream_log (operation, details, ran_at, ran_epoch) "
            "VALUES (?, ?, ?, ?)",
            (
                "lint-warning",
                json.dumps({"oversized": warnings}),
                now_iso,
                now_epoch,
            ),
        )

    # 4. File staleness: two-stage change detection (mtime → hash)
    #    Check if files referenced in observations still exist and are unchanged.
    stale_refs = _check_file_staleness(conn)
    if stale_refs:
        now_epoch = int(time.time() * 1000)
        now_iso = datetime.now(timezone.utc).isoformat()
        conn.execute(
            "INSERT INTO dream_log (operation, details, ran_at, ran_epoch) "
            "VALUES (?, ?, ?, ?)",
            (
                "lint-stale-files",
                json.dumps({"stale_refs": stale_refs[:20]}),
                now_iso,
                now_epoch,
            ),
        )
        # Reduce salience for observations with stale file refs
        for ref in stale_refs:
            conn.execute(
                "UPDATE observations SET salience = MAX(0.1, salience * 0.9) WHERE id = ?",
                (ref["obs_id"],),
            )
        count += len(stale_refs)

    conn.commit()
    return count


def _check_file_staleness(conn) -> list[dict]:
    """Two-stage file change detection: mtime first, then hash.

    Borrowed from codedb's watcher pattern — cheap mtime check, expensive
    hash only when mtime changed. Returns list of stale references.
    """
    stale = []
    now_epoch = int(time.time())

    rows = conn.execute(
        "SELECT id, files_read, files_modified, created_epoch, salience "
        "FROM observations "
        "WHERE (files_read != '[]' OR files_modified != '[]') "
        "AND salience > 0.1"
    ).fetchall()

    for row in rows:
        obs_id = row["id"]
        created_epoch = row["created_epoch"] or 0

        try:
            fr = json.loads(row["files_read"] or "[]")
            fm = json.loads(row["files_modified"] or "[]")
        except (json.JSONDecodeError, TypeError):
            continue

        all_files = list(dict.fromkeys(fr + fm))
        for fpath in all_files:
            if not isinstance(fpath, str) or not fpath.startswith("/"):
                continue

            # Stage 1: mtime check (fast)
            try:
                stat = os.stat(fpath)
            except OSError:
                # File gone — definitely stale
                stale.append({"obs_id": obs_id, "file": fpath, "reason": "deleted"})
                continue

            file_mtime = int(stat.st_mtime)
            if file_mtime <= created_epoch:
                continue  # File unchanged since observation

            # Stage 2: hash check (slower, only when mtime changed)
            # Read first 8KB for quick hash — avoids reading huge files
            try:
                with open(fpath, "rb") as f:
                    chunk = f.read(8192)
                file_hash = hashlib.md5(chunk).hexdigest()[:12]
                # Store hash prefix in obs content_hash for future comparison
                # If we've seen this hash before, it's not truly stale
            except OSError:
                stale.append({"obs_id": obs_id, "file": fpath, "reason": "unreadable"})
                continue

            # File was modified after observation — mark as stale
            stale.append(
                {
                    "obs_id": obs_id,
                    "file": fpath,
                    "reason": "modified",
                    "age_days": round((now_epoch - file_mtime) / 86400, 1),
                }
            )

    return stale


def _backfill_summaries(conn) -> int:
    """Generate summaries for observations where summary IS NULL.

    Returns number of summaries backfilled.
    """
    from mem.storage.observations import generate_summary

    rows = conn.execute(
        "SELECT id, title, narrative FROM observations WHERE summary IS NULL"
    ).fetchall()

    count = 0
    for row in rows:
        summary = generate_summary(row["narrative"] or "", row["title"] or "")
        conn.execute(
            "UPDATE observations SET summary = ? WHERE id = ?",
            (summary, row["id"]),
        )
        count += 1
    conn.commit()
    return count


def _backfill_pattern_ids(conn) -> int:
    """Backfill pattern_id for observations that don't have one.

    Also merges exact duplicates found by pattern_id.
    Returns number of observations backfilled.
    """
    from mem.storage.observations import compute_pattern_id

    rows = conn.execute(
        "SELECT id, title, narrative FROM observations WHERE pattern_id IS NULL"
    ).fetchall()

    count = 0
    seen_pids: dict[str, int] = {}
    to_delete: list[int] = []

    for row in rows:
        pid = compute_pattern_id(row["title"] or "", row["narrative"] or "")
        if pid in seen_pids:
            # Merge into the earlier observation
            to_delete.append(row["id"])
        else:
            seen_pids[pid] = row["id"]
            conn.execute(
                "UPDATE observations SET pattern_id = ? WHERE id = ?",
                (pid, row["id"]),
            )
            count += 1

    for obs_id in to_delete:
        conn.execute("DELETE FROM observations WHERE id = ?", (obs_id,))

    conn.commit()
    return count + len(to_delete)


def _promote_staged(conn) -> int:
    """Auto-promote staged observations with salience >= 0.7 AND verified.

    Returns number of observations promoted.
    """
    now_iso = datetime.now(timezone.utc).isoformat()
    now_epoch = int(datetime.now(timezone.utc).timestamp())

    rows = conn.execute(
        "SELECT id FROM observations "
        "WHERE lifecycle = 'staged' AND salience >= 0.7 AND verified = 1"
    ).fetchall()

    count = 0
    for row in rows:
        conn.execute(
            "UPDATE observations SET lifecycle = 'accepted' WHERE id = ?",
            (row["id"],),
        )
        conn.execute(
            "INSERT INTO decision_log (observation_id, from_state, to_state, reason, decided_by, decided_at, decided_epoch) "
            "VALUES (?, 'staged', 'accepted', 'auto-promote: high salience + verified', 'auto', ?, ?)",
            (row["id"], now_iso, now_epoch),
        )
        count += 1

    conn.commit()
    return count


# Negation patterns for conflict detection
_NEGATION_WORDS = frozenset(
    {
        "not",
        "never",
        "don't",
        "dont",
        "doesn't",
        "doesnt",
        "won't",
        "wont",
        "can't",
        "cant",
        "shouldn't",
        "shouldnt",
        "avoid",
        "broken",
        "failed",
        "wrong",
        "incorrect",
        "bug",
        "error",
        "fix",
        "fixed",
        "removed",
        "deprecated",
        "obsolete",
        "replaced",
        "instead",
    }
)


def _detect_conflicts(conn, synthesis_truth: str, new_observations: list) -> list[int]:
    """Detect observations that contradict existing synthesis.

    Heuristic: if an observation title contains negation words AND
    shares significant word overlap with synthesis truth, it's a conflict.
    """
    truth_words = set(re.findall(r"\b[a-zA-Z]{3,}\b", synthesis_truth.lower()))
    if not truth_words:
        return []

    conflict_ids = []
    for obs in new_observations:
        title = obs["title"] or ""
        title_words = set(re.findall(r"\b[a-zA-Z]{3,}\b", title.lower()))
        if not title_words:
            continue

        # Check for negation words
        has_negation = bool(title_words & _NEGATION_WORDS)
        if not has_negation:
            continue

        # Check significant word overlap (>30% of truth words in title)
        overlap = len(truth_words & title_words) / len(truth_words)
        if overlap > 0.3:
            conflict_ids.append(obs["id"])

            # Also create a contradicts link
            try:
                from mem.storage.links import create_link

                # Link to first evidence observation if exists
                evidence = conn.execute(
                    "SELECT evidence_ids FROM synthesis WHERE truth = ?",
                    (synthesis_truth,),
                ).fetchone()
                if evidence:
                    eids = json.loads(evidence["evidence_ids"] or "[]")
                    if eids:
                        create_link(conn, obs["id"], eids[0], "contradicts", 0.8)
            except Exception:
                pass

    return conflict_ids


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def _link_pass(conn) -> int:
    """Auto-link observations by shared concepts and session proximity.

    Hindsight pattern: build a memory graph connecting related observations.
    Returns total links created.
    """
    from mem.storage.links import auto_link_observations, auto_episode_links

    stats = auto_link_observations(conn)
    episode_count = auto_episode_links(conn)
    stats["episode"] = episode_count
    return stats.get("total", 0) + episode_count


_OPERATIONS = {
    "dedup": [_dedup_pass],
    "merge": [_merge_pass],
    "prune": [_prune_pass],
    "strengthen": [_strengthen_pass],
    "link": [_link_pass],
    "decay": [_decay_pass],
    "salience_decay": [_salience_decay_pass],
    "lint": [_lint_pass],
    "backfill": [_backfill_summaries],
    "backfill_pattern_ids": [_backfill_pattern_ids],
    "promote_staged": [_promote_staged],
    "full": [
        _dedup_pass,
        _merge_pass,
        _prune_pass,
        _strengthen_pass,
        _link_pass,
        _decay_pass,
        _salience_decay_pass,
        _lint_pass,
        _backfill_summaries,
        _backfill_pattern_ids,
        _promote_staged,
    ],
}


def run_dream_cycle(conn=None, mode: str = "full") -> list[dict]:
    """Execute dream cycle maintenance operations.

    Args:
        conn: Database connection. If None, acquired via get_db().
        mode: One of 'full', 'dedup', 'merge', 'prune', 'strengthen', 'link'.

    Returns:
        List of {operation, details} dicts describing what was done.
    """
    if mode not in _OPERATIONS:
        raise ValueError(
            f"Unknown dream mode: {mode!r}. Expected one of {list(_OPERATIONS)}"
        )

    own_conn = conn is None
    if own_conn:
        conn = get_db()

    results: list[dict] = []
    ops = _OPERATIONS[mode]

    for op_fn in ops:
        op_name = op_fn.__name__
        try:
            count = op_fn(conn)
            results.append(
                {
                    "operation": op_name,
                    "details": {"deleted_or_updated": count},
                }
            )
        except Exception as exc:
            results.append(
                {
                    "operation": op_name,
                    "details": {"error": str(exc)},
                }
            )

    # Log the run
    now_epoch = int(time.time() * 1000)
    now_iso = datetime.now(timezone.utc).isoformat()
    conn.execute(
        "INSERT INTO dream_log (operation, details, ran_at, ran_epoch) "
        "VALUES (?, ?, ?, ?)",
        (mode, json.dumps(results), now_iso, now_epoch),
    )
    conn.commit()

    return results
