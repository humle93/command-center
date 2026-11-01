from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, PlainTextResponse
from fastapi import Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.middleware.gzip import GZipMiddleware
from contextlib import contextmanager, asynccontextmanager
from urllib.parse import urlparse
from datetime import datetime, timezone, timedelta, date
from bs4 import BeautifulSoup
from concurrent.futures import ThreadPoolExecutor
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger
import os
import shutil
import sqlite3
import requests
import ssl
import socket
import urllib.parse
import asyncio
import secrets
import csv
import io
import time
import re
import hashlib
import hmac
import json as jsonlib
import subprocess
import tarfile
import base64
import smtplib
from email.message import EmailMessage

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "data", "center.db")
STATIC_DIR = os.path.join(BASE_DIR, "static")

try:  # python-dotenv er i requirements, men appen skal ogsaa kunne starte uden
    from dotenv import load_dotenv as _load_dotenv_file
except Exception:
    _load_dotenv_file = None


def load_dotenv(path=None):
    """Laes .env FOER konfigurationen nedenfor - rigtige miljoevariabler vinder.

    Inline-kommentarer (`KEY=   # note`) fjernes ogsaa naar python-dotenv bruges, saa en
    kommentar fra .env-skabelonen ikke ender som vaerdi (fx et GITHUB_TOKEN bestaaende af tekst)."""
    path = path or os.path.join(os.path.dirname(BASE_DIR), ".env")
    if not os.path.exists(path):
        return
    entries = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        entries.append((key.strip(), val.strip(), val.split(" #")[0].strip()))
    if _load_dotenv_file is not None:
        _load_dotenv_file(path, override=False)
    for key, raw, cleaned in entries:
        current = os.environ.get(key)
        if current is None:
            os.environ[key] = cleaned            # ikke sat (fallback uden python-dotenv)
        elif current.strip() == raw:
            os.environ[key] = cleaned            # python-dotenv tog inline-kommentaren med


load_dotenv()

# --- Konfiguration via miljoevariabler / .env ---
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()     # GitHub-token: opdatering fra GitHub
GITHUB_REPO = os.environ.get("GITHUB_REPO", "humle93/command-center").strip()
AIMLAPI_KEY = os.environ.get("AIMLAPI_KEY", "").strip()      # AI-artikelgenerator (gemini via aimlapi)
AI_MODEL = os.environ.get("AI_MODEL", "google/gemini-3-8-flash")
WP_URL = os.environ.get("WP_URL", "").strip()                # fx https://steamgears.eu
WP_USER = os.environ.get("WP_USER", "").strip()
WP_APP_PASSWORD = os.environ.get("WP_APP_PASSWORD", "").strip()
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
SERPAPI_KEY = os.environ.get("SERPAPI_KEY", "").strip()
TRACK_DOMAIN = os.environ.get("TRACK_DOMAIN", "steamgears.eu").strip()
SSL_WARN_DAYS = int(os.environ.get("SSL_WARN_DAYS", "30"))
LINKCHECK_LIMIT = int(os.environ.get("LINKCHECK_LIMIT", "25"))
PSI_API_KEY = os.environ.get("PSI_API_KEY", "").strip()   # Google PageSpeed API (gratis noegle)

# --- Alarmer: kanaler (v7.12) ---
# Alarmer sendes aldrig inline: de skrives i alert_outbox og leveres af et job med backoff.
# Kilder: smtplib (465 = implicit TLS, 587 = STARTTLS), ntfy publish-API (Title/Priority/Tags)
# og Standard Webhooks (webhook-id/-timestamp/-signature, HMAC-SHA256 over "id.timestamp.body").
SMTP_HOST = os.environ.get("SMTP_HOST", "").strip()
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587") or 587)
SMTP_USER = os.environ.get("SMTP_USER", "").strip()
SMTP_PASS = os.environ.get("SMTP_PASS", "").strip()
SMTP_FROM = os.environ.get("SMTP_FROM", "").strip() or SMTP_USER
SMTP_TO = os.environ.get("SMTP_TO", "").strip()
SMTP_TLS = os.environ.get("SMTP_TLS", "starttls").strip().lower()   # starttls | ssl | none
NTFY_URL = os.environ.get("NTFY_URL", "https://ntfy.sh").strip().rstrip("/")
NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "").strip()
NTFY_TOKEN = os.environ.get("NTFY_TOKEN", "").strip()
ALERT_WEBHOOK_URL = os.environ.get("ALERT_WEBHOOK_URL", "").strip()
ALERT_WEBHOOK_SECRET = os.environ.get("ALERT_WEBHOOK_SECRET", "").strip()
ALERT_MIN_SEVERITY = os.environ.get("ALERT_MIN_SEVERITY", "info").strip().lower()
ALERT_QUIET_HOURS = os.environ.get("ALERT_QUIET_HOURS", "").strip()   # fx "23-7"; tom = slaaet fra
ALERT_DEDUPE_MINUTES = int(os.environ.get("ALERT_DEDUPE_MINUTES", "180") or 180)

APP_VERSION = "7.13.2"

# --- Nyheder: skrives ved opstart (skaerm + app/data/startup.log) og vises paa login-siden ---
NEWEST = [
    ("7.13.2", "Agent + skill i .agents/ og sidste doede variabler fjernet (sitemap_missing, _up, result)"),
    ("7.13.1", "Oprydning: doede importer og variabler fjernet, Juno-tabelrester droppes naar de er tomme"),
    ("7.13.0", "Login viser IP og en koerselsrapport; opstart skriver version og nyheder"),
    ("7.12.0", "Alarmer til e-mail, ntfy og signeret webhook - i koe med dedupe og stille timer"),
    ("7.11.0", "Brugere med adgangskode, GitHub-opdatering med genstart, nginx/systemd"),
]
NEWEST_LINE = "Login: IP + sidste koersel i UI'et - opstart printer version og nyheder"


def startup_banner(host: str = "", port: int | None = None) -> list:
    """Linjer der vises ved opstart - samme indhold paa skaermen, i loggen og i /health."""
    lines = [f"Command Center v{APP_VERSION}"]
    for ver, text in NEWEST[:3]:
        lines.append(f"  nyhed {ver}: {text}")
    if host:
        lines.append(f"  lytter paa {host}" + (f":{port}" if port else ""))
    return lines


def log_startup(host: str = "", port: int | None = None) -> str:
    """Skriv version + nyheder ved opstart (stdout, app/data/startup.log og settings)."""
    text = "\n".join(startup_banner(host, port))
    print("[cc] " + text.replace("\n", "\n[cc] "), flush=True)
    try:
        os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        with open(os.path.join(os.path.dirname(DB_PATH), "startup.log"), "a") as f:
            f.write(f"{now_iso()} {text}\n\n")
        with get_db() as db:
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_start', ?)", (now_iso(),))
    except Exception as e:
        print("[cc] kunne ikke skrive startup-log:", repr(e), flush=True)
    return text
app = FastAPI(title="Command Center Engine", version=APP_VERSION)
# Git does not keep empty folders, so a fresh clone has no app/static: create it or startup fails.
os.makedirs(STATIC_DIR, exist_ok=True)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))
scheduler = AsyncIOScheduler(timezone="Europe/Copenhagen")
executor = ThreadPoolExecutor(max_workers=8)



_WAL_SET = False


@contextmanager
def get_db():
    global _WAL_SET
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=15)  # timeout = busy timeout (15 s)
    conn.row_factory = sqlite3.Row
    if not _WAL_SET:
        # WAL is a property of the database file: setting it once per process is enough.
        conn.execute("PRAGMA journal_mode=WAL")
        _WAL_SET = True
    conn.execute("PRAGMA synchronous=NORMAL")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    with get_db() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS domains (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT UNIQUE NOT NULL,
            status TEXT DEFAULT 'Ukendt',
            response_time TEXT DEFAULT '-',
            ssl_days TEXT DEFAULT '-',
            last_checked TEXT,
            last_error TEXT
        );
        CREATE TABLE IF NOT EXISTS check_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            domain_id INTEGER NOT NULL,
            status TEXT,
            response_time INTEGER,
            ssl_days INTEGER,
            checked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS competitors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            crawled_info TEXT DEFAULT 'Ikke scannet endnu',
            status TEXT DEFAULT 'Aktiv',
            found_at TEXT
        );
        CREATE TABLE IF NOT EXISTS articles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            keyword TEXT,
            content TEXT,
            status TEXT DEFAULT 'Kladde',
            source TEXT DEFAULT 'skabelon',
            wp_link TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS linkcheck (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            result TEXT,
            checked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS socialqueue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            platform TEXT NOT NULL,
            message TEXT NOT NULL,
            status TEXT DEFAULT 'Klar i ko',
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS keywords (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            keyword TEXT UNIQUE NOT NULL,
            position INTEGER,
            target_url TEXT,
            checked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS alarms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            message TEXT NOT NULL,
            severity TEXT DEFAULT 'info',
            resolved INTEGER DEFAULT 0,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS seopages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER,
            url TEXT NOT NULL,
            http_status INTEGER,
            title TEXT,
            meta_len INTEGER,
            h1 TEXT,
            words INTEGER,
            score INTEGER,
            issues TEXT,
            crawled_at TEXT
        );
        CREATE TABLE IF NOT EXISTS crawl_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            host TEXT,
            robots_ok INTEGER DEFAULT 0,
            sitemap_ok INTEGER DEFAULT 0,
            sitemap_urls INTEGER DEFAULT 0,
            pages INTEGER DEFAULT 0,
            avg_score INTEGER,
            started_at TEXT,
            finished_at TEXT
        );
        CREATE TABLE IF NOT EXISTS monitors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'contains',
            expected TEXT NOT NULL,
            last_status TEXT DEFAULT 'Ikke tjekket',
            last_result TEXT,
            last_checked TEXT
        );
        CREATE TABLE IF NOT EXISTS ai_visibility (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question TEXT NOT NULL,
            mention_found INTEGER DEFAULT 0,
            snippet TEXT,
            answer TEXT,
            checked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS health_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            host TEXT,
            avg_score INTEGER,
            pages INTEGER,
            run_id INTEGER,
            checked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS internal_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_url TEXT,
            to_url TEXT,
            anchor TEXT,
            reason TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS keyword_ideas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            keyword TEXT,
            idea TEXT,
            source TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS content_gap (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            keyword TEXT NOT NULL,
            stats_json TEXT,
            top_titles TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS outreach (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL,
            source_url TEXT,
            found_at TEXT,
            UNIQUE(email, source_url)
        );
        CREATE TABLE IF NOT EXISTS backlink_prospects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            keyword TEXT NOT NULL,
            site TEXT,
            url TEXT,
            type TEXT,
            email TEXT,
            draft TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS visibility (
            day TEXT PRIMARY KEY,
            score REAL
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        CREATE TABLE IF NOT EXISTS keyword_difficulty (
            keyword TEXT PRIMARY KEY,
            difficulty INTEGER,
            domains INTEGER,
            authority INTEGER,
            ads INTEGER,
            avg_words INTEGER,
            top_domains TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            created_at TEXT,
            last_seen TEXT,
            expires_at TEXT,
            ip TEXT
        );
        CREATE TABLE IF NOT EXISTS login_attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT,
            ip TEXT,
            ok INTEGER DEFAULT 0,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS alert_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT,
            alarm_id INTEGER,
            dedupe_key TEXT,
            channel TEXT NOT NULL,
            severity TEXT,
            subject TEXT,
            body TEXT,
            payload TEXT,
            attempts INTEGER DEFAULT 0,
            next_attempt_at TEXT,
            state TEXT DEFAULT 'pending',
            last_error TEXT,
            created_at TEXT,
            sent_at TEXT
        );
        """)


def _safe(fn):
    """Koer en init-funktion uden at lade importen crashe (opstart-stabilitet)."""
    try:
        fn()
    except Exception as e:
        print("[cc] init-fejl (proever igen om 5s):", repr(e), flush=True)
        import time as _t
        _t.sleep(5)
        try:
            fn()
        except Exception as e2:
            print("[cc] init-fejl fortsaetter (app starter alligevel):", repr(e2), flush=True)


_safe(init_db)


def migrate_db():
    with get_db() as db:
        for table, want in {
            "articles": ["meta_title", "meta_desc"],
            "seopages": ["content_hash", "redirects"],
            "crawl_runs": ["sitemap_broken", "sitemap_missing"],
            "monitors": ["last_value"],
            "users": ["last_login_ip", "last_login_at"],
            "sessions": ["ip"],
        }.items():
            existing = [r[1] for r in db.execute(f"PRAGMA table_info({table})").fetchall()]
            for c in want:
                if c not in existing:
                    db.execute(f"ALTER TABLE {table} ADD COLUMN {c} TEXT")
        db.execute("""CREATE TABLE IF NOT EXISTS login_attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT, ip TEXT, ok INTEGER DEFAULT 0, created_at TEXT
        )""")
        # v7.13: ryd tabelrester fra Juno-tiden - kun hvis de er tomme, saa data aldrig gaar tabt.
        for retired in ("drift", "gsc_daily", "gsc_queries"):
            try:
                exists = db.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (retired,)
                ).fetchone()
                if exists and db.execute(f"SELECT COUNT(*) FROM {retired}").fetchone()[0] == 0:
                    db.execute(f"DROP TABLE {retired}")
            except Exception:
                pass
        # v7.12: eksisterende installationer faar outbox-tabellen her (init_db rammer kun nye DB'er).
        db.execute("""CREATE TABLE IF NOT EXISTS alert_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT, alarm_id INTEGER, dedupe_key TEXT,
            channel TEXT NOT NULL, severity TEXT, subject TEXT, body TEXT, payload TEXT,
            attempts INTEGER DEFAULT 0, next_attempt_at TEXT, state TEXT DEFAULT 'pending',
            last_error TEXT, created_at TEXT, sent_at TEXT
        )""")


_safe(migrate_db)


def create_indexes():
    with get_db() as db:
        for stmt in [
            "CREATE INDEX IF NOT EXISTS idx_seopages_run ON seopages(run_id)",
            "CREATE INDEX IF NOT EXISTS idx_alarms_open ON alarms(resolved, id)",
            "CREATE INDEX IF NOT EXISTS idx_hist_domain ON check_history(domain_id, id)",
            "CREATE INDEX IF NOT EXISTS idx_health_time ON health_history(checked_at)",
            "CREATE INDEX IF NOT EXISTS idx_crawl_time ON crawl_runs(started_at)",
            "CREATE INDEX IF NOT EXISTS kw_ideas_kw ON keyword_ideas(keyword)",
            "CREATE INDEX IF NOT EXISTS idx_outbox_due ON alert_outbox(state, next_attempt_at)",
            "CREATE INDEX IF NOT EXISTS idx_outbox_dedupe ON alert_outbox(dedupe_key, created_at)",
        ]:
            db.execute(stmt)
        db.execute("ANALYZE")


_safe(create_indexes)


MODULES = ["domains", "keywords", "ai", "monitors", "social", "links", "spy", "wp_push", "telegram", "growth", "autopilot"]


_MODULE_CACHE = {"at": 0.0, "states": {}}


def modules_state() -> dict:
    """On/off for every module from one query, cached for 10 s (cleared by set_module)."""
    if time.time() - _MODULE_CACHE["at"] > 10:
        try:
            with get_db() as db:
                rows = db.execute("SELECT key, value FROM settings WHERE key LIKE 'module\\_%' ESCAPE '\\'").fetchall()
            stored = {r["key"][len("module_"):]: r["value"] == "on" for r in rows}
        except Exception:
            stored = {}
        _MODULE_CACHE.update(at=time.time(), states={m: stored.get(m, True) for m in MODULES})
    return _MODULE_CACHE["states"]


def module_on(name: str) -> bool:
    return modules_state().get(name, True)


def set_module(name: str, state: str):
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?,?)", ("module_" + name, state))
    _MODULE_CACHE["at"] = 0.0


def cleanup_old_data():
    """Daglig oprydning: gamle maalinger rulles af, DB holdes sund.

    Tidspunkter gemmes som lokal ISO-tid (now_iso), saa cutoff skal regnes i Python -
    SQLite's datetime('now') er UTC og rammer derfor forkert."""
    now = datetime.now()

    def cutoff(days):
        return (now - timedelta(days=days)).isoformat(timespec="seconds")

    with get_db() as db:
        db.execute("DELETE FROM check_history WHERE checked_at < ?", (cutoff(90),))
        db.execute("DELETE FROM alarms WHERE resolved=1 AND created_at < ?", (cutoff(30),))
        db.execute("DELETE FROM health_history WHERE checked_at < ?", (cutoff(180),))
        db.execute("DELETE FROM keyword_ideas WHERE created_at < ?", (cutoff(180),))


# ---------- Auth: brugere og sessioner ----------
# Dashboardet har rigtige brugere: brugernavn + adgangskode (PBKDF2-SHA256 med salt pr. bruger).
# Foerste besoeg opretter den foerste bruger via /setup - der er ingen delt token i .env.
SESSION_COOKIE = "cc_session"
SESSION_MAX_AGE = 60 * 60 * 24 * 30        # 30 dage
PBKDF2_ITERATIONS = 240_000
MIN_PASSWORD_LEN = 8
_USERNAME_RE = re.compile(r"[A-Za-z0-9._-]{3,32}")

_LOGIN_FAILS: dict = {}  # IP -> (antal fejl, laas-til)
_LOGIN_MAX_FAILS = 5
_LOGIN_LOCK_SECONDS = 600


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", (password or "").encode(), salt, PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, iterations, salt_hex, digest_hex = (stored or "").split("$")
        if algo != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac("sha256", (password or "").encode(), bytes.fromhex(salt_hex), int(iterations))
        return hmac.compare_digest(digest.hex(), digest_hex)
    except Exception:
        return False


def _session_key(sid: str) -> str:
    """Sessioner gemmes som sha256(id), saa en kopi af databasen ikke giver adgang."""
    return hashlib.sha256((sid or "").encode()).hexdigest()


def user_count() -> int:
    try:
        with get_db() as db:
            return db.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]
    except Exception:
        return 0


def create_user(username: str, password: str) -> int:
    username = (username or "").strip()
    if not _USERNAME_RE.fullmatch(username):
        raise ValueError("Brugernavn: 3-32 tegn (a-z, 0-9, punktum, bindestreg, underscore)")
    if len(password or "") < MIN_PASSWORD_LEN:
        raise ValueError(f"Adgangskoden skal vaere mindst {MIN_PASSWORD_LEN} tegn")
    with get_db() as db:
        cur = db.execute("INSERT INTO users (username, password_hash, created_at) VALUES (?,?,?)",
                         (username, hash_password(password), now_iso()))
        return cur.lastrowid


def client_ip(request: Request) -> str:
    """Klientens IP. uvicorn --proxy-headers saetter client.host ud fra X-Forwarded-For;
    vi laeser headeren selv som reserve (foerste hop) og falder tilbage til socket-adressen."""
    fwd = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    host = request.client.host if request.client else ""
    return (fwd or host or "ukendt")[:64]


def record_login(ip: str, username: str, ok: bool):
    """Log hvert login-forsoeg (ok/fejl) med IP - vist under Brugere og brugt i koerselsrapporten."""
    try:
        with get_db() as db:
            db.execute("INSERT INTO login_attempts (username, ip, ok, created_at) VALUES (?,?,?,?)",
                       ((username or "")[:64], (ip or "")[:64], 1 if ok else 0, now_iso()))
            db.execute("DELETE FROM login_attempts WHERE created_at < ?",
                       ((datetime.now() - timedelta(days=30)).isoformat(timespec="seconds"),))
    except Exception:
        pass


