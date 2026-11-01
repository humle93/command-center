"""In-process tests for the v8-plan features: quality gate, API budget guard, /health.
Usage: python3 tests/test_v8_features.py   (from the repo root, requirements installed)"""
import os, sys, shutil, threading, json, io, tarfile, tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)
shutil.rmtree(os.path.join(ROOT, "app", "data"), ignore_errors=True)
os.environ.update(AIMLAPI_KEY="test-key", WP_URL="", WP_USER="", WP_APP_PASSWORD="")

from app import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

FAILED = []
def check(name, ok, detail=None):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok or detail is None else f" -> {detail}"))
    if not ok:
        FAILED.append(name)

WORDS = "brass goggles " * 40

class Ok(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        pages = {
            "/": "<html><head><title>Hjem</title></head><body><h1>Hjem</h1><p>" + WORDS + '</p><a href="/a">a</a></body></html>',
            "/a": "<html><head><title>Side A</title></head><body><h1>Side A</h1><p>" + WORDS + "</p></body></html>",
            "/price": ('<html><head><title>Produkt</title></head><body>'
                       '<script type="application/ld+json">'
                       '{"@type":"Product","offers":{"price":"20.00"}}</script></body></html>'),
        }
        body = pages.get(self.path)
        if body is None:
            body, ctype = "{}", "application/json"
        else:
            ctype = "text/html"
        b = body.encode()
        self.send_response(200); self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(b))); self.end_headers(); self.wfile.write(b)
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

# --- dashboard article HTML is sanitised (stored XSS) ---
dirty = ('<h2>Ok</h2><p onclick="evil()">tekst</p><script>alert(1)</script>'
         '<img src=x onerror=alert(1)><a href="javascript:alert(1)">slem</a>'
         '<a href="https://example.com/x" title="t">god</a>')
clean = main.sanitize_article_html(dirty)
check("sanitise: formatting tags survive", "<h2>" in clean and "<p>" in clean, clean)
check("sanitise: scripts, handlers, images and javascript: are removed",
      "<script" not in clean and "onerror" not in clean and "onclick" not in clean
      and "<img" not in clean and "javascript:" not in clean, clean)
check("sanitise: http links kept with rel=noopener",
      'href="https://example.com/x"' in clean and "noopener" in clean, clean)

# --- price monitor compares the stored number, not the display text ---
main.API_BUDGETS["serpapi"] = ("127.0.0.1", 0)  # budget-guarden er testet ovenfor; slaas fra her
with main.get_db() as db:
    db.execute("DELETE FROM monitors")
    db.execute("INSERT INTO monitors (name, url, type, expected, last_status, last_result, last_value) "
               "VALUES (?,?,?,?,?,?,?)",
               ("pris", f"http://127.0.0.1:{port}/price", "price", "", "Pris: 10.00", "Pris: 10.00", "10.00"))
    mon = db.execute("SELECT * FROM monitors").fetchone()
status, ok, value = main.run_monitor_sync(mon)
check("price monitor: 10.00 -> 20.00 is a detected change",
      ok and "var 10.00" in status and value == "20.00", (status, value))
with main.get_db() as db:
    alarms = db.execute("SELECT COUNT(*) FROM alarms WHERE type='pris-monitor'").fetchone()[0]
check("price monitor: the change raises an alarm", alarms == 1, alarms)

# --- crawling keeps the previous run so crawl-diff can compare ---
for _ in range(2):
    main.site_crawl_sync(f"http://127.0.0.1:{port}/", 3)
with main.get_db() as db:
    runs = db.execute("SELECT COUNT(*) FROM crawl_runs").fetchone()[0]
    runs_with_pages = db.execute("SELECT COUNT(DISTINCT run_id) FROM seopages").fetchone()[0]
check("crawl: two runs (and their pages) are kept", runs == 2 and runs_with_pages == 2, (runs, runs_with_pages))

# --- authenticated UI rules: crawl-diff works, bad monitor input does not 500 ---
a = TestClient(main.app)
a.post("/setup", data={"username": "tester", "password": "testpass1", "confirm": "testpass1"}, follow_redirects=False)
r = a.get("/api/crawl/diff")
check("crawl: diff compares the two runs", r.status_code == 200 and "error" not in r.json(), r.text[:120])
r = a.post("/monitors/add", data={"name": "x", "url": "nope", "type_": "contains", "expected": "x"}, follow_redirects=False)
check("monitors: invalid URL redirects instead of returning 500", r.status_code == 303, r.status_code)
r = a.post("/monitors/add", data={"name": "x", "url": "https://example.com", "type_": "bogus", "expected": "x"}, follow_redirects=False)
with main.get_db() as db:
    saved = db.execute("SELECT type FROM monitors WHERE name='x'").fetchone()
check("monitors: unknown type falls back to 'contains'",
      r.status_code == 303 and saved and saved["type"] == "contains", (r.status_code, saved and saved["type"]))

# --- GitHub update: no token is explained, and extraction is whitelisted/traversal-safe ---
main.GITHUB_TOKEN = ""
check("update: missing GITHUB_TOKEN is reported clearly",
      main.update_apply_sync()["ok"] is False and "GITHUB_TOKEN" in main.update_apply_sync()["error"])

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz") as tar:
    def add(name, data=b"x"):
        info = tarfile.TarInfo(name)
        info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
    add("repo-main/app/main.py", b"pass\n")
    add("repo-main/requirements.txt", b"fastapi\n")
    add("repo-main/../../evil.txt", b"pwned\n")
    add("repo-main/app/../../../etc/evil.txt", b"pwned\n")
    add("repo-main/.env", b"SECRET=1\n")
buf.seek(0)
dest = tempfile.mkdtemp(dir=ROOT)
with tarfile.open(fileobj=buf, mode="r:gz") as tar:
    written = main._safe_extract(tar, dest)
check("update: only whitelisted files are written", sorted(written) == ["app/main.py", "requirements.txt"], written)
check("update: path traversal and .env are refused",
      not os.path.exists(os.path.join(dest, "evil.txt"))
      and not os.path.exists(os.path.join(ROOT, "evil.txt"))
      and not os.path.exists(os.path.join(dest, ".env")))
check("update: whitelisted file content is written",
      open(os.path.join(dest, "app", "main.py")).read() == "pass\n")
shutil.rmtree(dest, ignore_errors=True)

# --- update restart: mode detection and the opt-out switch (nothing is actually restarted) ---
check("update: restart mode is one of the known modes",
      main.restart_mode() in ("custom", "systemd-user", "systemd", "script", "manual"), main.restart_mode())
os.environ["UPDATE_AUTO_RESTART"] = "0"
plan = main.schedule_restart()
check("update: UPDATE_AUTO_RESTART=0 plans no restart",
      plan["scheduled"] is False and "UPDATE_AUTO_RESTART" in plan.get("reason", ""), plan)
os.environ.pop("UPDATE_AUTO_RESTART", None)
check("update: restart script exists for the pidfile/systemd path",
      os.path.exists(os.path.join(ROOT, "scripts", "restart.sh"))
      and os.path.exists(os.path.join(ROOT, "scripts", "update.sh")))

srv.shutdown()
shutil.rmtree(os.path.join(ROOT, "app", "data"), ignore_errors=True)
print("ALL PASS" if not FAILED else f"{len(FAILED)} FAILED")
sys.exit(1 if FAILED else 0)
