"""Cross-file call graph — regex-based reference scanning.

Builds callers.json: for each symbol, tracks who calls it and what it calls.
Accuracy is ~70% (regex-based, not full AST) but sufficient for impact analysis.
"""

import json
import os
import re
from collections import defaultdict
from pathlib import Path

from mem.codeparse.parser import detect_language

CALLERS_FILE = "callers.json"

# Per-language patterns for extracting references from source code.
# Each pattern matches symbol_name( which is a function/method call.
_CALL_PATTERNS = {
    "py": re.compile(r"(?<!\w)(?P<name>\w+)\s*\("),
    "ts": re.compile(r"(?<!\w)(?P<name>\w+)\s*\("),
    "js": re.compile(r"(?<!\w)(?P<name>\w+)\s*\("),
    "go": re.compile(r"(?<!\w)(?P<name>\w+)\s*[\.(]"),
    "rs": re.compile(r"(?<!\w)(?P<name>\w+)\s*[\.(]"),
    "sh": re.compile(r"(?<!\w)(?P<name>\w+)\s*(?:\s|$|;|&&|\|)"),
}

# Import patterns per language
_IMPORT_PATTERNS = {
    "py": re.compile(r"^(?:from|import)\s+(?P<module>[\w.]+)"),
    "ts": re.compile(r"import\s+.*?from\s+['\"](?P<module>[^'\"]+)['\"]"),
    "js": re.compile(r"import\s+.*?from\s+['\"](?P<module>[^'\"]+)['\"]"),
    "go": re.compile(r'"(?P<module>[^"]+)"'),
}


def _extract_references(file_path: str, defined_names: set[str]) -> dict:
    """Extract call references from a source file.

    Returns {"calls": [names this file calls], "imports": [module paths]}.
    Only reports calls to names that are defined elsewhere in the project.
    """
    lang = detect_language(file_path)
    if lang not in _CALL_PATTERNS:
        return {"calls": [], "imports": []}

    call_pattern = _CALL_PATTERNS[lang]
    import_pattern = _IMPORT_PATTERNS.get(lang)

    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError:
        return {"calls": [], "imports": []}

    calls = set()
    for m in call_pattern.finditer(content):
        name = m.group("name")
        if name in defined_names:
            calls.add(name)

    imports = set()
    if import_pattern:
        for m in import_pattern.finditer(content):
            imports.add(m.group("module"))

    return {"calls": sorted(calls), "imports": sorted(imports)}


class CallGraph:
    """Build cross-file call/dependency graph from symbol references."""

    def __init__(self, project_root: str, symbols: dict):
        self.root = Path(project_root).resolve()
        self.symbols = symbols  # symbols.json data
        self._graph: dict | None = None

    def _graph_path(self) -> Path:
        return self.root / ".codedb" / CALLERS_FILE

    def _all_defined_names(self) -> set[str]:
        """Collect all symbol names defined across the project."""
        names = set()
        for file_info in self.symbols.get("files", {}).values():
            for sym in file_info.get("symbols", []):
                names.add(sym["name"])
        return names

    def _file_defined_names(self, rel_path: str) -> set[str]:
        """Get names defined in a specific file."""
        entry = self.symbols.get("files", {}).get(rel_path, {})
        return {s["name"] for s in entry.get("symbols", [])}

    def build(self) -> dict:
        """Build the full call graph and save to callers.json."""
        all_names = self._all_defined_names()
        files = self.symbols.get("files", {})

        # Build forward edges: file -> {symbol -> [called_names]}
        forward: dict[str, dict[str, list[str]]] = {}
        for rel_path in files:
            full_path = str(self.root / rel_path)
            refs = _extract_references(full_path, all_names)
            file_names = self._file_defined_names(rel_path)
            # For each symbol in this file, record what it calls
            # (approximation: attribute all calls in file to all symbols)
            for sym_name in file_names:
                # Filter out self-references
                calls = [c for c in refs["calls"] if c != sym_name]
                if calls:
                    if rel_path not in forward:
                        forward[rel_path] = {}
                    forward[rel_path][sym_name] = calls

        # Build reverse edges: name -> [{file, symbol}] who call it
        reverse: dict[str, list[dict]] = defaultdict(list)
        for rel_path, syms in forward.items():
            for caller, callees in syms.items():
                for callee in callees:
                    reverse[callee].append({"file": rel_path, "symbol": caller})

        graph = {
            "forward": forward,  # file -> {symbol -> [what it calls]}
            "reverse": {k: v for k, v in reverse.items()},  # name -> [{who calls it}]
        }

        # Save to disk
        graph_dir = self.root / ".codedb"
        graph_dir.mkdir(parents=True, exist_ok=True)
        with open(self._graph_path(), "w", encoding="utf-8") as f:
            json.dump(graph, f, ensure_ascii=False, indent=2)
        self._graph = graph
        return graph

    def _load(self) -> dict:
        """Load call graph from disk."""
        if self._graph is not None:
            return self._graph
        try:
            with open(self._graph_path(), "r", encoding="utf-8") as f:
                self._graph = json.load(f)
            return self._graph
        except (OSError, json.JSONDecodeError):
            return {"forward": {}, "reverse": {}}

    def callers_of(self, name: str) -> list[dict]:
        """Who calls this symbol? Returns [{file, symbol}]."""
        graph = self._load()
        return graph.get("reverse", {}).get(name, [])

    def callees_of(self, name: str) -> list[dict]:
        """What does this symbol call? Returns [{file, symbol}]."""
        graph = self._load()
        results = []
        for rel_path, syms in graph.get("forward", {}).items():
            if name in syms:
                for callee in syms[name]:
                    # Find where callee is defined
                    for f, info in self.symbols.get("files", {}).items():
                        for sym in info.get("symbols", []):
                            if sym["name"] == callee:
                                results.append(
                                    {
                                        "name": callee,
                                        "file": f,
                                        "line": sym["line"],
                                        "kind": sym["kind"],
                                    }
                                )
                                break
        return results

    def impact(self, name: str, depth: int = 3) -> dict:
        """Blast radius analysis: find all symbols transitively affected.

        Returns {symbol: [chain of callers from target to symbol]}.
        """
        graph = self._load()
        reverse = graph.get("reverse", {})
        affected: dict[str, list[dict]] = {}

        def _walk(target: str, chain: list[dict], remaining: int):
            if remaining <= 0:
                return
            for caller in reverse.get(target, []):
                key = f"{caller['file']}:{caller['symbol']}"
                if key not in affected:
                    new_chain = chain + [{"name": target, "file": caller["file"]}]
                    affected[key] = new_chain
                    _walk(caller["symbol"], new_chain, remaining - 1)

        _walk(name, [], depth)
        return {
            "target": name,
            "depth": depth,
            "affected_count": len(affected),
            "affected": affected,
        }
