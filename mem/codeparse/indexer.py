"""Project indexer — builds and manages per-project symbol index.

Stores index as JSON in <project>/.codedb/symbols.json for fast lookup.
Incremental updates: only re-scan files with changed mtime.
"""

import json
import os
import time
from pathlib import Path

from mem.codeparse.parser import detect_language, extract_symbols

INDEX_VERSION = 1
CODEDB_DIR = ".codedb"
SYMBOLS_FILE = "symbols.json"

# Dirs to skip during indexing
_SKIP_DIRS = {
    ".git",
    ".svn",
    ".hg",
    "node_modules",
    "__pycache__",
    ".mypy_cache",
    ".tox",
    ".pytest_cache",
    ".venv",
    "venv",
    "env",
    ".env",
    "dist",
    "build",
    ".next",
    ".nuxt",
    "target",
    "vendor",
    ".codedb",
    ".sprint",
}


class ProjectIndex:
    """Build and manage per-project code index."""

    def __init__(self, project_root: str):
        self.root = Path(project_root).resolve()
        self._index_dir = self.root / CODEDB_DIR
        self._symbols_path = self._index_dir / SYMBOLS_FILE
        self._cache: dict | None = None

    @property
    def index_dir(self) -> Path:
        return self._index_dir

    def _read_index(self) -> dict:
        """Load index from disk."""
        if self._cache is not None:
            return self._cache
        try:
            with open(self._symbols_path, "r", encoding="utf-8") as f:
                self._cache = json.load(f)
            return self._cache
        except (OSError, json.JSONDecodeError):
            return self._empty_index()

    def _write_index(self, data: dict):
        """Persist index to disk."""
        self._index_dir.mkdir(parents=True, exist_ok=True)
        data["indexed_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with open(self._symbols_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        self._cache = data

    def _empty_index(self) -> dict:
        return {
            "version": INDEX_VERSION,
            "indexed_at": None,
            "root": str(self.root),
            "files": {},
        }

    def needs_reindex(self) -> bool:
        """Check if any source files have changed since last index."""
        data = self._read_index()
        if not data["files"]:
            return True
        for rel_path, info in data["files"].items():
            full = self.root / rel_path
            if not full.is_file():
                return True
            try:
                if full.stat().st_mtime > info.get("mtime", 0):
                    return True
            except OSError:
                return True
        return False

    def build_index(self) -> dict:
        """Full scan: extract symbols from all source files."""
        data = self._empty_index()
        file_count = 0
        sym_count = 0

        for dirpath, dirnames, filenames in os.walk(self.root):
            # Prune skipped dirs in-place
            dirnames[:] = [
                d for d in dirnames if d not in _SKIP_DIRS and not d.startswith(".")
            ]

            for fname in filenames:
                fpath = Path(dirpath) / fname
                lang = detect_language(str(fpath))
                if not lang:
                    continue
                try:
                    mtime = fpath.stat().st_mtime
                except OSError:
                    continue
                rel = str(fpath.relative_to(self.root))
                symbols = extract_symbols(str(fpath))
                data["files"][rel] = {
                    "mtime": mtime,
                    "language": lang,
                    "symbols": symbols,
                }
                file_count += 1
                sym_count += len(symbols)

        data["_stats"] = {
            "file_count": file_count,
            "symbol_count": sym_count,
        }
        self._write_index(data)
        return data

    def update_file(self, file_path: str) -> dict | None:
        """Incremental: reindex a single file. Returns updated entry or None."""
        data = self._read_index()
        fpath = Path(file_path).resolve()
        if not fpath.is_file():
            return None

        lang = detect_language(file_path)
        if not lang:
            return None

        try:
            rel = str(fpath.relative_to(self.root))
        except ValueError:
            return None

        mtime = fpath.stat().st_mtime
        symbols = extract_symbols(file_path)
        data["files"][rel] = {
            "mtime": mtime,
            "language": lang,
            "symbols": symbols,
        }

        # Recompute stats
        total_syms = sum(len(f["symbols"]) for f in data["files"].values())
        data["_stats"] = {
            "file_count": len(data["files"]),
            "symbol_count": total_syms,
        }
        self._write_index(data)
        return data["files"][rel]

    def remove_file(self, file_path: str) -> bool:
        """Remove a file from the index."""
        data = self._read_index()
        try:
            rel = str(Path(file_path).resolve().relative_to(self.root))
        except ValueError:
            return False
        if rel in data["files"]:
            del data["files"][rel]
            total_syms = sum(len(f["symbols"]) for f in data["files"].values())
            data["_stats"] = {
                "file_count": len(data["files"]),
                "symbol_count": total_syms,
            }
            self._write_index(data)
            return True
        return False

    def get_symbols(self) -> dict:
        """Load full index."""
        return self._read_index()

    def get_file_symbols(self, file_path: str) -> list[dict]:
        """Get symbols for a specific file."""
        data = self._read_index()
        try:
            rel = str(Path(file_path).resolve().relative_to(self.root))
        except ValueError:
            return []
        entry = data["files"].get(rel, {})
        return entry.get("symbols", [])

    def get_stats(self) -> dict:
        """Return index statistics."""
        data = self._read_index()
        return data.get("_stats", {"file_count": 0, "symbol_count": 0})

    def invalidate(self):
        """Clear in-memory cache so next read goes to disk."""
        self._cache = None
