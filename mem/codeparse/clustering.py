"""Module detection — groups files into functional modules.

Strategy: directory-based grouping with import-affinity merging.
No graph algorithms needed — uses directory structure + symbol density.
"""

import json
from collections import defaultdict
from pathlib import Path

MODULES_FILE = "modules.json"
MIN_MODULE_FILES = 2


class ModuleDetector:
    """Detect functional modules from directory structure + import graph."""

    def __init__(self, project_root: str, symbols: dict, callgraph: dict | None = None):
        self.root = Path(project_root).resolve()
        self.symbols = symbols
        self.callgraph = callgraph or {"forward": {}, "reverse": {}}

    def _modules_path(self) -> Path:
        return self.root / ".codedb" / MODULES_FILE

    def detect(self) -> list[dict]:
        """Detect modules and save to modules.json."""
        files = self.symbols.get("files", {})

        # Step 1: Group files by top-level directory
        dir_groups: dict[str, list[str]] = defaultdict(list)
        for rel_path in files:
            parts = Path(rel_path).parts
            group_key = parts[0] if len(parts) > 1 else "_root"
            dir_groups[group_key].append(rel_path)

        # Step 2: Compute per-group stats
        modules = []
        for group_name, file_list in dir_groups.items():
            languages: dict[str, int] = defaultdict(int)
            sym_count = 0
            for f in file_list:
                info = files[f]
                lang = info.get("language", "?")
                languages[lang] += 1
                sym_count += len(info.get("symbols", []))

            modules.append(
                {
                    "name": group_name,
                    "files": file_list,
                    "file_count": len(file_list),
                    "symbol_count": sym_count,
                    "languages": dict(languages),
                }
            )

        # Step 3: Merge small groups (< MIN_MODULE_FILES) into most-connected neighbor
        merged = True
        while merged:
            merged = False
            for i, mod in enumerate(modules):
                if mod["file_count"] < MIN_MODULE_FILES:
                    # Find most-connected module via callgraph
                    best_j = self._most_connected(mod, modules, i)
                    if best_j is not None:
                        target = modules[best_j]
                        target["files"].extend(mod["files"])
                        target["file_count"] += mod["file_count"]
                        target["symbol_count"] += mod["symbol_count"]
                        for lang, cnt in mod["languages"].items():
                            target["languages"][lang] = (
                                target["languages"].get(lang, 0) + cnt
                            )
                        modules.pop(i)
                        merged = True
                        break

        # Step 4: Compute inter-module connections
        forward = self.callgraph.get("forward", {})
        for mod in modules:
            mod_files = set(mod["files"])
            imports_from = set()
            for f in mod["files"]:
                for callee in forward.get(f, {}):
                    # Find which module the callee lives in
                    for other_mod in modules:
                        if other_mod["name"] != mod["name"] and callee in other_mod.get(
                            "files", []
                        ):
                            imports_from.add(other_mod["name"])
            mod["imports_from"] = sorted(imports_from)

        # Sort by symbol count descending
        modules.sort(key=lambda m: m["symbol_count"], reverse=True)

        # Save
        data = {"modules": modules}
        out_dir = self.root / ".codedb"
        out_dir.mkdir(parents=True, exist_ok=True)
        with open(self._modules_path(), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        return modules

    def _most_connected(
        self, mod: dict, all_modules: list, skip_idx: int
    ) -> int | None:
        """Find the module with most cross-references to this one."""
        reverse = self.callgraph.get("reverse", {})
        forward = self.callgraph.get("forward", {})
        mod_syms = set()
        for f in mod["files"]:
            file_info = self.symbols.get("files", {}).get(f, {})
            for s in file_info.get("symbols", []):
                mod_syms.add(s["name"])

        best_score = 0
        best_j = None
        for j, other in enumerate(all_modules):
            if j == skip_idx:
                continue
            other_syms = set()
            for f in other["files"]:
                file_info = self.symbols.get("files", {}).get(f, {})
                for s in file_info.get("symbols", []):
                    other_syms.add(s["name"])
            # Count shared references
            score = len(mod_syms & other_syms)
            if score > best_score:
                best_score = score
                best_j = j

        # If no shared references, merge into largest module
        if best_j is None and len(all_modules) > 1:
            return max(
                (j for j in range(len(all_modules)) if j != skip_idx),
                key=lambda j: all_modules[j]["file_count"],
            )
        return best_j

    def module_for_file(self, file_path: str) -> str | None:
        """Find which module a file belongs to."""
        try:
            rel = str(Path(file_path).relative_to(self.root))
        except ValueError:
            return None

        try:
            with open(self._modules_path(), "r", encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError):
            return None

        for mod in data.get("modules", []):
            if rel in mod.get("files", []):
                return mod["name"]
        return None
