#!/bin/bash
set -e
PROJECT_DIR="$HOME/command-center"

echo "⚡ Command Center v7.11 - installerer i $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR/app/templates" "$PROJECT_DIR/app/data" "$PROJECT_DIR/app/static" "$PROJECT_DIR/deploy" "$PROJECT_DIR/scripts"
echo "📄 requirements.txt..."
cat << 'EOF_REQ' > "$PROJECT_DIR/requirements.txt"
fastapi==0.115.6
uvicorn[standard]==0.34.0
requests==2.32.3
beautifulsoup4==4.12.3
Jinja2==3.1.5
APScheduler==3.10.4
python-dotenv==1.0.1
python-multipart==0.0.20
EOF_REQ

echo "📄 .env.example..."
cat << 'EOF_ENVDOT' > "$PROJECT_DIR/.env.example"
# Command Center v7.11 - kopier til .env og udfyld
# Login: der er ingen token. Foerste besoeg i browseren opretter din bruger (/setup),
# derefter logger du ind med brugernavn + adgangskode. Brugere styres under fanen "Brugere".
# Maskin-noegle til /api/* (bridge-push fra Juno). Valgfri - lad den vaere tom hvis ubrugt.
JUNO_TOKEN=
# Hvor run.sh lytter. 127.0.0.1 = kun denne maskine; 0.0.0.0 = ogsaa fra netvaerket (kraever TLS/proxy).
CC_HOST=127.0.0.1
CC_PORT=8000
# Adressen du aabner i browseren bag nginx (bruges kun til at printe den rigtige adresse).
# Ultra.cc: fx https://<bruger>.<server>.ultra.cc - tom = ingen nginx.
CC_PUBLIC_URL=
# Stoler paa X-Forwarded-* fra disse IP'er (nginx paa samme maskine = 127.0.0.1).
CC_FORWARDED_ALLOW_IPS=127.0.0.1
# Genstart automatisk efter en GitHub-opdatering (1 = ja, 0 = nej).
UPDATE_AUTO_RESTART=1
# Overstyr genstartskommandoen (fx din egen supervisor); tom = brug systemd-unit eller scripts/restart.sh.
UPDATE_RESTART_CMD=
# AI-artikler: din aimlapi-noegle
AIMLAPI_KEY=
AI_MODEL=google/gemini-3-8-flash
# WordPress-push + Steamgears Autopilot-bro (Application Password for en ADMINISTRATOR: WP Admin > Users > Profile)
WP_URL=https://steamgears.eu
WP_USER=
WP_APP_PASSWORD=
# Alarmer via Telegram-bot (valgfrit)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
# Keyword-positioner via SerpAPI
SERPAPI_KEY=
TRACK_DOMAIN=steamgears.eu
# API-budget pr. kalendermaaned (antal kald, 0 = intet loft). Stopper kald ved loftet + alarm ved 80 %/100 %
SERPAPI_MONTHLY_LIMIT=1000
AI_MONTHLY_LIMIT=3000
# Kvalitetsgate: autopilot-artikler under dette ordantal (eller 80 % af SERP-gennemsnittet) sendes ikke til WP
QUALITY_MIN_WORDS=400
# Tuninge
SSL_WARN_DAYS=30
LINKCHECK_LIMIT=25
# GitHub pull-bro + selv-opdatering (Juno committer bridge-filer, CC henter selv)
GITHUB_TOKEN=
GITHUB_REPO=humle93/command-center
BRIDGE_POLL_MINUTES=60
EOF_ENVDOT