def start_session(user_id: int, ip: str = "") -> str:
    sid = secrets.token_urlsafe(32)
    expires = (datetime.now() + timedelta(seconds=SESSION_MAX_AGE)).isoformat(timespec="seconds")
    with get_db() as db:
        db.execute("DELETE FROM sessions WHERE expires_at < ?", (now_iso(),))
        db.execute("INSERT INTO sessions (id, user_id, created_at, last_seen, expires_at, ip) VALUES (?,?,?,?,?,?)",
                   (_session_key(sid), user_id, now_iso(), now_iso(), expires, ip or ""))
    return sid


def last_run_report() -> dict:
    """Kort, ikke-foelsom status til login-siden: version, sidste koersel og taellinger.
    Ingen alarmtekster eller brugernavne - siden er offentlig."""
    report = {"version": APP_VERSION, "commit": "", "last_start": "", "generated": now_iso(),
              "alarms_open": 0, "alarms_critical": 0, "domains": 0, "keywords": 0, "monitors": 0,
              "last_domain_check": "", "last_crawl": "", "last_login": "", "db_mb": None,
              "newest": [f"{v}: {t}" for v, t in NEWEST[:2]]}
    try:
        report["commit"] = deployed_commit()
    except Exception:
        pass
    try:
        with get_db() as db:
            def one(sql, *args):
                row = db.execute(sql, args).fetchone()
                return (row[0] if row else None)
            report["alarms_open"] = one("SELECT COUNT(*) FROM alarms WHERE resolved=0") or 0
            report["alarms_critical"] = one("SELECT COUNT(*) FROM alarms WHERE resolved=0 AND severity='kritisk'") or 0
            report["domains"] = one("SELECT COUNT(*) FROM domains") or 0
            report["keywords"] = one("SELECT COUNT(*) FROM keywords") or 0
            report["monitors"] = one("SELECT COUNT(*) FROM monitors") or 0
            report["last_domain_check"] = one("SELECT MAX(last_checked) FROM domains") or ""
            report["last_crawl"] = one("SELECT MAX(started_at) FROM crawl_runs") or ""
            report["last_login"] = one("SELECT MAX(created_at) FROM login_attempts WHERE ok=1") or ""
            row = db.execute("SELECT value FROM settings WHERE key='last_start'").fetchone()
            report["last_start"] = row["value"] if row and row["value"] else ""
        report["db_mb"] = round(os.path.getsize(DB_PATH) / 1048576, 1) if os.path.exists(DB_PATH) else None
    except Exception:
        pass
    return report


def end_session(sid: str):
    if sid:
        with get_db() as db:
            db.execute("DELETE FROM sessions WHERE id=?", (_session_key(sid),))


def session_redirect(request: Request, sid: str) -> RedirectResponse:
    resp = RedirectResponse("/", status_code=303)
    resp.set_cookie(SESSION_COOKIE, sid, httponly=True, samesite="lax",
                    max_age=SESSION_MAX_AGE, secure=request.url.scheme == "https")
    return resp


def current_user(request: Request):
    """Brugeren bag session-cookien (eller None)."""
    sid = request.cookies.get(SESSION_COOKIE) or ""
    if not sid:
        return None
    key = _session_key(sid)
    try:
        with get_db() as db:
            row = db.execute(
                "SELECT u.id, u.username, s.expires_at FROM sessions s "
                "JOIN users u ON u.id = s.user_id WHERE s.id=?", (key,)
            ).fetchone()
            if not row:
                return None
            if (row["expires_at"] or "") < now_iso():
                db.execute("DELETE FROM sessions WHERE id=?", (key,))
                return None
            db.execute("UPDATE sessions SET last_seen=? WHERE id=?", (now_iso(), key))
            return {"id": row["id"], "username": row["username"]}
    except Exception:
        return None


def is_authed(request: Request) -> bool:
    """Er kaldet lavet af en logget-ind bruger?"""
    return bool(getattr(request.state, "user", None))


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    path = request.url.path
    host = request.client.host if request.client else ""
    # scheme er allerede X-Forwarded-Proto-resolveret af uvicorn/starlette.
    request.state.insecure = request.url.scheme == "http" and host not in ("127.0.0.1", "::1", "localhost")
    request.state.user = current_user(request)
    if any(path.startswith(p) for p in ("/login", "/setup", "/health", "/static")):
        return await call_next(request)
    if request.state.user:
        return await call_next(request)
    if path.startswith("/api/"):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return RedirectResponse("/setup" if user_count() == 0 else "/login", status_code=303)


@app.get("/setup", response_class=HTMLResponse)
async def setup_page(request: Request):
    if user_count() > 0:
        return RedirectResponse("/login", status_code=303)
    return templates.TemplateResponse("login.html", {"request": request, "mode": "setup", "error": "", "username": "",
                                                     "report": last_run_report(), "client_ip": client_ip(request),
                                                     "app_version": APP_VERSION})


@app.post("/setup")
async def setup_user(request: Request):
    """Foerste start: opret den foerste bruger (kun naar der ikke findes brugere)."""
    if user_count() > 0:
        return RedirectResponse("/login", status_code=303)
    form = await request.form()
    username = (form.get("username") or "").strip()
    password = form.get("password") or ""
    confirm = form.get("confirm") or ""
    err = ""
    user_id = None
    if password != confirm:
        err = "De to adgangskoder er ikke ens"
    else:
        try:
            user_id = create_user(username, password)
        except ValueError as e:
            err = str(e)
        except sqlite3.IntegrityError:
            err = "Brugernavnet er allerede taget"
    if not user_id:
        return templates.TemplateResponse("login.html", {"request": request, "mode": "setup", "username": username,
                                                         "error": err, "report": last_run_report(),
                                                         "client_ip": client_ip(request),
                                                         "app_version": APP_VERSION}, status_code=400)
    ip = client_ip(request)
    with get_db() as db:
        add_alarm(db, "brugere", f"Foerste bruger '{username}' oprettet", "info")
        db.execute("UPDATE users SET last_login_ip=?, last_login_at=? WHERE id=?", (ip, now_iso(), user_id))
    record_login(ip, username, True)
    return session_redirect(request, start_session(user_id, ip))


@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if user_count() == 0:
        return RedirectResponse("/setup", status_code=303)
    return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "error": "", "username": "",
                                                     "report": last_run_report(), "client_ip": client_ip(request),
                                                     "app_version": APP_VERSION})


@app.post("/login")
async def login(request: Request):
    ip = client_ip(request)
    now = time.time()
    fails, locked_until = _LOGIN_FAILS.get(ip, (0, 0.0))
    if locked_until > now:
        return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "username": "",
                                                         "error": "For mange fejlede logins - proev igen om " + str(int(locked_until - now)) + " sek."}, status_code=429)
    form = await request.form()
    username = (form.get("username") or "").strip()
    password = form.get("password") or ""
    with get_db() as db:
        user = db.execute("SELECT id, username, password_hash FROM users WHERE username=?", (username,)).fetchone()
    if user and verify_password(password, user["password_hash"]):
        _LOGIN_FAILS.pop(ip, None)
        with get_db() as db:
            db.execute("UPDATE users SET last_login_ip=?, last_login_at=? WHERE id=?", (ip, now_iso(), user["id"]))
        record_login(ip, username, True)
        return session_redirect(request, start_session(user["id"], ip))
    record_login(ip, username, False)
    fails += 1
    _LOGIN_FAILS[ip] = (0, now + _LOGIN_LOCK_SECONDS) if fails >= _LOGIN_MAX_FAILS else (fails, locked_until)
    if len(_LOGIN_FAILS) > 2000:  # undgaa at listen vokser ubegraenset
        _LOGIN_FAILS.clear()
    return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "username": username,
                                                     "error": "Forkert brugernavn eller adgangskode", "ip": ip,
                                                     "report": last_run_report(), "client_ip": ip,
                                                     "app_version": APP_VERSION}, status_code=401)


@app.get("/logout")
async def logout(request: Request):
    end_session(request.cookies.get(SESSION_COOKIE) or "")
    resp = RedirectResponse("/login", status_code=303)
    resp.delete_cookie(SESSION_COOKIE)
    return resp


@app.post("/users/add")
async def users_add(username: str = Form(...), password: str = Form(...)):
    try:
        create_user(username, password)
    except ValueError as e:
        with get_db() as db:
            add_alarm(db, "brugere", f"Kunne ikke oprette bruger '{username}': {str(e)[:120]}", "advarsel")
    except sqlite3.IntegrityError:
        with get_db() as db:
            add_alarm(db, "brugere", f"Kunne ikke oprette bruger '{username}': navnet er optaget", "advarsel")
    return RedirectResponse("/", status_code=303)


@app.post("/users/delete")
async def users_delete(request: Request, id: int = Form(...)):
    me = getattr(request.state, "user", None)
    with get_db() as db:
        total = db.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]
        if total <= 1:
            add_alarm(db, "brugere", "Den sidste bruger kan ikke slettes - opret en ny bruger foerst", "advarsel")
            return RedirectResponse("/", status_code=303)
        db.execute("DELETE FROM sessions WHERE user_id=?", (id,))
        db.execute("DELETE FROM users WHERE id=?", (id,))
    if me and me["id"] == id:
        resp = RedirectResponse("/login", status_code=303)
        resp.delete_cookie(SESSION_COOKIE)
        return resp
    return RedirectResponse("/", status_code=303)


@app.post("/users/password")
async def users_password(request: Request, current: str = Form(...), new: str = Form(...), confirm: str = Form("")):
    me = getattr(request.state, "user", None)
    if not me:
        return RedirectResponse("/login", status_code=303)
    with get_db() as db:
        row = db.execute("SELECT password_hash FROM users WHERE id=?", (me["id"],)).fetchone()
        if not row or not verify_password(current, row["password_hash"]):
            add_alarm(db, "brugere", f"Fejlet adgangskode-skift for '{me['username']}'", "info")
            return RedirectResponse("/", status_code=303)
        if new != confirm or len(new) < MIN_PASSWORD_LEN:
            add_alarm(db, "brugere", f"Adgangskode-skift afvist for '{me['username']}': mindst {MIN_PASSWORD_LEN} tegn og ens i begge felter", "info")
            return RedirectResponse("/", status_code=303)
        db.execute("UPDATE users SET password_hash=? WHERE id=?", (hash_password(new), me["id"]))
        # Log de andre sessioner ud, behold denne.
        db.execute("DELETE FROM sessions WHERE user_id=? AND id<>?",
                   (me["id"], _session_key(request.cookies.get(SESSION_COOKIE) or "")))
    return RedirectResponse("/", status_code=303)


# ---------- Hjaelpere ----------
def normalize_url(url: str) -> str:
    url = (url or "").strip()
    if not url:
        raise ValueError("URL mangler")
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    parsed = urlparse(url)
    if not parsed.netloc or "." not in parsed.netloc:
        raise ValueError("Ugyldig URL")
    return url.rstrip("/")


# ---------- API-budget (v8-plan): maanedligt loft for betalte API'er ----------
# Taeller hvert kald til SerpAPI og AI (aimlapi) pr. kalendermaaned og stopper dem ved loftet,
# saa en loekke eller fejl aldrig kan braende kreditter af. 0 = intet loft.
API_BUDGETS = {
    "serpapi": ("serpapi.com", int(os.environ.get("SERPAPI_MONTHLY_LIMIT", "1000") or 0)),
    "ai": ("aimlapi.com", int(os.environ.get("AI_MONTHLY_LIMIT", "3000") or 0)),
}


class BudgetExceeded(requests.RequestException):
    """Kaldet blev ikke sendt: maanedens API-budget er brugt."""


def budget_service(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    for service, (domain, _limit) in API_BUDGETS.items():
        if host == domain or host.endswith("." + domain):
            return service
    return ""


def budget_usage() -> dict:
    """{service: (brugt, loft)} for indevaerende maaned."""
    month = datetime.now().strftime("%Y-%m")
    with get_db() as db:
        rows = {r["key"]: int(r["value"]) for r in db.execute(
            "SELECT key, value FROM settings WHERE key LIKE ?", (f"budget_{month}_%",)
        ).fetchall()}
    return {s: (rows.get(f"budget_{month}_{s}", 0), limit) for s, (_d, limit) in API_BUDGETS.items()}


def budget_spend(service: str):
    """Taeller et kald; kaster BudgetExceeded hvis loftet er naaet. Alarmerer en gang ved 80 % og 100 %."""
    limit = API_BUDGETS[service][1]
    month = datetime.now().strftime("%Y-%m")
    key = f"budget_{month}_{service}"
    with get_db() as db:
        row = db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        used = int(row["value"]) if row else 0
        if limit and used >= limit:
            raise BudgetExceeded(f"{service}: maanedens budget paa {limit} kald er brugt (saet {service.upper()}_MONTHLY_LIMIT i .env)")
        used += 1
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (key, str(used)))
        if limit and used == int(limit * 0.8):
            add_alarm(db, "budget", f"{service}: 80 % af maanedens API-budget brugt ({used}/{limit})", "advarsel")
        if limit and used == limit:
            add_alarm(db, "budget", f"{service}: maanedens API-budget er brugt ({limit} kald) - kald stoppes til den 1.", "kritisk")


class BudgetAdapter(requests.adapters.HTTPAdapter):
    def send(self, request, **kwargs):
        service = budget_service(request.url)
        if service:
            budget_spend(service)
        return super().send(request, **kwargs)


HTTP = requests.Session()
_adapter = BudgetAdapter(pool_connections=10, pool_maxsize=20)
HTTP.mount("https://", _adapter)
HTTP.mount("http://", _adapter)


def safe_request(url: str, timeout: int = 6):
    return HTTP.get(
        url,
        timeout=timeout,
        allow_redirects=True,
        headers={"User-Agent": "Mozilla/5.0 CommandCenter/7.4"},
    )


def now_iso():
    return datetime.now().isoformat(timespec="seconds")


def add_alarm(db, type_: str, message: str, severity: str = "info"):
    cur = db.execute(
        "INSERT INTO alarms (type, message, severity, created_at) VALUES (?, ?, ?, ?)",
        (type_, message, severity, now_iso()),
    )
    # Ingen netvaerkskald her: alarmer koeres i alert_outbox og leveres af et job med backoff,
    # saa en langsom SMTP/HTTP-modtager eller ntfy ikke blokerer requesten (v7.12).
    try:
        enqueue_alert(db, type_, message, severity, alarm_id=cur.lastrowid)
    except Exception as e:
        print("[cc] kunne ikke koere alarm:", repr(e), flush=True)


def notify_telegram(text: str):
    if not (TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID):
        return False
    try:
        HTTP.post(
            f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
            json={"chat_id": TELEGRAM_CHAT_ID, "text": text},
            timeout=8,
        )
        return True
    except Exception:
        return False


# ---------- Alarmer: kanaler, outbox, dedupe (v7.12) ----------
SEVERITY_RANK = {"info": 1, "advarsel": 2, "warning": 2, "kritisk": 3, "critical": 3}
ALERT_BACKOFF = [30, 120, 600, 3600]   # sekunder foer forsoeg 2..5 - derefter 'failed'
CHANNEL_LABELS = {"telegram": "Telegram", "email": "E-mail", "ntfy": "ntfy", "webhook": "Webhook"}


def alert_channels() -> dict:
    """Hvilke kanaler er konfigureret lige nu (laeses ved kald, saa .env-aendringer virker)."""
    try:
        telegram_on = module_on("telegram")
    except Exception:
        telegram_on = True
    return {
        "telegram": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID) and telegram_on,
        "email": bool(SMTP_HOST and SMTP_TO and SMTP_FROM),
        "ntfy": bool(NTFY_URL and NTFY_TOPIC),
        "webhook": bool(ALERT_WEBHOOK_URL),
    }


def alert_severity_rank(severity: str) -> int:
    return SEVERITY_RANK.get((severity or "").strip().lower(), 1)


def _parse_quiet_hours(spec: str):
    m = re.match(r"^\s*(\d{1,2})\s*-\s*(\d{1,2})\s*$", spec or "")
    if not m:
        return None
    start, end = int(m.group(1)), int(m.group(2))
    if not (0 <= start <= 23 and 0 <= end <= 24):
        return None
    return start, end


def in_quiet_hours(moment: datetime | None = None) -> bool:
    window = _parse_quiet_hours(ALERT_QUIET_HOURS)
    if not window:
        return False
    hour = (moment or datetime.now()).hour
    start, end = window
    if start == end:
        return False
    if start < end:
        return start <= hour < end
    return hour >= start or hour < end          # fx 23-7 gaar over midnat


def quiet_hours_end_iso(moment: datetime | None = None) -> str:
    """Naeste tidspunkt hvor stille timer slutter - saa en udskudt alarm ikke tabes."""
    moment = moment or datetime.now()
    window = _parse_quiet_hours(ALERT_QUIET_HOURS) or (0, 0)
    end = window[1] % 24
    target = moment.replace(hour=end, minute=0, second=0, microsecond=0)
    if target <= moment:
        target += timedelta(days=1)
    return target.isoformat(timespec="seconds")


def alert_dedupe_key(type_: str, message: str) -> str:
    return hashlib.sha256(f"{type_}|{message}".strip().lower().encode()).hexdigest()[:32]


def enqueue_alert(db, type_: str, message: str, severity: str = "info",
                  alarm_id: int | None = None, force: bool = False) -> list:
    """Skriv alarmen i outboxen paa hver konfigureret kanal. Returnerer de koerte kanaler."""
    if not force and alert_severity_rank(severity) < alert_severity_rank(ALERT_MIN_SEVERITY):
        return []
    key = alert_dedupe_key(type_, message)
    if not force:
        since = (datetime.now() - timedelta(minutes=max(ALERT_DEDUPE_MINUTES, 1))).isoformat(timespec="seconds")
        seen = db.execute(
            "SELECT 1 FROM alert_outbox WHERE dedupe_key=? AND state IN ('pending','sent') AND created_at>=? LIMIT 1",
            (key, since),
        ).fetchone()
        if seen:
            return []                       # samme alarm er allerede koert inden for vinduet
    channels = [c for c, on in alert_channels().items() if on]
    if not channels:
        return []
    subject = f"[{severity.upper()}] {type_}"
    body = f"{type_}: {message}"
    payload = jsonlib.dumps({"type": type_, "severity": severity, "message": message, "created_at": now_iso()})
    event_id = secrets.token_urlsafe(18)    # samme id paa alle forsoeg = idempotens-noegle
    stamp = now_iso()
    for channel in channels:
        db.execute(
            "INSERT INTO alert_outbox (event_id, alarm_id, dedupe_key, channel, severity, subject, body, payload,"
            " attempts, next_attempt_at, state, created_at) VALUES (?,?,?,?,?,?,?,?,0,?,'pending',?)",
            (event_id, alarm_id, key, channel, severity, subject, body, payload, stamp, stamp),
        )
    return channels


def _send_telegram_alert(subject: str, body: str, severity: str) -> tuple:
    if notify_telegram(f"{subject}\n{body}"):
        return True, ""
    return False, "Telegram er ikke konfigureret eller afviste beskeden"


def _send_email_alert(subject: str, body: str, severity: str) -> tuple:
    if not (SMTP_HOST and SMTP_TO and SMTP_FROM):
        return False, "SMTP_HOST / SMTP_FROM / SMTP_TO mangler"
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM
    msg["To"] = SMTP_TO
    msg.set_content(body + f"\n\n--\nCommand Center {APP_VERSION}")
    try:
        if SMTP_TLS == "ssl":
            server = smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=15)
        else:
            server = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15)
        with server as s:
            s.ehlo()
            if SMTP_TLS == "starttls":
                s.starttls(context=ssl.create_default_context())
                s.ehlo()
            if SMTP_USER:
                s.login(SMTP_USER, SMTP_PASS)
            s.send_message(msg)
        return True, ""
    except (smtplib.SMTPException, OSError, TimeoutError) as e:
        return False, str(e)[:200]


