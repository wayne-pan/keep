"""Multi-repo registry — tracks all indexed projects.

Global registry at ~/.claude/codedb-registry.json.
One MCP server serves all registered repos.
"""

import json
import time
from pathlib import Path


REGISTRY_PATH = Path.home() / ".claude" / "codedb-registry.json"


def _load() -> dict:
    """Load registry from disk."""
    try:
        with open(REGISTRY_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {"projects": {}}


def _save(data: dict):
    """Persist registry to disk."""
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(REGISTRY_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def register(project_root: str, stats: dict | None = None):
    """Add or update a project in the registry."""
    data = _load()
    key = str(Path(project_root).resolve())
    existing = data["projects"].get(key, {})
    data["projects"][key] = {
        "registered_at": existing.get(
            "registered_at", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        ),
        "last_indexed": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "file_count": (stats or {}).get("file_count", 0),
        "symbol_count": (stats or {}).get("symbol_count", 0),
    }
    _save(data)


def unregister(project_root: str) -> bool:
    """Remove a project from the registry."""
    data = _load()
    key = str(Path(project_root).resolve())
    if key in data["projects"]:
        del data["projects"][key]
        _save(data)
        return True
    return False


def list_projects() -> list[dict]:
    """Return all registered projects with metadata."""
    data = _load()
    results = []
    for path, info in data["projects"].items():
        results.append({"path": path, **info})
    return sorted(results, key=lambda p: p.get("last_indexed", ""), reverse=True)


def find_project(path: str) -> dict | None:
    """Find a registered project by exact or prefix match."""
    data = _load()
    resolved = str(Path(path).resolve())
    # Exact match
    if resolved in data["projects"]:
        return {"path": resolved, **data["projects"][resolved]}
    # Prefix match (path is inside a registered project)
    for reg_path, info in data["projects"].items():
        if resolved.startswith(reg_path + "/"):
            return {"path": reg_path, **info}
    return None


def get_stats() -> dict:
    """Aggregate stats across all registered projects."""
    data = _load()
    total_files = sum(p.get("file_count", 0) for p in data["projects"].values())
    total_syms = sum(p.get("symbol_count", 0) for p in data["projects"].values())
    return {
        "project_count": len(data["projects"]),
        "total_files": total_files,
        "total_symbols": total_syms,
    }
