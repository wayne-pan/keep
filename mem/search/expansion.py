"""Multi-query expansion for better FTS5 recall.

Generates query variants: original, abbreviation-expanded, prefix, and OR-form.
"""

from __future__ import annotations

ABBREVIATIONS: dict[str, str] = {
    "db": "database",
    "auth": "authentication",
    "config": "configuration",
    "impl": "implementation",
    "perf": "performance",
    "sec": "security",
}


def expand_query(query: str) -> list[str]:
    """Expand a query into multiple FTS5 query variants.

    Returns a list of query strings, always including the original.

    Variants produced:
      1. Original query (verbatim)
      2. Abbreviation expansion (replace known abbreviations)
      3. Prefix match: last word gets * appended (FTS5 prefix operator)
      4. OR variant: split terms joined with OR
    """
    variants: list[str] = [query]

    # --- Abbreviation expansion ---
    words = query.split()
    expanded = []
    changed = False
    for word in words:
        lower = word.lower()
        if lower in ABBREVIATIONS:
            expanded.append(ABBREVIATIONS[lower])
            changed = True
        else:
            expanded.append(word)
    if changed:
        variants.append(" ".join(expanded))

    # --- Prefix match on last word ---
    if words:
        prefix_words = words[:-1] + [words[-1] + "*"]
        prefix_query = " ".join(prefix_words)
        if prefix_query != query:
            variants.append(prefix_query)

    # --- OR variant ---
    if len(words) > 1:
        or_query = " OR ".join(words)
        if or_query != query:
            variants.append(or_query)

    return variants
