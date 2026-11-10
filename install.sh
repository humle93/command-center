#!/bin/bash
set -e
PROJECT_DIR="$HOME/command-center"

# Versionsnummeret laeses fra den app/main.py der ligger indlejret nedenfor (EOF_MAIN), saa
# installatoeren ikke kan paastaa en anden version end den den skriver. Ret APP_VERSION i
# app/main.py - ikke her. Linjen staar i spalte 0 i den indlejrede fil.
VERSION="$(sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' "${BASH_SOURCE[0]:-$0}" | head -1)"

echo "⚡ Command Center v${VERSION:-?} - installerer i $PROJECT_DIR..."
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
# Command Center - kopier til .env og udfyld (hele listen staar i README og i manualen)
# Login: der er ingen token. Udfyld CC_ADMIN_EMAIL + CC_ADMIN_PASSWORD nedenfor, saa oprettes
# standardbrugeren ved opstart (efter deployment), og du logger ind med den med det samme.
# Er de to linjer tomme, opretter foerste besoeg brugeren via /setup som reserve. Nye brugere
# inviteres paa mail under fanen "Brugere" og kraever SMTP_HOST + SMTP_FROM nedenfor.
# Hvor run.sh lytter. 127.0.0.1 = kun denne maskine; 0.0.0.0 = ogsaa fra netvaerket (kraever TLS/proxy).
CC_HOST=127.0.0.1
CC_PORT=8000
# SSRF: udgaaende kald afviser loopback, private net og sky-metadata (169.254.169.254).
# Aabn enkelte vaertsnavne her, adskilt af komma, hvis CC skal maale en intern side.
CC_SSRF_ALLOW=
# Adressen du aabner i browseren bag nginx (bruges kun til at printe den rigtige adresse).
# Ultra.cc: fx https://<bruger>.<server>.ultra.cc - tom = ingen nginx. Bruges ogsaa som adresse
# i invitationsmailen.
# Den adresse DU aabner i browseren - den offentlige adresse bag nginx, ikke 127.0.0.1.
# Styrer tre ting: login-linket i scripts/update.sh og scripts/user_create.py, adressen i
# invitationsmailen, og Host-tjekket paa /mcp (MCP-noegler afvises med 421, hvis vaerten ikke
# matcher noejagtigt).
# Format: med https://, kun vaerten, uden anfoerselstegn og uden kommentar paa samme linje:
#     CC_PUBLIC_URL=https://humle91.ultra.cc
# Ultra.cc: brug praecis den adresse du selv skriver i browseren (den staar typisk i panelet
# under fanen Network/Domains). Sti som /apps/cc virker ikke - brug subdomaene eller egen port.
# Tom betyder "kun lokal": login-linket bliver http://127.0.0.1:8000/login, og Host-tjekket paa
# /mcp slaaes HELT fra - det er kun OK paa en maskine, ingen andre kan naa.
CC_PUBLIC_URL=
# Standardbruger oprettet ved opstart (kun naar der ikke findes brugere i databasen).
# Kontoen faar must_change_password, saa koden her kun bruges til det foerste login - derefter
# skifter du den under fanen Brugere. Klartekst staar kun i .env (.env committes aldrig).
# Tomme linjer = ingen standardbruger; foerste besoeg opretter brugeren via /setup i stedet.
# Bemaerk: en senere aendring af linjerne rorer ikke en konto, der allerede findes - og naar du
# skifter koden under Brugere, passer CC_ADMIN_PASSWORD ikke laengere: opstartsloggen skriver en
# advarsel, den ligger under Alarmer, og dashboardet viser en roed bjaelke, indtil linjen rettes
# eller fjernes. Login bruger hele tiden den nye kode. Skifter standardbrugeren selv koden i UI'et,
# toemmes CC_ADMIN_PASSWORD her automatisk (kun den linje) - saa bliver filen aldrig foraeldet.
# Siden v7.19.2 staar rydningen i dashboardet med tidspunkt og navn, og saettes linjen tilbage,
# siger bjaelken det i stedet - filens tilstand kan altsaa ses uden at aabne den.
CC_ADMIN_EMAIL=
CC_ADMIN_PASSWORD=
# Stoler paa X-Forwarded-* fra disse IP'er (nginx paa samme maskine = 127.0.0.1).
CC_FORWARDED_ALLOW_IPS=127.0.0.1
# Tidszone for planlagte opslag. Tiden gemmes som lokal tid OG UTC; ukendt zone -> Europe/Copenhagen.
CC_TZ=Europe/Copenhagen
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
# Alarmer: e-mail via SMTP (port 587 = STARTTLS, 465 = SMTP_TLS=ssl). Brug app-adgangskode.
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=
SMTP_TO=
SMTP_TLS=starttls
# Alarmer: ntfy (selvhostet eller ntfy.sh) - emne er i praksis en adgangskode paa ntfy.sh
NTFY_URL=https://ntfy.sh
NTFY_TOPIC=
NTFY_TOKEN=
# Alarmer: webhook (POST JSON + Standard Webhooks-signatur). Secret: whsec_<base64>
ALERT_WEBHOOK_URL=
ALERT_WEBHOOK_SECRET=
# info | advarsel | kritisk - alarmer under niveauet sendes ikke
ALERT_MIN_SEVERITY=info
# Stille timer, fx 23-7 (kun kritiske alarmer slipper igennem; resten udskydes, ikke tabt)
ALERT_QUIET_HOURS=
# Ens alarmer inden for dette antal minutter sendes kun én gang
ALERT_DEDUPE_MINUTES=180
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
# GitHub-opdatering (henter kun projektets filer)
GITHUB_TOKEN=
GITHUB_REPO=humle93/command-center
EOF_ENVDOT

echo "📄 app/main.py..."
cat << 'EOF_MAIN' > "$PROJECT_DIR/app/main.py"
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
from zoneinfo import ZoneInfo
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger
import os
import shutil
import ipaddress
import socket
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
import inspect
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

APP_VERSION = "7.24.0"

# --- Nyheder: skrives ved opstart (skaerm + app/data/startup.log) og vises paa login-siden ---
NEWEST = [
    ("7.24.0", "Vaekst-fanen: lokal indholdsoptimerer, konkurrent-sammenligning, indholdsplan og linkliste - uden API-noegle"),
    ("7.23.0", "Backup i UI: tag en backup nu og gendan en gemt backup med bekraeftelse - der tages altid en pre-restore-kopi foerst"),
    ("7.22.0", "Offline dashboard: Tailwind, Alpine og Chart.js ligger lokalt under /static/vendor - ingen CDN-afhaengighed"),
    ("7.21.0", "CSRF-beskyttelse: muterende kald fra andre sites afvises (403); ny session ved hvert login og gammel sid slettes"),
    ("7.20.0", "Cockpit viser API-budget og jobstatus; forsinkede eller fejlede jobs giver alarm (job-heartbeat)"),
    ("7.19.0", "Standardbrugeren i .env: oprettes ved deployment, advarer naar koden er foraeldet, rydder linjen selv og viser rydningen i dashboardet"),
    ("7.18.0", "Social viser hvornaar WordPress sidst hoerte fra Command Center - CC sender X-Command-Center"),
    ("7.17.5", "Knappen Log ind paa Command Center i WordPress bruger et engangslink fra CC"),
    ("7.17.4", "Sletning af brugere svarer i formularen - en afvist sletning forklares i stedet for kun at blive en alarm"),
    ("7.17.3", "Invitationen afviser pladsholder-adresser med en forklaring - i formularen og fra terminalen"),
    ("7.17.2", "Invitationen viser selv om mailen blev sendt - foer laa fejlen kun under Alarmer"),
    ("7.17.1", "MCP-noeglen ligger ikke laengere i klartekst i DB'en, og ukendte vaerktoejer havner i auditten"),
    ("7.17.0", "MCP fase 2: skrivende vaerktoejer med write-scope og audit pr. noegle"),
    ("7.16.0", "MCP-adgang: hver klient sin egen noegle (hash) og syv laese-vaerktoejer paa /mcp"),
    ("7.15.0", "Login med e-mail + invitation paa mail med midlertidig adgangskode - ingen tokens"),
    ("7.14.0", "Planlagt tid gemmes som lokal tid + UTC; sommertid afvises i stedet for at gaettes"),
    ("7.13.4", "Agentgrupper rettet til de tre repos: Command Center, Social Autopilot og Android"),
    ("7.13.3", "Fire agenter i tre grupper (app, WordPress-plugin, indhold) + manifest i .agents/"),
    ("7.13.2", "Agent + skill i .agents/ og sidste doede variabler fjernet (sitemap_missing, _up, result)"),
    ("7.13.1", "Oprydning: doede importer og variabler fjernet, Juno-tabelrester droppes naar de er tomme"),
    ("7.13.0", "Login viser IP og en koerselsrapport; opstart skriver version og nyheder"),
    ("7.12.0", "Alarmer til e-mail, ntfy og signeret webhook - i koe med dedupe og stille timer"),
    ("7.11.0", "Brugere med adgangskode, GitHub-opdatering med genstart, nginx/systemd"),
]
NEWEST_LINE = "Vaekst-fanen maaler indhold, sammenligner med konkurrenter og holder planen - helt lokalt"


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
            created_at TEXT,
            created_at_utc TEXT,
            scheduled_at TEXT,
            scheduled_at_utc TEXT
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
            email TEXT UNIQUE NOT NULL,
            username TEXT UNIQUE,
            password_hash TEXT NOT NULL,
            must_change_password INTEGER DEFAULT 0,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS api_clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            key_hash TEXT UNIQUE NOT NULL,
            key_hint TEXT,
            scopes TEXT NOT NULL DEFAULT 'read',
            created_at TEXT,
            last_used_at TEXT,
            last_used_ip TEXT,
            revoked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS api_audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id INTEGER,
            method TEXT,
            tool TEXT,
            ok INTEGER DEFAULT 1,
            detail TEXT,
            duration_ms INTEGER,
            created_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_api_audit_client ON api_audit(client_id, id);
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
            "socialqueue": ["created_at_utc", "scheduled_at", "scheduled_at_utc"],
        }.items():
            existing = [r[1] for r in db.execute(f"PRAGMA table_info({table})").fetchall()]
            for c in want:
                if c not in existing:
                    db.execute(f"ALTER TABLE {table} ADD COLUMN {c} TEXT")
        # v7.15: konti skifter fra brugernavn til e-mail. Gamle raekker beholder brugernavnet i
        # kolonnen username og kan stadig logge ind med det; de faar en pladsholder-adresse.
        user_cols = [r[1] for r in db.execute("PRAGMA table_info(users)").fetchall()]
        if user_cols and "email" not in user_cols:
            db.execute("DROP TABLE IF EXISTS users_migrate")
            db.execute("""CREATE TABLE users_migrate (
                id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE NOT NULL, username TEXT UNIQUE,
                password_hash TEXT NOT NULL, must_change_password INTEGER DEFAULT 0, created_at TEXT,
                last_login_ip TEXT, last_login_at TEXT
            )""")
            db.execute("""INSERT INTO users_migrate (id, email, username, password_hash, created_at,
                             last_login_ip, last_login_at)
                SELECT id, lower(username) || '@local', username, password_hash, created_at,
                       last_login_ip, last_login_at FROM users""")
            db.execute("DROP TABLE users")
            db.execute("ALTER TABLE users_migrate RENAME TO users")
        db.execute("""CREATE TABLE IF NOT EXISTS api_clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, key_hash TEXT UNIQUE NOT NULL,
            key_hint TEXT, scopes TEXT NOT NULL DEFAULT 'read', created_at TEXT, last_used_at TEXT,
            last_used_ip TEXT, revoked_at TEXT
        )""")
        db.execute("""CREATE TABLE IF NOT EXISTS api_audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT, client_id INTEGER, method TEXT, tool TEXT,
            ok INTEGER DEFAULT 1, detail TEXT, duration_ms INTEGER, created_at TEXT
        )""")
        db.execute("CREATE INDEX IF NOT EXISTS idx_api_audit_client ON api_audit(client_id, id)")
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
        # v7.14: gamle raekker er skrevet i lokal tid - backfill UTC ud fra CC_TZ.
        try:
            for r in db.execute(
                "SELECT id, created_at FROM socialqueue "
                "WHERE created_at_utc IS NULL AND created_at IS NOT NULL"
            ).fetchall():
                try:
                    db.execute("UPDATE socialqueue SET created_at_utc=? WHERE id=?",
                               (local_to_utc(r["created_at"]), r["id"]))
                except Exception:
                    pass
        except Exception:
            pass
        # v7.12: eksisterende installationer faar outbox-tabellen her (init_db rammer kun nye DB'er).
        db.execute("""CREATE TABLE IF NOT EXISTS alert_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT, alarm_id INTEGER, dedupe_key TEXT,
            channel TEXT NOT NULL, severity TEXT, subject TEXT, body TEXT, payload TEXT,
            attempts INTEGER DEFAULT 0, next_attempt_at TEXT, state TEXT DEFAULT 'pending',
            last_error TEXT, created_at TEXT, sent_at TEXT
        )""")
        # v7.24: vaekst-fanen. Briefs er planen, link_targets er den manuelle linkliste, og
        # content_audits er historikken fra indholdsoptimereren (de sidste 50 beholdes).
        db.execute("""CREATE TABLE IF NOT EXISTS content_briefs (
            id INTEGER PRIMARY KEY AUTOINCREMENT, keyword TEXT NOT NULL, intent TEXT, title TEXT,
            words INTEGER, headings TEXT, terms TEXT, notes TEXT, planned_for TEXT,
            status TEXT DEFAULT 'Planlagt', created_at TEXT
        )""")
        db.execute("""CREATE TABLE IF NOT EXISTS link_targets (
            id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT UNIQUE NOT NULL, site TEXT, type TEXT,
            reason TEXT, contact TEXT, status TEXT DEFAULT 'Ny', created_at TEXT
        )""")
        db.execute("""CREATE TABLE IF NOT EXISTS content_audits (
            id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT, keyword TEXT, score INTEGER,
            words INTEGER, target_words INTEGER, terms_json TEXT, checks_json TEXT, created_at TEXT
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
        db.execute("DELETE FROM api_audit WHERE created_at < ?", (cutoff(90),))
        # en noegle der blev vist men aldrig laest (fx lukket fane) skal ikke blive liggende i klartekst
        row = db.execute("SELECT value FROM settings WHERE key='api_key_once'").fetchone()
        if row:
            try:
                created = str((jsonlib.loads(row["value"]) or {}).get("created_at") or "")
            except Exception:
                created = ""
            if not created or created < (now - API_KEY_ONCE_TTL).isoformat(timespec="seconds"):
                db.execute("DELETE FROM settings WHERE key='api_key_once'")


# ---------- Auth: brugere og sessioner ----------
# Dashboardet har rigtige brugere: e-mail + adgangskode (PBKDF2-SHA256 med salt pr. bruger).
# Foerste besoeg opretter den foerste bruger via /setup; derefter inviterer en bruger de naeste
# med en mail. Der er hverken delt noegle eller invite-token - adgang er altid en adgangskode.
SESSION_COOKIE = "cc_session"
SESSION_MAX_AGE = 60 * 60 * 24 * 30        # 30 dage
PBKDF2_ITERATIONS = 240_000
MIN_PASSWORD_LEN = 8
EMAIL_MAX_LEN = 254
CC_PUBLIC_URL = os.environ.get("CC_PUBLIC_URL", "").strip()   # adressen der staar i invitationsmailen
_USER_EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[A-Za-z]{2,}")

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


def normalize_email(value: str) -> str:
    """E-mailen er login-id: trimmet, smaa bogstaver og i et format der kan modtage post."""
    email = (value or "").strip().lower()
    if len(email) > EMAIL_MAX_LEN or not _USER_EMAIL_RE.fullmatch(email):
        raise ValueError("E-mail: brug en gyldig adresse, fx bruger@ditfirma.dk")
    return email


# Eksempel-adresserne fra dokumentationen - dem kan ingen modtage post paa. Baade formularen i fanen
# Brugere og scripts/invite.py bruger den samme regel, saa en pladsholder ikke bliver en rigtig bruger.
# example.dk er ikke med: repoets egne tests bruger det som et almindeligt testdomaene.
EXAMPLE_EMAIL_DOMAINS = {"domaene.dk", "domæne.dk", "example.com", "example.org", "example.net"}
EXAMPLE_EMAIL_LOCALS = {"dit.navn", "ditnavn", "navn", "dit", "din", "adresse"}


def example_email_hint(email: str) -> str:
    """Forklarer hvorfor adressen ligner et eksempel (tom tekst = den ser rigtig ud)."""
    local, _, domain = (email or "").partition("@")
    if domain in EXAMPLE_EMAIL_DOMAINS:
        return f"domaene-navnet {domain} er et eksempel"
    if local in EXAMPLE_EMAIL_LOCALS:
        return f"'{local}' er et eksempel paa et navn"
    return ""


def create_user(email: str, password: str, must_change: bool = False, username: str = "") -> int:
    """Opretter en bruger. must_change=1 bruges til invitationer med en midlertidig kode."""
    email = normalize_email(email)
    if len(password or "") < MIN_PASSWORD_LEN:
        raise ValueError(f"Adgangskoden skal vaere mindst {MIN_PASSWORD_LEN} tegn")
    with get_db() as db:
        cur = db.execute(
            "INSERT INTO users (email, username, password_hash, must_change_password, created_at) "
            "VALUES (?,?,?,?,?)",
            (email, (username or None), hash_password(password), 1 if must_change else 0, now_iso()))
        return cur.lastrowid


# --- Standardbruger fra .env (v7.18) ---
# Et nyt deployment skal kunne logge ind med det samme: staar CC_ADMIN_EMAIL + CC_ADMIN_PASSWORD i
# .env, oprettes kontoen ved opstart. Klartekst findes kun i .env - her gemmes PBKDF2-hashen.
# Der seedes kun, naar der ingen brugere er, saa en rettet .env-kode ikke rorer en konto i brug.
ADMIN_EMAIL_ENV = "CC_ADMIN_EMAIL"
ADMIN_PASSWORD_ENV = "CC_ADMIN_PASSWORD"


def standard_user_settings() -> tuple:
    """(e-mail, adgangskode) fra .env - tomme strenge naar linjerne ikke er udfyldt."""
    return (os.environ.get(ADMIN_EMAIL_ENV, "").strip(),
            os.environ.get(ADMIN_PASSWORD_ENV, ""))


def seed_standard_user() -> str:
    """Opretter standardbrugeren fra .env. Returnerer en kort status til opstartsloggen.

    "oprettet" = kontoen blev lavet nu, "findes" = der var allerede brugere (roeres ikke),
    "mangler" = .env har ikke begge linjer (saa bruges /setup som foer), "fejl: ..." = afvist.
    Kontoen oprettes med must_change_password, saa koden fra .env skal skiftes ved foerste login.
    """
    email, password = standard_user_settings()
    if not email or not password:
        return "mangler"
    if user_count() > 0:
        return "findes"
    try:
        create_user(email, password, must_change=True)
    except ValueError as e:
        with get_db() as db:
            add_alarm(db, "brugere", f"Standardbrugeren i .env blev afvist: {str(e)[:160]}", "advarsel")
        return f"fejl: {e}"
    except sqlite3.IntegrityError:
        return "findes"
    with get_db() as db:
        add_alarm(db, "brugere", f"Standardbrugeren '{email}' oprettet ved opstart fra .env", "info")
    return "oprettet"


# Sidste verificerede svar paa "passer .env-koden?" - PBKDF2 er 240k iterationer, saa dashboardet
# maa ikke betale den pris ved hver sidevisning. Noeglen er (e-mail, sha256(kode), gemt hash).
_ENV_PASSWORD_STATE = {"sig": None, "msg": ""}


def env_password_mismatch() -> str:
    """Advarsel naar CC_ADMIN_PASSWORD ikke laengere passer til standardbrugeren - ellers "".

    Koden i .env bruges kun, naar kontoen seedes. Skiftes den i UI'et (eller med
    scripts/user_create.py), bliver linjen i .env foraeldet: login bruger den nye kode, mens filen
    lover den gamle. Advarslen findes, saa man retter .env i stedet for at saette koden tilbage.
    """
    email, password = standard_user_settings()
    if not email or not password:
        return ""
    try:
        row = find_user(email)
    except Exception:
        return ""
    if not row:
        return ""
    sig = (row["email"], hashlib.sha256(password.encode()).hexdigest(), row["password_hash"])
    if _ENV_PASSWORD_STATE["sig"] == sig:
        return _ENV_PASSWORD_STATE["msg"]
    msg = ""
    if not verify_password(password, row["password_hash"]):
        msg = (f"{ADMIN_PASSWORD_ENV} i .env passer ikke længere til '{row['email']}' - koden er "
               f"skiftet i UI'et, så login bruger den nye kode. Ret eller fjern linjen i .env.")
    _ENV_PASSWORD_STATE.update(sig=sig, msg=msg)
    return msg


def warn_stale_env_password() -> str:
    """Lægger advarslen i Alarmer ved opstart (dedupe som de andre) og returnerer teksten."""
    msg = env_password_mismatch()
    if not msg:
        return ""
    try:
        with get_db() as db:
            add_alarm(db, "brugere", msg, "advarsel")
    except Exception:
        pass
    return msg


# .env ligger i projektroden ved siden af app/ - samme sti som load_dotenv() bruger.
ENV_PATH = os.path.join(os.path.dirname(BASE_DIR), ".env")


def clear_env_admin_password(email: str = "") -> str:
    """Fjerner CC_ADMIN_PASSWORD fra .env, naar standardbrugeren selv har skiftet kode.

    Koden i .env bruges kun ved seed; derefter er linjen kun et fristed for forvirring (og for
    advarslen om en foraeldet kode). Kun den ene linje roeres - kommentarer og de andre noegler
    staar urort. Returnerer "fjernet", "passer-endnu" (koden er den samme som foer),
    "ikke-standardbruger", "ingen-linje", "ingen-fil" eller "fejl: ...". En fejl vaelter aldrig
    selve adgangskode-skiftet - saa bliver advarslen i dashboardet staaende i stedet.
    """
    env_email, env_password = standard_user_settings()
    if not env_email or not email or normalize_email(email) != normalize_email(env_email):
        return "ikke-standardbruger"
    if not env_password:
        return "ingen-linje"
    row = None
    try:
        row = find_user(env_email)
        still_valid = bool(row) and verify_password(env_password, row["password_hash"])
    except Exception:
        still_valid = False
    if still_valid:                      # koden er ikke skiftet vaek fra .env-linjen
        return "passer-endnu"
    path = ENV_PATH
    if not os.path.exists(path):
        return "ingen-fil"
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        pattern = re.compile(r"^\s*(?:export\s+)?%s\s*=" % re.escape(ADMIN_PASSWORD_ENV))
        out, changed = [], False
        for line in lines:
            if pattern.match(line):
                out.append(ADMIN_PASSWORD_ENV + "=" + ("\r\n" if line.endswith("\r\n") else "\n"))
                changed = True
            else:
                out.append(line)
        if not changed:
            return "ingen-linje"
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.writelines(out)
        try:
            os.chmod(tmp, os.stat(path).st_mode)
        except Exception:
            pass
        os.replace(tmp, path)
    except Exception as e:
        try:
            with get_db() as db:
                add_alarm(db, "brugere", "CC_ADMIN_PASSWORD kunne ikke fjernes fra .env efter "
                          "adgangskode-skift: %s - fjern linjen manuelt" % str(e)[:120], "advarsel")
        except Exception:
            pass
        return "fejl: %s" % e
    os.environ[ADMIN_PASSWORD_ENV] = ""
    _ENV_PASSWORD_STATE.update(sig=None, msg="")
    try:
        with get_db() as db:
            record_env_password_cleared(db, env_email)
            add_alarm(db, "brugere", "CC_ADMIN_PASSWORD er fjernet fra .env, fordi '%s' skiftede "
                      "adgangskode" % env_email, "info")
    except Exception:
        pass
    print("[cc] .env: CC_ADMIN_PASSWORD fjernet (standardbrugeren skiftede kode)", flush=True)
    return "fjernet"


# Dashboardet maa ikke kraeve, at man aabner .env: rydningen gemmes derfor i settings sammen med
# hvem og hvornaar, og "staar linjen der?" laeses fra filen selv. Miljoevariablen blev laest ved
# opstart og ser derfor ikke en rettelse undervejs.
ENV_CLEARED_KEY = "env_password_cleared"
_DA_MONTHS = ("januar", "februar", "marts", "april", "maj", "juni", "juli", "august",
              "september", "oktober", "november", "desember")


def danish_time(iso: str) -> str:
    """'2026-11-05T16:12:33' -> '5. november 2026 kl. 16:12' ('' naar vaerdien er skaev)."""
    try:
        dt = datetime.fromisoformat(str(iso))
    except Exception:
        return ""
    if dt.tzinfo is not None:
        try:
            dt = dt.astimezone(ZoneInfo(CC_TZ_NAME))
        except Exception:
            pass
    return "%d. %s %d kl. %02d:%02d" % (dt.day, _DA_MONTHS[dt.month - 1], dt.year, dt.hour, dt.minute)


def record_env_password_cleared(db, account: str) -> None:
    """Gemmer hvem/hvornaar .env-linjen blev ryddet. Fejler den, er rydningen stadig sket.

    Kun navnet paa den, der skiftede koden, gemmes - aldrig koden selv.
    """
    name = ""
    try:
        row = db.execute("SELECT username FROM users WHERE email=?", (account,)).fetchone()
        name = (row["username"] or "") if row else ""
    except Exception:
        name = ""
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?,?)",
               (ENV_CLEARED_KEY, jsonlib.dumps({"at": now_iso(), "by": (name or account),
                                                "account": account}, ensure_ascii=False)))


def env_password_cleared() -> dict:
    """Den seneste rydning som {'at', 'by', 'account'} - {} naar der ikke er nogen."""
    try:
        with get_db() as db:
            row = db.execute("SELECT value FROM settings WHERE key=?", (ENV_CLEARED_KEY,)).fetchone()
        data = jsonlib.loads(row["value"]) if row and row["value"] else {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def env_admin_password_in_file() -> str:
    """'sat', 'tom', 'ingen-fil' eller 'fejl' - laeser .env, saa manuelle rettelser ogsaa ses."""
    try:
        with open(ENV_PATH, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        return "ingen-fil"
    except Exception:
        return "fejl"
    pattern = re.compile(r"^\s*(?:export\s+)?%s\s*=(.*)$" % re.escape(ADMIN_PASSWORD_ENV), re.M)
    found = pattern.search(text)
    return "sat" if found and found.group(1).strip() else "tom"


def env_password_notice() -> dict:
    """Tekst til dashboardet om .env-linjen: ryddet af hvem/hvornaar - eller sat tilbage.

    Baren vises kun for rydninger, vi selv har lavet; en tom linje paa en ny installation skal ikke
    give stoej. Er koden blevet foraeldet, vinder den roede advarsel i stedet. Koderne selv er
    hverken i teksten eller i settings.
    """
    rec = env_password_cleared()
    if not rec or env_password_mismatch():
        return {}
    who = rec.get("by") or rec.get("account") or "ukendt"
    when = danish_time(rec.get("at", ""))
    stamp = (" " + when) if when else ""
    state = env_admin_password_in_file()
    if state == "sat":
        text = (f"CC_ADMIN_PASSWORD står i .env igen (fjernet{stamp} af {who}) - skiftes koden i "
                f"UI'et, bliver linjen forældet igen.")
    elif state in ("ingen-fil", "fejl"):
        text = (f"CC_ADMIN_PASSWORD blev fjernet fra .env{stamp} af {who}, men filen kunne ikke "
                f"læses ved denne kontrol.")
    else:
        text = (f"CC_ADMIN_PASSWORD blev fjernet fra .env{stamp} af {who} - filen kan ikke blive "
                f"forældet. Linjen skal kun tilbage, hvis et nyt deployment skal seedes.")
    return {"state": state, "text": text}


def find_user(identifier: str):
    """Brugeren bag en e-mail - eller et brugernavn fra foer v7.15, saa gamle konti ikke laases ude."""
    ident = (identifier or "").strip()
    if not ident:
        return None
    with get_db() as db:
        row = db.execute(
            "SELECT id, email, password_hash, must_change_password FROM users WHERE email=?",
            (ident.lower(),)).fetchone()
        if not row:
            row = db.execute(
                "SELECT id, email, password_hash, must_change_password FROM users WHERE username=?",
                (ident,)).fetchone()
        return row


def temporary_password() -> str:
    """Midlertidig adgangskode til en invitation: tilfaeldig, men til at skrive af (12 tegn)."""
    return secrets.token_urlsafe(9)


INVITE_SUBJECT = "Invitation til Command Center"


def invitation_body(email: str, base_url: str, password: str) -> str:
    """Mailteksten til en invitation - samme tekst uanset om SMTP eller en anden vej sender den."""
    return (
        "Du er inviteret til Command Center.\n\n"
        f"Adresse: {CC_PUBLIC_URL or base_url or 'den adresse du har faaet af ejeren'}\n"
        f"E-mail: {email}\n"
        f"Midlertidig adgangskode: {password}\n\n"
        "Log ind og skift adgangskoden med det samme under fanen Brugere.\n"
        "Adgangskoden staar kun i denne mail."
    )


def invite_user(email: str, base_url: str = "", deliver=None, allow_example: bool = False) -> tuple:
    """Inviterer en bruger: opretter kontoen med en midlertidig kode og mailer den.

    Returnerer (ok, fejl). Der sendes ingen links og ingen tokens - kun en e-mailadresse og en
    midlertidig adgangskode, som brugeren skifter ved foerste login.

    deliver(subject, body) -> (ok, fejl) bruges, naar mailen skal afsted ad en anden vej end SMTP
    (fx printes, saa ejeren kan sende den fra sin egen mailkonto). allow_example=True springer
    pladsholder-tjekket over, naar ejeren har bekræftet at adressen er rigtig alligevel."""
    try:
        email = normalize_email(email)
    except ValueError as e:
        return False, str(e)
    hint = example_email_hint(email)
    if hint and not allow_example:
        return False, f"'{email}' ligner eksemplet fra dokumentationen ({hint}) - skriv den rigtige adresse"
    with get_db() as db:
        if db.execute("SELECT 1 FROM users WHERE email=?", (email,)).fetchone():
            return False, f"Der findes allerede en bruger med {email}"
    password = temporary_password()
    body = invitation_body(email, base_url, password)
    ok, err = deliver(INVITE_SUBJECT, body) if deliver else send_email(email, INVITE_SUBJECT, body)
    if not ok:
        return False, err
    try:
        create_user(email, password, must_change=True)
    except sqlite3.IntegrityError:
        return False, f"Der findes allerede en bruger med {email}"
    except ValueError as e:
        return False, str(e)
    with get_db() as db:
        add_alarm(db, "brugere", f"Invitation sendt til {email}", "info")
    return True, ""


# Fanerne i dashboardet - bruges naar en handling skal lande i den rigtige fane efter et POST.
DASHBOARD_TABS = ("cockpit", "seo", "keywords", "articles", "vaekst", "links", "spy", "social",
                  "monitors", "ai", "pro", "moduler", "brugere", "alarms", "notes")


def invite_redirect(ok: bool, text: str, email: str = "", kind: str = "") -> str:
    """Sender brugeren tilbage til Brugere-fanen med invitationens resultat i URL'en.

    Uden det her landede svaret paa Cockpit, og en mislykket invitation var kun synlig som en
    alarm i en anden fane - det ligner en mail der bare er tabt. kind="adresse"/"eksempel" goer
    det muligt for formularen at forklare et afvist argument i stedet for en mailserver-fejl."""
    state = "ok" if ok else "fejl"
    url = f"/?tab=brugere&invite={state}&invite_msg={urllib.parse.quote((text or '').strip()[:180])}"
    if email:
        url += f"&invite_email={urllib.parse.quote(email[:254])}"
    if kind:
        url += f"&invite_kind={urllib.parse.quote(kind[:16])}"
    return url


def users_delete_redirect(ok: bool, text: str, kind: str = "", email: str = "") -> str:
    """Sender brugeren tilbage til Brugere-fanen med sletningens resultat i URL'en.

    Foer landede bade en afvist og en gennemfoert sletning paa Cockpit, saa svaret var vaek med det
    samme - kun alarmen under Alarmer vidste hvad der skete. kind goer det muligt at forklare den
    enkelte afvisning (sidste bruger, ukendt id, ugyldigt id) i selve fanen."""
    state = "ok" if ok else "fejl"
    url = f"/?tab=brugere&del={state}&del_msg={urllib.parse.quote((text or '').strip()[:180])}"
    if kind:
        url += f"&del_kind={urllib.parse.quote(kind[:16])}"
    if email:
        url += f"&del_email={urllib.parse.quote(email[:254])}"
    return url


# ---------- API-noegler: personlige noegler pr. MCP-klient (ingen global token) ----------
API_KEY_PREFIX = "cc_"
API_SCOPES = ("read", "write")
# Noeglen vises én gang i dashboardet. Den ligger i settings i saa kort tid som muligt: raekken
# slettes i samme kald som den laeses, og TTL'en er kun et sikkerhedsnet hvis visningen aldrig sker.
API_KEY_ONCE_TTL = timedelta(minutes=15)


def hash_api_key(key: str) -> str:
    return hashlib.sha256((key or "").encode()).hexdigest()


def normalize_scopes(value: str) -> str:
    parts = [p.strip().lower() for p in (value or "").replace(";", ",").split(",")]
    keep = sorted({p for p in parts if p in API_SCOPES})
    return ",".join(keep) or "read"


def create_api_client(name: str, scopes: str = "read") -> tuple:
    """Ny klient-noegle. Returnerer (id, noegle) - noeglen findes kun i klartekst her."""
    name = (name or "").strip()[:60]
    if len(name) < 2:
        raise ValueError("Navn: mindst 2 tegn")
    key = API_KEY_PREFIX + secrets.token_urlsafe(24)
    with get_db() as db:
        cur = db.execute(
            "INSERT INTO api_clients (name, key_hash, key_hint, scopes, created_at) VALUES (?,?,?,?,?)",
            (name, hash_api_key(key), key[-4:], normalize_scopes(scopes), now_iso()))
        return cur.lastrowid, key


def find_api_client(token: str):
    token = (token or "").strip()
    if not token.startswith(API_KEY_PREFIX):
        return None
    with get_db() as db:
        return db.execute("SELECT id, name, scopes, last_used_at FROM api_clients "
                          "WHERE key_hash=? AND revoked_at IS NULL", (hash_api_key(token),)).fetchone()


def touch_api_client(client_id: int, ip: str) -> None:
    with get_db() as db:
        db.execute("UPDATE api_clients SET last_used_at=?, last_used_ip=? WHERE id=?",
                   (now_iso(), ip, client_id))


def revoke_api_client(client_id: int) -> None:
    with get_db() as db:
        db.execute("UPDATE api_clients SET revoked_at=? WHERE id=? AND revoked_at IS NULL",
                   (now_iso(), client_id))


def api_client_rows() -> list:
    with get_db() as db:
        return db.execute("SELECT id, name, key_hint, scopes, created_at, last_used_at, last_used_ip, revoked_at "
                          "FROM api_clients ORDER BY id DESC").fetchall()


def remember_api_key(name: str, key: str) -> None:
    """Noeglen vises én gang i UI'et. Raekken indeholder klartekst, saa den lever kun til naeste visning."""
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('api_key_once', ?)",
                   (jsonlib.dumps({"name": name, "key": key, "created_at": now_iso()}),))


