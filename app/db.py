from __future__ import annotations

import sqlite3
from pathlib import Path

from app.config import settings

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS addresses (
  id TEXT PRIMARY KEY,
  address TEXT NOT NULL UNIQUE,
  local_part TEXT NOT NULL,
  domain TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS mails (
  id TEXT PRIMARY KEY,
  address TEXT NOT NULL,
  source TEXT,
  subject TEXT,
  text TEXT,
  html TEXT,
  raw TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_mails_address_created_at
ON mails(address, created_at DESC);
"""


def ensure_db_parent() -> None:
    settings.db_path.parent.mkdir(parents=True, exist_ok=True)


def get_conn() -> sqlite3.Connection:
    ensure_db_parent()
    conn = sqlite3.connect(settings.db_path, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout = 30000")
    return conn


def init_db() -> Path:
    ensure_db_parent()
    conn = get_conn()
    try:
        conn.executescript(SCHEMA_SQL)
        conn.commit()
    finally:
        conn.close()
    return settings.db_path