echo "📄 app/main.py..."
cat << 'EOF_MAIN' > "$PROJECT_DIR/app/main.py"
from fastapi import FastAPI, Request, Form, Header
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, PlainTextResponse
from fastapi import Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi import HTTPException
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
import sys
import tarfile

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
    kommentar fra .env-skabelonen ikke ender som vaerdi (fx et JUNO_TOKEN bestaaende af tekst)."""
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
JUNO_TOKEN = os.environ.get("JUNO_TOKEN", "").strip()        # maskin-noegle til /api/* (valgfri)
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()     # GitHub-token: pull-bro + selv-opdatering
GITHUB_REPO = os.environ.get("GITHUB_REPO", "humle93/command-center").strip()
BRIDGE_POLL_MINUTES = int(os.environ.get("BRIDGE_POLL_MINUTES", "60"))  # hvor ofte CC henter bridge-filer
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

APP_VERSION = "7.11.0"
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
        CREATE TABLE IF NOT EXISTS gsc_daily (
            day TEXT PRIMARY KEY,
            clicks INTEGER,
            impressions INTEGER,
            ctr REAL,
            avg_position REAL
        );
        CREATE TABLE IF NOT EXISTS gsc_queries (
            day TEXT NOT NULL,
            query TEXT NOT NULL,
            clicks INTEGER,
            impressions INTEGER,
            position REAL,
            PRIMARY KEY (day, query)
        );
        CREATE TABLE IF NOT EXISTS drift (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            checked_at TEXT,
            orders INTEGER,
            revenue REAL,
            woo_status TEXT,
            checkout_status TEXT,
            notes TEXT
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
            expires_at TEXT
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
        cols = {}
        for table, want in {
            "articles": ["meta_title", "meta_desc"],
            "seopages": ["content_hash", "redirects"],
            "crawl_runs": ["sitemap_broken", "sitemap_missing"],
            "monitors": ["last_value"],
        }.items():
            existing = [r[1] for r in db.execute(f"PRAGMA table_info({table})").fetchall()]
            for c in want:
                if c not in existing:
                    db.execute(f"ALTER TABLE {table} ADD COLUMN {c} TEXT")


_safe(migrate_db)


def create_indexes():
    with get_db() as db:
        for stmt in [
            "CREATE INDEX IF NOT EXISTS idx_seopages_run ON seopages(run_id)",
            "CREATE INDEX IF NOT EXISTS idx_gsc_daily_day ON gsc_daily(day)",
            "CREATE INDEX IF NOT EXISTS idx_gsc_q ON gsc_queries(query)",
            "CREATE INDEX IF NOT EXISTS idx_alarms_open ON alarms(resolved, id)",
            "CREATE INDEX IF NOT EXISTS idx_hist_domain ON check_history(domain_id, id)",
            "CREATE INDEX IF NOT EXISTS idx_health_time ON health_history(checked_at)",
            "CREATE INDEX IF NOT EXISTS idx_crawl_time ON crawl_runs(started_at)",
            "CREATE INDEX IF NOT EXISTS kw_ideas_kw ON keyword_ideas(keyword)",
        ]:
            db.execute(stmt)
        db.execute("ANALYZE")


_safe(create_indexes)


MODULES = ["domains", "keywords", "ai", "monitors", "social", "links", "bridge", "spy", "wp_push", "telegram", "growth", "autopilot"]


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


# ---------- Auth: brugere, sessioner og Juno-token ----------
# Dashboardet har rigtige brugere: brugernavn + adgangskode (PBKDF2-SHA256 med salt pr. bruger).
# Foerste besoeg opretter den foerste bruger via /setup - der er ingen delt token i .env.
# JUNO_TOKEN findes stadig som maskin-noegle, men giver KUN adgang til /api/* (bridge-push fra Juno).
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


def start_session(user_id: int) -> str:
    sid = secrets.token_urlsafe(32)
    expires = (datetime.now() + timedelta(seconds=SESSION_MAX_AGE)).isoformat(timespec="seconds")
    with get_db() as db:
        db.execute("DELETE FROM sessions WHERE expires_at < ?", (now_iso(),))
        db.execute("INSERT INTO sessions (id, user_id, created_at, last_seen, expires_at) VALUES (?,?,?,?,?)",
                   (_session_key(sid), user_id, now_iso(), now_iso(), expires))
    return sid


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
    """Er kaldet lavet af en logget-ind bruger? (Juno-token haandteres af middlewaren.)"""
    return bool(getattr(request.state, "user", None))


def is_juno(request: Request) -> bool:
    """Juno-adgang: separat maskin-noegle, gyldig KUN for /api/*-endpoints."""
    supplied = request.headers.get("x-cc-token") or ""
    return bool(JUNO_TOKEN) and secrets.compare_digest(supplied, JUNO_TOKEN)


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
        if is_juno(request):
            juno_forbidden = ("/api/bridge", "/api/duplicates", "/api/visibility", "/api/health-history")
            if request.method != "GET" and any(path.startswith(fp) for fp in juno_forbidden) \
                    and path not in ("/api/bridge/gsc", "/api/bridge/drift"):
                return JSONResponse({"error": "juno-token: kun GET eller bridge-push"}, status_code=403)
            return await call_next(request)
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return RedirectResponse("/setup" if user_count() == 0 else "/login", status_code=303)


@app.get("/setup", response_class=HTMLResponse)
async def setup_page(request: Request):
    if user_count() > 0:
        return RedirectResponse("/login", status_code=303)
    return templates.TemplateResponse("login.html", {"request": request, "mode": "setup", "error": "", "username": ""})


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
        return templates.TemplateResponse("login.html", {"request": request, "mode": "setup",
                                                         "username": username, "error": err}, status_code=400)
    with get_db() as db:
        add_alarm(db, "brugere", f"Foerste bruger '{username}' oprettet", "info")
    return session_redirect(request, start_session(user_id))


@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if user_count() == 0:
        return RedirectResponse("/setup", status_code=303)
    return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "error": "", "username": ""})


@app.post("/login")
async def login(request: Request):
    ip = request.client.host if request.client else "ukendt"
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
        return session_redirect(request, start_session(user["id"]))
    fails += 1
    _LOGIN_FAILS[ip] = (0, now + _LOGIN_LOCK_SECONDS) if fails >= _LOGIN_MAX_FAILS else (fails, locked_until)
    if len(_LOGIN_FAILS) > 2000:  # undgaa at listen vokser ubegraenset
        _LOGIN_FAILS.clear()
    return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "username": username,
                                                     "error": "Forkert brugernavn eller adgangskode"}, status_code=401)


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
    db.execute(
        "INSERT INTO alarms (type, message, severity, created_at) VALUES (?, ?, ?, ?)",
        (type_, message, severity, now_iso()),
    )
    notify_telegram(f"[{severity.upper()}] {type_}: {message}")


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
CRAWL_STATE = {"running": False, "done": 0, "total": 0, "start": "", "error": None, "avg": None}


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
        CRAWL_STATE.update({"running": True, "done": 0, "total": max_pages, "start": start_url, "error": None, "avg": None})
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
        sitemap_missing = 0
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
        CRAWL_STATE.update({"running": False, "avg": avg})
        return {"ok": True, "pages": pages_saved, "avg_score": avg, "robots_ok": robots_ok,
                "sitemap_ok": sitemap_ok, "sitemap_urls": sitemap_count}
    except Exception as e:
        CRAWL_STATE.update({"running": False, "error": str(e)[:200]})
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
    return JSONResponse(CRAWL_STATE)


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
            raise RuntimeError("Ingen resultater (DuckDuckGo blokerede muligvis - proev igen eller brug Juno/SerpAPI)")
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
            import urllib.parse as _up
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
    result = await loop.run_in_executor(executor, autopilot_sync)
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
@app.post("/alarms/resolve")
async def resolve_alarm(id: int = Form(...)):
    with get_db() as db:
        db.execute("UPDATE alarms SET resolved=1 WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


# ---------- Juno-broer (ekstern push af data) ----------
def ingest_gsc_data(db, data):
    days = data.get("daily", [])
    queries = data.get("queries", [])
    for d in days:
        db.execute(
            "INSERT INTO gsc_daily (day, clicks, impressions, ctr, avg_position) VALUES (?,?,?,?,?) "
            "ON CONFLICT(day) DO UPDATE SET clicks=excluded.clicks, impressions=excluded.impressions, "
            "ctr=excluded.ctr, avg_position=excluded.avg_position",
            (d.get("day"), d.get("clicks", 0), d.get("impressions", 0), d.get("ctr", 0), d.get("position", 0)),
        )
    for q in queries:
        db.execute(
            "INSERT INTO gsc_queries (day, query, clicks, impressions, position) VALUES (?,?,?,?,?) "
            "ON CONFLICT(day, query) DO UPDATE SET clicks=excluded.clicks, "
            "impressions=excluded.impressions, position=excluded.position",
            (data.get("date", date.today().isoformat()), q.get("query", ""), q.get("clicks", 0),
             q.get("impressions", 0), q.get("position", 0)),
        )
    return len(days), len(queries)


@app.post("/api/bridge/gsc")
async def bridge_gsc(request: Request):
    data = await request.json()
    if not isinstance(data.get("daily", []), list):
        raise HTTPException(400, "daily skal vaere en liste")
    with get_db() as db:
        days, queries = ingest_gsc_data(db, data)
    return {"ok": True, "days": days, "queries": queries}


def ingest_drift_data(db, data):
    db.execute(
        "INSERT INTO drift (checked_at, orders, revenue, woo_status, checkout_status, notes) VALUES (?,?,?,?,?,?)",
        (now_iso(), data.get("orders"), data.get("revenue"), data.get("woo_status", "ok"),
         data.get("checkout_status", "ok"), data.get("notes", "")),
    )
    if data.get("woo_status") not in (None, "ok", ""):
        add_alarm(db, "drift", f"Woo-status: {data.get('woo_status')}", "kritisk")


@app.post("/api/bridge/drift")
async def bridge_drift(request: Request):
    data = await request.json()
    with get_db() as db:
        ingest_drift_data(db, data)
    return {"ok": True}


# ---------- Pull-bro: CC henter selv fra GitHub (ingen tunnel noedvendig) ----------
def pull_bridge_sync():
    if not GITHUB_TOKEN or not module_on("bridge"):
        return
    try:
        headers = {"Authorization": "Bearer " + GITHUB_TOKEN, "Accept": "application/vnd.github+json"}
        r = HTTP.get(f"https://api.github.com/repos/{GITHUB_REPO}/contents/bridge/pending", headers=headers, timeout=15)
        if r.status_code != 200:
            return
        for item in r.json():
            name = item.get("name", "")
            if not name.endswith(".json"):
                continue
            rr = HTTP.get(item.get("url"), headers={"Authorization": "Bearer " + GITHUB_TOKEN, "Accept": "application/vnd.github.raw"}, timeout=15)
            try:
                data = jsonlib.loads(rr.text)
            except Exception:
                continue
            with get_db() as db:
                if name.startswith("gsc-"):
                    ingest_gsc_data(db, data)
                elif name.startswith("drift-"):
                    ingest_drift_data(db, data)
            HTTP.delete(item.get("url"), headers={"Authorization": "Bearer " + GITHUB_TOKEN}, timeout=15)
    except Exception:
        pass


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
        gsc_days = db.execute("SELECT * FROM gsc_daily ORDER BY day DESC LIMIT 14").fetchall()
        gsc_queries = db.execute(
            "SELECT query, SUM(clicks) AS clicks, SUM(impressions) AS impressions, AVG(position) AS pos "
            "FROM gsc_queries GROUP BY query ORDER BY clicks DESC LIMIT 10"
        ).fetchall()
        drift_rows = db.execute("SELECT * FROM drift ORDER BY id DESC LIMIT 7").fetchall()
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
        users = db.execute("SELECT id, username, created_at FROM users ORDER BY id").fetchall()
        update_row = db.execute("SELECT value FROM settings WHERE key='github_update'").fetchone()
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
        "gsc_days": gsc_days,
        "gsc_queries": gsc_queries,
        "drift_rows": drift_rows,
        "ai_enabled": bool(AIMLAPI_KEY),
        "wp_enabled": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "serpapi_enabled": bool(SERPAPI_KEY),
        "telegram_enabled": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
        "current_user": getattr(request.state, "user", None),
        "update_state": update_state,
        "update_token": bool(GITHUB_TOKEN),
        "update_repo": GITHUB_REPO,
        "current_commit": deployed_commit(),
        "users": users,
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
    }
    return JSONResponse(body, status_code=503 if status == "kritisk" else 200)


# ---------- Scheduler ----------
async def job_check_domains():
    if not module_on("domains"):
        return
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(executor, check_all_domains_sync)


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
        scheduler.add_job(job_check_domains, IntervalTrigger(hours=6), id="domain_checks", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_check_keywords, CronTrigger(hour=6, minute=0), id="keyword_checks", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_growth_autopilot, CronTrigger(hour=5, minute=15), id="growth_autopilot", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(cleanup_old_data, CronTrigger(hour=4, minute=30), id="cleanup", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(pull_bridge_sync, IntervalTrigger(minutes=BRIDGE_POLL_MINUTES), id="pull_bridge", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_backup_db, CronTrigger(hour=4, minute=40), id="db_backup", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_update_check, CronTrigger(hour=5, minute=0), id="update_check", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_sgap_sync, IntervalTrigger(minutes=30), id="sgap_sync", replace_existing=True, max_instances=1, coalesce=True)
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
EOF_MAIN

echo "📄 app/templates/dashboard.html..."
cat << 'EOF_HTML' > "$PROJECT_DIR/app/templates/dashboard.html"
<!DOCTYPE html>
<html lang="da" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Command Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <link rel="preconnect" href="https://cdn.tailwindcss.com" crossorigin>
    <link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
    <meta name="theme-color" content="#09090b">
    <style>
      html { scroll-behavior: smooth; }
      body { -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
      ::-webkit-scrollbar { width: 9px; height: 9px; }
      ::-webkit-scrollbar-track { background: #09090b; }
      ::-webkit-scrollbar-thumb { background: #3f3f46; border-radius: 8px; }
      ::-webkit-scrollbar-thumb:hover { background: #52525b; }
      nav, header { backdrop-filter: blur(12px); }
      tbody tr { transition: background-color .12s ease; }
      tbody tr:hover { background: rgba(39,39,42,.45); }
      button, a, input { transition: all .15s ease; }
      input:focus-visible, button:focus-visible { outline: 2px solid #34d399; outline-offset: 1px; }
      .spinner { width: 16px; height: 16px; border: 2px solid #3f3f46; border-top-color: #34d399; border-radius: 50%; display: inline-block; animation: ccspin .7s linear infinite; vertical-align: -3px; }
      @keyframes ccspin { to { transform: rotate(360deg); } }
      .bg-zinc-900:hover { border-color: #3f3f46; }
      @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
      @media (max-width: 640px) {
        nav::-webkit-scrollbar { display: none; }
        th, td { padding-top: .45rem; padding-bottom: .45rem; }
      }
    </style>
</head>
{% if insecure %}<div class="bg-yellow-600 text-black text-xs text-center py-1.5 px-4 font-semibold">&Uacute;t&uacute;n HTTPS &mdash; token sendes ukrypteret. S&aelig;t nginx + TLS op foran CC (se Install-dokumentationen).</div>{% endif %}
<body class="bg-zinc-950 text-zinc-100 min-h-screen font-sans" x-data="{ tab: 'cockpit', seoResult: null, seoLoading: false, crawl: null, histChart: null, histOpen: false, dups: null, healthChart: null, diff: null, redir: null, rewrite: null }">
<header class="border-b border-zinc-800 bg-zinc-900/60 px-4 py-3">
    <div class="max-w-7xl mx-auto flex items-center justify-between">
        <div>
            <h1 class="font-bold text-sm">⚡ COMMAND CENTER <span class="text-emerald-400">v7.11 PRO</span></h1>
            <p class="text-xs text-zinc-500">WordPress, SEO, indhold & overvågning</p>
        </div>
        <div class="flex items-center gap-3">
            <form action="/update/apply" method="POST" onsubmit="return confirm('Hent og installér nyeste version fra GitHub? Der laves en DB-backup først, og appen skal genstartes bagefter.')"><button class="text-xs text-zinc-400 hover:text-emerald-400">⬆️ Opdatér</button></form>
            <a href="/health" class="text-xs text-emerald-400">Systemstatus</a>
            {% if current_user %}<span class="text-xs text-zinc-500">👤 {{ current_user.username }}</span>
            <a href="/logout" class="text-xs text-zinc-500 hover:text-rose-400">Log ud</a>{% endif %}
        </div>
    </div>
</header>
<nav class="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-900/70 px-4 py-2 shadow-lg shadow-black/20">
    <div class="max-w-7xl mx-auto flex gap-2 overflow-x-auto">
        <button @click="tab='cockpit'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='cockpit' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🧭 1. Cockpit</button>
        <button @click="tab='seo'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='seo' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🔍 2. SEO & Audit</button>
        <button @click="tab='keywords'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='keywords' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🎯 3. Keywords</button>
        <button @click="tab='articles'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='articles' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">✍️ 4. Indhold</button>
        <button @click="tab='links'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='links' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🔗 5. Links</button>
        <button @click="tab='spy'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='spy' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🕷️ 6. Spy</button>
        <button @click="tab='social'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='social' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📱 7. Social</button>
        <button @click="tab='monitors'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='monitors' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🩺 8. Monitors</button>
        <button @click="tab='ai'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='ai' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🤖 AI Tools</button>
        <button @click="tab='pro'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='pro' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">💼 Pro</button>
        <button @click="tab='moduler'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='moduler' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">⚙️ Moduler</button>
        <button @click="tab='brugere'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='brugere' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">👤 Brugere</button>
        
        <button @click="tab='alarms'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='alarms' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🚨 Alarmer{% if alarms %} ({{ alarms|length }}){% endif %}</button>
        <button @click="tab='notes'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='notes' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📝 Noter</button>
    </div>
</nav>
<main class="max-w-7xl mx-auto p-4 space-y-4">

    {% if not ai_enabled or not wp_enabled %}
    <div class="bg-amber-500/10 border border-amber-500/30 rounded-2xl p-3 text-xs text-amber-300">
        Setup: AI {{ '✅' if ai_enabled else '❌ (AIMLAPI_KEY)' }} · WordPress {{ '✅' if wp_enabled else '❌ (WP_URL/WP_USER/WP_APP_PASSWORD)' }} · SerpAPI {{ '✅' if serpapi_enabled else '❌ (SERPAPI_KEY)' }} · Telegram {{ '✅' if telegram_enabled else '— (valgfrit)' }} — se .env.example
    </div>
    {% endif %}

    <!-- COCKPIT -->
    <section x-show="tab === 'cockpit'" class="space-y-4">
        <div class="bg-emerald-500/5 border border-emerald-500/20 rounded-2xl p-4">
            <h2 class="text-xs uppercase tracking-wider text-emerald-300 mb-2">🧭 Sådan bruger du Command Center (workflow)</h2>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-2 text-[11px]">
                <button @click="tab='seo'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">2. SEO & Audit</b><br><span class="text-zinc-500">Kør audit + crawl</span></button>
                <button @click="tab='keywords'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">3. Keywords</b><br><span class="text-zinc-500">Positioner + difficulty</span></button>
                <button @click="tab='articles'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">4. Indhold</b><br><span class="text-zinc-500">AI-artikler + autopilot</span></button>
                <button @click="tab='links'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">5. Links</b><br><span class="text-zinc-500">Interne + backlinks</span></button>
            </div>
            <p class="text-[10px] text-zinc-600 mt-2">Trin 1 (Cockpit) er denne side: overvågning + alarmer. Trin 6-8 (Spy/Social/Monitors) er løbende vækst. AI Tools/Pro/Moduler er værktøj.</p>
        </div>
        {% if alarms %}
        <div class="bg-rose-500/10 border border-rose-500/30 rounded-2xl p-4">
            <div class="flex items-center justify-between mb-2">
                <h2 class="text-xs uppercase tracking-wider text-rose-300">🚨 Åbne alarmer ({{ alarms|length }})</h2>
                <button @click="tab='alarms'" class="text-xs text-rose-300 hover:underline">Se alle</button>
            </div>
            {% for alarm in alarms[:3] %}<p class="text-xs text-zinc-300">• [{{ alarm.severity }}] {{ alarm.type }}: {{ alarm.message }}</p>{% endfor %}
        </div>
        {% endif %}

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Opdatering fra GitHub <span class="text-zinc-600 normal-case">({{ update_repo }})</span></h2>
                <div class="flex gap-2">
                    <form action="/update/check" method="POST"><button class="text-xs bg-zinc-800 text-zinc-300 border border-zinc-700 px-3 py-1.5 rounded-lg">🔄 Tjek for nye commits</button></form>
                    <form action="/update/apply" method="POST" class="flex items-center gap-2" onsubmit="return confirm('Hent og installér nyeste version fra GitHub? Der laves en DB-backup først, appen genstarter bagefter.')">
                        <label class="flex items-center gap-1 text-[11px] text-zinc-400" title="Genstarter appen når filerne er skrevet (systemd-unit eller scripts/restart.sh)"><input type="checkbox" name="restart" value="1" checked> genstart</label>
                        <button class="text-xs bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-3 py-1.5 rounded-lg">⬆️ Opdater</button>
                    </form>
                </div>
            </div>
            <p class="text-xs text-zinc-500">Installeret: <span class="text-zinc-300">{{ (current_commit or 'ukendt')[:7] }}</span>{% if update_state and update_state.latest %} · Nyeste på main: <span class="text-zinc-300">{{ update_state.latest[:7] }}</span>{% endif %}</p>
            {% if not update_token %}
            <p class="text-xs text-amber-400 mt-2">GITHUB_TOKEN mangler i .env — opdatering kræver adgang til det private repo.</p>
            {% elif update_state %}
                {% if update_state.error %}<p class="text-xs text-rose-400 mt-2">{{ update_state.error }}</p>
                {% elif update_state.behind %}<p class="text-xs text-amber-300 mt-2">Ny version tilgængelig{% if update_state.date %} ({{ update_state.date[:16] }}){% endif %}: {{ update_state.message }}</p>
                {% else %}<p class="text-xs text-emerald-400 mt-2">Du kører nyeste version.</p>{% endif %}
                {% if update_state.files %}<p class="text-xs text-zinc-500 mt-1">Sidste opdatering skrev {{ update_state.files|length }} filer{% if update_state.requirements_changed %} (requirements geninstalleret){% endif %}.</p>{% endif %}
                {% if update_state.restart %}{% if update_state.restart.scheduled %}<p class="text-xs text-sky-300 mt-1">Genstarter nu ({{ update_state.restart.mode }}) — genindlæs siden om et øjeblik.</p>{% else %}<p class="text-xs text-amber-300 mt-1">Ikke genstartet: {{ update_state.restart.reason }}</p>{% endif %}{% endif %}
            {% else %}
            <p class="text-xs text-zinc-500 mt-2">Tryk "Tjek for nye commits" for at sammenligne med GitHub (tjekker også automatisk kl. 05:00).</p>
            {% endif %}
        </div>

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Tilføj domæne</h2>
            <form action="/domains/add" method="POST" class="flex gap-2">
                <input type="text" name="url" placeholder="ditsite.dk" required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Tilføj</button>
            </form>
        </div>

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Overvågede domæner <span class="text-zinc-600 normal-case">(tjekker automatisk hver 6. time)</span></h2>
                <form action="/domains/check" method="POST"><button class="text-xs text-emerald-400">🔄 Kør tjek nu</button></form>
            </div>
            <div class="space-y-2">
                {% for domain in domains %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 flex justify-between items-center text-xs">
                    <div>
                        <div class="font-medium">{{ domain.url }}</div>
                        <div class="text-zinc-500">{{ domain.status }} • {{ domain.response_time }} • SSL: {{ domain.ssl_days }}
                            {% if domain.last_error %}• <span class="text-rose-400">{{ domain.last_error }}</span>{% endif %}
                        </div>
                    </div>
                    <div class="flex items-center gap-3">
                        <button @click="tab='seo'; showHistory({{ domain.id }}, $el.dataset.url)" data-url="{{ domain.url }}" class="text-emerald-400 hover:underline">📈</button>
                        <form action="/domains/delete" method="POST">
                            <input type="hidden" name="id" value="{{ domain.id }}">
                            <button class="text-zinc-500 hover:text-rose-400">✕</button>
                        </form>
                    </div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen domæner tilføjet endnu.</p>
                {% endfor %}
            </div>
        </div>

        {% if drift_rows %}
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Daglig drift (pushet fra Juno)</h2>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                {% for d in drift_rows[:3] %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs">
                    <div class="text-zinc-500">{{ d.checked_at[:16] }}</div>
                    <div class="mt-1">🛒 Ordrer: <span class="font-bold">{{ d.orders }}</span> · {{ 'DKK %.2f'|format(d.revenue or 0) }}</div>
                    <div>Woo: <span class="{{ 'text-emerald-400' if d.woo_status == 'ok' else 'text-rose-400' }}">{{ d.woo_status }}</span> · Checkout: <span class="{{ 'text-emerald-400' if d.checkout_status == 'ok' else 'text-rose-400' }}">{{ d.checkout_status }}</span></div>
                    {% if d.notes %}<div class="text-zinc-500 mt-1">{{ d.notes }}</div>{% endif %}
                </div>
                {% endfor %}
            </div>
        </div>
        {% endif %}
    </section>

    <!-- SEO SCANNER -->
    <section x-show="tab === 'seo'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Deep audit af enkelt side (RankMath-stil)</h2>
            <form @submit.prevent="
                seoLoading = true; seoResult = null;
                fetch('/seo/audit', { method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                    body: 'url=' + encodeURIComponent($el.querySelector('input[name=url]').value) + '&keyword=' + encodeURIComponent($el.querySelector('input[name=keyword]').value || '') + '&level=' + encodeURIComponent($el.querySelector('select[name=level]').value) + '&psi=' + ($el.querySelector('input[name=psi]')?.checked ? '1' : '0') })
                .then(r => r.json()).then(data => { seoResult = data; seoLoading = false; }).catch(() => { seoLoading = false; seoResult = { score: 0, items: [{ ok: false, text: 'Netværksfejl — prøv igen' }] }; })"
                class="flex flex-col md:flex-row gap-2">
                <input type="text" name="url" placeholder="https://steamgears.eu/guide..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <input type="text" name="keyword" placeholder="Focus keyword (valgfrit)" class="md:w-52 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <select name="level" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <option value="quick">⚡ Hurtig</option>
                    <option value="standard" selected>🔧 Standard</option>
                    <option value="deep">🚀 Dyb</option>
                </select>
                <label class="flex items-center gap-1 text-xs text-zinc-400 whitespace-nowrap"><input type="checkbox" name="psi"> Core Web Vitals</label>
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Analysér</button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="seoLoading" style="display: none;">
            <p class="text-xs text-zinc-400"><span class="spinner mr-2"></span>Analyserer side (20+ kontroller)…</p>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="seoResult" style="display: none;">
            <div class="flex items-center justify-between mb-4">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Resultat</h2>
                <div class="text-sm font-bold px-3 py-1 rounded-xl border" :class="seoResult?.score >= 80 ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : seoResult?.score >= 50 ? 'bg-amber-500/10 text-amber-400 border-amber-500/30' : 'bg-rose-500/10 text-rose-400 border-rose-500/30'" x-text="seoResult?.score + ' / 100' + (seoResult?.level === 'deep' ? ' · 🚀' : seoResult?.level === 'quick' ? ' · ⚡' : '')"></div>
            </div>
            <div class="mb-3">
                <button @click="loadRewrite()" class="text-xs bg-purple-500/10 text-purple-400 border border-purple-500/30 px-3 py-1.5 rounded-lg">✨ AI-rewrite titel/meta</button>
            </div>
            <div x-show="rewrite" style="display: none;" class="mb-3 text-xs bg-zinc-950 border border-purple-500/30 rounded-xl p-3 space-y-2">
                <div x-show="rewrite?.error" class="text-amber-400" x-text="rewrite?.error"></div>
                <div class="font-medium text-purple-400">Titel-forslag</div>
                <template x-for="t in (rewrite?.titles || [])"><div class="text-zinc-300 cursor-pointer hover:text-emerald-400" @click="navigator.clipboard.writeText(t)" x-text="t"></div></template>
                <div class="font-medium text-purple-400 pt-1">Meta-forslag</div>
                <template x-for="d in (rewrite?.descriptions || [])"><div class="text-zinc-300 cursor-pointer hover:text-emerald-400" @click="navigator.clipboard.writeText(d)" x-text="d"></div></template>
                <div class="text-zinc-500" x-text="rewrite?.note"></div>
            </div>
            <div x-show="seoResult?.psi" style="display: none;" class="mb-3 text-xs bg-zinc-950 border border-zinc-800 rounded-xl p-3">
                <span class="text-zinc-400">Core Web Vitals (mobile):</span>
                Performance <span class="text-emerald-400 font-bold" x-text="seoResult?.psi?.perf + '/100'"></span> ·
                LCP <span class="text-zinc-300" x-text="seoResult?.psi?.lcp"></span> ·
                CLS <span class="text-zinc-300" x-text="seoResult?.psi?.cls"></span>
            </div>
            <ul class="space-y-2 text-xs">
                <template x-for="item in (seoResult?.items || (seoResult?.quick_issues || []).map(t => ({ok: false, text: t})))">
                    <li class="flex items-center gap-2">
                        <span x-text="item.ok ? '✅' : '❌'"></span>
                        <span :class="item.ok ? 'text-zinc-300' : 'text-rose-400'" x-text="item.text"></span>
                    </li>
                </template>
            </ul>
        </div>

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Site-crawl (flerside-scan)</h2>
            <form action="/seo/crawl" method="POST" class="flex gap-2">
                <input type="text" name="url" placeholder="https://steamgears.eu" required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <select name="level" class="w-32 bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <option value="quick">⚡ Hurtig (10)</option>
                    <option value="standard" selected>🔧 Standard (30)</option>
                    <option value="deep">🚀 Dyb (60)</option>
                </select>
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Crawl</button>
            </form>
            <div class="flex gap-2 mt-2">
                <button @click="loadDiff()" class="text-xs bg-zinc-800 text-zinc-300 border border-zinc-700 px-3 py-1.5 rounded-lg">🔄 Sammenlign med forrige crawl</button>
                <a href="/api/sitemap.xml" class="text-xs bg-zinc-800 text-zinc-300 border border-zinc-700 px-3 py-1.5 rounded-lg">⬇️ Download sitemap.xml</a>
                <button @click="loadRedirects()" class="text-xs bg-zinc-800 text-zinc-300 border border-zinc-700 px-3 py-1.5 rounded-lg">🔀 Redirect-audit</button>
            </div>
            <div x-show="diff" style="display: none;" class="mt-3 text-xs bg-zinc-950 border border-zinc-800 rounded-xl p-3 space-y-1">
                <div x-show="diff?.error" class="text-amber-400" x-text="diff?.error"></div>
                <div><span class="text-emerald-400" x-text="'➕ Nye sider: ' + (diff?.new?.length || 0)"></span>
                     <span class="text-rose-400 ml-3" x-text="'➖ Fjernede: ' + (diff?.removed?.length || 0)"></span>
                     <span class="text-amber-400 ml-3" x-text="'✏️ Ændret indhold: ' + (diff?.changed_content?.length || 0)"></span>
                     <span class="text-rose-400 ml-3" x-text="'📉 Score-fald >10: ' + (diff?.score_drops?.length || 0)"></span></div>
                <template x-for="u in (diff?.score_drops || [])"><div class="text-zinc-500 truncate">📉 <span x-text="u.url"></span> <span x-text="u.old_score + ' → ' + u.score"></span></div></template>
                <template x-for="u in (diff?.removed || []).slice(0,5)"><div class="text-zinc-500 truncate">➖ <span x-text="u"></span></div></template>
            </div>
            <div x-show="redir" style="display: none;" class="mt-3 text-xs bg-zinc-950 border border-zinc-800 rounded-xl p-3 space-y-1">
                <div><span class="text-zinc-400" x-text="'Sider med redirects: ' + (redir?.with_redirects || 0)"></span>
                     <span class="text-amber-400 ml-3" x-text="'Kæder (2+ hop): ' + (redir?.chains?.length || 0)"></span>
                     <span class="text-rose-400 ml-3" x-text="'🌀 Loops: ' + (redir?.loops?.length || 0)"></span>
                     <span class="text-amber-400 ml-3" x-text="'🔓 http-links: ' + (redir?.insecure?.length || 0)"></span></div>
                <template x-for="c in (redir?.chains || []).slice(0,5)"><div class="text-zinc-500 truncate">🔗 <span x-text="c.chain"></span></div></template>
                <template x-for="l in (redir?.loops || [])"><div class="text-rose-400 truncate">🌀 <span x-text="l.chain"></span></div></template>
            </div>
            {% if crawl %}
            <div class="mt-3 text-xs text-zinc-400">
                Seneste crawl: {{ crawl.host }} · {{ crawl.pages }} sider · snitscore <span class="font-bold" :class="">{{ crawl.avg_score if crawl.avg_score is not none else '—' }}</span>/100 · robots.txt {{ '✅' if crawl.robots_ok else '❌' }} · sitemap {{ '✅ ' ~ crawl.sitemap_urls ~ ' URLs' if crawl.sitemap_ok else '❌' }}
            </div>
            {% endif %}
        </div>

        {% if seo_pages %}
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Side-rapport (dårligste først)</h2>
                <form action="/seo/crawl/delete" method="POST"><button class="text-xs text-zinc-500 hover:text-rose-400">Ryd</button></form>
            </div>
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="text-zinc-500 text-left">
                        <tr><th class="py-2 pr-2">Score</th><th class="py-2 pr-2">URL</th><th class="py-2 pr-2">Ord</th><th class="py-2 pr-2">Status</th><th class="py-2">Problemer</th></tr>
                    </thead>
                    <tbody>
                        {% for p in seo_pages %}
                        <tr class="border-t border-zinc-800">
                            <td class="py-2 pr-2"><span class="px-2 py-0.5 rounded {% if p.score >= 80 %}bg-emerald-500/10 text-emerald-400{% elif p.score >= 50 %}bg-amber-500/10 text-amber-400{% else %}bg-rose-500/10 text-rose-400{% endif %}">{{ p.score }}</span></td>
                            <td class="py-2 pr-2 max-w-xs truncate" title="{{ p.url }}">{{ p.url }}</td>
                            <td class="py-2 pr-2 text-zinc-400">{{ p.words }}</td>
                            <td class="py-2 pr-2 text-zinc-400">{{ p.http_status }}</td>
                            <td class="py-2 text-zinc-500">{{ p.issues }}</td>
                        </tr>
                        {% endfor %}
                    </tbody>
                </table>
            </div>
        </div>
        {% endif %}

        {% if health_hist_n %}
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Site Health over tid (crawl-snitscore)</h2>
            <canvas id="healthchart" height="70"></canvas>
        </div>
        {% endif %}

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Duplikater & redirects (Screaming Frog-stil)</h2>
                <button @click="fetch('/api/duplicates').then(r=>r.json()).then(d=>dups=d)" class="text-xs text-emerald-400">Analyser</button>
            </div>
            <div x-show="dups" style="display: none;" class="space-y-3 text-xs">
                <template x-if="dups">
                    <div class="space-y-3">
                        <div>
                            <p class="text-zinc-400 mb-1 font-medium">Dublettitler</p>
                            <template x-for="(d, i) in dups.titles" :key="i">
                                <p class="text-zinc-500">• <span class="text-zinc-300" x-text="d.n + 'x: '"></span><span x-text="d.urls"></span></p>
                            </template>
                            <p x-show="dups.titles.length === 0" class="text-emerald-400">✅ Ingen dublettitler</p>
                        </div>
                        <div>
                            <p class="text-zinc-400 mb-1 font-medium">Dublet-H1</p>
                            <template x-for="(d, i) in dups.h1" :key="'h'+i">
                                <p class="text-zinc-500">• <span class="text-zinc-300" x-text="d.n + 'x: '"></span><span x-text="d.urls"></span></p>
                            </template>
                            <p x-show="dups.h1.length === 0" class="text-emerald-400">✅ Ingen dublet-H1'er</p>
                        </div>
                        <div>
                            <p class="text-zinc-400 mb-1 font-medium">Næsten-identisk indhold</p>
                            <template x-for="(d, i) in dups.content" :key="'c'+i">
                                <p class="text-rose-400">• <span x-text="d.n + 'x: '"></span><span x-text="d.urls"></span></p>
                            </template>
                            <p x-show="dups.content.length === 0" class="text-emerald-400">✅ Intet duplikeret indhold</p>
                        </div>
                        <div>
                            <p class="text-zinc-400 mb-1 font-medium">Redirects</p>
                            <template x-for="(d, i) in dups.redirects" :key="'r'+i">
                                <p class="text-zinc-500">• <span x-text="d.url"></span> → <span class="text-amber-400" x-text="d.redirects"></span></p>
                            </template>
                            <p x-show="dups.redirects.length === 0" class="text-emerald-400">✅ Ingen redirects fundet</p>
                        </div>
                    </div>
                </template>
            </div>
            <p x-show="!dups" class="text-xs text-zinc-500">Kør et site-crawl først — kræver crawl-data.</p>
        </div>

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="histOpen" style="display: none;" id="histcard">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3" id="histtitle">Historik</h2>
            <canvas id="histchart" height="80"></canvas>
        </div>
    </section>

    <!-- SERP & SPY -->
    <section x-show="tab === 'spy'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Opdag konkurrenter (SERP)</h2>
            <form action="/serp/discover" method="POST" class="flex gap-2">
                <input type="text" name="keyword" placeholder="Søgeord / emne..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Søg & Scan</button>
            </form>
            <p class="text-[10px] text-zinc-600 mt-2">Fejl logges nu under Alarmer i stedet for at forsvinde.</p>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Fundne konkurrenter</h2>
            <div class="space-y-2">
                {% for comp in competitors %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs space-y-1">
                    <div class="flex justify-between items-center">
                        {% if comp.url.startswith('http') %}<a href="{{ comp.url }}" target="_blank" rel="noopener" class="font-medium text-emerald-400 hover:underline">{{ comp.name }}</a>{% else %}<span class="font-medium text-zinc-300">{{ comp.name }}</span>{% endif %}
                        <form action="/competitors/delete" method="POST">
                            <input type="hidden" name="id" value="{{ comp.id }}">
                            <button class="text-zinc-500 hover:text-rose-400">✕</button>
                        </form>
                    </div>
                    <div class="text-zinc-400">{{ comp.crawled_info }}</div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen konkurrenter fundet endnu.</p>
                {% endfor %}
            </div>
        </div>
    </section>

    <!-- ARTIKLER -->
    <section x-show="tab === 'articles'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-amber-600/40 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-amber-400/90 mb-1">SEO-strategi</h2>
            <p class="text-[10px] text-zinc-500 mb-3">Styrer AI-artikler (stil + lÃ¦ngde) og autopiloten. GÃ¦lder bÃ¥de manuel generering og autopilot.</p>
            <form action="/settings/strategy" method="POST" class="flex gap-2 items-center">
                <select name="strategy" onchange="this.form.submit()" class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                    {% for skey, st in strategies.items() %}
                    <option value="{{ skey }}"{{ ' selected' if skey == active_strategy else '' }}>{{ st.label }} — {{ st.desc }}</option>
                    {% endfor %}
                </select>
                <span class="text-[10px] text-zinc-500 whitespace-nowrap">skifter automatisk</span>
            </form>
            {% if strategy_check %}
            <div class="mt-3 border-t border-zinc-800 pt-3">
                <p class="text-[10px] uppercase tracking-wider text-zinc-500 mb-2">Pre-flight-tjek ({{ strategy_check.checked_at }})</p>
                <ul class="space-y-1">
                    {% for c in strategy_check.checks %}
                    <li class="text-xs {{ 'text-emerald-400' if c.ok else ('text-red-400' if c.kritisk else 'text-amber-400') }}">
                        {{ '✅' if c.ok else ('❌' if c.kritisk else '⚠️') }} {{ c.text }}
                    </li>
                    {% endfor %}
                </ul>
            </div>
            {% endif %}
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Generér artikel {{ '(AI: Gemini via aimlapi)' if ai_enabled else '(skabelon — sæt AIMLAPI_KEY for AI)' }}</h2>
            <form action="/articles/generate" method="POST" class="flex gap-2">
                <input type="text" name="keyword" placeholder="Emne / søgeord..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Generér</button>
            </form>
            <form action="/articles/autopilot" method="POST" class="mt-2">
                <button class="text-xs bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-4 py-1.5 rounded-lg">🌱 Autopilot ({{ strategy_autopilot_label }}): vælg idé → {{ 'prospecting + outreach' if strategy_autopilot == 'backlink' else 'AI-artikel' }} → WP-kladde</button>
                <span class="text-[10px] text-zinc-500 ml-2">kører også automatisk hver dag kl. 05:15 (modulet Growth)</span>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Kladder</h2>
            <div class="space-y-3">
                {% for art in articles %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-4 text-xs space-y-2">
                    <div class="flex justify-between items-start gap-2">
                        <div class="font-bold text-sm">{{ art.title }} <span class="text-[10px] font-normal text-zinc-500">({{ art.source }})</span></div>
                        <div class="flex gap-2 items-center shrink-0">
                            {% if art.wp_link %}<a href="{{ art.wp_link }}" target="_blank" class="text-emerald-400">Åbn i WP ↗</a>
                            {% else %}
                            <form action="/articles/score" method="POST">
                                <input type="hidden" name="id" value="{{ art.id }}">
                                <button class="bg-zinc-800 text-zinc-300 border border-zinc-700 px-3 py-1 rounded-lg">📊 Score vs SERP</button>
                            </form>
                            <form action="/articles/meta" method="POST">
                                <input type="hidden" name="id" value="{{ art.id }}">
                                <button class="bg-zinc-800 text-zinc-300 border border-zinc-700 px-3 py-1 rounded-lg">✨ Meta/social</button>
                            </form>
                            <form action="/articles/push" method="POST">
                                <input type="hidden" name="id" value="{{ art.id }}">
                                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-3 py-1 rounded-lg">⬆ Push til WP (kladde)</button>
                            </form>
                            {% endif %}
                            <form action="/articles/delete" method="POST">
                                <input type="hidden" name="id" value="{{ art.id }}">
                                <button class="text-zinc-500 hover:text-rose-400">✕</button>
                            </form>
                        </div>
                    </div>
                    {% if art.meta_title %}<div class="text-zinc-500 border-t border-zinc-800 pt-2">📌 <span class="text-zinc-300">{{ art.meta_title }}</span> — {{ art.meta_desc }}</div>{% endif %}
                    {# art.content er allow-list-saniteret i dashboard-routen i main.py (ingen scripts/handlers) #}
                    <div class="text-zinc-400 max-h-48 overflow-y-auto border-t border-zinc-800 pt-2">{{ art.content | safe }}</div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen artikler oprettet endnu.</p>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-1">🔗 Backlink-prospector</h2>
            <p class="text-xs text-zinc-500 mb-3">Søg keyword → top 10 i Google → type + kontakt-mail + AI-outreach-draft. Kræver SERPAPI_KEY (AIMLAPI_KEY for AI-drafts).</p>
            <form action="/backlinks/prospect" method="POST" class="flex gap-2 mb-4">
                <input type="text" name="keyword" placeholder="Keyword at finde links til..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Find muligheder</button>
            </form>
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead class="text-zinc-500 border-b border-zinc-800">
                        <tr><th class="text-left py-2 pr-3">Keyword</th><th class="text-left py-2 pr-3">Site</th><th class="text-left py-2 pr-3">Type</th><th class="text-left py-2 pr-3">E-mail</th><th class="text-left py-2 pr-3">Draft</th><th></th></tr>
                    </thead>
                    <tbody>
                        {% for b in backlink_rows %}
                        <tr class="border-b border-zinc-800/60">
                            <td class="py-2 pr-3 text-zinc-300">{{ b.keyword }}</td>
                            <td class="py-2 pr-3">{% if b.url.startswith('http') %}<a href="{{ b.url }}" target="_blank" rel="noopener" class="text-emerald-400">{{ b.site }}</a>{% else %}<span class="text-zinc-300">{{ b.site }}</span>{% endif %}</td>
                            <td class="py-2 pr-3 text-zinc-400">{{ b.type }}</td>
                            <td class="py-2 pr-3 text-zinc-300">{{ b.email or '—' }}</td>
                            <td class="py-2 pr-3 max-w-md"><details><summary class="cursor-pointer text-zinc-400">Vis draft</summary><p class="mt-2 text-zinc-400 whitespace-pre-line">{{ b.draft }}</p></details></td>
                            <td class="py-2 pr-3">
                                <form action="/backlinks/delete" method="POST"><input type="hidden" name="id" value="{{ b.id }}"><button class="text-zinc-500 hover:text-rose-400">✕</button></form>
                            </td>
                        </tr>
                        {% endfor %}
                        {% if not backlink_rows %}
                        <tr><td colspan="6" class="py-3 text-zinc-500">Ingen backlink-muligheder endnu.</td></tr>
                        {% endif %}
                    </tbody>
                </table>
            </div>
        </div>
    </section>

    <!-- KEYWORDS -->
    <section x-show="tab === 'keywords'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Keyword-positioner (SerpAPI, dagligt kl. 06:00) — sporer: {{ track_domain }}</h2>
                <form action="/keywords/check" method="POST"><button class="text-xs text-emerald-400">🔄 Tjek nu</button></form>
            </div>
            <form action="/keywords/add" method="POST" class="flex gap-2 mb-3">
                <input type="text" name="keyword" placeholder="fx steampunk goggles" required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Tilføj</button>
            </form>
            <div class="space-y-2">
                {% for kw in keywords %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-center">
                    <div>
                        <span class="font-medium">{{ kw.keyword }}</span>
                        {% if kw.position %}<span class="ml-2 px-2 py-0.5 rounded {% if kw.position <= 3 %}bg-emerald-500/10 text-emerald-400{% elif kw.position <= 10 %}bg-amber-500/10 text-amber-400{% else %}bg-zinc-800 text-zinc-400{% endif %}">#{{ kw.position }}</span>{% else %}<span class="text-zinc-600 ml-2">ikke i top 50</span>{% endif %}
                        {% if kw.target_url %}<a href="{{ kw.target_url }}" target="_blank" class="text-zinc-500 ml-2 truncate inline-block max-w-xs align-bottom">{{ kw.target_url }}</a>{% endif %}
                    </div>
                    <form action="/keywords/delete" method="POST">
                        <input type="hidden" name="id" value="{{ kw.id }}">
                        <button class="text-zinc-500 hover:text-rose-400">✕</button>
                    </form>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen keywords tilføjet endnu.</p>
                {% endfor %}
            </div>
        </div>

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Keyword-ideer (Ubersuggest-kopi — Google/DDG autocomplete)</h2>
            <form action="/keywords/ideas" method="POST" class="flex gap-2">
                <input type="text" name="keyword" placeholder="fx steampunk goggles" required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Find idéer</button>
            </form>
            <div class="flex flex-wrap gap-2 mt-3">
                {% for i in ideas %}
                <span class="px-2 py-0.5 rounded-lg bg-zinc-800 text-zinc-300 text-[11px]">{{ i.idea }} <span class="text-zinc-600">{{ i.source }}</span></span>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Visibility Index (SE Ranking-kopi — beregnes ved hvert keyword-tjek)</h2>
            <canvas id="vischart" height="70"></canvas>
        </div>
    </section>

    <!-- LINKS -->
    <section x-show="tab === 'links'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Tjek link-struktur</h2>
            <form action="/links/check" method="POST" class="flex gap-2">
                <input type="text" name="url" placeholder="https://eksempel.dk" required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Tjek links</button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Historik</h2>
            <div class="space-y-2">
                {% for item in linkchecks %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs space-y-1">
                    <div class="font-medium text-emerald-400">{{ item.url }}</div>
                    <div class="text-zinc-300">{{ item.result }}</div>
                    <div class="text-zinc-500 text-[10px]">{{ item.checked_at }}</div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen linktjek udført.</p>
                {% endfor %}
            </div>
        </div>
    </section>

    <!-- SOCIAL -->
    <section x-show="tab === 'social'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">⚙️ Steamgears Autopilot (WordPress)</h2>
                {% if sgap_ready and modules['autopilot'] %}
                <form action="/autopilot/sync" method="POST"><button class="text-xs text-emerald-400">↻ Opdater nu</button></form>
                {% endif %}
            </div>
            {% if not sgap_ready %}
            <p class="text-xs text-zinc-500">Saet WP_URL, WP_USER (administrator) og WP_APP_PASSWORD i .env for at forbinde til autopilot-pluginnet.</p>
            {% elif not modules['autopilot'] %}
            <p class="text-xs text-zinc-500">Modulet "Autopilot-bro" er slukket under Moduler.</p>
            {% elif not sgap %}
            <p class="text-xs text-zinc-500">Ingen data endnu - tryk "Opdater nu" (henter automatisk hver 30. min).</p>
            {% elif not sgap.ok %}
            <p class="text-xs text-rose-400">{{ sgap.error }}</p>
            <p class="text-[10px] text-zinc-500 mt-1">Tjekket {{ sgap.checked_at }}</p>
            {% else %}
            <div class="grid grid-cols-2 md:grid-cols-5 gap-2 mb-3 text-center">
                {% for label, key in [("I koe", "queued"), ("Sendes", "sending"), ("Udgivet", "published"), ("Fejlet", "failed")] %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-2">
                    <div class="text-lg font-bold {% if key == 'failed' and sgap.queue.get(key, 0) %}text-rose-400{% else %}text-emerald-400{% endif %}">{{ sgap.queue.get(key, 0) }}</div>
                    <div class="text-[10px] text-zinc-500">{{ label }}</div>
                </div>
                {% endfor %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-2">
                    <div class="text-lg font-bold {% if sgap.pending_drafts %}text-amber-400{% else %}text-emerald-400{% endif %}">{{ sgap.pending_drafts }}</div>
                    <div class="text-[10px] text-zinc-500">Kladder venter</div>
                </div>
            </div>
            <table class="w-full text-xs">
                <thead><tr class="text-zinc-500 text-left"><th class="py-1">Kanal (30 dage)</th><th>Udgivet</th><th>Klik</th><th>Ordrer</th><th>Omsaetning</th></tr></thead>
                <tbody>
                {% for c in sgap.channels %}
                <tr class="border-t border-zinc-800"><td class="py-1">{{ c.channel }}</td><td>{{ c.publish }}</td><td>{{ c.click }}</td><td>{{ c.order }}</td><td>{{ c.revenue }}</td></tr>
                {% else %}
                <tr><td colspan="5" class="py-1 text-zinc-500">Ingen aktivitet de sidste 30 dage.</td></tr>
                {% endfor %}
                </tbody>
            </table>
            <p class="text-[10px] text-zinc-500 mt-2">Tjekket {{ sgap.checked_at }} · Godkend kladder i WordPress: Steamgears → AI Drafts</p>
            {% endif %}
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Tilføj socialt opslag</h2>
            <form action="/social/add" method="POST" class="space-y-3">
                <input type="text" name="platform" placeholder="Platform (f.eks. Pinterest, LinkedIn, X)" required class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <textarea name="message" placeholder="Opslagets tekst..." rows="3" required class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm"></textarea>
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Tilføj til kø</button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Opslagskø</h2>
                <a href="/social/export.csv" class="text-xs text-emerald-400">⬇ Export CSV</a>
            </div>
            <div class="space-y-2">
                {% for post in socialqueue %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-start">
                    <div class="space-y-1">
                        <span class="inline-block bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-2 py-0.5 rounded text-[10px]">{{ post.platform }}</span>
                        <p class="text-zinc-300 whitespace-pre-wrap">{{ post.message }}</p>
                        <p class="text-[10px] text-zinc-500">{{ post.status }}</p>
                    </div>
                    <div class="flex items-center gap-2">
                        {% if sgap_ready and modules['autopilot'] %}
                        <form action="/social/to-autopilot" method="POST">
                            <input type="hidden" name="id" value="{{ post.id }}">
                            <button class="text-[11px] text-emerald-400 hover:text-emerald-300" title="Send som kladde til Steamgears Autopilot">→ Autopilot</button>
                        </form>
                        {% endif %}
                        <form action="/social/delete" method="POST">
                            <input type="hidden" name="id" value="{{ post.id }}">
                            <button class="text-zinc-500 hover:text-rose-400">✕</button>
                        </form>
                    </div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen opslag i køen.</p>
                {% endfor %}
            </div>
        </div>
    </section>

    <!-- ALARMER -->
    <section x-show="tab === 'alarms'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Åbne alarmer {% if telegram_enabled %}<span class="text-emerald-400">· Telegram 🔔 aktiv</span>{% endif %}</h2>
            <div class="space-y-2">
                {% for alarm in alarms %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-start">
                    <div>
                        <span class="inline-block px-2 py-0.5 rounded text-[10px] {% if alarm.severity == 'kritisk' %}bg-rose-500/10 text-rose-400{% else %}bg-amber-500/10 text-amber-400{% endif %}">{{ alarm.severity }}</span>
                        <span class="ml-2">{{ alarm.type }}: {{ alarm.message }}</span>
                        <div class="text-zinc-500 text-[10px] mt-1">{{ alarm.created_at }}</div>
                    </div>
                    <form action="/alarms/resolve" method="POST">
                        <input type="hidden" name="id" value="{{ alarm.id }}">
                        <button class="text-zinc-500 hover:text-emerald-400">✓</button>
                    </form>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen åbne alarmer. 🎉</p>
                {% endfor %}
            </div>
        </div>
    </section>

    <!-- AI TOOLS -->
    <section x-show="tab === 'ai'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">AI interne link-forslag (AI Link Genius-stil)</h2>
                <button @click="$el.textContent='Arbejder...'; fetch('/seo/linksuggest', {method:'POST'}).then(r=>r.json()).then(r=>{$el.textContent = r.ok ? '✅ ' + r.count + ' forslag' : '❌ ' + r.error; setTimeout(()=>location.reload(), 1200)})"
                        class="text-xs text-emerald-400">Generér forslag</button>
            </div>
            <div class="space-y-2">
                {% for l in links_sug %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs">
                    <div class="text-zinc-300">{{ l.anchor }} — <span class="text-zinc-500">{{ l.reason }}</span></div>
                    <div class="text-zinc-500 truncate">{{ l.from_url }} → <span class="text-emerald-400">{{ l.to_url }}</span></div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen forslag endnu. Kør site-crawl først, og kræver AIMLAPI_KEY.</p>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">AI-synlighed (RankMath AI Visibility-stil)</h2>
            <form action="/ai/visibility" method="POST" class="flex gap-2">
                <input type="text" name="question" placeholder="Hvor køber man steampunk goggles online?" required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Spørg AI</button>
            </form>
            <div class="space-y-2 mt-3">
                {% for v in ai_vis %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs space-y-1">
                    <div class="flex justify-between">
                        <span class="text-zinc-300">{{ v.question }}</span>
                        <span class="{% if v.mention_found %}text-emerald-400{% else %}text-rose-400{% endif %}">{{ '✅ Nævnt' if v.mention_found else '❌ Ikke nævnt' }}</span>
                    </div>
                    {% if v.snippet %}<div class="text-zinc-500">...{{ v.snippet }}...</div>{% endif %}
                    <div class="text-zinc-500 text-[10px]">{{ v.checked_at }}</div>
                </div>
                {% endfor %}
            </div>
        </div>
    </section>

    <!-- MONITORS -->
    <section x-show="tab === 'monitors'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Content-monitors (Uptime Kuma-stil, tjekkes hver time)</h2>
                <form action="/monitors/check" method="POST"><button class="text-xs text-emerald-400">🔄 Tjek nu</button></form>
            </div>
            <form action="/monitors/add" method="POST" class="grid grid-cols-1 md:grid-cols-5 gap-2 mb-3">
                <input type="text" name="name" placeholder="Navn" required class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="text" name="url" placeholder="https://steamgears.eu/shop/" required class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <select name="type_" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <option value="contains">contains (tekst på siden)</option>
                    <option value="json">json (API-felt)</option>
                    <option value="price">pris (JSON-LD / product:price)</option>
                </select>
                <input type="text" name="expected" placeholder="fx 'Add to cart' eller products.0.name" required class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Tilføj</button>
            </form>
            <div class="space-y-2">
                {% for m in monitors %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-center">
                    <div>
                        <span class="font-medium">{{ m.name }}</span>
                        <span class="text-zinc-500 ml-2">{{ m.url }}</span>
                        <div class="text-zinc-500">{{ m.last_status }} · {{ m.last_checked or 'ikke tjekket' }}</div>
                    </div>
                    <form action="/monitors/delete" method="POST">
                        <input type="hidden" name="id" value="{{ m.id }}">
                        <button class="text-zinc-500 hover:text-rose-400">✕</button>
                    </form>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen monitors endnu — fx: tjek at shop-siden indeholder 'Add to cart'.</p>
                {% endfor %}
            </div>
        </div>
    </section>

    <!-- PRO -->
    <section x-show="tab === 'pro'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Content Gap (Semrush-kopi — kræver SERPAPI_KEY)</h2>
            <form action="/serp/gap" method="POST" class="flex gap-2">
                <input type="text" name="keyword" placeholder="Søgeord..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Analysér top 10</button>
                <button formaction="/keywords/difficulty" class="bg-amber-500/10 text-amber-400 border border-amber-500/30 px-5 py-2 rounded-xl text-sm whitespace-nowrap">🎯 Sværhedsgrad</button>
            </form>
            <div class="space-y-2 mt-3">
                {% for g in gaps %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs">
                    <div class="font-medium text-emerald-400">{{ g.keyword }} <span class="text-zinc-500 text-[10px]">{{ g.created_at[:16] }}</span></div>
                    <div class="text-zinc-400">{{ g.stats_json | truncate(160) }}</div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen gap-analyser endnu.</p>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Keyword-sværhedsgrad (Ahrefs-kopi — heuristic over top 10)</h2>
            <div class="flex flex-wrap gap-2">
                {% for k in difficulties %}
                <span class="px-2 py-1 rounded-lg text-[11px] {% if k.difficulty < 35 %}bg-emerald-500/10 text-emerald-400{% elif k.difficulty < 60 %}bg-amber-500/10 text-amber-400{% else %}bg-rose-500/10 text-rose-400{% endif %}">
                    {{ k.keyword }} · {{ k.difficulty }}/100 · {{ k.authority }} autoritetsdomæner
                </span>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen analyser endnu — brug 🎯-knappen ovenfor.</p>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Email-finder til outreach (Hunter.io-kopi)</h2>
            <form action="/outreach/scan" method="POST" class="flex gap-2">
                <input type="text" name="url" placeholder="https://konkurrent.dk/kontakt" required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Scan emails</button>
            </form>
            <div class="flex flex-wrap gap-2 mt-3">
                {% for o in outreach_rows %}
                <span class="px-2 py-0.5 rounded-lg bg-emerald-500/10 text-emerald-400 text-[11px]">{{ o.email }}</span>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen emails fundet endnu.</p>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Pris-overvågning</h2>
            <p class="text-xs text-zinc-400">Tilføj en monitor med typen <span class="text-emerald-400">pris</span> under 🩺 Monitors — så alarmeres der (Telegram + alarmer) når konkurrenter ændrer pris. Bruges fx på AliExpress-/konkurrent-produktsider med JSON-LD eller product:price-meta.</p>
        </div>
    </section>

    <!-- MODULER -->
    <section x-show="tab === 'moduler'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-1">Moduler</h2>
            <p class="text-xs text-zinc-500 mb-4">Slå funktioner til/fra. Slukkede moduler kører ikke automatisk og viser ikke knapper i API-kald.</p>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
                {% set module_labels = {"domains": "🌐 Domæne-tjek", "keywords": "🎯 Keyword-tjek", "ai": "🤖 AI (artikler/rewrite)", "monitors": "🩺 Monitors", "social": "📱 Social-kø", "links": "🔗 Linktjek", "bridge": "🌉 Pull-bro", "spy": "🕷️ Spy/konkurrenter", "wp_push": "📝 WordPress-push", "telegram": "📬 Telegram", "growth": "🌱 Growth-autopilot", "autopilot": "⚙️ Autopilot-bro (WordPress)"} %}
                {% for m, label in module_labels.items() %}
                <div class="flex items-center justify-between bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2">
                    <span class="text-xs text-zinc-300">{{ label }}</span>
                    {% if modules[m] %}
                    <form action="/settings/module" method="POST">
                        <input type="hidden" name="name" value="{{ m }}"><input type="hidden" name="state" value="off">
                        <button class="text-[11px] bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-3 py-1 rounded-lg">✅ Til — sluk</button>
                    </form>
                    {% else %}
                    <form action="/settings/module" method="POST">
                        <input type="hidden" name="name" value="{{ m }}"><input type="hidden" name="state" value="on">
                        <button class="text-[11px] bg-zinc-800 text-zinc-400 border border-zinc-700 px-3 py-1 rounded-lg">⛔ Slukket — tænd</button>
                    </form>
                    {% endif %}
                </div>
                {% endfor %}
            </div>
        </div>
    </section>

    <!-- BRUGERE -->
    <section x-show="tab === 'brugere'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Brugere ({{ users|length }})</h2>
            <p class="text-xs text-zinc-500 mb-3">Adgang sker med brugernavn + adgangskode (PBKDF2-SHA256). Den foerste bruger blev oprettet ved foerste besoeg — opret gerne en ekstra, saa du ikke laaser dig ude.</p>
            <div class="space-y-2">
                {% for u in users %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-center">
                    <div>
                        <span class="font-medium">{{ u.username }}</span>
                        {% if current_user and u.id == current_user.id %}<span class="text-[10px] text-emerald-400 ml-2">dig</span>{% endif %}
                        <div class="text-zinc-500">Oprettet {{ u.created_at }}</div>
                    </div>
                    <form action="/users/delete" method="POST">
                        <input type="hidden" name="id" value="{{ u.id }}">
                        <button class="text-zinc-500 hover:text-rose-400">✕</button>
                    </form>
                </div>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Opret bruger</h2>
            <form action="/users/add" method="POST" class="grid grid-cols-1 md:grid-cols-3 gap-2">
                <input type="text" name="username" placeholder="Brugernavn" required pattern="[A-Za-z0-9._-]{3,32}" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="password" name="password" placeholder="Adgangskode (min. 8 tegn)" required minlength="8" autocomplete="new-password" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Opret bruger</button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Skift min adgangskode</h2>
            <form action="/users/password" method="POST" class="grid grid-cols-1 md:grid-cols-4 gap-2">
                <input type="password" name="current" placeholder="Nuværende" required autocomplete="current-password" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="password" name="new" placeholder="Ny (min. 8 tegn)" required minlength="8" autocomplete="new-password" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="password" name="confirm" placeholder="Gentag ny" required minlength="8" autocomplete="new-password" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Gem</button>
            </form>
            <p class="text-[10px] text-zinc-600 mt-2">Ved skift logges dine andre sessioner ud.</p>
        </div>
    </section>

    <!-- NOTER -->
    <section x-show="tab === 'notes'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Ny note</h2>
            <form action="/notes/add" method="POST" class="space-y-3">
                <textarea name="content" placeholder="Skriv en hurtig note..." rows="3" required class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm"></textarea>
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Gem note</button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Noter</h2>
            <div class="space-y-2">
                {% for note in notes %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-start">
                    <div class="space-y-1">
                        <p class="text-zinc-300 whitespace-pre-wrap">{{ note.content }}</p>
                        <p class="text-zinc-500 text-[10px]">{{ note.created_at }}</p>
                    </div>
                    <form action="/notes/delete" method="POST">
                        <input type="hidden" name="id" value="{{ note.id }}">
                        <button class="text-zinc-500 hover:text-rose-400">✕</button>
                    </form>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen noter oprettet endnu.</p>
                {% endfor %}
            </div>
        </div>
    </section>
</main>

<script>
function showHistory(domainId, url) {
    const s = Alpine.$data(document.body);
    s.histOpen = true;
    document.getElementById('histtitle').textContent = 'Svartid-historik: ' + (url || '');
    fetch('/api/history/' + domainId).then(r => r.json()).then(data => {
        const ctx = document.getElementById('histchart');
        if (window.histChartInstance) window.histChartInstance.destroy();
        window.histChartInstance = new Chart(ctx, {
            type: 'line',
            data: { labels: data.labels, datasets: [{ label: 'ms', data: data.ms, borderColor: '#34d399', tension: 0.3, pointRadius: 2 }] },
            options: { plugins: { legend: { display: false } }, scales: { x: { ticks: { color: '#71717a', font: { size: 9 } } }, y: { ticks: { color: '#71717a' } } } }
        });
    });
}

function loadHealth() {
    fetch('/api/health-history').then(r => r.json()).then(data => {
        if (!data.scores.length) return;
        if (window.healthChartInstance) window.healthChartInstance.destroy();
        window.healthChartInstance = new Chart(document.getElementById('healthchart'), {
            type: 'line',
            data: { labels: data.labels, datasets: [{ label: 'snitscore', data: data.scores, borderColor: '#f59e0b', backgroundColor: 'rgba(245,158,11,0.1)', fill: true, tension: 0.3 }] },
            options: { plugins: { legend: { display: false } }, scales: { x: { ticks: { color: '#71717a', font: { size: 9 } } }, y: { ticks: { color: '#71717a' }, min: 0, max: 100 } } }
        });
    });
}
if (document.getElementById('healthchart')) loadHealth();

function ccState() { return Alpine.$data(document.body); }
function loadDiff() {
    fetch('/api/crawl/diff').then(r => r.json()).then(d => {
        const s = ccState();
        if (d.error) { s.redir = null; s.diff = { new: [], removed: [], changed_content: [], score_drops: [], error: d.error }; }
        else { s.redir = null; s.diff = d; }
    });
}
function loadRedirects() {
    fetch('/api/redirects').then(r => r.json()).then(d => { const s = ccState(); s.diff = null; s.redir = d; });
}
function loadRewrite() {
    const s = ccState();
    const form = document.querySelector('input[name=psi]')?.closest('form');
    const url = (form?.querySelector('input[name=url]')?.value || '').trim();
    const kw = (form?.querySelector('input[name=keyword]')?.value || '').trim();
    if (!url) return;
    fetch('/seo/rewrite', { method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'url=' + encodeURIComponent(url) + '&keyword=' + encodeURIComponent(kw) })
        .then(r => r.json()).then(d => { s.rewrite = d.error ? { error: d.error } : d; });
}
function loadVis() {
    fetch('/api/visibility').then(r => r.json()).then(data => {
        if (!data.scores.length) return;
        if (window.visChartInstance) window.visChartInstance.destroy();
        window.visChartInstance = new Chart(document.getElementById('vischart'), {
            type: 'line',
            data: { labels: data.labels, datasets: [{ label: 'visibility %', data: data.scores, borderColor: '#34d399', backgroundColor: 'rgba(52,211,153,0.1)', fill: true, tension: 0.3 }] },
            options: { plugins: { legend: { display: false } }, scales: { x: { ticks: { color: '#71717a', font: { size: 9 } } }, y: { ticks: { color: '#71717a' }, min: 0, max: 100 } } }
        });
    });
}
if (document.getElementById('vischart')) loadVis();
</script>
</body>
</html>
EOF_HTML

echo "📄 app/templates/login.html..."
cat << 'EOF_LOGIN' > "$PROJECT_DIR/app/templates/login.html"
<!DOCTYPE html>
<html lang="da">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Command Center — {{ 'Opret bruger' if mode == 'setup' else 'Log ind' }}</title>
    <style>
      /* Ingen CDN'er: login-siden skal virke og se ens ud uden internetadgang. */
      :root { color-scheme: dark; }
      * { box-sizing: border-box; }
      body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
             padding: 24px; background: #09090b; color: #f4f4f5;
             font: 14px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
      .card { width: 100%; max-width: 390px; background: #18181b; border: 1px solid #27272a;
              border-radius: 16px; padding: 28px; box-shadow: 0 20px 50px rgba(0,0,0,.4); }
      h1 { margin: 0 0 6px; font-size: 16px; letter-spacing: .02em; }
      p.sub { margin: 0 0 18px; font-size: 12px; color: #a1a1aa; }
      label { display: block; margin: 14px 0 6px; font-size: 11px; letter-spacing: .06em;
              text-transform: uppercase; color: #a1a1aa; }
      input { width: 100%; padding: 10px 12px; font-size: 14px; color: #f4f4f5; background: #09090b;
              border: 1px solid #3f3f46; border-radius: 10px; }
      input:focus-visible { outline: 2px solid #34d399; outline-offset: 1px; border-color: #34d399; }
      button { width: 100%; margin-top: 22px; padding: 11px 16px; font-size: 14px; font-weight: 600;
               color: #34d399; background: rgba(52,211,153,.12); border: 1px solid rgba(52,211,153,.35);
               border-radius: 10px; cursor: pointer; }
      button:hover { background: rgba(52,211,153,.2); }
      button:focus-visible { outline: 2px solid #34d399; outline-offset: 2px; }
      .error { margin: 0 0 6px; padding: 9px 11px; font-size: 12px; color: #fda4af;
               background: rgba(244,63,94,.09); border: 1px solid rgba(244,63,94,.35); border-radius: 10px; }
      .foot { margin: 16px 0 0; font-size: 11px; color: #71717a; text-align: center; }
    </style>
</head>
<body>
<div class="card">
    <h1>⚡ COMMAND CENTER</h1>
    {% if mode == 'setup' %}
    <p class="sub">Foerste start: opret din bruger. Der er ingen token — kun brugernavn og adgangskode.</p>
    {% else %}
    <p class="sub">Log ind med din bruger.</p>
    {% endif %}
    {% if error %}<p class="error">{{ error }}</p>{% endif %}
    <form action="{{ '/setup' if mode == 'setup' else '/login' }}" method="POST">
        <label for="username">Brugernavn</label>
        <input id="username" type="text" name="username" value="{{ username }}" autocomplete="username"
               pattern="[A-Za-z0-9._-]{3,32}" title="3-32 tegn: a-z, 0-9, punktum, bindestreg, underscore"
               required autofocus>
        <label for="password">Adgangskode</label>
        <input id="password" type="password" name="password" autocomplete="{{ 'new-password' if mode == 'setup' else 'current-password' }}"
               minlength="8" required>
        {% if mode == 'setup' %}
        <label for="confirm">Gentag adgangskode</label>
        <input id="confirm" type="password" name="confirm" autocomplete="new-password" minlength="8" required>
        {% endif %}
        <button type="submit">{{ 'Opret bruger og log ind' if mode == 'setup' else 'Log ind' }}</button>
    </form>
    <p class="foot">Adgangskoder gemmes som PBKDF2-SHA256-hash. Sessionen varer 30 dage.</p>
</div>
</body>
</html>
EOF_LOGIN

echo "📄 run.sh..."
cat << 'EOF_RUNSH' > "$PROJECT_DIR/run.sh"
#!/bin/bash
cd "$(dirname "$0")"
if [ -f .env ]; then
    set -a; source .env; set +a
fi
HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
PUBLIC="${CC_PUBLIC_URL:-}"
FORWARDED="${CC_FORWARDED_ALLOW_IPS:-127.0.0.1}"

# Maskinens rigtige IPv4 (bruges naar der lyttes paa 0.0.0.0)
lan_ip() {
    { hostname -I 2>/dev/null | awk '{print $1}'
      ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}'
    } | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt

mkdir -p app/data
echo $$ > app/data/cc.pid   # pidfile: scripts/restart.sh kan genstarte en app startet med ./run.sh
echo "⚡ Starter Command Center v7.11..."
echo "   Lokalt:   http://127.0.0.1:$PORT"
if [ -n "$PUBLIC" ]; then
    echo "   Offentlig: $PUBLIC   (via nginx -> http://$HOST:$PORT)"
    echo "   nginx:    proxy_set_header X-Forwarded-Proto \$scheme;  (ellers bliver cookien ikke Secure)"
fi
case "$HOST" in
    0.0.0.0|::|"")
        echo "   Netvaerk: http://$(lan_ip || echo '<din-ip>'):$PORT   (lytter paa $HOST:$PORT)"
        ;;
    *)
        echo "   Lytter paa $HOST:$PORT — brug CC_HOST=0.0.0.0 for adgang uden nginx"
        ;;
esac
echo "   Login:    opret din bruger ved foerste besoeg (ingen token), derefter brugernavn + adgangskode"

if [ "$DEV" = "1" ]; then
    exec uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips "$FORWARDED" --reload
else
    exec uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips "$FORWARDED"
fi
EOF_RUNSH

echo "📄 Dockerfile..."
cat << 'EOF_DOCKER' > "$PROJECT_DIR/Dockerfile"
FROM python:3.12-slim
WORKDIR /cc
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF_DOCKER

echo "📄 docker-compose.yml..."
cat << 'EOF_COMPOSE' > "$PROJECT_DIR/docker-compose.yml"
services:
  command-center:
    build: .
    ports:
      - "8000:8000"
    env_file: .env
    volumes:
      - ./app/data:/cc/app/data
    restart: unless-stopped
EOF_COMPOSE

echo "📄 deploy/command-center.service..."
cat << 'EOF_SERVICE' > "$PROJECT_DIR/deploy/command-center.service"
[Unit]
Description=Steamgears Command Center
After=network.target

[Service]
Type=simple
User=%i
WorkingDirectory=/home/%i/command-center
# Goer .env-vaerdier (GITHUB_TOKEN m.fl.) til rigtige miljoevariabler; "-" = ok hvis filen mangler.
EnvironmentFile=-/home/%i/command-center/.env
# proxy-headers + forwarded-allow-ips: nginx paa 127.0.0.1 sender X-Forwarded-Proto/For.
ExecStart=/home/%i/command-center/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE

echo "📄 deploy/nginx-command-center.conf..."
cat << 'EOF_NGINX' > "$PROJECT_DIR/deploy/nginx-command-center.conf"
# Command Center bag nginx (Ultra.cc / VPS)
#
# Saadan bruges den:
#   Ultra.cc: læg filen i din nginx-proxy-mappe (fx ~/.apps/nginx/proxy.d/command-center.conf)
#             eller kopier "location /"-blokken ind i den server { } du bruger.
#   VPS:      kopier til /etc/nginx/conf.d/command-center.conf og ret server_name.
#
# Appen skal lytte paa 127.0.0.1:8000 (CC_HOST/CC_PORT i .env) og har ingen websockets,
# saa der er ingen "map"- eller "upstream"-blokke - kun det her, som virker inde i en server { }.
#
# VIGTIGT: appen kan ikke ligge paa en understi (https://host/apps/cc/) - alle links er absolute.
# Brug et subdomæne eller en egen port til Command Center.

server {
    listen 80;
    server_name cc.eksempel.dk;

    # Slaa TLS til (Ultra.cc har certifikater i deres panel; ellers brug certbot).
    # Derefter: return 301 https://$host$request_uri;  i denne blok,
    # og flyt location-blokken ned i en "listen 443 ssl;"-server.

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;

        # Uden X-Forwarded-Proto tror appen den koerer paa http:
        # session-cookien bliver ikke Secure, og der vises en HTTPS-advarsel i UI'et.
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Crawl, content gap, backlink-prospecting og AI-kald kan tage minutter - ellers 504.
        proxy_connect_timeout 15s;
        proxy_send_timeout    300s;
        proxy_read_timeout    300s;
        proxy_buffering       off;

        # Formularer er smaa: et loft saa et stort opslag ikke kan dræbe proxien.
        client_max_body_size 4m;

        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy same-origin always;
    }
}
EOF_NGINX

echo "📄 deploy/command-center.user.service..."
cat << 'EOF_USERSVC' > "$PROJECT_DIR/deploy/command-center.user.service"
[Unit]
Description=Steamgears Command Center (bruger-service, fx Ultra.cc)
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/command-center
# Lader .env-vaerdier som GITHUB_TOKEN og BRIDGE_POLL_MINUTES blive rigtige miljoevariabler
# (appen laeser selv de fleste, men dette er den paalidelige vej). "-" = ok hvis filen mangler.
EnvironmentFile=-%h/command-center/.env
# 127.0.0.1 + proxy-headers: nginx paa samme maskine sender X-Forwarded-Proto/For.
ExecStart=%h/command-center/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF_USERSVC

echo "📄 README.md..."
cat << 'EOF_README' > "$PROJECT_DIR/README.md"
# Command Center v7.11 PRO

Selv-hostet SEO- og drifts-center (FastAPI + SQLite) i stil med RankMath Pro / Yoast Premium — bygget til Steamgears.
Alt kører på din egen server: dine data, ingen abonnement. Se [docs/ROADMAP.md](docs/ROADMAP.md) for hvad der er færdigt og hvad der er næste.

## Nyheder i v7.11

- **Brugere i stedet for token-login** — første besøg opretter din bruger (`/setup`), derefter logger du ind med brugernavn + adgangskode (PBKDF2-SHA256, salt pr. bruger, 30 dages HttpOnly-session). Fanen **Brugere** opretter/sletter brugere og skifter adgangskode. `APP_TOKEN` findes ikke længere; `JUNO_TOKEN` er nu kun en maskin-nøgle til `/api/*`.
- **Opdatering fra GitHub** — Cockpit viser installeret commit vs. seneste commit på `main`, tjekker selv kl. 05:00, og "Opdater" laver DB-backup og henter kun projektets filer. Den gamle "hent install.sh og kør den"-vej er fjernet.
- **nginx / Ultra.cc** — `deploy/nginx-command-center.conf`, `deploy/command-center.user.service` og proxy-header-understøttelse, så appen bliver på `127.0.0.1` bag nginx med korrekte Secure-cookies og rigtig klient-IP.
- **Rettelser fra kodegennemgang** — saniteret artikel-HTML (XSS), `.env` læses før konfigurationen, pris-monitors registrerer ændringer igen, crawl-diff virker (to crawls gemmes), `/monitors/add` giver ikke længere 500, HTTPS-advarslen rammer rigtigt, plus mindre korrekthedsrettelser.

## Funktioner

- 🎛️ **Cockpit** — domæneovervågning (uptime, svartid, SSL), drift-kort fra Juno-broen, opdaterings-panel og alarmer
- 🔍 **SEO Scanner** — deep audit af enkelt side (20+ vægtede kontroller inkl. focus keyword, læsbarhed, mixed content, schema, OG/Twitter) + **site-crawl** med score per side, robots.txt/sitemap-tjek og crawl-diff mod forrige crawl
- ✍️ **Artikler** — AI-generering (Gemini via aimlapi) eller skabelon, **push til WordPress som udkast**, **fakta-prompt med SerpAPI-konkurrentanalyse**, autopilot (idé → artikel → WP-kladde) og **kvalitetsgate** før publicering
- 🎯 **SEO-strategi** — AdSense / Affiliate / Backlink-vækst styrer AI-artiklernes stil + længde og autopilotens arbejde, med automatisk pre-flight-checkliste
- 🌱 **Growth Pack** — backlink-prospector (SerpAPI top 10 → sitetype + kontakt-e-mail + AI-outreach-draft), keyword-ideer via Google/DDG-autocomplete, visibility-index
- 🎯 **Keywords** — Google-positioner via SerpAPI (dagligt kl. 06:00), sværhedsgrads-heuristik, content gap mod top 10
- 🕷️ **SERP & Spy** — konkurrent-opdagelse + crawl af titel/H1/beskrivelse
- 🔗 **Links** — ekstern linktjek + AI-forslag til interne links
- 📱 **Social** — opslagskø med CSV-export og "→ Autopilot" (kladde i WordPress-pluginnet)
- 🩺 **Monitors** — tekst/JSON/pris-overvågning med alarmer ved ændring
- 👤 **Brugere** — opret/slet brugere, skift adgangskode; den sidste bruger kan ikke slettes
- 🚨 **Alarmer** — SSL-udløb, nedetid, brudte links, fejlede scans, nye GitHub-commits; valgfrit Telegram-push
- 📈 **Historik** — svartid per domæne, site-health og visibility over tid (Chart.js)
- 🌉 **Juno-broer** — `POST /api/bridge/gsc` og `/api/bridge/drift` med `X-CC-Token`

## Login & opsætning

1. `cp .env.example .env` og udfyld nøgler
2. `./run.sh` — scriptet udskriver den adresse appen lytter på (samt LAN-IP når `CC_HOST=0.0.0.0`)
3. Åbn adressen: **første besøg opretter din bruger** (`/setup`) — derefter log ind med brugernavn + adgangskode. Der er ingen token i `.env`.
4. Nye brugere, sletning og adgangskode-skift klares under fanen **Brugere**
5. (VPS) kør bag reverse proxy med TLS, eller brug `deploy/command-center.service` + SSH-tunnel

## Ultra.cc / nginx (reverse proxy)

1. `.env`: udfyld nøgler, sæt `CC_PUBLIC_URL=https://<din-adresse>`, lad `CC_HOST=127.0.0.1` og `CC_FORWARDED_ALLOW_IPS=127.0.0.1`
2. Start appen: `./run.sh`, eller `deploy/command-center.user.service` med `systemctl --user enable --now command-center`
3. Læg `deploy/nginx-command-center.conf` ind i den `server { }` du bruger (Ultra.cc: `~/.apps/nginx/proxy.d/`), og genindlæs nginx
4. Åbn `CC_PUBLIC_URL` — første besøg opretter din bruger

Det skal med i proxy-blokken:

- `proxy_set_header X-Forwarded-Proto $scheme;` — ellers tror appen den kører på http: session-cookien bliver ikke `Secure`, og der vises en HTTPS-advarsel
- `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` — så login-låsen pr. IP rammer klienten i stedet for nginx
- `proxy_read_timeout 300s;` — crawl, content gap og backlink-prospecting kan tage minutter (ellers 504 fra nginx)
- Appen kan **ikke** ligge på en understi (`https://host/apps/cc/`): alle links er absolutte — brug et subdomæne eller en egen port

## Opdatering fra GitHub

Panelet i Cockpit sammenligner installeret commit med seneste commit på `main`:

- **Tjek for nye commits** (`POST /update/check`) — viser SHA, dato og commit-besked, eller den præcise fejl (manglende token, 401/403, 404). Kører også automatisk kl. 05:00.
- **Opdater** (`POST /update/apply`) — tager en `pre-update`-backup af databasen, henter commit-tarballen og skriver **kun** projektets filer (`app/`, `scripts/`, `deploy/`, requirements, start-scripts, `install.sh`, Dockerfile, compose, `.env.example`). `.env`, databasen og `..`-stier røres ikke.
- **Alt i ét hug**: er `requirements.txt` ændret, køres `pip install -r` automatisk, og appen **genstarter sig selv** ~1,5 s efter svaret (systemd-unit, ellers `scripts/restart.sh` med pidfile + `run.sh`). Fjern fluebenet "genstart" i panelet, eller sæt `UPDATE_AUTO_RESTART=0`, for at genstarte manuelt. `UPDATE_RESTART_CMD` overstyrer kommandoen (fx din egen supervisor).
- **Fra terminalen**: `bash scripts/update.sh` gør hele kæden (tjek → filer → requirements → genstart) og venter til `/health` svarer igen; `--check` tjekker kun, `--no-restart` springer genstarten over. `bash scripts/restart.sh` genstarter uden at opdatere.
- Status som JSON: `GET /api/update` (inkl. `restart_mode` og `auto_restart`). Kræver `GITHUB_TOKEN` (privat repo) og `JUNO_TOKEN` for scriptet. `/self-update` findes stadig som alias for `/update/apply`.

## Steamgears Autopilot-bro (WordPress-plugin 7.5+)

Command Center og WordPress-pluginnet **Steamgears Autopilot** snakker sammen via pluginnets REST-API
(`/wp-json/sgap/v1`) med de samme `WP_URL` / `WP_USER` / `WP_APP_PASSWORD` som WordPress-push
(`WP_USER` skal være administrator).

- **Status hver 30. min** (fanen Social → "Steamgears Autopilot"): kø, kladder der venter på godkendelse, og udgivet/klik/ordrer/omsætning pr. kanal de sidste 30 dage
- **Alarmer** når noget ændrer sig: nye fejlede opslag, nye kladder, eller pluginnet svarer ikke
- **"→ Autopilot"** sender et opslag som kladde til pluginnet (godkendes i WordPress under Steamgears → AI Drafts)
- Slå til/fra under Moduler ("Autopilot-bro"). Retningen er altid CC → site, så CC kan blive på 127.0.0.1

## Installering

```bash
curl -H "Authorization: Bearer <TOKEN>" -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/humle93/command-center/contents/install.sh -o install.sh && bash install.sh
```

Eller med Docker: `cp .env.example .env && docker compose up -d --build`. `install.sh` er selvstændig og
skriver alle filer (inkl. `deploy/nginx-command-center.conf` og `deploy/command-center.user.service`).

## Drift & test

- **Cron**: domæne-tjek hver 6. time, keyword-tjek 06:00, autopilot 05:15, oprydning 04:30, DB-backup 04:40, GitHub-tjek 05:00, Autopilot-bro hver 30. min
- **Backup**: `app/backups/cc-daglig-*.db` (14 gemmes) + `cc-pre-update-*.db` før hver opdatering
- **Health**: `/health` (200, eller 503 ved kritisk DB/disk-tilstand) viser også månedens API-forbrug
- **Tests**: `python3 tests/test_v8_features.py` (enhedstests), `bash tests/ci_check.sh` (boot + alle sider + auth + bridge + link-audit)

## Sikkerhed

- **Brugere**: PBKDF2-SHA256 med salt pr. bruger; sessioner er HttpOnly-cookies (30 dage) gemt som `sha256(id)` i databasen, så en DB-kopi ikke giver adgang. Skift af adgangskode logger dine andre sessioner ud.
- **JUNO_TOKEN** er en separat maskin-nøgle til `/api/*` (header `X-CC-Token`), ikke til mennesker.
- **Cookie/HTTPS**: cookien sættes `Secure` når appen ser https (kræver `X-Forwarded-Proto` bag proxy — se nginx-afsnittet).
- **API-budget**: SerpAPI og aimlapi tælles pr. måned og stoppes ved loftet (`SERPAPI_MONTHLY_LIMIT`, `AI_MONTHLY_LIMIT`), med alarm ved 80 % og 100 %.
- Default binding er 127.0.0.1 — sæt aldrig `0.0.0.0` uden reverse proxy + TLS.

## Kendte begrænsninger

- Dashboardet henter Tailwind, Alpine.js og Chart.js fra CDN (login-siden er helt selvstændig). Uden internetadgang ser dashboardet stadig ud, men uden styling/interaktivitet.
- Opdatering kræver `GITHUB_TOKEN`; ændringer i `requirements.txt` rapporteres men installeres først ved næste `./run.sh`.
- `install.sh` indeholder kopier af projektets filer (CI tjekker at de matcher); ret derfor altid kildefilerne og kør regen, ikke installeren.
- Screenshots i `docs/img/` er fra v7.8-UI'et.
EOF_README

echo "📄 scripts/smoke_test.sh..."
cat << 'EOF_RESTART' > scripts/restart.sh
#!/bin/bash
# Genstarter Command Center. Bruges af opdateringen (POST /update/apply) og kan koeres manuelt.
#
#   bash scripts/restart.sh              # genstart med det samme
#   bash scripts/restart.sh --delay 2    # vent 2 s (saa HTTP-svaret kan naa frem)
#
# Raekkefoelge:
#   1. UPDATE_RESTART_CMD (hvis sat i .env)
#   2. systemd --user unit "command-center"  (Ultra.cc)
#   3. systemd system unit "command-center"
#   4. pidfile app/data/cc.pid + ./run.sh    (naar appen er startet med ./run.sh)
set -u
cd "$(dirname "$0")/.."

DELAY=0
if [ "${1:-}" = "--delay" ]; then
    DELAY="${2:-2}"
fi
case "$DELAY" in
    ''|*[!0-9]*) DELAY=0 ;;
esac
[ "$DELAY" -gt 0 ] && sleep "$DELAY"

PIDFILE="app/data/cc.pid"
LOG="nohup.out"

restart_systemd_user() {
    systemctl --user cat "$1" > /dev/null 2>&1 || return 1
    systemctl --user restart "$1"
}

restart_systemd_system() {
    systemctl cat "$1" > /dev/null 2>&1 || return 1
    systemctl restart "$1"
}

if [ -n "${UPDATE_RESTART_CMD:-}" ]; then
    echo "Genstarter med UPDATE_RESTART_CMD: $UPDATE_RESTART_CMD"
    # shellcheck disable=SC2086
    eval "$UPDATE_RESTART_CMD"
    exit $?
fi

for unit in command-center steamgears-command-center; do
    if restart_systemd_user "$unit"; then
        echo "Genstartede systemd --user unit '$unit'."
        exit 0
    fi
done

if restart_systemd_system command-center; then
    echo "Genstartede systemd unit 'command-center'."
    exit 0
fi

# Ingen unit: brug pidfile fra run.sh og start appen igen i baggrunden.
if [ -f "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Stopper proces $OLD_PID..."
        kill "$OLD_PID" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$OLD_PID" 2>/dev/null || break
            sleep 0.5
        done
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
fi

echo "Starter appen igen (log: $LOG)..."
nohup ./run.sh >> "$LOG" 2>&1 &
echo "Ny proces startet - foelg opstarten i $LOG"
exit 0
EOF_RESTART
cat << 'EOF_UPDATE' > scripts/update.sh
#!/bin/bash
# Opdaterer Command Center fra GitHub: tjek -> filsynk (med backup) -> requirements -> genstart.
# Appens update-endpoints bruges, saa logikken findes kun ét sted.
#
#   bash scripts/update.sh              # opdater + genstart, vent til appen svarer
#   bash scripts/update.sh --no-restart # opdater, men genstart selv bagefter
#   bash scripts/update.sh --check      # kun tjek, skriv intet
#
# Kraever JUNO_TOKEN i .env (maskin-noegle til /api/*).
set -u
cd "$(dirname "$0")/.."

if [ -f .env ]; then
    set -a; source .env; set +a
fi

MODE="apply"
case "${1:-}" in
    --no-restart) MODE="apply-no-restart" ;;
    --check) MODE="check" ;;
    -h|--help)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    "") ;;
    *) echo "Ukendt argument: $1 (brug --check, --no-restart eller -h)" >&2; exit 64 ;;
