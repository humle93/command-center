"""Konfiguration, database og schema for Command Center.

Modulet indeholder det, baade ruterne og services-modulerne har brug for:
.env-konstanter, SQLite-adgangen, schema-opbygningen og de smaa hjaelpere.
Det maa ikke importere fra app.main eller app.services (det ville give en cirkulaer import)."""
from contextlib import contextmanager
from datetime import datetime
from urllib.parse import urlparse
import os
import requests
import sqlite3
import time
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

DB_PATH = os.path.join(BASE_DIR, "data", "center.db")

STATIC_DIR = os.path.join(BASE_DIR, "static")

APP_TOKEN = os.environ.get("APP_TOKEN", "").strip()          # login-token (tom = ingen auth, lokal tilstand)

JUNO_TOKEN = os.environ.get("JUNO_TOKEN", "").strip()

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()     # GitHub-token: pull-bro + selv-opdatering

GITHUB_REPO = os.environ.get("GITHUB_REPO", "humle93/command-center").strip()

BRIDGE_POLL_MINUTES = int(os.environ.get("BRIDGE_POLL_MINUTES", "60"))  # hvor ofte CC henter bridge-filer

AIMLAPI_KEY = os.environ.get("AIMLAPI_KEY", "").strip()      # AI-provider: aimlapi (OpenAI-kompatibel)

OPENROUTER_KEY = os.environ.get("OPENROUTER_KEY", "").strip()  # AI-provider: OpenRouter (OpenAI-kompatibel)

AI_PROVIDER = os.environ.get("AI_PROVIDER", "").strip().lower()  # "aimlapi" eller "openrouter"; tom = auto

AI_MODEL = os.environ.get("AI_MODEL", "")

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

APP_VERSION = "7.10.0"

SCHEMA_VERSION = 1  # v8.0: bumpes naar init_db/migrate_db aendrer tabeller eller kolonner

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

# AI-provider: aimlapi og OpenRouter deler OpenAI's /chat/completions-format, saa kun
# noegle, base-URL og standardmodel skifter. Er OPENROUTER_KEY sat, vaelges OpenRouter
# automatisk — AI_PROVIDER kan altid overrule valget.
OPENROUTER_KEY = os.environ.get("OPENROUTER_KEY", "").strip()

AI_PROVIDER = os.environ.get("AI_PROVIDER", "").strip().lower() or ("openrouter" if OPENROUTER_KEY else "aimlapi")

if AI_PROVIDER not in ("aimlapi", "openrouter"):
    AI_PROVIDER = "aimlapi"

AI_KEY_ENV = "OPENROUTER_KEY" if AI_PROVIDER == "openrouter" else "AIMLAPI_KEY"

AI_KEY = OPENROUTER_KEY if AI_PROVIDER == "openrouter" else AIMLAPI_KEY

AI_BASE_URL = "https://openrouter.ai/api/v1" if AI_PROVIDER == "openrouter" else "https://api.aimlapi.com/v1"

AI_MODEL = os.environ.get("AI_MODEL", "").strip() or ("anthropic/claude-3.5-sonnet" if AI_PROVIDER == "openrouter" else "anthropic/claude-3-5-sonnet")


