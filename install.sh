#!/bin/bash
set -e
PROJECT_DIR="$HOME/command-center"

echo "⚡ Command Center v7.1 - installerer i $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR/app/templates" "$PROJECT_DIR/app/data" "$PROJECT_DIR/app/static" "$PROJECT_DIR/deploy"
echo "📄 requirements.txt..."
cat << 'EOF_REQ' > "$PROJECT_DIR/requirements.txt"
fastapi==0.115.6
uvicorn[standard]==0.34.0
requests==2.32.3
beautifulsoup4==4.12.3
Jinja2==3.1.5
APScheduler==3.10.4
python-dotenv==1.0.1
EOF_REQ

echo "📄 .env.example..."
cat << 'EOF_ENVDOT' > "$PROJECT_DIR/.env.example"
# Command Center v7.1 - kopier til .env og udfyld
# Login-token for hele dashboardet (OBBLIGATORISK pa VPS!)
APP_TOKEN=
JUNO_TOKEN=                              # Junos egen noegle til automatisk API-push (laeg den fra copy-siden her)
# AI-artikler: din aimlapi-noegle
AIMLAPI_KEY=
AI_MODEL=google/gemini-3-8-flash
# WordPress-push (Application Password: WP Admin > Users > Profile)
WP_URL=https://steamgears.eu
WP_USER=
WP_APP_PASSWORD=
# Alarmer via Telegram-bot (valgfrit)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
# Keyword-positioner via SerpAPI
SERPAPI_KEY=
TRACK_DOMAIN=steamgears.eu
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
import hashlib
import json as jsonlib
import subprocess

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "data", "center.db")
STATIC_DIR = os.path.join(BASE_DIR, "static")

# --- Konfiguration via miljoevariabler / .env ---
APP_TOKEN = os.environ.get("APP_TOKEN", "").strip()          # login-token (tom = ingen auth, lokal tilstand)
JUNO_TOKEN = os.environ.get("JUNO_TOKEN", "").strip()
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

app = FastAPI(title="Command Center Engine", version="7.2")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))
scheduler = AsyncIOScheduler(timezone="Europe/Copenhagen")
executor = ThreadPoolExecutor(max_workers=8)


def load_dotenv(path=None):
    path = path or os.path.join(os.path.dirname(BASE_DIR), ".env")
    if not os.path.exists(path):
        return
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip())


