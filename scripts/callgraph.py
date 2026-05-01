#!/usr/bin/env python3
"""
callgraph.py — Function-level call graph extractor.

Supports: Python (AST), JavaScript/TypeScript, Shell, Go (regex-based).

Usage:
  callgraph.py [path]              # JSON call graph for project
  callgraph.py --mermaid [path]    # Mermaid flowchart
  callgraph.py --impact FUNC       # Blast radius (all transitive callers)
  callgraph.py --callers FUNC      # Direct callers of FUNC
  callgraph.py --callees FUNC      # Transitive callees of FUNC
  callgraph.py --lang py,js,sh,go  # Only scan specific languages
"""

import ast
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

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
        ".next",
        "vendor",
        "target",
        ".gradle",
        ".idea",
        ".vscode",
        ".codedb",
    ]
)

LANG_EXT = {
    ".py": "Python",
    ".js": "JavaScript",
    ".jsx": "JavaScript",
    ".ts": "TypeScript",
    ".tsx": "TypeScript",
    ".mjs": "JavaScript",
    ".sh": "Shell",
    ".bash": "Shell",
    ".go": "Go",
}


# ── Python (AST-based) ───────────────────────────────────────


def _collect_calls(node):
    """Walk AST node and collect all function call names."""
    calls = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Call):
            if isinstance(child.func, ast.Name):
                calls.add(child.func.id)
            elif isinstance(child.func, ast.Attribute):
                calls.add(child.func.attr)
    return calls


def _walk_functions(node, filepath, functions, prefix=""):
    """Recursively extract function definitions and their calls."""
    for child in ast.iter_child_nodes(node):
        if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
            name = f"{prefix}{child.name}"
            functions[name] = {
                "file": filepath,
                "line": child.lineno,
                "calls": sorted(_collect_calls(child)),
            }
            _walk_functions(child, filepath, functions, prefix=f"{name}.")
        elif isinstance(child, ast.ClassDef):
            _walk_functions(child, filepath, functions, prefix=f"{child.name}.")


def parse_python(filepath):
    try:
        with open(filepath) as f:
            tree = ast.parse(f.read())
    except (SyntaxError, UnicodeDecodeError, ValueError):
        return {}
    functions = {}
    _walk_functions(tree, filepath, functions)
    return functions


# ── JavaScript / TypeScript (regex) ──────────────────────────

_JS_FUNC_RE = re.compile(
    r"(?:async\s+)?function\s+(\w+)\s*\("
    r"|(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:function|\([^)]*\)\s*=>)"
    r"|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\w+\s*=>"
)
_JS_CALL_RE = re.compile(r"(\w+)\s*\(")
_JS_NOISE = frozenset(
    [
        "if",
        "else",
        "for",
        "while",
        "do",
        "switch",
        "case",
        "break",
        "continue",
        "return",
        "try",
        "catch",
        "finally",
        "throw",
        "new",
        "typeof",
        "instanceof",
        "in",
        "of",
        "void",
        "delete",
        "yield",
        "await",
        "import",
        "export",
        "from",
        "as",
        "class",
        "extends",
        "super",
        "this",
        "const",
        "let",
        "var",
        "function",
        "async",
        "true",
        "false",
        "null",
        "undefined",
        "console",
        "Math",
        "JSON",
        "Object",
        "Array",
        "String",
        "Number",
        "Boolean",
        "Promise",
        "Error",
        "Map",
        "Set",
        "Date",
        "parseInt",
        "parseFloat",
        "require",
    ]
)


