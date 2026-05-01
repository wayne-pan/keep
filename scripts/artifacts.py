#!/usr/bin/env python3
"""
artifacts.py — Context artifact scanner.

Extracts DB schemas, API endpoints, and infrastructure configs from a
codebase so AI assistants can reason about databases, APIs, and infra
without reading every file.

Usage:
  artifacts.py [path]          # All artifacts as JSON
  artifacts.py --sql [path]    # SQL schemas only
  artifacts.py --api [path]    # API endpoints only
  artifacts.py --infra [path]  # Infrastructure configs only
  artifacts.py --mermaid       # Output relationships as Mermaid diagram
"""

import json
import os
import re
import sys


SKIP_DIRS = frozenset(
    [
        ".git",
        "node_modules",
        "__pycache__",
        ".venv",
        "venv",
        "dist",
        "build",
        ".tox",
        ".mypy_cache",
        ".pytest_cache",
        "vendor",
        "target",
        ".gradle",
        ".idea",
        ".vscode",
        ".codedb",
        ".mind",
    ]
)


# ── SQL Schema Extraction ────────────────────────────────────

_TABLE_RE = re.compile(
    r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:"?(\w+)"?|`(\w+)`)\s*\(',
    re.IGNORECASE,
)
_INDEX_RE = re.compile(
    r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s+ON\s+(\w+)",
    re.IGNORECASE,
)
_COL_RE = re.compile(
    r'(?:"?(\w+)"?|`(\w+)`)\s+[\w]+(?:\([^)]+\))?(?:\s+\w+)*',
)


def scan_sql(root):
    """Extract SQL table definitions from .sql files."""
    tables = []
    indexes = []

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")
        ]
        for fname in filenames:
            if not fname.endswith(".sql"):
                continue
            filepath = os.path.join(dirpath, fname)
            try:
                with open(filepath) as f:
                    content = f.read()
            except (UnicodeDecodeError, IOError):
                continue

            rel = os.path.relpath(filepath, root)

            for m in _TABLE_RE.finditer(content):
                tname = m.group(1) or m.group(2)
                # Extract column definitions between parentheses
                start = m.end()
                depth, cols = 0, []
                for ch_idx, ch in enumerate(content[start:], start):
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            body = content[m.end() : ch_idx]
                            for line in body.split(","):
                                line = line.strip()
                                if not line or line.upper().startswith(
                                    (
                                        "PRIMARY",
                                        "UNIQUE",
                                        "INDEX",
                                        "FOREIGN",
                                        "CONSTRAINT",
                                        "CHECK",
                                        "EXCLUDE",
                                    )
                                ):
                                    continue
                                cm = re.match(r'(?:"?(\w+)"?|`(\w+)`)', line)
                                if cm:
                                    cols.append(cm.group(1) or cm.group(2))
                            break
                tables.append(
                    {
                        "name": tname,
                        "columns": cols,
                        "file": rel,
                        "line": content[: m.start()].count("\n") + 1,
                    }
                )

            for m in _INDEX_RE.finditer(content):
                indexes.append(
                    {
                        "name": m.group(1),
                        "table": m.group(2),
                        "file": rel,
                        "line": content[: m.start()].count("\n") + 1,
                    }
                )

    return {"tables": tables, "indexes": indexes}


# ── API Route Extraction ─────────────────────────────────────

# Python: @app.route, @app.get, @router.get, @api_view, app.add_url_rule
_PY_ROUTE_RE = re.compile(
    r"@(?:app|router|bp|blueprint|api|ns)\s*"
    r"(?:"
    r'\.route\(\s*["\']([^"\']+)["\']\s*(?:,\s*methods\s*=\s*\[([^\]]+)\])?'
    r"|\.((?:get|post|put|delete|patch|head|options))\(\s*[\"']([^\"']+)[\"']"
    r"|\.add_url_rule\(\s*[\"']([^\"']+)[\"']\s*(?:,\s*endpoint\s*=\s*(\w+))?\s*(?:,\s*view_func\s*=\s*(\w+))?"
    r")",
)
_PY_FLASK_METHODS = re.compile(r"(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)")

# JS/TS: app.get('/path', ...), router.post('/path', ...)
_JS_ROUTE_RE = re.compile(
    r'(?:app|router|server|Route)\s*\.\s*(get|post|put|delete|patch|all|use)\s*\(\s*["\']([^"\']+)["\']'
)


def scan_api(root):
    """Extract API route definitions from Python and JS/TS files."""
    routes = []

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")
        ]
        for fname in filenames:
            ext = os.path.splitext(fname)[1]
            if ext not in (".py", ".js", ".ts", ".jsx", ".tsx"):
                continue
            filepath = os.path.join(dirpath, fname)
            try:
                with open(filepath) as f:
                    lines = f.readlines()
            except (UnicodeDecodeError, IOError):
                continue

            rel = os.path.relpath(filepath, root)

            for i, line in enumerate(lines):
                stripped = line.strip()

                # Python routes
                if ext == ".py":
                    m = _PY_ROUTE_RE.search(stripped)
                    if m:
                        if m.group(1):  # .route() form
                            path = m.group(1)
                            methods_str = m.group(2) or ""
                            methods = [
                                m.strip().strip("\"'")
                                for m in _PY_FLASK_METHODS.findall(methods_str)
                            ]
                            if not methods:
                                methods = ["GET"]
                        elif m.group(3):  # .get()/.post() form
                            methods = [m.group(3).upper()]
                            path = m.group(4)
                        elif m.group(5):  # add_url_rule
                            path = m.group(5)
                            methods = ["GET"]
                        else:
                            continue
                        for method in methods:
                            routes.append(
                                {
                                    "method": method,
                                    "path": path,
                                    "file": rel,
                                    "line": i + 1,
                                }
                            )

                # JS/TS routes
                elif ext in (".js", ".ts", ".jsx", ".tsx"):
                    m = _JS_ROUTE_RE.search(stripped)
                    if m:
                        method = (
                            m.group(1).upper() if m.group(1) != "use" else "MIDDLEWARE"
                        )
                        routes.append(
                            {
                                "method": method,
                                "path": m.group(2),
                                "file": rel,
                                "line": i + 1,
                            }
                        )

    return {"routes": routes}


