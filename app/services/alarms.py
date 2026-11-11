"""Alarmer og Telegram-varsling.

Alarmer skrives til tabellen alarms, saa de kan ses i UI'et, og sendes videre til
Telegram hvis noeglen er sat. Modulet kender kun app.core."""
from app.core import HTTP
from app.core import TELEGRAM_BOT_TOKEN
from app.core import TELEGRAM_CHAT_ID
from app.core import now_iso
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
