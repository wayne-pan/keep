"""SQLite connection management and schema initialization.

Storage location: ~/.mind/memory.db
"""

import sqlite3
from pathlib import Path

MEM_DIR = Path.home() / ".mind"
DB_PATH = MEM_DIR / "memory.db"

SCHEMA_SQL = """
-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT    UNIQUE NOT NULL,
    project         TEXT,
    started_at      TEXT,
    started_epoch   INTEGER,
    ended_at        TEXT,
    ended_epoch     INTEGER,
    summary         TEXT,
    obs_count       INTEGER DEFAULT 0
);

-- Observations
CREATE TABLE IF NOT EXISTS observations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT,
    project         TEXT,
    type            TEXT    DEFAULT 'discovery',
    title           TEXT    NOT NULL,
    narrative       TEXT,
    facts           TEXT    DEFAULT '[]',
    concepts        TEXT    DEFAULT '[]',
    files_read      TEXT    DEFAULT '[]',
    files_modified  TEXT    DEFAULT '[]',
    summary         TEXT,
    content_hash    TEXT,
    relevance_count INTEGER DEFAULT 0,
    feedback_score  REAL    DEFAULT 0.0,
    created_at      TEXT,
    created_epoch   INTEGER
);

-- Synthesis (compiled truths)
CREATE TABLE IF NOT EXISTS synthesis (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    topic           TEXT    UNIQUE NOT NULL,
    truth           TEXT    NOT NULL,
    evidence_ids    TEXT    DEFAULT '[]',
    evidence_count  INTEGER DEFAULT 0,
    confidence      REAL    DEFAULT 0.5,
    first_seen      TEXT,
    last_updated    TEXT,
    last_epoch      INTEGER,
    updated_count   INTEGER DEFAULT 1
);

-- Timeline ordering
CREATE TABLE IF NOT EXISTS timeline (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    topic           TEXT,
    observation_id  INTEGER REFERENCES observations(id) ON DELETE CASCADE,
    position        INTEGER,
    created_epoch   INTEGER
);

-- Dream log
CREATE TABLE IF NOT EXISTS dream_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    operation       TEXT,
    details         TEXT,
    ran_at          TEXT,
    ran_epoch       INTEGER
);

-- Memory links (Hindsight-inspired observation relationships)
-- Temporal knowledge graph (MemPalace-inspired): valid_from/valid_to for time-scoped queries
CREATE TABLE IF NOT EXISTS memory_links (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id       INTEGER NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
    target_id       INTEGER NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
    link_type       TEXT    NOT NULL,
    strength        REAL    DEFAULT 1.0,
    created_epoch   INTEGER,
    valid_from      INTEGER,
    valid_to        INTEGER DEFAULT 9223372036854775807,
    UNIQUE(source_id, target_id, link_type)
);

-- Entity extraction (Hindsight-inspired entity resolution)
CREATE TABLE IF NOT EXISTS entities (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT    UNIQUE NOT NULL,
    entity_type     TEXT    NOT NULL,
    mention_count   INTEGER DEFAULT 1,
    first_seen      TEXT,
    last_seen       TEXT
);

CREATE TABLE IF NOT EXISTS entity_mentions (
    entity_id       INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    observation_id  INTEGER NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
    UNIQUE(entity_id, observation_id)
);

-- FTS5 virtual tables
CREATE VIRTUAL TABLE IF NOT EXISTS obs_fts
    USING fts5(title, narrative, facts, concepts, type, content=observations, content_rowid=id);

CREATE VIRTUAL TABLE IF NOT EXISTS synthesis_fts
    USING fts5(topic, truth, content=synthesis, content_rowid=id);

-- Auto-sync triggers: observations -> obs_fts
CREATE TRIGGER IF NOT EXISTS obs_fts_insert AFTER INSERT ON observations BEGIN
    INSERT INTO obs_fts(rowid, title, narrative, facts, concepts, type)
        VALUES (new.id, new.title, new.narrative, new.facts, new.concepts, new.type);
END;

CREATE TRIGGER IF NOT EXISTS obs_fts_delete AFTER DELETE ON observations BEGIN
    INSERT INTO obs_fts(obs_fts, rowid, title, narrative, facts, concepts, type)
        VALUES ('delete', old.id, old.title, old.narrative, old.facts, old.concepts, old.type);
END;

CREATE TRIGGER IF NOT EXISTS obs_fts_update AFTER UPDATE ON observations BEGIN
    INSERT INTO obs_fts(obs_fts, rowid, title, narrative, facts, concepts, type)
        VALUES ('delete', old.id, old.title, old.narrative, old.facts, old.concepts, old.type);
    INSERT INTO obs_fts(rowid, title, narrative, facts, concepts, type)
        VALUES (new.id, new.title, new.narrative, new.facts, new.concepts, new.type);
END;

-- Auto-sync triggers: synthesis -> synthesis_fts
CREATE TRIGGER IF NOT EXISTS synthesis_fts_insert AFTER INSERT ON synthesis BEGIN
    INSERT INTO synthesis_fts(rowid, topic, truth)
        VALUES (new.id, new.topic, new.truth);
END;

CREATE TRIGGER IF NOT EXISTS synthesis_fts_delete AFTER DELETE ON synthesis BEGIN
    INSERT INTO synthesis_fts(synthesis_fts, rowid, topic, truth)
        VALUES ('delete', old.id, old.topic, old.truth);
END;

CREATE TRIGGER IF NOT EXISTS synthesis_fts_update AFTER UPDATE ON synthesis BEGIN
    INSERT INTO synthesis_fts(synthesis_fts, rowid, topic, truth)
        VALUES ('delete', old.id, old.topic, old.truth);
    INSERT INTO synthesis_fts(rowid, topic, truth)
        VALUES (new.id, new.topic, new.truth);
END;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_obs_session_id  ON observations(session_id);
CREATE INDEX IF NOT EXISTS idx_obs_project     ON observations(project);
CREATE INDEX IF NOT EXISTS idx_obs_type        ON observations(type);
CREATE INDEX IF NOT EXISTS idx_obs_epoch_desc  ON observations(created_epoch DESC);
CREATE INDEX IF NOT EXISTS idx_timeline_topic  ON timeline(topic);
CREATE INDEX IF NOT EXISTS idx_links_source   ON memory_links(source_id);
CREATE INDEX IF NOT EXISTS idx_links_target   ON memory_links(target_id);
CREATE INDEX IF NOT EXISTS idx_links_type     ON memory_links(link_type);
CREATE INDEX IF NOT EXISTS idx_entities_name  ON entities(name);
CREATE INDEX IF NOT EXISTS idx_entmentions_obs ON entity_mentions(observation_id);
"""


