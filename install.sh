#!/bin/bash
set -e
PROJECT_DIR="$HOME/command-center"
echo "⚡ Opretter mappestruktur i $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR/app/templates"
mkdir -p "$PROJECT_DIR/app/static"
mkdir -p "$PROJECT_DIR/app/data"
cd "$PROJECT_DIR"
echo "📄 Opretter requirements.txt..."
cat << 'EOF_REQ' > requirements.txt
fastapi==0.115.6
uvicorn[standard]==0.34.0
requests==2.32.3
beautifulsoup4==4.12.3
Jinja2==3.1.5
EOF_REQ
echo "🐍 Opretter app/main.py..."
cat << 'EOF_MAIN' > app/main.py
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from contextlib import contextmanager
from urllib.parse import urlparse
from datetime import datetime, timezone
from bs4 import BeautifulSoup
import os
import sqlite3
import requests
import ssl
import socket
import urllib.parse
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "data", "center.db")
app = FastAPI(title="Command Center Engine", version="6.0")
app.mount("/static", StaticFiles(directory=os.path.join(BASE_DIR, "static")), name="static")
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))
@contextmanager
def get_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
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
            last_checked TEXT
        );
        CREATE TABLE IF NOT EXISTS competitors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            crawled_info TEXT DEFAULT 'Ikke scannet endnu',
            status TEXT DEFAULT 'Aktiv'
        );
        CREATE TABLE IF NOT EXISTS articles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            keyword TEXT,
            content TEXT,
            status TEXT DEFAULT 'Kladde'
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
            status TEXT DEFAULT 'Klar i kø'
        );
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT,
            created_at TEXT
        );
        """)
init_db()
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
        headers={"User-Agent": "Mozilla/5.0 CommandCenter/6.0"}
    )
def check_domain(url: str):
    try:
        url = normalize_url(url)
        start = datetime.now()
        response = safe_request(url, timeout=5)
        duration = int((datetime.now() - start).total_seconds() * 1000)
        status = "Oppe" if response.status_code < 400 else f"Fejl ({response.status_code})"
        ssl_days = "-"
        if url.startswith("https://"):
            try:
                host = urlparse(url).netloc
                context = ssl.create_default_context()
                with socket.create_connection((host, 443), timeout=3) as sock:
                    with context.wrap_socket(sock, server_hostname=host) as ssock:
                        cert = ssock.getpeercert()
                        expiry = datetime.fromtimestamp(
                            ssl.cert_time_to_seconds(cert["notAfter"]),
                            tz=timezone.utc
                        )
                        days = (expiry - datetime.now(timezone.utc)).days
                        ssl_days = f"{days} dage"
            except Exception:
                ssl_days = "Ukendt"
        return status, f"{duration} ms", ssl_days
    except Exception:
        return "Nede / Timeout", "-", "-"
def audit_seo(url: str):
    try:
        url = normalize_url(url)
        response = safe_request(url)
        if response.status_code != 200:
            return {
                "score": 0,
                "items": [{"ok": False, "text": f"HTTP-fejl: {response.status_code}"}]
            }
        soup = BeautifulSoup(response.text, "html.parser")
        title = soup.find("title")
        description = soup.find("meta", attrs={"name": "description"})
        viewport = soup.find("meta", attrs={"name": "viewport"})
        schema = soup.find("script", attrs={"type": "application/ld+json"})
        h1 = soup.find("h1")
        images = soup.find_all("img")
        images_without_alt = [img for img in images if not img.get("alt")]
        checks = [
            ("Titel", bool(title and title.get_text(strip=True))),
            ("Meta description", bool(description and description.get("content", "").strip())),
            ("Viewport", bool(viewport)),
            ("JSON-LD schema", bool(schema)),
            ("H1-overskrift", bool(h1)),
            ("Billeder har alt-tekst", len(images_without_alt) == 0),
        ]
        score = round(sum(1 for _, ok in checks if ok) / len(checks) * 100)
        return {
            "score": score,
            "items": [{"ok": ok, "text": text} for text, ok in checks]
        }
    except Exception as e:
        return {
            "score": 0,
            "items": [{"ok": False, "text": f"Fejl: {e}"}]
        }
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
        return (
            f"Titel: {title[:80]} | "
            f"H1: {h1_text[:60]} | "
            f"Beskrivelse: {description[:100]}"
        )
    except Exception as e:
        return f"Fejl: {e}"
def check_links(url: str):
    try:
        url = normalize_url(url)
        response = safe_request(url)
        soup = BeautifulSoup(response.text, "html.parser")
        links = [a["href"] for a in soup.find_all("a", href=True)]
        external = [link for link in links if link.startswith("http")]
        checked = 0
        broken = 0
        for link in external[:25]:
            checked += 1
            try:
                result = safe_request(link, timeout=5)
                if result.status_code >= 400:
                    broken += 1
            except Exception:
                broken += 1
        return {
            "total": len(links),
            "external": len(external),
            "checked": checked,
            "broken": broken
        }
    except Exception as e:
        return {"error": str(e)}
def generate_article(keyword: str):
    keyword = keyword.strip()
    title = f"Guide: {keyword} i 2027"
    content = f"""
