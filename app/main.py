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
import json as jsonlib
import subprocess
import sys

# --- Funktioner flyttet ud (v8.0 M4). Gen-eksporteres, saa app.main er uaendret. ---
from app.core import (
    AI_KEY, AI_KEY_ENV, AI_MODEL, AI_PROVIDER, API_BUDGETS, APP_TOKEN,
    get_ai_model,
    APP_VERSION, BASE_DIR, BRIDGE_POLL_MINUTES, BudgetAdapter,
    BudgetExceeded, DB_PATH, GITHUB_REPO, GITHUB_TOKEN,
    HTTP, JUNO_TOKEN, LINKCHECK_LIMIT, MODULES,
    PSI_API_KEY, SCHEMA_VERSION, SERPAPI_KEY, SSL_WARN_DAYS,
    STATIC_DIR, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, TRACK_DOMAIN,
    WP_APP_PASSWORD, WP_URL, WP_USER, _MODULE_CACHE,
    _WAL_SET, _adapter, _safe, cleanup_old_data,
    ai_chat, create_indexes, get_db, init_db, init_schema,
    load_dotenv, migrate_db, module_on, modules_state,
    normalize_url, now_iso, report_schema_version, safe_request,
    schema_version, set_module, stamp_schema_version,
)
from app.services.alarms import add_alarm, notify_telegram
from app.services.budget import budget_service, budget_spend, budget_usage
from app.services.wp import (
    SGAP_ALIASES, SGAP_CHANNELS, sgap_api, sgap_channel,
    sgap_error_text, sgap_ready, sgap_snapshot, sgap_sync,
    wp_push_draft,
)
from app.services.content import (
    DEFAULT_STRATEGY, EMAIL_RE, QUALITY_MIN_WORDS, STRATEGIES,
    TEMPLATE_ARTICLE, autopilot_sync, classify_site, generate_article_ai,
    get_active_strategy, prospect_sync, quality_check, serp_competitor_context,
)
from app.services.audit import (
    CRAWL_STATE, _check, analyze_page, check_links_sync,
    crawl_competitor, deep_extras, discover_competitors_sync, psi_fetch,
    site_crawl_sync,
)


app = FastAPI(title="Command Center Engine", version=APP_VERSION)
# Git does not keep empty folders, so a fresh clone has no app/static: create it or startup fails.
os.makedirs(STATIC_DIR, exist_ok=True)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))
scheduler = AsyncIOScheduler(timezone="Europe/Copenhagen")
executor = ThreadPoolExecutor(max_workers=8)


_safe(init_schema)
_safe(report_schema_version)


# ---------- Auth ----------
SESSION_COOKIE = "cc_sid"   # v8.0: cookien indeholder et session-id, ikke selve APP_TOKEN
SESSION_DAYS = 30


def _hash_session(sid: str) -> str:
    """Session-id gemmes kun som SHA-256 — en laekket database giver ikke gyldige cookies."""
    return hashlib.sha256(sid.encode("utf-8")).hexdigest()


def create_session(ip: str = "") -> str:
    """Opret en session og returnér det id, der skal i cookien."""
    sid = secrets.token_urlsafe(32)
    expires = (datetime.now() + timedelta(days=SESSION_DAYS)).isoformat(timespec="seconds")
    with get_db() as db:
        db.execute("DELETE FROM auth_sessions WHERE expires_at < ?", (now_iso(),))
        db.execute(
            "INSERT INTO auth_sessions (sid_hash, created_at, expires_at, ip) VALUES (?, ?, ?, ?)",
            (_hash_session(sid), now_iso(), expires, ip[:64]),
        )
    return sid


def session_valid(sid: str) -> bool:
    if not sid:
        return False
    try:
        with get_db() as db:
            row = db.execute(
                "SELECT 1 FROM auth_sessions WHERE sid_hash = ? AND expires_at > ?",
                (_hash_session(sid), now_iso()),
            ).fetchone()
        return row is not None
    except Exception:
        return False  # auth fejler lukket, ikke aabent