def _send_ntfy_alert(subject: str, body: str, severity: str) -> tuple:
    if not (NTFY_URL and NTFY_TOPIC):
        return False, "NTFY_URL / NTFY_TOPIC mangler"
    rank = alert_severity_rank(severity)
    headers = {
        "Title": subject,
        "Priority": "5" if rank >= 3 else ("4" if rank == 2 else "3"),
        "Tags": "rotating_light" if rank >= 3 else ("warning" if rank == 2 else "information_source"),
    }
    if NTFY_TOKEN:
        headers["Authorization"] = f"Bearer {NTFY_TOKEN}"
    try:
        r = HTTP.post(f"{NTFY_URL}/{NTFY_TOPIC}", data=body.encode("utf-8"), headers=headers, timeout=10)
        r.raise_for_status()
        return True, ""
    except Exception as e:
        return False, str(e)[:200]


def _webhook_secret_bytes() -> bytes:
    raw = (ALERT_WEBHOOK_SECRET or "").strip()
    if raw.startswith("whsec_"):
        try:
            return base64.b64decode(raw[len("whsec_"):])
        except Exception:
            pass
    return raw.encode()


def _send_webhook_alert(event_id: str, subject: str, body: str, severity: str, payload: str = "") -> tuple:
    if not ALERT_WEBHOOK_URL:
        return False, "ALERT_WEBHOOK_URL mangler"
    stamp = str(int(time.time()))
    data = jsonlib.dumps({
        "type": "alert",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "data": {"event_id": event_id, "severity": severity, "subject": subject,
                 "message": body, "source": "command-center", "version": APP_VERSION},
    }).encode()
    headers = {"Content-Type": "application/json", "webhook-id": event_id,
               "webhook-timestamp": stamp, "User-Agent": f"CommandCenter/{APP_VERSION}"}
    secret = _webhook_secret_bytes()
    if secret:
        sig = base64.b64encode(
            hmac.new(secret, f"{event_id}.{stamp}.".encode() + data, hashlib.sha256).digest()
        ).decode()
        headers["webhook-signature"] = f"v1,{sig}"
    try:
        r = HTTP.post(ALERT_WEBHOOK_URL, data=data, headers=headers, timeout=15, allow_redirects=False)
        if 200 <= r.status_code < 300:
            return True, ""
        if r.status_code == 410:
            return False, "HTTP 410 - modtageren er nedlagt (slaa webhooken fra)"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, str(e)[:200]


def deliver_alert_row(row) -> tuple:
    channel = row["channel"]
    if channel == "telegram":
        return _send_telegram_alert(row["subject"], row["body"], row["severity"])
    if channel == "email":
        return _send_email_alert(row["subject"], row["body"], row["severity"])
    if channel == "ntfy":
        return _send_ntfy_alert(row["subject"], row["body"], row["severity"])
    if channel == "webhook":
        return _send_webhook_alert(row["event_id"], row["subject"], row["body"], row["severity"], row["payload"])
    return False, f"ukendt kanal: {channel}"


def drain_alert_outbox(limit: int = 25, ignore_quiet: bool = False) -> dict:
    """Lever ventende alarmer. Fejl proeves igen med backoff; efter 5 forsoeg markeres 'failed'."""
    with get_db() as db:
        rows = db.execute(
            "SELECT * FROM alert_outbox WHERE state='pending' AND (next_attempt_at IS NULL OR next_attempt_at<=?) "
            "ORDER BY id LIMIT ?", (now_iso(), limit),
        ).fetchall()
    sent = failed = deferred = 0
    for row in rows:
        if not ignore_quiet and in_quiet_hours() and alert_severity_rank(row["severity"]) < 3:
            with get_db() as db:            # udskyd til stille timer slutter - alarmen tabes ikke
                db.execute("UPDATE alert_outbox SET next_attempt_at=? WHERE id=?", (quiet_hours_end_iso(), row["id"]))
            deferred += 1
            continue
        ok, err = deliver_alert_row(row)
        with get_db() as db:
            if ok:
                db.execute("UPDATE alert_outbox SET state='sent', sent_at=?, last_error=NULL WHERE id=?",
                           (now_iso(), row["id"]))
                sent += 1
            else:
                attempts = (row["attempts"] or 0) + 1
                if attempts > len(ALERT_BACKOFF):
                    db.execute("UPDATE alert_outbox SET attempts=?, state='failed', last_error=? WHERE id=?",
                               (attempts, err, row["id"]))
                else:
                    delay = ALERT_BACKOFF[attempts - 1]
                    nxt = (datetime.now() + timedelta(seconds=delay)).isoformat(timespec="seconds")
                    db.execute("UPDATE alert_outbox SET attempts=?, last_error=?, next_attempt_at=? WHERE id=?",
                               (attempts, err, nxt, row["id"]))
                failed += 1
    return {"checked": len(rows), "sent": sent, "failed": failed, "deferred": deferred}


def alert_test_sync(channel: str = "all") -> dict:
    """Send en testalarm med det samme (ignorerer dedupe, minimumsniveau og stille timer)."""
    message = f"Testalarm fra Command Center {APP_VERSION}"
    with get_db() as db:
        queued = enqueue_alert(db, "test", message, "info", force=True)
        if channel and channel != "all":
            if channel not in CHANNEL_LABELS:
                return {"error": f"ukendt kanal: {channel}", "channels": queued}
            db.execute("DELETE FROM alert_outbox WHERE dedupe_key=? AND channel<>?",
                       (alert_dedupe_key("test", message), channel))
            queued = [channel]
    return {"channels": queued, **drain_alert_outbox(ignore_quiet=True)}


# ---------- Domene-tjek ----------
def check_domain_sync(url: str):
    try:
        url = normalize_url(url)
        start = datetime.now()
        response = safe_request(url, timeout=6)
        duration = int((datetime.now() - start).total_seconds() * 1000)
        status = "Oppe" if response.status_code < 400 else f"Fejl ({response.status_code})"
        ssl_days = None
        if url.startswith("https://"):
            try:
                host = urlparse(url).hostname or ""  # netloc kan indeholde port -> socket fejler
                context = ssl.create_default_context()
                with socket.create_connection((host, 443), timeout=4) as sock:
                    with context.wrap_socket(sock, server_hostname=host) as ssock:
                        cert = ssock.getpeercert()
                        expiry = datetime.fromtimestamp(
                            ssl.cert_time_to_seconds(cert["notAfter"]), tz=timezone.utc
                        )
                        ssl_days = (expiry - datetime.now(timezone.utc)).days
            except Exception:
                ssl_days = None
        return {"status": status, "ms": duration, "ssl_days": ssl_days, "error": None}
    except Exception as e:
        return {"status": "Nede / Timeout", "ms": None, "ssl_days": None, "error": str(e)[:200]}


def check_all_domains_sync():
    results = []
    with get_db() as db:
        domains = db.execute("SELECT * FROM domains").fetchall()
    for d in domains:
        try:
            res = check_domain_sync(d["url"])
        except Exception as e:
            res = {"status": "Fejl", "ms": None, "ssl_days": None, "error": str(e)[:120]}
        results.append((d["id"], d["url"], res))
        with get_db() as db:
            db.execute(
                "UPDATE domains SET status=?, response_time=?, ssl_days=?, last_checked=?, last_error=? WHERE id=?",
                (
                    res["status"],
                    f"{res['ms']} ms" if res["ms"] is not None else "-",
                    f"{res['ssl_days']} dage" if res["ssl_days"] is not None else "-",
                    now_iso(),
                    res["error"],
                    d["id"],
                ),
            )
            db.execute(
                "INSERT INTO check_history (domain_id, status, response_time, ssl_days, checked_at) VALUES (?,?,?,?,?)",
                (d["id"], res["status"], res["ms"], res["ssl_days"], now_iso()),
            )
            if res["status"] != "Oppe":
                add_alarm(db, "domaene-nede", f"{d['url']}: {res['status']}", "kritisk")
            elif isinstance(res["ssl_days"], int) and res["ssl_days"] < SSL_WARN_DAYS:
                add_alarm(db, "ssl", f"{d['url']}: SSL udlorber om {res['ssl_days']} dage", "advarsel")
    return results


@app.post("/domains/check")
async def check_all_domains():
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, check_all_domains_sync)
    return RedirectResponse("/", status_code=303)


@app.post("/domains/add")
async def add_domain(url: str = Form(...)):
    try:
        url = normalize_url(url)
        with get_db() as db:
            db.execute("INSERT OR IGNORE INTO domains (url) VALUES (?)", (url,))
    except ValueError:
        pass
    return RedirectResponse("/", status_code=303)


@app.post("/domains/delete")
async def delete_domain(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM domains WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


@app.get("/api/history/{domain_id}")
async def domain_history(domain_id: int):
    with get_db() as db:
        rows = db.execute(
            "SELECT checked_at, response_time, status FROM check_history WHERE domain_id=? ORDER BY id DESC LIMIT 60",
            (domain_id,),
        ).fetchall()
    rows = list(reversed(rows))
    return JSONResponse({
        "labels": [r["checked_at"][5:16] for r in rows],
        "ms": [r["response_time"] for r in rows],
        "status": [r["status"] for r in rows],
    })


# ---------- SEO: deep audit (RankMath/Yoast-stil) ----------
def _check(name, ok, weight, info=""):
    return {"name": name, "ok": bool(ok), "weight": weight, "info": info}


def analyze_page(url: str, keyword: str = "", html: str = None, status_code: int = None, ms: int = None):
    """Dyb sideanalyse i stil med RankMath Pro / Yoast Premium."""
    keyword = (keyword or "").strip().lower()
    items = []
    try:
        if html is None:
            url = normalize_url(url)
            t0 = datetime.now()
            response = safe_request(url, timeout=10)
            ms = int((datetime.now() - t0).total_seconds() * 1000)
            status_code = response.status_code
            html = response.text
        soup = BeautifulSoup(html, "html.parser")

        # --- Grundlaeggende ---
        items.append(_check("HTTP 200", status_code == 200, 3, f"status {status_code}"))
        is_https = url.startswith("https://")
        items.append(_check("HTTPS", is_https, 3))
        title = soup.find("title")
        title_text = title.get_text(strip=True) if title else ""
        title_len = len(title_text)
        items.append(_check("Titel findes", bool(title_text), 3))
        items.append(_check("Titel-laengde 30-60", 30 <= title_len <= 60, 2, f"{title_len} tegn"))
        meta = soup.find("meta", attrs={"name": "description"})
        meta_text = (meta.get("content", "").strip() if meta else "")
        meta_len = len(meta_text)
        items.append(_check("Meta description findes", bool(meta_text), 3))
        items.append(_check("Meta description 70-160", 70 <= meta_len <= 160, 2, f"{meta_len} tegn"))
        h1s = soup.find_all("h1")
        items.append(_check("Praecis een H1", len(h1s) == 1, 3, f"{len(h1s)} stk"))
        h2s = soup.find_all("h2")
        items.append(_check("Min. 2 H2-underoverskrifter", len(h2s) >= 2, 2, f"{len(h2s)} stk"))
        h1_text = h1s[0].get_text(strip=True).lower() if h1s else ""
        viewport = soup.find("meta", attrs={"name": "viewport"})
        items.append(_check("Viewport (mobil)", bool(viewport), 3))
        robots_meta = soup.find("meta", attrs={"name": "robots"})
        noindex = robots_meta and "noindex" in (robots_meta.get("content", "") or "").lower()
        items.append(_check("Ikke noindex", not noindex, 3, "noindex!" if noindex else ""))
        canonical = soup.find("link", rel=lambda v: v and "canonical" in v)
        items.append(_check("Canonical", bool(canonical), 2))
        jsonlds = soup.find_all("script", attrs={"type": "application/ld+json"})
        schema_types = []
        for s in jsonlds:
            try:
                import json as _json
                d = _json.loads(s.string or "{}")
                g = d.get("@graph") or [d]
                for node in g:
                    t = node.get("@type")
                    if isinstance(t, list):
                        schema_types.extend(t)
                    elif t:
                        schema_types.append(t)
            except Exception:
                pass
        items.append(_check("JSON-LD schema", bool(jsonlds), 2, ", ".join(schema_types[:3])))
        og_title = soup.find("meta", attrs={"property": "og:title"})
        og_img = soup.find("meta", attrs={"property": "og:image"})
        items.append(_check("Open Graph", bool(og_title), 1, "med billede" if og_img else "uden billede"))
        twitter = soup.find("meta", attrs={"name": re.compile("twitter:card", re.I)})
        items.append(_check("Twitter card", bool(twitter), 1))
        favicon = soup.find("link", rel=lambda v: v and "icon" in v)
        items.append(_check("Favicon", bool(favicon), 1))
        html_tag = soup.find("html")
        lang = html_tag.get("lang") if html_tag else None
        items.append(_check("lang-attribut", bool(lang), 1, lang or ""))
        images = soup.find_all("img")
        no_alt = [img for img in images if not img.get("alt", "").strip()]
        items.append(_check("Billeder har alt-tekst", len(no_alt) == 0, 2, f"{len(no_alt)} mangler af {len(images)}"))

        # --- Indhold ---
        for tag in soup(["script", "style", "noscript"]):
            tag.decompose()
        text = soup.get_text(" ", strip=True)
        words = re.findall(r"[\w\u00C0-\u024F']+", text)
        wc = len(words)
        items.append(_check("Mindst 300 ord", wc >= 300, 3, f"{wc} ord"))
        sentences = [s for s in re.split(r"[.!?]+\s", text) if len(s.strip()) > 2]
        avg_sent = round(wc / max(len(sentences), 1), 1)
        items.append(_check("Lesbarhed: saetninger < 25 ord", avg_sent < 25, 1, f"snit {avg_sent} ord"))
        def _syllables(w):
            w = w.lower()
            groups = re.findall(r"[aeiouyaeiouy]+", w)
            return max(len(groups), 1)
        try:
            syl = sum(_syllables(w) for w in words)
            flesch = round(206.835 - 1.015 * (wc / max(len(sentences), 1)) - 84.6 * (syl / max(wc, 1)))
            items.append(_check("Flesch-lesbarhed > 50", flesch > 50, 1, f"score {flesch}"))
        except Exception:
            pass
        paragraphs = [p for p in soup.find_all("p") if len(p.get_text(strip=True)) > 20]
        long_paras = 0
        for p in paragraphs:
            if len(re.findall(r"[\w']+", p.get_text())) > 150:
                long_paras += 1
        items.append(_check("Korte afsnit (< 150 ord)", long_paras == 0, 1, f"{long_paras} lange"))
        links_all = [a.get("href", "") for a in soup.find_all("a", href=True)]
        host = urlparse(url).netloc if url else ""
        internal = [l for l in links_all if l.startswith("/") or (host and host in l)]
        external = [l for l in links_all if l.startswith("http") and host and host not in l]
        items.append(_check("Min. 3 interne links", len(internal) >= 3, 2, f"{len(internal)} stk"))
        items.append(_check("Min. 1 eksternt link", len(external) >= 1, 1, f"{len(external)} stk"))
        mixed = is_https and "http://" in html.replace("http://www.w3.org", "")
        items.append(_check("Intet mixed content", not mixed, 2))

        # --- Focus keyword (som RankMath) ---
        if keyword:
            kw = re.sub(r"\s+", " ", keyword)
            items.append(_check("Keyword i titel", kw in title_text.lower(), 3, title_text[:60]))
            items.append(_check("Keyword i meta description", kw in meta_text.lower(), 2))
            slug = urllib.parse.unquote(urlparse(url).path.lower()) if url else ""
            items.append(_check("Keyword i URL", kw.replace(" ", "-") in slug or kw in slug, 2, slug[:40]))
            items.append(_check("Keyword i H1", kw in h1_text, 2))
            first10 = " ".join(words[: max(int(wc * 0.1), 20)]).lower()
            items.append(_check("Keyword i foerste 10 % af teksten", kw in first10, 2))
            density = (text.lower().count(kw) * max(len(kw.split()), 1)) / max(wc, 1) * 100
            items.append(_check("Keyword density 0,5-3 %", 0.5 <= density <= 3.0, 2, f"{density:.1f} %"))

        # --- Hastighed ---
        if ms is not None:
            items.append(_check("Svartid < 1500 ms", ms < 1500, 2, f"{ms} ms"))

        total_weight = sum(c["weight"] for c in items)
        earned = sum(c["weight"] for c in items if c["ok"])
        score = round(earned / total_weight * 100) if total_weight else 0
        return {
            "score": score,
            "items": [{"ok": c["ok"], "text": c["name"] + (f" ({c['info']})" if c["info"] else "")} for c in items],
            "raw": items,
            "title": title_text, "meta": meta_text, "h1": h1_text,
            "words": wc, "internal": len(internal), "external": len(external),
        }
    except Exception as e:
        return {"score": 0, "items": [{"ok": False, "text": f"Fejl: {e}"}], "raw": [],
                "title": "", "meta": "", "h1": "", "words": 0, "internal": 0, "external": 0}


def psi_fetch(url: str):
    if not PSI_API_KEY:
        return None
    try:
        r = HTTP.get(
            "https://www.googleapis.com/pagespeedonline/v5/runPagespeed",
            params={"url": url, "key": PSI_API_KEY, "strategy": "mobile"},
            timeout=60,
        )
        r.raise_for_status()
        d = r.json()
        lr = d.get("lighthouseResult", {})
        cats = lr.get("categories", {}).get("performance", {}).get("score")
        audits = lr.get("audits", {})
        lcp = audits.get("largest-contentful-paint", {}).get("displayValue", "")
        cls = audits.get("cumulative-layout-shift", {}).get("displayValue", "")
        return {"perf": round((cats or 0) * 100), "lcp": lcp, "cls": cls}
    except Exception:
        return None


def deep_extras(url: str):
    """Dyb-niveau: status paa eksterne links + billeder uden alt-tekst."""
    items = []
    try:
        r = safe_request(url, timeout=12)
        soup = BeautifulSoup(r.text, "html.parser")
        base = url
        ext_links = []
        seen = set()
        for a_ in soup.find_all("a", href=True):
            href = urllib.parse.urljoin(base, a_["href"].split("#")[0])
            d = urlparse(href).netloc
            if d and d != urlparse(base).netloc and href not in seen:
                seen.add(href)
                ext_links.append(href)
            if len(ext_links) >= 8:
                break
        broken = 0
        for link in ext_links:
            try:
                lr = safe_request(link, timeout=8)
                if lr.status_code >= 400:
                    broken += 1
            except Exception:
                broken += 1
        items.append({"ok": broken == 0, "text": f"Eksterne links: {len(ext_links)} tjekket, {broken} brodne"})
        no_alt = [im for im in soup.find_all("img") if not (im.get("alt") or "").strip()]
        items.append({"ok": len(no_alt) == 0, "text": f"Billeder uden alt-tekst: {len(no_alt)}"})
    except Exception as e:
        items.append({"ok": False, "text": "Dyb-scan fejlede: " + str(e)[:100]})
    return items


@app.post("/seo/audit")
async def run_seo_audit(request: Request):
    form = await request.form()
    url = form.get("url", "")
    keyword = form.get("keyword", "")
    use_psi = form.get("psi", "") == "1"
    level = form.get("level", "standard")
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(executor, analyze_page, url, keyword)
    result["url"] = url
    result["level"] = level
    if level == "quick":
        # Hurtig: kun kerne-tal, ingen dybe kontroller
        fails = [c["name"] for c in result.get("raw", []) if not c["ok"]][:5]
        result = {"url": url, "score": result.get("score", 0), "title": result.get("title", ""),
                  "meta": result.get("meta", ""), "h1": result.get("h1", ""), "words": result.get("words", 0),
                  "level": "quick", "quick_issues": fails}
        return JSONResponse(result)
    if level == "deep":
        deep = await loop.run_in_executor(executor, deep_extras, url)
        result["items"] = list(result.get("items", [])) + deep
        if not use_psi and PSI_API_KEY:
            use_psi = True  # dyb scan koerer automatisk Core Web Vitals
    if use_psi:
        loop2 = asyncio.get_running_loop()
        psi = await loop2.run_in_executor(executor, psi_fetch, url)
        if psi:
            result["psi"] = psi
    return JSONResponse(result)


# ---------- SEO: site-crawler ----------
CRAWL_STATE = {"running": False, "done": 0, "total": 0, "start": "", "error": None, "avg": None,
               "started_at": None, "finished_at": None}

# Anslået varighed (sekunder) pr. tung opgave - bruges af UI'et til timer + ETA.
TASK_ESTIMATES = {
    "/seo/audit": {"label": "SEO-audit", "seconds": 12},
    "/seo/rewrite": {"label": "AI titel/meta-forslag", "seconds": 25},
    "/seo/linksuggest": {"label": "Interne link-forslag", "seconds": 25},
    "/serp/discover": {"label": "SERP-discovery", "seconds": 20},
    "/serp/gap": {"label": "Content gap-analyse", "seconds": 30},
    "/backlinks/prospect": {"label": "Backlink-prospecting", "seconds": 40},
    "/outreach/scan": {"label": "E-mail-scan", "seconds": 35},
    "/keywords/check": {"label": "Keyword-tjek", "seconds": 45},
    "/keywords/ideas": {"label": "Keyword-ideer", "seconds": 20},
    "/keywords/difficulty": {"label": "Svaerhedsgrad", "seconds": 25},
    "/domains/check": {"label": "Domaene-tjek", "seconds": 35},
    "/monitors/check": {"label": "Monitor-tjek", "seconds": 25},
    "/links/check": {"label": "Link-tjek", "seconds": 25},
    "/articles/generate": {"label": "AI-artikel", "seconds": 60},
    "/articles/autopilot": {"label": "Autopilot (ide til kladde)", "seconds": 150},
    "/articles/meta": {"label": "Meta-forslag", "seconds": 20},
    "/articles/score": {"label": "Kvalitetsscore", "seconds": 10},
    "/articles/push": {"label": "Push til WordPress", "seconds": 8},
    "/ai/visibility": {"label": "AI-synlighed", "seconds": 60},
    "/autopilot/sync": {"label": "Autopilot-synk", "seconds": 10},
    "/update/check": {"label": "GitHub-tjek", "seconds": 10},
    "/api/duplicates": {"label": "Duplikat-analyse", "seconds": 6},
    "/api/redirects": {"label": "Redirect-audit", "seconds": 6},
    "/api/crawl/diff": {"label": "Crawl-sammenligning", "seconds": 6},
    "/alerts/test": {"label": "Testalarm til kanalerne", "seconds": 12},
    "/update/apply": {"label": "Opdatering fra GitHub", "seconds": 60},
}


def crawl_progress(state: dict | None = None) -> dict:
    """Procent, forloebet tid og ETA for crawl - bruges af UI'et og /api/crawl/status."""
    s = dict(CRAWL_STATE if state is None else state)
    done = int(s.get("done") or 0)
    total = int(s.get("total") or 0)
    running = bool(s.get("running"))
    started_at, finished_at = s.get("started_at") or "", s.get("finished_at") or ""

    def _dt(value):
        try:
            return datetime.fromisoformat(value)
        except Exception:
            return None

    t0 = _dt(started_at)
    elapsed = 0.0
    if t0:
        elapsed = max(0.0, ((_dt(finished_at) or datetime.now()) - t0).total_seconds())
    if running:
        percent = min(99, int(round(done * 100 / total))) if total else 0
        eta = int(round(elapsed / done * (total - done))) if done and total > done else None
    else:
        percent = 100 if done and not s.get("error") else 0
        eta = None
    return {"running": running, "done": done, "total": total, "percent": percent,
            "elapsed_seconds": round(elapsed, 1), "eta_seconds": eta, "finished": bool(finished_at),
            "error": s.get("error"), "avg": s.get("avg")}


def site_crawl_sync(start_url: str, max_pages: int = 30):
    try:
        start_url = normalize_url(start_url)
        host = urlparse(start_url).netloc
        # Behold det seneste crawl, saa crawl-diff kan sammenligne med det nye; ryd alt aeldre.
        with get_db() as db:
            keep = [r["id"] for r in db.execute("SELECT id FROM crawl_runs ORDER BY id DESC LIMIT 1").fetchall()]
            if keep:
                marks = ",".join("?" * len(keep))
                db.execute(f"DELETE FROM seopages WHERE run_id NOT IN ({marks})", keep)
                db.execute(f"DELETE FROM crawl_runs WHERE id NOT IN ({marks})", keep)
            else:
                db.execute("DELETE FROM seopages")
        # robots.txt + sitemap.xml
        robots_ok = sitemap_ok = False
        sitemap_count = 0
        try:
            r = safe_request(f"https://{host}/robots.txt", timeout=8)
            robots_ok = (r.status_code == 200)
            m = re.search(r"Sitemap:\s*(\S+)", r.text, re.I)
            sitemap_url = m.group(1) if m else f"https://{host}/sitemap.xml"
            r2 = safe_request(sitemap_url, timeout=10)
            if r2.status_code == 200:
                sm = BeautifulSoup(r2.text, "html.parser")
                sitemap_count = len(sm.find_all("loc"))
                sitemap_ok = sitemap_count > 0
        except Exception:
            pass
        with get_db() as db:
            db.execute(
                "INSERT INTO crawl_runs (host, robots_ok, sitemap_ok, sitemap_urls, started_at) VALUES (?,?,?,?,?)",
                (host, int(robots_ok), int(sitemap_ok), sitemap_count, now_iso()),
            )
            run_id = db.execute("SELECT last_insert_rowid() AS id").fetchone()["id"]

        queue = [start_url]
        seen = set()
        CRAWL_STATE.update({"running": True, "done": 0, "total": max_pages, "start": start_url, "error": None, "avg": None,
                            "started_at": now_iso(), "finished_at": None})
        total_score = 0
        pages_saved = 0
        while queue and len(seen) < max_pages:
            current = queue.pop(0)
            if current in seen:
                continue
            seen.add(current)
            resp = None
            try:
                t0 = datetime.now()
                resp = safe_request(current, timeout=10)
                ms = int((datetime.now() - t0).total_seconds() * 1000)
                # html videregives altid, saa analyze_page ikke henter siden igen ved 4xx/5xx.
                res = analyze_page(current, "", html=resp.text or "", status_code=resp.status_code, ms=ms)
                status = resp.status_code
            except Exception:
                res = {"score": 0, "title": "", "meta": "", "h1": "", "words": 0, "raw": []}
                status = 0
            issues = [c["name"] for c in res.get("raw", []) if not c["ok"]]
            redirects = ""
            if resp is not None and resp.history:
                redirects = " -> ".join([str(r.status_code) for r in resp.history] + [str(resp.status_code)]) +                             " | " + " -> ".join([r.url for r in resp.history] + [resp.url])
            content_hash = ""
            if resp is not None and resp.status_code == 200:
                psoup2 = BeautifulSoup(resp.text, "html.parser")
                for t in psoup2(["script", "style", "noscript"]):
                    t.decompose()
                content_hash = hashlib.md5(" ".join(psoup2.get_text().split()).encode()).hexdigest()
            with get_db() as db:
                db.execute(
                    "INSERT INTO seopages (run_id, url, http_status, title, meta_len, h1, words, score, issues, redirects, content_hash, crawled_at) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    (run_id, current, status, res.get("title", "")[:200], len(res.get("meta", "")),
                     res.get("h1", "")[:200], res.get("words", 0), res["score"],
                     "; ".join(issues[:8]), redirects[:300], content_hash, now_iso()),
                )
            if resp is not None and resp.status_code < 400:
                total_score += res["score"]
                pages_saved += 1
                try:
                    psoup = BeautifulSoup(resp.text, "html.parser")
                    for a in psoup.find_all("a", href=True):
                        href = urllib.parse.urljoin(current, a["href"].split("#")[0])
                        ph = urlparse(href)
                        if ph.netloc == host and ph.scheme.startswith("http") and href not in seen:
                            queue.append(href)
                except Exception:
                    pass
            CRAWL_STATE["done"] = len(seen)
            time.sleep(0.4)
        avg = round(total_score / pages_saved) if pages_saved else 0
        # sitemap-validering: tjek foerste 50 sitemap-URLs for 404/fejl
        sitemap_broken = []
        if sitemap_ok:
            try:
                sm_urls = []
                r3 = safe_request(sitemap_url, timeout=10)
                for loc in BeautifulSoup(r3.text, "html.parser").find_all("loc"):
                    sm_urls.append(loc.get_text(strip=True))
                for su in sm_urls[:50]:
                    try:
                        rr = safe_request(su, timeout=8)
                        if rr.status_code >= 400:
                            sitemap_broken.append(f"{su} ({rr.status_code})")
                    except Exception:
                        sitemap_broken.append(f"{su} (timeout)")
                    time.sleep(0.2)
            except Exception:
                pass
        with get_db() as db:
            db.execute("UPDATE crawl_runs SET pages=?, avg_score=?, finished_at=?, sitemap_broken=?, sitemap_missing=? WHERE id=?",
                       (pages_saved, avg, now_iso(), "; ".join(sitemap_broken[:10]) if sitemap_broken else "",
                        max(sitemap_count - pages_saved, 0) if sitemap_ok else 0, run_id))
            db.execute("INSERT INTO health_history (host, avg_score, pages, run_id, checked_at) VALUES (?,?,?,?,?)",
                       (host, avg, pages_saved, run_id, now_iso()))
            if sitemap_broken:
                add_alarm(db, "sitemap", f"{len(sitemap_broken)} sitemap-URLs fejler (foerste 50 tjekket)", "advarsel")
        CRAWL_STATE.update({"running": False, "avg": avg, "finished_at": now_iso()})
        return {"ok": True, "pages": pages_saved, "avg_score": avg, "robots_ok": robots_ok,
                "sitemap_ok": sitemap_ok, "sitemap_urls": sitemap_count}
    except Exception as e:
        CRAWL_STATE.update({"running": False, "error": str(e)[:200], "finished_at": now_iso()})
        return {"ok": False, "error": str(e)[:200]}