def parse_javascript(filepath):
    try:
        with open(filepath) as f:
            lines = f.readlines()
    except (UnicodeDecodeError, IOError):
        return {}

    functions = {}
    for i, line in enumerate(lines):
        m = _JS_FUNC_RE.search(line)
        if not m:
            continue
        name = m.group(1) or m.group(2) or m.group(3)
        calls = set()
        brace_depth = 0
        started = False
        for j in range(i, min(i + 80, len(lines))):
            brace_depth += lines[j].count("{") - lines[j].count("}")
            if "{" in lines[j]:
                started = True
            if started and brace_depth <= 0 and j > i:
                break
            for cm in _JS_CALL_RE.finditer(lines[j]):
                callee = cm.group(1)
                if callee not in _JS_NOISE and callee != name:
                    calls.add(callee)
        functions[name] = {"file": filepath, "line": i + 1, "calls": sorted(calls)}
    return functions


# ── Shell (regex) ─────────────────────────────────────────────

_SHELL_FUNC_RE = re.compile(r"^(?:function\s+)?(\w+)\s*\(\)\s*\{")
_SHELL_BUILTINS = frozenset(
    [
        "if",
        "then",
        "else",
        "elif",
        "fi",
        "for",
        "while",
        "do",
        "done",
        "case",
        "esac",
        "in",
        "function",
        "select",
        "until",
        "time",
        "return",
        "exit",
        "break",
        "continue",
        "echo",
        "printf",
        "read",
        "cd",
        "pushd",
        "popd",
        "pwd",
        "source",
        "eval",
        "exec",
        "export",
        "local",
        "declare",
        "readonly",
        "set",
        "unset",
        "shift",
        "test",
        "true",
        "false",
        "trap",
        "wait",
        "kill",
        "let",
        "builtin",
        "command",
        "mkdir",
        "rm",
        "cp",
        "mv",
        "cat",
        "ls",
        "grep",
        "sed",
        "awk",
        "find",
        "sort",
        "uniq",
        "wc",
        "head",
        "tail",
        "cut",
        "tr",
        "tee",
        "xargs",
        "dirname",
        "basename",
        "date",
        "sleep",
        "touch",
        "chmod",
        "env",
        "which",
        "jq",
        "git",
        "docker",
        "npm",
        "pip",
    ]
)


def parse_shell(filepath):
    try:
        with open(filepath) as f:
            lines = f.readlines()
    except (UnicodeDecodeError, IOError):
        return {}

    functions = {}
    current_func = None
    func_start = 0
    brace_depth = 0
    body_calls = set()

    for i, line in enumerate(lines):
        stripped = line.strip()
        m = _SHELL_FUNC_RE.match(stripped)

        if m and current_func is None:
            # Save previous function if any
            current_func = m.group(1)
            func_start = i + 1
            brace_depth = 1
            body_calls = set()
            # Check if opening brace is on the same line beyond the match
            after = stripped[m.end() :]
            brace_depth += after.count("{") - after.count("}")
            if brace_depth <= 0:
                functions[current_func] = {
                    "file": filepath,
                    "line": func_start,
                    "calls": sorted(body_calls),
                }
                current_func = None
            continue

        if current_func is not None:
            brace_depth += stripped.count("{") - stripped.count("}")
            # Collect potential function calls from this line
            for word in re.findall(r"(\w+)", stripped):
                if (
                    word not in _SHELL_BUILTINS
                    and word != current_func
                    and not word.startswith("-")
                ):
                    body_calls.add(word)
            if brace_depth <= 0:
                functions[current_func] = {
                    "file": filepath,
                    "line": func_start,
                    "calls": sorted(body_calls),
                }
                current_func = None

    return functions


# ── Go (regex) ────────────────────────────────────────────────

_GO_FUNC_RE = re.compile(r"func\s+(?:\([^)]+\)\s*)?(\w+)\s*\(")
_GO_CALL_RE = re.compile(r"(\w+)\s*\(")
_GO_NOISE = frozenset(
    [
        "if",
        "else",
        "for",
        "range",
        "switch",
        "case",
        "break",
        "continue",
        "return",
        "func",
        "var",
        "const",
        "type",
        "struct",
        "interface",
        "package",
        "import",
        "defer",
        "go",
        "select",
        "chan",
        "map",
        "make",
        "new",
        "len",
        "cap",
        "append",
        "copy",
        "delete",
        "close",
        "panic",
        "recover",
        "print",
        "println",
        "true",
        "false",
        "nil",
        "string",
        "int",
        "bool",
        "error",
        "err",
        "fmt",
    ]
)