def is_authed(request: Request) -> bool:
    if not APP_TOKEN:
        return True
    # Scripts/curl bruger den raa token i headeren; browseren bruger et session-id i cookien.
    # Constant-time comparison so the token cannot be guessed from response timing.
    supplied = request.headers.get("x-cc-token") or ""
    if supplied and secrets.compare_digest(supplied, APP_TOKEN):
        return True
    return session_valid(request.cookies.get(SESSION_COOKIE) or "")


def _cookie_secure(request: Request) -> bool:
    """Secure-flag paa cookien naar forbindelsen er HTTPS.

    Bevidst ikke ubetinget: run.sh koerer http://127.0.0.1, og en Secure-cookie bliver
    ikke sendt tilbage over ren HTTP — login ville loope. Terminerer en reverse proxy
    TLS, staar det i X-Forwarded-Proto.
    """
    proto = (request.headers.get("x-forwarded-proto") or request.url.scheme or "")
    return proto.split(",")[0].strip().lower() == "https"


def is_juno(request: Request) -> bool:
    """Juno-adgang: separat token, gyldig KUN for /api/*-endpoints (laese-data + bridge-push)."""
    return bool(JUNO_TOKEN) and request.headers.get("x-cc-token") == JUNO_TOKEN


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    path = request.url.path
    request.state.insecure = (request.headers.get("x-forwarded-proto", "https") == "http" and (request.client.host if request.client else "") not in ("127.0.0.1", "::1"))
    public = ("/login", "/landing", "/health", "/static")
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


@app.get("/landing", response_class=HTMLResponse)
async def landing_page(request: Request):
    return templates.TemplateResponse("landing.html", {"request": request})


@app.post("/login")
async def login(request: Request):
    ip = request.client.host if request.client else "ukendt"
    now = time.time()
    fails, locked_until = _LOGIN_FAILS.get(ip, (0, 0.0))
    if locked_until > now:
        return templates.TemplateResponse("login.html", {"request": request, "error": "For mange fejlede login - proev igen om " + str(int(locked_until - now)) + " sek."}, status_code=429)
    form = await request.form()
    token = (form.get("token") or "").strip()
    if APP_TOKEN and secrets.compare_digest(token, APP_TOKEN):
        try:
            sid = create_session(ip)
        except Exception as exc:
            print("[cc] kunne ikke oprette session:", repr(exc), flush=True)
            return templates.TemplateResponse(
                "login.html",
                {"request": request, "error": "Kunne ikke oprette session - se serverlog"},
                status_code=500,
            )
        resp = RedirectResponse("/", status_code=303)
        resp.set_cookie(
            SESSION_COOKIE, sid, httponly=True, samesite="lax",
            secure=_cookie_secure(request), max_age=60 * 60 * 24 * SESSION_DAYS,
        )
        resp.delete_cookie("cc_token")  # v8.0: den raa token skal ikke ligge i browseren
        _LOGIN_FAILS.pop(ip, None)
        return resp
    fails += 1
    if fails >= 5:
        _LOGIN_FAILS[ip] = (0, now + 600)  # 5 fejl = 10 min laas
    else:
        _LOGIN_FAILS[ip] = (fails, locked_until)
    return templates.TemplateResponse("login.html", {"request": request, "error": "Forkert token"}, status_code=401)


@app.post("/logout")
async def logout(request: Request):
    """Log ud: sletter sessionen i DB og cookien. POST, saa et link ikke kan logge dig ud."""
    sid = request.cookies.get(SESSION_COOKIE) or ""
    if sid:
        try:
            with get_db() as db:
                db.execute("DELETE FROM auth_sessions WHERE sid_hash = ?", (_hash_session(sid),))
        except Exception:
            pass
    resp = RedirectResponse("/login", status_code=303)
    resp.delete_cookie(SESSION_COOKIE)
    resp.delete_cookie("cc_token")
    return resp


