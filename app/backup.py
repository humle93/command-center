import os
import sqlite3
import glob
from datetime import datetime, timezone
from app.jobs import DB_PATH

BACKUP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backups")

def create_hot_backup(retention_days: int = 14) -> dict:
    os.makedirs(BACKUP_DIR, exist_ok=True)
    if not os.path.exists(DB_PATH):
        return {"ok": False, "error": "Database findes ikke endnu"}
    
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    dest_path = os.path.join(BACKUP_DIR, f"center_backup_{ts}.db")
    
    src = sqlite3.connect(DB_PATH)
    dst = sqlite3.connect(dest_path)
    try:
        with dst:
            src.backup(dst)
    finally:
        dst.close()
        src.close()
    
    if not os.path.exists(dest_path) or os.path.getsize(dest_path) == 0:
        return {"ok": False, "error": "Backup-validering fejlede (0 bytes)"}
    
    files = sorted(glob.glob(os.path.join(BACKUP_DIR, "center_backup_*.db")), reverse=True)
    for old_file in files[retention_days:]:
        try:
            os.remove(old_file)
        except OSError:
            pass
            
    return {"ok": True, "path": dest_path, "size": os.path.getsize(dest_path)}
