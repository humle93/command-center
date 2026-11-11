"""WordPress- og SGAP-broen.

Alt der taler med WordPress (kladde-push) og social-gap-plugin'et samles her, saa
ruterne i main.py kun beskaeftiger sig med HTTP-svaret."""
from app.core import HTTP
from app.core import WP_APP_PASSWORD
from app.core import WP_URL
from app.core import WP_USER
from app.core import get_db
from app.core import module_on
from app.core import now_iso
from app.services.alarms import add_alarm
import json as jsonlib
def wp_push_draft(title: str, content: str):
    resp = HTTP.post(
        f"{WP_URL.rstrip('/')}/wp-json/wp/v2/posts",
        auth=(WP_USER, WP_APP_PASSWORD),
        json={"title": title, "content": content, "status": "draft"},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json().get("id")

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
