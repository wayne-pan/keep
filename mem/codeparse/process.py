"""Process tracing — trace execution flows from entry points.

Finds entry points (main, handlers, __name__ == '__main__') and follows
the call graph to build execution flow chains.
"""

import json
import re
from pathlib import Path

from mem.codeparse.parser import detect_language

TRACES_FILE = "traces.json"

# Patterns that indicate an entry point
_ENTRY_PATTERNS = {
    "py": [
        re.compile(r"^def\s+main\s*\("),
        re.compile(r"^async\s+def\s+main\s*\("),
        re.compile(r"if\s+__name__\s*==\s*['\"]__main__['\"]"),
        re.compile(r"^def\s+(?:app|create_app|handler|run|serve|start)\s*\("),
        re.compile(r"^async\s+def\s+(?:app|create_app|handler|run|serve|start)\s*\("),
    ],
    "ts": [
        re.compile(r"(?:export\s+)?function\s+main\s*\("),
        re.compile(r"(?:export\s+)?async\s+function\s+main\s*\("),
        re.compile(r"(?:export\s+)?default\s+function"),
        re.compile(r"app\.(?:listen|get|post|put|delete|use)\s*\("),
    ],
    "js": [
        re.compile(r"(?:export\s+)?function\s+main\s*\("),
        re.compile(r"(?:export\s+)?async\s+function\s+main\s*\("),
        re.compile(r"app\.(?:listen|get|post|put|delete|use)\s*\("),
    ],
    "go": [
        re.compile(r"^func\s+main\s*\("),
        re.compile(r"^func\s+\w+Handler\s*\("),
    ],
    "rs": [
        re.compile(r"^fn\s+main\s*\("),
    ],
    "sh": [
        re.compile(r"^main\s*(?:\(\)|\s)"),
    ],
}


class ProcessTracer:
    """Trace execution flows from entry points."""

    def __init__(self, project_root: str, symbols: dict, callgraph: dict | None = None):
        self.root = Path(project_root).resolve()
        self.symbols = symbols
        self.callgraph = callgraph or {"forward": {}, "reverse": {}}

    def _traces_path(self) -> Path:
        return self.root / ".codedb" / TRACES_FILE

    def find_entry_points(self) -> list[dict]:
        """Find all entry points in the project."""
        entries = []
        for rel_path, file_info in self.symbols.get("files", {}).items():
            lang = file_info.get("language", "")
            full_path = str(self.root / rel_path)
            patterns = _ENTRY_PATTERNS.get(lang, [])
            if not patterns:
                continue

            try:
                with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
            except OSError:
                continue

            for pat in patterns:
                for m in pat.finditer(content):
                    # Try to extract the function name from the match
                    match_text = m.group(0)
                    name = self._extract_entry_name(match_text, lang)
                    if name:
                        # Find line number
                        line_num = content[: m.start()].count("\n") + 1
                        entries.append(
                            {
                                "name": name,
                                "file": rel_path,
                                "line": line_num,
                                "language": lang,
                                "pattern": match_text[:60],
                            }
                        )

        return entries

    def _extract_entry_name(self, match_text: str, lang: str) -> str | None:
        """Extract function name from a pattern match."""
        name_match = re.search(r"(?:def|function|fn)\s+(\w+)", match_text)
        if name_match:
            return name_match.group(1)
        if "__main__" in match_text:
            return "__main__"
        if "app." in match_text:
            method = re.search(r"app\.(\w+)", match_text)
            return f"app.{method.group(1)}" if method else "app.handler"
        if "default" in match_text:
            return "default_export"
        return None

    def trace(self, entry_name: str, max_depth: int = 5) -> list[dict]:
        """Trace execution flow from an entry point.

        Returns a chain of [{name, file, line, depth}].
        """
        forward = self.callgraph.get("forward", {})
        visited = set()
        chain = []

        def _walk(name: str, depth: int):
            if depth > max_depth or name in visited:
                return
            visited.add(name)

            # Find where this name is defined
            location = self._find_definition(name)
            if location:
                chain.append(
                    {
                        "name": name,
                        "file": location["file"],
                        "line": location["line"],
                        "depth": depth,
                    }
                )

            # Follow callees
            for rel_path, syms in forward.items():
                if name in syms:
                    for callee in syms[name]:
                        _walk(callee, depth + 1)

        _walk(entry_name, 0)
        return chain

    def _find_definition(self, name: str) -> dict | None:
        """Find where a symbol is defined."""
        for rel_path, file_info in self.symbols.get("files", {}).items():
            for sym in file_info.get("symbols", []):
                if sym["name"] == name:
                    return {"file": rel_path, "line": sym["line"]}
        return None

    def trace_all(self, max_depth: int = 5) -> dict:
        """Trace from all entry points and save to traces.json."""
        entries = self.find_entry_points()
        traces = {}
        for entry in entries:
            name = entry["name"]
            chain = self.trace(name, max_depth)
            traces[name] = {
                "entry": entry,
                "chain": chain,
                "chain_length": len(chain),
            }

        # Save
        out_dir = self.root / ".codedb"
        out_dir.mkdir(parents=True, exist_ok=True)
        with open(self._traces_path(), "w", encoding="utf-8") as f:
            json.dump({"traces": traces}, f, ensure_ascii=False, indent=2)
        return traces