# ── Infrastructure Config Extraction ──────────────────────────


def scan_infra(root):
    """Extract infrastructure configs: Dockerfile, docker-compose, .env."""
    result = {"dockerfiles": [], "compose": [], "env_vars": []}

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")
        ]

        for fname in filenames:
            filepath = os.path.join(dirpath, fname)
            rel = os.path.relpath(filepath, root)

            # Dockerfile
            if fname in (
                "Dockerfile",
                "Dockerfile.prod",
                "Dockerfile.dev",
                "Dockerfile.test",
            ):
                result["dockerfiles"].append(_parse_dockerfile(filepath, rel))

            # docker-compose
            if fname.startswith("docker-compose") and fname.endswith((".yml", ".yaml")):
                result["compose"].append(_parse_compose(filepath, rel))

            # .env files (variable names only — never expose values)
            if fname.startswith(".env") and not fname.endswith(
                (".example", ".sample", ".template")
            ):
                result["env_vars"].extend(_parse_env(filepath, rel))

    return result


_FROM_RE = re.compile(r"^FROM\s+(\S+)", re.MULTILINE)
_EXPOSE_RE = re.compile(r"^EXPOSE\s+(.+)$", re.MULTILINE)
_ENV_DF_RE = re.compile(r"^ENV\s+(\w+)=", re.MULTILINE)


def _parse_dockerfile(filepath, rel):
    try:
        with open(filepath) as f:
            content = f.read()
    except (UnicodeDecodeError, IOError):
        return {"file": rel, "error": "unreadable"}

    base = _FROM_RE.search(content)
    exposes = _EXPOSE_RE.findall(content)
    env_vars = _ENV_DF_RE.findall(content)

    return {
        "file": rel,
        "base_image": base.group(1) if base else None,
        "exposed_ports": [p.strip() for p in exposes],
        "env_vars": env_vars,
    }


def _parse_compose(filepath, rel):
    """Extract service names from docker-compose (lightweight, no yaml dep)."""
    try:
        with open(filepath) as f:
            content = f.read()
    except (UnicodeDecodeError, IOError):
        return {"file": rel, "error": "unreadable"}

    services = []
    in_services = False
    for line in content.split("\n"):
        stripped = line.rstrip()
        if stripped.strip() == "services:" or stripped.strip().startswith("services:"):
            in_services = True
            continue
        if in_services:
            # Service lines are indented with 2 spaces
            m = re.match(r"^  (\w+):\s*$", stripped)
            if m:
                services.append(m.group(1))
            elif not stripped.startswith("  "):
                in_services = False

    return {
        "file": rel,
        "services": services,
    }


def _parse_env(filepath, rel):
    """Extract variable names from .env files (never expose values)."""
    try:
        with open(filepath) as f:
            lines = f.readlines()
    except (UnicodeDecodeError, IOError):
        return []

    vars_found = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^(\w+)=", line)
        if m:
            vars_found.append({"name": m.group(1), "file": rel})

    return vars_found


# ── Mermaid Output ────────────────────────────────────────────


def to_mermaid(data):
    """Generate Mermaid erDiagram from SQL tables + API routes."""
    parts = []

    # Database tables
    if data.get("sql", {}).get("tables"):
        parts.append("erDiagram")
        for table in data["sql"]["tables"]:
            for col in table["columns"]:
                parts.append(f"    {table['name']} {{ string {col} }}")

    # API routes
    if data.get("api", {}).get("routes"):
        if parts:
            parts.append("")
        parts.append("graph LR")
        seen = set()
        for route in data["api"]["routes"]:
            path_id = re.sub(r"[^a-zA-Z0-9]", "_", route["path"])
            path_id = path_id.strip("_") or "root"
            if path_id not in seen:
                parts.append(f'    {path_id}["{route["method"]} {route["path"]}"]')
                seen.add(path_id)

    return "\n".join(parts) if parts else "%% No artifacts found"


# ── CLI ───────────────────────────────────────────────────────


def main():
    import argparse

    ap = argparse.ArgumentParser(description="Context artifact scanner")
    ap.add_argument("path", nargs="?", default=".", help="Project root (default: .)")
    ap.add_argument("--sql", action="store_true", help="SQL schemas only")
    ap.add_argument("--api", action="store_true", help="API endpoints only")
    ap.add_argument("--infra", action="store_true", help="Infrastructure configs only")
    ap.add_argument("--mermaid", action="store_true", help="Output as Mermaid diagram")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    if not os.path.isdir(root):
        print(f"Error: {root} is not a directory", file=sys.stderr)
        sys.exit(1)

    data = {}
    if args.sql:
        data["sql"] = scan_sql(root)
    elif args.api:
        data["api"] = scan_api(root)
    elif args.infra:
        data["infra"] = scan_infra(root)
    else:
        data = {
            "sql": scan_sql(root),
            "api": scan_api(root),
            "infra": scan_infra(root),
        }

    if args.mermaid:
        print(to_mermaid(data))
    else:
        print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