esac

HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
case "$HOST" in
    0.0.0.0|::|"") PROBE=127.0.0.1 ;;
    *) PROBE="$HOST" ;;
esac
BASE="http://$PROBE:$PORT"
TOKEN="${JUNO_TOKEN:-}"

PY="./venv/bin/python"
[ -x "$PY" ] || PY="python3"
field() {
    printf '%s' "$1" | "$PY" -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]))' "$2" 2>/dev/null
}

if [ -z "$TOKEN" ]; then
    echo "❌ JUNO_TOKEN mangler i .env - update-endpoints kraever maskin-noeglen." >&2
    exit 2
fi
if ! curl -sf -o /dev/null --max-time 5 -H "X-CC-Token: $TOKEN" "$BASE/api/update"; then
    echo "❌ Appen svarer ikke paa $BASE - start den foerst (./run.sh)." >&2
    exit 3
fi

echo "→ Tjekker GitHub mod $BASE..."
CHECK="$(curl -s --max-time 120 -X POST -H "X-CC-Token: $TOKEN" "$BASE/api/update/check")"
[ -n "$CHECK" ] || { echo "❌ Tomt svar fra /api/update/check" >&2; exit 4; }
echo "   installeret: $(field "$CHECK" current)"
echo "   nyeste:      $(field "$CHECK" latest)  $(field "$CHECK" message)"
if [ "$(field "$CHECK" ok)" != "True" ]; then
    echo "❌ Tjekket fejlede: $(field "$CHECK" error)" >&2
    exit 4
