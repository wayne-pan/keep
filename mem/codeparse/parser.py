"""Regex-based symbol extraction for py, ts, js, sh, go, rs."""

import os
import re
from typing import Optional

# ---------------------------------------------------------------------------
# Language detection
# ---------------------------------------------------------------------------

_EXTENSION_MAP = {
    ".py": "py",
    ".ts": "ts",
    ".tsx": "ts",
    ".js": "js",
    ".jsx": "js",
    ".sh": "sh",
    ".bash": "sh",
    ".go": "go",
    ".rs": "rs",
}


def detect_language(file_path: str) -> str:
    """Return language key by file extension, or empty string if unknown."""
    _, ext = os.path.splitext(file_path)
    return _EXTENSION_MAP.get(ext.lower(), "")


# ---------------------------------------------------------------------------
# Per-language regex patterns
# ---------------------------------------------------------------------------

# Each entry: (compiled_re, kind_label)
# Named groups: name, signature (optional)

# _PATTERNS: (compiled_re, kind_label)
# Two kinds of patterns per language:
#   - _SINGLE: match entirely on one line
#   - _MULTI:  may span multiple lines (e.g. Python def with type hints)
# Both use named groups: name, signature

_PY_SINGLE = [
    (re.compile(
        r"^(?:(?:async)\s+)?def\s+(?P<name>\w+)\s*(?P<signature>\([^)]*\))\s*(?:->.*?)?:"
    ), "function"),
    (re.compile(
        r"^class\s+(?P<name>\w+)(?P<signature>\([^)]*\))?\s*:"
    ), "class"),
]

# Multi-line Python: def name( that may not close on the same line
_PY_MULTI = re.compile(
    r"^(?:(?:async)\s+)?def\s+(?P<name>\w+)\s*\($"
)

_SINGLE_PATTERNS: dict[str, list[tuple[re.Pattern, str]]] = {
    "py": _PY_SINGLE,
    "ts": [
        (re.compile(
            r"^(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+(?P<name>\w+)\s*(?P<signature>\([^)]*\))"
        ), "function"),
        (re.compile(
            r"^(?:export\s+)?(?:const|let|var)\s+(?P<name>\w+)\s*(?P<signature>=.+)"
        ), "variable"),
        (re.compile(
            r"^(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+(?P<name>\w+)"
        ), "class"),
        (re.compile(
            r"^(?:export\s+)?(?:default\s+)?interface\s+(?P<name>\w+)"
        ), "interface"),
        (re.compile(
            r"^(?:export\s+)?type\s+(?P<name>\w+)\s*(?P<signature>=.+)"
        ), "type"),
    ],
    "sh": [
        (re.compile(
            r"^function\s+(?P<name>\w+)\s*\(\)"
        ), "function"),
        (re.compile(
            r"^(?P<name>\w+)\s*\(\)"
        ), "function"),
    ],
    "go": [
        (re.compile(
            r"^func\s+(?:\([^)]*\)\s+)?(?P<name>\w+)\s*(?P<signature>\([^)]*\))"
        ), "function"),
        (re.compile(
            r"^type\s+(?P<name>\w+)\s+struct"
        ), "struct"),
        (re.compile(
            r"^type\s+(?P<name>\w+)\s+interface"
        ), "interface"),
    ],
    "rs": [
        (re.compile(
            r"^(?:pub\s+)?(?:async\s+)?fn\s+(?P<name>\w+)\s*(?P<signature>\([^)]*\))"
        ), "function"),
        (re.compile(
            r"^(?:pub\s+)?struct\s+(?P<name>\w+)"
        ), "struct"),
        (re.compile(
            r"^(?:pub\s+)?enum\s+(?P<name>\w+)"
        ), "enum"),
        (re.compile(
            r"^(?:pub\s+)?trait\s+(?P<name>\w+)"
        ), "trait"),
        (re.compile(
            r"^(?:pub\s+)?impl\s+(?:(?:\w+)\s+for\s+)?(?P<name>\w+)"
        ), "impl"),
    ],
}

# js reuses ts patterns
_SINGLE_PATTERNS["js"] = _SINGLE_PATTERNS["ts"]


# ---------------------------------------------------------------------------
# extract_symbols
# ---------------------------------------------------------------------------

def _join_multiline_sig(lines: list[str], start_idx: int) -> str:
    """Join a multi-line Python signature starting with 'def name('.

    Reads forward until an unindented closing paren is found, then
    returns the joined signature text (without the 'def name' prefix).
    """
    parts: list[str] = []
    depth = 0
    for i in range(start_idx, len(lines)):
        raw = lines[i].rstrip("\n")
        parts.append(raw)
        depth += raw.count("(") - raw.count(")")
        if depth <= 0:
            break
    joined = " ".join(p.strip() for p in parts)
    # Extract just the signature portion after 'def name'
    m = re.match(r"^(?:async\s+)?def\s+\w+\s*(?P<sig>.*)", joined)
    return m.group("sig") if m else ""


