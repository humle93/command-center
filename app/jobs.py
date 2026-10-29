import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "data", "center.db")

@contextmanager
def get_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA busy_timeout=15000")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def init_db_and_jobs():
    with get_db() as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS job_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_type TEXT NOT NULL,
                payload TEXT,
                status TEXT DEFAULT 'pending',
                locked_at TEXT,
                attempts INTEGER DEFAULT 0,
                last_error TEXT,
                created_at TEXT,
                completed_at TEXT
            );
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                action TEXT NOT NULL,
                autonomy_level TEXT DEFAULT 'safe',
                details TEXT,
                created_at TEXT
            );
        """)
        now = datetime.now(timezone.utc).isoformat()
        cur = db.execute("UPDATE job_queue SET status = 'pending', locked_at = NULL WHERE status = 'running'")
        if cur.rowcount > 0:
            db.execute("INSERT INTO audit_log (action, details, created_at) VALUES (?, ?, ?)",
                       ("zombie_reset", f"Nulstillede {cur.rowcount} hængende jobs ved opstart", now))

def enqueue_job(job_type: str, payload: str = "") -> int:
    now = datetime.now(timezone.utc).isoformat()
    with get_db() as db:
        cur = db.execute("INSERT INTO job_queue (job_type, payload, status, created_at) VALUES (?, ?, 'pending', ?)",
                         (job_type, payload, now))
        return cur.lastrowid