@app.post("/seo/crawl/delete")
async def crawl_delete():
    with get_db() as db:
        db.execute("DELETE FROM seopages")
        db.execute("DELETE FROM crawl_runs")
    return RedirectResponse("/", status_code=303)


@app.post("/seo/crawl")
async def start_crawl(url: str = Form(...), max_pages: int = Form(30), level: str = Form("standard")):
    if CRAWL_STATE["running"]:
        return RedirectResponse("/", status_code=303)
    preset = {"quick": 10, "standard": 30, "deep": 60}.get(level, None)
    if preset:
        max_pages = preset
    max_pages = max(5, min(int(max_pages or 30), 100))
    loop = asyncio.get_running_loop()
    loop.run_in_executor(executor, site_crawl_sync, url, max_pages)
    return RedirectResponse("/", status_code=303)


@app.get("/api/crawl/status")
async def crawl_status():
    """Crawl-fremdrift: sider, procent og ETA (polles af dashboardet)."""
    return JSONResponse(crawl_progress())


@app.get("/api/crawl/diff")
async def crawl_diff():
    with get_db() as db:
        runs = db.execute("SELECT id FROM crawl_runs ORDER BY id DESC LIMIT 2").fetchall()
        if len(runs) < 2:
            return JSONResponse({"error": "Kræver mindst to crawls"})
        new_r, old_r = runs[0]["id"], runs[1]["id"]
        new_pages = {r["url"]: r for r in db.execute("SELECT * FROM seopages WHERE run_id=?", (new_r,)).fetchall()}
        old_pages = {r["url"]: r for r in db.execute("SELECT * FROM seopages WHERE run_id=?", (old_r,)).fetchall()}
        added = [u for u in new_pages if u not in old_pages]
        removed = [u for u in old_pages if u not in new_pages]
        changed = []
        for u in new_pages:
            if u in old_pages:
                n, o = new_pages[u], old_pages[u]
                if n["content_hash"] and o["content_hash"] and n["content_hash"] != o["content_hash"]:
                    changed.append({"url": u, "score": n["score"], "old_score": o["score"]})
        score_drops = [{"url": u, "score": new_pages[u]["score"], "old_score": old_pages[u]["score"]}
                       for u in new_pages if u in old_pages and old_pages[u]["score"] and new_pages[u]["score"] and new_pages[u]["score"] < old_pages[u]["score"] - 10]
        return JSONResponse({"new": added, "removed": removed, "changed_content": changed, "score_drops": score_drops,
                             "new_run": new_r, "old_run": old_r})


@app.get("/api/sitemap.xml")
async def gen_sitemap():
    with get_db() as db:
        run = db.execute("SELECT id FROM crawl_runs ORDER BY id DESC LIMIT 1").fetchone()
        if not run:
            return JSONResponse({"error": "Ingen crawl-data — kør et crawl først"}, status_code=400)
        pages = db.execute("SELECT url FROM seopages WHERE run_id=? AND http_status=200 ORDER BY url", (run["id"],)).fetchall()
    today = datetime.now().strftime("%Y-%m-%d")
    rows = ['<?xml version="1.0" encoding="UTF-8"?>',
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for pg in pages:
        rows.append("  <url><loc>" + pg["url"] + "</loc><lastmod>" + today + "</lastmod></url>")
    rows.append("</urlset>")
    return Response("\n".join(rows), media_type="application/xml")


@app.get("/api/redirects")
async def redirect_audit():
    with get_db() as db:
        rows = db.execute(
            "SELECT url, redirects, http_status FROM seopages WHERE redirects != '' "
            "AND run_id=(SELECT id FROM crawl_runs ORDER BY id DESC LIMIT 1)"
        ).fetchall()
    chains = []
    loops = []
    insecure = []
    for r in rows:
        parts = (r["redirects"] or "").split(" | ")
        if len(parts) != 2:
            continue
        codes = parts[0].split(" -> ")
        urls = parts[1].split(" -> ")
        if len(codes) > 2:
            chains.append({"url": r["url"], "chain": " -> ".join(urls), "codes": parts[0]})
        if len(set(urls)) < len(urls):
            loops.append({"url": r["url"], "chain": " -> ".join(urls)})
        if any(u.startswith("http://") for u in urls):
            insecure.append({"url": r["url"], "chain": " -> ".join(urls)})
    return JSONResponse({"with_redirects": len(rows), "chains": chains, "loops": loops, "insecure": insecure})

# ---------- SERP & konkurrenter ----------# ---------- SERP & konkurrenter ----------
def discover_competitors_sync(keyword: str):
    try:
        query = urllib.parse.quote_plus(keyword)
        response = safe_request(f"https://html.duckduckgo.com/html/?q={query}", timeout=10)
        soup = BeautifulSoup(response.text, "html.parser")
        found = []
        for anchor in soup.select("a.result__url[href]"):
            href = anchor.get("href", "")
            if "uddg=" in href:
                parsed = urllib.parse.parse_qs(urllib.parse.urlparse(href).query)
                href = parsed.get("uddg", [href])[0]
            if href.startswith("http") and "duckduckgo.com" not in href:
                domain = urlparse(href).netloc
                if domain and domain not in [item[0] for item in found]:
                    found.append((domain, href))
                if len(found) >= 5:
                    break
        if not found:
            raise RuntimeError("Ingen resultater (DuckDuckGo blokerede muligvis - proev igen eller brug SerpAPI)")
        with get_db() as db:
            for domain, url in found:
                info = crawl_competitor(url)
                db.execute(
                    "INSERT INTO competitors (name, url, crawled_info, found_at) VALUES (?,?,?,?)",
                    (domain, url, info, now_iso()),
                )
        return {"ok": True, "count": len(found), "error": None}
    except Exception as e:
        err = str(e)[:200]
        with get_db() as db:
            add_alarm(db, "serp-scan", f"Konkurrent-scan '{keyword}' fejlede: {err}", "advarsel")
        return {"ok": False, "count": 0, "error": err}


@app.post("/serp/discover")
async def discover(keyword: str = Form(...)):
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, discover_competitors_sync, keyword)
    return RedirectResponse("/", status_code=303)


def crawl_competitor(url: str):
    try:
        url = normalize_url(url)
        response = safe_request(url)
        if response.status_code != 200:
            return f"HTTP-fejl {response.status_code}"
        soup = BeautifulSoup(response.text, "html.parser")
        title = soup.title.get_text(strip=True) if soup.title else "Ingen titel"
        meta = soup.find("meta", attrs={"name": "description"})
        description = meta.get("content", "").strip() if meta else "Ingen beskrivelse"
        h1 = soup.find("h1")
        h1_text = h1.get_text(strip=True) if h1 else "Ingen H1"
        return f"Titel: {title[:80]} | H1: {h1_text[:60]} | Beskrivelse: {description[:100]}"
    except Exception as e:
        return f"Fejl: {e}"