_LOGIN_FAILS: dict = {}  # v7.9: IP -> (antal fejl, laas-til)


# ---------- Hjaelpere ----------


# ---------- API-budget (v8-plan): maanedligt loft for betalte API'er ----------
# Taeller hvert kald til SerpAPI og AI (aimlapi) pr. kalendermaaned og stopper dem ved loftet,
# saa en loekke eller fejl aldrig kan braende kreditter af. 0 = intet loft.


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


@app.post("/seo/audit")
async def run_seo_audit(request: Request):
    form = await request.form()
    url = form.get("url", "")
    keyword = form.get("keyword", "")
    use_psi = form.get("psi", "") == "1"
    level = form.get("level", "standard")
    loop = asyncio.get_event_loop()
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
        loop2 = asyncio.get_event_loop()
        psi = await loop2.run_in_executor(executor, psi_fetch, url)
        if psi:
            result["psi"] = psi
    return JSONResponse(result)


# ---------- SEO: site-crawler ----------


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


@app.post("/serp/discover")
async def discover(keyword: str = Form(...)):
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(executor, discover_competitors_sync, keyword)
    return RedirectResponse("/", status_code=303)


@app.post("/competitors/delete")
async def delete_competitor(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM competitors WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


# ---------- Artikler (AI + WordPress) ----------


# ---------- SEO-strategier (v7.8) ----------


@app.post("/articles/generate")
async def create_article(keyword: str = Form(...)):
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/", status_code=303)
    source = "skabelon"
    title = f"Guide: {keyword} i 2027"
    content = TEMPLATE_ARTICLE.format(keyword=keyword)
    err = None
    if AI_KEY:
        try:
            loop = asyncio.get_event_loop()
            st_active = get_active_strategy()
            content = await loop.run_in_executor(executor, generate_article_ai, keyword, st_active)
            title = f"Guide: {keyword}"
            source = f"AI ({get_ai_model()})"
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


# ---------- Growth Pack (v7.7): autopilot + backlink-prospector ----------


async def run_autopilot():
    loop = asyncio.get_event_loop()
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


@app.post("/backlinks/prospect")
async def backlink_prospect(keyword: str = Form(...)):
    keyword = keyword.strip()
    if keyword:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(executor, prospect_sync, keyword)
    return RedirectResponse("/", status_code=303)


@app.post("/backlinks/delete")
async def backlink_delete(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM backlink_prospects WHERE id=?", (id,))
    return RedirectResponse("/", status_code=303)


# ---------- Linktjek ----------


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


# ---------- Steamgears Autopilot-bro (WordPress-pluginnet steamgears-autopilot >= 7.5) ----------
# CC kalder pluginnets REST-API (/wp-json/sgap/v1) med samme WP_USER/WP_APP_PASSWORD som WordPress-push.
# Retningen er altid CC -> site: sitet kan ikke naa CC, der kun lytter paa 127.0.0.1.


async def job_sgap_sync():
    if not sgap_ready():
        return
    await asyncio.get_event_loop().run_in_executor(executor, sgap_sync)


@app.post("/autopilot/sync")
async def autopilot_sync_now():
    await asyncio.get_event_loop().run_in_executor(executor, sgap_sync)
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
        result = await asyncio.get_event_loop().run_in_executor(executor, send)
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
    if APP_TOKEN and not AI_KEY:
        fejl.append(f"{AI_KEY_ENV} mangler - AI-artikler vil fejle")
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
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(executor, backup_db_sync)


def self_update_sync():
    try:
        if sys.platform.startswith("win"):
            # v7.9: self-update bruger bash-installeren (Linux/macOS). Paa Windows: opdater manuelt.
            with get_db() as db:
                add_alarm(db, "self-update", "Self-update er ikke understoettet paa Windows endnu - opdater manuelt via git pull eller ny install.sh", "advarsel")
            return False
        backup_db_sync(tag="pre-update")  # rollback-punkt foer nye filer skrives
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
@app.post("/seo/linksuggest")
async def suggest_internal_links():
    if not AI_KEY:
        return JSONResponse({"ok": False, "error": f"{AI_KEY_ENV} ikke sat"})
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
    if not AI_KEY:
        return {"error": f"{AI_KEY_ENV} ikke sat"}
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
    if not AI_KEY:
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
    if not AI_KEY:
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
        seo_pages = db.execute("SELECT * FROM seopages ORDER BY score ASC LIMIT 100").fetchall()
        crawl = db.execute("SELECT * FROM crawl_runs ORDER BY id DESC LIMIT 1").fetchone()
        difficulties = db.execute("SELECT * FROM keyword_difficulty ORDER BY created_at DESC LIMIT 20").fetchall()
        # Read here, while the connection is open (get_db closes it when the block ends).
        backlink_rows = db.execute("SELECT * FROM backlink_prospects ORDER BY id DESC LIMIT 30").fetchall()
        strategy_row = db.execute("SELECT value FROM settings WHERE key='active_strategy'").fetchone()
        check_row = db.execute("SELECT value FROM settings WHERE key='strategy_check'").fetchone()
        sgap_row = db.execute("SELECT value FROM settings WHERE key='sgap_snapshot'").fetchone()
    active_key = (strategy_row["value"] if strategy_row else None) or DEFAULT_STRATEGY
    if active_key not in STRATEGIES:
        active_key = DEFAULT_STRATEGY
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
        "ai_enabled": bool(AI_KEY),
        "ai_provider": AI_PROVIDER,
        "ai_model": get_ai_model(),
        "wp_enabled": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "serpapi_enabled": bool(SERPAPI_KEY),
        "telegram_enabled": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
        "auth_required": bool(APP_TOKEN),
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
        add(bool(AI_KEY), f"{AI_KEY_ENV} (AI-outreach-drafts): " + ("OK" if AI_KEY else "mangler - drafts skrives manuelt"))
    else:
        add(bool(AI_KEY), f"{AI_KEY_ENV} (AI-artikler): " + ("OK" if AI_KEY else "MANGLER (generering falder tilbage til skabelon)"), kritisk=True)
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
            await asyncio.get_event_loop().run_in_executor(executor, strategy_check_sync, key)
        except Exception:
            pass
    return RedirectResponse("/", status_code=303)


@app.post("/settings/ai-model")
async def settings_ai_model(request: Request):
    form = await request.form()
    model = str(form.get("model", "")).strip()
    with get_db() as db:
        if model:
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('ai_model', ?)", (model,))
        else:
            db.execute("DELETE FROM settings WHERE key='ai_model'")
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
    have_schema = schema_version()
    schema_ok = have_schema == SCHEMA_VERSION
    status = "ok"
    if disk_used_pct is not None and disk_used_pct >= 80:
        status = "advarsel"
    if not schema_ok:
        status = "advarsel"  # appen koerer, men schemaet er ikke det koden forventer
    if not db_write or (disk_used_pct is not None and disk_used_pct >= 90):
        status = "kritisk"
    body = {
        "status": status,
        "db_write": db_write,
        "disk_used_pct": disk_used_pct,
        "schema_version": have_schema,
        "schema_version_expected": SCHEMA_VERSION,
        "schema_ok": schema_ok,
        "budget": {s: {"used": u, "limit": l} for s, (u, l) in budget_usage().items()},
        "version": APP_VERSION,
        "ai": bool(AI_KEY),
        "ai_provider": AI_PROVIDER,
        "wordpress": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "serpapi": bool(SERPAPI_KEY),
        "telegram": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
        "auth": bool(APP_TOKEN),
    }
    return JSONResponse(body, status_code=503 if status == "kritisk" else 200)


# ---------- Scheduler ----------
async def job_check_domains():
    if not module_on("domains"):
        return
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(executor, check_all_domains_sync)


async def job_check_keywords():
    if not module_on("keywords"):
        return
    if not SERPAPI_KEY:
        return
    loop = asyncio.get_event_loop()
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
