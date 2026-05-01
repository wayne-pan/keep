#!/usr/bin/env python3
"""mind — Self-contained memory MCP server.

Replaces claude-mem with built-in memory + gbrain patterns.
Zero external deps for core. Single dep: pip install mcp.
"""

import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mcp.server.fastmcp import FastMCP
from mem.tools.memory_tools import register_memory_tools
from mem.tools.code_tools import register_code_tools
from mem.tools.admin_tools import register_admin_tools
from mem.tools.web_tools import register_web_tools
from mem.codeparse.registry import list_projects as reg_list, find_project as reg_find

mcp = FastMCP("mind")

register_memory_tools(mcp)
register_code_tools(mcp)
register_admin_tools(mcp)
register_web_tools(mcp)


# ── MCP Resources: codedb:// URIs ──


@mcp.resource("codedb://projects")
def resource_projects() -> str:
    """List all registered indexed projects."""
    import json

    projects = reg_list()
    if not projects:
        return "No projects registered."
    return json.dumps({"projects": projects}, indent=2)


@mcp.resource("codedb://project/{name}/summary")
def resource_project_summary(name: str) -> str:
    """Get project summary by directory name."""
    import json
    from pathlib import Path

    projects = reg_list()
    for p in projects:
        if Path(p["path"]).name == name:
            from mem.codeparse.indexer import ProjectIndex

            idx = ProjectIndex(p["path"])
            stats = idx.get_stats()
            data = idx.get_symbols()
            return json.dumps(
                {
                    "path": p["path"],
                    "file_count": stats.get("file_count", 0),
                    "symbol_count": stats.get("symbol_count", 0),
                    "last_indexed": data.get("indexed_at"),
                    "registered_at": p.get("registered_at"),
                },
                indent=2,
            )
    return f"Project '{name}' not found in registry."


@mcp.resource("codedb://project/{name}/outline/{file_path}")
def resource_project_outline(name: str, file_path: str) -> str:
    """Get file outline within a project."""
    from pathlib import Path
    from mem.codeparse.parser import extract_symbols

    projects = reg_list()
    for p in projects:
        if Path(p["path"]).name == name:
            full = str(Path(p["path"]) / file_path)
            symbols = extract_symbols(full)
            if not symbols:
                return f"No symbols in {file_path}."
            lines = [f"{file_path} ({len(symbols)} symbols)"]
            for s in symbols:
                lines.append(f"  L{s['line']:>4d}  {s['kind']:<10s}  {s['name']}")
            return "\n".join(lines)
    return f"Project '{name}' not found."


@mcp.resource("memory://review-queue")
def resource_review_queue() -> str:
    """Staged observations rendered as markdown with accept/reject hints."""
    import json
    from mem.storage.database import get_db
    from mem.storage.observations import get_review_queue

    db = get_db()
    queue = get_review_queue(db, status="staged", limit=20)
    if not queue:
        return "No staged observations pending review."

    lines = [f"# Review Queue ({len(queue)} staged)\n"]
    for i, obs in enumerate(queue, 1):
        summary = obs.get("summary") or obs.get("title", "")
        lines.append(f"### {i}. [{obs.get('type', '?')}] #{obs['id']} {summary[:80]}")
        if obs.get("narrative"):
            lines.append(f"{obs['narrative'][:200]}")
        try:
            facts = json.loads(obs.get("facts", "[]"))
            for f in facts[:3]:
                lines.append(f"- {f}")
        except (json.JSONDecodeError, TypeError):
            pass
        lines.append(
            f"Accept: `lifecycle_transition(id={obs['id']}, new_state='accepted')` | "
            f"Reject: `lifecycle_transition(id={obs['id']}, new_state='rejected')`"
        )
        lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    mcp.run()