fi
if [ "$(field "$CHECK" behind)" != "True" ]; then
    echo "✅ Du kører nyeste version."
    exit 0
fi

if [ "$MODE" = "check" ]; then
    echo "⬆️  Ny version tilgængelig."
    exit 0
fi

RESTART=1
[ "$MODE" = "apply-no-restart" ] && RESTART=0
echo "→ Henter og skriver filer (DB-backup foerst, requirements installeres hvis de er aendret)..."
RESULT="$(curl -s --max-time 600 -X POST -H "X-CC-Token: $TOKEN" "$BASE/api/update/apply?restart=$RESTART")"
[ -n "$RESULT" ] || { echo "❌ Tomt svar fra /api/update/apply" >&2; exit 5; }

echo "   ok:           $(field "$RESULT" ok)"
echo "   filer:        $(printf '%s' "$RESULT" | "$PY" -c 'import json,sys;print(len(json.load(sys.stdin).get("files") or []))' 2>/dev/null)"
echo "   requirements: $(printf '%s' "$RESULT" | "$PY" -c 'import json,sys;d=json.load(sys.stdin).get("requirements_install") or {};print(("OK" if d.get("ok") else "FEJL")+": "+(d.get("output") or "")[:200])' 2>/dev/null)"
if [ "$(field "$RESULT" ok)" != "True" ]; then
    echo "❌ Opdateringen fejlede: $(field "$RESULT" error)" >&2
    exit 5
