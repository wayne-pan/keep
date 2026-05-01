"""Wake-up Layer — MemPalace-inspired session startup context.

Builds a ~170 token context blob from high-confidence synthesis truths.
Loaded at session start to give Claude immediate project awareness.

L0 Identity (~50 tokens): Top synthesis by confidence — who/what this project is
L1 Critical Facts (~120 tokens): High-confidence truths (>0.7) — key decisions, patterns
"""

from __future__ import annotations

from mem.storage.database import get_db


def generate_wake_up(project: str | None = None, max_tokens: int = 170) -> str:
    """Build a wake-up context blob from synthesis truths.

    Selects top synthesis entries by confidence, trims to fit token budget.
    Rough token estimate: 1 token ≈ 4 chars.
    """
    db = get_db()

    # L0: Identity — top 3 synthesis by confidence (highest first)
    if project:
        rows = db.execute(
            "SELECT topic, truth, confidence FROM synthesis "
            "WHERE topic LIKE ? OR truth LIKE ? "
            "ORDER BY confidence DESC, updated_count DESC LIMIT 3",
            (f"%{project}%", f"%{project}%"),
        ).fetchall()
    else:
        rows = db.execute(
            "SELECT topic, truth, confidence FROM synthesis "
            "ORDER BY confidence DESC, updated_count DESC LIMIT 3",
        ).fetchall()

    if not rows:
        return ""

    # L0: Identity section (~50 tokens)
    l0_lines = []
    l0_budget = 200  # chars
    for r in rows:
        if r["confidence"] < 0.3:
            continue
        line = (
            f"[{r['confidence']:.1f}] {r['topic']}: {_truncate_truth(r['truth'], 60)}"
        )
        l0_lines.append(line)
        l0_budget -= len(line)
        if l0_budget <= 0:
            break

    if not l0_lines:
        return ""

    # L1: Critical facts — additional high-confidence truths (>0.7)
    l1_lines = []
    l1_budget = 480  # chars (~120 tokens)
    existing_topics = {r["topic"] for r in rows}

    # Get more truths beyond L0
    if project:
        extra = db.execute(
            "SELECT topic, truth, confidence FROM synthesis "
            "WHERE confidence > 0.7 AND topic NOT LIKE ? "
            "ORDER BY confidence DESC, updated_count DESC LIMIT 8",
            (f"%{project}%",),
        ).fetchall()
    else:
        extra = db.execute(
            "SELECT topic, truth, confidence FROM synthesis "
            "WHERE confidence > 0.7 "
            "ORDER BY confidence DESC, updated_count DESC LIMIT 8",
        ).fetchall()

    for r in extra:
        if r["topic"] in existing_topics:
            continue
        line = f"- {r['topic']}: {_truncate_truth(r['truth'], 50)}"
        l1_lines.append(line)
        l1_budget -= len(line)
        existing_topics.add(r["topic"])
        if l1_budget <= 0:
            break

    # L2: Recent high-salience observations (EverOS-inspired: active context)
    l2_lines = []
    l2_budget = 200  # chars
    recent_obs = db.execute(
        "SELECT id, type, title, salience FROM observations "
        "WHERE salience >= 0.7 "
        "ORDER BY created_epoch DESC LIMIT 5"
    ).fetchall()
    for obs in recent_obs:
        line = f"- [#{obs['id']}] {obs['title'][:60]}"
        l2_lines.append(line)
        l2_budget -= len(line)
        if l2_budget <= 0:
            break

    # L3: Last session checkpoint (cross-session continuity)
    l3_lines = []
    l3_budget = 160  # chars
    checkpoint = db.execute(
        "SELECT id, title, narrative FROM observations "
        "WHERE type = 'session-checkpoint' "
        "ORDER BY created_epoch DESC LIMIT 1"
    ).fetchone()
    if checkpoint:
        import json as _json

        try:
            data = _json.loads(checkpoint["narrative"])
            branch = data.get("git_branch", "unknown")
            dirty = data.get("dirty_files", 0)
            mods = data.get("modified_files", "")
            mod_short = mods[:80] + ("..." if len(mods) > 80 else "")
            l3_lines.append(f"Branch: {branch} ({dirty} dirty)")
            if mod_short:
                l3_lines.append(f"Modified: {mod_short}")
        except (_json.JSONDecodeError, TypeError):
            l3_lines.append(f"[#{checkpoint['id']}] {checkpoint['title'][:60]}")

    # Assemble wake-up blob
    parts = ["## Memory Wake-Up"]
    if l0_lines:
        parts.append("### Identity")
        parts.extend(l0_lines)
    if l1_lines:
        parts.append("### Key Facts")
        parts.extend(l1_lines)
    if l2_lines:
        parts.append("### Recent (high importance)")
        parts.extend(l2_lines)
    if l3_lines:
        parts.append("### Last Session")
        parts.extend(l3_lines)

    blob = "\n".join(parts)

    # Hard truncate to token budget
    max_chars = max_tokens * 4
    if len(blob) > max_chars:
        blob = blob[: max_chars - 3] + "..."

    return blob


def _truncate_truth(truth: str | None, max_len: int) -> str:
    """Truncate truth text to max_len, breaking at sentence boundary."""
    if not truth:
        return ""
    # Take first line or first sentence
    first = truth.split("\n")[0]
    if len(first) <= max_len:
        return first
    # Break at last period/question mark within limit
    truncated = first[:max_len]
    for sep in (". ", "? ", "! "):
        idx = truncated.rfind(sep)
        if idx > max_len // 2:
            return truncated[: idx + 1]
    return truncated[: max_len - 3] + "..."