load_dotenv()
APP_TOKEN = os.environ.get("APP_TOKEN", "").strip()
AIMLAPI_KEY = os.environ.get("AIMLAPI_KEY", "").strip()
WP_URL = os.environ.get("WP_URL", "").strip()
WP_USER = os.environ.get("WP_USER", "").strip()
WP_APP_PASSWORD = os.environ.get("WP_APP_PASSWORD", "").strip()
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
SERPAPI_KEY = os.environ.get("SERPAPI_KEY", "").strip()
TRACK_DOMAIN = os.environ.get("TRACK_DOMAIN", "steamgears.eu").strip()


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
        CREATE TABLE IF NOT EXISTS visibility (
            day TEXT PRIMARY KEY,
            score REAL
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
        """)


init_db()


def migrate_db():
    with get_db() as db:
        cols = {}
        for table, want in {
            "articles": ["meta_title", "meta_desc"],
            "seopages": ["content_hash", "redirects"],
            "crawl_runs": ["sitemap_broken", "sitemap_missing"],
        }.items():
            existing = [r[1] for r in db.execute(f"PRAGMA table_info({table})").fetchall()]
            for c in want:
                if c not in existing:
                    db.execute(f"ALTER TABLE {table} ADD COLUMN {c} TEXT")


migrate_db()


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


create_indexes()


def cleanup_old_data():
    """Daglig oprydning: gamle maalinger rulles af, DB holdes sund."""
    with get_db() as db:
        db.execute("DELETE FROM check_history WHERE checked_at < datetime('now', '-90 days')")
        db.execute("DELETE FROM alarms WHERE resolved=1 AND created_at < datetime('now', '-30 days')")
        db.execute("DELETE FROM health_history WHERE checked_at < datetime('now', '-180 days')")
        db.execute("DELETE FROM keyword_ideas WHERE created_at < datetime('now', '-180 days')")


# ---------- Auth ----------
def is_authed(request: Request) -> bool:
    if not APP_TOKEN:
        return True
    return request.cookies.get("cc_token") == APP_TOKEN or request.headers.get("x-cc-token") == APP_TOKEN


def is_juno(request: Request) -> bool:
    """Juno-adgang: separat token, gyldig KUN for /api/*-endpoints (laese-data + bridge-push)."""
    return bool(JUNO_TOKEN) and request.headers.get("x-cc-token") == JUNO_TOKEN


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    path = request.url.path
    public = ("/login", "/health", "/static")
    if APP_TOKEN and not any(path.startswith(p) for p in public) and not is_authed(request):
        if path.startswith("/api/") and is_juno(request):
            juno_forbidden = ("/api/bridge", "/api/duplicates", "/api/visibility", "/api/health-history")
            if request.method != "GET" and any(path.startswith(fp) for fp in juno_forbidden) and not (path == "/api/bridge/gsc" or path == "/api/bridge/drift"):
                return JSONResponse({"error": "juno-token: kun GET eller bridge-push"}, status_code=403)  # Juno-token har adgang til API-endpoints (inkl. bridge-push)
        elif path.startswith("/api/"):
            return JSONResponse({"error": "unauthorized"}, status_code=401)
        else:
            return RedirectResponse("/login", status_code=303)
    return await call_next(request)


@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request, "error": ""})


@app.post("/login")
async def login(request: Request):
    form = await request.form()
    token = (form.get("token") or "").strip()
    if APP_TOKEN and secrets.compare_digest(token, APP_TOKEN):
        resp = RedirectResponse("/", status_code=303)
        resp.set_cookie("cc_token", token, httponly=True, samesite="lax", max_age=60 * 60 * 24 * 30)
        return resp
    return templates.TemplateResponse("login.html", {"request": request, "error": "Forkert token"}, status_code=401)


@app.get("/logout")
async def logout():
    resp = RedirectResponse("/login", status_code=303)
    resp.delete_cookie("cc_token")
    return resp


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


HTTP = requests.Session()
_adapter = requests.adapters.HTTPAdapter(pool_connections=10, pool_maxsize=20)
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
        requests.post(
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
                host = urlparse(url).netloc
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
        res = check_domain_sync(d["url"])
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
    loop = asyncio.get_event_loop()
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
        r = requests.get(
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


@app.post("/seo/audit")
async def run_seo_audit(request: Request):
    form = await request.form()
    url = form.get("url", "")
    keyword = form.get("keyword", "")
    use_psi = form.get("psi", "") == "1"
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, analyze_page, url, keyword)
    result["url"] = url
    if use_psi:
        loop2 = asyncio.get_event_loop()
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
        with get_db() as db:
            db.execute("DELETE FROM seopages")
            db.execute("DELETE FROM crawl_runs")
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
                res = analyze_page(current, "", html=resp.text if resp.status_code == 200 else None,
                                   status_code=resp.status_code, ms=ms)
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
async def start_crawl(url: str = Form(...), max_pages: int = Form(30)):
    if CRAWL_STATE["running"]:
        return RedirectResponse("/", status_code=303)
    max_pages = max(5, min(int(max_pages or 30), 100))
    loop = asyncio.get_event_loop()
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
        rows = db.execute("SELECT url, redirects, http_status FROM seopages WHERE redirects != ''").fetchall()
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
    loop = asyncio.get_event_loop()
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


def generate_article_ai(keyword: str):
    prompt = (
        f"Write an SEO-optimized blog article draft in English about '{keyword}' for a steampunk "
        f"cosplay & merchandise webshop. Output raw HTML (h2/h3/p/ul/ol only, no <html> wrapper). "
        f"Include: engaging intro, 3-4 H2 sections, a bullet list, an FAQ section with 3 questions, "
        f"and a short conclusion. Around 600-900 words. No images. Natural, helpful tone."
    )
    resp = requests.post(
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
            loop = asyncio.get_event_loop()
            content = await loop.run_in_executor(executor, generate_article_ai, keyword)
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
    try:
        resp = requests.post(
            f"{WP_URL.rstrip('/')}/wp-json/wp/v2/posts",
            auth=(WP_USER, WP_APP_PASSWORD),
            json={"title": art["title"], "content": art["content"], "status": "draft"},
            timeout=30,
        )
        resp.raise_for_status()
        wp_id = resp.json().get("id")
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
    loop = asyncio.get_event_loop()
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


# ---------- Keywords (SerpAPI) ----------
def check_keyword_sync(kw_row):
    kw = kw_row["keyword"]
    if not SERPAPI_KEY:
        return {"position": None, "url": None, "error": "SERPAPI_KEY ikke sat i .env"}
    try:
        resp = requests.get(
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
        res = check_keyword_sync(kw)
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
    loop = asyncio.get_event_loop()
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
            (data.get("date", date.today().isoformat()), q.get("query", ""), q.get("clicks", ""),
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
    if not GITHUB_TOKEN:
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


def self_update_sync():
    try:
        headers = {"Authorization": "Bearer " + GITHUB_TOKEN, "Accept": "application/vnd.github.raw"}
        r = HTTP.get(f"https://api.github.com/repos/{GITHUB_REPO}/contents/install.sh", headers=headers, timeout=30)
        r.raise_for_status()
        script_path = os.path.join(os.path.dirname(BASE_DIR), "install.sh")
        with open(script_path, "w") as f:
            f.write(r.text)
        subprocess.Popen(["bash", script_path], cwd=os.path.dirname(script_path))
        return True
    except Exception as e:
        with get_db() as db:
            add_alarm(db, "self-update", "Selv-opdatering fejlede: " + str(e)[:120], "advarsel")
        return False


@app.post("/self-update")
async def self_update():
    if GITHUB_TOKEN:
        loop = asyncio.get_event_loop()
        loop.run_in_executor(executor, self_update_sync)
    return RedirectResponse("/", status_code=303)


# ---------- Duplicates & redirects rapport ----------
def duplicates_report():
    with get_db() as db:
        dup_titles = db.execute(
            "SELECT title, COUNT(*) AS n, GROUP_CONCAT(url, ' | ') AS urls FROM seopages "
            "WHERE title != '' GROUP BY LOWER(TRIM(title)) HAVING n > 1 ORDER BY n DESC LIMIT 20"
        ).fetchall()
        dup_h1 = db.execute(
            "SELECT h1, COUNT(*) AS n, GROUP_CONCAT(url, ' | ') AS urls FROM seopages "
            "WHERE h1 != '' GROUP BY LOWER(TRIM(h1)) HAVING n > 1 ORDER BY n DESC LIMIT 20"
        ).fetchall()
        dup_content = db.execute(
            "SELECT content_hash, COUNT(*) AS n, GROUP_CONCAT(url, ' | ') AS urls FROM seopages "
            "WHERE content_hash != '' GROUP BY content_hash HAVING n > 1 ORDER BY n DESC LIMIT 20"
        ).fetchall()
        redirects = db.execute(
            "SELECT url, redirects FROM seopages WHERE redirects != '' ORDER BY id LIMIT 50"
        ).fetchall()
    return {"titles": [dict(r) for r in dup_titles], "h1": [dict(r) for r in dup_h1],
            "content": [dict(r) for r in dup_content], "redirects": [dict(r) for r in redirects]}


@app.get("/api/duplicates")
async def get_duplicates():
    return JSONResponse(duplicates_report())


# ---------- AI: interne links, meta/social, synlighed ----------
def ai_chat(prompt: str, max_tokens: int = 1500):
    resp = requests.post(
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
        pages = db.execute("SELECT url, title, h1, words FROM seopages ORDER BY score DESC LIMIT 40").fetchall()
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
        loop = asyncio.get_event_loop()
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
    # hent eksisterende titel/meta fra seneste crawl, ellers hent live
    title = desc = ""
    with get_db() as db:
        row = db.execute("SELECT title, meta_len FROM seopages WHERE url=? ORDER BY id DESC LIMIT 1", (url,)).fetchone()
    if not row:
        try:
            r = safe_request(url, timeout=10)
            soup = BeautifulSoup(r.text, "html.parser")
            t = soup.find("title")
            title = t.get_text(strip=True) if t else ""
            m = soup.find("meta", attrs={"name": "description"})
            desc = m.get("content", "") if m else ""
        except Exception:
            pass
    else:
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
    loop = asyncio.get_event_loop()
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
        loop = asyncio.get_event_loop()
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
        loop = asyncio.get_event_loop()
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
    url = m["url"]
    try:
        resp = safe_request(url, timeout=10)
        if resp.status_code >= 400:
            return f"HTTP-fejl {resp.status_code}", False
        if m["type"] == "contains":
            ok = m["expected"] in resp.text
            return ("Fundet" if ok else "IKKE fundet: " + m["expected"][:50], ok)
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
                return "Ingen pris fundet paa siden", False
            prev = m["last_result"] or ""
            try:
                changed = abs(float(prev) - float(price)) > 0.001 if prev else False
            except Exception:
                changed = False
            if changed:
                add_alarm_sync_global(f"Prisaendring paa {url}: {prev} -> {price}")
            return f"Pris: {price}" + (f" (var {prev})" if changed else ""), True
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
            return (f"JSON-path '{m['expected']}' = {str(node)[:60]}", ok)
        return "Ukendt type", False
    except Exception as e:
        return f"Fejl: {str(e)[:120]}", False


def check_all_monitors_sync():
    with get_db() as db:
        monitors = db.execute("SELECT * FROM monitors").fetchall()
    for m in monitors:
        status, ok = run_monitor_sync(m)
        with get_db() as db:
            db.execute("UPDATE monitors SET last_status=?, last_result=?, last_checked=? WHERE id=?",
                       (status, status, now_iso(), m["id"]))
            if not ok:
                add_alarm(db, "monitor", f"{m['name']} ({m['url']}): {status}", "kritisk")


@app.post("/monitors/add")
async def add_monitor(name: str = Form(...), url: str = Form(...), type_: str = Form(...), expected: str = Form(...)):
    if name.strip() and url.strip() and expected.strip():
        with get_db() as db:
            db.execute("INSERT INTO monitors (name, url, type, expected) VALUES (?,?,?,?)",
                       (name.strip(), normalize_url(url), type_, expected.strip()))
    return RedirectResponse("/", status_code=303)


@app.post("/monitors/delete")
async def delete_monitor(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM monitors WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


@app.post("/monitors/check")
async def check_monitors():
    loop = asyncio.get_event_loop()
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
        r = requests.get(
            "https://suggestqueries.google.com/complete/search",
            params={"client": "firefox", "q": keyword, "hl": "en"},
            timeout=8,
        )
        for item in r.json()[1][:15]:
            ideas.append((item, "Google suggest"))
    except Exception:
        pass
    try:
        r2 = requests.get("https://duckduckgo.com/ac/", params={"q": keyword, "type": "list"}, timeout=8)
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
    loop = asyncio.get_event_loop()
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
        resp = requests.get(
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
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, keyword_difficulty_sync, keyword)
    if result.get("ok"):
        with get_db() as db2:
            add_alarm(db2, "keyword-difficulty", "Keyword '" + keyword + "': sværhedsgrad " + str(result["difficulty"]) + "/100 (" + result["label"] + ") — top: " + result["top_domains"][:80], "info")
    return RedirectResponse("/", status_code=303)


def serp_gap_sync(keyword: str):
    if not SERPAPI_KEY:
        return {"error": "SERPAPI_KEY ikke sat i .env"}
    try:
        resp = requests.get(
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
    loop = asyncio.get_event_loop()
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
        loop = asyncio.get_event_loop()
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
    loop = asyncio.get_event_loop()
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


# ---------- Dashboard ----------
@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    with get_db() as db:
        domains = db.execute("SELECT * FROM domains ORDER BY id DESC").fetchall()
        competitors = db.execute("SELECT * FROM competitors ORDER BY id DESC LIMIT 20").fetchall()
        articles = db.execute("SELECT * FROM articles ORDER BY id DESC LIMIT 10").fetchall()
        linkchecks = db.execute("SELECT * FROM linkcheck ORDER BY id DESC LIMIT 10").fetchall()
        socialqueue = db.execute("SELECT * FROM socialqueue ORDER BY id DESC").fetchall()
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
        seo_pages = db.execute("SELECT * FROM seopages ORDER BY score ASC LIMIT 100").fetchall()
        crawl = db.execute("SELECT * FROM crawl_runs ORDER BY id DESC LIMIT 1").fetchone()
        difficulties = db.execute("SELECT * FROM keyword_difficulty ORDER BY id DESC LIMIT 20").fetchall()
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
        "auth_required": bool(APP_TOKEN),
        "seo_pages": seo_pages,
        "monitors": monitors,
        "ideas": ideas,
        "gaps": gaps,
        "outreach_rows": outreach_rows,
        "ai_vis": ai_vis,
        "links_sug": links_sug,
        "health_hist_n": health_hist,
        "crawl": crawl,
        "track_domain": TRACK_DOMAIN,
        "difficulties": difficulties,
    })


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
    return {
        "status": "ok",
        "version": "7.3",
        "ai": bool(AIMLAPI_KEY),
        "wordpress": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "serpapi": bool(SERPAPI_KEY),
        "telegram": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
        "auth": bool(APP_TOKEN),
    }


# ---------- Scheduler ----------
async def job_check_domains():
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(executor, check_all_domains_sync)


async def job_check_keywords():
    if not SERPAPI_KEY:
        return
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(executor, check_all_keywords_sync)


@asynccontextmanager
async def lifespan(app_: FastAPI):
    scheduler.add_job(job_check_domains, IntervalTrigger(hours=6), id="domain_checks", replace_existing=True)
    scheduler.add_job(job_check_keywords, CronTrigger(hour=6, minute=0), id="keyword_checks", replace_existing=True)
    scheduler.add_job(cleanup_old_data, CronTrigger(hour=4, minute=30), id="cleanup", replace_existing=True)
    scheduler.add_job(pull_bridge_sync, IntervalTrigger(minutes=BRIDGE_POLL_MINUTES), id="pull_bridge", replace_existing=True)
    scheduler.start()
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
<body class="bg-zinc-950 text-zinc-100 min-h-screen font-sans" x-data="{ tab: 'cockpit', seoResult: null, seoLoading: false, crawl: null, histChart: null, dups: null, healthChart: null, diff: null, redir: null, rewrite: null }">
<header class="border-b border-zinc-800 bg-zinc-900/60 px-4 py-3">
    <div class="max-w-7xl mx-auto flex items-center justify-between">
        <div>
            <h1 class="font-bold text-sm">⚡ COMMAND CENTER <span class="text-emerald-400">v7.5 PRO</span></h1>
            <p class="text-xs text-zinc-500">WordPress, SEO, indhold & overvågning</p>
        </div>
        <div class="flex items-center gap-3">
            <form action="/self-update" method="POST" onsubmit="return confirm('Hent og installér nyeste version? Genstart run.sh bagefter.')"><button class="text-xs text-zinc-400 hover:text-emerald-400">⬆️ Opdatér</button></form>
            <a href="/health" class="text-xs text-emerald-400">Systemstatus</a>
            {% if auth_required %}<a href="/logout" class="text-xs text-zinc-500 hover:text-rose-400">Log ud</a>{% endif %}
        </div>
    </div>
</header>
<nav class="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-900/70 px-4 py-2 shadow-lg shadow-black/20">
    <div class="max-w-7xl mx-auto flex gap-2 overflow-x-auto">
        <button @click="tab='cockpit'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='cockpit' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🎛️ Cockpit</button>
        <button @click="tab='seo'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='seo' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🔍 SEO Scanner</button>
        <button @click="tab='spy'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='spy' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🕷️ SERP & Spy</button>
        <button @click="tab='articles'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='articles' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">✍️ Artikler</button>
        <button @click="tab='keywords'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='keywords' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🎯 Keywords</button>
        <button @click="tab='links'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='links' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🔗 Links</button>
        <button @click="tab='social'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='social' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📱 Social</button>
        <button @click="tab='ai'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='ai' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🤖 AI Tools</button>
        <button @click="tab='monitors'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='monitors' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🩺 Monitors</button>
        <button @click="tab='pro'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='pro' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">💼 Pro</button>
        <button @click="tab='alarms'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='alarms' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🚨 Alarmer{% if alarms %} ({{ alarms|length }}){% endif %}</button>
        <button @click="tab='notes'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='notes' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📝 Noter</button>
    </div>
</nav>
<main class="max-w-7xl mx-auto p-4 space-y-4">

    {% if not ai_enabled or not wp_enabled or not auth_required %}
    <div class="bg-amber-500/10 border border-amber-500/30 rounded-2xl p-3 text-xs text-amber-300">
        Setup: AI {{ '✅' if ai_enabled else '❌ (AIMLAPI_KEY)' }} · WordPress {{ '✅' if wp_enabled else '❌ (WP_URL/WP_USER/WP_APP_PASSWORD)' }} · SerpAPI {{ '✅' if serpapi_enabled else '❌ (SERPAPI_KEY)' }} · Telegram {{ '✅' if telegram_enabled else '— (valgfrit)' }} · Login {{ '✅' if auth_required else '❌ (APP_TOKEN — sæt den, hvis dashboardet kører på en VPS!)' }} — se .env.example
    </div>
    {% endif %}

    <!-- COCKPIT -->
    <section x-show="tab === 'cockpit'" class="space-y-4">
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
                        <button @click="tab='seo'; showHistory({{ domain.id }}, '{{ domain.url }}')" class="text-emerald-400 hover:underline">📈</button>
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
                    <div class="mt-1">🛒 Ordrer: <span class="font-bold">{{ d.orders }}</span> · ${(d.revenue or 0)|round(2)}</div>
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
                    body: 'url=' + encodeURIComponent($el.querySelector('input[name=url]').value) + '&keyword=' + encodeURIComponent($el.querySelector('input[name=keyword]').value || '') + '&psi=' + ($el.querySelector('input[name=psi]')?.checked ? '1' : '0') })
                .then(r => r.json()).then(data => { seoResult = data; seoLoading = false; })"
                class="flex flex-col md:flex-row gap-2">
                <input type="text" name="url" placeholder="https://steamgears.eu/guide..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <input type="text" name="keyword" placeholder="Focus keyword (valgfrit)" class="md:w-52 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
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
                <div class="text-sm font-bold px-3 py-1 rounded-xl border" :class="seoResult?.score >= 80 ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : seoResult?.score >= 50 ? 'bg-amber-500/10 text-amber-400 border-amber-500/30' : 'bg-rose-500/10 text-rose-400 border-rose-500/30'" x-text="seoResult?.score + ' / 100'"></div>
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
                <template x-for="item in seoResult?.items">
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
                <input type="number" name="max_pages" value="30" min="5" max="100" class="w-24 bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
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

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="false" id="histcard">
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
                        <a href="{{ comp.url }}" target="_blank" class="font-medium text-emerald-400 hover:underline">{{ comp.name }}</a>
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
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Generér artikel {{ '(AI: Gemini via aimlapi)' if ai_enabled else '(skabelon — sæt AIMLAPI_KEY for AI)' }}</h2>
            <form action="/articles/generate" method="POST" class="flex gap-2">
                <input type="text" name="keyword" placeholder="Emne / søgeord..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Generér</button>
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
                    <div class="text-zinc-400 max-h-48 overflow-y-auto border-t border-zinc-800 pt-2">{{ art.content | safe }}</div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen artikler oprettet endnu.</p>
                {% endfor %}
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
    </section>

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
                    </div>
                    <form action="/social/delete" method="POST">
                        <input type="hidden" name="id" value="{{ post.id }}">
                        <button class="text-zinc-500 hover:text-rose-400">✕</button>
                    </form>
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
    document.getElementById('histcard').style.display = '';
    document.getElementById('histtitle').textContent = 'Svartid-historik: ' + url;
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
<html lang="da" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Command Center — Login</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-zinc-950 text-zinc-100 min-h-screen font-sans flex items-center justify-center">
    <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-8 w-full max-w-sm space-y-4">
        <h1 class="font-bold text-lg">⚡ COMMAND CENTER</h1>
        <p class="text-xs text-zinc-400">Indtast din adgangstoken</p>
        {% if error %}<p class="text-xs text-rose-400">{{ error }}</p>{% endif %}
        <form action="/login" method="POST" class="space-y-3">
            <input type="password" name="token" required autofocus
                   class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
            <button class="w-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                Log ind
            </button>
        </form>
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
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt
echo "⚡ Starter Command Center v7.5..."
if [ "$DEV" = "1" ]; then
    uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
else
    uvicorn app.main:app --host 127.0.0.1 --port 8000
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
ExecStart=/home/%i/command-center/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_SERVICE

echo "📄 README.md..."
cat << 'EOF_README' > "$PROJECT_DIR/README.md"
# Command Center v7.5 PRO

Selv-hostet SEO- og drifts-center (FastAPI + SQLite) i stil med RankMath Pro / Yoast Premium — bygget til Steamgears.

## Funktioner
- 🎛️ **Cockpit** — domæneovervågning (uptime, svartid, SSL), daglig drift-kort (Woo/checkout via Juno-bro)
- 🔍 **SEO Scanner** — deep audit af enkelt side (20+ vægtede kontroller inkl. focus keyword, lesbarhed, mixed content, schema, OG/Twitter) + **site-crawl** med score per side og robots.txt/sitemap-tjek
- ✍️ **Artikler** — AI-generering (Gemini via aimlapi) eller skabelon, **push direkte til WordPress som udkast**
- 🎯 **Keywords** — Google-positioner via SerpAPI, tjekket automatisk daglig kl. 06:00
- 🕷️ **SERP & Spy** — konkurrent-opdagelse + crawl af titel/H1/beskrivelse
- 🔗 **Links** — ekstern linktjek med brodte-links-rapport
- 📱 **Social** — opslagskø med CSV-export
- 🚨 **Alarmer** — SSL-udlob, nedetid, brodte links, fejlede scans; valgfrit Telegram-push
- 📈 **Historik** — svartid-grafer pr. domæne (Chart.js)
- 🌉 **Juno-broer** — `POST /api/bridge/gsc` og `/api/bridge/drift` (header `X-CC-Token`) sa Juno kan pushe GSC-tal og daglig drift

## Installering
```bash
curl -H "Authorization: Bearer <TOKEN>" -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/humle93/command-center/contents/install.sh -o install.sh && bash install.sh
```

Eller med Docker: `cp .env.example .env && docker compose up -d --build`

## Opsaetning
1. `cp .env.example .env` og udfyld noegler
2. `./run.sh` → http://127.0.0.1:8000
3. (VPS) saet `APP_TOKEN` i `.env` og kør bag reverse proxy, eller brug `deploy/command-center.service` + SSH-tunnel

## v7.5 — performance & drift
- **Pull-bro**: Juno committer JSON-filer til repoets bridge/pending/, CC henter selv hver time (GITHUB_TOKEN i .env) — ingen tunnel eller FTP noedvendig
- **Selv-opdatering**: Opdater-knap i toppen henter nyeste install.sh og koerer den
- **SQLite**: WAL-mode, busy_timeout, 8 indekser, daglig oprydning kl. 04:30
- **HTTP**: connection-pooling og gzip-komprimering
- **UI**: sticky nav, preconnect, spinner, hover/focus-puds, mobile-forbedringer

## v7.4 PRO tilfoejelser
- **Crawl-diff** (Screaming Frog-stil): sammenlign to crawls — nye/fjernede sider, aendret indhold (hash), score-fald >10
- **Redirect-audit**: kæder (2+ hop), redirect-loops og usikre http-redirects fra crawleren
- **Sitemap-generator**: download sitemap.xml bygget fra seneste crawl (/api/sitemap.xml)
- **Keyword-svaerhedsgrad** (Ahrefs-kopi): heuristic over top 10 — autoritetsdomaener, unikke domaener, annoncer → 0-100 score
- **AI titel/meta-rewrite**: Gemini foreslar 3 titler + 3 meta descriptions direkte fra deep audit (klik for at kopiere)

## PRO-funktioner (betalt-varktoej-kloner)
- **Content Gap** (Semrush-kopi): top 10 SERP hentes via SerpAPI, gennemsnit af ord/H2 beregnes, og dine artikel-kladder scores mod markedet (Content Score)
- **Keyword-ideer** (Ubersuggest-kopi): Google + DuckDuckGo autocomplete, gratis
- **Email-finder** (Hunter.io-kopi): scan sider for kontakt-emails til linkbuilding-outreach
- **Pris-overvaagning**: monitors med typen "pris" laeser JSON-LD/product:price og alarmerer ved pris-andringer hos konkurrenter
- **Visibility Index** (SE Ranking-kopi): samlet synlighedstal ud fra dine keyword-positioner, graf over tid
- **Core Web Vitals**: valgfri Google PageSpeed API-noegle (PSI_API_KEY) giver perf/LCP/CLS i deep audit
- **Flesch-lesbarhed** (Hemingway-kopi) i hver side-audit

## Sikkerhed
- `APP_TOKEN` = login til hele UI'et og noeglen til Juno-broerne (header `X-CC-Token`)
- Default binding er 127.0.0.1 — saet aldrig `0.0.0.0` uden reverse proxy + auth
EOF_README

if [ -f "$PROJECT_DIR/.env" ]; then echo "✅ .env findes allerede - bruger den"; else cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"; echo "⚠ Opret .env (se .env.example) inden foerste start"; fi
cat << 'EOF_RUN' > "$PROJECT_DIR/run.sh"
#!/bin/bash
cd "$(dirname "$0")"
if [ -f .env ]; then
    set -a; source .env; set +a
fi
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt
echo "⚡ Starter Command Center v7.5..."
if [ "$DEV" = "1" ]; then
    uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
else
    uvicorn app.main:app --host 127.0.0.1 --port 8000
fi
EOF_RUN
chmod +x "$PROJECT_DIR/run.sh"
echo "✨ Installation klar! Sæt noegler i $PROJECT_DIR/.env og kør: cd ~/command-center && ./run.sh"