@app.post("/competitors/delete")
async def delete_competitor(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM competitors WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


# ---------- Artikler (AI + WordPress) ----------
TEMPLATE_ARTICLE = """
<h2>Hvad er {keyword}?</h2>
<p>{keyword} er et emne, hvor god struktur, klar information og brugervenligt indhold gor en stor forskel.</p>
<h3>Hvorfor er {keyword} vigtigt?</h3>
<ul><li>Det hjaelper besogende med hurtigt at finde relevant information.</li><li>Godt struktureret indhold understotter sogemaskineforstaelse.</li></ul>
<h3>Sadan kommer du i gang</h3>
<ol><li>Definer malgruppen og deres behov.</li><li>Lav en klar side med overskrifter, korte afsnit og relevante links.</li><li>Tilfoj FAQ, interne links og relevant struktureret data.</li></ol>
<h3>Konklusion</h3>
<p>Med fokus paa kvalitet, struktur og brugerbehov kan indhold om {keyword} skabe langtidsholdbar vaerdi.</p>
"""


def serp_competitor_context(keyword: str, n: int = 5):
    """Hent top-SERP-resultater som konkurrent-kontekst til artikelgenerering."""
    if not SERPAPI_KEY:
        return ""
    try:
        r = HTTP.get(
            "https://serpapi.com/search",
            params={"engine": "google", "q": keyword, "num": 10, "api_key": SERPAPI_KEY},
            timeout=30,
        )
        r.raise_for_status()
        org = r.json().get("organic_results") or []
        lines = []
        for it in org[:n]:
            t = (it.get("title") or "").strip()
            sn = (it.get("snippet") or "").strip()
            if t:
                lines.append(f"- {t}: {sn}" if sn else f"- {t}")
        if not lines:
            return ""
        return "\n".join(lines)
    except Exception:
        return ""


# ---------- SEO-strategier (v7.8) ----------
STRATEGIES = {
    "adsense": {
        "label": "AdSense-indkomst",
        "desc": "Long-tail informationsartikler, volumen forst, rolig CTA",
        "words": "1000-1400",
        "style": (
            "Artikeltypen er LANG og informationsrig (1000-1400 ord). Maalgruppe: laesere fra "
            "Google-sogninger der vil vide noget. Dybdegaaende sektioner, tabel eller liste med "
            "konkrete data, FAQ-sektion med 4-5 spoergsmaal. Roelig, nyttig tone; hojst 1 diskret "
            "produktlink. Fokus: laesetid, laesbarhed og reelle svar."
        ),
        "autopilot": "artikel",
    },
    "affiliate": {
        "label": "Affiliate",
        "desc": "Buyer-intent (best/vs/review), sammenligningstabeller, CTA-tung",
        "words": "900-1200",
        "style": (
            "Artikeltypen er koebeside-venlig (900-1200 ord). Keywordet er typisk buyer-intent "
            "(best, vs, review, hvor kan man koebe). Indhold: sammenligningstabel med 3-5 produkter/"
            "valg, fordele-ulemper-lister, tydelig men aeldelig CTA efter hver stor sektion, FAQ med "
            "4 koeb-relaterede spoergsmaal. Fokus: hjaelp laeseren at vælge."
        ),
        "autopilot": "artikel",
    },
    "backlinks": {
        "label": "Backlink-vÃ¦kst",
        "desc": "Link-vÃ¦rdigt indhold + prospector/outreach autopilot",
        "words": "700-1000",
        "style": (
            "Artikeltypen er link-venlig (700-1000 ord): lister ('10 bedste ...'), checklister, "
            "begynder-guides og ressourcesider andre sider naturligt vil linke til. Klar struktur, "
            "citervenlige facts, faerre produktlinks. Autopiloten koerer ogsa backlink-prospecting "
            "paa keywords i denne strategi."
        ),
        "autopilot": "backlink",
    },
}
DEFAULT_STRATEGY = "adsense"


def get_active_strategy() -> dict:
    try:
        with get_db() as db:
            row = db.execute("SELECT value FROM settings WHERE key='active_strategy'").fetchone()
        key = row["value"] if row else DEFAULT_STRATEGY
    except Exception:
        key = DEFAULT_STRATEGY
    return STRATEGIES.get(key, STRATEGIES[DEFAULT_STRATEGY])


def generate_article_ai(keyword: str, strategy: dict = None):
    st = strategy or get_active_strategy()
    competitors = serp_competitor_context(keyword)
    if competitors:
        comp_block = (
            "TOP 5 KONKURRENTER PA GOOGLE FOR DETA KEYWORD (titel + snippet):\n"
            f"{competitors}\n\n"
            "DIN OPGAVE: Skriv en artikel der er MAERKBART BEDRE end disse resultater. "
            "Dæk alt hvad konkurrenterne dækker (content gap), og tilføj mere: konkrete "
            "materialer, prisestimater, trin-for-trin, praktiske detaljer. "
            "Byg KUN pa faktuelle, verifikbare oplysninger - ingen opdigtede tal, "
            "ingen tom fyldstof-saetninger ('in today's world', 'look no further' osv. "
            "er forbudt). Hver saetning skal give laeseren ny, brugbar info."
        )
    else:
        comp_block = (
            "KVALITETSKRAV: Byg KUN pa faktuelle, verifikbare oplysninger om emnet - "
            "ingen opdigtede tal eller statistik. Ingen tom fyldstof-saetninger. "
            "Hver saetning skal give laeseren konkret, brugbar info (materialer, "
            "prisniveauer, trin, fejl man skal undga). Mål: bedre end de nuværende "
            "topresultater pa Google for dette keyword."
        )
    prompt = (
        f"Write an SEO-optimized blog article draft in English about '{keyword}' for a steampunk "
        f"cosplay & merchandise webshop. Output raw HTML (h2/h3/p/ul/ol only, no <html> wrapper). "
        f"Include: engaging intro, 3-4 H2 sections, a bullet list, an FAQ section, "
        f"and a short conclusion. Around {st['words']} words. No images. Natural, helpful tone.\n\n"
        f"STRATEGI ({st['label']}): {st['style']}\n\n"
        f"{comp_block}"
    )
    resp = HTTP.post(
        "https://api.aimlapi.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {AIMLAPI_KEY}", "Content-Type": "application/json"},
        json={
            "model": AI_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 3000,
        },
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


@app.post("/articles/generate")
async def create_article(keyword: str = Form(...)):
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    source = "skabelon"
    title = f"Guide: {keyword} i 2027"
    content = TEMPLATE_ARTICLE.format(keyword=keyword)
    err = None
    if AIMLAPI_KEY:
        try:
            loop = asyncio.get_running_loop()
            st_active = get_active_strategy()
            content = await loop.run_in_executor(executor, generate_article_ai, keyword, st_active)
            title = f"Guide: {keyword}"
            source = f"AI ({AI_MODEL})"
        except Exception as e:
            err = str(e)[:200]
    with get_db() as db:
        db.execute(
            "INSERT INTO articles (title, keyword, content, source, created_at) VALUES (?,?,?,?,?)",
            (title, keyword, content, source, now_iso()),
        )
        if err:
            add_alarm(db, "ai-artikel", f"AI-generering fejlede for '{keyword}', brugte skabelon: {err}", "advarsel")
    return RedirectResponse("/", status_code=303)


@app.post("/articles/push")
async def push_article(id: int = Form(...)):
    if not (WP_URL and WP_USER and WP_APP_PASSWORD):
        with get_db() as db:
            add_alarm(db, "wordpress", "WordPress-push fejlede: WP_URL/WP_USER/WP_APP_PASSWORD er ikke sat i .env", "advarsel")
        return RedirectResponse("/", status_code=303)
    with get_db() as db:
        art = db.execute("SELECT * FROM articles WHERE id=?", (id,)).fetchone()
    if not art:
        return RedirectResponse("/", status_code=303)
    gate = quality_check(art["content"], art["keyword"])
    if not gate["passed"]:
        with get_db() as db:
            add_alarm(db, "kvalitet", f"Artikel #{id} sendt manuelt trods kvalitetsgate: " + "; ".join(gate["errors"]), "info")
    try:
        wp_id = wp_push_draft(art["title"], art["content"])
        link = f"{WP_URL.rstrip('/')}/wp-admin/post.php?post={wp_id}&action=edit"
        with get_db() as db:
            db.execute("UPDATE articles SET status='Sendt til WP (kladde)', wp_link=? WHERE id=?", (link, id))
    except Exception as e:
        with get_db() as db:
            add_alarm(db, "wordpress", f"WP-push fejlede for artikel #{id}: {str(e)[:150]}", "kritisk")
    return RedirectResponse("/", status_code=303)


@app.post("/articles/delete")
async def delete_article(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM articles WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


# ---------- Artikel-kvalitetsgate (v8-plan) ----------
QUALITY_MIN_WORDS = int(os.environ.get("QUALITY_MIN_WORDS", "400") or 0)


def quality_check(content: str, keyword: str) -> dict:
    """Deterministisk tjek foer en artikel maa blive WP-kladde.
    Blokerer: for faa ord (min. QUALITY_MIN_WORDS, eller 80 % af SERP-gennemsnittet fra Content Gap),
    fokus-keyword mangler, under 2 H2-overskrifter. Advarer: faerre end 2 interne links."""
    soup = BeautifulSoup(content or "", "html.parser")
    text = soup.get_text(" ", strip=True)
    words = len(text.split())
    min_words = QUALITY_MIN_WORDS
    try:
        with get_db() as db:
            gap = db.execute("SELECT stats_json FROM content_gap WHERE keyword=? ORDER BY id DESC LIMIT 1", (keyword,)).fetchone()
        avg = jsonlib.loads(gap["stats_json"]).get("summary", {}).get("avg_words", 0) if gap and gap["stats_json"] else 0
        if avg:
            min_words = max(min_words, int(avg * 0.8))
    except Exception:
        pass
    h2 = len(soup.find_all("h2")) or len([l for l in (content or "").splitlines() if l.startswith("## ")])
    internal = 0
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if href.startswith("/") or (TRACK_DOMAIN and TRACK_DOMAIN in href):
            internal += 1
    errors, warnings = [], []
    if words < min_words:
        errors.append(f"for kort: {words} ord (min. {min_words})")
    if keyword and keyword.lower() not in text.lower():
        errors.append(f"fokus-keyword '{keyword}' mangler")
    if h2 < 2:
        errors.append(f"kun {h2} H2-overskrift(er), min. 2")
    if internal < 2:
        warnings.append(f"kun {internal} interne link(s), anbefalet min. 2")
    return {"passed": not errors, "words": words, "min_words": min_words, "h2": h2, "internal_links": internal,
            "errors": errors, "warnings": warnings}


# ---------- Growth Pack (v7.7): autopilot + backlink-prospector ----------
def wp_push_draft(title: str, content: str):
    resp = HTTP.post(
        f"{WP_URL.rstrip('/')}/wp-json/wp/v2/posts",
        auth=(WP_USER, WP_APP_PASSWORD),
        json={"title": title, "content": content, "status": "draft"},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json().get("id")


def autopilot_sync():
    """Growth-autopilot: vaelg aeldste ubrugte keyword-idee -> AI-artikel -> (valgfrit) WP-kladde."""
    if not AIMLAPI_KEY:
        with get_db() as db:
            add_alarm(db, "growth", "Autopilot sprang over: AIMLAPI_KEY mangler", "advarsel")
        return "no-ai"
    with get_db() as db:
        row = db.execute(
            "SELECT id, idea FROM keyword_ideas WHERE idea IS NOT NULL AND idea != '' "
            "AND idea NOT IN (SELECT keyword FROM articles) ORDER BY id ASC LIMIT 1"
        ).fetchone()
    if not row:
        # Idea-puljen er tom: sow nye via Google-autocomplete fra eksisterende keywords
        try:
            with get_db() as db:
                seeds = [r["keyword"] for r in db.execute("SELECT DISTINCT keyword FROM keywords LIMIT 5").fetchall()]
            if not seeds:
                seeds = ["steampunk costume", "steampunk goggles"]
            newideas = []
            for seed in seeds[:3]:
                rr = HTTP.get(
                    "https://suggestqueries.google.com/complete/search",
                    params={"client": "firefox", "q": seed, "hl": "en"},
                    timeout=10,
                )
                for sug in (rr.json()[1] or [])[:5]:
                    if sug.lower() != seed.lower():
                        newideas.append(sug)
            with get_db() as db:
                for ni in dict.fromkeys(newideas):
                    db.execute("INSERT OR IGNORE INTO keyword_ideas (keyword, idea, source, created_at) VALUES (?,?,?,?)",
                               (ni.split()[0] if ni else "", ni, "autopilot", now_iso()))
            with get_db() as db:
                row = db.execute(
                    "SELECT id, idea FROM keyword_ideas WHERE idea IS NOT NULL AND idea != '' "
                    "AND idea NOT IN (SELECT keyword FROM articles) ORDER BY id ASC LIMIT 1"
                ).fetchone()
        except Exception as e:
            with get_db() as db:
                add_alarm(db, "growth", f"Autopilot kunne ikke hente nye ideer: {str(e)[:120]}", "advarsel")
            return "no-ideas"
        if not row:
            return "no-ideas"
    idea = row["idea"].strip()
    st_auto = get_active_strategy()
    if st_auto.get("autopilot") == "backlink":
        try:
            prospect_sync(idea)
        except Exception as e:
            with get_db() as db:
                add_alarm(db, "growth", f"Autopilot-prospecting fejlede for '{idea}': {str(e)[:120]}", "advarsel")
        with get_db() as db:
            db.execute("DELETE FROM keyword_ideas WHERE id=?", (row["id"],))
        return "backlink-prospect"
    try:
        content = generate_article_ai(idea, st_auto)
    except Exception as e:
        with get_db() as db:
            add_alarm(db, "growth", f"Autopilot-generering fejlede for '{idea}': {str(e)[:150]}", "advarsel")
        return "ai-fail"
    title = f"Guide: {idea}"
    with get_db() as db:
        cur = db.execute(
            "INSERT INTO articles (title, keyword, content, source, created_at) VALUES (?,?,?,?,?)",
            (title, idea, content, "Autopilot", now_iso()),
        )
        art_id = cur.lastrowid
        db.execute("DELETE FROM keyword_ideas WHERE id=?", (row["id"],))
    gate = quality_check(content, idea)
    if not gate["passed"]:
        with get_db() as db:
            db.execute("UPDATE articles SET status=? WHERE id=?", ("Stoppet af kvalitetsgate: " + "; ".join(gate["errors"]), art_id))
            add_alarm(db, "kvalitet", f"Autopilot-artikel #{art_id} ('{idea}') blev ikke sendt til WP: " + "; ".join(gate["errors"]), "advarsel")
        return f"quality-blocked:{art_id}"
    if WP_URL and WP_USER and WP_APP_PASSWORD and module_on("wp_push"):
        try:
            wp_id = wp_push_draft(title, content)
            link = f"{WP_URL.rstrip('/')}/wp-admin/post.php?post={wp_id}&action=edit"
            with get_db() as db:
                db.execute("UPDATE articles SET status='Sendt til WP (kladde)', wp_link=? WHERE id=?", (link, art_id))
        except Exception as e:
            with get_db() as db:
                add_alarm(db, "growth", f"Autopilot WP-push fejlede for #{art_id}: {str(e)[:150]}", "advarsel")
    return f"ok:{art_id}"


async def run_autopilot():
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, autopilot_sync)
    return RedirectResponse("/", status_code=303)


@app.post("/articles/autopilot")
async def autopilot_manual():
    """Manuel koersel af autopilot (knappen i Artikler-fanen)."""
    return await run_autopilot()


async def job_growth_autopilot():
    if not module_on("growth"):
        return
    await run_autopilot()


def classify_site(url: str):
    u = (url or "").lower()
    if any(x in u for x in ("/blog/", ".blogspot", "medium.com", "substack.com")):
        return "blog"
    if any(x in u for x in ("directory", "liste", "resources", "tools")):
        return "liste"
    if any(x in u for x in ("forum", "reddit.com", "quora.com")):
        return "forum"
    return "artikel"


EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")

def prospect_sync(keyword: str):
    if not SERPAPI_KEY:
        with get_db() as db:
            add_alarm(db, "growth", "Backlink-prospector: SERPAPI_KEY mangler", "advarsel")
        return
    r = HTTP.get(
        "https://serpapi.com/search",
        params={"engine": "google", "q": keyword, "num": 10, "api_key": SERPAPI_KEY},
        timeout=20,
    )
    results = (r.json().get("organic_results") or [])[:10]
    for res in results:
        url = res.get("link") or ""
        if not url or urlparse(url).netloc in (TRACK_DOMAIN, "www." + TRACK_DOMAIN):
            continue
        site = urlparse(url).netloc
        stype = classify_site(url)
        email, draft = None, None
        try:
            resp = safe_request(url, timeout=6)
            found = EMAIL_RE.findall(resp.text or "")
            email = next((e for e in found if not any(x in e.lower() for x in (".png", ".jpg", ".webp", ".svg", "example.com", "sentry"))), None)
        except Exception:
            pass
        if AIMLAPI_KEY and email:
            try:
                prompt = (
                    f"Write a short (max 120 words) friendly outreach email in English to {email} "
                    f"who runs {site}. Suggest a steampunk cosplay guide or resource relevant to "
                    f"their page about '{keyword}' as a reason to add a link to our site {TRACK_DOMAIN}. "
                    f"Output only the email body."
                )
                resp2 = HTTP.post(
                    "https://api.aimlapi.com/v1/chat/completions",
                    headers={"Authorization": f"Bearer {AIMLAPI_KEY}", "Content-Type": "application/json"},
                    json={"model": AI_MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": 3000},
                    timeout=60,
                )
                draft = resp2.json()["choices"][0]["message"]["content"]
            except Exception:
                draft = None
        if not draft:
            draft = (f"Hej! Vi har lavet en guide om '{keyword}' paa {TRACK_DOMAIN}, som dine laesere "
                     f"maaske kan bruge. Maa vi linke den ind? (Skabelon-draft - saet AIMLAPI_KEY for AI-drafts)")
        with get_db() as db:
            db.execute(
                "INSERT INTO backlink_prospects (keyword, site, url, type, email, draft, created_at) VALUES (?,?,?,?,?,?,?)",
                (keyword, site, url, stype, email, draft, now_iso()),
            )


@app.post("/backlinks/prospect")
async def backlink_prospect(keyword: str = Form(...)):
    keyword = keyword.strip()
    if keyword:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(executor, prospect_sync, keyword)
    return RedirectResponse("/", status_code=303)


@app.post("/backlinks/delete")
async def backlink_delete(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM backlink_prospects WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


# ---------- Linktjek ----------
def check_links_sync(url: str):
    try:
        url = normalize_url(url)
        response = safe_request(url)
        soup = BeautifulSoup(response.text, "html.parser")
        links = [a["href"] for a in soup.find_all("a", href=True)]
        external = [l for l in links if l.startswith("http")]
        checked = 0
        broken = 0
        broken_list = []
        for link in external[:LINKCHECK_LIMIT]:
            checked += 1
            try:
                result = safe_request(link, timeout=5)
                if result.status_code >= 400:
                    broken += 1
                    broken_list.append(f"{link} ({result.status_code})")
            except Exception:
                broken += 1
                broken_list.append(f"{link} (timeout)")
        result_text = (
            f"Fandt {len(links)} links. Eksterne: {len(external)}. "
            f"Tjekkede: {checked}. Broedte/muligt fejlende: {broken}."
        )
        if broken:
            result_text += " | " + "; ".join(broken_list[:5])
        return {"ok": True, "text": result_text, "broken": broken, "url": url, "error": None}
    except Exception as e:
        return {"ok": False, "text": f"Fejl: {e}", "broken": 0, "url": url, "error": str(e)[:200]}


@app.post("/links/check")
async def check_page_links(url: str = Form(...)):
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(executor, check_links_sync, url)
    with get_db() as db:
        db.execute(
            "INSERT INTO linkcheck (url, result, checked_at) VALUES (?,?,?)",
            (result["url"], result["text"], now_iso()),
        )
        if result["broken"] >= 3:
            add_alarm(db, "broedte-links", f"{result['url']}: {result['broken']} broedte links fundet", "advarsel")
    return RedirectResponse("/", status_code=303)


# ---------- Social ko ----------
@app.post("/social/add")
async def add_social_post(platform: str = Form(...), message: str = Form(...)):
    if platform.strip() and message.strip():
        with get_db() as db:
            db.execute(
                "INSERT INTO socialqueue (platform, message, created_at) VALUES (?,?,?)",
                (platform.strip(), message.strip(), now_iso()),
            )
    return RedirectResponse("/", status_code=303)


@app.post("/social/delete")
async def delete_social_post(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM socialqueue WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


@app.get("/social/export.csv")
async def export_social_csv():
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["platform", "message", "status", "created_at"])
    with get_db() as db:
        for row in db.execute("SELECT platform, message, status, created_at FROM socialqueue ORDER BY id").fetchall():
            writer.writerow([row["platform"], row["message"], row["status"], row["created_at"]])
    return PlainTextResponse(
        buf.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=socialqueue.csv"},
    )


# ---------- Steamgears Autopilot-bro (WordPress-pluginnet steamgears-autopilot >= 7.5) ----------
# CC kalder pluginnets REST-API (/wp-json/sgap/v1) med samme WP_USER/WP_APP_PASSWORD som WordPress-push.
# Retningen er altid CC -> site: sitet kan ikke naa CC, der kun lytter paa 127.0.0.1.
SGAP_CHANNELS = {"facebook", "instagram", "pinterest", "linkedin", "twitter", "threads", "bluesky", "mastodon", "telegram", "google"}
SGAP_ALIASES = {"x": "twitter", "fb": "facebook", "ig": "instagram", "gmb": "google", "google business": "google"}


def sgap_ready() -> bool:
    return bool(WP_URL and WP_USER and WP_APP_PASSWORD) and module_on("autopilot")


def sgap_api(method: str, path: str, **kwargs):
    """Kald pluginnets REST-API. Kaster requests.HTTPError ved fejl-svar."""
    resp = HTTP.request(
        method,
        f"{WP_URL.rstrip('/')}/wp-json/sgap/v1{path}",
        auth=(WP_USER, WP_APP_PASSWORD),
        timeout=20,
        **kwargs,
    )
    resp.raise_for_status()
    return resp.json()


def sgap_channel(platform: str) -> str:
    key = (platform or "").strip().lower()
    key = SGAP_ALIASES.get(key, key)
    return key if key in SGAP_CHANNELS else ""


def sgap_error_text(exc: Exception) -> str:
    status = getattr(getattr(exc, "response", None), "status_code", None)
    if status in (401, 403):
        return f"WordPress afviste login ({status}): WP_USER skal vaere administrator med et gyldigt Application Password"
    if status == 404:
        return "Autopilot-API'et findes ikke (404): er Steamgears Autopilot 7.5+ installeret og aktiveret?"
    return f"Autopilot-pluginnet svarer ikke: {exc}"


def sgap_snapshot() -> dict:
    with get_db() as db:
        row = db.execute("SELECT value FROM settings WHERE key='sgap_snapshot'").fetchone()
    try:
        return jsonlib.loads(row["value"]) if row and row["value"] else {}
    except Exception:
        return {}


def sgap_sync() -> dict:
    """Henter status fra pluginnet, gemmer et snapshot og alarmerer ved nye fejl eller nye kladder."""
    if not sgap_ready():
        return {}
    previous = sgap_snapshot()
    snap = {"checked_at": now_iso(), "ok": False, "error": "", "queue": {}, "channels": [], "pending_drafts": 0}
    try:
        stats = sgap_api("GET", "/stats", params={"days": 30})
        drafts = sgap_api("GET", "/drafts", params={"status": "pending", "limit": 100})
        snap["ok"] = True
        snap["queue"] = {r["status"]: int(r["count"]) for r in stats.get("queue", [])}
        channels = {}
        for r in stats.get("events", []):
            c = channels.setdefault(r["channel"], {"channel": r["channel"], "publish": 0, "click": 0, "order": 0, "revenue": 0.0})
            if r["event_type"] in ("publish", "click", "order"):
                c[r["event_type"]] = int(r["count"])
            if r["event_type"] == "order":
                c["revenue"] = round(float(r["value"] or 0), 2)
        snap["channels"] = sorted(channels.values(), key=lambda c: (-c["revenue"], -c["click"]))
        snap["pending_drafts"] = len(drafts) if isinstance(drafts, list) else 0
    except Exception as e:
        snap["error"] = sgap_error_text(e)
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('sgap_snapshot', ?)", (jsonlib.dumps(snap),))
        # Kun alarm naar noget AENDRER sig, saa Telegram ikke spammes hver halve time.
        if snap["error"] and snap["error"] != previous.get("error"):
            add_alarm(db, "autopilot", snap["error"], "advarsel")
        if snap["ok"]:
            failed, failed_before = snap["queue"].get("failed", 0), previous.get("queue", {}).get("failed", 0)
            if failed > failed_before:
                add_alarm(db, "autopilot", f"{failed - failed_before} opslag fejlede i Steamgears Autopilot (se Queue i WordPress)", "advarsel")
            drafts_now, drafts_before = snap["pending_drafts"], previous.get("pending_drafts", 0)
            if drafts_now > drafts_before:
                add_alarm(db, "autopilot", f"{drafts_now} AI-kladde(r) venter paa godkendelse i WordPress", "info")
    return snap


async def job_sgap_sync():
    if not sgap_ready():
        return
    await asyncio.get_running_loop().run_in_executor(executor, sgap_sync)


@app.post("/autopilot/sync")
async def autopilot_sync_now():
    await asyncio.get_running_loop().run_in_executor(executor, sgap_sync)
    return RedirectResponse("/", status_code=303)


@app.post("/social/to-autopilot")
async def social_to_autopilot(id: int = Form(...)):
    """Send et opslag fra CC's sociale koe til pluginnet som AI-kladde (godkendes i WordPress)."""
    with get_db() as db:
        post = db.execute("SELECT platform, message FROM socialqueue WHERE id=?", (id,)).fetchone()
    if not post:
        return RedirectResponse("/", status_code=303)
    channel = sgap_channel(post["platform"])
    if not sgap_ready() or not channel:
        why = "WP_URL/WP_USER/WP_APP_PASSWORD mangler eller modulet er slukket" if not sgap_ready() else f"platformen '{post['platform']}' kendes ikke af autopiloten"
        with get_db() as db:
            add_alarm(db, "autopilot", f"Kunne ikke sende opslag til autopiloten: {why}", "advarsel")
        return RedirectResponse("/", status_code=303)
    message = post["message"].strip()
    title = message.split("\n", 1)[0][:90]

    def send():
        return sgap_api("POST", "/drafts", json={"channel": channel, "title": title, "body": message, "ai_model": "command-center"})

    try:
        result = await asyncio.get_running_loop().run_in_executor(executor, send)
        with get_db() as db:
            db.execute("UPDATE socialqueue SET status=? WHERE id=?", (f"sendt til autopilot (kladde #{result.get('id')})", id))
    except Exception as e:
        with get_db() as db:
            add_alarm(db, "autopilot", "Kunne ikke sende opslag: " + sgap_error_text(e), "advarsel")
    return RedirectResponse("/", status_code=303)


# ---------- Keywords (SerpAPI) ----------
def check_keyword_sync(kw_row):
    kw = kw_row["keyword"]
    if not SERPAPI_KEY:
        return {"position": None, "url": None, "error": "SERPAPI_KEY ikke sat i .env"}
    try:
        resp = HTTP.get(
            "https://serpapi.com/search",
            params={"engine": "google", "q": kw, "api_key": SERPAPI_KEY, "num": 50},
            timeout=20,
        )
        resp.raise_for_status()
        data = resp.json()
        position = None
        url = None
        for i, item in enumerate(data.get("organic_results", []), start=1):
            link = item.get("link", "")
            if TRACK_DOMAIN in link:
                position = i
                url = link
                break
        return {"position": position, "url": url, "error": None}
    except Exception as e:
        return {"position": None, "url": None, "error": str(e)[:200]}


def check_all_keywords_sync():
    with get_db() as db:
        kws = db.execute("SELECT * FROM keywords").fetchall()
    for kw in kws:
        try:
            res = check_keyword_sync(kw)
        except Exception as e:
            res = {"position": None, "url": None, "error": str(e)[:120]}
        with get_db() as db:
            if res["error"]:
                add_alarm(db, "keyword-tjek", f"'{kw['keyword']}': {res['error']}", "advarsel")
            else:
                db.execute(
                    "UPDATE keywords SET position=?, target_url=?, checked_at=? WHERE id=?",
                    (res["position"], res["url"], now_iso(), kw["id"]),
                )
    with get_db() as db:
        kws2 = db.execute("SELECT * FROM keywords").fetchall()
        score = 0.0
        for kw in kws2:
            if kw["position"] and kw["position"] <= 50:
                score += (51 - kw["position"]) / 50
        vis = round(score / max(len(kws2), 1) * 100, 1) if kws2 else 0.0
        db.execute(
            "INSERT INTO visibility (day, score) VALUES (?,?) "
            "ON CONFLICT(day) DO UPDATE SET score=excluded.score",
            (date.today().isoformat(), vis),
        )


@app.post("/keywords/add")
async def add_keyword(keyword: str = Form(...)):
    keyword = keyword.strip()
    if keyword:
        with get_db() as db:
            db.execute("INSERT OR IGNORE INTO keywords (keyword) VALUES (?)", (keyword,))
    return RedirectResponse("/", status_code=303)


@app.post("/keywords/delete")
async def delete_keyword(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM keywords WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


@app.post("/keywords/check")
async def check_keywords():
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, check_all_keywords_sync)
    return RedirectResponse("/", status_code=303)


# ---------- Alarmer ----------
@app.post("/alerts/test")
async def alerts_test(channel: str = Form("all")):
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(executor, alert_test_sync, channel)
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_alert_test', ?)",
                   (jsonlib.dumps({"at": now_iso(), "result": result}),))
    return RedirectResponse("/", status_code=303)


@app.get("/api/alerts/status")
async def alerts_status():
    with get_db() as db:
        counts = {r["state"]: r["n"] for r in
                  db.execute("SELECT state, COUNT(*) AS n FROM alert_outbox GROUP BY state").fetchall()}
        problems = db.execute(
            "SELECT channel, subject, attempts, last_error, created_at FROM alert_outbox "
            "WHERE last_error IS NOT NULL AND state IN ('pending','failed') ORDER BY id DESC LIMIT 10"
        ).fetchall()
    return JSONResponse({
        "channels": alert_channels(),
        "min_severity": ALERT_MIN_SEVERITY,
        "quiet_hours": ALERT_QUIET_HOURS,
        "quiet_now": in_quiet_hours(),
        "dedupe_minutes": ALERT_DEDUPE_MINUTES,
        "outbox": counts,
        "problems": [dict(p) for p in problems],
    })


@app.post("/alarms/resolve")
async def resolve_alarm(id: int = Form(...)):
    with get_db() as db:
        db.execute("UPDATE alarms SET resolved=1 WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


# ---------- v7.9 Stabilitet: DB-backup + opstarts-selvtest ----------
def backup_db_sync(tag: str = "daglig"):
    try:
        bdir = os.path.join(BASE_DIR, "backups")
        os.makedirs(bdir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d-%H%M")
        dest = os.path.join(bdir, "cc-" + tag + "-" + ts + ".db")
        src = sqlite3.connect(DB_PATH)
        dst = sqlite3.connect(dest)
        with dst:
            src.backup(dst)
        dst.close()
        src.close()
        backups = sorted(f for f in os.listdir(bdir) if f.startswith("cc-" + tag + "-") and f.endswith(".db"))
        for old in backups[:-14]:
            try:
                os.remove(os.path.join(bdir, old))
            except OSError:
                pass
        with get_db() as db:
            db.execute("INSERT INTO settings(key, value) VALUES('last_db_backup', ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (jsonlib.dumps(now_iso()),))
        return dest
    except Exception as e:
        try:
            with get_db() as db:
                add_alarm(db, "backup", "DB-backup fejlede: " + str(e)[:120], "advarsel")
        except Exception:
            pass
        return None


def startup_selftest_sync():
    fejl = []
    ruter = len(app.routes)
    try:
        with get_db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS _selftest(x TEXT)")
            db.execute("INSERT INTO _selftest(x) VALUES('ok')")
            db.execute("DELETE FROM _selftest")
    except Exception as e:
        fejl.append("DB-skrivetest: " + str(e)[:80])
    if user_count() and not AIMLAPI_KEY:
        fejl.append("AIMLAPI_KEY mangler - AI-artikler vil fejle")
    if ruter < 40:
        fejl.append("Kun " + str(ruter) + " ruter registreret (forventet 50+)")
    try:
        with get_db() as db:
            if fejl:
                add_alarm(db, "selftest", "Selvtest ved opstart FEJLEDE: " + " | ".join(fejl)[:300], "kritisk")
                status = {"ok": False, "at": now_iso(), "fejl": fejl}
            else:
                status = {"ok": True, "at": now_iso(), "ruter": ruter}
            db.execute("INSERT INTO settings(key, value) VALUES('last_selftest', ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (jsonlib.dumps(status),))
    except Exception as e:
        print("[cc] selvtest kunne ikke gemme resultat:", repr(e), flush=True)
    print("[cc] opstarts-selvtest:", "OK (" + str(ruter) + " ruter)" if not fejl else "FEJL: " + "; ".join(fejl), flush=True)


async def job_backup_db():
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, backup_db_sync)


@app.post("/self-update")
async def self_update():
    """Bevaret for gamle bogmaerker: koerer GitHub-opdateringen (backup + filsynk)."""
    return await update_apply_now()


# ---------- Opdatering fra GitHub (repo-synk, ikke remote shell) ----------
# Henter tarballen for seneste commit paa main og skriver kun whitelistede projektfiler.
# Der laves DB-backup foer hver opdatering, og appen skal genstartes bagefter.
UPDATE_PATHS = (
    "app/", "scripts/", "deploy/", "requirements.txt", "README.md", "run.sh", "run.bat",
    "install.sh", "Dockerfile", "docker-compose.yml", ".env.example",
)


def _gh_headers(accept: str = "application/vnd.github+json") -> dict:
    headers = {"Accept": accept, "User-Agent": f"CommandCenter/{APP_VERSION}"}
    if GITHUB_TOKEN:
        headers["Authorization"] = "Bearer " + GITHUB_TOKEN
    return headers


def deployed_commit() -> str:
    """Installeret commit (fra settings, ellers fra git-historikken - som saa gemmes)."""
    try:
        with get_db() as db:
            row = db.execute("SELECT value FROM settings WHERE key='deployed_commit'").fetchone()
        if row and row["value"]:
            return row["value"]
    except Exception:
        pass
    try:
        out = subprocess.run(["git", "-C", os.path.dirname(BASE_DIR), "rev-parse", "HEAD"],
                             capture_output=True, text=True, timeout=5)
        sha = out.stdout.strip() if out.returncode == 0 else ""
        if sha:
            with get_db() as db:
                db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('deployed_commit', ?)", (sha,))
            return sha
    except Exception:
        pass
    return ""


def update_check_sync() -> dict:
    """Sammenligner installeret commit med seneste commit paa main."""
    result = {"ok": False, "current": deployed_commit(), "latest": "", "behind": False,
              "date": "", "message": "", "url": "", "error": ""}
    if not GITHUB_TOKEN:
        result["error"] = "GITHUB_TOKEN mangler - opdatering fra GitHub kraever adgang til repoet"
        return result
    try:
        r = HTTP.get(f"https://api.github.com/repos/{GITHUB_REPO}/commits",
                     params={"sha": "main", "per_page": 1}, headers=_gh_headers(), timeout=20)
        if r.status_code in (401, 403):
            result["error"] = "GitHub afviste adgang (401/403) - tjek GITHUB_TOKEN"
            return result
        if r.status_code == 404:
            result["error"] = f"Repoet {GITHUB_REPO} blev ikke fundet - tjek GITHUB_REPO"
            return result
        r.raise_for_status()
        commits = r.json()
        if not isinstance(commits, list) or not commits:
            result["error"] = "Ingen commits fundet paa main"
            return result
        commit = commits[0]
        info = commit.get("commit") or {}
        result["latest"] = commit.get("sha", "")
        result["date"] = (info.get("author") or {}).get("date", "")
        result["message"] = (info.get("message") or "").splitlines()[0][:200]
        result["url"] = commit.get("html_url", "")
        result["behind"] = bool(result["latest"] and result["latest"] != result["current"])
        result["ok"] = True
    except Exception as e:
        result["error"] = "Opdaterings-tjek fejlede: " + str(e)[:150]
    return result


def _safe_extract(tar, dest: str):
    """Pak kun whitelistede filer ud - ingen .., absolutte stier eller links."""
    written = []
    for member in tar.getmembers():
        if not member.isfile():
            continue
        parts = member.name.split("/", 1)      # GitHub-tarball: <owner>-<repo>-<sha>/<sti>
        if len(parts) != 2:
            continue
        rel = parts[1]
        if rel.startswith("/") or ".." in rel.split("/"):
            continue
        if not any(rel == p or rel.startswith(p) for p in UPDATE_PATHS):
            continue
        source = tar.extractfile(member)
        if source is None:
            continue
        target = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(target) or dest, exist_ok=True)
        with open(target, "wb") as fh:
            shutil.copyfileobj(source, fh)
        written.append(rel)
    return written


def _install_requirements() -> dict:
    """Koer pip install -r requirements.txt i projektets venv efter en opdatering."""
    project = os.path.dirname(BASE_DIR)
    requirements = os.path.join(project, "requirements.txt")
    pip = os.path.join(project, "venv", "bin", "pip")
    if not os.path.exists(pip):
        pip = shutil.which("pip3") or shutil.which("pip") or ""
    if not pip:
        return {"ok": False, "output": "pip blev ikke fundet - koer 'pip install -r requirements.txt' selv"}
    try:
        proc = subprocess.run([pip, "install", "-q", "-r", requirements],
                              capture_output=True, text=True, timeout=300, cwd=project)
        output = ((proc.stdout or "") + (proc.stderr or "")).strip()
        return {"ok": proc.returncode == 0, "output": output[-400:]}
    except Exception as e:
        return {"ok": False, "output": str(e)[:200]}


def restart_mode() -> str:
    """Hvordan appen kan genstartes her: custom, systemd-user, systemd, script eller manual."""
    if os.environ.get("UPDATE_RESTART_CMD"):
        return "custom"
    try:
        if subprocess.run(["systemctl", "--user", "cat", "command-center"],
                          capture_output=True, timeout=5).returncode == 0:
            return "systemd-user"
    except Exception:
        pass
    try:
        if subprocess.run(["systemctl", "cat", "command-center"],
                          capture_output=True, timeout=5).returncode == 0:
            return "systemd"
    except Exception:
        pass
    return "script" if os.path.exists(os.path.join(os.path.dirname(BASE_DIR), "scripts", "restart.sh")) else "manual"


def schedule_restart(delay: float = 1.5) -> dict:
    """Planlaeg genstart EFTER HTTP-svaret er sendt (systemd-unit eller scripts/restart.sh).

    Kan slaa s fra med UPDATE_AUTO_RESTART=0; UPDATE_RESTART_CMD overstyrer kommandoen."""
    mode = restart_mode()
    if os.environ.get("UPDATE_AUTO_RESTART", "1") in ("0", "false", "no"):
        return {"scheduled": False, "mode": mode, "reason": "UPDATE_AUTO_RESTART=0"}
    project = os.path.dirname(BASE_DIR)
    script = os.path.join(project, "scripts", "restart.sh")
    try:
        if os.environ.get("UPDATE_RESTART_CMD"):
            cmd = ["bash", "-lc", f"sleep {delay}; {os.environ['UPDATE_RESTART_CMD']}"]
        elif os.path.exists(script):
            cmd = ["bash", script, "--delay", str(delay)]
        elif mode == "systemd-user":
            cmd = ["bash", "-lc", f"sleep {delay}; systemctl --user restart command-center"]
        elif mode == "systemd":
            cmd = ["bash", "-lc", f"sleep {delay}; systemctl restart command-center"]
        else:
            return {"scheduled": False, "mode": mode,
                    "reason": "ingen systemd-unit og ingen scripts/restart.sh - genstart manuelt"}
        subprocess.Popen(cmd, cwd=project, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return {"scheduled": True, "mode": mode}
    except Exception as e:
        return {"scheduled": False, "mode": mode, "reason": str(e)[:150]}


def update_apply_sync() -> dict:
    """Backup + hent seneste tarball + skriv whitelistede filer + requirements. Genstart bagefter."""
    if not GITHUB_TOKEN:
        return {"ok": False, "error": "GITHUB_TOKEN mangler - opdatering fra GitHub kraever adgang til repoet"}
    check = update_check_sync()
    if not check["ok"]:
        return {"ok": False, "error": check["error"]}
    ref = check["latest"] or "main"
    try:
        backup_db_sync(tag="pre-update")       # rollback-punkt foer nye filer skrives
        r = HTTP.get(f"https://api.github.com/repos/{GITHUB_REPO}/tarball/{ref}",
                     headers=_gh_headers(), timeout=120)
        r.raise_for_status()
        with tarfile.open(fileobj=io.BytesIO(r.content), mode="r:gz") as tar:
            written = _safe_extract(tar, os.path.dirname(BASE_DIR))
        if not written:
            return {"ok": False, "error": "Tarballen indeholdt ingen kendte projektfiler"}
        requirements_changed = "requirements.txt" in written
        requirements_install = _install_requirements() if requirements_changed else {"ok": True, "output": "uaendret"}
        with get_db() as db:
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('deployed_commit', ?)", (ref,))
            add_alarm(db, "opdatering", f"Hentede {ref[:7]} fra GitHub ({len(written)} filer) - genstart appen", "info")
        return {"ok": True, "error": "", "current": check["current"], "latest": ref, "behind": False,
                "files": written, "needs_restart": True,
                "requirements_changed": requirements_changed,
                "requirements_install": requirements_install}
    except Exception as e:
        return {"ok": False, "error": "Opdatering fejlede: " + str(e)[:180]}


@app.get("/api/update")
async def api_update():
    with get_db() as db:
        row = db.execute("SELECT value FROM settings WHERE key='github_update'").fetchone()
    cached = {}
    try:
        cached = jsonlib.loads(row["value"]) if row and row["value"] else {}
    except Exception:
        cached = {}
    return JSONResponse({"current": deployed_commit(), "repo": GITHUB_REPO,
                         "token": bool(GITHUB_TOKEN), "restart_mode": restart_mode(),
                         "auto_restart": os.environ.get("UPDATE_AUTO_RESTART", "1") not in ("0", "false", "no"),
                         "last_check": cached})


@app.post("/update/check")
async def update_check_now():
    result = await asyncio.get_running_loop().run_in_executor(executor, update_check_sync)
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('github_update', ?)",
                   (jsonlib.dumps(result),))
        if not result["ok"]:
            add_alarm(db, "opdatering", "Tjek for nye commits fejlede: " + result["error"], "advarsel")
        elif result["behind"]:
            add_alarm(db, "opdatering", f"Ny version paa GitHub: {result['latest'][:7]} - {result['message']}", "info")
    return RedirectResponse("/", status_code=303)


def store_update_result(result: dict):
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('github_update', ?)",
                   (jsonlib.dumps(result),))
        if not result.get("ok"):
            add_alarm(db, "opdatering", result.get("error", "ukendt fejl"), "advarsel")


@app.post("/update/apply")
async def update_apply_now(restart: str = Form("1")):
    result = await asyncio.get_running_loop().run_in_executor(executor, update_apply_sync)
    if result.get("ok"):
        result["restart"] = (schedule_restart() if restart == "1"
                             else {"scheduled": False, "mode": restart_mode(), "reason": "genstart fravalgt"})
    store_update_result(result)
    return RedirectResponse("/", status_code=303)


@app.post("/api/update/check")
async def api_update_check():
    """Maskin-endpoint til scripts/update.sh - samme tjek som knappen, men JSON."""
    result = await asyncio.get_running_loop().run_in_executor(executor, update_check_sync)
    store_update_result(result)
    return JSONResponse(result)


@app.post("/api/update/apply")
async def api_update_apply(request: Request):
    """Maskin-endpoint: hent filer, installér requirements og genstart (medmindre restart=0)."""
    restart = request.query_params.get("restart", "1") not in ("0", "false", "no")
    result = await asyncio.get_running_loop().run_in_executor(executor, update_apply_sync)
    if result.get("ok"):
        result["restart"] = (schedule_restart() if restart
                             else {"scheduled": False, "mode": restart_mode(), "reason": "restart=0"})
    store_update_result(result)
    return JSONResponse(result)


async def job_update_check():
    if not GITHUB_TOKEN:
        return
    result = await asyncio.get_running_loop().run_in_executor(executor, update_check_sync)
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('github_update', ?)",
                   (jsonlib.dumps(result),))
        if result.get("ok") and result.get("behind"):
            add_alarm(db, "opdatering", f"Ny version paa GitHub: {result['latest'][:7]} - {result['message']}", "info")


# ---------- Duplicates & redirects rapport ----------
def duplicates_report():
    with get_db() as db:
        latest = " AND run_id=(SELECT id FROM crawl_runs ORDER BY id DESC LIMIT 1)"
        dup_titles = db.execute(
            "SELECT title, COUNT(*) AS n, GROUP_CONCAT(url, ' | ') AS urls FROM seopages "
            "WHERE title != ''" + latest + " GROUP BY LOWER(TRIM(title)) HAVING n > 1 ORDER BY n DESC LIMIT 20"
        ).fetchall()
        dup_h1 = db.execute(
            "SELECT h1, COUNT(*) AS n, GROUP_CONCAT(url, ' | ') AS urls FROM seopages "
            "WHERE h1 != ''" + latest + " GROUP BY LOWER(TRIM(h1)) HAVING n > 1 ORDER BY n DESC LIMIT 20"
        ).fetchall()
        dup_content = db.execute(
            "SELECT content_hash, COUNT(*) AS n, GROUP_CONCAT(url, ' | ') AS urls FROM seopages "
            "WHERE content_hash != ''" + latest + " GROUP BY content_hash HAVING n > 1 ORDER BY n DESC LIMIT 20"
        ).fetchall()
        redirects = db.execute(
            "SELECT url, redirects FROM seopages WHERE redirects != ''" + latest + " ORDER BY id LIMIT 50"
        ).fetchall()
    return {"titles": [dict(r) for r in dup_titles], "h1": [dict(r) for r in dup_h1],
            "content": [dict(r) for r in dup_content], "redirects": [dict(r) for r in redirects]}


@app.get("/api/duplicates")
async def get_duplicates():
    return JSONResponse(duplicates_report())


# ---------- AI: interne links, meta/social, synlighed ----------
def ai_chat(prompt: str, max_tokens: int = 1500):
    resp = HTTP.post(
        "https://api.aimlapi.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {AIMLAPI_KEY}", "Content-Type": "application/json"},
        json={"model": AI_MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": max_tokens},
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


@app.post("/seo/linksuggest")
async def suggest_internal_links():
    if not AIMLAPI_KEY:
        return JSONResponse({"ok": False, "error": "AIMLAPI_KEY ikke sat"})
    with get_db() as db:
        pages = db.execute(
            "SELECT url, title, h1, words FROM seopages "
            "WHERE run_id=(SELECT id FROM crawl_runs ORDER BY id DESC LIMIT 1) ORDER BY score DESC LIMIT 40"
        ).fetchall()
        kws = [r["keyword"] for r in db.execute("SELECT keyword FROM keywords LIMIT 20").fetchall()]
    if len(pages) < 3:
        return JSONResponse({"ok": False, "error": "Koer foerst et site-crawl (min. 3 sider)"})
    listing = "\n".join([f"- {p['url']} | titel: {p['title'][:70]} | H1: {p['h1'][:50]}" for p in pages])
    prompt = (
        "You are an internal linking strategist for a steampunk cosplay webshop. "
        "Given this list of pages:\n" + listing +
        "\nAnd target keywords: " + ", ".join(kws) +
        "\nSuggest 8-12 internal links that should be added (from one page to another, both must be in the list). "
        'Return ONLY a JSON array like [{"from":"URL","to":"URL","anchor":"anchor text","reason":"short reason"}]. No markdown.'
    )
    try:
        loop = asyncio.get_running_loop()
        raw = await loop.run_in_executor(executor, ai_chat, prompt)
        m = re.search(r"\[.*\]", raw, re.S)
        suggestions = jsonlib.loads(m.group(0)) if m else []
        with get_db() as db:
            db.execute("DELETE FROM internal_links")
            for s in suggestions[:12]:
                db.execute("INSERT INTO internal_links (from_url, to_url, anchor, reason, created_at) VALUES (?,?,?,?,?)",
                           (s.get("from", ""), s.get("to", ""), s.get("anchor", ""), s.get("reason", ""), now_iso()))
        return JSONResponse({"ok": True, "count": len(suggestions)})
    except Exception as e:
        return JSONResponse({"ok": False, "error": str(e)[:200]})


def rewrite_meta_sync(url: str, title: str, desc: str, keyword: str):
    if not AIMLAPI_KEY:
        return {"error": "AIMLAPI_KEY ikke sat"}
    prompt = (
        "Du er en SEO-ekspert for " + TRACK_DOMAIN + ". Optimer denne side:\n"
        "URL: " + url + "\n"
        "Nuvaerende title: " + (title or "(ingen)") + "\n"
        "Nuvaerende meta description: " + (desc or "(ingen)") + "\n"
        "Focus keyword: " + (keyword or title[:60]) + "\n\n"
        "Svar KUN med gyldig JSON (ingen markdown): "
        '{"titles": ["<60 tegn titel 1", "titel 2", "titel 3"], '
        '"descriptions": ["<155 tegn description 1", "description 2", "description 3"], '
        '"note": "kort begrundelse pa dansk"}'
    )
    return ai_chat(prompt, max_tokens=800, temperature=0.7)


@app.post("/seo/rewrite")
async def seo_rewrite(request: Request):
    if not is_authed(request):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    form = await request.form()
    url = str(form.get("url", "")).strip()
    if not url:
        return JSONResponse({"error": "url paakraevet"}, status_code=400)
    # Hent titel/meta live - crawl-data kan vaere foraeldet eller fra en anden URL.
    title = desc = ""
    try:
        r = safe_request(url, timeout=10)
        soup = BeautifulSoup(r.text, "html.parser")
        t = soup.find("title")
        title = t.get_text(strip=True) if t else ""
        m = soup.find("meta", attrs={"name": "description"})
        desc = m.get("content", "") if m else ""
    except Exception:
        pass
    kw = str(form.get("keyword", "")).strip()
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(executor, rewrite_meta_sync, url, title, desc, kw)
    return JSONResponse(result)


@app.post("/articles/meta")
async def generate_meta(id: int = Form(...)):
    if not AIMLAPI_KEY:
        return RedirectResponse("/", status_code=303)
    with get_db() as db:
        art = db.execute("SELECT * FROM articles WHERE id=?", (id,)).fetchone()
    if not art:
        return RedirectResponse("/", status_code=303)
    text = re.sub(r"<[^>]+>", " ", art["content"])[:3000]
    prompt = (
        f"For this article titled '{art['title']}', produce EXACTLY this JSON (no markdown): "
        '{"meta_title":"max 60 chars","meta_description":"70-160 chars","social_post":"punchy social media post, max 240 chars, 2-3 relevant hashtags"}. '
        "Article text:\n" + text
    )
    try:
        loop = asyncio.get_running_loop()
        raw = await loop.run_in_executor(executor, ai_chat, prompt)
        m = re.search(r"\{.*\}", raw, re.S)
        data = jsonlib.loads(m.group(0)) if m else {}
        with get_db() as db:
            db.execute("UPDATE articles SET meta_title=?, meta_desc=? WHERE id=?",
                       (data.get("meta_title", ""), data.get("meta_description", ""), id))
            post = data.get("social_post", "")
            if post:
                db.execute("INSERT INTO socialqueue (platform, message, created_at) VALUES (?,?,?)",
                           ("auto: " + art["keyword"], post, now_iso()))
    except Exception as e:
        with get_db() as db:
            add_alarm(db, "ai-meta", f"Meta/social-generering fejlede for artikel #{id}: {str(e)[:150]}", "advarsel")
    return RedirectResponse("/", status_code=303)


@app.post("/ai/visibility")
async def ai_visibility(question: str = Form(...)):
    if not AIMLAPI_KEY:
        return RedirectResponse("/", status_code=303)
    question = question.strip()
    if not question:
        return RedirectResponse("/", status_code=303)
    try:
        loop = asyncio.get_running_loop()
        answer = await loop.run_in_executor(executor, ai_chat, question + " Name specific websites and shops in your answer.", 800)
        found = TRACK_DOMAIN.lower() in answer.lower()
        snippet = ""
        idx = answer.lower().find(TRACK_DOMAIN.lower())
        if idx >= 0:
            snippet = answer[max(idx - 120, 0):idx + 160]
        with get_db() as db:
            db.execute("INSERT INTO ai_visibility (question, mention_found, snippet, answer, checked_at) VALUES (?,?,?,?,?)",
                       (question, int(found), snippet, answer[:2000], now_iso()))
    except Exception as e:
        with get_db() as db:
            add_alarm(db, "ai-synlighed", f"Synlighedstjek fejlede: {str(e)[:150]}", "advarsel")
    return RedirectResponse("/", status_code=303)


# ---------- Keyword/content-monitors ----------

def add_alarm_sync_global(message):
    try:
        with get_db() as db:
            add_alarm(db, "pris-monitor", message, "advarsel")
    except Exception:
        pass


def run_monitor_sync(m):
    """Returnerer (status, ok, vaerdi) - vaerdi er den raa talvaerdi for pris-monitors."""
    url = m["url"]
    try:
        resp = safe_request(url, timeout=10)
        if resp.status_code >= 400:
            return f"HTTP-fejl {resp.status_code}", False, None
        if m["type"] == "contains":
            ok = m["expected"] in resp.text
            return ("Fundet" if ok else "IKKE fundet: " + m["expected"][:50], ok, None)
        elif m["type"] == "price":
            psoup = BeautifulSoup(resp.text, "html.parser")
            price = None
            pm = psoup.find("meta", attrs={"property": "product:price:amount"})
            if pm:
                price = pm.get("content")
            if not price:
                for s in psoup.find_all("script", attrs={"type": "application/ld+json"}):
                    try:
                        d = jsonlib.loads(s.string or "{}")
                        offers = d.get("offers") or {}
                        if isinstance(offers, list) and offers:
                            offers = offers[0]
                        price = offers.get("price") or d.get("price")
                        if price:
                            break
                    except Exception:
                        continue
            if price is None:
                return "Ingen pris fundet paa siden", False, None
            # Sammenlign med den gemte talvaerdi (last_value), ikke med status-teksten.
            prev = str(m["last_value"] or "").strip()
            try:
                changed = bool(prev) and abs(float(prev) - float(price)) > 0.001
            except Exception:
                changed = False
            if changed:
                add_alarm_sync_global(f"Prisaendring paa {url}: {prev} -> {price}")
            return f"Pris: {price}" + (f" (var {prev})" if changed else ""), True, str(price)
        elif m["type"] == "json":
            data = resp.json()
            node = data
            for part in m["expected"].split("."):
                if isinstance(node, list) and part.isdigit():
                    node = node[int(part)]
                elif isinstance(node, dict):
                    node = node.get(part)
                else:
                    node = None
                    break
            ok = bool(node)
            return (f"JSON-path '{m['expected']}' = {str(node)[:60]}", ok, None)
        return "Ukendt type", False, None
    except Exception as e:
        return f"Fejl: {str(e)[:120]}", False, None


def check_all_monitors_sync():
    with get_db() as db:
        monitors = db.execute("SELECT * FROM monitors").fetchall()
    for m in monitors:
        status, ok, value = run_monitor_sync(m)
        with get_db() as db:
            db.execute("UPDATE monitors SET last_status=?, last_result=?, last_value=?, last_checked=? WHERE id=?",
                       (status, status, value, now_iso(), m["id"]))
            if not ok:
                add_alarm(db, "monitor", f"{m['name']} ({m['url']}): {status}", "kritisk")


@app.post("/monitors/add")
async def add_monitor(name: str = Form(...), url: str = Form(...), type_: str = Form(...), expected: str = Form(...)):
    if not (name.strip() and url.strip() and expected.strip()):
        return RedirectResponse("/", status_code=303)
    if type_ not in ("contains", "json", "price"):
        type_ = "contains"
    try:
        clean_url = normalize_url(url)
    except ValueError as e:
        with get_db() as db:
            add_alarm(db, "monitor", f"Kunne ikke tilfoeje monitor '{name.strip()}': {e}", "advarsel")
        return RedirectResponse("/", status_code=303)
    with get_db() as db:
        db.execute("INSERT INTO monitors (name, url, type, expected) VALUES (?,?,?,?)",
                   (name.strip(), clean_url, type_, expected.strip()))
    return RedirectResponse("/", status_code=303)


@app.post("/monitors/delete")
async def delete_monitor(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM monitors WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


@app.post("/monitors/check")
async def check_monitors():
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, check_all_monitors_sync)
    return RedirectResponse("/", status_code=303)


@app.get("/api/health-history")
async def health_history():
    with get_db() as db:
        rows = db.execute("SELECT checked_at, avg_score FROM health_history ORDER BY id DESC LIMIT 40").fetchall()
    rows = list(reversed(rows))
    return JSONResponse({"labels": [r["checked_at"][5:16] for r in rows], "scores": [r["avg_score"] for r in rows]})


# ---------- PRO: keyword-ideer, content gap, outreach ----------
def autocomplete_sources(keyword: str):
    ideas = []
    try:
        r = HTTP.get(
            "https://suggestqueries.google.com/complete/search",
            params={"client": "firefox", "q": keyword, "hl": "en"},
            timeout=8,
        )
        for item in r.json()[1][:15]:
            ideas.append((item, "Google suggest"))
    except Exception:
        pass
    try:
        r2 = HTTP.get("https://duckduckgo.com/ac/", params={"q": keyword, "type": "list"}, timeout=8)
        data = r2.json()
        for item in (data[1] if isinstance(data, list) and len(data) > 1 else []):
            if item not in [i for i, _ in ideas]:
                ideas.append((item, "DuckDuckGo"))
    except Exception:
        pass
    return ideas


@app.post("/keywords/ideas")
async def keyword_ideas(keyword: str = Form(...)):
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    loop = asyncio.get_running_loop()
    ideas = await loop.run_in_executor(executor, autocomplete_sources, keyword)
    with get_db() as db:
        for idea, source in ideas:
            db.execute("INSERT OR IGNORE INTO keyword_ideas (keyword, idea, source, created_at) VALUES (?,?,?,?)",
                       (keyword, idea, source, now_iso()))
    return RedirectResponse("/", status_code=303)


AUTHORITY_DOMAINS = {
    "wikipedia.org", "youtube.com", "amazon.com", "reddit.com", "pinterest.com",
    "facebook.com", "instagram.com", "tiktok.com", "etsy.com", "ebay.com",
    "quora.com", "linkedin.com", "forbes.com", "nytimes.com", "wikihow.com",
}


def keyword_difficulty_sync(keyword: str):
    if not SERPAPI_KEY:
        return {"error": "SERPAPI_KEY ikke sat i .env"}
    try:
        resp = HTTP.get(
            "https://serpapi.com/search",
            params={"engine": "google", "q": keyword, "api_key": SERPAPI_KEY, "num": 10},
            timeout=25,
        )
        resp.raise_for_status()
        data = resp.json()
        organic = data.get("organic_results", [])[:10]
        ads = len(data.get("ads", data.get("shopping_results", [])) or [])
        domains = []
        authority = 0
        for item in organic:
            d = urlparse(item.get("link", "")).netloc.lower().replace("www.", "")
            if d and d not in domains:
                domains.append(d)
            if any(d == a or d.endswith("." + a) for a in AUTHORITY_DOMAINS):
                authority += 1
        # heuristic: baseline + authority-domains + faa unikke domainer (domineret af eet site) + ads
        difficulty = 20
        difficulty += authority * 9
        if len(domains) <= 4 and organic:
            difficulty += 15
        difficulty += 3 if ads else 0
        difficulty = max(5, min(95, difficulty))
        label = "Let" if difficulty < 35 else ("Middel" if difficulty < 60 else ("Svaer" if difficulty < 80 else "Meget svaer"))
        top = ", ".join(domains[:5])
        with get_db() as db:
            db.execute(
                "INSERT OR REPLACE INTO keyword_difficulty (keyword, difficulty, domains, authority, ads, top_domains, created_at) VALUES (?,?,?,?,?,?,?)",
                (keyword, difficulty, len(domains), authority, ads, top, now_iso()),
            )
        return {"ok": True, "keyword": keyword, "difficulty": difficulty, "label": label,
                "domains": len(domains), "authority": authority, "ads": ads, "top_domains": top}
    except Exception as e:
        return {"error": str(e)[:200]}


@app.post("/keywords/difficulty")
async def kw_difficulty(request: Request):
    if not is_authed(request):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    form = await request.form()
    keyword = str(form.get("keyword", "")).strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(executor, keyword_difficulty_sync, keyword)
    if result.get("ok"):
        with get_db() as db2:
            add_alarm(db2, "keyword-difficulty", "Keyword '" + keyword + "': sværhedsgrad " + str(result["difficulty"]) + "/100 (" + result["label"] + ") — top: " + result["top_domains"][:80], "info")
    return RedirectResponse("/", status_code=303)


def serp_gap_sync(keyword: str):
    if not SERPAPI_KEY:
        return {"error": "SERPAPI_KEY ikke sat i .env"}
    try:
        resp = HTTP.get(
            "https://serpapi.com/search",
            params={"engine": "google", "q": keyword, "api_key": SERPAPI_KEY, "num": 10},
            timeout=25,
        )
        resp.raise_for_status()
        organic = resp.json().get("organic_results", [])[:10]
        stats = []
        titles = []
        for item in organic:
            link = item.get("link", "")
            title = item.get("title", "")
            titles.append(title)
            words = h2s = 0
            try:
                pr = safe_request(link, timeout=8)
                psoup = BeautifulSoup(pr.text, "html.parser")
                for t in psoup(["script", "style", "noscript"]):
                    t.decompose()
                words = len(psoup.get_text().split())
                h2s = len(psoup.find_all("h2"))
            except Exception:
                pass
            stats.append({"url": link, "words": words, "h2": h2s})
        good = [s for s in stats if s["words"]]
        summary = {
            "avg_words": round(sum(s["words"] for s in good) / len(good)) if good else 0,
            "avg_h2": round(sum(s["h2"] for s in good) / len(good), 1) if good else 0,
            "pages_fetched": len(good),
        }
        with get_db() as db:
            db.execute("INSERT INTO content_gap (keyword, stats_json, top_titles, created_at) VALUES (?,?,?,?)",
                       (keyword, jsonlib.dumps({"summary": summary, "stats": stats}), " | ".join(titles[:10]), now_iso()))
        return {"ok": True, "summary": summary, "stats": stats, "titles": titles}
    except Exception as e:
        return {"error": str(e)[:200]}


@app.post("/serp/gap")
async def serp_gap(keyword: str = Form(...)):
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, serp_gap_sync, keyword)
    return RedirectResponse("/", status_code=303)


def content_score(article, gap):
    if not gap or "summary" not in gap:
        return None
    target_words = gap["summary"]["avg_words"] or 600
    target_h2 = gap["summary"]["avg_h2"] or 4
    soup = BeautifulSoup(article["content"], "html.parser")
    words = len(soup.get_text().split())
    h2s = len(soup.find_all("h2"))
    kw = (article["keyword"] or "").lower()
    text_l = soup.get_text().lower()
    kw_hits = text_l.count(kw) if kw else 0
    w_score = min(words / target_words, 1.0) * 40
    h_score = min(h2s / target_h2, 1.0) * 30
    k_score = min(kw_hits / 6, 1.0) * 30
    return {"score": round(w_score + h_score + k_score), "words": words, "target_words": target_words,
            "h2": h2s, "target_h2": target_h2, "kw_hits": kw_hits}


@app.post("/articles/score")
async def article_score(id: int = Form(...)):
    with get_db() as db:
        art = db.execute("SELECT * FROM articles WHERE id=?", (id,)).fetchone()
    if not art:
        return RedirectResponse("/", status_code=303)
    with get_db() as db:
        gap_row = db.execute("SELECT * FROM content_gap WHERE keyword=? ORDER BY id DESC LIMIT 1", (art["keyword"],)).fetchone()
    if gap_row:
        gap = {"summary": jsonlib.loads(gap_row["stats_json"])["summary"]}
    else:
        loop = asyncio.get_running_loop()
        gap = await loop.run_in_executor(executor, serp_gap_sync, art["keyword"])
    result = content_score(art, gap)
    if result:
        result["status"] = f"Content Score: {result['score']}/100 (mal: {result['target_words']} ord, {result['target_h2']} H2)"
    else:
        result = {"status": f"Kunne ikke saette score: {gap.get('error', 'ingen SERP-data')}" if isinstance(gap, dict) else "Ingen data"}
    with get_db() as db:
        db.execute("INSERT INTO notes (content, created_at) VALUES (?,?)",
                   (f"[Content Score] {art['title']}: {result.get('status', '')}", now_iso()))
    return RedirectResponse("/", status_code=303)


@app.post("/outreach/scan")
async def outreach_scan(url: str = Form(...)):
    try:
        url = normalize_url(url)
    except ValueError:
        return RedirectResponse("/", status_code=303)
    def scan(u):
        try:
            resp = safe_request(u, timeout=10)
            emails = set(re.findall(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]{2,}", resp.text))
            emails = {e for e in emails if not e.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".webp"))}
            return emails
        except Exception:
            return set()
    loop = asyncio.get_running_loop()
    emails = await loop.run_in_executor(executor, scan, url)
    with get_db() as db:
        for e in emails:
            db.execute("INSERT OR IGNORE INTO outreach (email, source_url, found_at) VALUES (?,?,?)",
                       (e, url, now_iso()))
    return RedirectResponse("/", status_code=303)


@app.get("/api/visibility")
async def visibility_series():
    with get_db() as db:
        rows = db.execute("SELECT day, score FROM visibility ORDER BY day DESC LIMIT 60").fetchall()
    rows = list(reversed(rows))
    return JSONResponse({"labels": [r["day"][5:] for r in rows], "scores": [r["score"] for r in rows]})


# ---------- Sanitering af artikel-HTML (XSS) ----------
# AI-genereret indhold (og SERP-snippets i prompten) er ikke til at stole paa. Foer det vises
# med |safe i dashboardet, fjernes alt undtagen en lille allow-list af formateringstags.
ALLOWED_ARTICLE_TAGS = {
    "p", "br", "h2", "h3", "h4", "ul", "ol", "li", "strong", "b", "em", "i",
    "a", "blockquote", "table", "thead", "tbody", "tr", "th", "td",
}
DANGEROUS_ARTICLE_TAGS = ("script", "style", "iframe", "object", "embed", "form", "svg", "math", "link", "meta")


def sanitize_article_html(html: str) -> str:
    """Allow-list-sanitering af artikel-HTML (samme ide som DOMPurify, blot server-side)."""
    soup = BeautifulSoup(html or "", "html.parser")
    for tag in soup(list(DANGEROUS_ARTICLE_TAGS)):
        tag.decompose()
    for tag in soup.find_all(True):
        if tag.name not in ALLOWED_ARTICLE_TAGS:
            tag.unwrap()          # ukendt tag: behold teksten, drop tagget
            continue
        # Laes href FOER alle attributter fjernes, saa gode links overlever.
        href = (tag.get("href") or "").strip()
        tag.attrs = {}            # drop onclick/style/javascript: m.m.
        if tag.name == "a" and href and re.match(r"^(https?://|/)", href, re.I):
            tag["href"] = href
            tag["rel"] = "noopener noreferrer"
            tag["target"] = "_blank"
    return str(soup)


# ---------- Dashboard ----------
@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    with get_db() as db:
        domains = db.execute("SELECT * FROM domains ORDER BY id DESC").fetchall()
        competitors = db.execute("SELECT * FROM competitors ORDER BY id DESC LIMIT 20").fetchall()
        articles = []
        for art_row in db.execute("SELECT * FROM articles ORDER BY id DESC LIMIT 10").fetchall():
            art = dict(art_row)
            art["content"] = sanitize_article_html(art.get("content") or "")
            articles.append(art)
        linkchecks = db.execute("SELECT * FROM linkcheck ORDER BY id DESC LIMIT 10").fetchall()
        socialqueue = db.execute("SELECT * FROM socialqueue ORDER BY id DESC LIMIT 100").fetchall()  # full list: /social/export.csv
        notes = db.execute("SELECT * FROM notes ORDER BY id DESC LIMIT 10").fetchall()
        keywords = db.execute("SELECT * FROM keywords ORDER BY position IS NULL, position").fetchall()
        alarms = db.execute("SELECT * FROM alarms WHERE resolved=0 ORDER BY id DESC LIMIT 20").fetchall()
        ideas = db.execute("SELECT * FROM keyword_ideas ORDER BY id DESC LIMIT 30").fetchall()
        gaps = db.execute("SELECT * FROM content_gap ORDER BY id DESC LIMIT 5").fetchall()
        outreach_rows = db.execute("SELECT DISTINCT email FROM outreach ORDER BY id DESC LIMIT 30").fetchall()
        monitors = db.execute("SELECT * FROM monitors ORDER BY id DESC").fetchall()
        ai_vis = db.execute("SELECT * FROM ai_visibility ORDER BY id DESC LIMIT 5").fetchall()
        links_sug = db.execute("SELECT * FROM internal_links ORDER BY id").fetchall()
        health_hist = db.execute("SELECT COUNT(*) AS n FROM health_history").fetchone()["n"]
        seo_pages = db.execute(
            "SELECT * FROM seopages WHERE run_id=(SELECT id FROM crawl_runs ORDER BY id DESC LIMIT 1) "
            "ORDER BY score ASC LIMIT 100"
        ).fetchall()
        crawl = db.execute("SELECT * FROM crawl_runs ORDER BY id DESC LIMIT 1").fetchone()
        difficulties = db.execute("SELECT * FROM keyword_difficulty ORDER BY created_at DESC LIMIT 20").fetchall()
        # Read here, while the connection is open (get_db closes it when the block ends).
        backlink_rows = db.execute("SELECT * FROM backlink_prospects ORDER BY id DESC LIMIT 30").fetchall()
        strategy_row = db.execute("SELECT value FROM settings WHERE key='active_strategy'").fetchone()
        check_row = db.execute("SELECT value FROM settings WHERE key='strategy_check'").fetchone()
        sgap_row = db.execute("SELECT value FROM settings WHERE key='sgap_snapshot'").fetchone()
        users = db.execute("SELECT id, username, created_at, last_login_ip, last_login_at FROM users ORDER BY id").fetchall()
        login_rows = db.execute("SELECT username, ip, ok, created_at FROM login_attempts ORDER BY id DESC LIMIT 8").fetchall()
        update_row = db.execute("SELECT value FROM settings WHERE key='github_update'").fetchone()
        alert_outbox = {r["state"]: r["n"] for r in
                        db.execute("SELECT state, COUNT(*) AS n FROM alert_outbox GROUP BY state").fetchall()}
        alert_problems = db.execute(
            "SELECT channel, subject, attempts, last_error FROM alert_outbox "
            "WHERE last_error IS NOT NULL AND state IN ('pending','failed') ORDER BY id DESC LIMIT 5"
        ).fetchall()
    active_key = (strategy_row["value"] if strategy_row else None) or DEFAULT_STRATEGY
    if active_key not in STRATEGIES:
        active_key = DEFAULT_STRATEGY
    try:
        update_state = jsonlib.loads(update_row["value"]) if update_row and update_row["value"] else None
    except Exception:
        update_state = None
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "domains": domains,
        "competitors": competitors,
        "articles": articles,
        "linkchecks": linkchecks,
        "socialqueue": socialqueue,
        "notes": notes,
        "keywords": keywords,
        "alarms": alarms,
        "ai_enabled": bool(AIMLAPI_KEY),
        "wp_enabled": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "serpapi_enabled": bool(SERPAPI_KEY),
        "telegram_enabled": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
        "alert_channels": alert_channels(),
        "alert_settings": {"min_severity": ALERT_MIN_SEVERITY, "quiet_hours": ALERT_QUIET_HOURS,
                           "dedupe_minutes": ALERT_DEDUPE_MINUTES},
        "alert_outbox": alert_outbox,
        "alert_problems": alert_problems,
        "current_user": getattr(request.state, "user", None),
        "update_state": update_state,
        "update_token": bool(GITHUB_TOKEN),
        "update_repo": GITHUB_REPO,
        "task_estimates": TASK_ESTIMATES,
        "current_commit": deployed_commit(),
        "users": users,
        "login_rows": login_rows,
        "app_version": APP_VERSION,
        "newest": NEWEST,
        "client_ip": client_ip(request),
        "seo_pages": seo_pages,
        "monitors": monitors,
        "ideas": ideas,
        "gaps": gaps,
        "outreach_rows": outreach_rows,
        "backlink_rows": backlink_rows,
        "ai_vis": ai_vis,
        "links_sug": links_sug,
        "health_hist_n": health_hist,
        "crawl": crawl,
        "track_domain": TRACK_DOMAIN,
        "difficulties": difficulties,
        "sgap": jsonlib.loads(sgap_row["value"]) if sgap_row and sgap_row["value"] else {},
        "sgap_ready": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "modules": modules_state(),
        "strategies": STRATEGIES,
        "active_strategy": active_key,
        "strategy_autopilot": STRATEGIES[active_key]["autopilot"],
        "strategy_autopilot_label": STRATEGIES[active_key]["label"],
        "insecure": getattr(request.state, "insecure", False),
        "strategy_check": jsonlib.loads(check_row["value"]) if check_row and check_row["value"] else None,
    })


