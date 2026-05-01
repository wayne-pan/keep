"""Code tools: smart_outline, smart_search, smart_unfold + codedb tools."""

import os

from mem.codeparse.parser import extract_symbols, search_symbols, unfold_symbol
from mem.codeparse.indexer import ProjectIndex
from mem.codeparse.registry import (
    register as reg_register,
    unregister as reg_unregister,
    list_projects as reg_list,
    find_project as reg_find,
    get_stats as reg_stats,
)
from mem.codeparse.callgraph import CallGraph
from mem.codeparse.clustering import ModuleDetector
from mem.codeparse.process import ProcessTracer
from mem.tools import _trim


def _detect_project_root(path: str | None = None) -> str:
    """Walk up from path to find project root (has .git or .codedb)."""
    start = path or os.getcwd()
    cur = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(cur, ".git")) or os.path.isdir(
            os.path.join(cur, ".codedb")
        ):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return start
        cur = parent


def _ensure_index(root: str) -> ProjectIndex:
    """Get a ProjectIndex, building if needed."""
    idx = ProjectIndex(root)
    data = idx.get_symbols()
    if not data.get("files"):
        data = idx.build_index()
        reg_register(root, data.get("_stats", {}))
    return idx


def register_code_tools(mcp):
    # ── Existing tools ──

    @mcp.tool()
    def smart_outline(file_path: str) -> str:
        """Get structural outline of a file — shows all symbols (functions, classes, methods, types) with signatures but bodies folded. Much cheaper than reading the full file."""
        symbols = extract_symbols(file_path)
        if not symbols:
            return f"No symbols found in {file_path}."

        lines = [f"## {file_path} ({len(symbols)} symbols)"]
        for s in symbols:
            sig = s.get("signature", "")
            sig_display = f"({sig})" if sig and not sig.startswith("(") else sig
            lines.append(
                f"  L{s['line']:>4d}  {s['kind']:<10s}  {s['name']}{sig_display}"
            )
        return _trim("\n".join(lines))

    @mcp.tool()
    def smart_search(
        query: str, path: str = None, max_results: int = 20, file_pattern: str = None
    ) -> str:
        """Search codebase for symbols, functions, classes using AST-like parsing. Returns folded structural views with token counts."""
        results = search_symbols(
            query, path=path or ".", max_results=max_results, file_pattern=file_pattern
        )
        if not results:
            return f"No symbols matching '{query}'."

        lines = [f"Found {len(results)} symbols matching '{query}':"]
        for r in results:
            lines.append(
                f"  {r['file']}:{r['line']}  {r['kind']:<10s}  {r['name']}  (score: {r.get('score', 0)})"
            )
        return _trim("\n".join(lines))

    @mcp.tool()
    def smart_unfold(file_path: str, symbol_name: str) -> str:
        """Expand a specific symbol (function, class, method) from a file. Returns the full source code of just that symbol."""
        source = unfold_symbol(file_path, symbol_name)
        if source is None:
            return f"Symbol '{symbol_name}' not found in {file_path}."
        return source

    # ── P0: Index + Registry tools ──

    @mcp.tool()
    def codedb_index(path: str = None) -> str:
        """Build or rebuild the code intelligence index for a project. Scans all source files and extracts symbols. Returns summary stats."""
        root = _detect_project_root(path)
        idx = ProjectIndex(root)
        data = idx.build_index()
        stats = data.get("_stats", {})
        reg_register(root, stats)

        lines = [f"Indexed: {root}"]
        lines.append(f"  Files: {stats.get('file_count', 0)}")
        lines.append(f"  Symbols: {stats.get('symbol_count', 0)}")
        return "\n".join(lines)

    @mcp.tool()
    def codedb_status(path: str = None) -> str:
        """Show code intelligence index status: file count, symbol count, last indexed time, registered projects."""
        root = _detect_project_root(path)
        idx = ProjectIndex(root)
        stats = idx.get_stats()
        data = idx.get_symbols()

        lines = [f"Project: {root}"]
        lines.append(f"  Files indexed: {stats.get('file_count', 0)}")
        lines.append(f"  Symbols: {stats.get('symbol_count', 0)}")
        lines.append(f"  Last indexed: {data.get('indexed_at', 'never')}")

        # Show per-language breakdown
        langs = {}
        for f_info in data.get("files", {}).values():
            lang = f_info.get("language", "?")
            langs[lang] = langs.get(lang, 0) + 1
        if langs:
            lang_str = ", ".join(f"{k}:{v}" for k, v in sorted(langs.items()))
            lines.append(f"  Languages: {lang_str}")

        # Global registry stats
        gstats = reg_stats()
        lines.append(
            f"\nRegistry: {gstats['project_count']} projects, {gstats['total_files']} files, {gstats['total_symbols']} symbols"
        )

        return "\n".join(lines)

    @mcp.tool()
    def codedb_registry() -> str:
        """List all indexed projects in the global registry. Shows path, file count, symbol count, last indexed time."""
        projects = reg_list()
        if not projects:
            return "No projects registered."

        lines = [f"Registered projects ({len(projects)}):"]
        for p in projects:
            name = os.path.basename(p["path"])
            lines.append(
                f"  {name}  {p['file_count']} files, {p['symbol_count']} syms  "
                f"indexed: {p.get('last_indexed', '?')}  path: {p['path']}"
            )
        return _trim("\n".join(lines))

    # ── P1: Call graph + Impact tools ──

    @mcp.tool()
    def codedb_callers(name: str, path: str = None) -> str:
        """Find all callers of a function/method/class (who calls it). Shows file and function name for each caller."""
        root = _detect_project_root(path)
        idx = _ensure_index(root)
        data = idx.get_symbols()
        cg = CallGraph(root, data)

        # Build graph if not cached
        callers = cg.callers_of(name)
        if not callers and not cg._load().get("forward"):
            cg.build()
            callers = cg.callers_of(name)

        if not callers:
            return f"No callers found for '{name}'."

        lines = [f"Callers of '{name}' ({len(callers)}):"]
        for c in callers:
            lines.append(f"  {c['file']}:{c['symbol']}")
        return _trim("\n".join(lines))

    @mcp.tool()
    def codedb_impact(name: str, path: str = None, depth: int = 3) -> str:
        """Blast radius analysis: find all symbols transitively affected by changing this function/class. Shows caller chains up to N levels deep."""
        root = _detect_project_root(path)
        idx = _ensure_index(root)
        data = idx.get_symbols()
        cg = CallGraph(root, data)

        if not cg._load().get("forward"):
            cg.build()

        result = cg.impact(name, depth)
        affected = result.get("affected", {})

        if not affected:
            return f"No transitive impact found for '{name}' (no callers detected)."

        lines = [
            f"Impact of changing '{name}' (depth={depth}): {len(affected)} symbols affected"
        ]
        for key, chain in sorted(affected.items()):
            chain_str = " → ".join(
                f"{step['name']}@{os.path.basename(step['file'])}" for step in chain
            )
            lines.append(f"  {chain_str} → {key.split(':')[-1]}")
        return _trim("\n".join(lines))

    # ── P2: Module detection + Process tracing ──

    @mcp.tool()
    def codedb_modules(path: str = None) -> str:
        """Detect functional modules in the project. Groups files by directory structure and import affinity. Shows module name, files, symbols, and inter-module connections."""
        root = _detect_project_root(path)
        idx = _ensure_index(root)
        data = idx.get_symbols()

        # Load or build callgraph
        cg = CallGraph(root, data)
        graph = cg._load()
        if not graph.get("forward"):
            graph = cg.build()

        detector = ModuleDetector(root, data, graph)
        modules = detector.detect()

        if not modules:
            return "No modules detected."

        lines = [f"Detected {len(modules)} modules:"]
        for mod in modules:
            langs = ", ".join(
                f"{k}:{v}" for k, v in sorted(mod.get("languages", {}).items())
            )
            imports = ", ".join(mod.get("imports_from", []))
            lines.append(
                f"\n  {mod['name']} ({mod['file_count']} files, {mod['symbol_count']} syms)"
            )
            lines.append(f"    Languages: {langs}")
            if imports:
                lines.append(f"    Imports from: {imports}")
            for f in mod["files"][:5]:
                lines.append(f"    - {f}")
            if len(mod["files"]) > 5:
                lines.append(f"    ... +{len(mod['files']) - 5} more")
        return _trim("\n".join(lines))

    @mcp.tool()
    def codedb_traces(entry: str = None, path: str = None, max_depth: int = 5) -> str:
        """Trace execution flow from an entry point. If no entry specified, lists all detected entry points (main, handlers, etc)."""
        root = _detect_project_root(path)
        idx = _ensure_index(root)
        data = idx.get_symbols()

        # Load or build callgraph
        cg = CallGraph(root, data)
        graph = cg._load()
        if not graph.get("forward"):
            graph = cg.build()

        tracer = ProcessTracer(root, data, graph)

        if not entry:
            entries = tracer.find_entry_points()
            if not entries:
                return "No entry points detected in this project."
            lines = [f"Entry points ({len(entries)}):"]
            for e in entries:
                lines.append(
                    f"  {e['name']}  {e['file']}:{e['line']}  ({e['language']})"
                )
            return _trim("\n".join(lines))

        chain = tracer.trace(entry, max_depth)
        if not chain:
            return f"No execution trace found from '{entry}'."

        lines = [f"Execution trace from '{entry}' ({len(chain)} steps):"]
        for step in chain:
            indent = "  " * (step["depth"] + 1)
            lines.append(
                f"{indent}{step['name']}  {step['file']}:{step['line']}  [depth={step['depth']}]"
            )
        return _trim("\n".join(lines))