fi
echo "   genstart:     $(printf '%s' "$RESULT" | "$PY" -c 'import json,sys;r=json.load(sys.stdin).get("restart") or {};print(("planlagt ("+str(r.get("mode"))+")") if r.get("scheduled") else "IKKE planlagt: "+str(r.get("reason")))' 2>/dev/null)"

if [ "$RESTART" = "0" ]; then
    echo "✅ Filer opdateret. Genstart selv: bash scripts/restart.sh"
    exit 0
fi

echo "→ Venter paa at appen svarer igen..."
for _ in $(seq 1 60); do
    sleep 1
    if curl -sf -o /dev/null --max-time 3 "$BASE/health"; then
        echo "✅ Opdateret og genstartet - $BASE svarer igen."
        exit 0
    fi
done
echo "⚠️  Appen svarede ikke inden 60 s. Se logs: journalctl --user -u command-center (eller nohup.out)" >&2
exit 6
EOF_UPDATE
cat << 'EOF_SMOKE' > "$PROJECT_DIR/scripts/smoke_test.sh"
#!/bin/bash
# Command Center smoke-test - koer efter install eller self-update.
# Brug: bash scripts/smoke_test.sh   (CC_HOST/CC_PORT overstyrer adressen)
HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
PUBLIC="${CC_PUBLIC_URL:-}"
PROBE="$HOST"
case "$HOST" in
    0.0.0.0|::|"") PROBE=127.0.0.1 ;;