@app.post("/settings/module")
async def settings_module(request: Request):
    form = await request.form()
    name = str(form.get("name", ""))
    state = "on" if str(form.get("state", "on")) == "on" else "off"
    if name in MODULES:
        set_module(name, state)
    return RedirectResponse("/", status_code=303)


def strategy_check_sync(key: str):
    """Pre-flight-tjek: er alt udfyldt og koerende for den valgte strategi? Gemmer checkliste i settings."""
    st = STRATEGIES.get(key) or STRATEGIES[DEFAULT_STRATEGY]
    checks = []
    is_backlink = st.get("autopilot") == "backlink"

    def add(ok, text, kritisk=False):
        checks.append({"ok": bool(ok), "text": text, "kritisk": kritisk})

    # AI-noegle (artikel-strategier: kritisk; backlink: til AI-drafts)
    if is_backlink:
        add(bool(SERPAPI_KEY), "SERPAPI_KEY: " + ("OK" if SERPAPI_KEY else "MANGLER (prospecting kan ikke kore)"), kritisk=True)
        add(bool(AIMLAPI_KEY), "AIMLAPI_KEY (AI-outreach-drafts): " + ("OK" if AIMLAPI_KEY else "mangler - drafts skrives manuelt"))
    else:
        add(bool(AIMLAPI_KEY), "AIMLAPI_KEY (AI-artikler): " + ("OK" if AIMLAPI_KEY else "MANGLER (generering falder tilbage til skabelon)"), kritisk=True)
        add(bool(SERPAPI_KEY), "SERPAPI_KEY (konkurrent-analyse): " + ("OK" if SERPAPI_KEY else "mangler - prompten kobrer uden SERP-kontekst"))

    # WordPress-push
    wp_ok = bool(WP_URL and WP_USER and WP_APP_PASSWORD)
    add(wp_ok, "WordPress-push (kladde): " + ("OK" if wp_ok else "mangler - artikler gemmes kun i CC"))

    # Moduler
    add(module_on("ai"), "Modul 'ai' er aktivt")
    add(module_on("growth"), "Modul 'growth' er aktivt (autopilot-cron)")
    if wp_ok:
        add(module_on("wp_push"), "Modul 'wp_push' er aktivt")

    # Autopilot-cron registreret?
    try:
        add(scheduler.get_job("growth_autopilot") is not None, "Autopilot-cron (05:15) er planlagt")
    except Exception:
        add(False, "Autopilot-cron kunne ikke verificeres")

    # DB-skrivetest
    try:
        with get_db() as db:
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_strategy_check', ?)", (now_iso(),))
        add(True, "Database: skrivetest OK")
    except Exception as e:
        add(False, "Database: skrivetest FEJLEDE - " + str(e)[:80], kritisk=True)

    # Alarm ved kritiske mangler
    for c in checks:
        if c["kritisk"] and not c["ok"]:
            with get_db() as db:
                add_alarm(db, "strategi", f"Strategi '{st['label']}': {c['text']}", "kritisk")

    try:
        with get_db() as db:
            db.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES ('strategy_check', ?)",
                (jsonlib.dumps({"key": key, "checks": checks, "checked_at": now_iso()}),),
            )
    except Exception:
        pass
    return checks


