"""API-budget: maanedligt loft pr. betalt tjeneste.

Kald taelles i settings-tabellen pr. maaned, saa en loekke eller fejl ikke kan
braende kreditter af. Selve taellingen sker i app.core (HTTP-adapteren), mens
rapporteringen til /health ligger her."""
from app.core import API_BUDGETS
from app.core import BudgetExceeded
from app.core import get_db
from app.services.alarms import add_alarm
from datetime import datetime
from urllib.parse import urlparse
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