<h2>Hvad er {keyword}?</h2>
<p>{keyword} er et emne, hvor god struktur, klar information og brugervenligt indhold gør en stor forskel.</p>
<h3>Hvorfor er {keyword} vigtigt?</h3>
<ul>
<li>Det hjælper besøgende med hurtigt at finde relevant information.</li>
<li>Godt struktureret indhold understøtter søgemaskineforståelse.</li>
<li>En klar sideoplevelse kan forbedre konverteringer og engagement.</li>
</ul>
<h3>Sådan kommer du i gang</h3>
<ol>
<li>Definér målgruppen og deres behov.</li>
<li>Lav en klar side med overskrifter, korte afsnit og relevante links.</li>
<li>Tilføj FAQ, interne links og relevant struktureret data.</li>
</ol>
<h3>Konklusion</h3>
<p>Med fokus på kvalitet, struktur og brugerbehov kan indhold om {keyword} skabe langtidsholdbar værdi.</p>
"""
    return title, content
@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    with get_db() as db:
        domains = db.execute("SELECT * FROM domains ORDER BY id DESC").fetchall()
        competitors = db.execute("SELECT * FROM competitors ORDER BY id DESC").fetchall()
        articles = db.execute("SELECT * FROM articles ORDER BY id DESC").fetchall()
        linkchecks = db.execute("SELECT * FROM linkcheck ORDER BY id DESC LIMIT 10").fetchall()
        socialqueue = db.execute("SELECT * FROM socialqueue ORDER BY id DESC").fetchall()
        notes = db.execute("SELECT * FROM notes ORDER BY id DESC LIMIT 10").fetchall()
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "domains": domains,
        "competitors": competitors,
        "articles": articles,
        "linkchecks": linkchecks,
        "socialqueue": socialqueue,
        "notes": notes
    })
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
        db.execute("DELETE FROM domains WHERE id = ?", (id,))
    return RedirectResponse("/", status_code=303)
@app.get("/domains/check")
async def check_all_domains():
    with get_db() as db:
        domains = db.execute("SELECT * FROM domains").fetchall()
        for domain in domains:
            status, response_time, ssl_days = check_domain(domain["url"])
            db.execute("""
                UPDATE domains
                SET status = ?, response_time = ?, ssl_days = ?, last_checked = ?
                WHERE id = ?
            """, (
                status,
                response_time,
                ssl_days,
                datetime.now().isoformat(),
                domain["id"]
            ))
    return RedirectResponse("/", status_code=303)
@app.post("/serp/discover")
async def discover_competitors(keyword: str = Form(...)):
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    try:
        query = urllib.parse.quote_plus(keyword)
        search_url = f"https://html.duckduckgo.com/html/?q={query}"
        response = safe_request(search_url, timeout=8)
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
        with get_db() as db:
            for domain, url in found:
                info = crawl_competitor(url)
                db.execute(
                    "INSERT INTO competitors (name, url, crawled_info) VALUES (?, ?, ?)",
                    (domain, url, info)
                )
    except Exception:
        pass
    return RedirectResponse("/", status_code=303)
@app.post("/competitors/delete")
async def delete_competitor(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM competitors WHERE id = ?", (id,))
    return RedirectResponse("/", status_code=303)
@app.post("/articles/generate")
async def create_article(keyword: str = Form(...)):
    keyword = keyword.strip()
    if keyword:
        title, content = generate_article(keyword)
        with get_db() as db:
            db.execute(
                "INSERT INTO articles (title, keyword, content) VALUES (?, ?, ?)",
                (title, keyword, content)
            )
    return RedirectResponse("/", status_code=303)
@app.post("/links/check")
async def check_page_links(url: str = Form(...)):
    result = check_links(url)
    if "error" in result:
        text = f"Fejl: {result['error']}"
    else:
        text = (
            f"Fandt {result['total']} links. "
            f"Eksterne: {result['external']}. "
            f"Tjekkede: {result['checked']}. "
            f"Brudte/muligt fejlende: {result['broken']}."
        )
    with get_db() as db:
        db.execute(
            "INSERT INTO linkcheck (url, result, checked_at) VALUES (?, ?, ?)",
            (url, text, datetime.now().isoformat())
        )
    return RedirectResponse("/", status_code=303)
@app.post("/social/add")
async def add_social_post(platform: str = Form(...), message: str = Form(...)):
    if platform.strip() and message.strip():
        with get_db() as db:
            db.execute(
                "INSERT INTO socialqueue (platform, message) VALUES (?, ?)",
                (platform.strip(), message.strip())
            )
    return RedirectResponse("/", status_code=303)
@app.post("/social/delete")
async def delete_social_post(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM socialqueue WHERE id = ?", (id,))
    return RedirectResponse("/", status_code=303)
@app.post("/seo/audit")
async def run_seo_audit(url: str = Form(...)):
    result = audit_seo(url)
    return JSONResponse(result)
@app.post("/notes/add")
async def add_note(content: str = Form(...)):
    if content.strip():
        with get_db() as db:
            db.execute(
                "INSERT INTO notes (content, created_at) VALUES (?, ?)",
                (content.strip(), datetime.now().isoformat())
            )
    return RedirectResponse("/", status_code=303)
@app.post("/notes/delete")
async def delete_note(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM notes WHERE id = ?", (id,))
    return RedirectResponse("/", status_code=303)
@app.get("/health")
async def health():
    return {"status": "ok", "version": "6.0"}
EOF_MAIN
echo "🎨 Opretter app/templates/dashboard.html..."
cat << 'EOF_HTML' > app/templates/dashboard.html
<!DOCTYPE html>
<html lang="da" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Command Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
</head>
<body class="bg-zinc-950 text-zinc-100 min-h-screen font-sans" x-data="{ tab: 'cockpit' }">
<header class="border-b border-zinc-800 bg-zinc-900/60 px-4 py-3">
    <div class="max-w-7xl mx-auto flex items-center justify-between">
        <div>
            <h1 class="font-bold text-sm">⚡ COMMAND CENTER</h1>
            <p class="text-xs text-zinc-400">WordPress, SEO og indhold</p>
        </div>
        <a href="/health" class="text-xs text-emerald-400">Systemstatus</a>
    </div>
</header>
<nav class="border-b border-zinc-800 bg-zinc-900/30 px-4 py-2">
    <div class="max-w-7xl mx-auto flex gap-2 overflow-x-auto">
        <button @click="tab='cockpit'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='cockpit' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🎛️ Cockpit</button>
        <button @click="tab='spy'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='spy' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🕷️ SERP & Spy</button>
        <button @click="tab='articles'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='articles' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">✍️ Artikler</button>
        <button @click="tab='links'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='links' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">🔗 Links</button>
        <button @click="tab='social'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='social' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📱 Social</button>
        <button @click="tab='seo'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='seo' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📈 SEO</button>
        <button @click="tab='notes'" class="px-3 py-1.5 rounded-lg text-xs border" :class="tab==='notes' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' : 'text-zinc-400 border-transparent'">📝 Noter</button>
    </div>
</nav>
<main class="max-w-7xl mx-auto p-4 space-y-4">
    <!-- COCKPIT -->
    <section x-show="tab === 'cockpit'" class="space-y-4">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Tilføj domæne</h2>
            <form action="/domains/add" method="POST" class="flex gap-2">
                <input type="text" name="url" placeholder="ditsite.dk" required
                       class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                    Tilføj
                </button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Overvågede domæner</h2>
                <a href="/domains/check" class="text-xs text-emerald-400">🔄 Kør tjek</a>
            </div>
            <div class="space-y-2">
                {% for domain in domains %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 flex justify-between items-center text-xs">
                    <div>
                        <div class="font-medium">{{ domain.url }}</div>
                        <div class="text-zinc-500">
                            {{ domain.status }} • {{ domain.response_time }} • SSL: {{ domain.ssl_days }}
                        </div>
                    </div>
                    <form action="/domains/delete" method="POST">
                        <input type="hidden" name="id" value="{{ domain.id }}">
                        <button class="text-zinc-500 hover:text-rose-400">✕</button>
                    </form>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen domæner tilføjet endnu.</p>
                {% endfor %}
            </div>
        </div>
    </section>
    <!-- SPY -->
    <section x-show="tab === 'spy'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Opdag konkurrenter (SERP)</h2>
            <form action="/serp/discover" method="POST" class="flex gap-2">
                <input type="text" name="keyword" placeholder="Søgeord / emne..." required
                       class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                    Søg & Scan
                </button>
            </form>
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
    <!-- ARTICLES -->
    <section x-show="tab === 'articles'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Generér AI-artikel</h2>
            <form action="/articles/generate" method="POST" class="flex gap-2">
                <input type="text" name="keyword" placeholder="Emne / søgeord..." required
                       class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                    Generér
                </button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Artikler</h2>
            <div class="space-y-3">
                {% for art in articles %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-4 text-xs space-y-2">
                    <div class="font-bold text-sm">{{ art.title }}</div>
                    <div class="text-zinc-400 prose prose-invert max-none border-t border-zinc-800 pt-2">
                        {{ art.content | safe }}
                    </div>
                </div>
                {% else %}
                <p class="text-xs text-zinc-500">Ingen artikler oprettet endnu.</p>
                {% endfor %}
            </div>
        </div>
    </section>
    <!-- LINKS -->
    <section x-show="tab === 'links'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Tjek link-struktur</h2>
            <form action="/links/check" method="POST" class="flex gap-2">
                <input type="text" name="url" placeholder="https://eksempel.dk" required
                       class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                    Tjek links
                </button>
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
                <input type="text" name="platform" placeholder="Platform (f.eks. LinkedIn, X)" required
                       class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <textarea name="message" placeholder="Opslagets tekst..." rows="3" required
                          class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm"></textarea>
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                    Tilføj til kø
                </button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Opslagskø</h2>
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
    <!-- SEO -->
    <section x-show="tab === 'seo'" class="space-y-4" style="display: none;" x-data="{ seoResult: null, loading: false }">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Kør SEO Audit</h2>
            <form @submit.prevent="
                loading = true;
                fetch('/seo/audit', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                    body: 'url=' + encodeURIComponent($el.querySelector('input[name=url]').value)
                })
                .then(r => r.json())
                .then(data => { seoResult = data; loading = false; })
            " class="flex gap-2">
                <input type="text" name="url" placeholder="https://eksempel.dk" required
                       class="flex-1 bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                    Analyser
                </button>
            </form>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="loading">
            <p class="text-xs text-zinc-400">Analyserer side...</p>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5" x-show="seoResult" style="display: none;">
            <div class="flex items-center justify-between mb-4">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400">Resultat</h2>
                <div class="text-sm font-bold px-3 py-1 rounded-xl bg-emerald-500/10 text-emerald-400 border border-emerald-500/30" x-text="seoResult?.score + '%'"></div>
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
    </section>
    <!-- NOTES -->
    <section x-show="tab === 'notes'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Ny note</h2>
            <form action="/notes/add" method="POST" class="space-y-3">
                <textarea name="content" placeholder="Skriv en hurtig note..." rows="3" required
                          class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm"></textarea>
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">
                    Gem note
                </button>
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
</body>
</html>
EOF_HTML
mkdir -p ~/command-center
mv install.sh ~/command-center/
cd ~/command-center
cat << 'EOF_RUN' > run.sh
#!/bin/bash
cd "$(dirname "$0")"
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt
echo "⚡ Starter Command Center v6.0..."
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
EOF_RUN
chmod +x run.sh
echo "✨ Installation klar! Starter..."
exec ./run.sh
EOF