def parse_go(filepath):
    try:
        with open(filepath) as f:
            lines = f.readlines()
    except (UnicodeDecodeError, IOError):
        return {}

    functions = {}
    for i, line in enumerate(lines):
        m = _GO_FUNC_RE.search(line)
        if not m:
            continue
        name = m.group(1)
        calls = set()
        brace_depth = 0
        for j in range(i, min(i + 120, len(lines))):
            brace_depth += lines[j].count("{") - lines[j].count("}")
            for cm in _GO_CALL_RE.finditer(lines[j]):
                callee = cm.group(1)
                if callee not in _GO_NOISE and callee != name:
                    calls.add(callee)
            if brace_depth <= 0 and j > i:
                break
        functions[name] = {"file": filepath, "line": i + 1, "calls": sorted(calls)}
    return functions


# ── Graph operations ──────────────────────────────────────────

PARSERS = {
    "Python": parse_python,
    "JavaScript": parse_javascript,
    "TypeScript": parse_javascript,
    "Shell": parse_shell,
    "Go": parse_go,
}


def scan_project(root, langs=None):
    """Walk directory tree, extract all function definitions and calls."""
    all_funcs = {}
    stats = defaultdict(int)

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")
        ]
        for fname in filenames:
            ext = Path(fname).suffix
            lang = LANG_EXT.get(ext)
            if not lang:
                continue
            if langs and lang not in langs:
                continue
            parser = PARSERS.get(lang)
            if not parser:
                continue
            filepath = os.path.join(dirpath, fname)
            funcs = parser(filepath)
            # Qualify names to avoid cross-file collisions
            for name, info in funcs.items():
                qualified = name
                if name in all_funcs:
                    # Disambiguate with relative path
                    rel = os.path.relpath(filepath, root)
                    qualified = f"{rel}:{name}"
                    # Also re-qualify the existing one
                    if ":" not in next(iter([k for k in all_funcs if k == name]), ""):
                        old_info = all_funcs.pop(name)
                        old_rel = os.path.relpath(old_info["file"], root)
                        all_funcs[f"{old_rel}:{name}"] = old_info
                all_funcs[qualified] = info
            stats[lang] += len(funcs)

    return all_funcs, dict(stats)


def build_graph(all_funcs):
    """Build forward (callees) and reverse (callers) adjacency lists."""
    forward = defaultdict(set)
    reverse = defaultdict(set)
    known = set(all_funcs.keys())
    # Also index by short name for matching
    short_names = {}
    for qualified in known:
        short = qualified.split(":")[-1] if ":" in qualified else qualified
        short = short.split(".")[-1]  # Handle class.method
        short_names.setdefault(short, []).append(qualified)

    for func, info in all_funcs.items():
        for callee in info["calls"]:
            # Try exact match first
            if callee in known:
                forward[func].add(callee)
                reverse[callee].add(func)
            elif callee in short_names:
                for target in short_names[callee]:
                    forward[func].add(target)
                    reverse[target].add(func)
            # else: external/unknown call, skip

    return forward, reverse


def blast_radius(reverse_graph, func, max_depth=10):
    """BFS: find all transitive callers (who would be affected by changing func)."""
    affected = []
    visited = set()
    queue = [func]
    for _ in range(max_depth):
        next_q = []
        for f in queue:
            for caller in reverse_graph.get(f, []):
                if caller not in visited:
                    visited.add(caller)
                    affected.append(caller)
                    next_q.append(caller)
        queue = next_q
        if not queue:
            break
    return affected


def trace_callees(forward_graph, func, max_depth=10):
    """BFS: find all transitive callees (what func eventually calls)."""
    reachable = []
    visited = set()
    queue = [func]
    for _ in range(max_depth):
        next_q = []
        for f in queue:
            for callee in forward_graph.get(f, []):
                if callee not in visited:
                    visited.add(callee)
                    reachable.append(callee)
                    next_q.append(callee)
        queue = next_q
        if not queue:
            break
    return reachable


