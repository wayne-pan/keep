"""Harness utilities: output truncation, externalization, and input validation.

Layer 2 (Tools): Token budget truncation prevents context window bloat.
  Oversized outputs are externalized to disk with a compact reference returned.
Layer 3 (Contracts): Input validation rejects malformed data at boundaries.
"""

import hashlib
import json
import time
from pathlib import Path

MAX_TOOL_CHARS = 12000  # ~3000 tokens, ~1-2% of typical context window

# Externalization directory
_EXTERNAL_DIR = Path.home() / ".mind" / "externalized"


def _trim(text: str, max_chars: int = MAX_TOOL_CHARS) -> str:
    """Truncate tool output to prevent context bloat (Harness Layer 2).

    If output exceeds max_chars, the full content is externalized to a file
    and a compact reference with head summary is returned instead.
    The externalized content can be recovered via _read_externalized().
    """
    if not isinstance(text, str):
        return str(text) if text is not None else ""
    if len(text) <= max_chars:
        return text

    # Externalize: write full content to disk
    ref = _externalize(text)
    if ref is None:
        # Fallback to simple truncation if externalization fails
        return text[:max_chars] + "\n...[truncated]"

    # Return compact reference: head summary + tail hint + ref
    head_lines = text[:800].split("\n")
    summary_lines = head_lines[:5]
    tail_hint = text[-100:].strip().split("\n")[-1] if len(text) > 1000 else ""

    parts = [
        "\n".join(summary_lines),
        f"...[{len(text)} chars externalized]",
        f"...ref: {ref}",
    ]
    if tail_hint:
        parts.append(f"...tail: {tail_hint}")
    return "\n".join(parts)


def _externalize(content: str) -> str | None:
    """Write oversized content to disk. Returns ref filename or None on failure."""
    try:
        _EXTERNAL_DIR.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256(content.encode("utf-8")).hexdigest()[:12]
        ts = int(time.time())
        ref = f"{ts}-{digest}.json"
        payload = {
            "content": content,
            "chars": len(content),
            "created_at": ts,
        }
        path = _EXTERNAL_DIR / ref
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        return ref
    except Exception:
        return None


def _read_externalized(ref: str) -> str | None:
    """Recover externalized content by ref filename. Returns content or None."""
    try:
        # Sanitize: only allow alphanumeric+dash+dot filenames
        safe = "".join(c for c in ref if c.isalnum() or c in "-._")
        if safe != ref:
            return None
        path = _EXTERNAL_DIR / ref
        if not path.exists():
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
        return data.get("content")
    except Exception:
        return None


def _validate_input(title: str = None, **required_fields) -> str | None:
    """Validate tool input parameters (Harness Layer 3 — Contracts).

    Returns error message if validation fails, None if OK.
    """
    if not title or not isinstance(title, str) or not title.strip():
        return "Error: title is required and must be a non-empty string."
    for field_name, value in required_fields.items():
        if value is not None and not isinstance(value, (str, list, dict)):
            return f"Error: {field_name} must be str, list, or dict, got {type(value).__name__}."
    return None
