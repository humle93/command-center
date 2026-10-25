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
EOF_ENVDOT

echo "📄 app/main.py..."
cat << 'EOF_MAIN' > "$PROJECT_DIR/app/main.py"
from fastapi import FastAPI, Request, Form, Header
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi import HTTPException
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

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "data", "center.db")
STATIC_DIR = os.path.join(BASE_DIR, "static")

# --- Konfiguration via miljoevariabler / .env ---
APP_TOKEN = os.environ.get("APP_TOKEN", "").strip()          # login-token (tom = ingen auth, lokal tilstand)
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

app = FastAPI(title="Command Center Engine", version="7.0")
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
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
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
        """)


init_db()


# ---------- Auth ----------
def is_authed(request: Request) -> bool:
    if not APP_TOKEN:
        return True
    return request.cookies.get("cc_token") == APP_TOKEN or request.headers.get("x-cc-token") == APP_TOKEN


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    path = request.url.path
    public = ("/login", "/health", "/static")
    if APP_TOKEN and not any(path.startswith(p) for p in public) and not is_authed(request):
        if path.startswith("/api/"):
            return JSONResponse({"error": "unauthorized"}, status_code=401)
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


def safe_request(url: str, timeout: int = 6):
    return requests.get(
        url,
        timeout=timeout,
        allow_redirects=True,
        headers={"User-Agent": "Mozilla/5.0 CommandCenter/7.0"},
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


@app.post("/seo/audit")
async def run_seo_audit(request: Request):
    form = await request.form()
    url = form.get("url", "")
    keyword = form.get("keyword", "")
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, analyze_page, url, keyword)
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
            with get_db() as db:
                db.execute(
                    "INSERT INTO seopages (run_id, url, http_status, title, meta_len, h1, words, score, issues, crawled_at) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?)",
                    (run_id, current, status, res.get("title", "")[:200], len(res.get("meta", "")),
                     res.get("h1", "")[:200], res.get("words", 0), res["score"],
                     "; ".join(issues[:8]), now_iso()),
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
        with get_db() as db:
            db.execute("UPDATE crawl_runs SET pages=?, avg_score=?, finished_at=? WHERE id=?",
                       (pages_saved, avg, now_iso(), run_id))
        CRAWL_STATE.update({"running": False, "avg": avg})
        return {"ok": True, "pages": pages_saved, "avg_score": avg, "robots_ok": robots_ok,
                "sitemap_ok": sitemap_ok, "sitemap_urls": sitemap_count}
    except Exception as e:
        CRAWL_STATE.update({"running": False, "error": str(e)[:200]})
        return {"ok": False, "error": str(e)[:200]}


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
@app.post("/api/bridge/gsc")
async def bridge_gsc(request: Request):
    data = await request.json()
    days = data.get("daily", [])
    queries = data.get("queries", [])
    if not isinstance(days, list):
        raise HTTPException(400, "daily skal vaere en liste")
    with get_db() as db:
        for d in days:
            db.execute(
                """INSERT INTO gsc_daily (day, clicks, impressions, ctr, avg_position)
                   VALUES (?,?,?,?,?)
                   ON CONFLICT(day) DO UPDATE SET clicks=excluded.clicks, impressions=excluded.impressions,
                   ctr=excluded.ctr, avg_position=excluded.avg_position""",
                (d.get("day"), d.get("clicks", 0), d.get("impressions", 0), d.get("ctr", 0), d.get("position", 0)),
            )
        for q in queries:
            db.execute(
                """INSERT INTO gsc_queries (day, query, clicks, impressions, position)
                   VALUES (?,?,?,?,?)
                   ON CONFLICT(day, query) DO UPDATE SET clicks=excluded.clicks,
                   impressions=excluded.impressions, position=excluded.position""",
                (data.get("date", date.today().isoformat()), q.get("query", ""), q.get("clicks", 0),
                 q.get("impressions", 0), q.get("position", 0)),
            )
    return {"ok": True, "days": len(days), "queries": len(queries)}


@app.post("/api/bridge/drift")
async def bridge_drift(request: Request):
    data = await request.json()
    with get_db() as db:
        db.execute(
            "INSERT INTO drift (checked_at, orders, revenue, woo_status, checkout_status, notes) VALUES (?,?,?,?,?,?)",
            (now_iso(), data.get("orders"), data.get("revenue"), data.get("woo_status", "ok"),
             data.get("checkout_status", "ok"), data.get("notes", "")),
        )
        if data.get("woo_status") not in (None, "ok", ""):
            add_alarm(db, "drift", f"Woo-status: {data.get('woo_status')}", "kritisk")
    return {"ok": True}


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
        seo_pages = db.execute("SELECT * FROM seopages ORDER BY score ASC LIMIT 100").fetchall()
        crawl = db.execute("SELECT * FROM crawl_runs ORDER BY id DESC LIMIT 1").fetchone()
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
        "crawl": crawl,
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
        "version": "7.1",
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
    scheduler.start()
    yield
    scheduler.shutdown()


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
</head>
<body class="bg-zinc-950 text-zinc-100 min-h-screen font-sans" x-data="{ tab: 'cockpit', seoResult: null, seoLoading: false, crawl: null, histChart: null }">
<header class="border-b border-zinc-800 bg-zinc-900/60 px-4 py-3">
    <div class="max-w-7xl mx-auto flex items-center justify-between">
        <div>
            <h1 class="font-bold text-sm">⚡ COMMAND CENTER <span class="text-emerald-400">v7.1</span></h1>
            <p class="text-xs text-zinc-400">WordPress, SEO, indhold & overvågning</p>
        </div>
        <div class="flex items-center gap-3">
            <a href="/health" class="text-xs text-emerald-400">Systemstatus</a>
            {% if auth_required %}<a href="/logout" class="text-xs text-zinc-500 hover:text-rose-400">Log ud</a>{% endif %}
        </div>
    </div>
</header>
<nav class="border-b border-zinc-800 bg-zinc-900/30 px-4 py-2">
    <div class="max-w-7xl mx-auto flex gap-2 overflow-x-auto">
        <button @click="tab='cockpit'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='cockpit' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🎛️ Cockpit</button>
        <button @click="tab='seo'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='seo' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🔍 SEO Scanner</button>
        <button @click="tab='spy'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='spy' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🕷️ SERP & Spy</button>
        <button @click="tab='articles'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='articles' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">✍️ Artikler</button>
        <button @click="tab='keywords'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='keywords' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🎯 Keywords</button>
        <button @click="tab='links'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='links' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🔗 Links</button>
        <button @click="tab='social'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='social' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📱 Social</button>
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
                    body: 'url=' + encodeURIComponent($el.querySelector('input[name=url]').value) + '&keyword=' + encodeURIComponent($el.querySelector('input[name=keyword]').value || '') })
                .then(r => r.json()).then(data => { seoResult = data; seoLoading = false; })"
                class="flex flex-col md:flex-row gap-2">
                <input type="text" name="url" placeholder="https://steamgears.eu/guide..." required class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <input type="text" name="keyword" placeholder="Focus keyword (valgfrit)" class="md:w-64 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Analysér</button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="seoLoading" style="display: none;">
            <p class="text-xs text-zinc-400">Analyserer side (20+ kontroller)...</p>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="seoResult" style="display: none;">
            <div class="flex items-center justify-between mb-4">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Resultat</h2>
                <div class="text-sm font-bold px-3 py-1 rounded-xl border" :class="seoResult?.score >= 80 ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : seoResult?.score >= 50 ? 'bg-amber-500/10 text-amber-400 border-amber-500/30' : 'bg-rose-500/10 text-rose-400 border-rose-500/30'" x-text="seoResult?.score + ' / 100'"></div>
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
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Keyword-positioner (SerpAPI, dagligt kl. 06:00) — sporer: {{ 'steamgears.eu' }}</h2>
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
echo "⚡ Starter Command Center v7.1..."
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
# Command Center v7.1

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
echo "⚡ Starter Command Center v7.1..."
if [ "$DEV" = "1" ]; then
    uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
else
    uvicorn app.main:app --host 127.0.0.1 --port 8000
fi
EOF_RUN
chmod +x "$PROJECT_DIR/run.sh"
echo "✨ Installation klar! Sæt noegler i $PROJECT_DIR/.env og kør: cd ~/command-center && ./run.sh"