def pending_api_key():
    """Ny noegle til dashboardet - og raekken slettes i samme kald, saa klartekst ikke bliver liggende."""
    try:
        with get_db() as db:
            row = db.execute("SELECT value FROM settings WHERE key='api_key_once'").fetchone()
            if not row or not row["value"]:
                return None
            data = jsonlib.loads(row["value"])
            created = str((data or {}).get("created_at") or "")
            stale = (not created
                     or created < (datetime.now() - API_KEY_ONCE_TTL).isoformat(timespec="seconds"))
            db.execute("DELETE FROM settings WHERE key='api_key_once'")
            return None if stale else data
    except Exception:
        return None


def log_api_call(client_id: int, method: str, tool: str, ok: bool, detail: str = "",
                 duration_ms: int = 0) -> None:
    """Audit pr. noegle: ét spor pr. vaerktoejskald, saa et misbrugt noegle kan ses i UI'et."""
    try:
        with get_db() as db:
            db.execute("INSERT INTO api_audit (client_id, method, tool, ok, detail, duration_ms, created_at) "
                       "VALUES (?,?,?,?,?,?,?)",
                       (client_id, (method or "")[:40], (tool or "")[:60], 1 if ok else 0,
                        (detail or "")[:300], int(duration_ms or 0), now_iso()))
    except Exception:
        pass


def api_usage() -> dict:
    """Kald og fejl pr. noegle - vist i MCP-kortet."""
    with get_db() as db:
        rows = db.execute("SELECT client_id, COUNT(*) AS calls, "
                          "SUM(CASE WHEN ok=0 THEN 1 ELSE 0 END) AS errors, MAX(created_at) AS last_at "
                          "FROM api_audit GROUP BY client_id").fetchall()
    return {r["client_id"]: dict(r) for r in rows}


def api_audit_rows(limit: int = 8) -> list:
    try:
        limit = max(1, min(int(limit), 100))
    except (TypeError, ValueError):
        limit = 8
    with get_db() as db:
        return [dict(r) for r in db.execute(
            "SELECT a.created_at, a.method, a.tool, a.ok, a.detail, a.duration_ms, c.name AS client "
            "FROM api_audit a LEFT JOIN api_clients c ON c.id = a.client_id "
            "ORDER BY a.id DESC LIMIT ?", (limit,)).fetchall()]


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


def _same_origin(request: Request) -> bool:
    """Er en muterende forespoergsel fra samme site (eller uden browser-headers)?"""
    fetch_site = (request.headers.get("sec-fetch-site") or "").lower()
    if fetch_site and fetch_site not in ("same-origin", "none"):
        return False
    origin = request.headers.get("origin") or ""
    if origin and origin != "null":
        host = request.headers.get("host") or ""
        return urlparse(origin).netloc.lower() == host.lower()
    return True


def start_session(user_id: int, ip: str = "", old_sid: str = "") -> str:
    """Ny sid ved hvert login. Den gamle sid (hvis den findes) slettes, saa en stjålet/fikseret sid er vaerdiloes."""
    sid = secrets.token_urlsafe(32)
    if old_sid:
        end_session(old_sid)
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
                "SELECT u.id, u.email, u.must_change_password, s.expires_at FROM sessions s "
                "JOIN users u ON u.id = s.user_id WHERE s.id=?", (key,)
            ).fetchone()
            if not row:
                return None
            if (row["expires_at"] or "") < now_iso():
                db.execute("DELETE FROM sessions WHERE id=?", (key,))
                return None
            db.execute("UPDATE sessions SET last_seen=? WHERE id=?", (now_iso(), key))
            return {"id": row["id"], "email": row["email"],
                    "must_change_password": bool(row["must_change_password"])}
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
    if any(path.startswith(p) for p in ("/login", "/cc-login", "/setup", "/health", "/static", "/mcp")):
        return await call_next(request)
    # CSRF: en muterende forespoergsel fra et andet site afvises. Browsere sender Sec-Fetch-Site
    # (og Origin) paa cross-site POST; kald uden de headers (scripts, API-noegler) roeres ikke.
    if request.method not in ("GET", "HEAD", "OPTIONS") and not _same_origin(request):
        return JSONResponse({"error": "cross-site forespoergsel afvist"}, status_code=403)
    if request.state.user:
        return await call_next(request)
    if path.startswith("/api/"):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return RedirectResponse("/setup" if user_count() == 0 else "/login", status_code=303)


@app.get("/setup", response_class=HTMLResponse)
async def setup_page(request: Request):
    if user_count() > 0:
        return RedirectResponse("/login", status_code=303)
    return templates.TemplateResponse("login.html", {"request": request, "mode": "setup", "error": "", "email": "",
                                                     "report": last_run_report(), "client_ip": client_ip(request),
                                                     "app_version": APP_VERSION})


@app.post("/setup")
async def setup_user(request: Request):
    """Foerste start: opret den foerste bruger (kun naar der ikke findes brugere)."""
    if user_count() > 0:
        return RedirectResponse("/login", status_code=303)
    form = await request.form()
    email = (form.get("email") or "").strip()
    password = form.get("password") or ""
    confirm = form.get("confirm") or ""
    err = ""
    user_id = None
    if password != confirm:
        err = "De to adgangskoder er ikke ens"
    else:
        try:
            user_id = create_user(email, password)
        except ValueError as e:
            err = str(e)
        except sqlite3.IntegrityError:
            err = "E-mailen er allerede oprettet - log ind i stedet"
    if not user_id:
        return templates.TemplateResponse("login.html", {"request": request, "mode": "setup", "email": email,
                                                         "error": err, "report": last_run_report(),
                                                         "client_ip": client_ip(request),
                                                         "app_version": APP_VERSION}, status_code=400)
    ip = client_ip(request)
    with get_db() as db:
        add_alarm(db, "brugere", f"Foerste bruger '{email}' oprettet", "info")
        db.execute("UPDATE users SET last_login_ip=?, last_login_at=? WHERE id=?", (ip, now_iso(), user_id))
    record_login(ip, email, True)
    return session_redirect(request, start_session(user_id, ip, request.cookies.get(SESSION_COOKIE) or ""))


@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if user_count() == 0:
        return RedirectResponse("/setup", status_code=303)
    cc_msg = ("Login-linket fra WordPress er allerede brugt eller udloebet (de holder 10 min.). "
              "Log ind med e-mail og adgangskode, og lav et nyt link i fanen Social.") if request.query_params.get("cc") else ""
    return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "error": cc_msg, "email": "",
                                                     "report": last_run_report(), "client_ip": client_ip(request),
                                                     "app_version": APP_VERSION})


@app.post("/login")
async def login(request: Request):
    ip = client_ip(request)
    now = time.time()
    fails, locked_until = _LOGIN_FAILS.get(ip, (0, 0.0))
    if locked_until > now:
        return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "email": "",
                                                         "error": "For mange fejlede logins - proev igen om " + str(int(locked_until - now)) + " sek."}, status_code=429)
    form = await request.form()
    email = (form.get("email") or form.get("username") or "").strip()   # username = gamle installationer
    password = form.get("password") or ""
    user = find_user(email)
    if user and verify_password(password, user["password_hash"]):
        _LOGIN_FAILS.pop(ip, None)
        with get_db() as db:
            db.execute("UPDATE users SET last_login_ip=?, last_login_at=? WHERE id=?", (ip, now_iso(), user["id"]))
        record_login(ip, email, True)
        return session_redirect(request, start_session(user["id"], ip, request.cookies.get(SESSION_COOKIE) or ""))
    record_login(ip, email, False)
    fails += 1
    _LOGIN_FAILS[ip] = (0, now + _LOGIN_LOCK_SECONDS) if fails >= _LOGIN_MAX_FAILS else (fails, locked_until)
    if len(_LOGIN_FAILS) > 2000:  # undgaa at listen vokser ubegraenset
        _LOGIN_FAILS.clear()
    return templates.TemplateResponse("login.html", {"request": request, "mode": "login", "email": email,
                                                     "error": "Forkert e-mail eller adgangskode", "ip": ip,
                                                     "report": last_run_report(), "client_ip": ip,
                                                     "app_version": APP_VERSION}, status_code=401)


@app.get("/logout")
async def logout(request: Request):
    end_session(request.cookies.get(SESSION_COOKIE) or "")
    resp = RedirectResponse("/login", status_code=303)
    resp.delete_cookie(SESSION_COOKIE)
    return resp


@app.post("/users/invite")
async def users_invite(request: Request, email: str = Form(...), force: str = Form("")):
    """Inviterer en bruger paa mail. Fejler SMTP, oprettes brugeren ikke - fejlen bliver en alarm
    og vises samtidig i formularen, saa en manglende mail ikke ser ud som en tabt mail.

    Adressen tjekkes foer SMTP: en pladsholder som navn@domaene.dk eller en adresse uden @ forklares
    i formularen i stedet for at blive en konto, ingen kan bruge. force=1 opretter alligevel, naar
    ejeren har bekræftet at adressen er rigtig."""
    raw = (email or "").strip()
    try:
        clean = normalize_email(raw)
    except ValueError as e:
        with get_db() as db:
            add_alarm(db, "brugere", f"Invitation til '{raw[:64]}' blev ikke sendt: {str(e)[:160]}", "advarsel")
        return RedirectResponse(invite_redirect(False, str(e), email=raw, kind="adresse"), status_code=303)
    hint = example_email_hint(clean)
    if hint and not force.strip():
        msg = f"'{clean}' ligner eksemplet fra dokumentationen ({hint}) - skriv den rigtige adresse"
        with get_db() as db:
            add_alarm(db, "brugere", f"Invitation til '{clean[:64]}' blev ikke sendt: {msg[:160]}", "advarsel")
        return RedirectResponse(invite_redirect(False, msg, email=clean, kind="eksempel"), status_code=303)
    ok, err = invite_user(clean, str(request.base_url).rstrip("/"), allow_example=bool(force.strip()))
    if not ok:
        with get_db() as db:
            add_alarm(db, "brugere", f"Invitation til '{clean[:64]}' blev ikke sendt: {str(err)[:160]}", "advarsel")
        return RedirectResponse(invite_redirect(False, err, email=clean, kind="smtp"), status_code=303)
    return RedirectResponse(invite_redirect(True, clean), status_code=303)


@app.post("/users/delete")
async def users_delete(request: Request, id: str = Form("")):
    """Sletter en bruger - og svarer i fanen Brugere, hvor knappen blev trykket.

    id tages som tekst, saa et tomt eller forkert id bliver en forklaring i formularen i stedet for
    et 422-svar uden tekst. En afvist sletning (sidste bruger, ukendt id) aendrer intet i listen og
    bliver baade en alarm og en besked i fanen."""
    me = getattr(request.state, "user", None)
    raw = (id or "").strip()
    try:
        uid = int(raw)
        if uid <= 0:
            raise ValueError
    except ValueError:
        msg = f"'{raw[:32]}' er ikke et bruger-id - der blev ikke slettet noget"
        with get_db() as db:
            add_alarm(db, "brugere", f"Sletning afvist: {msg[:160]}", "advarsel")
        return RedirectResponse(users_delete_redirect(False, msg, kind="ugyldig"), status_code=303)
    with get_db() as db:
        row = db.execute("SELECT email FROM users WHERE id=?", (uid,)).fetchone()
        total = db.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]
        if not row:
            msg = f"Der findes ingen bruger med id {uid} - den kan allerede vaere slettet"
            add_alarm(db, "brugere", f"Sletning afvist: {msg[:160]}", "advarsel")
            return RedirectResponse(users_delete_redirect(False, msg, kind="findes-ikke"), status_code=303)
        email = row["email"]
        if total <= 1:
            msg = f"'{email}' er den sidste bruger og kan ikke slettes - opret en ny bruger foerst"
            add_alarm(db, "brugere", f"Sletning afvist: {msg[:160]}", "advarsel")
            return RedirectResponse(users_delete_redirect(False, msg, kind="sidste", email=email), status_code=303)
        db.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
        db.execute("DELETE FROM users WHERE id=?", (uid,))
        add_alarm(db, "brugere", f"Brugeren '{email}' blev slettet", "info")
    if me and me["id"] == uid:
        resp = RedirectResponse("/login", status_code=303)
        resp.delete_cookie(SESSION_COOKIE)
        return resp
    return RedirectResponse(users_delete_redirect(True, "", kind="slettet", email=email), status_code=303)


@app.post("/users/password")
async def users_password(request: Request, current: str = Form(...), new: str = Form(...), confirm: str = Form("")):
    me = getattr(request.state, "user", None)
    if not me:
        return RedirectResponse("/login", status_code=303)
    with get_db() as db:
        row = db.execute("SELECT password_hash FROM users WHERE id=?", (me["id"],)).fetchone()
        if not row or not verify_password(current, row["password_hash"]):
            add_alarm(db, "brugere", f"Fejlet adgangskode-skift for '{me['email']}'", "info")
            return RedirectResponse("/", status_code=303)
        if new != confirm or len(new) < MIN_PASSWORD_LEN:
            add_alarm(db, "brugere", f"Adgangskode-skift afvist for '{me['email']}': mindst {MIN_PASSWORD_LEN} tegn og ens i begge felter", "info")
            return RedirectResponse("/", status_code=303)
        db.execute("UPDATE users SET password_hash=?, must_change_password=0 WHERE id=?", (hash_password(new), me["id"]))
        # Log de andre sessioner ud, behold denne.
        db.execute("DELETE FROM sessions WHERE user_id=? AND id<>?",
                   (me["id"], _session_key(request.cookies.get(SESSION_COOKIE) or "")))
    try:  # standardbrugeren skiftede kode: saa skal .env-linjen ikke love den gamle
        clear_env_admin_password(me["email"])
    except Exception as e:
        print("[cc] .env: kunne ikke rydde CC_ADMIN_PASSWORD:", repr(e), flush=True)
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
    assert_public_url(url)          # SSRF: afvises foer URL'en gemmes eller hentes
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


# ---------- SSRF-beskyttelse (v7.19.0) ----------
# Alle udgaaende kald med en brugerangivet URL gaar gennem safe_request(), saa guarden staar ét sted:
# loopback, private net, link-local (169.254.169.254 = sky-metadata), reserverede og multicast-adresser
# afvises, og viderestillinger valideres hop for hop - ellers kunne en 302 pege ind i det lokale net.
# CC_SSRF_ALLOW=a, b aabner for enkelte vaertsnavne (fx en intern WooCommerce under udvikling).
SSRF_ALLOW_HOSTS = [h.strip().lower() for h in (os.getenv("CC_SSRF_ALLOW") or "").split(",") if h.strip()]


class BlockedURL(ValueError):
    """En URL der peger ind i det lokale net - afvist foer der hentes noget."""


def _ip_is_public(ip) -> bool:
    return not (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved
                or ip.is_multicast or ip.is_unspecified)


def assert_public_url(url: str) -> str:
    """SSRF-guard: afviser URL'er der peger paa det lokale net. Rejser BlockedURL (en ValueError)."""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise BlockedURL("Kun http:// og https:// er tilladt")
    host = (parsed.hostname or "").strip().lower()
    if not host:
        raise BlockedURL("URL mangler et vaertsnavn")
    bare = host.strip("[]")
    if bare in SSRF_ALLOW_HOSTS:
        return url
    if bare == "localhost" or bare.endswith((".localhost", ".local", ".internal", ".home.arpa")):
        raise BlockedURL(f"{bare} er en intern adresse")
    try:
        if not _ip_is_public(ipaddress.ip_address(bare)):
            raise BlockedURL(f"{bare} er en intern adresse")
        return url
    except ValueError as e:
        if isinstance(e, BlockedURL):
            raise
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        infos = socket.getaddrinfo(bare, port, proto=socket.IPPROTO_TCP)
    except OSError:
        raise BlockedURL(f"Vaertsnavnet {bare} kan ikke slaaes op")
    for info in infos:
        try:
            ip = ipaddress.ip_address(info[4][0])
        except ValueError:
            continue
        if not _ip_is_public(ip):
            raise BlockedURL(f"{bare} peger paa en intern adresse ({ip})")
    return url


def safe_request(url: str, timeout: int = 6, max_redirects: int = 3):
    """Henter en URL efter SSRF-tjek - ogsaa for hvert viderestillingshop."""
    current = assert_public_url(url)
    for _ in range(max_redirects + 1):
        response = HTTP.get(
            current,
            timeout=timeout,
            allow_redirects=False,
            headers={"User-Agent": "Mozilla/5.0 CommandCenter/7.19"},
        )
        location = response.headers.get("location") or ""
        if response.status_code in (301, 302, 303, 307, 308) and location:
            current = assert_public_url(urllib.parse.urljoin(current, location))
            continue
        return response
    raise BlockedURL("For mange viderestillinger")


def now_iso():
    return datetime.now().isoformat(timespec="seconds")


# ---------- Tider: lokal tid + UTC ----------
CC_TZ_NAME = (os.getenv("CC_TZ") or "Europe/Copenhagen").strip()
try:
    CC_TZ = ZoneInfo(CC_TZ_NAME)
except Exception:
    CC_TZ, CC_TZ_NAME = ZoneInfo("Europe/Copenhagen"), "Europe/Copenhagen"


