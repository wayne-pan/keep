"""Web content memory tools: remember_web."""

from urllib.parse import urlparse

from mem.storage.database import get_db
from mem.storage.observations import add_observation as _add_obs
from mem.storage.synthesis import update_synthesis as _update_syn


def register_web_tools(mcp):
    @mcp.tool()
    def remember_web(
        url: str,
        title: str,
        content: str = None,
        tags: list[str] = None,
        project: str = None,
    ) -> str:
        """Store web content as a memory observation. Use after browsing or reading web pages.

        Automatically extracts the domain as a searchable entity and tags the source URL.
        Combines with existing memory dedup and merge logic.
        """
        if not url or not title:
            return "Error: url and title are required."

        domain = urlparse(url).netloc or url

        # Build concepts: user tags + domain-based tag for site-level recall
        concepts = list(tags or [])
        domain_tag = f"url:{domain}"
        if domain_tag not in concepts:
            concepts.append(domain_tag)

        # Structure narrative with source attribution
        narrative = f"Source: {url}\n\n{content}" if content else f"Source: {url}"

        db = get_db()
        obs_id = _add_obs(
            db,
            session_id="cli",
            project=project or "",
            obs_type="web",
            title=title,
            narrative=narrative,
            facts=[],
            concepts=concepts,
            files_read=[url],
            files_modified=[],
        )

        if obs_id == 0:
            return "Rejected by density gate (too similar to existing memory)."

        for topic in concepts:
            _update_syn(db, topic, [obs_id])

        return f"Remembered web content as #{obs_id} (from {domain})."
