"""In-process tests for the v8-plan features: quality gate, API budget guard, /health.
Usage: python3 tests/test_v8_features.py   (from the repo root, requirements installed)"""
import os, sys, shutil, threading, json
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)
shutil.rmtree(os.path.join(ROOT, "app", "data"), ignore_errors=True)
os.environ.update(APP_TOKEN="", AIMLAPI_KEY="test-key", WP_URL="", WP_USER="", WP_APP_PASSWORD="")

from app import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

FAILED = []
def check(name, ok, detail=None):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok or detail is None else f" -> {detail}"))
    if not ok:
        FAILED.append(name)

class Ok(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(b"{}")
srv = HTTPServer(("127.0.0.1", 0), Ok); threading.Thread(target=srv.serve_forever, daemon=True).start()
port = srv.server_address[1]

# --- quality gate ---
body = " ".join(["steampunk goggles brass leather"] * 110)
good = f"<h2>Intro</h2><p>{body}</p><h2>How</h2><p>See <a href='/shop/'>shop</a> and <a href='https://steamgears.eu/guide/'>guide</a>.</p>"
r = main.quality_check(good, "steampunk goggles")
check("gate: complete article passes", r["passed"] and not r["warnings"], r)
r = main.quality_check("<h2>A</h2><p>short text</p>", "steampunk goggles")
check("gate: short article without keyword and 1 H2 fails with 3 reasons", not r["passed"] and len(r["errors"]) == 3, r)
r = main.quality_check(good.replace("<a href='/shop/'>shop</a>", "shop").replace("<a href='https://steamgears.eu/guide/'>guide</a>", "guide"), "steampunk goggles")
check("gate: missing internal links only warns", r["passed"] and r["warnings"], r)
with main.get_db() as db:
    db.execute("INSERT INTO content_gap (keyword, stats_json, created_at) VALUES (?,?,?)",
               ("steampunk goggles", json.dumps({"summary": {"avg_words": 1000}}), main.now_iso()))
r = main.quality_check(good, "steampunk goggles")
check("gate: SERP benchmark raises the minimum (80 % of 1000)", not r["passed"] and r["min_words"] == 800, r)

# --- autopilot is blocked by the gate ---
with main.get_db() as db:
    db.execute("INSERT INTO keyword_ideas (idea, created_at) VALUES (?,?)", ("brass goggles", main.now_iso())) if "idea" in [c[1] for c in db.execute("PRAGMA table_info(keyword_ideas)")] else None
main.generate_article_ai = lambda keyword, strategy=None: "<h2>x</h2><p>too short</p>"
res = main.autopilot_sync()
with main.get_db() as db:
    art = db.execute("SELECT status FROM articles ORDER BY id DESC LIMIT 1").fetchone()
check("autopilot: short AI article stopped before WordPress", str(res).startswith("quality-blocked") and art and art["status"].startswith("Stoppet af kvalitetsgate"), (res, art and art["status"]))

# --- API budget guard ---
main.API_BUDGETS["serpapi"] = ("127.0.0.1", 3)
codes = [main.HTTP.get(f"http://127.0.0.1:{port}/search", timeout=5).status_code for _ in range(3)]
try:
    main.HTTP.get(f"http://127.0.0.1:{port}/search", timeout=5); blocked = False
except main.BudgetExceeded:
    blocked = True
check("budget: calls under the limit go through", codes == [200, 200, 200], codes)
check("budget: call over the limit is blocked before sending", blocked)
with main.get_db() as db:
    alarms = [r["message"] for r in db.execute("SELECT message FROM alarms WHERE type='budget' ORDER BY id")]
check("budget: one alarm at 80 % and one at 100 %", len(alarms) == 2 and "80 %" in alarms[0] and "er brugt" in alarms[1], alarms)
check("budget: other hosts are not counted", main.budget_service("https://example.com/x") == "")

# --- /health ---
c = TestClient(main.app)
h = c.get("/health")
j = h.json()
check("health: 200 with db_write, disk and budget", h.status_code == 200 and j["db_write"] is True and j["disk_used_pct"] is not None
      and j["budget"]["serpapi"] == {"used": 3, "limit": 3} and j["version"] == main.APP_VERSION, j)

srv.shutdown()
shutil.rmtree(os.path.join(ROOT, "app", "data"), ignore_errors=True)
print("ALL PASS" if not FAILED else f"{len(FAILED)} FAILED")
sys.exit(1 if FAILED else 0)