def now_utc_iso():
    """UTC som ISO-streng - gemmes ved siden af den lokale tid, saa den er entydig."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def local_to_utc(value):
    """'YYYY-MM-DDTHH:MM[:SS]' i CC_TZ -> ISO-UTC.

    Rejser ValueError ved tom, ugyldig eller ikke-eksisterende tid (sommertid). En tvetydig tid
    (efteraar, hvor klokken gaar tilbage) giver den foerste forekomst - det er et valg, ikke en
    tilfaeldighed, og det er derfor tiden ALTID gemmes som UTC ved siden af.
    """
    text = (value or "").strip().replace(" ", "T")
    if not text:
        raise ValueError("tomt tidspunkt")
    naive = None
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d"):
        try:
            naive = datetime.strptime(text, fmt)
            break
        except ValueError:
            continue
    if naive is None:
        raise ValueError("forventer YYYY-MM-DDTHH:MM")
    local = naive.replace(tzinfo=CC_TZ, fold=0)
    if local.astimezone(timezone.utc).astimezone(CC_TZ).replace(tzinfo=None) != naive:
        raise ValueError(f"{naive:%Y-%m-%d %H:%M} findes ikke i {CC_TZ_NAME} (sommertid)")
    return local.astimezone(timezone.utc).isoformat(timespec="seconds")


def utc_to_local(value):
    """ISO-UTC -> 'YYYY-MM-DDTHH:MM:SS' i CC_TZ. Ukendt format returneres uaendret."""
    if not value:
        return ""
    try:
        moment = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return str(value)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(CC_TZ).replace(tzinfo=None).isoformat(timespec="seconds")


def social_payload(post, channel, title, message):
    """Payload til Social Autopilot. Planlagt tid sendes som UTC + lokal + zone, saa modtageren
    ikke skal gaette. Opslag uden planlagt tid faar ingen tidsfelter."""
    body = {"channel": channel, "title": title, "body": message, "ai_model": "command-center"}
    scheduled_utc = (post["scheduled_at_utc"] if "scheduled_at_utc" in post.keys() else "") if hasattr(post, "keys") else ""
    if scheduled_utc:
        body["scheduled_at_utc"] = scheduled_utc
        body["scheduled_at_local"] = (post["scheduled_at"] if "scheduled_at" in post.keys() else "") or ""
        body["timezone"] = CC_TZ_NAME
    return body


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


def send_email(to: str, subject: str, body: str) -> tuple:
    """Sender én mail til en konkret modtager (alarmer gaar til SMTP_TO, invitationer til brugeren)."""
    if not (SMTP_HOST and SMTP_FROM):
        return False, "SMTP_HOST / SMTP_FROM mangler i .env - der blev ikke sendt noget"
    if not to:
        return False, "Modtager mangler"
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM
    msg["To"] = to
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


def _send_email_alert(subject: str, body: str, severity: str) -> tuple:
    if not (SMTP_HOST and SMTP_TO and SMTP_FROM):
        return False, "SMTP_HOST / SMTP_FROM / SMTP_TO mangler"
    return send_email(SMTP_TO, subject, body)


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
    "/growth/optimize": {"label": "Indholdsoptimering", "seconds": 12},
    "/growth/compare": {"label": "Konkurrent-sammenligning", "seconds": 20},
    "/growth/brief": {"label": "Indholds-brief", "seconds": 15},
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
async def add_social_post(platform: str = Form(...), message: str = Form(...),
                          scheduled_at: str = Form("")):
    """Tilfoejer et opslag. En planlagt tid indtastes i lokal tid, gemmes som lokal + UTC og
    afvises hvis den ikke findes (sommertid) - ellers ville opslaget blive udgivet forkert."""
    if platform.strip() and message.strip():
        scheduled_local = scheduled_utc = error = ""
        if scheduled_at.strip():
            try:
                scheduled_utc = local_to_utc(scheduled_at)
                scheduled_local = utc_to_local(scheduled_utc)
            except ValueError as e:
                error = str(e)
        with get_db() as db:
            if error:
                add_alarm(db, "social",
                          f"Opslag ikke gemt: tidspunktet '{scheduled_at}' blev afvist ({error})",
                          "advarsel")
            else:
                db.execute(
                    "INSERT INTO socialqueue "
                    "(platform, message, status, created_at, created_at_utc, scheduled_at, scheduled_at_utc) "
                    "VALUES (?,?,?,?,?,?,?)",
                    (platform.strip(), message.strip(),
                     "Planlagt" if scheduled_utc else "Klar i ko",
                     now_iso(), now_utc_iso(), scheduled_local, scheduled_utc),
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
    writer.writerow(["platform", "message", "status", "created_at", "created_at_utc",
                     "scheduled_at", "scheduled_at_utc", "timezone"])
    with get_db() as db:
        for row in db.execute(
            "SELECT platform, message, status, created_at, created_at_utc, scheduled_at, scheduled_at_utc "
            "FROM socialqueue ORDER BY id"
        ).fetchall():
            writer.writerow([row["platform"], row["message"], row["status"], row["created_at"],
                             row["created_at_utc"], row["scheduled_at"], row["scheduled_at_utc"],
                             CC_TZ_NAME])
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


def sgap_headers() -> dict:
    """Headerne paa hvert kald til pluginnet.

    X-Command-Center goer at WordPress kan se, hvem der kalder (SGAP_CC::note_call): pluginnet
    noterer tidsstempel, version, rute og bruger i optionen sgap_cc_seen og svarer med det i
    /snapshot. Uden headeren ville WordPress altid mene, at Command Center aldrig havde kaldt."""
    return {"X-Command-Center": APP_VERSION}


def sgap_api(method: str, path: str, **kwargs):
    """Kald pluginnets REST-API. Kaster requests.HTTPError ved fejl-svar."""
    kwargs["headers"] = {**sgap_headers(), **(kwargs.get("headers") or {})}
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


# ---------- Engangslink til login fra WordPress (Steamgears Autopilot) ----------
# Broen er envejs (CC -> site, fordi CC kun lytter paa 127.0.0.1). Knappen i WordPress kan derfor
# ikke selv spoerge CC om noget: CC laver et faerdigt engangslink og laegger det i pluginnet, som
# viser knappen. Koden gemmes kun som sha256, kan bruges én gang og udloeber efter CC_LOGIN_TTL.
CC_LOGIN_TTL = 600
CC_LOGIN_KEY = "cc_login_code"


def cc_login_issue(user_id: int) -> str:
    """Laver en engangskode til brugeren og gemmer hashen (koden findes kun i linket)."""
    code = secrets.token_urlsafe(32)
    with get_db() as db:
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                   (CC_LOGIN_KEY, jsonlib.dumps({"hash": hashlib.sha256(code.encode()).hexdigest(),
                                                 "user_id": int(user_id),
                                                 "exp": int(time.time()) + CC_LOGIN_TTL})))
    return code


def cc_login_consume(code: str):
    """Returnerer user_id for en gyldig kode - og sletter den i samme kald (engangsbrug).

    Koden slettes foerst naar den er godkendt, saa et forkert gaet ikke kan braende ejerens link."""
    code = (code or "").strip()
    if not code:
        return None
    digest = hashlib.sha256(code.encode()).hexdigest()
    with get_db() as db:
        row = db.execute("SELECT value FROM settings WHERE key=?", (CC_LOGIN_KEY,)).fetchone()
        if not row or not row["value"]:
            return None
        try:
            data = jsonlib.loads(row["value"])
        except Exception:
            return None
        if not isinstance(data, dict) or int(data.get("exp") or 0) < int(time.time()):
            return None
        if not hmac.compare_digest(str(data.get("hash") or ""), digest):
            return None
        db.execute("DELETE FROM settings WHERE key=?", (CC_LOGIN_KEY,))
    return int(data.get("user_id") or 0) or None


# Idempotens for "-> Autopilot": statusfeltet er laasen. Samme opslag maa kun give EN kladde,
# ogsaa hvis brugeren dobbeltklikker eller proever igen efter et tabt svar.
SOCIAL_SENT = "sendt til autopilot"
SOCIAL_SENDING = "sender til autopilot"
SOCIAL_UNCERTAIN = "sendt? (svar udeblev)"


def social_claim(db, post_id: int) -> bool:
    """Atomisk laas paa raekken: True kun hvis opslaget hverken er sendt eller undervejs."""
    cur = db.execute(
        """UPDATE socialqueue SET status = ?
           WHERE id = ?
             AND COALESCE(status, '') NOT LIKE ?
             AND COALESCE(status, '') NOT IN (?, ?)""",
        (SOCIAL_SENDING, post_id, SOCIAL_SENT + "%", SOCIAL_SENDING, SOCIAL_UNCERTAIN),
    )
    return cur.rowcount == 1


def sgap_snapshot() -> dict:
    with get_db() as db:
        row = db.execute("SELECT value FROM settings WHERE key='sgap_snapshot'").fetchone()
    try:
        return jsonlib.loads(row["value"]) if row and row["value"] else {}
    except Exception:
        return {}


# ---------- Naar WordPress sidst hoerte fra Command Center ----------
# Pluginnet noterer hvert CC-kald i optionen sgap_cc_seen og svarer med det i /snapshot. Samme tal
# staar i WordPress-kortet (SGAP_CC::last_call), saa de to sider ikke viser hver sin sandhed.
CC_SEEN_LATE = 45 * 60       # en 30-minutters-sync misset
CC_SEEN_STALE = 2 * 60 * 60  # tre misset: saa er broen sandsynligvis brudt


def cc_age_text(seconds: int) -> str:
    """Alder i ord paa dansk: 'lige nu', '12 min.', '3 t 4 min.', '2 dage'."""
    seconds = max(0, int(seconds))
    if seconds < 60:
        return "lige nu"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes} min."
    hours = minutes // 60
    if hours < 24:
        rest = minutes % 60
        return f"{hours} t" + (f" {rest} min." if rest else "")
    days = hours // 24
    return "1 dag" if days == 1 else f"{days} dage"


def cc_seen_view(sgap: dict, now: float | None = None) -> dict:
    """WordPress' eget svar paa, hvornaar det sidst hoerte fra Command Center.

    Alderen regnes ud her og nu (ikke ved synken), saa tallet ikke fryser mellem to kald. 'known'
    er False, naar pluginnet ikke svarer med /snapshot endnu (Steamgears Autopilot < 7.33)."""
    sgap = sgap or {}
    view = {"known": False, "state": "ukendt", "ts": None, "age": None, "when": "",
            "headline": "WordPress svarer ikke med Command Center-status endnu",
            "hint": "Alder paa sidste CC-kald kraever Steamgears Autopilot 7.33+ - opdater pluginnet.",
            "tone": "muted", "detail": "", "last_seen": "", "version": "", "route": "", "user": "",
            "checked_at": sgap.get("checked_at") or ""}
    cc = sgap.get("command_center") or {}
    try:
        ts = int(cc.get("ts"))
    except (TypeError, ValueError):
        return view
    age = max(0, int((time.time() if now is None else now) - ts))
    if age <= CC_SEEN_LATE:
        state, tone = "live", "ok"
    elif age <= CC_SEEN_STALE:
        state, tone = "sent", "warn"
    else:
        state, tone = "tavs", "fejl"
    view.update({
        "known": True, "state": state, "ts": ts, "age": age, "tone": tone,
        "when": "lige nu" if age < 60 else f"for {cc_age_text(age)} siden",
        "last_seen": str(cc.get("last_seen") or ""),
        "version": str(cc.get("version") or ""),
        "route": str(cc.get("last_route") or ""),
        "user": str(cc.get("user") or ""),
    })
    view["headline"] = ("WordPress hoerte fra Command Center " if age < 60
                        else "WordPress hoerte sidst fra Command Center ") + view["when"]
    facts = [(("v" + view["version"]) if view["version"] else ""), view["route"],
             (("som " + view["user"]) if view["user"] else "")]
    view["detail"] = " - ".join([f for f in facts if f])
    if state == "live":
        view["hint"] = "Broen virker: WordPress noterer hvert kald fra CC. Kortet i WordPress viser samme tal."
    elif state == "sent":
        view["hint"] = "En sync-runde er misset - naeste kald kommer om lidt. Kortet i WordPress viser samme tal."
    else:
        view["hint"] = ("WordPress har ikke hoert fra Command Center i over 2 timer. Tjek at WordPress "
                        "koerer, og at WP_URL, WP_USER og WP_APP_PASSWORD stadig passer.")
    return view


def sgap_sync() -> dict:
    """Henter status fra pluginnet, gemmer et snapshot og alarmerer ved nye fejl eller nye kladder."""
    if not sgap_ready():
        return {}
    previous = sgap_snapshot()
    snap = {"checked_at": now_iso(), "ok": False, "error": "", "queue": {}, "channels": [], "pending_drafts": 0}
    try:
        try:
            # Nyere plugins har /snapshot: alt i ét kald, inkl. selvtjek, cron-forsinkelse og pause-aarsag.
            doc = sgap_api("GET", "/snapshot", params={"days": 30, "limit": 20})
            snap.update(sgap_from_snapshot(doc))
            # Samme svar fortæller, hvornaar WordPress sidst hørte fra CC (SGAP_CC::status()).
            cc_seen = ((doc or {}).get("status") or {}).get("command_center") or {}
            if isinstance(cc_seen, dict) and cc_seen.get("ts"):
                snap["command_center"] = {k: cc_seen.get(k) for k in
                                          ("state", "ts", "age", "version", "last_route", "user", "last_seen")}
            else:
                snap.pop("command_center", None)
            snap["ok"] = True
        except requests.HTTPError as e:
            if getattr(e.response, "status_code", None) != 404:
                raise
            snap.update(sgap_from_stats())
            snap.pop("command_center", None)
            snap["ok"] = True
    except Exception as e:
        snap["error"] = sgap_error_text(e)
    sgap_store(snap, previous)
    return snap


def sgap_from_snapshot(data: dict) -> dict:
    """Oversaet pluginnets /snapshot til det format dashboardet og alarmerne bruger."""
    status = data.get("status") or {}
    counts = data.get("counts") or {}
    channels = []
    for r in (data.get("results") or {}).get("by_channel") or []:
        channels.append({
            "channel": r.get("channel"),
            "publish": int(r.get("published") or 0),
            "click": int(r.get("clicks") or 0),
            "order": int(r.get("orders") or 0),
            "revenue": round(float(r.get("revenue") or 0), 2),
        })
    check = status.get("last_self_check") or {}
    return {
        "source": "snapshot",
        "version": data.get("version") or "",
        "queue": {k: int(v) for k, v in (counts.get("queue") or {}).items()},
        "pending_drafts": int((counts.get("drafts") or {}).get("pending", 0)),
        "channels": sorted(channels, key=lambda c: (-c["revenue"], -c["click"])),
        "autopilot": bool(status.get("autopilot")),
        "full_auto": bool(status.get("full_auto")),
        "paused_because": status.get("sending_paused_because") or "",
        "cron_lag_minutes": int(status.get("cron_lag_minutes") or 0),
        "problems": [str(p) for p in (check.get("problems") or [])][:10],
        "self_check_at": check.get("at") or "",
        "missing_tables": list(data.get("missing_tables") or []),
    }


def sgap_from_stats() -> dict:
    """Reserve for plugins uden /snapshot (aeldre end 7.5)."""
    stats = sgap_api("GET", "/stats", params={"days": 30})
    drafts = sgap_api("GET", "/drafts", params={"status": "pending", "limit": 100})
    snap = {"source": "stats"}
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
    return snap


def sgap_store(snap: dict, previous: dict) -> None:
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
            # Pluginnets eget selvtjek: alarm kun for NYE problemer, saa samme tekst ikke sendes hver halve time.
            for problem in snap.get("problems", []):
                if problem not in previous.get("problems", []):
                    add_alarm(db, "autopilot", f"Autopilot-selvtjek: {problem}", "advarsel")
            if snap.get("missing_tables") and snap["missing_tables"] != previous.get("missing_tables"):
                add_alarm(db, "autopilot", "Autopilot mangler tabeller: " + ", ".join(snap["missing_tables"]) + " - genaktiver pluginnet", "kritisk")


def wp_cron_ping() -> int:
    """Kald wp-cron.php, saa pluginnets job koerer til tiden selvom sitet har faa besoeg. Returnerer HTTP-status."""
    resp = HTTP.get(f"{WP_URL.rstrip('/')}/wp-cron.php", params={"doing_wp_cron": f"{time.time():.4f}"},
                    headers={"X-Command-Center": APP_VERSION}, timeout=15)
    return resp.status_code


async def job_wp_cron():
    if not sgap_ready():
        return
    try:
        await asyncio.get_running_loop().run_in_executor(executor, wp_cron_ping)
    except Exception:
        pass  # sitet nede fanges af sgap_sync og monitorerne; et tabt ping skal ikke give alarm


async def job_sgap_sync():
    if not sgap_ready():
        return
    await asyncio.get_running_loop().run_in_executor(executor, sgap_sync)


@app.post("/autopilot/sync")
async def autopilot_sync_now():
    await asyncio.get_running_loop().run_in_executor(executor, sgap_sync)
    return RedirectResponse("/", status_code=303)


@app.post("/autopilot/login-link")
async def autopilot_login_link(request: Request):
    """Laegger et engangslink til Command Center i WordPress-pluginnet.

    Knappen i WordPress kan ikke selv kalde CC (CC lytter kun paa 127.0.0.1), saa CC laegger linket
    derud, hvor knappen er - og svarer i fanen Social, hvor der blev trykket."""
    me = getattr(request.state, "user", None)
    if not me:
        return RedirectResponse("/login", status_code=303)
    if not sgap_ready():
        return RedirectResponse("/?tab=social&cc_link=fejl&cc_msg=" + urllib.parse.quote(
            "WP_URL/WP_USER/WP_APP_PASSWORD mangler, eller modulet Autopilot-bro er slukket"), status_code=303)
    base = (CC_PUBLIC_URL or str(request.base_url)).rstrip("/")
    code = cc_login_issue(me["id"])
    try:
        sgap_api("POST", "/login-link", json={"url": f"{base}/cc-login?code={urllib.parse.quote(code)}",
                                             "expires_in": CC_LOGIN_TTL, "user": me["email"]})
    except Exception as e:
        return RedirectResponse("/?tab=social&cc_link=fejl&cc_msg="
                                + urllib.parse.quote(sgap_error_text(e)), status_code=303)
    return RedirectResponse("/?tab=social&cc_link=ok&cc_msg=" + urllib.parse.quote(
        "Engangslinket ligger nu i WordPress i 10 min. - aabn Steamgears der, og tryk Log ind paa Command Center"),
        status_code=303)


@app.get("/cc-login")
async def cc_login(request: Request, code: str = ""):
    """Logger ind med engangskoden fra WordPress-knappen (bruges én gang, holder 10 min.)."""
    user_id = cc_login_consume(code)
    if not user_id:
        return RedirectResponse("/login?cc=udloebet", status_code=303)
    ip = client_ip(request)
    with get_db() as db:
        user = db.execute("SELECT id, email FROM users WHERE id=?", (user_id,)).fetchone()
        if user:
            db.execute("UPDATE users SET last_login_ip=?, last_login_at=? WHERE id=?", (ip, now_iso(), user_id))
    if not user:
        return RedirectResponse("/login?cc=udloebet", status_code=303)
    record_login(ip, user["email"], True)
    return session_redirect(request, start_session(user["id"], ip, request.cookies.get(SESSION_COOKIE) or ""))


@app.post("/social/to-autopilot")
async def social_to_autopilot(id: int = Form(...)):
    """Send et opslag fra CC's sociale koe til pluginnet som AI-kladde (godkendes i WordPress)."""
    with get_db() as db:
        post = db.execute(
            "SELECT platform, message, status, scheduled_at, scheduled_at_utc FROM socialqueue WHERE id=?", (id,)
        ).fetchone()
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

    # Laas raekken FOER kaldet. Uden laasen giver et dobbeltklik - eller et genforsoeg efter et
    # tabt svar - to kladder i WordPress til det samme opslag.
    with get_db() as db:
        if not social_claim(db, id):
            return RedirectResponse("/", status_code=303)

    def send():
        return sgap_api("POST", "/drafts", json=social_payload(post, channel, title, message))

    try:
        result = await asyncio.get_running_loop().run_in_executor(executor, send)
        with get_db() as db:
            db.execute("UPDATE socialqueue SET status=? WHERE id=?", (f"{SOCIAL_SENT} (kladde #{result.get('id')})", id))
    except Exception as e:
        # Svar fra WordPress = kladden blev ikke oprettet -> slip raekken, saa den kan sendes igen.
        # Timeout/forbindelsesfejl = vi ved ikke om den blev oprettet -> bloker for gensend.
        uncertain = isinstance(e, (requests.exceptions.Timeout, requests.exceptions.ConnectionError))
        with get_db() as db:
            db.execute("UPDATE socialqueue SET status=? WHERE id=?",
                       (SOCIAL_UNCERTAIN if uncertain else (post["status"] or ""), id))
            if uncertain:
                add_alarm(db, "autopilot",
                          f"Opslaget blev sendt, men svaret udeblev ({sgap_error_text(e)}). "
                          "Tjek AI Drafts i WordPress foer du sender igen",
                          "advarsel")
            else:
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


# ---------- v7.23 Backup/restore i UI ----------
BACKUP_NAME_RE = re.compile(r"^cc-[a-z0-9-]{1,32}-\d{8}-\d{4}\.db$")


def _backup_path(name: str):
    """Sti til en backupfil - kun hvis navnet matcher det faste format (ingen stier, ingen '..')."""
    if not BACKUP_NAME_RE.fullmatch(name or ""):
        return None
    bdir = os.path.abspath(os.path.join(BASE_DIR, "backups"))
    p = os.path.join(bdir, name)
    if os.path.dirname(os.path.abspath(p)) != bdir or not os.path.isfile(p):
        return None
    return p


def list_backups():
    """Alle gyldige backupfiler, nyeste først."""
    bdir = os.path.join(BASE_DIR, "backups")
    out = []
    try:
        names = os.listdir(bdir)
    except OSError:
        return out
    for n in names:
        p = _backup_path(n)
        if not p:
            continue
        st = os.stat(p)
        out.append({"name": n, "size_kb": round(st.st_size / 1024),
                    "mtime": datetime.fromtimestamp(st.st_mtime).strftime("%d-%m-%Y %H:%M")})
    return sorted(out, key=lambda b: b["name"], reverse=True)


def _check_backup_file(path: str):
    """Er filen en brugbar CC-database? Returnerer en dansk fejltekst eller None."""
    try:
        conn = sqlite3.connect("file:" + path + "?mode=ro", uri=True)
        try:
            res = conn.execute("PRAGMA integrity_check").fetchone()
            has_users = conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='users'").fetchone()
        finally:
            conn.close()
    except sqlite3.Error as e:
        return "filen kan ikke læses som database: " + str(e)[:80]
    if not res or res[0] != "ok":
        return "integritetstjek fejlede"
    if not has_users:
        return "filen er ikke en Command Center-database (mangler tabellen users)"
    return None


def restore_backup_sync(name: str):
    """Gendanner en backup. Tager altid en pre-restore-kopi først; fejler den, sker der intet."""
    p = _backup_path(name)
    if not p:
        return False, "ugyldigt backupnavn - der blev ikke gendannet noget"
    err = _check_backup_file(p)
    if err:
        return False, "'" + name + "' kan ikke gendannes: " + err
    safety = backup_db_sync(tag="pre-restore")
    if not safety:
        return False, "sikkerhedskopi før gendannelse fejlede - der blev ikke gendannet noget"
    try:
        src = sqlite3.connect(p)
        dst = sqlite3.connect(DB_PATH)
        try:
            src.backup(dst)
        finally:
            dst.close()
            src.close()
    except sqlite3.Error as e:
        return False, "gendannelsen fejlede: " + str(e)[:120]
    with get_db() as db:
        add_alarm(db, "backup", "Databasen blev gendannet fra '" + name + "' (før-kopi: '"
                  + os.path.basename(safety) + "')", "kritisk")
    return True, name


def backup_redirect(ok: bool, text: str) -> str:
    state = "ok" if ok else "fejl"
    return "/?tab=moduler&bk=" + state + "&bk_msg=" + urllib.parse.quote((text or "").strip()[:180])


@app.post("/backup/now")
async def backup_now(request: Request):
    loop = asyncio.get_running_loop()
    path = await loop.run_in_executor(executor, backup_db_sync, "manuel")
    if not path:
        return RedirectResponse(backup_redirect(False, "backup fejlede - se alarmer"), status_code=303)
    return RedirectResponse(backup_redirect(True, "Backup gemt: " + os.path.basename(path)), status_code=303)


@app.post("/backup/restore")
async def backup_restore(request: Request, name: str = Form(""), confirm: str = Form("")):
    if (confirm or "").strip() != "GENDAN":
        return RedirectResponse(backup_redirect(False, "skriv GENDAN for at bekræfte - der blev ikke gendannet noget"), status_code=303)
    loop = asyncio.get_running_loop()
    ok, msg = await loop.run_in_executor(executor, restore_backup_sync, (name or "").strip())
    if not ok:
        with get_db() as db:
            add_alarm(db, "backup", "Gendannelse afvist: " + msg[:160], "advarsel")
        return RedirectResponse(backup_redirect(False, msg), status_code=303)
    return RedirectResponse(backup_redirect(True, "Databasen er gendannet fra " + msg), status_code=303)


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
                db.execute("INSERT INTO socialqueue (platform, message, created_at, created_at_utc) "
                           "VALUES (?,?,?,?)",
                           ("auto: " + art["keyword"], post, now_iso(), now_utc_iso()))
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


# ---------- Vækst (v7.24): lokal SEO-optimering uden API-nøgle ----------
# Surfer, Ahrefs, Semrush og BabyLoveGrowth gør tre ting: måler indhold mod et termsæt,
# sammenligner med konkurrenter og holder en plan. Det kan gøres lokalt: vi tæller ord og termer
# selv, henter konkurrenternes sider med safe_request() og gemmer planen i SQLite. Ingen nøgle,
# ingen eksterne AI-kald - og ingen påstand om søgevolumen eller backlink-data, vi ikke har.
CONTENT_MAX_CHARS = 200_000
COMPETITOR_MAX = 3
CONTENT_DEFAULT_WORDS = 800
BRIEF_STATUS = ("Planlagt", "Skrevet", "Publiceret", "Fravalgt")
LINK_STATUS = ("Ny", "Kontaktet", "Link aftalt", "Link live", "Afvist")
LINK_TYPES = ("Gæsteblog", "Ressourceside", "Nyhedsmedie", "Forum", "Katalog", "Partner", "Andet")

# Danske og engelske funktionsord - de siger intet om emnet og ville fylde termlisten op.
CONTENT_STOPWORDS = set("""
og i jeg det at en den til er som på de med han af for ikke der var mig sig men et har om vi min
havde ham hun nu over da fra du ud sin dem os op man hans hvor eller hvad skal selv her alle vil
blev kunne ind når være dog noget ville jo deres efter ned skulle denne end dette mit også under
have dig anden hende mine alt meget sit sine vor mod disse hvis din nogle hos blive mange ad
bliver hendes været thi jer sådan mellem uden mere mindre stor stort små godt god dårlig
the a an and or but if then than that this these those is are was were be been being of to in
on at for from with without by as it its into about over under not no yes you your we our they
their he she his her him them me my mine who whom which what when where why how all any both
each few more most other some such only own same so too very can will just should now here
there also may might must shall do does did done has have had having out up down off again
""".split())


def content_text(html: str) -> str:
    """Synlig tekst fra HTML - scripts, styles og skabeloner tæller ikke med."""
    soup = BeautifulSoup(html or "", "html.parser")
    for tag in soup(["script", "style", "noscript", "template"]):
        tag.decompose()
    return soup.get_text(" ", strip=True)


def content_words(text: str) -> list:
    return re.findall(r"[\w\u00C0-\u024F']+", (text or "").lower())


def content_term_counts(text: str) -> dict:
    counts = {}
    for word in content_words(text):
        word = word.strip("'")
        if len(word) < 3 or word in CONTENT_STOPWORDS or word.isdigit():
            continue
        counts[word] = counts.get(word, 0) + 1
    return counts


def content_top_terms(text: str, limit: int = 12) -> list:
    counts = content_term_counts(text)
    ordered = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    return [{"term": t, "count": n} for t, n in ordered[:limit]]


def parse_term_list(raw: str, limit: int = 25) -> list:
    """'a, b; c' -> ['a', 'b', 'c'] (små bogstaver, uden dubletter)."""
    out = []
    for part in re.split(r"[,;\n]+", raw or ""):
        term = re.sub(r"\s+", " ", part.strip().lower())
        if term and term not in out:
            out.append(term)
    return out[:limit]


def term_stats(text: str, term: str, words: int = 0) -> dict:
    """Antal forekomster og tæthed for et ord eller en frase (hele ord, ikke delstrenge)."""
    term = re.sub(r"\s+", " ", (term or "").strip().lower())
    if not term:
        return {"term": "", "count": 0, "density": 0.0, "present": False}
    pattern = r"(?<![\w\u00C0-\u024F])" + re.escape(term) + r"(?![\w\u00C0-\u024F])"
    count = len(re.findall(pattern, (text or "").lower()))
    wc = words or len(content_words(text))
    density = round(count * max(len(term.split()), 1) / max(wc, 1) * 100, 2)
    return {"term": term, "count": count, "density": density, "present": count > 0}


def content_profile(html: str, url: str = "") -> dict:
    """Det vi kan måle på en side uden hjælp udefra: ord, overskrifter, links og toptermer."""
    soup = BeautifulSoup(html or "", "html.parser")
    title_tag = soup.find("title")
    title = title_tag.get_text(" ", strip=True) if title_tag else ""
    meta_tag = soup.find("meta", attrs={"name": "description"})
    meta = (meta_tag.get("content") or "").strip() if meta_tag else ""
    h1 = [h.get_text(" ", strip=True) for h in soup.find_all("h1")]
    h2 = [h.get_text(" ", strip=True) for h in soup.find_all("h2")]
    text = content_text(html)
    words = content_words(text)
    host = urlparse(url).netloc if url else ""
    links = [a.get("href", "") for a in soup.find_all("a", href=True)]
    internal = [l for l in links if l.startswith("/") or (host and host in l)]
    external = [l for l in links if l.startswith("http") and (not host or host not in l)]
    return {"url": url, "title": title, "meta": meta, "h1": h1[:3], "h2": h2, "h2_count": len(h2),
            "words": len(words), "text": text, "internal": len(internal), "external": len(external),
            "top_terms": content_top_terms(text)}


def local_content_optimizer(html: str, keyword: str = "", terms=None, target_words: int = 0) -> dict:
    """Lokal 0-100-score med begrundede forbedringer - samme idé som Surfer, uden SERP-data.

    Hver kontrol har en vægt, så scoren er et vægtet gennemsnit af det, der faktisk kan måles i
    teksten: fokus-keyword på de rigtige pladser, tæthed, struktur, længde, links og dækning af
    de relaterede termer. Ingen skjult model og ingen tal udefra.
    """
    keyword = re.sub(r"\s+", " ", (keyword or "").strip().lower())
    terms = [t for t in (terms or []) if t and t != keyword]
    profile = content_profile(html or "")
    text, wc = profile["text"], profile["words"]
    try:
        target = max(100, int(target_words or CONTENT_DEFAULT_WORDS))
    except (TypeError, ValueError):
        target = CONTENT_DEFAULT_WORDS
    checks = []

    def add(name, ok, weight, info="", hint=""):
        checks.append({"name": name, "ok": bool(ok), "weight": weight, "info": info, "hint": hint})

    word_list = content_words(text)
    first_tenth = " ".join(word_list[: max(int(wc * 0.1), 25)])
    kw_stats = term_stats(text, keyword, wc) if keyword else {"term": "", "count": 0, "density": 0.0}
    if keyword:
        title_hit = keyword in profile["title"].lower()
        h1_hit = any(keyword in h.lower() for h in profile["h1"])
        h2_hits = sum(1 for h in profile["h2"] if keyword in h.lower())
        add("Keyword i titel", title_hit, 6, "ja" if title_hit else "nej",
            "Skriv fokus-keyword i sidens titel")
        add("Keyword i H1", h1_hit, 5, "ja" if h1_hit else "nej",
            "Lad H1 indeholde fokus-keyword")
        add("Keyword i første 10 % af teksten", keyword in first_tenth, 4,
            f"{kw_stats['count']} forekomster i alt", "Nævn fokus-keyword tidligt i indledningen")
        add("Keyword i mindst 2 H2", h2_hits >= 2, 4, f"{h2_hits} H2",
            "Brug fokus-keyword i mindst to underoverskrifter")
        add("Keyword-tæthed 0,5-3 %", 0.5 <= kw_stats["density"] <= 3.0, 5,
            f"{kw_stats['density']} %", "Juster antallet af gange fokus-keyword nævnes")
    else:
        add("Fokus-keyword angivet", False, 8, "mangler",
            "Skriv det søgeord, siden skal ranke på")

    add("Mindst 3 H2-overskrifter", profile["h2_count"] >= 3, 5, f"{profile['h2_count']} stk",
        "Del indholdet op i mindst tre H2-afsnit")
    add("Ordantal når målet", wc >= target, 7, f"{wc} af {target} ord",
        f"Skriv ca. {max(target - wc, 0)} ord mere")
    sentences = [s for s in re.split(r"[.!?]+\s", text) if len(s.strip()) > 2]
    avg_sent = round(wc / max(len(sentences), 1), 1)
    add("Korte sætninger (< 25 ord)", avg_sent < 25, 3, f"snit {avg_sent} ord",
        "Del lange sætninger op")
    paragraphs = BeautifulSoup(html or "", "html.parser").find_all("p")
    long_paras = sum(1 for p in paragraphs if len(content_words(p.get_text(" ", strip=True))) > 150)
    add("Korte afsnit (< 150 ord)", long_paras == 0, 2, f"{long_paras} lange",
        "Del lange afsnit op")
    add("Mindst 2 interne links", profile["internal"] >= 2, 4, f"{profile['internal']} stk",
        "Link til mindst to relevante sider på sitet")
    if profile["title"] or profile["meta"] or re.search(r"<head[\s>]", html or "", re.I):
        meta_len = len(profile["meta"])
        add("Meta description 70-160 tegn", 70 <= meta_len <= 160, 3, f"{meta_len} tegn",
            "Skriv en meta description på 70-160 tegn")

    extra_terms = [term_stats(text, t, wc) for t in terms]
    if terms:
        share = len([t for t in extra_terms if t["present"]]) / len(terms)
        add("Relaterede termer dækket", share >= 0.6, 10, f"{round(share * 100)} % af {len(terms)}",
            "Brug de manglende termer naturligt i teksten")

    total = sum(c["weight"] for c in checks)
    earned = sum(c["weight"] for c in checks if c["ok"])
    fixes = sorted([c for c in checks if not c["ok"]], key=lambda c: -c["weight"])
    term_rows = ([kw_stats] if keyword else []) + extra_terms
    return {"score": round(earned / total * 100) if total else 0, "words": wc, "target_words": target,
            "h2_count": profile["h2_count"], "title": profile["title"],
            "meta_len": len(profile["meta"]), "internal": profile["internal"],
            "external": profile["external"], "checks": checks,
            "fixes": [{"text": c["name"], "info": c["info"], "hint": c["hint"]} for c in fixes],
            "terms": [t for t in term_rows if t["term"]], "top_terms": profile["top_terms"]}


def fetch_page_html(url: str) -> dict:
    """Henter en side efter SSRF-tjek - samme vej som resten af appen bruger."""
    try:
        url = normalize_url(url)
        response = safe_request(url, timeout=12)
        return {"ok": True, "url": url, "html": (response.text or "")[:CONTENT_MAX_CHARS],
                "status": response.status_code}
    except Exception as e:
        return {"ok": False, "url": (url or "").strip()[:200], "error": str(e)[:200]}


def compare_with_competitors(url: str = "", html: str = "", competitors=None, keyword: str = "") -> dict:
    """Sammenligner eget indhold med brugerangivne konkurrent-URL'er - helt uden SERP-API.

    Vi kan ikke sige, hvem der ranker; brugeren peger på de sider, der skal måles imod. Det giver
    ordantal, overskrifter og hvilke termer de dækker, som vi ikke gør.
    """
    competitors = [c.strip() for c in (competitors or []) if c and c.strip()][:COMPETITOR_MAX]
    own_html, own_url = html or "", (url or "").strip()
    if not own_html.strip():
        if not own_url:
            return {"ok": False, "error": "Indsæt din tekst eller din URL"}
        fetched = fetch_page_html(own_url)
        if not fetched.get("ok"):
            return {"ok": False, "error": fetched.get("error") or "Din side kunne ikke hentes"}
        own_html, own_url = fetched["html"], fetched["url"]
    own = content_profile(own_html, own_url)
    rows, words_list, h2_list, tally = [], [], [], {}
    for competitor_url in competitors:
        fetched = fetch_page_html(competitor_url)
        if not fetched.get("ok"):
            rows.append({"url": competitor_url, "ok": False,
                         "error": fetched.get("error") or "kunne ikke hentes"})
            continue
        prof = content_profile(fetched["html"], fetched["url"])
        rows.append({"url": prof["url"], "ok": True, "title": prof["title"], "words": prof["words"],
                     "h2_count": prof["h2_count"], "top_terms": prof["top_terms"],
                     "headings": prof["h2"][:6]})
        words_list.append(prof["words"])
        h2_list.append(prof["h2_count"])
        for term in {t["term"] for t in prof["top_terms"]}:
            tally[term] = tally.get(term, 0) + 1
    good = [r for r in rows if r.get("ok")]
    avg_words = round(sum(words_list) / len(words_list)) if words_list else 0
    avg_h2 = round(sum(h2_list) / len(h2_list), 1) if h2_list else 0
    own_counts = content_term_counts(own["text"])
    keyword = re.sub(r"\s+", " ", (keyword or "").strip().lower())
    missing, single = [], []
    for term, hits in sorted(tally.items(), key=lambda kv: (-kv[1], kv[0])):
        if term in own_counts or term == keyword:
            continue
        item = {"term": term, "in_competitors": hits}
        if len(good) >= 2 and hits >= 2:
            missing.append(item)
        else:
            single.append(item)
    advice = []
    if avg_words and own["words"] < avg_words * 0.8:
        advice.append(f"Skriv ca. {max(avg_words - own['words'], 0)} ord mere - konkurrenternes snit er {avg_words} ord")
    if avg_h2 and own["h2_count"] < avg_h2:
        advice.append(f"Tilføj {max(int(round(avg_h2)) - own['h2_count'], 1)} H2-afsnit - konkurrenterne har {avg_h2} i snit")
    if missing:
        advice.append("Dæk de emner mindst to konkurrenter skriver om: " + ", ".join(m["term"] for m in missing[:6]))
    if not advice:
        advice.append("Du dækker det samme som konkurrenterne - brug overskuddet på bedre eksempler og links")
    return {"ok": True, "own": {k: v for k, v in own.items() if k != "text"}, "competitors": rows,
            "averages": {"words": avg_words, "h2": avg_h2, "pages": len(good)},
            "missing_terms": missing[:15], "single_terms": single[:10], "advice": advice}


def brief_headings(keyword: str, terms=None) -> list:
    kw = keyword or "emnet"
    headings = [f"Hvad er {kw}?", f"Hvorfor {kw} betyder noget for køberen"]
    if terms:
        headings.append("Det skal du vide om " + " og ".join(terms[:2]))
    headings += [f"Sådan vælger du {kw}", "Pris og hvad du får for pengene",
                 f"Ofte stillede spørgsmål om {kw}"]
    return headings