def to_mermaid(forward_graph, title=None):
    """Convert forward adjacency list to Mermaid flowchart."""
    lines = ["graph TD"]
    if title:
        lines.insert(0, f"---\ntitle: {title}\n---")
    seen = set()
    for func in sorted(forward_graph):
        for callee in sorted(forward_graph[func]):
            # Sanitize node IDs for Mermaid
            src_id = re.sub(r"[^a-zA-Z0-9_]", "_", func)
            dst_id = re.sub(r"[^a-zA-Z0-9_]", "_", callee)
            if src_id == dst_id:
                continue
            edge = f'    {src_id}["{func}"] --> {dst_id}["{callee}"]'
            lines.append(edge)
            seen.add(src_id)
            seen.add(dst_id)
    return "\n".join(lines)


# ── CLI ───────────────────────────────────────────────────────


def main():
    import argparse

    ap = argparse.ArgumentParser(description="Function-level call graph extractor")
    ap.add_argument("path", nargs="?", default=".", help="Project root (default: .)")
    ap.add_argument(
        "--mermaid", action="store_true", help="Output as Mermaid flowchart"
    )
    ap.add_argument(
        "--impact", metavar="FUNC", help="Blast radius: all transitive callers"
    )
    ap.add_argument("--callers", metavar="FUNC", help="Direct callers of FUNC")
    ap.add_argument("--callees", metavar="FUNC", help="Transitive callees of FUNC")
    ap.add_argument("--lang", help="Comma-separated languages to scan (py,js,sh,go)")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    if not os.path.isdir(root):
        print(f"Error: {root} is not a directory", file=sys.stderr)
        sys.exit(1)

    lang_map = {
        "py": "Python",
        "js": "JavaScript",
        "ts": "TypeScript",
        "sh": "Shell",
        "go": "Go",
    }
    langs = set()
    if args.lang:
        for l in args.lang.split(","):
            l = l.strip()
            if l in lang_map:
                langs.add(lang_map[l])

    all_funcs, stats = scan_project(root, langs or None)
    forward, reverse = build_graph(all_funcs)

    if args.impact:
        # Find the function (support partial match)
        matches = [f for f in all_funcs if args.impact in f]
        if not matches:
            print(
                json.dumps(
                    {
                        "error": f"{args.impact} not found",
                        "available": sorted(all_funcs.keys())[:20],
                    },
                    indent=2,
                )
            )
            sys.exit(1)
        func = matches[0]
        affected = blast_radius(reverse, func)
        print(
            json.dumps(
                {
                    "function": func,
                    "blast_radius": affected,
                    "count": len(affected),
                },
                indent=2,
            )
        )

    elif args.callers:
        matches = [f for f in all_funcs if args.callers in f]
        if not matches:
            print(json.dumps({"error": f"{args.callers} not found"}, indent=2))
            sys.exit(1)
        func = matches[0]
        callers = sorted(reverse.get(func, []))
        print(
            json.dumps(
                {"function": func, "callers": callers, "count": len(callers)}, indent=2
            )
        )

    elif args.callees:
        matches = [f for f in all_funcs if args.callees in f]
        if not matches:
            print(json.dumps({"error": f"{args.callees} not found"}, indent=2))
            sys.exit(1)
        func = matches[0]
        reachable = trace_callees(forward, func)
        print(
            json.dumps(
                {"function": func, "callees": reachable, "count": len(reachable)},
                indent=2,
            )
        )

    elif args.mermaid:
        print(to_mermaid(forward))

    else:
        print(
            json.dumps(
                {
                    "functions": all_funcs,
                    "stats": stats,
                    "total_functions": len(all_funcs),
                },
                indent=2,
            )
        )


if __name__ == "__main__":
    main()
