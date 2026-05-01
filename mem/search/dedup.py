"""4-layer dedup pipeline for search results.

Layers:
  1. Group by (session_id, type), keep highest rank per group
  2. Jaccard word overlap >0.85 title dedup
  3. Cap any single type at 60% of results
  4. Max 3 results per concept tag
"""

from __future__ import annotations

import json
from collections import defaultdict


def _tokenize(text: str) -> set[str]:
    """Lowercase word set for Jaccard comparison."""
    return set(text.lower().split())


def _jaccard(a: set[str], b: set[str]) -> float:
    """Jaccard similarity between two sets."""
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def dedup_results(results: list[dict]) -> list[dict]:
    """Apply 4-layer dedup pipeline to scored search results.

    Each result dict must have: rank, session_id, type, title, concepts.
    """
    if not results:
        return []

    # Sort by rank ascending (lower BM25 = better) to process best first
    results = sorted(results, key=lambda r: r.get("rank", 0.0))

    # --- Layer 1: Group by (session_id, type), keep best rank ---
    seen_groups: dict[tuple, int] = {}  # (session_id, type) -> index in kept
    layer1: list[dict] = []
    for r in results:
        key = (r.get("session_id", ""), r.get("type", ""))
        if key not in seen_groups:
            seen_groups[key] = len(layer1)
            layer1.append(r)
    results = layer1

    # --- Layer 2: Jaccard title dedup (>0.85 overlap) ---
    kept_titles: list[set[str]] = []
    layer2: list[dict] = []
    for r in results:
        title_tokens = _tokenize(r.get("title", ""))
        is_dup = False
        for existing_tokens in kept_titles:
            if _jaccard(title_tokens, existing_tokens) > 0.85:
                is_dup = True
                break
        if not is_dup:
            kept_titles.append(title_tokens)
            layer2.append(r)
    results = layer2

    if not results:
        return []

    # --- Layer 3: Cap any single type at 60% of results ---
    total = len(results)
    max_per_type = max(1, int(total * 0.6))
    type_counts: dict[str, int] = defaultdict(int)
    layer3: list[dict] = []
    for r in results:
        t = r.get("type", "unknown")
        if type_counts[t] < max_per_type:
            type_counts[t] += 1
            layer3.append(r)
    results = layer3

    # --- Layer 4: Max 3 results per concept tag ---
    concept_counts: dict[str, int] = defaultdict(int)
    layer4: list[dict] = []
    for r in results:
        concepts_raw = r.get("concepts", "[]")
        try:
            concepts = (
                json.loads(concepts_raw)
                if isinstance(concepts_raw, str)
                else concepts_raw
            )
        except (json.JSONDecodeError, TypeError):
            concepts = []
        # Allow if no concepts or all concepts are under the limit
        over_limit = any(concept_counts.get(str(c), 0) >= 3 for c in concepts)
        if not over_limit:
            for c in concepts:
                concept_counts[str(c)] += 1
            layer4.append(r)
    results = layer4

    return results


def _rrf_fuse(result_sets: list, k: int = 60) -> list:
    """Reciprocal Rank Fusion: score = sum(1 / (k + rank)) + feedback bonus."""
    scores = {}
    meta = {}
    for results in result_sets:
        for rank, r in enumerate(results):
            rid = r["id"]
            rrf = 1.0 / (k + rank + 1)
            fb = r.get("feedback_score", 0.0) * 0.1
            scores[rid] = scores.get(rid, 0) + rrf + fb
            meta[rid] = r
    sorted_ids = sorted(scores, key=scores.get, reverse=True)
    return [{**meta[rid], "rrf_score": scores[rid]} for rid in sorted_ids]