def brief_from_keyword(keyword: str, intent: str = "", terms_raw: str = "", competitors_raw: str = "") -> dict:
    """Bygger en indholds-brief lokalt: mål for ord/H2, termliste, overskrifter og vinkler.

    Er der konkurrent-URL'er med, kommer målene derfra (gennemsnit af deres ord og H2), og deres
    topptermer og overskrifter bliver en del af briefen. Ellers bruges standardmålene.
    """
    keyword = re.sub(r"\s+", " ", (keyword or "").strip())
    if not keyword:
        return {"ok": False, "error": "Skriv et emne eller keyword"}
    terms = parse_term_list(terms_raw, 12)
    competitor_urls = [u.strip() for u in re.split(r"[\n,]+", competitors_raw or "") if u.strip()][:COMPETITOR_MAX]
    words_list, h2_list, competitor_terms, angles, failed = [], [], [], [], []
    for competitor_url in competitor_urls:
        fetched = fetch_page_html(competitor_url)
        if not fetched.get("ok"):
            failed.append(competitor_url)
            continue
        prof = content_profile(fetched["html"], fetched["url"])
        words_list.append(prof["words"])
        h2_list.append(prof["h2_count"])
        competitor_terms += [t["term"] for t in prof["top_terms"]]
        angles += prof["h2"][:3]
    target_words = int(round((sum(words_list) / len(words_list)) / 100.0) * 100) if words_list else 1200
    target_words = max(800, min(target_words, 3000))
    target_h2 = max(3, int(round(sum(h2_list) / len(h2_list)))) if h2_list else 5
    merged = []
    for term in terms + competitor_terms:
        term = (term or "").strip().lower()
        if term and term != keyword.lower() and term not in merged:
            merged.append(term)
    notes = [f"Mål: ca. {target_words} ord og {target_h2} H2-overskrifter"]
    if words_list:
        notes.append(f"Målene er gennemsnittet af {len(words_list)} konkurrentside(r)")
    else:
        notes.append("Ingen konkurrentsider blev læst - målene er standard (1200 ord, 5 H2)")
    if angles:
        notes.append("Konkurrenternes vinkler: " + " · ".join(angles[:5]))
    if failed:
        notes.append("Kunne ikke hente: " + ", ".join(failed))
    notes.append("Termerne er talt fra teksten - der er ingen søgevolumen i tallene")
    return {"ok": True, "keyword": keyword, "intent": (intent or "").strip()[:80],
            "title": keyword[:1].upper() + keyword[1:] + " – guide, pris og valg",
            "words": target_words, "h2": target_h2, "terms": merged[:12],
            "headings": brief_headings(keyword, merged)[:max(target_h2, 5)], "notes": notes}


@app.post("/growth/optimize")
async def growth_optimize(request: Request):
    """Indholdsoptimerer: tekst eller URL ind, score/termer/fixes ud (JSON til dashboardet)."""
    form = await request.form()
    content = str(form.get("content") or "")[:CONTENT_MAX_CHARS]
    url = str(form.get("url") or "").strip()
    keyword = str(form.get("keyword") or "").strip()
    terms = parse_term_list(str(form.get("terms") or ""))
    try:
        target_words = int(str(form.get("target_words") or "0") or 0)
    except ValueError:
        target_words = 0
    loop = asyncio.get_running_loop()
    if not content.strip():
        if not url:
            return JSONResponse({"ok": False, "error": "Indsæt teksten eller en URL"}, status_code=400)
        fetched = await loop.run_in_executor(executor, fetch_page_html, url)
        if not fetched.get("ok"):
            return JSONResponse({"ok": False, "error": fetched.get("error") or "Siden kunne ikke hentes"},
                               status_code=400)
        content, url = fetched["html"], fetched["url"]
    result = await loop.run_in_executor(executor, local_content_optimizer, content, keyword, terms, target_words)
    result.update({"ok": True, "url": url, "keyword": keyword})
    with get_db() as db:
        db.execute(
            "INSERT INTO content_audits (source, keyword, score, words, target_words, terms_json, checks_json, created_at) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (url or "indsat tekst", keyword, result["score"], result["words"], result["target_words"],
             jsonlib.dumps(result["terms"], ensure_ascii=False),
             jsonlib.dumps(result["fixes"], ensure_ascii=False), now_iso()),
        )
        db.execute("DELETE FROM content_audits WHERE id NOT IN (SELECT id FROM content_audits ORDER BY id DESC LIMIT 50)")
    return JSONResponse(result)


@app.post("/growth/compare")
async def growth_compare(request: Request):
    """Sammenligner egen side/tekst med op til tre konkurrent-URL'er (JSON)."""
    form = await request.form()
    content = str(form.get("content") or "")[:CONTENT_MAX_CHARS]
    url = str(form.get("url") or "").strip()
    keyword = str(form.get("keyword") or "").strip()
    competitors = [c.strip() for c in re.split(r"[\n,]+", str(form.get("competitors") or "")) if c.strip()]
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        executor, compare_with_competitors, url, content, competitors[:COMPETITOR_MAX], keyword)
    if not result.get("ok"):
        return JSONResponse(result, status_code=400)
    return JSONResponse(result)


@app.post("/growth/brief")
async def growth_brief(keyword: str = Form(...), intent: str = Form(""), terms: str = Form(""),
                       competitors: str = Form(""), planned_for: str = Form("")):
    """Gemmer en indholds-brief i planen. Mål og termer bygges lokalt."""
    keyword = keyword.strip()
    if not keyword:
        return RedirectResponse("/?tab=vaekst&brief=fejl&brief_msg=" +
                                urllib.parse.quote("Skriv et emne eller keyword"), status_code=303)
    planned = planned_for.strip()[:10]
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", planned or ""):
        planned = ""
    loop = asyncio.get_running_loop()
    brief = await loop.run_in_executor(executor, brief_from_keyword, keyword, intent, terms, competitors)
    if not brief.get("ok"):
        return RedirectResponse("/?tab=vaekst&brief=fejl&brief_msg=" +
                                urllib.parse.quote(brief.get("error", "Briefen kunne ikke bygges")[:160]),
                                status_code=303)
    with get_db() as db:
        db.execute(
            "INSERT INTO content_briefs (keyword, intent, title, words, headings, terms, notes, planned_for, status, created_at) "
            "VALUES (?,?,?,?,?,?,?,?,?,?)",
            (keyword[:120], brief["intent"], brief["title"][:200], brief["words"],
             "\n".join(brief["headings"]), ", ".join(brief["terms"]), "\n".join(brief["notes"]),
             planned, BRIEF_STATUS[0], now_iso()),
        )
    return RedirectResponse("/?tab=vaekst&brief=ok", status_code=303)


@app.post("/growth/brief/status")
async def growth_brief_status(id: int = Form(...), status: str = Form(...)):
    if status not in BRIEF_STATUS:
        return RedirectResponse("/?tab=vaekst", status_code=303)
    with get_db() as db:
        db.execute("UPDATE content_briefs SET status=? WHERE id=?", (status, id))
    return RedirectResponse("/?tab=vaekst", status_code=303)


@app.post("/growth/brief/delete")
async def growth_brief_delete(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM content_briefs WHERE id=?", (id,))
    return RedirectResponse("/?tab=vaekst", status_code=303)


@app.post("/links/target/add")
async def link_target_add(url: str = Form(...), type_: str = Form(""), contact: str = Form(""),
                          reason: str = Form(""), site: str = Form("")):
    """Manuel linkliste: den side man gerne vil have et link fra (ingen automatisk prospecting)."""
    try:
        url = normalize_url(url)
    except ValueError as e:
        return RedirectResponse("/?tab=vaekst&link=fejl&link_msg=" + urllib.parse.quote(str(e)[:160]),
                                status_code=303)
    site = (site or urlparse(url).netloc).strip()[:120]
    link_type = type_ if type_ in LINK_TYPES else LINK_TYPES[-1]
    with get_db() as db:
        db.execute(
            "INSERT OR IGNORE INTO link_targets (url, site, type, reason, contact, status, created_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (url, site, link_type, reason.strip()[:300], contact.strip()[:200], LINK_STATUS[0], now_iso()),
        )
    return RedirectResponse("/?tab=vaekst&link=ok", status_code=303)


@app.post("/links/target/status")
async def link_target_status(id: int = Form(...), status: str = Form(...)):
    if status not in LINK_STATUS:
        return RedirectResponse("/?tab=vaekst", status_code=303)
    with get_db() as db:
        db.execute("UPDATE link_targets SET status=? WHERE id=?", (status, id))
    return RedirectResponse("/?tab=vaekst", status_code=303)


@app.post("/links/target/delete")
async def link_target_delete(id: int = Form(...)):
    with get_db() as db:
        db.execute("DELETE FROM link_targets WHERE id=?", (id,))
    return RedirectResponse("/?tab=vaekst", status_code=303)


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
    tab = (request.query_params.get("tab") or "").strip().lower()
    invite = (request.query_params.get("invite") or "").strip().lower()
    invite_msg = (request.query_params.get("invite_msg") or "").strip()[:180]
    invite_email = (request.query_params.get("invite_email") or "").strip()[:254]
    invite_kind = (request.query_params.get("invite_kind") or "").strip().lower()[:16]
    del_state = (request.query_params.get("del") or "").strip().lower()[:8]
    del_msg = (request.query_params.get("del_msg") or "").strip()[:180]
    del_kind = (request.query_params.get("del_kind") or "").strip().lower()[:16]
    del_email = (request.query_params.get("del_email") or "").strip()[:254]
    bk_state = (request.query_params.get("bk") or "").strip().lower()[:8]
    bk_msg = (request.query_params.get("bk_msg") or "").strip()[:200]
    cc_link = (request.query_params.get("cc_link") or "").strip().lower()[:8]
    cc_msg = (request.query_params.get("cc_msg") or "").strip()[:180]
    brief_state = (request.query_params.get("brief") or "").strip().lower()[:8]
    brief_msg = (request.query_params.get("brief_msg") or "").strip()[:180]
    link_state = (request.query_params.get("link") or "").strip().lower()[:8]
    link_msg = (request.query_params.get("link_msg") or "").strip()[:180]
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
        briefs = db.execute(
            "SELECT * FROM content_briefs ORDER BY CASE status WHEN 'Planlagt' THEN 0 "
            "WHEN 'Skrevet' THEN 1 ELSE 2 END, id DESC LIMIT 40"
        ).fetchall()
        link_targets = db.execute("SELECT * FROM link_targets ORDER BY id DESC LIMIT 40").fetchall()
        content_audits = db.execute("SELECT * FROM content_audits ORDER BY id DESC LIMIT 5").fetchall()
        strategy_row = db.execute("SELECT value FROM settings WHERE key='active_strategy'").fetchone()
        check_row = db.execute("SELECT value FROM settings WHERE key='strategy_check'").fetchone()
        sgap_row = db.execute("SELECT value FROM settings WHERE key='sgap_snapshot'").fetchone()
        users = db.execute("SELECT id, email, created_at, last_login_ip, last_login_at, must_change_password "
                           "FROM users ORDER BY id").fetchall()
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
    try:
        sgap_state = jsonlib.loads(sgap_row["value"]) if sgap_row and sgap_row["value"] else {}
    except Exception:
        sgap_state = {}
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "domains": domains,
        "competitors": competitors,
        "articles": articles,
        "linkchecks": linkchecks,
        "socialqueue": socialqueue,
        "cc_tz": CC_TZ_NAME,
        "notes": notes,
        "keywords": keywords,
        "alarms": alarms,
        "budget_rows": [
            {"service": s, "used": u, "limit": l, "pct": (round(u / l * 100) if l else 0)}
            for s, (u, l) in budget_usage().items()
        ],
        "job_rows": job_status(),
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
        "env_password_warning": env_password_mismatch(),
        "env_password_notice": env_password_notice(),
        "update_state": update_state,
        "update_token": bool(GITHUB_TOKEN),
        "update_repo": GITHUB_REPO,
        "task_estimates": TASK_ESTIMATES,
        "current_commit": deployed_commit(),
        "users": users,
        "backups": list_backups(),
        "backup_feedback": ({"ok": bk_state == "ok", "message": bk_msg}
                            if bk_state in ("ok", "fejl") else None),
        "api_clients": api_client_rows(),
        "api_key_once": pending_api_key(),
        "api_usage": api_usage(),
        "api_audit": api_audit_rows(10),
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
        "briefs": briefs,
        "brief_statuses": BRIEF_STATUS,
        "brief_feedback": ({"ok": brief_state == "ok", "message": brief_msg}
                           if brief_state in ("ok", "fejl") else None),
        "link_targets": link_targets,
        "link_statuses": LINK_STATUS,
        "link_types": LINK_TYPES,
        "link_feedback": ({"ok": link_state == "ok", "message": link_msg}
                          if link_state in ("ok", "fejl") else None),
        "content_audits": content_audits,
        "ai_vis": ai_vis,
        "links_sug": links_sug,
        "health_hist_n": health_hist,
        "crawl": crawl,
        "track_domain": TRACK_DOMAIN,
        "difficulties": difficulties,
        "sgap": sgap_state,
        "cc_seen": cc_seen_view(sgap_state),
        "sgap_ready": bool(WP_URL and WP_USER and WP_APP_PASSWORD),
        "cc_link": cc_link,
        "cc_msg": cc_msg,
        "modules": modules_state(),
        "strategies": STRATEGIES,
        "active_strategy": active_key,
        "strategy_autopilot": STRATEGIES[active_key]["autopilot"],
        "strategy_autopilot_label": STRATEGIES[active_key]["label"],
        "insecure": getattr(request.state, "insecure", False),
        "strategy_check": jsonlib.loads(check_row["value"]) if check_row and check_row["value"] else None,
        "initial_tab": tab if tab in DASHBOARD_TABS else "cockpit",
        "invite_feedback": ({"ok": invite == "ok", "message": invite_msg,
                             "email": invite_email, "kind": invite_kind}
                            if invite in ("ok", "fejl") else None),
        "delete_feedback": ({"ok": del_state == "ok", "message": del_msg, "kind": del_kind,
                             "email": del_email}
                            if del_state in ("ok", "fejl") else None),
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

# ---------- MCP (fase 1): laese-vaerktoejer paa /mcp ----------
# Spec 2026-07-28 er stateless: hver request beskriver sig selv, og svaret er almindelig JSON.
# Vi daekker tools/list + tools/call (ingen SSE, ingen sessioner), saa endpointet kan ligge i
# denne proces uden nye afhaengigheder. Den officielle SDK kraever starlette 1.x, som fastapi
# 0.115.6 ikke kan bruge - se docs/Command_Center_MCP.md.
MCP_PROTOCOL_VERSION = "2026-07-28"
MCP_SERVER_NAME = "command-center"
_MCP_LOCAL_HOSTS = ("localhost", "127.0.0.1", "::1", "testserver")


def _mcp_limit(args: dict, default: int, maximum: int) -> int:
    try:
        value = int(args.get("limit", default))
    except (TypeError, ValueError):
        value = default
    return max(1, min(value, maximum))


def _mcp_rows(sql: str, params: tuple = ()) -> list:
    with get_db() as db:
        return [dict(r) for r in db.execute(sql, params).fetchall()]


def mcp_tool_health(args: dict) -> dict:
    with get_db() as db:
        alarms_open = db.execute("SELECT COUNT(*) FROM alarms WHERE resolved=0").fetchone()[0]
        crawl = db.execute("SELECT host, pages, avg_score, started_at FROM crawl_runs "
                           "ORDER BY id DESC LIMIT 1").fetchone()
    try:
        size_mb = round(os.path.getsize(DB_PATH) / 1048576, 2)
    except OSError:
        size_mb = None
    return {"version": APP_VERSION, "status": "ok" if user_count() else "uden brugere",
            "db_mb": size_mb, "users": user_count(), "alarms_open": alarms_open,
            "latest_crawl": dict(crawl) if crawl else None,
            "newest": [f"{v}: {t}" for v, t in NEWEST[:3]]}


def mcp_tool_crawl_summary(args: dict) -> dict:
    return {"runs": _mcp_rows("SELECT id, host, pages, avg_score, sitemap_urls, started_at, finished_at "
                              "FROM crawl_runs ORDER BY id DESC LIMIT ?", (_mcp_limit(args, 5, 50),))}


def mcp_tool_keywords(args: dict) -> dict:
    return {"keywords": _mcp_rows("SELECT keyword, position, target_url, checked_at FROM keywords "
                                  "ORDER BY (position IS NULL), position LIMIT ?",
                                  (_mcp_limit(args, 20, 200),))}


def mcp_tool_monitors(args: dict) -> dict:
    return {"monitors": _mcp_rows("SELECT name, url, type, last_status, last_result, last_checked "
                                  "FROM monitors ORDER BY id LIMIT ?", (_mcp_limit(args, 50, 200),))}


def mcp_tool_alarms_open(args: dict) -> dict:
    return {"alarms": _mcp_rows("SELECT type, message, severity, created_at FROM alarms "
                                "WHERE resolved=0 ORDER BY id DESC LIMIT ?", (_mcp_limit(args, 20, 200),))}


def mcp_tool_notes(args: dict) -> dict:
    return {"notes": _mcp_rows("SELECT content, created_at FROM notes ORDER BY id DESC LIMIT ?",
                               (_mcp_limit(args, 10, 100),))}


def mcp_tool_history(args: dict) -> dict:
    try:
        domain_id = int(args.get("domain_id"))
    except (TypeError, ValueError):
        raise ValueError("domain_id skal vaere et tal (se /api/history eller fanen Domæner)")
    return {"domain_id": domain_id,
            "checks": _mcp_rows("SELECT status, response_time, ssl_days, checked_at FROM check_history "
                                "WHERE domain_id=? ORDER BY id DESC LIMIT ?",
                                (domain_id, _mcp_limit(args, 20, 100)))}


# --- fase 2: skrivende vaerktoejer (kraever write-scope) ---
MCP_MAX_PAGES = {"quick": 10, "standard": 30, "deep": 60}


def mcp_tool_add_note(args: dict) -> dict:
    content = str(args.get("content") or "").strip()
    if len(content) < 2:
        raise ValueError("content: mindst 2 tegn")
    ts = now_iso()
    with get_db() as db:
        cur = db.execute("INSERT INTO notes (content, created_at) VALUES (?,?)", (content[:2000], ts))
    return {"ok": True, "note_id": cur.lastrowid, "created_at": ts}


def mcp_tool_resolve_alarm(args: dict) -> dict:
    try:
        alarm_id = int(args.get("id"))
    except (TypeError, ValueError):
        raise ValueError("id skal vaere et tal (se alarms_open)")
    with get_db() as db:
        row = db.execute("SELECT id, message, resolved FROM alarms WHERE id=?", (alarm_id,)).fetchone()
        if not row:
            raise ValueError(f"Alarm #{alarm_id} findes ikke (se alarms_open)")
        db.execute("UPDATE alarms SET resolved=1 WHERE id=?", (alarm_id,))
        left = db.execute("SELECT COUNT(*) FROM alarms WHERE resolved=0").fetchone()[0]
    return {"ok": True, "resolved": alarm_id, "already_resolved": bool(row["resolved"]),
            "message": (row["message"] or "")[:200], "alarms_open": left}


def mcp_tool_add_monitor(args: dict) -> dict:
    name = str(args.get("name") or "").strip()[:60]
    url = str(args.get("url") or "").strip()
    expected = str(args.get("expected") or "").strip()[:200]
    mtype = str(args.get("type") or "contains").strip().lower()
    if len(name) < 2 or not url or not expected:
        raise ValueError("name, url og expected er paakraevet")
    if mtype not in ("contains", "json", "price"):
        raise ValueError("type skal vaere contains, json eller price")
    try:
        clean = normalize_url(url)
    except ValueError as e:
        raise ValueError(str(e))
    with get_db() as db:
        dup = db.execute("SELECT id FROM monitors WHERE url=? AND type=?", (clean, mtype)).fetchone()
        if dup:
            return {"ok": True, "created": False, "monitor_id": dup["id"], "url": clean,
                    "note": "monitoren findes allerede - intet nyt blev oprettet"}
        cur = db.execute("INSERT INTO monitors (name, url, type, expected) VALUES (?,?,?,?)",
                         (name, clean, mtype, expected))
        add_alarm(db, "monitor", f"MCP: monitor '{name}' oprettet", "info")
    return {"ok": True, "created": True, "monitor_id": cur.lastrowid, "name": name, "url": clean, "type": mtype}


async def mcp_tool_start_crawl(args: dict) -> dict:
    url = str(args.get("url") or "").strip()
    try:
        clean = normalize_url(url)
    except ValueError as e:
        raise ValueError(str(e))
    level = str(args.get("level") or "standard").strip().lower()
    if level not in MCP_MAX_PAGES:
        level = "standard"
    try:
        max_pages = int(args.get("max_pages") or MCP_MAX_PAGES[level])
    except (TypeError, ValueError):
        raise ValueError("max_pages skal vaere et tal")
    max_pages = max(5, min(max_pages, 100))
    if CRAWL_STATE.get("running"):
        raise RuntimeError("Crawl kører allerede - vent på den (se crawl_summary eller /api/crawl/status)")
    loop = asyncio.get_running_loop()
    loop.run_in_executor(executor, site_crawl_sync, clean, max_pages)
    return {"ok": True, "started": clean, "max_pages": max_pages, "level": level,
            "status_url": "/api/crawl/status",
            "estimate": f"~{max(1, round(max_pages * 0.4))} min",
            "note": "Crawlen koerer i baggrunden - spoerg crawl_summary om resultatet"}


MCP_TOOLS = [
    {"name": "health", "description": "Status for Command Center: version, database, brugere, aabne alarmer "
                                      "og seneste crawl.",
     "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
     "fn": mcp_tool_health},
    {"name": "crawl_summary", "description": "De seneste crawl-koersler med sideantal og gennemsnitlig score.",
     "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 50}},
                     "additionalProperties": False},
     "fn": mcp_tool_crawl_summary},
    {"name": "keywords", "description": "Nøgleord med seneste position, sorteret efter position.",
     "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 200}},
                     "additionalProperties": False},
     "fn": mcp_tool_keywords},
    {"name": "monitors", "description": "Pris- og indholdsmonitorer med seneste status.",
     "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 200}},
                     "additionalProperties": False},
     "fn": mcp_tool_monitors},
    {"name": "alarms_open", "description": "Aabne alarmer (uløste) med type, tekst og alvorsgrad.",
     "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 200}},
                     "additionalProperties": False},
     "fn": mcp_tool_alarms_open},
    {"name": "notes", "description": "De nyeste noter fra dashboardet.",
     "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 100}},
                     "additionalProperties": False},
     "fn": mcp_tool_notes},
    {"name": "history", "description": "Historik for et domæne (status, svartid og SSL-dage pr. tjek).",
     "inputSchema": {"type": "object", "properties": {"domain_id": {"type": "integer"},
                                                      "limit": {"type": "integer", "minimum": 1, "maximum": 100}},
                     "required": ["domain_id"], "additionalProperties": False},
     "fn": mcp_tool_history},
    {"name": "start_crawl", "scope": "write",
     "description": "Start et site-crawl i baggrunden (kræver write-scope). Afvises hvis et crawl kører.",
     "inputSchema": {"type": "object",
                     "properties": {"url": {"type": "string", "description": "Startside, fx https://site.dk"},
                                    "level": {"type": "string", "enum": ["quick", "standard", "deep"]},
                                    "max_pages": {"type": "integer", "minimum": 5, "maximum": 100}},
                     "required": ["url"], "additionalProperties": False},
     "fn": mcp_tool_start_crawl},
    {"name": "add_monitor", "scope": "write",
     "description": "Opret en monitor (kræver write-scope). Samme url+type oprettes ikke to gange.",
     "inputSchema": {"type": "object",
                     "properties": {"name": {"type": "string"},
                                    "url": {"type": "string"},
                                    "type": {"type": "string", "enum": ["contains", "json", "price"]},
                                    "expected": {"type": "string", "description": "Tekst, JSON-nøgle eller pris"}},
                     "required": ["name", "url", "expected"], "additionalProperties": False},
     "fn": mcp_tool_add_monitor},
    {"name": "resolve_alarm", "scope": "write",
     "description": "Markér en alarm som løst (kræver write-scope).",
     "inputSchema": {"type": "object", "properties": {"id": {"type": "integer"}},
                     "required": ["id"], "additionalProperties": False},
     "fn": mcp_tool_resolve_alarm},
    {"name": "add_note", "scope": "write",
     "description": "Skriv en note i dashboardet (kræver write-scope).",
     "inputSchema": {"type": "object",
                     "properties": {"content": {"type": "string", "minLength": 2, "maxLength": 2000}},
                     "required": ["content"], "additionalProperties": False},
     "fn": mcp_tool_add_note},
]

# annoteringer foelger MCP-spec (readOnlyHint/destructiveHint), saa klienten kan advare foer kald
for _tool in MCP_TOOLS:
    _tool.setdefault("scope", "read")
    _tool["annotations"] = {"readOnlyHint": _tool["scope"] == "read",
                            "destructiveHint": _tool["name"] in ("resolve_alarm",),
                            "idempotentHint": _tool["name"] in ("resolve_alarm",)}


def _mcp_host_allowed(host: str) -> bool:
    """Host-validering mod DNS-rebinding. Er CC_PUBLIC_URL tom, er vi i udvikling og lader alt passere."""
    name = (host or "").split(":")[0].strip().lower()
    if name in _MCP_LOCAL_HOSTS:
        return True
    if not CC_PUBLIC_URL:
        return True
    want = (urlparse(CC_PUBLIC_URL).hostname or "").lower()
    return bool(want) and name == want


def _mcp_origin_allowed(origin: str) -> bool:
    if not origin:
        return True
    parts = urlparse(origin)
    return parts.scheme in ("http", "https") and bool(parts.hostname) and _mcp_host_allowed(parts.hostname)


def _mcp_result(mid, result: dict) -> dict:
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def _mcp_error(mid, code: int, message: str) -> dict:
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}}


async def _mcp_handle(msg, client) -> dict | None:
    if not isinstance(msg, dict):
        return _mcp_error(None, -32600, "Ugyldig request")
    mid = msg.get("id")
    method = str(msg.get("method") or "")
    params = msg.get("params") or {}
    if method.startswith("notifications/"):
        return None                      # notifikationer besvares ikke
    if method == "initialize":
        return _mcp_result(mid, {"protocolVersion": MCP_PROTOCOL_VERSION,
                                 "capabilities": {"tools": {"listChanged": False}},
                                 "serverInfo": {"name": MCP_SERVER_NAME, "version": APP_VERSION}})
    if method == "ping":
        return _mcp_result(mid, {})
    if method == "tools/list":
        return _mcp_result(mid, {"tools": [{k: t[k] for k in ("name", "description", "inputSchema", "annotations")}
                                           for t in MCP_TOOLS]})
    if method == "tools/call":
        name = str(params.get("name") or "").strip()
        args = params.get("arguments") or {}
        tool = next((t for t in MCP_TOOLS if t["name"] == name), None)
        if not tool:
            # ogsaa et forkert vaerktoejsnavn er et spoer: en noegle der famler skal kunne ses i auditten
            log_api_call(client["id"], "tools/call", name or "(tomt navn)", False, "ukendt vaerktoej")
            return _mcp_error(mid, -32602, f"Ukendt vaerktoej: {name}")
        scope = tool.get("scope", "read")
        if scope not in [x for x in (client["scopes"] or "").split(",") if x]:
            log_api_call(client["id"], "tools/call", name, False, f"mangler scope: {scope}")
            return _mcp_error(mid, -32003, f"Noeglen mangler scope: {scope}")
        started = time.perf_counter()
        try:
            data = tool["fn"](args if isinstance(args, dict) else {})
            if inspect.isawaitable(data):
                data = await data
        except Exception as e:
            log_api_call(client["id"], "tools/call", name, False, f"fejl: {str(e)[:200]}",
                         int((time.perf_counter() - started) * 1000))
            return _mcp_result(mid, {"content": [{"type": "text", "text": f"Fejl: {str(e)[:200]}"}], "isError": True})
        log_api_call(client["id"], "tools/call", name, True, "",
                     int((time.perf_counter() - started) * 1000))
        return _mcp_result(mid, {"content": [{"type": "text",
                                             "text": jsonlib.dumps(data, ensure_ascii=False, indent=2)}],
                                 "isError": False})
    return _mcp_error(mid, -32601, f"Ukendt metode: {method}")


@app.post("/mcp")
async def mcp_endpoint(request: Request):
    """MCP over Streamable HTTP (JSON-svar): Bearer-noegle pr. klient, Origin/Host-valideret."""
    if not _mcp_origin_allowed(request.headers.get("origin") or ""):
        return JSONResponse({"error": "origin ikke tilladt"}, status_code=403)
    if not _mcp_host_allowed(request.headers.get("host") or ""):
        return JSONResponse({"error": "host ikke tilladt"}, status_code=421)
    auth = request.headers.get("authorization") or ""
    token = auth[7:].strip() if auth.lower().startswith("bearer ") else ""
    client = find_api_client(token)
    if not client:
        return JSONResponse({"error": "unauthorized"}, status_code=401,
                            headers={"WWW-Authenticate": 'Bearer realm="command-center"'})
    try:
        payload = await request.json()
    except Exception:
        return JSONResponse(_mcp_error(None, -32700, "Ugyldig JSON"), status_code=400)
    touch_api_client(client["id"], client_ip(request))
    items = payload if isinstance(payload, list) else [payload]
    answers = []
    for item in items:
        answer = await _mcp_handle(item, client)
        if answer is not None:
            answers.append(answer)
    headers = {"MCP-Protocol-Version": MCP_PROTOCOL_VERSION, "X-Accel-Buffering": "no"}
    if not answers:
        return Response(status_code=202, headers=headers)
    return JSONResponse(answers if isinstance(payload, list) else answers[0], headers=headers)


@app.post("/api-keys/create")
async def api_keys_create(name: str = Form(...), scopes: str = Form("read")):
    try:
        client_id, key = create_api_client(name, scopes)
        remember_api_key((name or "").strip()[:60], key)
        with get_db() as db:
            add_alarm(db, "brugere", f"API-noegle #{client_id} oprettet til '{(name or '').strip()[:40]}'", "info")
    except ValueError as e:
        with get_db() as db:
            add_alarm(db, "brugere", f"API-noegle ikke oprettet: {str(e)[:120]}", "advarsel")
    return RedirectResponse("/", status_code=303)


@app.post("/api-keys/revoke")
async def api_keys_revoke(client_id: int = Form(...)):
    revoke_api_client(client_id)
    with get_db() as db:
        add_alarm(db, "brugere", f"API-noegle #{client_id} tilbagekaldt", "info")
    return RedirectResponse("/", status_code=303)



# ---------- Job-heartbeat (v7.20.0): er de planlagte jobs stille eller fejlende? ----------
# Hvert scheduler-job skriver sidste succes og sidste fejl i settings. job_heartbeat_check() (hvert 15. min)
# alarmerer, hvis et job er forsinket for meget, eller hvis det fejlede. Hver tilstand alarmeres kun én gang.
JOB_MAX_AGE_HOURS = {
    "domain_checks": 7, "keyword_checks": 26, "growth_autopilot": 26, "cleanup": 26,
    "db_backup": 26, "update_check": 26, "sgap_sync": 1.5, "wp_cron": 0.5,
    "alert_outbox": 0.1,
}
JOB_LABELS = {
    "domain_checks": "Domæne-tjek", "keyword_checks": "Keyword-tjek", "growth_autopilot": "Vækst-autopilot",
    "cleanup": "Oprydning", "db_backup": "DB-backup", "update_check": "Opdateringstjek",
    "sgap_sync": "WordPress-synk", "wp_cron": "WP-Cron-ping", "alert_outbox": "Alarm-udsendelse",
}


def job_heartbeat(job_id: str, fn):
    """Pakker et job: skriver succes/fejl i settings. Fejlen rethrows, saa APScheduler stadig logger den.
    Async jobs pakkes som async, saa AsyncIOScheduler stadig kender dem som coroutines."""
    if asyncio.iscoroutinefunction(fn):
        async def wrapped_async(*args, **kwargs):
            try:
                out = await fn(*args, **kwargs)
            except Exception as e:
                _job_mark(job_id, False, repr(e))
                raise
            _job_mark(job_id, True, "")
            return out
        wrapped_async.__name__ = fn.__name__
        return wrapped_async

    def wrapped(*args, **kwargs):
        try:
            out = fn(*args, **kwargs)
        except Exception as e:
            _job_mark(job_id, False, repr(e))
            raise
        _job_mark(job_id, True, "")
        return out
    wrapped.__name__ = fn.__name__
    return wrapped


