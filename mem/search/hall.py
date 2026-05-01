"""Hall-type classification — MemPalace spatial organization pattern.

Maps observation types to 5 hall categories for structured retrieval:
  facts       → decision   (confirmed knowledge, architectural decisions)
  events      → milestone  (significant occurrences, completions)
  discoveries → discovery  (research findings, insights, patterns)
  preferences → preference (user preferences, coding style, conventions)
  advice      → solution   (recommended approaches, fixes, best practices)

Used in observations.hall column. Auto-assigned during add_observation().
"""

from __future__ import annotations

# Observation type → Hall mapping
HALL_MAP: dict[str, str] = {
    "decision":   "decision",
    "milestone":  "milestone",
    "discovery":  "discovery",
    "preference": "preference",
    "solution":   "solution",
    # Aliases — common type names mapped to hall categories
    "fact":       "decision",
    "event":      "milestone",
    "insight":    "discovery",
    "finding":    "discovery",
    "pattern":    "discovery",
    "convention": "preference",
    "style":      "preference",
    "advice":     "solution",
    "fix":        "solution",
    "workaround": "solution",
    "best_practice": "solution",
    "bug":        "discovery",
    "error":      "discovery",
    "architecture": "decision",
    "design":     "decision",
    "rule":       "decision",
}

ALL_HALLS = ["decision", "milestone", "discovery", "preference", "solution"]


def classify_hall(obs_type: str, title: str = "", narrative: str = "") -> str:
    """Classify an observation into a hall category.

    Uses explicit type mapping first, falls back to keyword heuristics.
    """
    # Direct mapping
    hall = HALL_MAP.get(obs_type.lower())
    if hall:
        return hall

    # Keyword heuristics from title + narrative
    text = f"{title} {narrative}".lower()

    if any(w in text for w in ("decided", "decision", "architecture", "design", "chosen", "adopted")):
        return "decision"
    if any(w in text for w in ("completed", "finished", "deployed", "released", "milestone", "shipped")):
        return "milestone"
    if any(w in text for w in ("prefer", "style", "convention", "always use", "never use", "习惯", "风格")):
        return "preference"
    if any(w in text for w in ("fix", "workaround", "solution", "resolved", "solved", "approach", "建议")):
        return "solution"

    # Default: discovery (most observations are findings)
    return "discovery"