def get_db() -> sqlite3.Connection:
    """Return a connection to the memory database, creating dirs if needed."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db(conn: sqlite3.Connection | None = None) -> None:
    """Create all tables, indexes, triggers, and FTS virtual tables."""
    own_conn = conn is None
    if own_conn:
        conn = get_db()
    try:
        conn.executescript(SCHEMA_SQL)
        # Safe migrations for existing databases
        _migrate(conn)
        _create_indexes_and_extra_tables(conn)
        conn.commit()
    finally:
        if own_conn:
            conn.close()


def _migrate(conn: sqlite3.Connection) -> None:
    """Add columns that may not exist in older schemas."""
    migrations = [
        ("ALTER TABLE synthesis ADD COLUMN conflict_flags TEXT DEFAULT '[]'", None),
        ("ALTER TABLE observations ADD COLUMN feedback_score REAL DEFAULT 0.0", None),
        ("ALTER TABLE observations ADD COLUMN hall TEXT DEFAULT NULL", None),
        ("ALTER TABLE memory_links ADD COLUMN valid_from INTEGER", None),
        (
            "ALTER TABLE memory_links ADD COLUMN valid_to INTEGER DEFAULT 9223372036854775807",
            None,
        ),
        ("ALTER TABLE observations ADD COLUMN summary TEXT", None),
        ("ALTER TABLE observations ADD COLUMN salience REAL DEFAULT 0.5", None),
        ("ALTER TABLE observations ADD COLUMN ease_factor REAL DEFAULT 2.5", None),
        ("ALTER TABLE observations ADD COLUMN next_review INTEGER", None),
        ("ALTER TABLE observations ADD COLUMN context_tags TEXT DEFAULT '{}'", None),
        ("ALTER TABLE observations ADD COLUMN verified INTEGER DEFAULT 0", None),
        ("ALTER TABLE observations ADD COLUMN pattern_id TEXT", None),
        ("ALTER TABLE observations ADD COLUMN lifecycle TEXT DEFAULT 'accepted'", None),
    ]
    for sql, _ in migrations:
        try:
            conn.execute(sql)
        except sqlite3.OperationalError:
            pass  # Column already exists


def _create_indexes_and_extra_tables(conn: sqlite3.Connection) -> None:
    """Create indexes and tables that may not exist in older schemas."""
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_obs_pattern_id ON observations(pattern_id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_obs_lifecycle ON observations(lifecycle)"
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS decision_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            observation_id  INTEGER NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
            from_state      TEXT NOT NULL,
            to_state        TEXT NOT NULL,
            reason          TEXT,
            decided_by      TEXT DEFAULT 'auto',
            decided_at      TEXT,
            decided_epoch   INTEGER
        )
        """
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_decision_obs ON decision_log(observation_id)"
    )