@app.post("/settings/strategy")
async def settings_strategy(request: Request):
    form = await request.form()
    key = str(form.get("strategy", ""))
    if key in STRATEGIES:
        with get_db() as db:
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('active_strategy', ?)", (key,))
        try:
            await asyncio.get_running_loop().run_in_executor(executor, strategy_check_sync, key)
        except Exception:
            pass
    return RedirectResponse("/", status_code=303)


@app.post("/notes/add")
async def add_note(content: str = Form(...)):
    if content.strip():
        with get_db() as db:
            db.execute("INSERT INTO notes (content, created_at) VALUES (?,?)", (content.strip(), now_iso()))
    return RedirectResponse("/", status_code=303)


@app.post("/notes/delete")
async def delete_note(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM notes WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


@app.get("/health")
async def health():
    """Selvtest (v8-plan): kan databasen skrive, og er der plads paa disken? 503 hvis kritisk."""
    db_write = True
    try:
        with get_db() as db:
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('health_probe', ?)", (now_iso(),))
    except Exception:
        db_write = False
    try:
        du = shutil.disk_usage(os.path.dirname(DB_PATH))
        disk_used_pct = round(du.used / du.total * 100, 1)
    except Exception:
        disk_used_pct = None
    status = "ok"
    if disk_used_pct is not None and disk_used_pct >= 80:
        status = "advarsel"
    if not db_write or (disk_used_pct is not None and disk_used_pct >= 90):
        status = "kritisk"
    body = {
        "status": status,
        "db_write": db_write,
        "disk_used_pct": disk_used_pct,
        "budget": {s: {"used": u, "limit": l} for s, (u, l) in budget_usage().items()},
        "version": APP_VERSION,
        "ai": bool(AIMLAPI_KEY),
        "wordpress": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "serpapi": bool(SERPAPI_KEY),
        "telegram": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
        "auth": "users",
        "users": user_count(),
        "newest": [f"{v}: {t}" for v, t in NEWEST[:3]],
        "started_at": last_run_report().get("last_start", ""),
    }
    return JSONResponse(body, status_code=503 if status == "kritisk" else 200)


# ---------- Scheduler ----------
async def job_check_domains():
    if not module_on("domains"):
        return
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, check_all_domains_sync)