def extract_symbols(file_path: str) -> list[dict]:
    """Return [{name, kind, line, signature}] for all symbols found."""
    lang = detect_language(file_path)
    if not lang:
        return []

    patterns = _SINGLE_PATTERNS.get(lang, [])
    if not patterns:
        return []

    symbols: list[dict] = []
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as fh:
            all_lines = fh.readlines()
    except (OSError, UnicodeDecodeError):
        return []

    lineno = 0
    while lineno < len(all_lines):
        stripped = all_lines[lineno].rstrip("\n")

        # Check single-line patterns first
        matched = False
        for regex, kind in patterns:
            m = regex.match(stripped)
            if m:
                sig = m.groupdict().get("signature") or ""
                symbols.append({
                    "name": m.group("name"),
                    "kind": kind,
                    "line": lineno + 1,
                    "signature": sig,
                })
                matched = True
                break

        # For Python: check multi-line def (e.g. "def name(" at line end)
        if not matched and lang == "py":
            m_multi = _PY_MULTI.match(stripped)
            if m_multi:
                sig = _join_multiline_sig(all_lines, lineno)
                symbols.append({
                    "name": m_multi.group("name"),
                    "kind": "function",
                    "line": lineno + 1,
                    "signature": sig,
                })

        lineno += 1

    return symbols


# ---------------------------------------------------------------------------
# search_symbols
# ---------------------------------------------------------------------------

def _score_symbol(name: str, query: str) -> int:
    """Return relevance score. 0 means no match."""
    q = query.lower()
    n = name.lower()
    if n == q:
        return 10
    if n.startswith(q):
        return 3 + (5 if q in n else 0)
    if q in n:
        return 5
    return 0


def search_symbols(
    query: str,
    path: str = ".",
    max_results: int = 20,
    file_pattern: Optional[str] = None,
) -> list[dict]:
    """Walk directory, extract and score symbols. Return top results sorted."""
    results: list[dict] = []

    for root, _dirs, files in os.walk(path):
        # skip hidden / vcs dirs
        _dirs[:] = [d for d in _dirs if not d.startswith(".")]
        for fname in files:
            fpath = os.path.join(root, fname)
            if file_pattern and file_pattern not in fname:
                continue
            lang = detect_language(fpath)
            if not lang:
                continue
            for sym in extract_symbols(fpath):
                score = _score_symbol(sym["name"], query)
                if score > 0:
                    results.append({
                        "name": sym["name"],
                        "kind": sym["kind"],
                        "file": fpath,
                        "line": sym["line"],
                        "signature": sym["signature"],
                        "score": score,
                    })

    results.sort(key=lambda r: r["score"], reverse=True)
    return results[:max_results]


# ---------------------------------------------------------------------------
# unfold_symbol
# ---------------------------------------------------------------------------

def _read_lines(file_path: str) -> list[str]:
    with open(file_path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.readlines()


def _unfold_python(lines: list[str], start_idx: int) -> str:
    """Collect lines at same or greater indent level starting from start_idx."""
    first_line = lines[start_idx].rstrip("\n")
    if not first_line:
        return first_line

    # measure indent of the definition line
    leading = len(first_line) - len(first_line.lstrip())
    collected = [first_line]

    for i in range(start_idx + 1, len(lines)):
        raw = lines[i]
        stripped = raw.rstrip("\n")

        # blank lines are included
        if stripped.strip() == "":
            collected.append(stripped)
            continue

        current_indent = len(stripped) - len(stripped.lstrip())
        if current_indent <= leading and stripped.strip():
            break
        collected.append(stripped)

    return "\n".join(collected)


def _unfold_brace(lines: list[str], start_idx: int) -> str:
    """Brace-counting body extraction (ts, js, go, rs)."""
    collected: list[str] = []
    depth = 0
    started = False

    for i in range(start_idx, len(lines)):
        raw = lines[i].rstrip("\n")
        collected.append(raw)
        for ch in raw:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
        if started and depth <= 0:
            break

    return "\n".join(collected)


def _unfold_shell(lines: list[str], start_idx: int) -> str:
    """Read until next function definition or EOF."""
    collected = [lines[start_idx].rstrip("\n")]
    func_re = re.compile(r"^(?:function\s+\w+\s*\(\)|\w+\s*\(\))")

    for i in range(start_idx + 1, len(lines)):
        raw = lines[i]
        stripped = raw.rstrip("\n")
        if func_re.match(stripped):
            break
        collected.append(stripped)

    return "\n".join(collected)


_UNFOLD_STRATEGY = {
    "py": _unfold_python,
    "ts": _unfold_brace,
    "js": _unfold_brace,
    "go": _unfold_brace,
    "rs": _unfold_brace,
    "sh": _unfold_shell,
}


def unfold_symbol(file_path: str, symbol_name: str) -> Optional[str]:
    """Find symbol and return its full body text, or None."""
    lang = detect_language(file_path)
    if not lang:
        return None

    symbols = extract_symbols(file_path)
    target = None
    for sym in symbols:
        if sym["name"] == symbol_name:
            target = sym
            break
    if target is None:
        return None

    try:
        lines = _read_lines(file_path)
    except OSError:
        return None

    start_idx = target["line"] - 1  # 0-based index
    if start_idx >= len(lines):
        return None

    strategy = _UNFOLD_STRATEGY.get(lang)
    if strategy is None:
        return None

    return strategy(lines, start_idx)