esac
BASE="http://$PROBE:$PORT"
echo "Smoke-test mod $BASE (lytter paa $HOST:$PORT)"
[ -n "$PUBLIC" ] && echo "Offentlig adresse (bag nginx): $PUBLIC"
ok=1
for p in /health /login /setup; do
  code=$(curl -s -o /dev/null --max-time 5 -w "%{http_code}" "$BASE$p" 2>/dev/null) || code=000
  case "$code" in
    200|303) echo "OK   $p -> $code" ;;
    *) echo "FAIL $p -> $code"; ok=0 ;;
  esac
done
if [ "$ok" = "1" ]; then
  echo "✅ Smoke-test OK — åbn ${PUBLIC:-$BASE} (første besøg opretter din bruger)"
else
  echo "❌ Smoke-test FEJLEDE - tjek logs: journalctl --user -u command-center ellers journalctl -u command-center"
fi
exit $((1 - ok))  # 0 = alt OK (shell-konvention)
EOF_SMOKE

echo "📄 run.bat..."
cat << 'EOF_WINBAT' > "$PROJECT_DIR/run.bat"
@echo off
REM Command Center - Windows startscript. Opretter din bruger ved foerste besoeg (ingen token).
cd /d "%~dp0"
if exist .env for /f "usebackq eol=# tokens=1,* delims==" %%a in (".env") do set "%%a=%%b"
set "HOST=127.0.0.1"
set "PORT=8000"
set "FORWARDED=127.0.0.1"
if defined CC_HOST set "HOST=%CC_HOST%"
if defined CC_PORT set "PORT=%CC_PORT%"
if defined CC_FORWARDED_ALLOW_IPS set "FORWARDED=%CC_FORWARDED_ALLOW_IPS%"
if not exist venv python -m venv venv
call venv\Scripts\activate.bat
python -m pip install --upgrade pip > nul 2>&1
python -m pip install -r requirements.txt
set "LAN="
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /c:"IPv4"') do if not defined LAN set "LAN=%%i"
if defined LAN set "LAN=%LAN: =%"
echo Starter Command Center v7.11 (Windows)...
echo    Lokalt:   http://127.0.0.1:%PORT%
if defined CC_PUBLIC_URL echo    Offentlig: %CC_PUBLIC_URL%   (via nginx -^> http://%HOST%:%PORT%)
if defined LAN echo    Netvaerk: http://%LAN%:%PORT%   (naas kun med CC_HOST=0.0.0.0)
echo    Login:    opret din bruger ved foerste besoeg (ingen token).
python -m uvicorn app.main:app --host %HOST% --port %PORT% --proxy-headers --forwarded-allow-ips %FORWARDED%
EOF_WINBAT

if [ -f "$PROJECT_DIR/.env" ]; then echo "✅ .env findes allerede - bruger den"; else cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"; echo "⚠ Opret .env (se .env.example) inden foerste start"; fi
cat << 'EOF_RUN' > "$PROJECT_DIR/run.sh"
#!/bin/bash
cd "$(dirname "$0")"
if [ -f .env ]; then
    set -a; source .env; set +a
fi
HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
PUBLIC="${CC_PUBLIC_URL:-}"
FORWARDED="${CC_FORWARDED_ALLOW_IPS:-127.0.0.1}"

# Maskinens rigtige IPv4 (bruges naar der lyttes paa 0.0.0.0)
lan_ip() {
    { hostname -I 2>/dev/null | awk '{print $1}'
      ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}'
    } | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt

mkdir -p app/data
echo $$ > app/data/cc.pid   # pidfile: scripts/restart.sh kan genstarte en app startet med ./run.sh
echo "⚡ Starter Command Center v7.11..."
echo "   Lokalt:   http://127.0.0.1:$PORT"
if [ -n "$PUBLIC" ]; then
    echo "   Offentlig: $PUBLIC   (via nginx -> http://$HOST:$PORT)"
    echo "   nginx:    proxy_set_header X-Forwarded-Proto \$scheme;  (ellers bliver cookien ikke Secure)"
fi
case "$HOST" in
    0.0.0.0|::|"")
        echo "   Netvaerk: http://$(lan_ip || echo '<din-ip>'):$PORT   (lytter paa $HOST:$PORT)"
        ;;
    *)
        echo "   Lytter paa $HOST:$PORT — brug CC_HOST=0.0.0.0 for adgang uden nginx"
        ;;