async def job_drain_alerts():
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, drain_alert_outbox)


async def job_check_keywords():
    if not module_on("keywords"):
        return
    if not SERPAPI_KEY:
        return
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, check_all_keywords_sync)


@asynccontextmanager
async def lifespan(app_: FastAPI):
    try:
        log_startup(os.environ.get("CC_HOST", ""), os.environ.get("CC_PORT") and int(os.environ.get("CC_PORT")))
    except Exception:
        pass
    try:
        scheduler.add_job(job_check_domains, IntervalTrigger(hours=6), id="domain_checks", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_check_keywords, CronTrigger(hour=6, minute=0), id="keyword_checks", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_growth_autopilot, CronTrigger(hour=5, minute=15), id="growth_autopilot", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(cleanup_old_data, CronTrigger(hour=4, minute=30), id="cleanup", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_backup_db, CronTrigger(hour=4, minute=40), id="db_backup", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_update_check, CronTrigger(hour=5, minute=0), id="update_check", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_sgap_sync, IntervalTrigger(minutes=30), id="sgap_sync", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_drain_alerts, IntervalTrigger(minutes=1), id="alert_outbox", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.start()
        try:
            executor.submit(startup_selftest_sync)  # v7.9: selvtest ved hver opstart (efter self-update/install)
        except Exception:
            pass
    except Exception as e:
        print("[cc] scheduler kunne ikke starte (app koerer videre uden cron):", repr(e), flush=True)
    yield
    scheduler.shutdown()


app.add_middleware(GZipMiddleware, minimum_size=500)
app.router.lifespan_context = lifespan