def _job_mark(job_id: str, ok: bool, err: str):
    try:
        with get_db() as db:
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (f"job_ok_{job_id}", now_iso() if ok else (get_setting_value(db, f"job_ok_{job_id}") or "")))
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (f"job_err_{job_id}", "" if ok else f"{now_iso()} {err[:200]}"))
    except Exception as e:
        print("[cc] kunne ikke skrive job-status:", repr(e), flush=True)


def get_setting_value(db, key: str):
    row = db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return row["value"] if row else None


def job_status() -> list[dict]:
    """Status for alle planlagte jobs: sidst ok, sidste fejl, og om jobbet er forsinket."""
    out = []
    now = datetime.now()
    with get_db() as db:
        for job_id, max_hours in JOB_MAX_AGE_HOURS.items():
            ok_at = get_setting_value(db, f"job_ok_{job_id}") or ""
            err = get_setting_value(db, f"job_err_{job_id}") or ""
            stale = True
            age_hours = None
            if ok_at:
                try:
                    age_hours = round((now - datetime.fromisoformat(ok_at)).total_seconds() / 3600, 1)
                    stale = age_hours > max_hours
                except Exception:
                    stale = True
            else:
                # Aldrig koert: forsinket foerst naar appen selv har koert laenger end jobbets maks-alder
                try:
                    started = datetime.fromisoformat(get_setting_value(db, "last_start") or "")
                    stale = (now - started).total_seconds() / 3600 > max_hours
                except Exception:
                    stale = False
            state = "fejlet" if err else ("forsinket" if stale else "ok")
            out.append({"id": job_id, "label": JOB_LABELS.get(job_id, job_id), "state": state,
                        "last_ok": ok_at, "age_hours": age_hours, "last_error": err})
    return out