esac
echo "   Login:    opret din bruger ved foerste besoeg (ingen token), derefter brugernavn + adgangskode"

if [ "$DEV" = "1" ]; then
    exec uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips "$FORWARDED" --reload
else
    exec uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips "$FORWARDED"
fi
EOF_RUN
chmod +x "$PROJECT_DIR/run.sh"
if curl -s -o /dev/null --max-time 3 "http://127.0.0.1:${CC_PORT:-8000}/health" 2>/dev/null; then echo "🔎 App koerer allerede - koerer smoke-test:"; bash "$PROJECT_DIR/scripts/smoke_test.sh" || true; fi
LAN_IP=$({ hostname -I 2>/dev/null | awk '{print $1}'; ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}'; } | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "✨ Installation klar!"
echo "   Start:      cd $PROJECT_DIR && ./run.sh"
echo "   Adresse:    http://127.0.0.1:${CC_PORT:-8000}   (LAN: http://${LAN_IP:-<din-ip>}:${CC_PORT:-8000} naar CC_HOST=0.0.0.0)"
echo "   Login:      opret din bruger ved foerste besoeg - ingen token"
echo "   Smoke-test: bash $PROJECT_DIR/scripts/smoke_test.sh"
echo "   nginx:      saet CC_PUBLIC_URL i $PROJECT_DIR/.env og brug deploy/nginx-command-center.conf"

