from datetime import datetime, timezone
from app.jobs import get_db

def init_budgets():
    with get_db() as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS api_budgets (
                service TEXT PRIMARY KEY,
                monthly_limit INTEGER DEFAULT 1000,
                used_this_month INTEGER DEFAULT 0,
                month_key TEXT,
                paused INTEGER DEFAULT 0,
                last_status TEXT DEFAULT 'OK'
            );
        """)
        month_key = datetime.now(timezone.utc).strftime("%Y-%m")
        for svc, lim in [("aimlapi", 500), ("serpapi", 250), ("pagespeed", 1000)]:
            db.execute("INSERT OR IGNORE INTO api_budgets (service, monthly_limit, month_key) VALUES (?, ?, ?)",
                       (svc, lim, month_key))

def check_and_record_call(service: str, status_code: int = 200) -> bool:
    init_budgets()
    month_key = datetime.now(timezone.utc).strftime("%Y-%m")
    with get_db() as db:
        row = db.execute("SELECT * FROM api_budgets WHERE service = ?", (service,)).fetchone()
        if not row:
            return True
        if row["month_key"] != month_key:
            db.execute("UPDATE api_budgets SET used_this_month = 0, paused = 0, month_key = ? WHERE service = ?",
                       (month_key, service))
            row = db.execute("SELECT * FROM api_budgets WHERE service = ?", (service,)).fetchone()
        
        if status_code in (401, 403, 429):
            db.execute("UPDATE api_budgets SET paused = 1, last_status = ? WHERE service = ?",
                       (f"HTTP {status_code} Hard-Stop", service))
            return False
            
        if row["paused"] or row["used_this_month"] >= row["monthly_limit"]:
            return False
            
        db.execute("UPDATE api_budgets SET used_this_month = used_this_month + 1, last_status = 'OK' WHERE service = ?",
                   (service,))
        return True