def ai_chat(prompt: str, max_tokens: int = 1500, temperature=None, timeout: int = 120) -> str:
    """Send en prompt til den valgte AI-provider og returner svarets tekst.

    HTTP er den budget-taellende session, saa kaldet rammer API_BUDGETS["ai"].
    """
    payload = {"model": get_ai_model(), "messages": [{"role": "user", "content": prompt}], "max_tokens": max_tokens}
    if temperature is not None:
        payload["temperature"] = temperature
    resp = HTTP.post(
        AI_BASE_URL + "/chat/completions",
        headers={"Authorization": f"Bearer {AI_KEY}", "Content-Type": "application/json"},
        json=payload,
        timeout=timeout,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


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
        CREATE TABLE IF NOT EXISTS schema_meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );
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
        CREATE TABLE IF NOT EXISTS auth_sessions (
            sid_hash TEXT PRIMARY KEY,
            created_at TEXT,
            expires_at TEXT,
            ip TEXT
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

def schema_version() -> int:
    """Schema-versionen der er stemplet i databasen (0 = ikke stemplet / ukendt)."""
    try:
        with get_db() as db:
            row = db.execute("SELECT value FROM schema_meta WHERE key = 'schema_version'").fetchone()
        return int(row["value"]) if row else 0
    except Exception:
        return 0

def stamp_schema_version():
    with get_db() as db:
        db.execute(
            "INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('schema_version', ?)",
            (str(SCHEMA_VERSION),),
        )

def init_schema():
    """Byg og migrer schemaet i raekkefoelge — stemplet saettes kun naar alle trin gik igennem.

    Fejler et trin, bliver versionen i DB ikke opdateret, og naeste opstart (og /health)
    kan se forskellen. Foer stod hvert trin med sit eget _safe()-kald, saa en fejlet
    migrering kunne fortsaette i aevig tid uden at nogen opdagede det.
    """
    init_db()
    migrate_db()
    create_indexes()
    stamp_schema_version()

def report_schema_version():
    """Goer version-mismatch synligt: skarp loglinje + alarm i UI'et."""
    have = schema_version()
    if have == SCHEMA_VERSION:
        return
    msg = (f"Database-schema er version {have or 'ukendt'}, koden forventer {SCHEMA_VERSION} — "
           "en migrering er ikke gennemfoert (se serverloggen)")
    print("[cc] SCHEMA-ADVARSEL:", msg, flush=True)
    try:
        # now_iso() er defineret laengere nede i filen, og denne koeres ved import.
        with get_db() as db:
            db.execute(
                "INSERT INTO alarms (type, message, severity, created_at) VALUES (?, ?, ?, ?)",
                ("schema", msg[:300], "kritisk", datetime.now().isoformat(timespec="seconds")),
            )
    except Exception:
        pass

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
    """Daglig oprydning: gamle maalinger rulles af, DB holdes sund."""
    with get_db() as db:
        db.execute("DELETE FROM check_history WHERE checked_at < datetime('now', '-90 days')")
        db.execute("DELETE FROM alarms WHERE resolved=1 AND created_at < datetime('now', '-30 days')")
        db.execute("DELETE FROM health_history WHERE checked_at < datetime('now', '-180 days')")
        db.execute("DELETE FROM keyword_ideas WHERE created_at < datetime('now', '-180 days')")
        db.execute("DELETE FROM auth_sessions WHERE expires_at < ?", (now_iso(),))

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

API_BUDGETS = {
    "serpapi": ("serpapi.com", int(os.environ.get("SERPAPI_MONTHLY_LIMIT", "1000") or 0)),
    "ai": ("openrouter.ai" if AI_PROVIDER == "openrouter" else "aimlapi.com", int(os.environ.get("AI_MONTHLY_LIMIT", "3000") or 0)),
}

class BudgetExceeded(requests.RequestException):
    """Kaldet blev ikke sendt: maanedens API-budget er brugt."""

class BudgetAdapter(requests.adapters.HTTPAdapter):
    def send(self, request, **kwargs):
        # Importeres her og ikke i toppen: app.services.budget importerer app.core,
        # saa et top-import ville give en cirkulaer import.
        from app.services.budget import budget_service, budget_spend

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


def get_ai_model() -> str:
    """Aktiv AI-model: DB-override (settings.ai_model) hvis sat, ellers env/default.

    Laeser fra settings-tabellen, saa modellen kan skiftes i dashboardet uden
    at redigere .env. Fejl giver stille fallback til AI_MODEL.
    """
    try:
        with get_db() as db:
            row = db.execute("SELECT value FROM settings WHERE key='ai_model'").fetchone()
        if row and (row["value"] or "").strip():
            return row["value"].strip()
    except Exception:
        pass
    return AI_MODEL