async def job_heartbeat_check():
    """Alarmerer en gang pr. tilstand: forsinket eller fejlet. Naar jobbet er ok igen, nulstilles tilstanden."""
    for j in job_status():
        key = f"job_alarm_{j['id']}"
        with get_db() as db:
            prev = get_setting_value(db, key) or "ok"
            if j["state"] == prev:
                continue
            if j["state"] == "ok":
                db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, 'ok')", (key,))
                continue
            db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (key, j["state"]))
            if j["state"] == "fejlet":
                msg = f"Job '{j['label']}' fejlede: {j['last_error'][:160]}"
                add_alarm(db, "jobs", msg, "kritisk")
            else:
                hrs = "aldrig koert" if j["age_hours"] is None else f"sidst ok for {j['age_hours']} t siden"
                add_alarm(db, "jobs", f"Job '{j['label']}' er forsinket ({hrs})", "advarsel")


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
        seed_status = seed_standard_user()
        if seed_status not in ("findes", "mangler"):
            print(f"[cc] standardbruger ({ADMIN_EMAIL_ENV}): {seed_status}", flush=True)
    except Exception as e:
        print("[cc] standardbruger kunne ikke oprettes:", repr(e), flush=True)
    try:
        stale = warn_stale_env_password()
        if stale:
            print(f"[cc] advarsel: {stale}", flush=True)
    except Exception as e:
        print("[cc] .env-koden kunne ikke tjekkes:", repr(e), flush=True)
    try:
        scheduler.add_job(job_heartbeat("domain_checks", job_check_domains), IntervalTrigger(hours=6), id="domain_checks", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("keyword_checks", job_check_keywords), CronTrigger(hour=6, minute=0), id="keyword_checks", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("growth_autopilot", job_growth_autopilot), CronTrigger(hour=5, minute=15), id="growth_autopilot", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("cleanup", cleanup_old_data), CronTrigger(hour=4, minute=30), id="cleanup", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("db_backup", job_backup_db), CronTrigger(hour=4, minute=40), id="db_backup", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("update_check", job_update_check), CronTrigger(hour=5, minute=0), id="update_check", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("sgap_sync", job_sgap_sync), IntervalTrigger(minutes=30), id="sgap_sync", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("wp_cron", job_wp_cron), IntervalTrigger(minutes=5), id="wp_cron", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat("alert_outbox", job_drain_alerts), IntervalTrigger(minutes=1), id="alert_outbox", replace_existing=True, max_instances=1, coalesce=True)
        scheduler.add_job(job_heartbeat_check, IntervalTrigger(minutes=15), id="job_heartbeat", replace_existing=True, max_instances=1, coalesce=True)
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
    <script src="/static/vendor/tailwind.js"></script>
    <script defer src="/static/vendor/alpine.min.js"></script>
    <script src="/static/vendor/chart.umd.min.js"></script>
    <meta name="theme-color" content="#09090b">
    <style>
      html { scroll-behavior: smooth; }
      body { -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
      ::-webkit-scrollbar { width: 9px; height: 9px; }
      ::-webkit-scrollbar-track { background: #09090b; }
      ::-webkit-scrollbar-thumb { background: #3f3f46; border-radius: 8px; }
      ::-webkit-scrollbar-thumb:hover { background: #52525b; }
      nav, header { backdrop-filter: blur(12px); }
      nav > div { scrollbar-width: none; }
      nav > div::-webkit-scrollbar { display: none; }
      tbody tr { transition: background-color .12s ease; }
      tbody tr:hover { background: rgba(39,39,42,.45); }
      button, a, input { transition: all .15s ease; }
      input:focus-visible, button:focus-visible { outline: 2px solid #34d399; outline-offset: 1px; }
      .spinner { width: 16px; height: 16px; border: 2px solid #3f3f46; border-top-color: #34d399; border-radius: 50%; display: inline-block; animation: ccspin .7s linear infinite; vertical-align: -3px; }
      @keyframes ccspin { to { transform: rotate(360deg); } }
      .bg-zinc-900:hover { border-color: #3f3f46; }
      @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
      @media (max-width: 640px) {
        .cc-tabbar .cc-pill { display: none; }
        .cc-nav-inner { flex-wrap: nowrap; }
        .cc-hero { padding: .9rem 1rem; }
        .cc-hero-stats { width: 100%; justify-content: space-between; gap: .9rem; }
        .cc-hero-stats b { font-size: 1rem; }
        .cc-term-row { grid-template-columns: minmax(0,1fr) 54px 72px; gap: .4rem; }
        .cc-score { width: 84px; height: 84px; }
        .cc-score b { font-size: 1.2rem; }
        nav::-webkit-scrollbar { display: none; }
        th, td { padding-top: .45rem; padding-bottom: .45rem; }
      }
      /* ---- Designlag (v7.24): én rolig visuel rytme for kort, felter og navigation ---- */
      :root { --cc-line: #27272a; --cc-line-strong: #3f3f46; --cc-accent: #34d399; }
      body {
        background:
          radial-gradient(1100px 520px at 12% -8%, rgba(52,211,153,.10), transparent 62%),
          radial-gradient(900px 480px at 96% -4%, rgba(56,189,248,.07), transparent 58%),
          #09090b;
        background-attachment: fixed;
      }
      main section > div.bg-zinc-900.border-zinc-800 {
        background-image: linear-gradient(180deg, rgba(39,39,42,.42), rgba(24,24,27,.72));
        box-shadow: inset 0 1px 0 rgba(255,255,255,.035), 0 24px 48px -40px rgba(0,0,0,.95);
        transition: border-color .18s ease, box-shadow .18s ease;
      }
      main section > div.bg-zinc-900.border-zinc-800:hover {
        border-color: var(--cc-line-strong);
        box-shadow: inset 0 1px 0 rgba(255,255,255,.05), 0 30px 60px -44px rgba(0,0,0,1);
      }
      main input:not([type=checkbox]):not([type=radio]), main select, main textarea {
        background-color: rgba(9,9,11,.75) !important;
        border-color: var(--cc-line) !important;
        color: #e4e4e7;
      }
      main input:not([type=checkbox]):not([type=radio]):focus, main select:focus, main textarea:focus {
        border-color: rgba(52,211,153,.55) !important;
        box-shadow: 0 0 0 3px rgba(52,211,153,.12);
        outline: none;
      }
      main button:hover { filter: brightness(1.12); }
      .cc-nav-inner { flex-wrap: wrap; row-gap: .22rem; padding-block: .12rem; }
      .cc-nav-link { display:inline-flex; align-items:center; gap:.35rem; white-space:nowrap; padding:.36rem .62rem;
        border-radius:.65rem; font-size:.72rem; color:#a1a1aa; border:1px solid transparent; }
      .cc-nav-link:hover { color:#e4e4e7; background:rgba(63,63,70,.35); }
      .cc-nav-link.is-active { color:#6ee7b7; background:linear-gradient(180deg, rgba(52,211,153,.18), rgba(52,211,153,.06));
        border-color: rgba(52,211,153,.32); box-shadow: inset 0 0 0 1px rgba(52,211,153,.08); }
      .cc-nav-group { display:flex; align-items:center; gap:.1rem; margin-right:.5rem; }
      .cc-nav-group:last-child { margin-right:0; }
      .cc-card-head { display:flex; align-items:flex-start; justify-content:space-between; gap:.75rem; margin-bottom:.9rem; }
      .cc-card-title { font-size:.7rem; text-transform:uppercase; letter-spacing:.12em; color:#d4d4d8; font-weight:600; }
      .cc-card-sub { font-size:.72rem; color:#71717a; margin-top:.3rem; max-width:60ch; line-height:1.55; }
      .cc-pill { display:inline-flex; align-items:center; gap:.3rem; font-size:.62rem; letter-spacing:.08em; text-transform:uppercase;
        padding:.2rem .55rem; border-radius:999px; border:1px solid rgba(52,211,153,.3); color:#6ee7b7;
        background:rgba(52,211,153,.08); white-space:nowrap; }
      .cc-eyebrow { font-size:.62rem; text-transform:uppercase; letter-spacing:.18em; color:#34d399; }
      .cc-btn { display:inline-flex; align-items:center; gap:.4rem; border-radius:.7rem; padding:.5rem .9rem; font-size:.75rem;
        border:1px solid var(--cc-line-strong); color:#d4d4d8; background:rgba(39,39,42,.6); }
      .cc-btn-primary { display:inline-flex; align-items:center; gap:.4rem; border-radius:.7rem; padding:.5rem 1rem;
        font-size:.78rem; font-weight:600; color:#052e21; background:linear-gradient(180deg,#6ee7b7,#34d399);
        border:1px solid rgba(52,211,153,.6); }
      .cc-hero { display:flex; flex-wrap:wrap; align-items:center; justify-content:space-between; gap:1rem;
        border:1px solid rgba(52,211,153,.22); border-radius:1rem; padding:1.1rem 1.25rem;
        background: radial-gradient(600px 170px at 0% 0%, rgba(52,211,153,.16), transparent 70%), rgba(17,17,19,.75); }
      .cc-hero-title { font-size:1.05rem; font-weight:700; color:#f4f4f5; margin-top:.15rem; }
      .cc-hero-text { font-size:.76rem; color:#a1a1aa; margin-top:.35rem; max-width:72ch; line-height:1.55; }
      .cc-hero-stats { display:flex; gap:1.4rem; }
      .cc-hero-stats b { display:block; font-size:1.15rem; color:#6ee7b7; font-variant-numeric:tabular-nums; }
      .cc-hero-stats span { font-size:.62rem; color:#71717a; text-transform:uppercase; letter-spacing:.1em; }
      .cc-score { position:relative; display:grid; place-items:center; width:104px; height:104px; border-radius:999px;
        background: conic-gradient(var(--ring) calc(var(--pct) * 1%), rgba(63,63,70,.4) 0); flex:none; }
      .cc-score::before { content:""; position:absolute; inset:9px; border-radius:inherit; background:#111113;
        box-shadow: inset 0 0 0 1px rgba(255,255,255,.04); }
      .cc-score b, .cc-score small { position:relative; font-variant-numeric:tabular-nums; }
      .cc-score b { font-size:1.5rem; color:#f4f4f5; line-height:1; }
      .cc-score small { font-size:.65rem; color:#71717a; }
      .cc-term-row { display:grid; grid-template-columns: minmax(0,1fr) 84px 84px; gap:.6rem; align-items:center; font-size:.72rem; }
      .cc-bar { height:5px; border-radius:999px; background:rgba(63,63,70,.45); overflow:hidden; }
      .cc-bar i { display:block; height:100%; border-radius:inherit; background:linear-gradient(90deg,#34d399,#22d3ee); }
      .cc-check { display:flex; align-items:baseline; gap:.5rem; font-size:.72rem; padding:.3rem .55rem; border-radius:.5rem; }
      .cc-check + .cc-check { margin-top:.15rem; }
      .cc-check.is-ok { color:#a7f3d0; background:rgba(52,211,153,.05); }
      .cc-check.is-bad { color:#fecdd3; background:rgba(251,113,133,.06); }
      .cc-check .cc-dot { width:6px; height:6px; border-radius:999px; background:currentColor; flex:none; margin-top:.35rem; }
      .cc-fix { display:flex; flex-direction:column; gap:.12rem; font-size:.72rem; padding:.45rem .6rem; border-radius:.6rem;
        background:rgba(251,191,36,.06); border:1px solid rgba(251,191,36,.18); }
      .cc-fix b { color:#fcd34d; font-weight:600; }
      .cc-fix span { color:#a1a1aa; }
      .cc-chip { display:inline-flex; align-items:center; gap:.3rem; font-size:.68rem; padding:.2rem .5rem; border-radius:999px;
        border:1px solid var(--cc-line-strong); color:#d4d4d8; background:rgba(39,39,42,.55); }
      .cc-chip.is-missing { border-color:rgba(251,113,133,.35); color:#fda4af; background:rgba(251,113,133,.07); }
      .cc-metric { display:flex; flex-direction:column; gap:.1rem; padding:.55rem .7rem; border-radius:.7rem;
        border:1px solid var(--cc-line); background:rgba(9,9,11,.5); }
      .cc-metric b { font-size:.95rem; color:#e4e4e7; font-variant-numeric:tabular-nums; }
      .cc-metric span { font-size:.62rem; color:#71717a; text-transform:uppercase; letter-spacing:.09em; }
      .cc-note { font-size:.72rem; color:#71717a; line-height:1.55; }
      .cc-tabbar { display:flex; align-items:center; justify-content:space-between; gap:1rem; padding:.1rem .15rem 0; }
      .cc-tabbar h2 { font-size:.95rem; font-weight:600; color:#f4f4f5; }
      .cc-tabbar p { font-size:.72rem; color:#71717a; margin-top:.15rem; }
    </style>
</head>
{% if insecure %}<div class="bg-yellow-600 text-black text-xs text-center py-1.5 px-4 font-semibold">&Uacute;t&uacute;n HTTPS &mdash; login og adgangskoder sendes ukrypteret. S&aelig;t nginx + TLS op foran CC (se Install-dokumentationen).</div>{% endif %}
<body class="bg-zinc-950 text-zinc-100 min-h-screen font-sans" x-data="{ tab: '{{ initial_tab }}', seoResult: null, seoLoading: false, crawl: null, histChart: null, histOpen: false, dups: null, healthChart: null, diff: null, redir: null, rewrite: null, growth: null, growthLoading: false, growthError: '', cmp: null, cmpLoading: false, cmpError: '' }">
{% if env_password_warning %}
<div class="bg-red-500/10 border-b border-red-500/40 text-red-300 text-xs text-center py-2 px-4">⚠️ {{ env_password_warning }}</div>
{% endif %}
{% if current_user and current_user.must_change_password %}
<div class="bg-amber-500/10 border-b border-amber-500/40 text-amber-300 text-xs text-center py-2 px-4">Du er logget ind med en midlertidig adgangskode (fra invitationsmailen eller CC_ADMIN_PASSWORD i .env) &mdash; skift den under fanen <b>Brugere</b>.</div>
{% endif %}
{% if env_password_notice %}
<div class="bg-sky-500/10 border-b border-sky-500/40 text-sky-300 text-xs text-center py-2 px-4">🧹 {{ env_password_notice.text }}</div>
{% endif %}
<header class="border-b border-zinc-800/80 bg-zinc-950/80 px-4 py-2.5">
    <div class="max-w-7xl mx-auto flex items-center justify-between gap-3">
        <div class="flex items-center gap-2.5 min-w-0">
            <span class="grid place-items-center w-8 h-8 rounded-xl border border-emerald-500/30 bg-emerald-500/10 text-sm shrink-0">⚡</span>
            <div class="leading-tight min-w-0">
                <h1 class="font-semibold text-[13px] tracking-wide whitespace-nowrap">Command Center <span class="text-emerald-400">v{{ app_version }}</span></h1>
                <p class="hidden sm:block text-[11px] text-zinc-500 truncate">SEO, indhold og drift</p>
            </div>
        </div>
        <div class="flex items-center gap-2 text-[11px] shrink-0">
            <form action="/update/apply" method="POST" onsubmit="return confirm('Hent og installér nyeste version fra GitHub? Der laves en DB-backup først, og appen skal genstartes bagefter.')"><button class="text-[11px] text-zinc-400 hover:text-emerald-400" title="Opdatér fra GitHub">⬆️<span class="hidden sm:inline"> Opdatér</span></button></form>
            <a href="/health" class="text-[11px] text-emerald-400 hover:text-emerald-300" title="Systemstatus">🩺<span class="hidden sm:inline"> Systemstatus</span></a>
            {% if current_user %}<span class="hidden sm:inline text-[11px] text-zinc-500">👤 {{ current_user.email }}</span>
            {% if client_ip %}<span class="hidden md:inline text-[11px] text-zinc-600" title="Din IP">{{ client_ip }}</span>{% endif %}
            <a href="/logout" class="text-[11px] text-zinc-500 hover:text-rose-400"><span class="hidden sm:inline">Log ud</span><span class="sm:hidden" aria-label="Log ud">⏏</span></a>{% endif %}
        </div>
    </div>
</header>
<nav class="sticky top-0 z-50 border-b border-zinc-800/80 bg-zinc-950/75 px-3 py-1.5 shadow-lg shadow-black/20">
    <div class="max-w-7xl mx-auto cc-nav-inner flex items-center gap-1 overflow-x-auto">
        <div class="cc-nav-group">
            <button @click="tab='cockpit'" class="cc-nav-link" :class="tab==='cockpit' && 'is-active'">🧭 Cockpit</button>
        </div>
        <div class="cc-nav-group">
            <button @click="tab='seo'" class="cc-nav-link" :class="tab==='seo' && 'is-active'">🔍 SEO &amp; audit</button>
            <button @click="tab='keywords'" class="cc-nav-link" :class="tab==='keywords' && 'is-active'">🎯 Keywords</button>
            <button @click="tab='vaekst'" class="cc-nav-link" :class="tab==='vaekst' && 'is-active'">🚀 Vækst</button>
        </div>
        <div class="cc-nav-group">
            <button @click="tab='articles'" class="cc-nav-link" :class="tab==='articles' && 'is-active'">✍️ Indhold</button>
            <button @click="tab='links'" class="cc-nav-link" :class="tab==='links' && 'is-active'">🔗 Links</button>
            <button @click="tab='spy'" class="cc-nav-link" :class="tab==='spy' && 'is-active'">🕷️ Spy</button>
        </div>
        <div class="cc-nav-group">
            <button @click="tab='social'" class="cc-nav-link" :class="tab==='social' && 'is-active'">📱 Social</button>
            <button @click="tab='monitors'" class="cc-nav-link" :class="tab==='monitors' && 'is-active'">🩺 Monitors</button>
            <button @click="tab='alarms'" class="cc-nav-link" :class="tab==='alarms' && 'is-active'">🚨 Alarmer{% if alarms %} ({{ alarms|length }}){% endif %}</button>
        </div>
        <div class="cc-nav-group">
            <button @click="tab='ai'" class="cc-nav-link" :class="tab==='ai' && 'is-active'">🤖 AI</button>
            <button @click="tab='pro'" class="cc-nav-link" :class="tab==='pro' && 'is-active'">💼 Pro</button>
            <button @click="tab='moduler'" class="cc-nav-link" :class="tab==='moduler' && 'is-active'">⚙️ Moduler</button>
            <button @click="tab='brugere'" class="cc-nav-link" :class="tab==='brugere' && 'is-active'">👤 Brugere</button>
            <button @click="tab='notes'" class="cc-nav-link" :class="tab==='notes' && 'is-active'">📝 Noter</button>
        </div>
    </div>
</nav>
<main class="max-w-7xl mx-auto p-4 space-y-4">
    <div class="cc-tabbar flex-wrap">
        <div>
            <h2 x-text="ccTabInfo[tab]?.title || 'Cockpit'">Cockpit</h2>
            <p x-text="ccTabInfo[tab]?.hint || ''"></p>
        </div>
        <span class="cc-pill">v{{ app_version }}</span>
    </div>

    {% if not ai_enabled or not wp_enabled %}
    <div class="bg-amber-500/10 border border-amber-500/30 rounded-2xl p-3 text-xs text-amber-300">
        Setup: AI {{ '✅' if ai_enabled else '❌ (AIMLAPI_KEY)' }} · WordPress {{ '✅' if wp_enabled else '❌ (WP_URL/WP_USER/WP_APP_PASSWORD)' }} · SerpAPI {{ '✅' if serpapi_enabled else '❌ (SERPAPI_KEY)' }} · Telegram {{ '✅' if telegram_enabled else '— (valgfrit)' }} — se .env.example
    </div>
    {% endif %}

    <!-- COCKPIT -->
    <section x-show="tab === 'cockpit'" class="space-y-4">
        <div class="bg-emerald-500/5 border border-emerald-500/20 rounded-2xl p-4">
            <h2 class="text-xs uppercase tracking-wider text-emerald-300 mb-2">🧭 Sådan bruger du Command Center (workflow)</h2>
            <div class="grid grid-cols-2 md:grid-cols-5 gap-2 text-[11px]">
                <button @click="tab='seo'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">SEO &amp; audit</b><br><span class="text-zinc-500">Kør audit + crawl</span></button>
                <button @click="tab='keywords'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">Keywords</b><br><span class="text-zinc-500">Positioner + difficulty</span></button>
                <button @click="tab='articles'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">Indhold</b><br><span class="text-zinc-500">AI-artikler + autopilot</span></button>
                <button @click="tab='links'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">Links</b><br><span class="text-zinc-500">Interne + backlinks</span></button>
                <button @click="tab='vaekst'" class="bg-zinc-950 border border-zinc-800 rounded-xl p-2 text-left hover:border-emerald-500/40"><b class="text-emerald-400">Vækst</b><br><span class="text-zinc-500">Optimer + plan</span></button>
            </div>
            <p class="text-[10px] text-zinc-600 mt-2">Cockpit er overblikket. SEO, Keywords og Vækst er den daglige analyse og plan; Indhold, Links og Spy producerer og finder muligheder. Social, Monitors og Alarmer holder driften i gang.</p>
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

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">💳 API-budget denne måned</h2>
                {% for b in budget_rows %}
                <div class="mb-3">
                    <div class="flex justify-between text-xs text-zinc-300"><span>{{ b.service }}</span><span>{{ b.used }} / {{ b.limit if b.limit else '∞' }} kald{% if b.limit %} ({{ b.pct }} %){% endif %}</span></div>
                    <div class="h-1.5 bg-zinc-800 rounded-full overflow-hidden mt-1"><div class="h-full {% if b.pct >= 100 %}bg-rose-500{% elif b.pct >= 80 %}bg-amber-500{% else %}bg-emerald-500{% endif %}" style="width:{{ [b.pct, 100]|min if b.limit else 0 }}%"></div></div>
                </div>
                {% endfor %}
                <p class="text-[10px] text-zinc-600">Grænsen sættes med SERPAPI_MONTHLY_LIMIT og AI_MONTHLY_LIMIT i .env (0 = ingen grænse). Ved 80 % og 100 % kommer der alarm.</p>
            </div>
            <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
                <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">⏱️ Planlagte jobs (heartbeat)</h2>
                {% for j in job_rows %}
                <div class="flex justify-between items-start text-xs py-1 border-b border-zinc-800/60 last:border-0">
                    <span class="text-zinc-300">{{ j.label }}</span>
                    <span class="text-right {% if j.state == 'ok' %}text-emerald-400{% elif j.state == 'forsinket' %}text-amber-400{% else %}text-rose-400{% endif %}">
                        {% if j.state == 'ok' %}ok · {{ j.last_ok[0:16] }}{% elif j.state == 'forsinket' %}forsinket{% else %}fejlet{% endif %}
                    </span>
                </div>
                {% endfor %}
                <p class="text-[10px] text-zinc-600 mt-2">Et job er forsinket, hvis det ikke er kørt inden for sin forventede periode. Tjekket kører hvert 15. minut.</p>
            </div>
        </div>

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

    <!-- VÆKST -->
    <section x-show="tab === 'vaekst'" class="space-y-4" style="display: none;">
        <div class="cc-hero">
            <div class="min-w-0">
                <p class="cc-eyebrow">Vækst</p>
                <h2 class="cc-hero-title">Indhold der er målt — ikke gættet</h2>
                <p class="cc-hero-text">Optimer teksten mod et fokus-keyword og dine egne termer, mål den mod konkurrenter du selv peger på, og hold planen samlet. Alt regnes lokalt: ingen API-nøgle, ingen kald til fremmede tjenester, og ingen data der forlader serveren.</p>
            </div>
            <div class="cc-hero-stats">
                <div title="Briefs i planen"><b>{{ briefs|length }}</b><span>briefs</span></div>
                <div title="Linkmuligheder i listen"><b>{{ link_targets|length }}</b><span>links</span></div>
                <div title="Seneste score fra indholdsoptimeringen"><b>{{ content_audits[0].score if content_audits else '–' }}</b><span>score</span></div>
            </div>
        </div>

        {% if brief_feedback %}
        <div class="rounded-xl border px-4 py-2 text-xs {{ 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300' if brief_feedback.ok else 'border-rose-500/30 bg-rose-500/10 text-rose-300' }}">
            {{ 'Briefen er lagt i planen.' if brief_feedback.ok else ('Briefen blev ikke oprettet: ' ~ (brief_feedback.message or 'ukendt fejl')) }}
        </div>
        {% endif %}
        {% if link_feedback %}
        <div class="rounded-xl border px-4 py-2 text-xs {{ 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300' if link_feedback.ok else 'border-rose-500/30 bg-rose-500/10 text-rose-300' }}">
            {{ 'Linkmuligheden er gemt.' if link_feedback.ok else ('Linkmuligheden blev ikke gemt: ' ~ (link_feedback.message or 'ukendt fejl')) }}
        </div>
        {% endif %}

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="cc-card-head">
                <div>
                    <h2 class="cc-card-title">Indholdsoptimerer</h2>
                    <p class="cc-card-sub">Indsæt din tekst eller en URL. Scoren er et vægtet gennemsnit af fokus-keyword, struktur, længde, links og dækning af dine termer — og hver manglende kontrol kommer med et konkret forslag.</p>
                </div>
                <span class="cc-pill">Lokal</span>
            </div>
            <form @submit.prevent="ccOptimize($el)" class="grid gap-2 md:grid-cols-2">
                <textarea name="content" rows="5" placeholder="Indsæt artikeltekst eller HTML (kan udelades, hvis du angiver en URL)" class="md:col-span-2 bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm"></textarea>
                <input type="text" name="url" placeholder="https://ditdomaene.dk/guide (valgfrit)" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="text" name="keyword" placeholder="Fokus-keyword" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="text" name="terms" placeholder="Relaterede termer, adskilt af komma" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="number" name="target_words" min="100" max="10000" step="50" value="1200" placeholder="Mål for ordantal" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <div class="md:col-span-2 flex flex-wrap items-center gap-3">
                    <button class="cc-btn-primary">Analysér indhold</button>
                    <span class="text-[11px] text-zinc-500" x-show="growthLoading" style="display: none;">Regner på teksten…</span>
                    <span class="text-[11px] text-zinc-600">Ingen nøgle · intet sendes videre</span>
                </div>
            </form>
            <p class="text-xs text-rose-400 mt-2" x-show="growthError" x-text="growthError" style="display: none;"></p>

            <div x-show="growth" style="display: none;" class="mt-5 space-y-5">
                <div class="flex flex-wrap items-center gap-5">
                    <div class="cc-score" :style="'--pct:' + (growth?.score || 0) + ';--ring:' + ((growth?.score || 0) >= 80 ? '#34d399' : (growth?.score || 0) >= 50 ? '#fbbf24' : '#fb7185')">
                        <b x-text="growth?.score"></b><small>/100</small>
                    </div>
                    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 flex-1 min-w-[240px]">
                        <div class="cc-metric"><b x-text="growth?.words"></b><span>ord</span></div>
                        <div class="cc-metric"><b x-text="growth?.target_words"></b><span>mål</span></div>
                        <div class="cc-metric"><b x-text="growth?.h2_count"></b><span>H2-afsnit</span></div>
                        <div class="cc-metric"><b x-text="growth?.internal"></b><span>interne links</span></div>
                    </div>
                </div>

                <div class="grid gap-4 lg:grid-cols-2">
                    <div>
                        <h3 class="cc-card-title mb-2">Termdækning</h3>
                        <div class="space-y-2">
                            <template x-for="t in (growth?.terms || [])" :key="t.term">
                                <div class="cc-term-row">
                                    <span class="text-zinc-200 truncate" x-text="t.term"></span>
                                    <div class="cc-bar"><i :style="'width:' + Math.min(100, (t.density || 0) * 25) + '%'"></i></div>
                                    <span class="text-zinc-500 text-right" x-text="t.count + '× · ' + t.density + ' %'"></span>
                                </div>
                            </template>
                            <p x-show="!(growth?.terms || []).length" class="cc-note">Skriv et fokus-keyword eller nogle termer for at måle dækningen.</p>
                        </div>
                        <div x-show="(growth?.top_terms || []).length" class="mt-4">
                            <h3 class="cc-card-title mb-2">Tekstens egne toptermer</h3>
                            <div class="flex flex-wrap gap-1.5">
                                <template x-for="t in (growth?.top_terms || []).slice(0, 10)" :key="'top' + t.term">
                                    <span class="cc-chip"><span x-text="t.term"></span><span class="text-zinc-500" x-text="t.count + '×'"></span></span>
                                </template>
                            </div>
                        </div>
                    </div>
                    <div>
                        <h3 class="cc-card-title mb-2">Kontroller</h3>
                        <ul class="space-y-1">
                            <template x-for="c in (growth?.checks || [])" :key="c.name">
                                <li class="cc-check" :class="c.ok ? 'is-ok' : 'is-bad'">
                                    <span class="cc-dot"></span>
                                    <span x-text="c.name"></span>
                                    <span class="text-zinc-500 ml-auto text-right" x-text="c.info"></span>
                                </li>
                            </template>
                        </ul>
                    </div>
                </div>

                <div x-show="(growth?.fixes || []).length">
                    <h3 class="cc-card-title mb-2">Næste skridt, vigtigst først</h3>
                    <div class="space-y-1.5">
                        <template x-for="(f, i) in (growth?.fixes || [])" :key="'fix' + i">
                            <div class="cc-fix"><b x-text="(i + 1) + '. ' + f.text"></b><span x-text="f.hint"></span></div>
                        </template>
                    </div>
                </div>
                <p x-show="!(growth?.fixes || []).length" class="text-xs text-emerald-300">Alt det målbare sidder i skabet — gå efter links og opdateringer nu.</p>
            </div>

            {% if content_audits %}
            <div class="mt-5 border-t border-zinc-800 pt-3">
                <h3 class="cc-card-title mb-2">Seneste målinger</h3>
                <div class="space-y-1">
                    {% for a in content_audits %}
                    <div class="flex items-center gap-3 text-[11px] text-zinc-500">
                        <span class="px-2 py-0.5 rounded-md {% if a.score >= 80 %}bg-emerald-500/10 text-emerald-400{% elif a.score >= 50 %}bg-amber-500/10 text-amber-400{% else %}bg-rose-500/10 text-rose-400{% endif %}">{{ a.score }}</span>
                        <span class="text-zinc-300 truncate max-w-[45%]" title="{{ a.source }}">{{ a.keyword or a.source }}</span>
                        <span>{{ a.words }} ord</span>
                        <span class="ml-auto whitespace-nowrap">{{ a.created_at[:16] }}</span>
                    </div>
                    {% endfor %}
                </div>
            </div>
            {% endif %}
        </div>

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <div class="cc-card-head">
                <div>
                    <h2 class="cc-card-title">Sammenlign med konkurrenter</h2>
                    <p class="cc-card-sub">Du peger selv på de sider, du vil måles imod — op til tre. Vi henter dem, tæller ord og overskrifter og viser hvilke emner de dækker, som du ikke gør.</p>
                </div>
                <span class="cc-pill">Uden SERP-API</span>
            </div>
            <form @submit.prevent="ccCompare($el)" class="grid gap-2 md:grid-cols-2">
                <input type="text" name="url" placeholder="Din side (URL)" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <input type="text" name="keyword" placeholder="Fokus-keyword (valgfrit)" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <textarea name="competitors" rows="3" placeholder="Konkurrent-URL'er — én pr. linje (op til 3)" class="md:col-span-2 bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm"></textarea>
                <div class="md:col-span-2 flex items-center gap-3">
                    <button class="cc-btn">Sammenlign</button>
                    <span class="text-[11px] text-zinc-500" x-show="cmpLoading" style="display: none;">Henter siderne…</span>
                </div>
            </form>
            <p class="text-xs text-rose-400 mt-2" x-show="cmpError" x-text="cmpError" style="display: none;"></p>

            <div x-show="cmp" style="display: none;" class="mt-4 space-y-4">
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    <div class="cc-metric"><b x-text="cmp?.own?.words"></b><span>dine ord</span></div>
                    <div class="cc-metric"><b x-text="cmp?.averages?.words || '–'"></b><span>deres snit</span></div>
                    <div class="cc-metric"><b x-text="cmp?.own?.h2_count"></b><span>dine H2</span></div>
                    <div class="cc-metric"><b x-text="cmp?.averages?.h2 || '–'"></b><span>deres H2</span></div>
                </div>
                <div class="overflow-x-auto">
                    <table class="w-full text-xs">
                        <thead class="text-zinc-500 text-left">
                            <tr><th class="py-2 pr-3">Side</th><th class="py-2 pr-3">Ord</th><th class="py-2 pr-3">H2</th><th class="py-2">Toptermer</th></tr>
                        </thead>
                        <tbody>
                            <tr class="border-t border-zinc-800">
                                <td class="py-2 pr-3 text-emerald-300">Din side</td>
                                <td class="py-2 pr-3 text-zinc-300" x-text="cmp?.own?.words"></td>
                                <td class="py-2 pr-3 text-zinc-300" x-text="cmp?.own?.h2_count"></td>
                                <td class="py-2 text-zinc-500" x-text="(cmp?.own?.top_terms || []).slice(0, 6).map(t => t.term).join(', ')"></td>
                            </tr>
                            <template x-for="c in (cmp?.competitors || [])" :key="c.url">
                                <tr class="border-t border-zinc-800">
                                    <td class="py-2 pr-3 max-w-xs truncate" :title="c.url">
                                        <span x-show="c.ok" class="text-zinc-300" x-text="c.url"></span>
                                        <span x-show="!c.ok" class="text-rose-400" x-text="c.url + ' — ' + (c.error || 'fejl')"></span>
                                    </td>
                                    <td class="py-2 pr-3 text-zinc-400" x-text="c.ok ? c.words : '–'"></td>
                                    <td class="py-2 pr-3 text-zinc-400" x-text="c.ok ? c.h2_count : '–'"></td>
                                    <td class="py-2 text-zinc-500" x-text="c.ok ? (c.top_terms || []).slice(0, 6).map(t => t.term).join(', ') : ''"></td>
                                </tr>
                            </template>
                        </tbody>
                    </table>
                </div>
                <div>
                    <h3 class="cc-card-title mb-2">Emner du mangler</h3>
                    <div class="flex flex-wrap gap-1.5">
                        <template x-for="m in (cmp?.missing_terms || [])" :key="'miss' + m.term">
                            <span class="cc-chip is-missing"><span x-text="m.term"></span><span x-text="m.in_competitors + '/' + (cmp?.averages?.pages || 0)"></span></span>
                        </template>
                        <template x-for="m in (cmp?.single_terms || [])" :key="'single' + m.term">
                            <span class="cc-chip"><span x-text="m.term"></span><span class="text-zinc-500" x-text="m.in_competitors + ' side'"></span></span>
                        </template>
                        <p x-show="!(cmp?.missing_terms || []).length && !(cmp?.single_terms || []).length" class="cc-note">Ingen emnegab fundet i de sider, der kunne hentes.</p>
                    </div>
                </div>
                <ul class="space-y-1">
                    <template x-for="(a, i) in (cmp?.advice || [])" :key="'adv' + i">
                        <li class="text-xs text-zinc-300 flex gap-2"><span class="text-emerald-400">→</span><span x-text="a"></span></li>
                    </template>
                </ul>
            </div>
        </div>

        <div class="grid gap-4 lg:grid-cols-2">
            <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
                <div class="cc-card-head">
                    <div>
                        <h2 class="cc-card-title">Indholdsplan</h2>
                        <p class="cc-card-sub">En brief pr. emne: mål for ord og H2, termer, overskrifter og de vinkler konkurrenterne bruger. Bygges lokalt.</p>
                    </div>
                    <span class="cc-pill">{{ briefs|length }} i kø</span>
                </div>
                <form action="/growth/brief" method="POST" class="grid gap-2">
                    <input type="text" name="keyword" placeholder="Emne eller keyword" required class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <div class="grid grid-cols-2 gap-2">
                        <select name="intent" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                            <option value="informationssøgning">Informationssøgning</option>
                            <option value="sammenligning">Sammenligning</option>
                            <option value="transaktionel">Købsintention</option>
                            <option value="lokal">Lokal søgning</option>
                        </select>
                        <input type="date" name="planned_for" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    </div>
                    <input type="text" name="terms" placeholder="Termer du vil dække (valgfrit)" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <textarea name="competitors" rows="2" placeholder="Konkurrent-URL'er til at sætte målene (valgfrit)" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm"></textarea>
                    <div><button class="cc-btn-primary">Byg brief</button></div>
                </form>

                <div class="mt-4 space-y-2 max-h-[26rem] overflow-y-auto pr-1">
                    {% for b in briefs %}
                    <details class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs">
                        <summary class="cursor-pointer flex items-center gap-2">
                            <span class="font-medium text-zinc-200 truncate">{{ b.keyword }}</span>
                            <span class="cc-pill ml-auto">{{ b.status }}</span>
                        </summary>
                        <div class="mt-3 space-y-2 text-zinc-400">
                            <p class="text-zinc-300">{{ b.title }}</p>
                            <p class="cc-note">Mål: {{ b.words }} ord · {{ b.headings.split('\n')|length }} overskrifter{% if b.planned_for %} · planlagt {{ b.planned_for }}{% endif %}{% if b.intent %} · {{ b.intent }}{% endif %}</p>
                            <div>
                                <p class="text-zinc-500 uppercase tracking-wider text-[10px] mb-1">Overskrifter</p>
                                <p class="whitespace-pre-line">{{ b.headings }}</p>
                            </div>
                            {% if b.terms %}
                            <div>
                                <p class="text-zinc-500 uppercase tracking-wider text-[10px] mb-1">Termer</p>
                                <div class="flex flex-wrap gap-1">
                                    {% for term in b.terms.split(', ') %}<span class="cc-chip">{{ term }}</span>{% endfor %}
                                </div>
                            </div>
                            {% endif %}
                            <div>
                                <p class="text-zinc-500 uppercase tracking-wider text-[10px] mb-1">Noter</p>
                                <p class="whitespace-pre-line">{{ b.notes }}</p>
                            </div>
                            <div class="flex items-center gap-2 pt-1">
                                <form action="/growth/brief/status" method="POST">
                                    <input type="hidden" name="id" value="{{ b.id }}">
                                    <select name="status" onchange="this.form.submit()" class="bg-zinc-900 border border-zinc-800 rounded-lg px-2 py-1 text-[11px]">
                                        {% for st in brief_statuses %}<option value="{{ st }}"{{ ' selected' if st == b.status else '' }}>{{ st }}</option>{% endfor %}
                                    </select>
                                </form>
                                <form action="/growth/brief/delete" method="POST" class="ml-auto">
                                    <input type="hidden" name="id" value="{{ b.id }}">
                                    <button class="text-zinc-500 hover:text-rose-400">Slet</button>
                                </form>
                            </div>
                        </div>
                    </details>
                    {% else %}
                    <p class="cc-note">Ingen briefs endnu — skriv et emne ovenfor, og planen bygges med det samme.</p>
                    {% endfor %}
                </div>
            </div>

            <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
                <div class="cc-card-head">
                    <div>
                        <h2 class="cc-card-title">Linkmuligheder</h2>
                        <p class="cc-card-sub">Din egen liste over sider, du vil have et link fra — med kontakt, begrundelse og status. Ingen automatisk udsendelse.</p>
                    </div>
                    <span class="cc-pill">{{ link_targets|length }} i alt</span>
                </div>
                <form action="/links/target/add" method="POST" class="grid gap-2">
                    <input type="text" name="url" placeholder="https://partner.dk/ressourcer" required class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <div class="grid grid-cols-2 gap-2">
                        <select name="type_" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                            {% for t in link_types %}<option value="{{ t }}">{{ t }}</option>{% endfor %}
                        </select>
                        <input type="text" name="contact" placeholder="Kontakt (navn eller mail)" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    </div>
                    <input type="text" name="reason" placeholder="Hvorfor er siden relevant?" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <div><button class="cc-btn-primary">Tilføj mulighed</button></div>
                </form>

                <div class="mt-4 space-y-2 max-h-[26rem] overflow-y-auto pr-1">
                    {% for l in link_targets %}
                    <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs space-y-1">
                        <div class="flex items-center gap-2">
                            <a href="{{ l.url }}" target="_blank" rel="noopener" class="font-medium text-emerald-400 truncate">{{ l.site or l.url }}</a>
                            <span class="cc-pill ml-auto">{{ l.type }}</span>
                        </div>
                        {% if l.reason %}<p class="text-zinc-400">{{ l.reason }}</p>{% endif %}
                        {% if l.contact %}<p class="text-zinc-500">Kontakt: {{ l.contact }}</p>{% endif %}
                        <div class="flex items-center gap-2 pt-1">
                            <form action="/links/target/status" method="POST">
                                <input type="hidden" name="id" value="{{ l.id }}">
                                <select name="status" onchange="this.form.submit()" class="bg-zinc-900 border border-zinc-800 rounded-lg px-2 py-1 text-[11px]">
                                    {% for st in link_statuses %}<option value="{{ st }}"{{ ' selected' if st == l.status else '' }}>{{ st }}</option>{% endfor %}
                                </select>
                            </form>
                            <form action="/links/target/delete" method="POST" class="ml-auto">
                                <input type="hidden" name="id" value="{{ l.id }}">
                                <button class="text-zinc-500 hover:text-rose-400">Slet</button>
                            </form>
                        </div>
                    </div>
                    {% else %}
                    <p class="cc-note">Ingen linkmuligheder endnu. Tilføj den første side, du vil række ud til.</p>
                    {% endfor %}
                </div>
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
            {% if sgap.paused_because %}
            <p class="text-xs text-amber-400 mt-2">⏸ Afsendelse sat paa pause: {{ sgap.paused_because }}</p>
            {% endif %}
            {% if sgap.cron_lag_minutes and sgap.cron_lag_minutes >= 30 %}
            <p class="text-xs text-amber-400 mt-2">⏱ WP-Cron er {{ sgap.cron_lag_minutes }} min bagud - Command Center kalder wp-cron.php hvert 5. min for at hjaelpe</p>
            {% endif %}
            {% if sgap.problems %}
            <div class="mt-2">
                <div class="text-[10px] uppercase tracking-wider text-zinc-500 mb-1">Pluginnets selvtjek{% if sgap.self_check_at %} ({{ sgap.self_check_at }}){% endif %}</div>
                <ul class="text-xs text-amber-300 list-disc pl-4 space-y-0.5">
                    {% for p in sgap.problems %}<li>{{ p }}</li>{% endfor %}
                </ul>
            </div>
            {% elif sgap.source == 'snapshot' %}
            <p class="text-xs text-emerald-400 mt-2">✓ Pluginnets selvtjek: ingen problemer</p>
            {% endif %}
            <p class="text-[10px] text-zinc-500 mt-2">Tjekket {{ sgap.checked_at }}{% if sgap.version %} · Autopilot {{ sgap.version }}{% endif %}{% if sgap.source == 'stats' %} · aeldre plugin uden /snapshot{% endif %} · Godkend kladder i WordPress: Steamgears → AI Drafts</p>
            {% endif %}
            {% if sgap_ready and modules['autopilot'] %}
            <div class="mt-3 pt-3 border-t border-zinc-800">
                <div class="mb-3">
                    {% set cc_tone = {'ok': 'text-emerald-300', 'warn': 'text-amber-300', 'fejl': 'text-rose-300', 'muted': 'text-zinc-500'}.get(cc_seen.tone, 'text-zinc-500') %}
                    <p class="text-[11px] {{ cc_tone }}">{{ cc_seen.headline }}{% if cc_seen.checked_at %} <span class="text-zinc-600">(svaret fra {{ cc_seen.checked_at }})</span>{% endif %}</p>
                    {% if cc_seen.detail %}<p class="text-[10px] text-zinc-500">{{ cc_seen.detail }}</p>{% endif %}
                    <p class="text-[10px] text-zinc-500">{{ cc_seen.hint }}</p>
                </div>
                {% if cc_link == 'ok' %}
                <p class="text-[11px] text-emerald-300 mb-2">✅ {{ cc_msg }}</p>
                {% elif cc_link == 'fejl' %}
                <p class="text-[11px] text-rose-300 mb-2">❌ Linket kunne ikke lægges i WordPress: {{ cc_msg }}</p>
                {% endif %}
                <div class="flex flex-wrap items-center gap-3">
                    <form action="/autopilot/login-link" method="POST">
                        <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-4 py-2 rounded-xl text-xs">🔑 Log ind på Command Center</button>
                    </form>
                    <span class="text-[10px] text-zinc-500">Lægger et engangslink i WordPress, så knappen der logger dig ind her — uden adgangskode. Linket holder 10 min. og virker én gang.</span>
                </div>
            </div>
            {% endif %}
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Tilføj socialt opslag</h2>
            <form action="/social/add" method="POST" class="space-y-3">
                <input type="text" name="platform" placeholder="Platform (f.eks. Pinterest, LinkedIn, X)" required class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm">
                <textarea name="message" placeholder="Opslagets tekst..." rows="3" required class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm"></textarea>
                <label class="block text-[10px] text-zinc-500">Planlagt tid i {{ cc_tz }} — tomt felt = send med det samme. Tiden gemmes også som UTC.</label>
                <input type="datetime-local" name="scheduled_at" class="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 text-sm text-zinc-300">
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
                        <p class="text-[10px] text-zinc-500">{{ post.status }}{% if post.scheduled_at %} · planlagt {{ post.scheduled_at|replace('T', ' ') }} lokal ({{ post.scheduled_at_utc }} UTC){% endif %}</p>
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

        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Kanaler</h2>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-2 mb-3">
                {% for key, label in [('telegram','Telegram'), ('email','E-mail'), ('ntfy','ntfy'), ('webhook','Webhook')] %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-xs flex items-center justify-between">
                    <span class="text-zinc-300">{{ label }}</span>
                    {% if alert_channels[key] %}<span class="text-emerald-400">● klar</span>{% else %}<span class="text-zinc-500">○ ikke sat</span>{% endif %}
                </div>
                {% endfor %}
            </div>
            <p class="text-[11px] text-zinc-500 mb-3">
                Minimumsniveau: <b>{{ alert_settings.min_severity }}</b> · dedupe {{ alert_settings.dedupe_minutes }} min
                {% if alert_settings.quiet_hours %}· stille timer {{ alert_settings.quiet_hours }} (kun kritiske går igennem){% endif %}
                {% if alert_outbox %}· {{ alert_outbox.get('pending', 0) }} i kø, {{ alert_outbox.get('sent', 0) }} sendt, {{ alert_outbox.get('failed', 0) }} fejlet{% endif %}
            </p>
            <div class="flex flex-wrap gap-2">
                {% for key, label in [('all','Test alle'), ('email','Test e-mail'), ('ntfy','Test ntfy'), ('webhook','Test webhook'), ('telegram','Test Telegram')] %}
                <form action="/alerts/test" method="POST">
                    <input type="hidden" name="channel" value="{{ key }}">
                    <button class="text-[11px] border px-3 py-1 rounded-lg {% if key == 'all' %}bg-emerald-500/10 text-emerald-400 border-emerald-500/30{% else %}bg-zinc-800 text-zinc-300 border-zinc-700{% endif %}">{{ label }}</button>
                </form>
                {% endfor %}
            </div>
            <p class="text-[11px] text-zinc-600 mt-3">Sæt kanalerne i <code>.env</code> (SMTP_*, NTFY_*, ALERT_WEBHOOK_URL) og genstart. Alarmer sendes fra en kø med genforsoeg, så en langsom modtager ikke blokerer appen.</p>
            {% if alert_problems %}
            <div class="mt-3 space-y-1">
                {% for p in alert_problems %}
                <div class="text-[11px] text-rose-300">{{ p.channel }}: {{ p.subject }} — {{ p.last_error }} ({{ p.attempts }} forsøg)</div>
                {% endfor %}
            </div>
            {% endif %}
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
                {% set module_labels = {"domains": "🌐 Domæne-tjek", "keywords": "🎯 Keyword-tjek", "ai": "🤖 AI (artikler/rewrite)", "monitors": "🩺 Monitors", "social": "📱 Social-kø", "links": "🔗 Linktjek", "spy": "🕷️ Spy/konkurrenter", "wp_push": "📝 WordPress-push", "telegram": "📬 Telegram", "growth": "🌱 Growth-autopilot", "autopilot": "⚙️ Autopilot-bro (WordPress)"} %}
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

    <!-- BACKUP -->
    <section x-show="tab === 'moduler'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-1">Database-backup</h2>
            <p class="text-xs text-zinc-500 mb-3">Den nyeste backup tages automatisk hver nat kl. 04:40 og før hver opdatering. Her kan du tage en manuel backup og gendanne en af de gemte. Ved gendannelse tages først en kopi af den nuværende database.</p>
            {% if backup_feedback %}
            {% if backup_feedback.ok %}
            <div class="bg-emerald-500/10 border border-emerald-500/40 text-emerald-300 rounded-xl px-3 py-2 mb-3 text-xs">✅ {{ backup_feedback.message }}</div>
            {% else %}
            <div class="bg-rose-500/10 border border-rose-500/40 text-rose-300 rounded-xl px-3 py-2 mb-3 text-xs">❌ <b>Handlingen blev ikke gennemført</b> — <code class="break-all">{{ backup_feedback.message }}</code></div>
            {% endif %}
            {% endif %}
            <form action="/backup/now" method="POST" class="mb-4">
                <button class="text-[11px] bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-3 py-1.5 rounded-lg">💾 Tag backup nu</button>
            </form>
            {% if backups %}
            <div class="space-y-2">
                {% for b in backups %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2 flex flex-wrap items-center justify-between gap-2">
                    <span class="text-xs text-zinc-300 break-all"><code>{{ b.name }}</code> <span class="text-zinc-500">· {{ b.size_kb }} KB · {{ b.mtime }}</span></span>
                    <form action="/backup/restore" method="POST" class="flex items-center gap-2">
                        <input type="hidden" name="name" value="{{ b.name }}">
                        <input type="text" name="confirm" autocomplete="off" placeholder="skriv GENDAN" aria-label="Skriv GENDAN for at bekræfte gendannelse af {{ b.name }}" class="bg-zinc-900 border border-zinc-700 rounded-lg px-2 py-1 text-[11px] text-zinc-200 w-32">
                        <button class="text-[11px] bg-rose-500/10 text-rose-300 border border-rose-500/40 px-3 py-1 rounded-lg">↺ Gendan</button>
                    </form>
                </div>
                {% endfor %}
            </div>
            {% else %}
            <p class="text-xs text-zinc-500">Ingen backups endnu.</p>
            {% endif %}
        </div>
    </section>

    <!-- BRUGERE -->
    <section x-show="tab === 'brugere'" class="space-y-4" style="display: none;">
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Brugere ({{ users|length }})</h2>
            <p class="text-xs text-zinc-500 mb-3">Adgang sker med e-mail + adgangskode (PBKDF2-SHA256). Den foerste bruger blev oprettet ved foerste besoeg — invitér gerne en ekstra, saa du ikke laaser dig ude.</p>
            {% if delete_feedback %}
            {% if delete_feedback.ok %}
            <div class="bg-emerald-500/10 border border-emerald-500/40 text-emerald-300 rounded-xl px-3 py-2 mb-3 text-xs">
                ✅ <b>Brugeren er slettet</b>{% if delete_feedback.email %} — <b>{{ delete_feedback.email }}</b>{% endif %}. Sessionerne er ryddet, så en åben fane ikke kan bruge kontoen længere.
            </div>
            {% else %}
            <div class="bg-rose-500/10 border border-rose-500/40 text-rose-300 rounded-xl px-3 py-2 mb-3 text-xs">
                ❌ <b>Brugeren blev ikke slettet</b> — der er ikke ændret noget i listen.
                <code class="block mt-1 text-rose-200 break-all">{{ delete_feedback.message }}</code>
                {% if delete_feedback.kind == 'sidste' %}
                <span class="block mt-1 text-rose-300/80">Der skal altid være mindst én bruger, så du ikke låser dig ude. Invitér en ny bruger, og prøv igen.</span>
                {% elif delete_feedback.kind == 'findes-ikke' %}
                <span class="block mt-1 text-rose-300/80">Listen nedenfor er den nyeste — brugeren kan være slettet i en anden fane, så genindlæs siden.</span>
                {% elif delete_feedback.kind == 'ugyldig' %}
                <span class="block mt-1 text-rose-300/80">Siden sendte ikke et gyldigt bruger-id. Genindlæs siden, og brug ✕ ud for brugeren igen.</span>
                {% endif %}
            </div>
            {% endif %}
            {% endif %}
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-4">
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3">
                    <div class="text-[11px] uppercase tracking-wider text-zinc-500 mb-2">Seneste login pr. bruger</div>
                    {% for u in users %}
                    <div class="text-[11px] flex justify-between gap-2"><span>{{ u['email'] }}</span><span class="text-zinc-500">{{ u['last_login_ip'] or '—' }} · {{ (u['last_login_at'] or '')[0:16] }}</span></div>
                    {% endfor %}
                </div>
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3">
                    <div class="text-[11px] uppercase tracking-wider text-zinc-500 mb-2">Login-forsøg (seneste 8)</div>
                    {% for r in login_rows %}
                    <div class="text-[11px] flex justify-between gap-2">
                        <span class="{{ 'text-emerald-400' if r['ok'] else 'text-rose-300' }}">{{ r['username'] or '?' }}</span>
                        <span class="text-zinc-500">{{ r['ip'] }} · {{ r['created_at'][5:16] }}</span>
                    </div>
                    {% else %}
                    <div class="text-[11px] text-zinc-500">Ingen endnu.</div>
                    {% endfor %}
                </div>
            </div>
            <div class="space-y-2">
                {% for u in users %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-center">
                    <div>
                        <span class="font-medium">{{ u.email }}</span>
                        {% if current_user and u.id == current_user.id %}<span class="text-[10px] text-emerald-400 ml-2">dig</span>{% endif %}
                        {% if u['must_change_password'] %}<span class="text-[10px] text-amber-400 ml-2">skal skifte kode</span>{% endif %}
                        <div class="text-zinc-500">Oprettet {{ u.created_at }}</div>
                    </div>
                    <form action="/users/delete" method="POST">
                        <input type="hidden" name="id" value="{{ u.id }}">
                        <button class="text-zinc-500 hover:text-rose-400" title="Slet {{ u.email }}">✕</button>
                    </form>
                </div>
                {% endfor %}
            </div>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">Inviter bruger</h2>
            {% if invite_feedback %}
            {% if invite_feedback.ok %}
            <div class="bg-emerald-500/10 border border-emerald-500/40 text-emerald-300 rounded-xl px-3 py-2 mb-3 text-xs">
                ✅ Invitationen er sendt til <b>{{ invite_feedback.message }}</b>. Brugeren får en midlertidig adgangskode i mailen — bed den inviterede tjekke spam, hvis den ikke dukker op.
            </div>
            {% else %}
            <div class="bg-rose-500/10 border border-rose-500/40 text-rose-300 rounded-xl px-3 py-2 mb-3 text-xs">
                ❌ <b>Invitationen blev ikke sendt</b> — og der blev ikke oprettet nogen bruger.
                {% if invite_feedback.kind == 'adresse' or invite_feedback.kind == 'eksempel' %}Adressen blev afvist, før der blev sendt noget:{% else %}Fejlen fra mailserveren:{% endif %}
                <code class="block mt-1 text-rose-200 break-all">{{ invite_feedback.message }}</code>
                {% if invite_feedback.kind != 'adresse' and invite_feedback.kind != 'eksempel' %}
                <span class="block mt-1 text-rose-300/80">Mangler <b>SMTP_HOST</b> + <b>SMTP_FROM</b> i <code>.env</code>, bliver der ikke sendt noget. Uden SMTP kan invitationen i stedet læses op med <code>python3 scripts/invite.py bruger@ditfirma.dk --print</code>.</span>
                {% endif %}
                {% if invite_feedback.kind == 'eksempel' and invite_feedback.email %}
                <form action="/users/invite" method="POST" class="mt-2 flex flex-wrap items-center gap-2">
                    <input type="hidden" name="email" value="{{ invite_feedback.email }}">
                    <input type="hidden" name="force" value="1">
                    <span class="text-rose-300/80">Er <b>{{ invite_feedback.email }}</b> rigtig alligevel?</span>
                    <button class="bg-rose-500/10 text-rose-200 border border-rose-500/40 px-3 py-1 rounded-lg text-xs">Opret alligevel</button>
                </form>
                {% endif %}
            </div>
            {% endif %}
            {% endif %}
            <form action="/users/invite" method="POST" class="grid grid-cols-1 md:grid-cols-2 gap-2">
                <input type="email" name="email" placeholder="bruger@ditfirma.dk" required maxlength="254" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Send invitation</button>
            </form>
            <p class="text-[10px] text-zinc-600 mt-2">Invitationen er en mail med en midlertidig adgangskode, som brugeren skifter ved foerste login. Kraever SMTP_HOST + SMTP_FROM i .env — mangler de, oprettes ingen bruger, og fejlen staar under Alarmer.</p>
        </div>
        <div class="bg-zinc-900 border border-zinc-800 rounded-2xl p-5">
            <h2 class="text-xs uppercase tracking-wider text-zinc-400 mb-3">MCP-adgang ({{ api_clients|length }} nøgler)</h2>
            {% if api_key_once %}
            <div class="bg-emerald-500/5 border border-emerald-500/40 rounded-xl p-3 mb-4">
                <div class="text-[11px] uppercase tracking-wider text-emerald-300 mb-1">Ny nøgle til {{ api_key_once.name }} — vises kun her</div>
                <code class="block text-xs text-emerald-200 break-all select-all" id="cc-api-key">{{ api_key_once.key }}</code>
                <p class="text-[10px] text-zinc-500 mt-2">Nøglen er allerede slettet fra databasen — kopiér den nu. Genindlæser du siden, er den væk, og du skal oprette en ny.</p>
            </div>
            {% endif %}
            <p class="text-xs text-zinc-500 mb-3">Hver MCP-klient får sin egen nøgle (ingen fælles token). Nøglen sendes som <code class="text-zinc-400">Authorization: Bearer …</code> til <code class="text-zinc-400">/mcp</code> og gemmes kun som hash — den kan tilbagekaldes enkeltvis. Selve nøglen findes i klartekst i databasen i det ene øjeblik den vises, og slettes i samme kald (højst 15 min. hvis siden aldrig åbnes). <code class="text-zinc-400">read</code> giver de syv læse-værktøjer; <code class="text-zinc-400">read,write</code> giver også <code class="text-zinc-400">start_crawl</code>, <code class="text-zinc-400">add_monitor</code>, <code class="text-zinc-400">resolve_alarm</code> og <code class="text-zinc-400">add_note</code>. Hvert kald havner i auditten nedenfor.</p>
            <form action="/api-keys/create" method="POST" class="grid grid-cols-1 md:grid-cols-3 gap-2 mb-4">
                <input type="text" name="name" placeholder="Navn, fx Claude Desktop" required minlength="2" maxlength="60" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                <select name="scopes" class="bg-zinc-950 border border-zinc-800 rounded-xl px-3 py-2 text-sm">
                    <option value="read">read (læs)</option>
                    <option value="read,write">read,write</option>
                </select>
                <button class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-5 py-2 rounded-xl text-sm">Opret nøgle</button>
            </form>
            <div class="space-y-2">
                {% for c in api_clients %}
                {% set u = api_usage.get(c.id) or {} %}
                <div class="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs flex justify-between items-center gap-3">
                    <div>
                        <span class="font-medium">{{ c.name }}</span>
                        <span class="text-zinc-600">…{{ c.key_hint or '????' }}</span>
                        <span class="text-[10px] text-zinc-500 ml-2">{{ c.scopes }}</span>
                        <span class="text-[10px] text-zinc-500 ml-2">{{ u.get('calls', 0) }} kald{% if u.get('errors') %} · <span class="text-rose-400">{{ u.get('errors') }} fejl</span>{% endif %}</span>
                        {% if c.revoked_at %}<span class="text-[10px] text-rose-400 ml-2">tilbagekaldt</span>{% endif %}
                        <div class="text-zinc-500">Oprettet {{ (c.created_at or '')[0:16] }} · sidst brugt {{ (c.last_used_at or '—')[0:16] }}{% if c.last_used_ip %} fra {{ c.last_used_ip }}{% endif %}</div>
                    </div>
                    {% if not c.revoked_at %}
                    <form action="/api-keys/revoke" method="POST">
                        <input type="hidden" name="client_id" value="{{ c.id }}">
                        <button class="text-zinc-500 hover:text-rose-400" title="Tilbagekald nøglen">✕</button>
                    </form>
                    {% endif %}
                </div>
                {% else %}
                <div class="text-[11px] text-zinc-500">Ingen nøgler endnu. Læse-værktøjer: health, crawl_summary, keywords, monitors, alarms_open, notes, history. Skrive-værktøjer (kræver write): start_crawl, add_monitor, resolve_alarm, add_note.</div>
                {% endfor %}
            </div>
            {% if api_audit %}
            <h3 class="text-[11px] uppercase tracking-wider text-zinc-500 mt-5 mb-2">Seneste MCP-kald (audit)</h3>
            <div class="space-y-1">
                {% for a in api_audit %}
                <div class="text-[11px] flex justify-between gap-3 {{ 'text-zinc-500' if a.ok else 'text-rose-400' }}">
                    <span class="truncate">{{ a.client or 'ukendt nøgle' }} · <span class="text-zinc-300">{{ a.tool or a.method }}</span>{% if a.detail %} — {{ a.detail }}{% endif %}</span>
                    <span class="text-zinc-600 shrink-0">{{ (a.created_at or '')[0:16] }}{% if a.duration_ms %} · {{ a.duration_ms }} ms{% endif %}</span>
                </div>
                {% endfor %}
            </div>
            {% endif %}
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


<div id="cc-task" class="hidden fixed bottom-4 right-4 z-[60] w-80 max-w-[90vw] rounded-2xl border border-zinc-800 bg-zinc-900/95 backdrop-blur-md p-3 shadow-2xl shadow-black/60 text-xs" role="status" aria-live="polite">
    <div class="flex items-center justify-between mb-1.5">
        <span id="cc-task-label" class="text-zinc-200 font-medium">Arbejder…</span>
        <button type="button" onclick="ccTaskHide()" class="text-zinc-500 hover:text-rose-400" aria-label="Skjul fremdrift">✕</button>
    </div>
    <div class="h-1.5 bg-zinc-800 rounded-full overflow-hidden"><div id="cc-task-bar" class="h-full bg-emerald-500 transition-all duration-500" style="width:0%"></div></div>
    <div class="flex items-center justify-between mt-1.5 text-[11px] text-zinc-500"><span id="cc-task-pct">0 %</span><span id="cc-task-eta"></span></div>
    <p id="cc-task-note" class="text-[10px] text-zinc-500 mt-1 hidden"></p>
</div>
<div id="cc-toast" class="hidden fixed bottom-4 left-4 z-[60] rounded-xl border border-emerald-500/30 bg-zinc-900/95 backdrop-blur-md px-3 py-2 text-xs text-emerald-300 shadow-lg" role="status"></div>

<script>
    // ---- Opgave-fremdrift: timer, procent og ETA paa alle laengere opgaver ----
    const CC_EST = {{ task_estimates | tojson }};
    let ccTask = null;
    function ccEl(id) { return document.getElementById(id); }
    function ccEstimate(path) {
        if (CC_EST[path]) return CC_EST[path];
        let best = null, len = 0;
        for (const key in CC_EST) {
            if (key.endsWith('/') && path.startsWith(key) && key.length > len) { best = CC_EST[key]; len = key.length; }
        }
        return best;
    }
    function ccRender() {
        if (!ccTask) return;
        const elapsed = (Date.now() - ccTask.start) / 1000;
        let pct, eta;
        if (ccTask.live) { pct = ccTask.percent || 0; eta = ccTask.eta; }
        else { pct = Math.min(95, Math.round(elapsed / ccTask.seconds * 100)); eta = Math.round(ccTask.seconds - elapsed); }
        ccEl('cc-task-bar').style.width = pct + '%';
        ccEl('cc-task-pct').textContent = pct + ' %';
        if (ccTask.live) {
            ccEl('cc-task-eta').textContent = ccTask.detail || '';
        } else {
            ccEl('cc-task-eta').textContent = eta > 0 ? '~' + eta + ' s igen' : 'tager lidt laengere end forventet';
        }
    }
    function ccTaskStart(label, seconds) {
        if (ccTask && ccTask.timer) clearInterval(ccTask.timer);
        ccTask = { label: label, seconds: Math.max(1, seconds || 10), start: Date.now(), timer: null, live: false };
        try { sessionStorage.setItem('ccLastTask', JSON.stringify({ label: label, start: ccTask.start })); } catch (e) {}
        ccEl('cc-task').classList.remove('hidden');
        ccEl('cc-task-label').textContent = label;
        ccEl('cc-task-note').classList.add('hidden');
        ccEl('cc-task-bar').className = 'h-full bg-emerald-500 transition-all duration-500';
        ccTask.timer = setInterval(ccRender, 250);
        ccRender();
    }
    function ccTaskDone(ok, note) {
        if (!ccTask) return;
        const elapsed = Math.round((Date.now() - ccTask.start) / 1000);
        if (ccTask.timer) clearInterval(ccTask.timer);
        ccEl('cc-task-bar').style.width = '100%';
        ccEl('cc-task-bar').className = 'h-full transition-all duration-500 ' + (ok === false ? 'bg-rose-500' : 'bg-emerald-500');
        ccEl('cc-task-pct').textContent = '100 %';
        ccEl('cc-task-eta').textContent = ok === false ? 'fejlede' : 'faerdig paa ' + elapsed + ' s';
        if (note) { ccEl('cc-task-note').textContent = note; ccEl('cc-task-note').classList.remove('hidden'); }
        try { sessionStorage.removeItem('ccLastTask'); } catch (e) {}
        ccTask = null;
        setTimeout(function () {
            if (ccTask) return;
            ccEl('cc-task').classList.add('hidden');
            ccEl('cc-task-note').classList.add('hidden');
        }, note ? 8000 : 2500);
    }
    function ccTaskHide() {
        if (ccTask && ccTask.timer) clearInterval(ccTask.timer);
        ccTask = null;
        ccEl('cc-task').classList.add('hidden');
    }
    // Alle fetch-kald med et estimat faar timer + ETA
    (function () {
        const orig = window.fetch;
        window.fetch = function (input, init) {
            const url = typeof input === 'string' ? input : (input && input.url) || '';
            const meta = ccEstimate(url.split('?')[0]);
            if (!meta) return orig.apply(this, arguments);
            if (!ccTask) ccTaskStart(meta.label, meta.seconds);
            return orig.apply(this, arguments).then(
                function (res) { ccTaskDone(true); return res; },
                function (err) { ccTaskDone(false); throw err; }
            );
        };
    })();
    // Tunge formularer: start timeren (0 ms udsaettelse, saa "confirm"-afvisning respekteres)
    document.addEventListener('submit', function (e) {
        const form = e.target;
        if (!form || (form.getAttribute('method') || 'get').toLowerCase() !== 'post') return;
        const meta = ccEstimate(new URL(form.getAttribute('action') || form.action, location.href).pathname);
        if (!meta) return;
        setTimeout(function () {
            if (e.defaultPrevented || ccTask) return;
            ccTaskStart(meta.label, meta.seconds);
            ccEl('cc-task-note').textContent = 'Lad siden staa - den skifter selv, naar opgaven er faerdig.';
            ccEl('cc-task-note').classList.remove('hidden');
        }, 0);
    }, true);
    // Crawl koerer i baggrunden: vis serverens procent + ETA
    function ccPollCrawl() {
        fetch('/api/crawl/status').then(function (r) { return r.json(); }).then(function (s) {
            if (s.running) {
                if (!ccTask) ccTaskStart('Site-crawl', 120);
                ccTask.live = true;
                ccTask.percent = s.percent || 0;
                ccTask.eta = s.eta_seconds;
                ccTask.detail = (s.done || 0) + '/' + (s.total || 0) + ' sider' + (s.eta_seconds ? ' · ~' + s.eta_seconds + ' s igen' : '');
                ccRender();
                setTimeout(ccPollCrawl, 3000);
            } else if (ccTask && ccTask.live) {
                ccTaskDone(true, 'Crawl faerdig - genindlaes siden for at se siderne.');
            }
        }).catch(function () {});
    }
    // Toasts efter en side-genindlaesning (fx tung formular der redirecter)
    (function () {
        try {
            const raw = sessionStorage.getItem('ccLastTask');
            if (!raw) return;
            const t = JSON.parse(raw);
            sessionStorage.removeItem('ccLastTask');
            const age = Math.round((Date.now() - (t.start || Date.now())) / 1000);
            if (age < 900) {
                ccEl('cc-toast').textContent = (t.label || 'Opgave') + ' faerdig paa ' + age + ' s';
                ccEl('cc-toast').classList.remove('hidden');
                setTimeout(function () { ccEl('cc-toast').classList.add('hidden'); }, 4000);
            }
        } catch (e) {}
    })();
    ccPollCrawl();

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

    // ---- Vækst (v7.24): fanebeskrivelser, indholdsoptimering og konkurrent-sammenligning ----
    const ccTabInfo = {
        cockpit: { title: 'Cockpit', hint: 'Overvågning, budget, jobs og åbne alarmer' },
        seo: { title: 'SEO & audit', hint: 'Enkelt side, crawl, duplikater og redirects' },
        keywords: { title: 'Keywords', hint: 'Positioner, idéer, sværhedsgrad og synlighed' },
        vaekst: { title: 'Vækst', hint: 'Optimer indhold, mål mod konkurrenter og hold planen' },
        articles: { title: 'Indhold', hint: 'Artikler, kvalitetsgate og WordPress-kladder' },
        links: { title: 'Links', hint: 'Brudte links og forslag til interne links' },
        spy: { title: 'Spy', hint: 'Find og læs konkurrenternes sider' },
        social: { title: 'Social', hint: 'Opslagskø og broen til Steamgears Autopilot' },
        monitors: { title: 'Monitors', hint: 'Tekst-, JSON- og prisovervågning' },
        ai: { title: 'AI-værktøjer', hint: 'Titel/meta, outreach og AI-synlighed' },
        pro: { title: 'Pro', hint: 'Content gap, sværhedsgrad og e-mailfund' },
        moduler: { title: 'Moduler', hint: 'Slå funktionsområder til og fra' },
        brugere: { title: 'Brugere', hint: 'Adgang, invitationer og MCP-nøgler' },
        alarms: { title: 'Alarmer', hint: 'Hvad der kræver din opmærksomhed' },
        notes: { title: 'Noter', hint: 'Hurtige noter til arbejdsflowet' }
    };

    // Den aktive fane skal altid vaere synlig i den vandrette navigation - ogsaa paa mobil.
    function ccScrollActiveTab() {
        const el = document.querySelector('.cc-nav-link.is-active');
        if (!el || !el.scrollIntoView) return;
        const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        el.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', inline: 'center', block: 'nearest' });
    }
    document.addEventListener('alpine:initialized', function () { setTimeout(ccScrollActiveTab, 60); });
    document.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('.cc-nav-link')) { setTimeout(ccScrollActiveTab, 30); }
    });

    function ccFormBody(form) { return new URLSearchParams(new FormData(form)); }

    function ccOptimize(form) {
        const s = ccState();
        s.growthLoading = true; s.growthError = ''; s.growth = null;
        fetch('/growth/optimize', { method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: ccFormBody(form) })
            .then(function (r) { return r.json(); })
            .then(function (d) { if (!d.ok) { s.growthError = d.error || 'Analysen fejlede'; } else { s.growth = d; } })
            .catch(function () { s.growthError = 'Netværksfejl - prøv igen'; })
            .finally(function () { s.growthLoading = false; });
    }

    function ccCompare(form) {
        const s = ccState();
        s.cmpLoading = true; s.cmpError = ''; s.cmp = null;
        fetch('/growth/compare', { method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: ccFormBody(form) })
            .then(function (r) { return r.json(); })
            .then(function (d) { if (!d.ok) { s.cmpError = d.error || 'Sammenligningen fejlede'; } else { s.cmp = d; } })
            .catch(function () { s.cmpError = 'Netværksfejl - prøv igen'; })
            .finally(function () { s.cmpLoading = false; });
    }
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
    <title>Command Center — {{ 'Opret foerste bruger' if mode == 'setup' else 'Log ind' }}</title>
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
      .setup { margin: 0 0 14px; padding: 9px 11px; font-size: 12px; color: #fbbf24;
               background: rgba(251,191,36,.08); border: 1px solid rgba(251,191,36,.3); border-radius: 10px; }
      .foot { margin: 16px 0 0; font-size: 11px; color: #71717a; text-align: center; }
      .report { margin: 20px 0 0; padding: 12px 14px; background: #09090b; border: 1px solid #27272a; border-radius: 12px; }
      .report .row { display: flex; justify-content: space-between; gap: 10px; font-size: 11px; padding: 3px 0; color: #a1a1aa; }
      .report .row b { color: #e4e4e7; font-weight: 600; text-align: right; }
      .report .row b.warn { color: #fbbf24; }
    </style>
</head>
<body>
<div class="card">
    <h1>⚡ COMMAND CENTER</h1>
    {% if mode == 'setup' %}
    <p class="sub">Der findes ingen brugere endnu - opret den foerste nedenfor.</p>
    <p class="setup">Vil du hellere have standardbrugeren automatisk? Skriv CC_ADMIN_EMAIL og
      CC_ADMIN_PASSWORD i <code>.env</code> og genstart appen - saa oprettes kontoen ved opstart,
      og denne side bruges ikke.</p>
    {% else %}
    <p class="sub">Log ind med din e-mail og adgangskode.</p>
    {% endif %}
    {% if error %}<p class="error">{{ error }}</p>{% endif %}
    <form action="{{ '/setup' if mode == 'setup' else '/login' }}" method="POST">
        <label for="email">E-mail</label>
        <input id="email" type="email" name="email" value="{{ email }}" autocomplete="email"
               placeholder="navn@domaene.dk" maxlength="254" required autofocus>
        <label for="password">Adgangskode</label>
        <input id="password" type="password" name="password" autocomplete="{{ 'new-password' if mode == 'setup' else 'current-password' }}"
               minlength="8" required>
        {% if mode == 'setup' %}
        <label for="confirm">Gentag adgangskode</label>
        <input id="confirm" type="password" name="confirm" autocomplete="new-password" minlength="8" required>
        {% endif %}
        <button type="submit">{{ 'Opret bruger og log ind' if mode == 'setup' else 'Log ind' }}</button>
    </form>
    {% if report %}
    <div class="report">
      <div class="row"><span>Version</span><b>v{{ report.version }}{% if report.commit %} · {{ report.commit[:7] }}{% endif %}</b></div>
      <div class="row"><span>Seneste opstart</span><b>{{ (report.last_start or '—')[0:16] }}</b></div>
      <div class="row"><span>Aabne alarmer</span><b{% if report.alarms_open %} class="warn"{% endif %}>{{ report.alarms_open }}{% if report.alarms_critical %} ({{ report.alarms_critical }} kritiske){% endif %}</b></div>
      <div class="row"><span>Domæner / keywords / monitors</span><b>{{ report.domains }} / {{ report.keywords }} / {{ report.monitors }}</b></div>
      <div class="row"><span>Seneste domænetjek</span><b>{{ (report.last_domain_check or '—')[0:16] }}</b></div>
      <div class="row"><span>Seneste crawl</span><b>{{ (report.last_crawl or '—')[0:16] }}</b></div>
      <div class="row"><span>Database</span><b>{{ report.db_mb ~ ' MB' if report.db_mb is not none else '—' }}</b></div>
      <div class="row"><span>Din IP</span><b>{{ client_ip }}</b></div>
      <div class="row"><span>Nyheder</span><b>{{ report.newest[0] if report.newest else '—' }}</b></div>
    </div>
    {% endif %}
    <p class="foot">Adgangskoder gemmes som PBKDF2-SHA256-hash. Sessionen varer 30 dage.<br>
      Standardbrugeren oprettes ved opstart fra CC_ADMIN_EMAIL + CC_ADMIN_PASSWORD i <code>.env</code>.</p>
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
VERSION="$(sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' app/main.py | head -1)"
NEWEST="$(sed -n 's/^NEWEST_LINE = "\(.*\)"/\1/p' app/main.py | head -1)"
echo "⚡ Starter Command Center v${VERSION:-?}..."
[ -n "$NEWEST" ] && echo "   Nyheder:  $NEWEST"
echo "   (version + alle nyheder skrives ogsaa til app/data/startup.log ved opstart)"
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
#
# MCP-adgang (v7.16) bruger samme location: POST /mcp svarer med almindelig JSON (ingen SSE), saa
# proxy_buffering off + de 300 s timeouts nedenfor er rigeligt. Appen sender selv X-Accel-Buffering: no.

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
# Lader .env-vaerdier som GITHUB_TOKEN og AIMLAPI_KEY blive rigtige miljoevariabler
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
# Command Center v7.24 PRO

[![CI](https://github.com/humle93/command-center/actions/workflows/ci.yml/badge.svg)](https://github.com/humle93/command-center/actions/workflows/ci.yml)

Selv-hostet SEO- og drifts-center (FastAPI + SQLite) i stil med RankMath Pro / Yoast Premium — bygget til Steamgears.
Alt kører på din egen server: dine data, ingen abonnement. Se [docs/ROADMAP.md](docs/ROADMAP.md) for hvad der er færdigt og hvad der er næste.

## Nyheder i v7.24

- **Vækst-fanen (v7.24.0)** — en lokal udgave af det, Surfer, Ahrefs, Semrush og BabyLoveGrowth gør, uden API-nøgle: **indholdsoptimerer** med vægtet 0-100-score, termdækning og prioriteret forbedringsliste, **sammenligning** med op til tre konkurrent-URL'er du selv peger på, **indholdsplan** med briefs (mål for ord og H2, termer, overskrifter og konkurrenternes vinkler) og en **linkliste** med kontakt, begrundelse og status. Alt regnes lokalt — ingen nøgler, ingen eksterne AI-kald og ingen data der forlader serveren
- **Moderniseret UI (v7.24.0)** — navigationen er delt i grupper (overblik, analyse, produktion, drift, system) med tydelig aktiv fane, hver fane har en kort beskrivelse øverst, og kort, felter, knapper og tabeller har fået én fælles visuel rytme. Funktioner, ruter og genveje er de samme

## Nyheder i v7.22

- **Backup i UI (v7.23.0)** — fanen Moduler viser alle backups med "Tag backup nu" og "Gendan". Gendannelse kræver at skrive `GENDAN`, og der tages altid en `pre-restore`-kopi først.
- **Offline dashboard (v7.22.0)** — dashboardet henter ikke længere Tailwind, Alpine eller Chart.js fra CDN. De ligger lokalt i `app/static/vendor/`, så UI'et virker uden internet.

## Nyheder i v7.21

- **CSRF-beskyttelse (v7.21.0)** — muterende kald fra et andet site afvises med 403. Hvert login giver en ny session, og den gamle sid slettes.

## Nyheder i v7.20

- **Budget og jobstatus på Cockpit (v7.20.0)** — kortet "API-budget denne måned" viser forbrug og loft for SerpAPI og AI, og "Planlagte jobs (heartbeat)" viser hvornår hvert job sidst kørte. Et job der holder op med at køre, eller fejler, giver én alarm.

## Nyheder i v7.19

- **Standardbruger fra `.env` (v7.18.0)** — er `users` tom, oprettes kontoen ved opstart fra `CC_ADMIN_EMAIL` + `CC_ADMIN_PASSWORD`, så et nyt deployment kan logge ind med det samme; `/setup` er reserve. Koden skal skiftes ved første login, og en rettet `.env` rører ikke en konto i brug.
- **`.env` rydder sig selv (v7.19.1–v7.19.2)** — skifter standardbrugeren koden under Brugere, fjernes `CC_ADMIN_PASSWORD` fra `.env`, og dashboardet viser hvem og hvornår. En advarsel vises, hvis linjen alligevel er forældet.
- **Autopilot-broen læser hele `/snapshot` (v7.19.0)** — selvtjek, cron-forsinkelse og pause-årsag i ét kald, reserve til `/stats` for ældre plugins, og CC holder WP-Cron i gang hvert 5. minut.

## Nyheder i v7.17

**Standardbrugeren i `.env` — ét samlet forløb (v7.18 → v7.20).** Hele vejen fra kontoen oprettes, til filen ikke kan komme til at lyve om koden. De fire trin bygger på hinanden og vises i appen som én nyhed (v7.20.0):

- **Kontoen oprettes ved deployment (v7.18.0)** — skriv `CC_ADMIN_EMAIL` + `CC_ADMIN_PASSWORD` i `.env`, så oprettes kontoen ved opstart, og du kan logge ind med det samme; opsætningssiden er ikke længere en del af et normalt deployment. Koden gemmes kun som PBKDF2-hash, kontoen oprettes med `must_change_password` (gul bjælke indtil du skifter den under fanen **Brugere**), og der seedes kun, når `users` er tom — en senere ændring af `.env` rører ikke en konto i brug. Er linjerne tomme, er `/setup` stadig reserven. Adgangskoden står kun i `.env` (gitignored), aldrig i repoet eller i loggen
- **Advarsel når koden er forældet (v7.18.1)** — skifter du koden under **Brugere**, passer `CC_ADMIN_PASSWORD` ikke længere. Så skriver opstartsloggen `[cc] advarsel: …`, advarslen ligger under **Alarmer**, og dashboardet viser en rød bjælke, indtil du retter eller fjerner linjen i `.env`. Kontoen røres ikke — login bruger den nye kode
- **Linjen rydder sig selv (v7.19.1)** — skifter **du** koden under **Brugere**, tømmes `CC_ADMIN_PASSWORD` i `.env` automatisk (kun den linje; kommentarer og de andre nøgler står urørt). Så kan filen ikke komme til at love en kode, login afviser. Kan filen ikke skrives, ændres intet ved kontoen — så bliver advarslen fra v7.18.1 stående i stedet
- **Dashboardet viser rydningen (v7.19.2)** — øverst står en blå bjælke med tidspunkt og navn, fx "CC_ADMIN_PASSWORD blev fjernet fra .env 5. november 2026 kl. 23:19 af henning", så du kan se filens tilstand uden at åbne den. Sætter du linjen tilbage i `.env`, skifter bjælken tekst og siger det, så den ikke påstår noget forkert; bliver koden samtidig forældet, vinder den røde advarsel. Kun navn og tidspunkt gemmes (i `settings` under `env_password_cleared`) — aldrig en kode — så rydningen også ses efter en genstart

- **MCP-hærdning (v7.17.1)** — nøglen ligger ikke længere i klartekst i databasen: rækken i `settings` slettes i samme kald som dashboardet viser den (højst 15 min. hvis siden aldrig åbnes, og oprydningen fjerner resten). "Jeg har gemt nøglen"-knappen er derfor væk. Ukendte værktøjsnavne på `/mcp` havner nu også i auditten, så en nøgle der famler kan ses.
- **MCP skriver nu også (fase 2)** — med `read,write` på nøglen kan en agent starte et site-crawl, oprette en monitor, løse en alarm og skrive en note (`start_crawl`, `add_monitor`, `resolve_alarm`, `add_note`). Hvert kald — også afviste — havner i en **audit pr. nøgle** (`api_audit`) med værktøj, varighed og fejl, som du ser i fanen **Brugere** og med `python3 scripts/api_key.py audit`. Værktøjerne har `readOnlyHint`/`destructiveHint`, så klienten kan advare før et kald.
- **MCP-adgang (fase 1)** — agenter og editorer kan læse Command Center direkte. Under fanen **Brugere** opretter du en nøgle pr. klient (ingen fælles token); den vises én gang, gemmes kun som sha256 og kan tilbagekaldes enkeltvis. `POST /mcp` tilbyder syv læse-værktøjer: `health`, `crawl_summary`, `keywords`, `monitors`, `alarms_open`, `notes` og `history`. Endpointet validerer `Origin`/`Host` (DNS-rebinding) og svarer `401` med `WWW-Authenticate` uden nøgle — se [docs/Command_Center_MCP.md](docs/Command_Center_MCP.md).
- **E-mail er login (v7.15)** — første besøg opretter din bruger med e-mail + adgangskode (`/setup`), derefter logger du ind med e-mail og adgangskode (PBKDF2-SHA256, salt pr. bruger, 30 dages HttpOnly-session). Gamle konti fra brugernavn-tiden kan stadig logge ind med deres brugernavn, indtil de får en e-mail.
- **Invitation på mail (v7.15, svar i v7.17.2)** — fanen **Brugere** har "Inviter bruger": du skriver en e-mail, og appen sender en invitation med en midlertidig adgangskode, som brugeren skifter ved første login (dashboardet minder om det). Der er ingen invite-links og ingen tokens - kun en adgangskode. Svaret lander i den samme formular: blev mailen sendt, står der hvilken adresse den gik til, og fejler den, står mailserverens fejl der med det samme i stedet for kun under Alarmer. En adresse, der ligner eksemplet fra dokumentationen (`navn@domaene.dk`), afvises med en forklaring i formularen — så en pladsholder eller tastefejl ikke bliver en konto uden modtager; er adressen rigtig alligevel, oprettes den med knappen **Opret alligevel**.
- ⏱️ **Fremdrift på opgaver** — tunge handlinger (crawl, AI-artikel, keyword-tjek, backlink-prospecting …) viser timer, procent og "~N s igen"; crawl læser de rigtige tal (sider/total + ETA) fra `/api/crawl/status`
- **Opdatering fra GitHub** — Cockpit viser installeret commit vs. seneste commit på `main`, tjekker selv kl. 05:00, og "Opdater" laver DB-backup og henter kun projektets filer. Den gamle "hent install.sh og kør den"-vej er fjernet.
- **nginx / Ultra.cc** — `deploy/nginx-command-center.conf`, `deploy/command-center.user.service` og proxy-header-understøttelse, så appen bliver på `127.0.0.1` bag nginx med korrekte Secure-cookies og rigtig klient-IP.
- **Rettelser fra kodegennemgang** — saniteret artikel-HTML (XSS), `.env` læses før konfigurationen, pris-monitors registrerer ændringer igen, crawl-diff virker (to crawls gemmes), `/monitors/add` giver ikke længere 500, HTTPS-advarslen rammer rigtigt, plus mindre korrekthedsrettelser.

## Funktioner

- 🎛️ **Cockpit** — domæneovervågning (uptime, svartid, SSL), opdaterings-panel og alarmer
- 🔍 **SEO Scanner** — deep audit af enkelt side (20+ vægtede kontroller inkl. focus keyword, læsbarhed, mixed content, schema, OG/Twitter) + **site-crawl** med score per side, robots.txt/sitemap-tjek og crawl-diff mod forrige crawl
- ✍️ **Artikler** — AI-generering (Gemini via aimlapi) eller skabelon, **push til WordPress som udkast**, **fakta-prompt med SerpAPI-konkurrentanalyse**, autopilot (idé → artikel → WP-kladde) og **kvalitetsgate** før publicering
- 🎯 **SEO-strategi** — AdSense / Affiliate / Backlink-vækst styrer AI-artiklernes stil + længde og autopilotens arbejde, med automatisk pre-flight-checkliste
- 🌱 **Growth Pack** — backlink-prospector (SerpAPI top 10 → sitetype + kontakt-e-mail + AI-outreach-draft), keyword-ideer via Google/DDG-autocomplete, visibility-index
- 🎯 **Keywords** — Google-positioner via SerpAPI (dagligt kl. 06:00), sværhedsgrads-heuristik, content gap mod top 10
- 🚀 **Vækst** — lokal indholdsoptimering uden API-nøgle: score og termdækning for en tekst eller URL, sammenligning mod op til tre konkurrent-URL'er, indholdsplan med briefs og en manuel linkliste. Måler kun det, der står i teksten — ingen søgevolumen, ingen backlink-data
- 🕷️ **SERP & Spy** — konkurrent-opdagelse + crawl af titel/H1/beskrivelse
- 🔗 **Links** — ekstern linktjek + AI-forslag til interne links
- 📱 **Social** — opslagskø med CSV-export og "→ Autopilot" (kladde i WordPress-pluginnet — kun **én** kladde pr. opslag, også ved dobbeltklik). Planlagt tid indtastes i lokal tid og gemmes som **lokal tid + UTC**, så sommertid ikke flytter opslaget
- 🩺 **Monitors** — tekst/JSON/pris-overvågning med alarmer ved ændring
- 🤖 **AI-synlighed** — stil en kundes spørgsmål til AI-modellen og se, om `TRACK_DOMAIN` nævnes i svaret (historik i `ai_visibility`)
- 📝 **Noter** — hurtige workflow-noter i dashboardet (`/notes/add`, `/notes/delete`)
- 👤 **Brugere** — invitér/slet brugere, skift adgangskode og opret **MCP-nøgler** pr. klient (hash, scopes, tilbagekald); den sidste bruger kan ikke slettes, og både en gennemført og en afvist sletning svarer i fanen med det samme i stedet for kun at ende som en alarm
- 🚨 **Alarmer** — SSL-udløb, nedetid, brudte links, fejlede scans, nye GitHub-commits; valgfrit Telegram-push
- 📈 **Historik** — svartid per domæne, site-health og visibility over tid (Chart.js)

## Skærmbilleder

![Cockpit](docs/img/cc-cockpit.png)

Cockpit med opdaterings-panel og alarmer. Login-siden og alle 15 faner ligger i `docs/img/`
(`cc-login.png`, `cc-cockpit.png` … `cc-notes.png`); billederne er taget med
`python3 scripts/screenshots.py` mod den kørende app, og samme kommando opdaterer dem — se
[manualens afsnit om screenshots](docs/Command_Center_Bruger_og_Systemmanual.md#opdater-screenshots).

## Login & opsætning

1. `cp .env.example .env` og udfyld nøgler — bl.a. `CC_ADMIN_EMAIL` + `CC_ADMIN_PASSWORD` til standardbrugeren, så den findes efter deployment
2. `./run.sh` — scriptet udskriver den adresse appen lytter på (samt LAN-IP når `CC_HOST=0.0.0.0`)
3. Åbn adressen: **standardbrugeren oprettes ved opstart**, så du logger ind med e-mail + adgangskode med det samme (koden fra `.env` skal skiftes under fanen **Brugere** ved første login). Er de to linjer tomme, opretter første besøg brugeren via `/setup` i stedet — det er reserven. Der er ingen token i `.env`.
4. Nye brugere inviteres på mail, og sletning/adgangskode-skift klares under fanen **Brugere** (kræver `SMTP_HOST` + `SMTP_FROM`); fra serveren kan samme invitation sendes med `python3 scripts/invite.py navn@domaene.dk` — og med `--print` udskrives mailen i stedet, så den kan sendes fra en anden mailkonto når SMTP ikke er sat op. Scriptet tager én adresse ad gangen og afviser eksempel-adresser som `navn@domaene.dk`, så en tastefejl ikke bliver en bruger. Helt uden mail kan brugeren oprettes direkte med `python3 scripts/user_create.py navn@domaene.dk --username humle91` (koden skrives skjult og skal være min. 8 tegn)
5. (VPS) kør bag reverse proxy med TLS, eller brug `deploy/command-center.service` + SSH-tunnel
6. Vil du have en agent på? Opret en nøgle under **Brugere → MCP-adgang** og peg klienten på `https://<din-adresse>/mcp` (se nedenfor)

## MCP-adgang (v7.16)

Fase 1 er **læse-adgang** (syv værktøjer); fase 2 tilføjer fire **skrive-værktøjer** med `write`-scope
og audit pr. nøgle. Alt over MCP (Streamable HTTP, JSON-svar) på `/mcp`.

```bash
# nøgle fra terminalen (samme tabel som UI'et) - vises kun én gang
python3 scripts/api_key.py create "Claude Desktop" read

# prøv endpointet
curl -s https://<din-adresse>/mcp -H "Authorization: Bearer cc_..." \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

- Nøglen sendes altid i `Authorization: Bearer …` (aldrig i query string) og gemmes kun som hash. Den vises **én gang** — rækken med klartekst slettes i samme kald som dashboardet viser den.
- `scopes`: `read` (kun læsning) eller `read,write` (læsning + de fire skrive-værktøjer). Manglende scope giver `-32003`.
- `Origin`/`Host` valideres mod `CC_PUBLIC_URL`; ukendt vært giver `421`, fremmed origin `403`.
- Ukendte værktøjsnavne og manglende scopes havner også i auditten (`ok=0`), så et nøgle der prøver ting af kan ses.
- `python3 scripts/api_key.py list` viser nøglerne (kun halen), `revoke <id>` slår dem fra med det samme, og `audit [antal]` viser de seneste kald pr. nøgle.
- Læse-værktøjer: `health`, `crawl_summary`, `keywords`, `monitors`, `alarms_open`, `notes`, `history`.
- Skrive-værktøjer (`write`): `start_crawl` (afvises hvis et crawl kører), `add_monitor` (samme url+type oprettes ikke to gange), `resolve_alarm`, `add_note`.

## Ultra.cc / nginx (reverse proxy)

1. `.env`: `cp .env.example .env` og udfyld nøglerne. Sæt `CC_PUBLIC_URL` til **præcis** den adresse du åbner i browseren — med `https://`, uden anførselstegn og uden sti (`CC_PUBLIC_URL=https://humle91.ultra.cc`). Lad `CC_HOST=127.0.0.1` og `CC_FORWARDED_ALLOW_IPS=127.0.0.1` stå. `install.sh` skriver kun `.env.example`, og opdateringer rører aldrig `.env` — så linjen forbliver tom, indtil du selv udfylder den
2. Start appen: `./run.sh`, eller `deploy/command-center.user.service` med `systemctl --user enable --now command-center`
3. Læg `deploy/nginx-command-center.conf` ind i den `server { }` du bruger (Ultra.cc: `~/.apps/nginx/proxy.d/`), og genindlæs nginx
4. Åbn `CC_PUBLIC_URL` — standardbrugeren fra `.env` kan logge ind med det samme (er linjerne tomme, opretter første besøg din bruger via `/setup`)

`CC_PUBLIC_URL` styrer login-linket i `scripts/update.sh` og `scripts/user_create.py`, adressen i invitationsmailen og Host-tjekket på `/mcp`. Tjek med `bash scripts/update.sh --check`: står der `127.0.0.1` som login-adresse, er linjen tom eller skrevet forkert. Er `/mcp` utilgængelig med `421`, er det samme linje — værten skal matche ord for ord, og et sæt anførselstegn omkring værdien er nok til at ødelægge den.

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
- **Fra terminalen**: `bash scripts/update.sh` gør hele kæden (tjek → filer → requirements → genstart) og venter til `/health` svarer igen; `--check` tjekker kun, `--no-restart` springer genstarten over. Øverst viser scriptet **tre** versioner ved siden af hinanden: den der **kører nu** (fra `/health`), den **filerne** indeholder (`app/main.py`), og den **installatøren** vil skrive (`install.sh`s indlejrede `app/main.py`) — plus login-adressen fra `CC_PUBLIC_URL`. `bash scripts/update.sh --version` er den samme kontrol som rent svar: kode 0 kun når alle tre stemmer, ellers kode 1 med en linje om hvad der er galt. Opdateringen bruger kontrollen selv: er `install.sh` på disken ældre end koden, skriver den **ingen** filer — den stopper med kode 7 og siger, at installatøren skal hentes fra git først (`git checkout -- install.sh`). `bash scripts/restart.sh` genstarter uden at opdatere.
- Status som JSON: `GET /api/update` (inkl. `restart_mode` og `auto_restart`). Kræver `GITHUB_TOKEN` (privat repo). `/self-update` findes stadig som alias for `/update/apply`.

## Steamgears Autopilot-bro (WordPress-plugin 7.5+)

Command Center og WordPress-pluginnet **Steamgears Autopilot** snakker sammen via pluginnets REST-API
(`/wp-json/sgap/v1`) med de samme `WP_URL` / `WP_USER` / `WP_APP_PASSWORD` som WordPress-push
(`WP_USER` skal være administrator).

- **Status hver 30. min** (fanen Social → "Steamgears Autopilot"): kø, kladder der venter på godkendelse, og udgivet/klik/ordrer/omsætning pr. kanal de sidste 30 dage. Hentes fra pluginnets `GET /snapshot` (ét kald) med pluginversion, pause-årsag, WP-Cron-forsinkelse og pluginnets eget selvtjek; ældre plugins uden `/snapshot` læses via `/stats` + `/drafts` som før
- **Alarmer** når noget ændrer sig: nye fejlede opslag, nye kladder, nye problemer i pluginnets selvtjek, manglende tabeller, eller pluginnet svarer ikke
- **WP-Cron holdes i gang**: CC kalder `wp-cron.php` hvert 5. min, så pluginnets job (udgivelse, selvtjek) kører til tiden, selvom sitet har få besøg
- **Pluginnet ser CC**: hvert kald sender `X-Command-Center: <version>`; Steamgears Autopilot 7.33+ viser "Command Center connected" i sit selvtjek og melder et problem, hvis CC har været tavs i over 2 timer
- **"→ Autopilot"** sender et opslag som kladde til pluginnet (godkendes i WordPress under Steamgears → AI Drafts). Opslaget sendes **kun én gang**: rækken låses før kaldet, så et dobbeltklik eller et genforsøg ikke giver to kladder. Svarer WordPress ikke (timeout), bliver status "sendt? (svar udeblev)" — tjek AI Drafts, før du sender igen
- **Log ind på Command Center fra WordPress** — knappen **🔑 Log ind på Command Center** i fanen Social lægger et engangslink i pluginnet (`POST /login-link` på `sgap/v1`, gemt som option), og knappen i WordPress åbner det. Linket logger dig ind på CC uden adgangskode: koden gemmes kun som sha256, virker **én gang** og udløber efter 10 minutter. Er den brugt eller udløbet, forklarer login-siden det — så en gammel knap ikke ser ud som et brudt login. Retningen er stadig CC → site
- Slå til/fra under Moduler ("Autopilot-bro"). Retningen er altid CC → site, så CC kan blive på 127.0.0.1
- **Begge sider viser, hvornår CC sidst kaldte**: hvert kald har `X-Command-Center`-headeren, så WordPress noterer tid, version, rute og bruger (`sgap_cc_seen`). Pluginnets kort viser alderen (`live` / `late` / `silent`), og fanen Social viser **WordPress' eget svar** — samme tal, regnet ud ved visning. Er broen brudt, siger begge sider det i stedet for at se stille ud

## Installering

```bash
curl -H "Authorization: Bearer <TOKEN>" -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/humle93/command-center/contents/install.sh -o install.sh && bash install.sh
```

Eller med Docker: `cp .env.example .env && docker compose up -d --build`. `install.sh` er selvstændig og
skriver alle filer (inkl. `deploy/nginx-command-center.conf` og `deploy/command-center.user.service`).

## Drift & test

- **Cron**: domæne-tjek hver 6. time, keyword-tjek 06:00, autopilot 05:15, oprydning 04:30, DB-backup 04:40, GitHub-tjek 05:00, Autopilot-bro hver 30. min, WP-Cron-ping hvert 5. min
- **Backup**: `app/backups/cc-daglig-*.db` (14 gemmes) + `cc-pre-update-*.db` før hver opdatering. Gendan fra Moduler-fanen (skriv `GENDAN`)
- **Health**: `/health` (200, eller 503 ved kritisk DB/disk-tilstand) viser også månedens API-forbrug
- **Tests**: `python3 tests/test_v8_features.py` (enhedstests), `bash tests/ci_check.sh` (boot + alle sider + auth + WordPress-bro + link-audit)
- **Screenshots**: `python3 scripts/screenshots.py` tager login-siden og alle 15 faner ind i `docs/img/` (kræver `pip install playwright` + `python3 -m playwright install chromium`; kør mod en kørende app med `--base/--user/--password`). CI **fejler**, hvis billederne er ældre end dashboard-skabelonen — skriv `[skip screenshots]` i commit-beskeden, når ændringen ikke påvirker udseendet
- **Fælles agentregler i alle repoer**: `bash scripts/agents_md_rollout.sh --dry-run` viser planen, og uden `--dry-run` lægger den `AGENTS.md` ind i alle dine repoer som branch + PR (kræver `gh` logget ind). En eksisterende fil overskrives kun med `--overwrite`, og `main` røres aldrig
- **Scripts i `scripts/`**: alle otte har samme header — `navn - formål`, `Brug:`, `Kraever:` og `Sidst aendret` — og er eksekverbare. `bash scripts/update.sh -h` (og `--help` på de øvrige med flag) læser headeren, så hjælpen ikke kan drive fra scriptet. Versionsnumre står ikke i headere: de læses fra `APP_VERSION` i `app/main.py`

## Alarmer (v7.12)

Alarmer går til flere kanaler: **Telegram**, **e-mail** (SMTP), **ntfy** og en **signeret webhook**.
De sendes ikke inline — de skrives i køen `alert_outbox` og leveres af et job med backoff
(30 s → 2 min → 10 min → 1 t, maks. 5 forsøg), så en langsom modtager aldrig blokerer appen.
Ens alarmer dedupliceres inden for `ALERT_DEDUPE_MINUTES`, stille timer (`ALERT_QUIET_HOURS=23-7`)
udskyder alt under "kritisk" til vinduet slutter, og webhooken signeres efter Standard Webhooks
(`webhook-id`, `webhook-timestamp`, `webhook-signature: v1,...` = HMAC-SHA256 over
`id.timestamp.body`). Fanen **Alarmer** viser hvilke kanaler der er sat op, har test-knapper pr.
kanal og lister fejlede leveringer med årsag og antal forsøg. Fremdriftskortet dækker alle tunge
handlinger — crawl med rigtig procent, resten med ærlige skøn (`TASK_ESTIMATES`), nu også
testalarmer og GitHub-opdatering.

## Opstart, login og IP (v7.13)

Ved hver opstart skriver appen version og de nyeste aendringer til skaermen, til
`app/data/startup.log` og til `settings.last_start` - og de samme nyheder er med i `GET /health`.
`run.sh`, `run.bat`, `scripts/restart.sh`, `scripts/update.sh` og `install.sh` viser version + nyheder,
saa man ikke skal huske hvilken version der kører. `scripts/update.sh` går to skridt videre: den viser
versionen på disken, den version processen svarer med i `/health` **og** den version `install.sh` vil
skrive, advarer hvis de er forskellige, og skriver login-adressen (`CC_PUBLIC_URL` + `/login`, dvs. den
adresse nginx videresender). `bash scripts/update.sh --version` giver samme kontrol som rent svar:
kode 0 kun når alle tre stemmer, ellers kode 1 med en linje om hvad der er galt — så en gammel
`install.sh`, der ville overskrive koden med en ældre version, bliver opdaget før man kører den.

Login logger nu IP: `users.last_login_ip`/`last_login_at`, `sessions.ip` og tabellen `login_attempts`
(ok/fejl, 30 dage) - vist under fanen **Brugere** sammen med de seneste forsoeg. IP'en hentes fra
`X-Forwarded-For` (foerste hop) med socket-adressen som reserve, saa den er korrekt bag nginx.
Login-siden viser en kort **kørselsrapport** uden at man er logget ind: version + commit, seneste
opstart, åbne alarmer, antal domæner/keywords/monitors, seneste domænetjek og crawl, DB-størrelse og
din IP - ingen alarmtekster eller brugernavne.

## Agenter og skills (v7.13.2)

Fem agenter i tre grupper, plus en skill. Se `.agents/README.md` for detaljer og spawn-eksempler.

| Repo | Agenter |
|---|---|
| **Command Center** (dette repo) | `command-center-reviewer` (regler/kontrakter), `cc-verifier` (tests, ruter, installer-paritet), `site-seo-auditor` (SEO ud fra appens DB), `mcp-access-auditor` (MCP-nøgler, scopes, audit, transport) |
| **Social Autopilot** (tjenesten) | `social-autopilot-auditor` (`/drafts`, `/autopilot/sync`, kanaler, idempotens, tidszoner) |
| **Social Autopilot Android** (mobilklienten) | `social-autopilot-android` (API-paritet, Keystore, offline-kø, release) |

- `.agents/skills/command-center/SKILL.md` — en **skill** med reglerne, kontrakterne,
  verify-kommandoerne og faldgruberne. Den bliver slash-kommandoen `/skill:command-center`.
- Alle agenter er **read-only** med vilje; kun `cc-verifier` må køre kommandoer, og den skriver ikke.

De er udviklerværktøj, ikke app-funktioner: de indgår ikke i `install.sh`, og self-update henter dem
ikke. Modellen i agenten står som `anthropic/claude-sonnet-4.5` (Codebuff-docsenes eksempel) — skift
den linje hvis kontoen ikke kan tilgå modellen.

## Dokumentation

Kodeændringer kræver dokumentation i samme commit: `README.md` plus den relevante fil i `docs/`
(manual ved funktioner, arkitektur ved struktur/jobs/ruter, roadmap ved prioriteringer). `install.sh`
regenereres bagefter, fordi den indeholder kopier af filerne. CI fejler, hvis der ændres kode uden
dokumentation — `[skip docs]` i commit-beskeden springer tjekket over. `CLAUDE.md` er statusnotatet
og handoff, `AGENTS.md` er de korte regler for agenter.

## Sikkerhed

- **Brugere**: PBKDF2-SHA256 med salt pr. bruger; sessioner er HttpOnly-cookies (30 dage) gemt som `sha256(id)` i databasen, så en DB-kopi ikke giver adgang. Skift af adgangskode logger dine andre sessioner ud.
- **Cookie/HTTPS**: cookien sættes `Secure` når appen ser https (kræver `X-Forwarded-Proto` bag proxy — se nginx-afsnittet).
- **API-budget**: SerpAPI og aimlapi tælles pr. måned og stoppes ved loftet (`SERPAPI_MONTHLY_LIMIT`, `AI_MONTHLY_LIMIT`), med alarm ved 80 % og 100 %. Forbruget vises på Cockpit.
- **Job-heartbeat**: hvert planlagt job skriver sin sidste kørsel; forsinkede eller fejlede jobs alarmeres (v7.20).
- Default binding er 127.0.0.1 — sæt aldrig `0.0.0.0` uden reverse proxy + TLS.
- **SSRF**: alle udgående kald med en URL fra et felt går gennem `safe_request()`. Loopback, private net, link-local (`169.254.169.254` = sky-metadata), reserverede adresser og navne som `.local`/`.internal` afvises, og en viderestilling tjekkes hop for hop — så en 302 ikke kan føre ind i det lokale net. Afvisningen forklares i formularen. Skal CC måle en intern side, åbner `CC_SSRF_ALLOW=vaert.ditdomaene` for netop den værtsadresse.

## Kendte begrænsninger

- Dashboardet henter Tailwind, Alpine.js og Chart.js lokalt fra `app/static/vendor/` (siden v7.22), så det virker uden internetadgang. Login-siden er helt selvstændig.
- Opdatering kræver `GITHUB_TOKEN`; ændringer i `requirements.txt` rapporteres men installeres først ved næste `./run.sh`.
- `install.sh` indeholder kopier af projektets filer (CI tjekker at de matcher); ret derfor altid kildefilerne og kør regen, ikke installeren.
- Screenshots i `docs/img/` er taget med `python3 scripts/screenshots.py` mod v7.24-UI'et (alle 15 faner, inkl. Vækst); kør scriptet igen efter større UI-ændringer — CI fejler, hvis du glemmer det.
- **Vækst måler tekst, ikke markedet**: Surfer, Ahrefs og Semrush bygger på egne webindekser og søgedata. Vækst-fanen tæller ord og termer i det indhold, du giver den, og henter kun de konkurrentsider, du selv angiver — derfor ingen søgevolumen, sværhedsgrad, placeringer eller backlink-profiler.
EOF_README

echo "📄 scripts/smoke_test.sh..."
cat << 'EOF_RESTART' > scripts/restart.sh
#!/usr/bin/env bash
# restart.sh - genstarter Command Center. Bruges af opdateringen (POST /update/apply) og manuelt.
#
# Brug:
#   bash scripts/restart.sh              # genstart med det samme
#   bash scripts/restart.sh --delay 2    # vent 2 s (saa HTTP-svaret kan naa frem)
#
# Raekkefoelge:
#   1. UPDATE_RESTART_CMD (hvis sat i .env)
#   2. systemd --user unit "command-center"  (Ultra.cc)
#   3. systemd system unit "command-center"
#   4. pidfile app/data/cc.pid + ./run.sh    (naar appen er startet med ./run.sh)
# Kraever: intet ud over bash - det foerste trin der findes, bliver brugt.
# Sidst aendret: 4. november 2026
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

banner() {
    V="$(sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' app/main.py 2>/dev/null | head -1)"
    N="$(sed -n 's/^NEWEST_LINE = "\(.*\)"/\1/p' app/main.py 2>/dev/null | head -1)"
    echo "   Command Center v${V:-?} - ${N:-se app/data/startup.log}"
}

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
        banner
        exit 0
    fi
done

if restart_systemd_system command-center; then
    echo "Genstartede systemd unit 'command-center'."
    banner
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
banner
exit 0
EOF_RESTART
cat << 'EOF_UPDATE' > scripts/update.sh
#!/usr/bin/env bash
# update.sh - opdaterer Command Center fra GitHub: tjek -> filer (med DB-backup) -> requirements ->
# genstart.
#
# Brug:
#   bash scripts/update.sh              # opdater + genstart, vent til /health svarer
#   bash scripts/update.sh --no-restart # opdater, men genstart selv bagefter
#   bash scripts/update.sh --check      # kun tjek, skriv intet
#   bash scripts/update.sh --version    # sammenlign de tre versioner og stop med kode 1 ved uenighed
#
# Viser foerst hvilken version der koerer (/health) ved siden af filernes og installatoerens, og hvor
# man logger ind (CC_PUBLIC_URL via nginx). --version er den strenge kontrol: den stopper med kode 1,
# hvis en gammel install.sh eller en manglende genstart kan snige sig ind. Opdateringen selv skriver
# intet, hvis install.sh paa disken er aeldre end koden (kode 7) - hent den fra git foerst.
# Koerer appens funktioner direkte i venv'en - ingen token eller login.
# Kraever: venv (./venv) og GITHUB_TOKEN i .env til opdateringen; --version kraever ingen af dem.
# Sidst aendret: 4. november 2026
set -u
cd "$(dirname "$0")/.."

if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Hjaelpen er header-kommentarerne efter shebang: retter man dem, retter man hjaelpen.
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

MODE="apply"
case "${1:-}" in
    --no-restart) MODE="apply-no-restart" ;;
    --check) MODE="check" ;;
    --version) MODE="version" ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "Ukendt argument: $1 (brug --version, --check, --no-restart eller -h)" >&2; exit 64 ;;
esac

HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
case "$HOST" in
    0.0.0.0|::|"") PROBE=127.0.0.1 ;;
    *) PROBE="$HOST" ;;
esac
BASE="http://$PROBE:$PORT"

# ---------- Version: filer, proces og installatoer ----------
# Tre kilder kan vaere uenige, og alle tre kan snige sig ind: app/main.py (det der ligger paa disken),
# /health (den proces der svarer lige nu) og install.sh (installatoeren nogen maaske koerer bagefter og
# overskriver det hele med). --version tjekker alle tre og stopper med kode 1 ved uenighed.
RUN=""; FILE=""; INST=""
login_url() { local b="${CC_PUBLIC_URL:-$BASE}"; echo "${b%/}/login"; }
file_version() { sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' app/main.py 2>/dev/null | head -1; }
# Versionen af den proces der svarer - laeses ud af JSON uden python, saa --version ogsaa virker uden venv.
running_version() {
    curl -sf --max-time 3 "$BASE/health" 2>/dev/null \
        | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}
# Versionen installatoeren vil skrive: APP_VERSION i install.sh's indlejrede app/main.py. Linjen staar
# i spalte 0 i den indlejrede fil, saa den findes uden at parse heredocs (og uden at skrive
# heredoc-markoeren her - den streng leder paritetstjekket i CI efter).
installer_version() {
    [ -f install.sh ] || return 0
    sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' install.sh 2>/dev/null | head -1
}
read_versions() { RUN="$(running_version)"; FILE="$(file_version)"; INST="$(installer_version)"; }
# 0 hvis $1 er nyere end $2 - sammenlignet tal for tal, saa 7.9 er aeldre end 7.17.
ver_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x,".");m=split(b,y,".");k=(n>m?n:m)
        for(i=1;i<=k;i++){if(x[i]+0>y[i]+0)exit 0; if(x[i]+0<y[i]+0)exit 1} exit 1}'
}
# Etiketterne har selv deres polstring (13 tegn): printf '%-13s' taelier bytes, ikke tegn, saa de
# danske bogstaver skubbede kolonnen ud af flugt.
ver_row() { if [ -n "$2" ]; then echo "   $1v$2   ($3)"; else echo "   $1ukendt   ($3)"; fi; }
version_rows() {
    ver_row "kører nu:    " "$RUN" "processen, fra $BASE/health"
    ver_row "filer:       " "$FILE" "app/main.py på disken"
    if [ -f install.sh ]; then
        ver_row "installatør: " "$INST" "install.sh, indlejret app/main.py"
    else
        echo "   installatør:  ingen install.sh i denne mappe"
    fi
}
# Forklarer uenigheden i klartekst; ingen linjer betyder at alt stemmer. Kode 1 = der er en forskel.
version_diff() {
    local bad=0
    if [ -z "$RUN" ]; then
        echo "   forskel:     processen svarer ikke på $BASE/health - kan ikke sammenlignes"
        bad=1
    elif [ -n "$FILE" ] && [ "$RUN" != "$FILE" ]; then
        if ver_gt "$FILE" "$RUN"; then
            echo "   forskel:     filerne er nyere end processen - genstart mangler (bash scripts/restart.sh)"
        else
            echo "   forskel:     processen kører nyere kode end filerne - filerne er rullet tilbage, kør opdateringen igen"
        fi
        bad=1
    fi
    if [ -n "$INST" ] && [ -n "$FILE" ] && [ "$INST" != "$FILE" ]; then
        if ver_gt "$INST" "$FILE"; then
            echo "   forskel:     install.sh er nyere end koden - kør den for at skrive de nye filer"
        else
            echo "   forskel:     install.sh er ældre (v$INST) end koden (v$FILE) - kør den IKKE; den overskriver app/main.py med den gamle version. Hent den fra git (git checkout -- install.sh eller git pull); opdateringen nægter selv at skrive, indtil den er rettet."
        fi
        bad=1
    fi
    return $bad
}
show_versions() {
    read_versions
    echo "Command Center"
    version_rows
    version_diff || true
    if [ -n "${CC_PUBLIC_URL:-}" ]; then
        echo "   login:       $(login_url)   (via nginx)"
    else
        echo "   login:       $(login_url)   (lokal adresse - sæt CC_PUBLIC_URL i .env for den offentlige)"
    fi
    echo
}
# Den strenge kontrol: kode 0 kun naar alle tre kilder svarer med samme version.
version_check() {
    read_versions
    echo "Command Center - versionskontrol"
    version_rows
    if version_diff; then
        [ -n "$FILE" ] || { echo "❌ Kan ikke læse APP_VERSION fra app/main.py."; exit 1; }
        echo "✅ Alle kilder stemmer: v$FILE."
        exit 0
    fi
    echo
    echo "❌ Versionskontrol fejlede - se 'forskel' ovenfor."
    exit 1
}

if [ "$MODE" = "version" ]; then
    version_check
fi

# ---------- Guard foer skrivning: en installatoer der ruller koden tilbage ----------
# install.sh skriver app/main.py med den version der ligger indlejret i den selv. Er den aeldre end
# koden paa disken, rulles koden tilbage hvis nogen koerer den. Derfor skrives der ikke filer oven paa
# en saadan installation: stop foerst, ret installatoren, koer igen. Kode 7 = naegtet, intet er roert.
installer_guard() {
    local inst file
    inst="$(installer_version)"; file="$(file_version)"
    [ -n "$inst" ] && [ -n "$file" ] || return 0
    ver_gt "$file" "$inst" || return 0
    echo "❌ Stopper før der bliver skrevet filer: install.sh på disken er ældre (v$inst) end koden (v$file)."
    echo "   Den installatør ville overskrive app/main.py med v$inst, hvis nogen kørte den nu."
    echo "   Hent den rette version først:   git checkout -- install.sh   (eller git pull)"
    echo "   Intet er ændret - kør scriptet igen bagefter. (--check og --version skriver intet og virker stadig.)"
    exit 7
}
case "$MODE" in
    apply|apply-no-restart) installer_guard ;;
esac

PY="./venv/bin/python"
if [ ! -x "$PY" ]; then
    echo "❌ venv mangler ($PY) - start appen en gang med ./run.sh foerst." >&2
    exit 2
fi

show_versions

# Et felt ud af JSON paa stdin ("None" -> tom)
field() { "$PY" -c 'import json,sys;d=json.load(sys.stdin);v=d.get(sys.argv[1]);print("" if v is None else v)' "$1"; }
count() { "$PY" -c 'import json,sys;print(len(json.load(sys.stdin).get(sys.argv[1]) or []))' "$1"; }
req_line() {
    "$PY" -c 'import json,sys;d=json.load(sys.stdin).get("requirements_install") or {};print(("OK" if d.get("ok") else "FEJL")+": "+(d.get("output") or "")[:200])'
}

echo "→ Tjekker GitHub..."
CHECK="$("$PY" -c 'import json;from app import main;print(json.dumps(main.update_check_sync(), ensure_ascii=False))')"
[ -n "$CHECK" ] || { echo "❌ Tomt svar fra tjekket." >&2; exit 3; }

echo "   installeret: $(printf '%s' "$CHECK" | field current)"
echo "   nyeste:      $(printf '%s' "$CHECK" | field latest)  $(printf '%s' "$CHECK" | field message)"
if [ "$(printf '%s' "$CHECK" | field ok)" != "True" ]; then
    echo "❌ Tjekket fejlede: $(printf '%s' "$CHECK" | field error)" >&2
    exit 4
fi
if [ "$(printf '%s' "$CHECK" | field behind)" != "True" ]; then
    echo "✅ Du kører nyeste version."
    exit 0
fi
if [ "$MODE" = "check" ]; then
    echo "⬆️  Ny version tilgængelig."
    exit 0
fi

echo "→ Henter og skriver filer (DB-backup foerst, requirements installeres hvis de er aendret)..."
RESULT="$("$PY" -c 'import json;from app import main;print(json.dumps(main.update_apply_sync(), ensure_ascii=False))')"
[ -n "$RESULT" ] || { echo "❌ Tomt svar fra opdateringen." >&2; exit 5; }

echo "   ok:           $(printf '%s' "$RESULT" | field ok)"
echo "   filer:        $(printf '%s' "$RESULT" | count files)"
echo "   requirements: $(printf '%s' "$RESULT" | req_line)"
if [ "$(printf '%s' "$RESULT" | field ok)" != "True" ]; then
    echo "❌ Opdateringen fejlede: $(printf '%s' "$RESULT" | field error)" >&2
    exit 5
fi

if [ "$MODE" = "apply-no-restart" ]; then
    echo "✅ Filer opdateret til v$(file_version) (processen kører stadig den gamle). Genstart selv: bash scripts/restart.sh"
    exit 0
fi

echo "→ Genstarter..."
bash scripts/restart.sh || { echo "❌ Genstart fejlede - se logs." >&2; exit 6; }
echo "→ Venter paa at appen svarer igen..."
for _ in $(seq 1 60); do
    sleep 1
    if curl -sf -o /dev/null --max-time 3 "$BASE/health"; then
        echo "✅ Opdateret og genstartet - $BASE svarer igen."
        echo "   kører nu:    v$(running_version)"
        echo "   login:       $(login_url)"
        exit 0
    fi
done
echo "⚠️  Appen svarede ikke inden 60 s. Se logs: journalctl --user -u command-center (eller nohup.out)" >&2
exit 6
EOF_UPDATE
cat << 'EOF_SMOKE' > "$PROJECT_DIR/scripts/smoke_test.sh"
#!/usr/bin/env bash
# smoke_test.sh - tjekker at appen svarer efter install eller self-update.
#
# Brug:
#   bash scripts/smoke_test.sh                           # 127.0.0.1:8000
#   CC_HOST=0.0.0.0 CC_PORT=8000 bash scripts/smoke_test.sh
#
# Kraever: en koerende app. CC_PUBLIC_URL vises som den offentlige adresse, hvis den er sat.
# Sidst aendret: 4. november 2026
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
set "VERSION="
for /f "tokens=2 delims==" %%v in ('findstr /b "APP_VERSION" app\main.py') do set "VERSION=%%v"
set "VERSION=%VERSION: =%"
set "VERSION=%VERSION:"=%"
echo Starter Command Center v%VERSION% (Windows)...
echo    Nyheder (fra app/main.py):
findstr /b "NEWEST_LINE" app\main.py
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
VERSION="$(sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' app/main.py | head -1)"
NEWEST="$(sed -n 's/^NEWEST_LINE = "\(.*\)"/\1/p' app/main.py | head -1)"
echo "⚡ Starter Command Center v${VERSION:-?}..."
[ -n "$NEWEST" ] && echo "   Nyheder:  $NEWEST"
echo "   (version + alle nyheder skrives ogsaa til app/data/startup.log ved opstart)"
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
CC_VER=$(sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' "$PROJECT_DIR/app/main.py" 2>/dev/null | head -1)
CC_NEW=$(sed -n 's/^NEWEST_LINE = "\(.*\)"/\1/p' "$PROJECT_DIR/app/main.py" 2>/dev/null | head -1)
echo "✨ Installation klar!  (Command Center v${CC_VER:-?})"
echo "   Nyheder:    ${CC_NEW:-se app/data/startup.log efter foerste start}"
echo "   Start:      cd $PROJECT_DIR && ./run.sh"
echo "   Adresse:    http://127.0.0.1:${CC_PORT:-8000}   (LAN: http://${LAN_IP:-<din-ip>}:${CC_PORT:-8000} naar CC_HOST=0.0.0.0)"
echo "   Login:      opret din bruger ved foerste besoeg - ingen token"
echo "   Smoke-test: bash $PROJECT_DIR/scripts/smoke_test.sh"
echo "   nginx:      saet CC_PUBLIC_URL i $PROJECT_DIR/.env og brug deploy/nginx-command-center.conf"

