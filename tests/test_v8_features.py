"""In-process tests for the v8-plan features: quality gate, API budget guard, /health.
Usage: python3 tests/test_v8_features.py   (from the repo root, requirements installed)"""
import os, sys, shutil, threading, json, io, tarfile, tempfile, base64, hmac, hashlib
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)
shutil.rmtree(os.path.join(ROOT, "app", "data"), ignore_errors=True)
os.environ.update(OPENROUTER_API_KEY="test-key", WP_URL="", WP_USER="", WP_APP_PASSWORD="")

__import__("os").environ.setdefault("CC_SSRF_ALLOW", "127.0.0.1")  # lokale testservere
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
    hits = []
    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(n)
        Ok.hits.append({"path": self.path, "body": body, "headers": dict(self.headers)})
        self.send_response(500 if self.path.startswith("/hookfail") else 200)
        self.send_header("content-length", "0"); self.end_headers()
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
a.post("/setup", data={"email": "tester@example.dk", "password": "testpass1", "confirm": "testpass1"}, follow_redirects=False)
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

# --- Juno er fjernet helt: ingen maskin-noegle, ingen bridge-endpoints ---
check("auth: no machine token or Juno bridge left",
      not hasattr(main, "JUNO_TOKEN") and not hasattr(main, "is_juno")
      and not any("/api/bridge" in getattr(r, "path", "") for r in main.app.routes),
      [getattr(r, "path", "") for r in main.app.routes if "/api/bridge" in getattr(r, "path", "")])

# --- opgave-fremdrift: procent + ETA paa crawl og alle tunge opgaver ---
main.CRAWL_STATE.update({"running": True, "done": 5, "total": 10, "error": None,
                         "started_at": main.now_iso(), "finished_at": None})
prog = main.crawl_progress()
check("tasks: crawl percent is done/total while running",
      prog["percent"] == 50 and prog["running"] is True, prog)
main.CRAWL_STATE.update({"running": False, "finished_at": main.now_iso(), "error": None})
prog = main.crawl_progress()
check("tasks: finished crawl reports 100 % and no ETA",
      prog["percent"] == 100 and prog["eta_seconds"] is None, prog)
check("tasks: de nye tunge handlinger har estimater",
      "/alerts/test" in main.TASK_ESTIMATES and "/update/apply" in main.TASK_ESTIMATES,
      sorted(main.TASK_ESTIMATES))
check("tasks: every estimate has a label and a positive duration",
      bool(main.TASK_ESTIMATES)
      and all(v.get("label") and int(v.get("seconds", 0)) > 0 for v in main.TASK_ESTIMATES.values())
      and all(k.startswith("/") for k in main.TASK_ESTIMATES), len(main.TASK_ESTIMATES))

# --- alarmer: kanaler, outbox, dedupe, signatur, backoff og stille timer (v7.12) ---
main.API_BUDGETS["serpapi"] = ("", 0)          # budget-guarden er testet ovenfor
main.TELEGRAM_BOT_TOKEN = main.TELEGRAM_CHAT_ID = ""
main.SMTP_HOST = main.SMTP_TO = main.SMTP_FROM = ""
main.NTFY_TOPIC = ""
main.ALERT_WEBHOOK_URL = f"http://127.0.0.1:{port}/hook"
main.ALERT_WEBHOOK_SECRET = "whsec_" + base64.b64encode(b"test-secret").decode()
main.ALERT_MIN_SEVERITY, main.ALERT_QUIET_HOURS = "info", ""
with main.get_db() as db:
    db.execute("DELETE FROM alert_outbox"); db.execute("DELETE FROM alarms")
    queued = main.enqueue_alert(db, "test-kanal", "webhook virker", "advarsel")
check("alerts: kun konfigurerede kanaler koeres", queued == ["webhook"], queued)
res = main.drain_alert_outbox()
check("alerts: webhook leveres", res["sent"] == 1 and bool(Ok.hits), res)
hit = Ok.hits[-1]
expect = "v1," + base64.b64encode(hmac.new(
    b"test-secret",
    f'{hit["headers"]["webhook-id"]}.{hit["headers"]["webhook-timestamp"]}.'.encode() + hit["body"],
    hashlib.sha256).digest()).decode()
check("alerts: signaturen foelger standard-webhooks (HMAC over id.timestamp.body)",
      hit["headers"].get("webhook-signature") == expect)
check("alerts: payload har type/timestamp/data med event_id",
      b'"type": "alert"' in hit["body"] and b'"data"' in hit["body"] and b'"event_id"' in hit["body"],
      hit["body"][:120])

with main.get_db() as db:
    db.execute("DELETE FROM alert_outbox")
    first = main.enqueue_alert(db, "pris", "pris steget", "advarsel")
    second = main.enqueue_alert(db, "pris", "pris steget", "advarsel")
check("alerts: identisk alarm inden for dedupe-vinduet koeres en gang",
      first == ["webhook"] and second == [], (first, second))

with main.get_db() as db:
    db.execute("DELETE FROM alert_outbox")
main.ALERT_WEBHOOK_URL = f"http://127.0.0.1:{port}/hookfail"
with main.get_db() as db:
    main.enqueue_alert(db, "fejl", "500 fra modtager", "info")
res = main.drain_alert_outbox()
with main.get_db() as db:
    row = db.execute("SELECT * FROM alert_outbox").fetchone()
check("alerts: fejlende modtager proeves igen med backoff (ikke tabt)",
      res["failed"] == 1 and row["state"] == "pending" and row["attempts"] == 1
      and row["next_attempt_at"] > row["created_at"], dict(row))

main.ALERT_WEBHOOK_URL = f"http://127.0.0.1:{port}/hook"
main.ALERT_QUIET_HOURS = f"{datetime.now().hour}-{(datetime.now().hour + 1) % 24}"
with main.get_db() as db:
    db.execute("DELETE FROM alert_outbox")
    main.enqueue_alert(db, "stille", "info om natten", "info")
before = len(Ok.hits)
res = main.drain_alert_outbox()
check("alerts: stille timer udskyder ikke-kritiske alarmer i stedet for at tabe dem",
      res["deferred"] == 1 and len(Ok.hits) == before, res)
main.ALERT_QUIET_HOURS = ""

ok, err = main._send_email_alert("x", "y", "info")
check("alerts: manglende SMTP-felter forklares", ok is False and "SMTP" in err, err)

with main.get_db() as db:
    db.execute("DELETE FROM alert_outbox")
    main.add_alarm(db, "test", "alarm via add_alarm", "advarsel")
    n = db.execute("SELECT COUNT(*) FROM alert_outbox").fetchone()[0]
check("alerts: add_alarm kun koer (ingen blokerende HTTP i request-stien)", n == 1, n)

# --- opstart, login-IP og koerselsrapport (v7.13) ---
banner = "\n".join(main.startup_banner("0.0.0.0", 8000))
check("startup: banneret har version, de tre nyeste og lytteadresse",
      main.APP_VERSION in banner and all(f"nyhed {v}" in banner for v, _ in main.NEWEST[:3])
      and "lytter paa 0.0.0.0:8000" in banner, banner[:160])
check("startup: NEWEST_LINE er én linje scripts kan laese",
      bool(main.NEWEST_LINE) and "\n" not in main.NEWEST_LINE, main.NEWEST_LINE)

with main.get_db() as db:
    db.execute("DELETE FROM login_attempts"); db.execute("DELETE FROM sessions"); db.execute("DELETE FROM users")
b = TestClient(main.app)
b.post("/setup", data={"email": "iptest@example.dk", "password": "iptest-pass", "confirm": "iptest-pass"},
       follow_redirects=False, headers={"x-forwarded-for": "203.0.113.9, 10.0.0.1"})
with main.get_db() as db:
    usr = db.execute("SELECT last_login_ip FROM users WHERE email='iptest@example.dk'").fetchone()
    ses = db.execute("SELECT ip FROM sessions ORDER BY rowid DESC LIMIT 1").fetchone()
    okn = db.execute("SELECT COUNT(*) FROM login_attempts WHERE ok=1").fetchone()[0]
check("login: IP gemmes paa bruger, session og i loggen",
      usr and usr["last_login_ip"] == "203.0.113.9" and ses and ses["ip"] == "203.0.113.9" and okn == 1,
      (usr and dict(usr), ses and dict(ses), okn))

# Her findes praecis én bruger: en sletning af den skal forklares i fanen, ikke bare give en alarm.
with main.get_db() as db:
    only_id = db.execute("SELECT id FROM users WHERE email='iptest@example.dk'").fetchone()["id"]
r = b.post("/users/delete", data={"id": str(only_id)}, follow_redirects=False)
with main.get_db() as db:
    survivors = db.execute("SELECT COUNT(*) FROM users").fetchone()[0]
check("delete: den sidste bruger kan ikke slettes - og svaret lander i Brugere-fanen",
      r.status_code == 303 and survivors == 1 and "del_kind=sidste" in (r.headers.get("location") or ""),
      (r.status_code, r.headers.get("location"), survivors))
_del_side = b.get(r.headers["location"])
check("delete: formularen forklarer hvorfor den sidste bruger bliver",
      _del_side.status_code == 200 and "Brugeren blev ikke slettet" in _del_side.text
      and "mindst én bruger" in _del_side.text, _del_side.text[:160])

b.post("/login", data={"email": "iptest@example.dk", "password": "helt-forkert"}, follow_redirects=False,
       headers={"x-forwarded-for": "198.51.100.7"})
with main.get_db() as db:
    fail = db.execute("SELECT ip, ok FROM login_attempts ORDER BY id DESC LIMIT 1").fetchone()
check("login: fejlede forsoeg logges med IP", fail and fail["ip"] == "198.51.100.7" and fail["ok"] == 0,
      fail and dict(fail))

b.get("/logout")
r = b.get("/login", headers={"x-forwarded-for": "203.0.113.9"})
check("login-side: viser version, IP og koerselsrapport",
      r.status_code == 200 and main.APP_VERSION in r.text and "Din IP" in r.text
      and "Seneste opstart" in r.text and "203.0.113.9" in r.text, r.text[:160])

# --- v7.15: e-mail er login-id, og nye brugere inviteres paa mail (ingen tokens) ---
try:
    main.normalize_email("ikke-en-mail")
    bad_mail = False
except ValueError:
    bad_mail = True
check("mail: ugyldig adresse afvises", bad_mail)
check("mail: adressen gemmes i smaa bogstaver",
      main.normalize_email("  Ejer@Example.DK ") == "ejer@example.dk")
with main.get_db() as db:
    db.execute("UPDATE users SET username='gammelt-navn' WHERE email='iptest@example.dk'")
check("mail: gamle brugernavne kan stadig logge ind",
      TestClient(main.app).post("/login", data={"email": "gammelt-navn", "password": "iptest-pass"},
                                follow_redirects=False).status_code == 303)

sent = {}


def _fake_send(to, subject, body):
    sent.update(to=to, subject=subject, body=body)
    return True, ""


_orig_send = main.send_email
main.send_email = _fake_send
d = TestClient(main.app)
d.post("/login", data={"email": "iptest@example.dk", "password": "iptest-pass"}, follow_redirects=False)
r = d.post("/users/invite", data={"email": "Ny@Example.dk"}, follow_redirects=False)
with main.get_db() as db:
    invited = db.execute("SELECT email, must_change_password FROM users WHERE email='ny@example.dk'").fetchone()
check("invite: mailen gaar til den inviterede adresse", r.status_code == 303 and sent.get("to") == "ny@example.dk",
      (r.status_code, sent.get("to")))
check("invite: svaret lander i Brugere-fanen",
      (r.headers.get("location") or "").startswith("/?tab=brugere&invite=ok"), r.headers.get("location"))
_ok_side = d.get(r.headers["location"])
check("invite: dashboardet bekraefter at mailen er sendt",
      _ok_side.status_code == 200 and "Invitationen er sendt til" in _ok_side.text
      and "ny@example.dk" in _ok_side.text and "tab: 'brugere'" in _ok_side.text, _ok_side.text[:120])
check("invite: brugeren oprettes og skal skifte kode",
      invited and invited["must_change_password"] == 1, invited and dict(invited))
match = __import__("re").search(r"Midlertidig adgangskode: (\S+)", sent.get("body") or "")
temp = match.group(1) if match else ""
e = TestClient(main.app)
check("invite: den midlertidige kode virker",
      bool(temp) and e.post("/login", data={"email": "ny@example.dk", "password": temp},
                            follow_redirects=False).status_code == 303, temp)
check("invite: dashboardet minder om at skifte kode",
      "midlertidig adgangskode" in e.get("/").text)
e.post("/users/password", data={"current": temp, "new": "nyt-pass-1", "confirm": "nyt-pass-1"},
       follow_redirects=False)
with main.get_db() as db:
    cleared = db.execute("SELECT must_change_password FROM users WHERE email='ny@example.dk'").fetchone()
check("invite: skift af adgangskode fjerner midlertidig-kode flaget",
      cleared and cleared["must_change_password"] == 0, cleared and dict(cleared))
main.send_email = lambda to, subject, body: (False, "SMTP_HOST / SMTP_FROM mangler i .env")
r = d.post("/users/invite", data={"email": "fejl@example.dk"}, follow_redirects=False)
with main.get_db() as db:
    missing = db.execute("SELECT COUNT(*) FROM users WHERE email='fejl@example.dk'").fetchone()[0]
    warned = db.execute("SELECT COUNT(*) FROM alarms WHERE message LIKE '%blev ikke sendt%'").fetchone()[0]
check("invite: uden SMTP oprettes ingen bruger, og fejlen bliver en alarm",
      r.status_code == 303 and missing == 0 and warned >= 1, (missing, warned))
check("invite: fejlen sendes tilbage til Brugere-fanen",
      (r.headers.get("location") or "").startswith("/?tab=brugere&invite=fejl"), r.headers.get("location"))
_fail_side = d.get(r.headers["location"])
check("invite: dashboardet viser fejlen i formularen",
      "Invitationen blev ikke sendt" in _fail_side.text and "SMTP_HOST / SMTP_FROM mangler" in _fail_side.text,
      _fail_side.text[:160])
check("invite: en ukendt fane falder tilbage til Cockpit",
      "tab: 'cockpit'" in d.get("/?tab=findes-ikke").text)

# --- v7.17.3: formularen bruger samme tjek som scripts/invite.py, saa en pladsholder forklares ---
main.send_email = _fake_send
r = d.post("/users/invite", data={"email": "dit.navn@domaene.dk"}, follow_redirects=False)
with main.get_db() as db:
    ph_user = db.execute("SELECT COUNT(*) FROM users WHERE email='dit.navn@domaene.dk'").fetchone()[0]
check("invite: en eksempel-adresse afvises i formularen uden at blive en bruger",
      r.status_code == 303 and ph_user == 0 and "invite_kind=eksempel" in (r.headers.get("location") or ""),
      (r.status_code, r.headers.get("location"), ph_user))
_ph_side = d.get(r.headers["location"])
check("invite: formularen forklarer pladsholderen og tilbyder 'opret alligevel'",
      _ph_side.status_code == 200 and "Adressen blev afvist" in _ph_side.text
      and "Opret alligevel" in _ph_side.text and "domaene.dk" in _ph_side.text, _ph_side.text[:160])
check("invite: formularens pladsholder er ikke selv en afvist adresse",
      main.example_email_hint("bruger@ditfirma.dk") == "" and "placeholder=\"bruger@ditfirma.dk\"" in _ph_side.text)
r = d.post("/users/invite", data={"email": "dit.navn@domaene.dk", "force": "1"}, follow_redirects=False)
with main.get_db() as db:
    forced_user = db.execute("SELECT COUNT(*) FROM users WHERE email='dit.navn@domaene.dk'").fetchone()[0]
    db.execute("DELETE FROM users WHERE email='dit.navn@domaene.dk'")
check("invite: force i formularen opretter brugeren alligevel",
      (r.headers.get("location") or "").startswith("/?tab=brugere&invite=ok") and forced_user == 1,
      (r.headers.get("location"), forced_user))
r = d.post("/users/invite", data={"email": "ikke-en-mail"}, follow_redirects=False)
check("invite: en ugyldig adresse forklares som en adressefejl, ikke en mailserver-fejl",
      "invite_kind=adresse" in (r.headers.get("location") or ""), r.headers.get("location"))
main.send_email = _orig_send

# --- v7.17.4: sletning svarer i formularen, ligesom invitationen ---
tmp_id = main.create_user("slettes@example.dk", "slettes-pass-1")
r = d.post("/users/delete", data={"id": str(tmp_id)}, follow_redirects=False)
with main.get_db() as db:
    gone = db.execute("SELECT COUNT(*) FROM users WHERE id=?", (tmp_id,)).fetchone()[0]
    logged = db.execute("SELECT COUNT(*) FROM alarms WHERE message LIKE '%blev slettet%'").fetchone()[0]
check("delete: en slettet bruger er vaek, og sletningen staar i loggen",
      r.status_code == 303 and "del=ok" in (r.headers.get("location") or "") and gone == 0 and logged >= 1,
      (r.headers.get("location"), gone, logged))
r = d.post("/users/delete", data={"id": "999999"}, follow_redirects=False)
check("delete: et ukendt id forklares i stedet for at se ud som en sletning",
      "del_kind=findes-ikke" in (r.headers.get("location") or ""), r.headers.get("location"))
r = d.post("/users/delete", data={"id": "abc"}, follow_redirects=False)
_bad_side = d.get(r.headers["location"])
check("delete: et ugyldigt id forklares i formularen",
      "del_kind=ugyldig" in (r.headers.get("location") or "")
      and "Brugeren blev ikke slettet" in _bad_side.text, (r.headers.get("location"), _bad_side.text[:120]))

# --- v7.17.5: knappen i WordPress faar et engangslink til Command Center ---
_me = main.find_user("iptest@example.dk")
code = main.cc_login_issue(_me["id"])
check("cc-login: engangskoden virker en gang og derefter ikke",
      main.cc_login_consume(code) == _me["id"] and main.cc_login_consume(code) is None)
check("cc-login: tom og ukendt kode afvises",
      main.cc_login_consume("") is None and main.cc_login_consume("findes-ikke") is None)
with main.get_db() as db:
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
               (main.CC_LOGIN_KEY, __import__("json").dumps({"hash": main.hashlib.sha256(b"gammel").hexdigest(),
                                                             "user_id": _me["id"], "exp": 1})))
check("cc-login: en udloebet kode afvises", main.cc_login_consume("gammel") is None)
z = TestClient(main.app)
code2 = main.cc_login_issue(_me["id"])
r = z.get("/cc-login?code=" + code2, follow_redirects=False)
check("cc-login: linket logger ind uden adgangskode",
      r.status_code == 303 and main.SESSION_COOKIE in (r.headers.get("set-cookie") or "")
      and z.get("/").status_code == 200, r.status_code)
r = z.get("/cc-login?code=" + code2, follow_redirects=False)
check("cc-login: et brugt link sendes til login med en forklaring",
      (r.headers.get("location") or "").startswith("/login?cc=")
      and "allerede brugt" in TestClient(main.app).get("/login?cc=udloebet").text,
      r.headers.get("location"))
_ready, _api = main.sgap_ready, main.sgap_api
pushed = []
main.sgap_ready = lambda: True
main.sgap_api = lambda method, path, **kw: (pushed.append((method, path, kw.get("json"))), {"ok": True})[1]
r = d.post("/autopilot/login-link", follow_redirects=False)
_sent = pushed[-1][2] if pushed else {}
check("cc-login: CC laegger linket i WordPress med engangskode",
      (r.headers.get("location") or "").startswith("/?tab=social&cc_link=ok")
      and pushed and pushed[-1][0] == "POST" and pushed[-1][1] == "/login-link"
      and "/cc-login?code=" in (_sent.get("url") or ""), (r.headers.get("location"), pushed[:1]))
_wp_env = (main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD)
main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD = "http://wp.test", "admin", "x"
_social = d.get("/?tab=social")
check("cc-login: knappen staar i fanen Social",
      _social.status_code == 200 and "Log ind p\u00e5 Command Center" in _social.text
      and "/autopilot/login-link" in _social.text, _social.text[:160])
main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD = _wp_env
_ok_code = (_sent.get("url") or "").split("code=")[-1]
check("cc-login: koden i linket er den CC gemmer", main.cc_login_consume(_ok_code) == _me["id"])
main.sgap_api = lambda method, path, **kw: (_ for _ in ()).throw(ValueError("nede"))
r = d.post("/autopilot/login-link", follow_redirects=False)
check("cc-login: en fejl fra WordPress svares i Social-fanen",
      (r.headers.get("location") or "").startswith("/?tab=social&cc_link=fejl"), r.headers.get("location"))
main.sgap_ready, main.sgap_api = _ready, _api

# --- v7.18.0: begge sider viser hvornaar WordPress sidst hoerte fra Command Center ---
import time as _cc_time
check("cc-seen: CC markerer hvert kald med X-Command-Center",
      main.sgap_headers().get("X-Command-Center") == main.APP_VERSION, main.sgap_headers())
_ages = (0, 90, 3 * 3600 + 240, 2 * 86400)
check("cc-seen: alderen skrives i ord",
      [main.cc_age_text(n) for n in _ages] == ["lige nu", "1 min.", "3 t 4 min.", "2 dage"],
      [main.cc_age_text(n) for n in _ages])
_now = 1_800_000_000
_live = main.cc_seen_view({"ok": True, "checked_at": "2026-11-06T14:31:00", "command_center": {
    "ts": _now - 120, "version": "7.18.0", "last_route": "/sgap/v1/snapshot", "user": "admin"}}, now=_now)
check("cc-seen: et kald for 2 min. er live med samme tal som WordPress",
      _live["known"] and _live["state"] == "live" and _live["age"] == 120 and _live["tone"] == "ok"
      and "2 min." in _live["headline"], _live)
_sent_cc = main.cc_seen_view({"ok": True, "command_center": {"ts": _now - 3600}}, now=_now)
check("cc-seen: en time er en misset runde", _sent_cc["state"] == "sent" and _sent_cc["tone"] == "warn", _sent_cc)
_tavs = main.cc_seen_view({"ok": True, "command_center": {"ts": _now - 3 * 3600}}, now=_now)
check("cc-seen: tre timer uden kald er tavst og peger paa WP-creds",
      _tavs["state"] == "tavs" and _tavs["tone"] == "fejl" and "WP_APP_PASSWORD" in _tavs["hint"], _tavs)
_ukendt = main.cc_seen_view({"ok": True})
check("cc-seen: uden /snapshot forklares det i stedet for at gaettes",
      not _ukendt["known"] and _ukendt["tone"] == "muted" and "7.33" in _ukendt["hint"], _ukendt)
_wp_saved = (main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD)
main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD = "http://wp.test", "admin", "x"
with main.get_db() as db:
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('sgap_snapshot', ?)",
               (json.dumps({"ok": True, "checked_at": "2026-11-06T14:31:00", "queue": {},
                            "channels": [], "pending_drafts": 0, "command_center": {
                   "ts": int(_cc_time.time()) - 120, "version": "7.18.0",
                   "last_route": "/sgap/v1/snapshot", "user": "admin"}}),))
_social_cc = d.get("/?tab=social")
check("cc-seen: fanen Social viser hvornaar WordPress sidst hoerte fra CC",
      _social_cc.status_code == 200 and "WordPress hoerte sidst fra Command Center" in _social_cc.text
      and "2 min." in _social_cc.text, _social_cc.text[:160])
with main.get_db() as db:
    db.execute("DELETE FROM settings WHERE key='sgap_snapshot'")
main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD = _wp_saved

# --- v7.19.0: SSRF-beskyttelse paa alle udgaaende kald ---
_ssrf_saved = main.SSRF_ALLOW_HOSTS
main.SSRF_ALLOW_HOSTS = []          # uden allowlist, saa 127.0.0.1 faktisk afvises nedenfor
_blocked_urls = ["http://127.0.0.1/", "http://localhost:8000/x", "http://169.254.169.254/latest/meta-data/",
                 "http://10.1.2.3/", "http://192.168.0.5/", "http://[::1]/", "http://printer.local/",
                 "http://metadata.internal/", "ftp://example.com/x", "gopher://127.0.0.1/"]
_leaked = []
for _u in _blocked_urls:
    try:
        main.assert_public_url(_u)
        _leaked.append(_u)
    except main.BlockedURL:
        pass
check("ssrf: interne adresser, interne navne og andre skemaer afvises", not _leaked, _leaked)
check("ssrf: en offentlig IP slipper igennem",
      main.assert_public_url("http://93.184.216.34/side") == "http://93.184.216.34/side")
check("ssrf: BlockedURL er en ValueError, saa formularerne fanger den",
      issubclass(main.BlockedURL, ValueError))
_fetched = None
try:
    main.safe_request("http://127.0.0.1:9/", timeout=1)
    _fetched = True
except main.BlockedURL:
    _fetched = False
except Exception as e:
    _fetched = "nettet: " + type(e).__name__
check("ssrf: safe_request henter ikke en intern adresse", _fetched is False, _fetched)
_denied = False
try:
    main.normalize_url("127.0.0.1/admin")
except main.BlockedURL:
    _denied = True
check("ssrf: normalize_url afviser 127.0.0.1 i stedet for at gemme den", _denied)
main.SSRF_ALLOW_HOSTS = ["127.0.0.1"]
check("ssrf: CC_SSRF_ALLOW aabner for en enkelt vaert",
      main.assert_public_url("http://127.0.0.1:8770/wp-json") == "http://127.0.0.1:8770/wp-json")
main.SSRF_ALLOW_HOSTS = _ssrf_saved

# --print-stien: mailen holdes tilbage, saa den kan sendes fra en anden mailkonto. Den skal
# virke selv om SMTP fejler, og koden skal vaere den samme som i den udskrevne mail.
produced = []
ok_print, err_print = main.invite_user("print@example.dk", "https://cc.example.dk",
                                       deliver=lambda subject, body: (produced.append(body), (True, ""))[1])
pmatch = __import__("re").search(r"Midlertidig adgangskode: (\S+)", produced[0] if produced else "")
ptemp = pmatch.group(1) if pmatch else ""
prow = main.find_user("print@example.dk")
check("invite: --print opretter brugeren uden SMTP og giver en kode der virker",
      ok_print and bool(ptemp) and prow is not None and prow["must_change_password"] == 1
      and main.verify_password(ptemp, prow["password_hash"])
      and "Adresse: https://cc.example.dk" in (produced[0] if produced else ""),
      (ok_print, err_print, ptemp))
main.send_email = _orig_send

# --- v7.16: MCP fase 1 - laese-vaerktoejer paa /mcp med personlige noegler ---
client_id, api_key = main.create_api_client("CI-agent", "read")
with main.get_db() as db:
    stored = db.execute("SELECT key_hash, key_hint, scopes FROM api_clients WHERE id=?", (client_id,)).fetchone()
check("mcp: noeglen gemmes som hash, ikke i klartekst",
      stored and stored["key_hash"] == main.hash_api_key(api_key) and api_key not in (stored["key_hash"], stored["key_hint"])
      and stored["scopes"] == "read", dict(stored) if stored else None)
check("mcp: ukendt noegle afvises", main.find_api_client("cc_findes-ikke") is None
      and main.find_api_client("") is None)

m = TestClient(main.app)
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
check("mcp: uden noegle svarer 401 med WWW-Authenticate",
      r.status_code == 401 and "Bearer" in (r.headers.get("www-authenticate") or ""), r.status_code)
mh = {"Authorization": f"Bearer {api_key}"}
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "initialize"}, headers=mh)
check("mcp: initialize giver protokolversion og servernavn",
      r.status_code == 200 and r.json()["result"]["protocolVersion"] == main.MCP_PROTOCOL_VERSION
      and r.json()["result"]["serverInfo"]["name"] == "command-center"
      and r.headers.get("mcp-protocol-version") == main.MCP_PROTOCOL_VERSION, r.text[:200])
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, headers=mh)
names = [t["name"] for t in r.json()["result"]["tools"]]
check("mcp: tools/list giver syv laese- og fire skrive-vaerktoejer",
      names == ["health", "crawl_summary", "keywords", "monitors", "alarms_open", "notes", "history",
                "start_crawl", "add_monitor", "resolve_alarm", "add_note"], names)
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                         "params": {"name": "health", "arguments": {}}}, headers=mh)
payload = __import__("json").loads(r.json()["result"]["content"][0]["text"])
check("mcp: health-vaerktoejet svarer med version og alarmer",
      r.json()["result"]["isError"] is False and payload["version"] == main.APP_VERSION
      and "alarms_open" in payload, payload)
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                         "params": {"name": "finnes-ikke", "arguments": {}}}, headers=mh)
check("mcp: ukendt vaerktoej giver -32602", r.json()["error"]["code"] == -32602, r.text[:160])
check("mcp: sidste brug bliver noteret",
      main.find_api_client(api_key)["last_used_at"] is not None)

_public = main.CC_PUBLIC_URL
main.CC_PUBLIC_URL = "https://cc.example.dk"
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 5, "method": "ping"},
           headers={**mh, "Origin": "https://ondskab.example"})
check("mcp: fremmed Origin afvises med 403", r.status_code == 403, r.status_code)
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 6, "method": "ping"},
           headers={**mh, "Origin": "https://cc.example.dk"})
check("mcp: egen Origin og ping virker", r.status_code == 200 and r.json()["result"] == {}, r.text[:120])
main.CC_PUBLIC_URL = _public

only_write, write_key = main.create_api_client("Skrive-klient", "write")
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                         "params": {"name": "health", "arguments": {}}},
           headers={"Authorization": f"Bearer {write_key}"})
check("mcp: noegle uden read-scope afvises", r.json()["error"]["code"] == -32003, r.text[:160])
main.revoke_api_client(client_id)
r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 8, "method": "tools/list"}, headers=mh)
check("mcp: tilbagekaldt noegle virker ikke laengere", r.status_code == 401, r.status_code)
r = m.post("/mcp", data="{ikke json", headers={"Authorization": f"Bearer {write_key}",
                                                "Content-Type": "application/json"})
check("mcp: ugyldig JSON giver 400 og -32700",
      r.status_code == 400 and r.json()["error"]["code"] == -32700, r.status_code)

# --- v7.17: MCP fase 2 - skrivende vaerktoejer med write-scope og audit pr. noegle ---
rw_id, rw_key = main.create_api_client("Skrive-agent", "read,write")
mhw = {"Authorization": f"Bearer {rw_key}"}


def mcp_call(tool, args, key=rw_key):
    return m.post("/mcp", json={"jsonrpc": "2.0", "id": 20, "method": "tools/call",
                                "params": {"name": tool, "arguments": args}},
                  headers={"Authorization": f"Bearer {key}"})


r = m.post("/mcp", json={"jsonrpc": "2.0", "id": 19, "method": "tools/list"}, headers=mhw)
tools = {t["name"]: t for t in r.json()["result"]["tools"]}
check("mcp2: tools/list har annoteringer pr. vaerktoej",
      tools["health"]["annotations"]["readOnlyHint"] is True
      and tools["add_note"]["annotations"]["readOnlyHint"] is False
      and tools["resolve_alarm"]["annotations"]["destructiveHint"] is True,
      {k: v["annotations"] for k, v in tools.items()})

r = mcp_call("add_note", {"content": "MCP-note fra CI"})
note_data = __import__("json").loads(r.json()["result"]["content"][0]["text"])
with main.get_db() as db:
    note_row = db.execute("SELECT content FROM notes WHERE id=?", (note_data["note_id"],)).fetchone()
check("mcp2: add_note skriver noten i dashboardet",
      r.json()["result"]["isError"] is False and note_row and note_row["content"] == "MCP-note fra CI",
      note_data)

ro_id, ro_key = main.create_api_client("Laese-agent", "read")
r = mcp_call("add_note", {"content": "skal afvises"}, key=ro_key)
check("mcp2: read-noegle kan ikke skrive (-32003)",
      r.json()["error"]["code"] == -32003 and "write" in r.json()["error"]["message"], r.text[:160])

mon_args = {"name": "MCP-monitor", "url": "https://example.dk/pris", "type": "price", "expected": "199"}
first = __import__("json").loads(mcp_call("add_monitor", mon_args).json()["result"]["content"][0]["text"])
second = __import__("json").loads(mcp_call("add_monitor", mon_args).json()["result"]["content"][0]["text"])
with main.get_db() as db:
    mon_n = db.execute("SELECT COUNT(*) FROM monitors WHERE name='MCP-monitor'").fetchone()[0]
check("mcp2: add_monitor opretter én monitor og genbruger ved dublet",
      first["created"] is True and second["created"] is False
      and first["monitor_id"] == second["monitor_id"] and mon_n == 1, (first, second, mon_n))

with main.get_db() as db:
    db.execute("INSERT INTO alarms (type, message, severity, created_at) VALUES ('test','MCP-alarm','info',?)",
               (main.now_iso(),))
    alarm_id = db.execute("SELECT MAX(id) FROM alarms").fetchone()[0]
res_data = __import__("json").loads(mcp_call("resolve_alarm", {"id": alarm_id}).json()["result"]["content"][0]["text"])
with main.get_db() as db:
    alarm_resolved = db.execute("SELECT resolved FROM alarms WHERE id=?", (alarm_id,)).fetchone()["resolved"]
check("mcp2: resolve_alarm markerer alamen loest",
      res_data["ok"] is True and res_data["already_resolved"] is False and alarm_resolved == 1, res_data)
r = mcp_call("resolve_alarm", {"id": 999999})
check("mcp2: ukendt alarm giver isError med forklaring",
      r.json()["result"]["isError"] is True and "findes ikke" in r.json()["result"]["content"][0]["text"],
      r.json()["result"]["content"][0]["text"])

_crawl_was = main.CRAWL_STATE.get("running")
main.CRAWL_STATE["running"] = True
r = mcp_call("start_crawl", {"url": "https://example.dk"})
check("mcp2: start_crawl afvises naar et crawl koerer",
      r.json()["result"]["isError"] is True and "kører allerede" in r.json()["result"]["content"][0]["text"],
      r.json()["result"]["content"][0]["text"])
main.CRAWL_STATE["running"] = _crawl_was
r = mcp_call("start_crawl", {"url": "ikke-en-url"})
check("mcp2: start_crawl afviser en ugyldig URL",
      r.json()["result"]["isError"] is True, r.json()["result"]["content"][0]["text"])

audit_rows = main.api_audit_rows(100)
usage = main.api_usage()
check("mcp2: auditten har ét spor pr. kald med noeglenavn og varighed",
      any(a["tool"] == "add_note" and a["ok"] == 1 and a["client"] == "Skrive-agent" for a in audit_rows)
      and any(a["tool"] == "resolve_alarm" and a["ok"] == 1 for a in audit_rows)
      and all(isinstance(a["duration_ms"], int) for a in audit_rows), audit_rows[:3])
check("mcp2: afviste kald havner i auditten med scope-aarsag",
      any(a["tool"] == "add_note" and a["ok"] == 0 and "scope: write" in (a["detail"] or "") for a in audit_rows),
      [a for a in audit_rows if not a["ok"]][:2])
check("mcp2: api_usage taeller kald og fejl pr. noegle",
      usage.get(rw_id, {}).get("calls", 0) >= 3 and usage.get(ro_id, {}).get("errors", 0) >= 1, usage)
check("mcp2: auditten gemmer ikke noeglen i klartekst",
      not any((rw_key in (a["detail"] or "")) or (rw_key in (a["tool"] or "")) for a in audit_rows))

# --- v7.17.1: ukendte vaerktoejer i auditten + noeglen bliver ikke liggende i klartekst ---
r = mcp_call("findes_ikke", {})
row = main.api_audit_rows(1)[0]
check("mcp3: ukendt vaerktoej giver -32602 og havner i auditten",
      r.json()["error"]["code"] == -32602
      and row["tool"] == "findes_ikke" and row["ok"] == 0 and "ukendt" in (row["detail"] or ""),
      (r.json()["error"]["code"], row["tool"], row["detail"]))

_j = __import__("json")
main.remember_api_key("Engangs-noegle", rw_key)
with main.get_db() as db:
    raw = db.execute("SELECT value FROM settings WHERE key='api_key_once'").fetchone()
raw_data = _j.loads(raw["value"]) if raw else {}
check("mcp3: remember_api_key gemmer et tidsstempel",
      bool(raw_data.get("created_at")) and raw_data.get("key") == rw_key, raw_data)
shown = main.pending_api_key()
with main.get_db() as db:
    left = db.execute("SELECT COUNT(*) FROM settings WHERE key='api_key_once'").fetchone()[0]
check("mcp3: noeglen vises én gang og slettes i samme kald",
      shown and shown["key"] == rw_key and left == 0, (bool(shown), left))
check("mcp3: genindlaesning viser ingen noegle", main.pending_api_key() is None)

stale = (main.datetime.now() - main.timedelta(minutes=20)).isoformat(timespec="seconds")
with main.get_db() as db:
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('api_key_once', ?)",
               (_j.dumps({"name": "Gammel", "key": rw_key, "created_at": stale}),))
check("mcp3: en noegle aeldre end 15 min vises ikke", main.pending_api_key() is None)
with main.get_db() as db:
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('api_key_once', ?)",
               (_j.dumps({"name": "Glemt", "key": rw_key, "created_at": stale}),))
main.cleanup_old_data()
with main.get_db() as db:
    glemt = db.execute("SELECT COUNT(*) FROM settings WHERE key='api_key_once'").fetchone()[0]
check("mcp3: oprydningen fjerner en glemt noegle", glemt == 0, glemt)

main.log_startup("127.0.0.1", 8000)      # lifespan koerer ikke i TestClient uden context manager
rep = main.last_run_report()
check("report: version, taellinger, tidsstempler og db-stoerrelse",
      rep["version"] == main.APP_VERSION and rep["alarms_open"] >= 0 and rep["db_mb"] is not None
      and rep["last_start"] and rep["newest"], rep)

hb = TestClient(main.app).get("/health").json()
check("health: nyheder og opstartstid er med",
      hb.get("newest") and len(hb["newest"]) >= 1 and "started_at" in hb, (hb.get("newest"), hb.get("started_at")))

# --- oprydning: tomme Juno-tabelrester droppes, tabeller med data beholdes (v7.13.1) ---
with main.get_db() as db:
    for t in ("drift", "gsc_daily", "gsc_queries"):
        db.execute(f"CREATE TABLE IF NOT EXISTS {t} (id INTEGER PRIMARY KEY, x TEXT)")
    db.execute("INSERT INTO gsc_queries (x) VALUES ('behold')")
main.migrate_db()
with main.get_db() as db:
    names = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    kept = db.execute("SELECT COUNT(*) FROM gsc_queries").fetchone()[0]
check("oprydning: tomme Juno-tabeller droppes, tabeller med data beholdes",
      "drift" not in names and "gsc_daily" not in names and "gsc_queries" in names and kept == 1,
      (sorted(n for n in names if n.startswith(("drift", "gsc"))), kept))

# --- tider: lokal tid + UTC (v7.14.0) ---
check("tid: sommertid konverteres korrekt (juli = UTC+2)",
      main.local_to_utc("2026-07-01T12:00") == "2026-07-01T10:00:00+00:00",
      main.local_to_utc("2026-07-01T12:00"))
check("tid: vintertid konverteres korrekt (januar = UTC+1)",
      main.local_to_utc("2026-01-15T12:00") == "2026-01-15T11:00:00+00:00",
      main.local_to_utc("2026-01-15T12:00"))
check("tid: rundtur lokal -> UTC -> lokal er uaendret",
      main.utc_to_local(main.local_to_utc("2026-07-01T12:00")) == "2026-07-01T12:00:00",
      main.utc_to_local(main.local_to_utc("2026-07-01T12:00")))
try:
    main.local_to_utc("2026-03-29T02:30")
    nonexistent = False
except ValueError as e:
    nonexistent = "sommertid" in str(e)
check("tid: ikke-eksisterende tid afvises (spring forward 29/3 2026)", nonexistent)
check("tid: tvetydig tid giver foerste forekomst (25/10 2026)",
      main.local_to_utc("2026-10-25T02:30") == "2026-10-25T00:30:00+00:00",
      main.local_to_utc("2026-10-25T02:30"))
try:
    main.local_to_utc("i morgen")
    bad_fmt = False
except ValueError:
    bad_fmt = True
check("tid: ugyldigt format afvises", bad_fmt)
check("tid: ukendt zone falder tilbage i stedet for at crashe",
      main.CC_TZ_NAME == "Europe/Copenhagen", main.CC_TZ_NAME)

c2 = TestClient(main.app)
c2.post("/login", data={"email": "iptest@example.dk", "password": "iptest-pass"}, follow_redirects=False)
check("social: testklienten er logget ind", c2.get("/").status_code == 200, c2.get("/").status_code)
c2.post("/social/add", data={"platform": "Pinterest", "message": "Test opslag",
                             "scheduled_at": "2026-07-01T12:00"})
with main.get_db() as db:
    row = db.execute("SELECT * FROM socialqueue ORDER BY id DESC LIMIT 1").fetchone()
check("social: planlagt opslag gemmer lokal tid OG UTC",
      bool(row) and row["scheduled_at"] == "2026-07-01T12:00:00"
      and row["scheduled_at_utc"] == "2026-07-01T10:00:00+00:00",
      (row["scheduled_at"], row["scheduled_at_utc"]) if row else None)
check("social: created_at_utc gemmes ved siden af created_at",
      bool(row) and (row["created_at_utc"] or "").endswith("+00:00") and bool(row["created_at"]),
      row["created_at_utc"] if row else None)
check("social: planlagt opslag faar status Planlagt", bool(row) and row["status"] == "Planlagt",
      row["status"] if row else None)
payload = main.social_payload(row, "pinterest", "titel", "body")
check("social: payload har UTC, lokal tid og zone",
      payload.get("scheduled_at_utc") == "2026-07-01T10:00:00+00:00"
      and payload.get("scheduled_at_local") == "2026-07-01T12:00:00"
      and payload.get("timezone") == main.CC_TZ_NAME, payload)
check("social: payload uden planlagt tid har ingen tidsfelter",
      set(main.social_payload({"scheduled_at": "", "scheduled_at_utc": ""}, "x", "t", "b"))
      == {"channel", "title", "body", "ai_model"})
with main.get_db() as db:
    before = db.execute("SELECT COUNT(*) FROM socialqueue").fetchone()[0]
c2.post("/social/add", data={"platform": "Pinterest", "message": "Sommertid",
                             "scheduled_at": "2026-03-29T02:30"})
with main.get_db() as db:
    after = db.execute("SELECT COUNT(*) FROM socialqueue").fetchone()[0]
    alarm = db.execute("SELECT message FROM alarms WHERE type='social' ORDER BY id DESC LIMIT 1").fetchone()
check("social: ugyldig sommertid gemmes IKKE og giver alarm",
      after == before and bool(alarm) and "sommertid" in alarm["message"],
      (after, alarm["message"] if alarm else None))
with main.get_db() as db:
    db.execute("INSERT INTO socialqueue (platform, message, status, created_at) VALUES (?,?,?,?)",
               ("Legacy", "gammel raekke", "Klar i ko", "2026-01-15T12:00:00"))
main.migrate_db()
with main.get_db() as db:
    legacy = db.execute("SELECT created_at_utc FROM socialqueue WHERE platform='Legacy'").fetchone()
check("social: migrering backfiller UTC for gamle raekker",
      bool(legacy) and legacy["created_at_utc"] == "2026-01-15T11:00:00+00:00",
      legacy["created_at_utc"] if legacy else None)
csv_text = c2.get("/social/export.csv").text
check("social: CSV har UTC-kolonner og zone",
      "created_at_utc" in csv_text and "scheduled_at_utc" in csv_text and main.CC_TZ_NAME in csv_text,
      csv_text.splitlines()[0] if csv_text else "")

# --- idempotens: samme opslag maa kun give én kladde i WordPress ---
class _SgapDrafts(BaseHTTPRequestHandler):
    log_message = lambda self, *a: None
    posts = []
    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        _SgapDrafts.posts.append(json.loads(self.rfile.read(n) or b"{}"))
        b = json.dumps({"id": len(_SgapDrafts.posts)}).encode()
        self.send_response(201)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


_sgap_srv = HTTPServer(("127.0.0.1", 0), _SgapDrafts)
threading.Thread(target=_sgap_srv.serve_forever, daemon=True).start()
with main.get_db() as db:
    db.execute("INSERT INTO socialqueue (platform, message, status, created_at) VALUES (?,?,?,?)",
               ("Twitter", "dobbeltklik", "Klar i ko", "2026-01-01T12:00:00"))
    double_id = db.execute("SELECT MAX(id) FROM socialqueue").fetchone()[0]
_keep = main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD, main.sgap_ready
main.WP_URL = f"http://127.0.0.1:{_sgap_srv.server_address[1]}"
main.WP_USER, main.WP_APP_PASSWORD = "admin", "app pass"
main.sgap_ready = lambda: True
for _ in range(3):
    c2.post("/social/to-autopilot", data={"id": double_id})
main.sgap_ready = _keep[3]
main.WP_URL, main.WP_USER, main.WP_APP_PASSWORD = _keep[0], _keep[1], _keep[2]
check("autopilot: dobbeltklik sender kun én kladde", len(_SgapDrafts.posts) == 1, len(_SgapDrafts.posts))
with main.get_db() as db:
    dbl = db.execute("SELECT status FROM socialqueue WHERE id=?", (double_id,)).fetchone()
check("autopilot: status peger paa den ene kladde",
      bool(dbl) and dbl["status"] == "sendt til autopilot (kladde #1)", dbl["status"] if dbl else None)

# --- /snapshot-oversaettelse og WP-Cron-ping (v7.19) ---
_m = main.sgap_from_snapshot({
    "version": "7.33.0", "missing_tables": ["events"],
    "status": {"autopilot": True, "full_auto": True, "sending_paused_because": "Quiet hours", "cron_lag_minutes": "40",
               "last_self_check": {"at": "2026-11-05 06:00", "problems": ["The autopilot is off.", 7]}},
    "counts": {"queue": {"queued": "2", "failed": 1}, "drafts": {"pending": "4", "used": 9}},
    "results": {"by_channel": [{"channel": "facebook", "published": "1", "clicks": "5", "orders": "0", "revenue": "0"},
                               {"channel": "pinterest", "published": "0", "clicks": "1", "orders": "1", "revenue": "19.5"}]}})
check("snapshot: koe og kladder som tal", _m["queue"] == {"queued": 2, "failed": 1} and _m["pending_drafts"] == 4, _m)
check("snapshot: kanaler sorteret efter omsaetning", [c["channel"] for c in _m["channels"]] == ["pinterest", "facebook"]
      and _m["channels"][0] == {"channel": "pinterest", "publish": 0, "click": 1, "order": 1, "revenue": 19.5}, _m["channels"])
check("snapshot: selvtjek, pause, cron og manglende tabeller",
      _m["problems"] == ["The autopilot is off.", "7"] and _m["paused_because"] == "Quiet hours"
      and _m["cron_lag_minutes"] == 40 and _m["missing_tables"] == ["events"] and _m["version"] == "7.33.0", _m)
check("snapshot: tomt svar giver ingen fejl", main.sgap_from_snapshot({})["queue"] == {} and main.sgap_from_snapshot({})["problems"] == [])


class _CronSite(BaseHTTPRequestHandler):
    hits = []
    def log_message(self, *a):
        pass
    def do_GET(self):
        _CronSite.hits.append((self.path, self.headers.get("X-Command-Center")))
        self.send_response(200)
        self.send_header("content-length", "0")
        self.end_headers()


_cron_srv = HTTPServer(("127.0.0.1", 0), _CronSite)
threading.Thread(target=_cron_srv.serve_forever, daemon=True).start()
_keep_url = main.WP_URL
main.WP_URL = f"http://127.0.0.1:{_cron_srv.server_address[1]}/"
_code = main.wp_cron_ping()
main.WP_URL = _keep_url
check("wp-cron: ping rammer wp-cron.php med doing_wp_cron", _code == 200 and len(_CronSite.hits) == 1
      and _CronSite.hits[0][0].startswith("/wp-cron.php?doing_wp_cron="), _CronSite.hits)
check("wp-cron: ping sender X-Command-Center", _CronSite.hits[0][1] == main.APP_VERSION if _CronSite.hits else False)
check("wp-cron: job koerer hvert 5. min", 'id="wp_cron"' in open(os.path.join(os.path.dirname(main.__file__), "main.py")).read())
with main.get_db() as db:
    db.execute("INSERT INTO socialqueue (platform, message, status, created_at) VALUES (?,?,?,?)",
               ("Mastodon", "laas", "Klar i ko", "2026-01-01T12:00:00"))
    lock_id = db.execute("SELECT MAX(id) FROM socialqueue").fetchone()[0]
    first = main.social_claim(db, lock_id)
    second = main.social_claim(db, lock_id)
check("autopilot: laasen kan kun tages én gang", first and not second, (first, second))

# --- agent + skill i repoet (v7.13.3) ---
import glob, re as _re
agents_dir = os.path.join(ROOT, ".agents")
agent_files = sorted(glob.glob(os.path.join(agents_dir, "*.ts")))
manifest_p = os.path.join(agents_dir, "README.md")
skill_p = os.path.join(agents_dir, "skills", "command-center", "SKILL.md")
manifest = open(manifest_p, encoding="utf-8").read() if os.path.exists(manifest_p) else ""
skill = open(skill_p, encoding="utf-8").read() if os.path.exists(skill_p) else ""
texts = {p: open(p, encoding="utf-8").read() for p in agent_files}
check("agents: mindst fem definitioner fordelt paa tre repos",
      len(agent_files) >= 5, [os.path.basename(p) for p in agent_files])
bad = []
for path, txt in texts.items():
    stem = os.path.basename(path)[:-3]
    m = _re.search(r"id: '([a-z0-9-]+)'", txt)
    if not (m and m.group(1) == stem and all(k in txt for k in
            ("displayName:", "model:", "toolNames:", "instructionsPrompt", "export default definition"))):
        bad.append(os.path.basename(path))
check("agents: id matcher filnavn, og alle har model, vaerktoejer og prompt", not bad, bad)
check("agents: hver agent er naevnt i .agents/README.md",
      all(os.path.basename(p)[:-3] in manifest for p in agent_files),
      [os.path.basename(p) for p in agent_files if os.path.basename(p)[:-3] not in manifest])
check("agents: manifestet grupperer dem med de tre repos",
      all(k in manifest for k in ("Command Center", "Social Autopilot", "Social Autopilot Android")))
front = skill.split("---")[1] if skill.startswith("---") else ""
desc = _re.search(r"description: (.+)", skill)
check("skill: SKILL.md har frontmatter med name = mappenavn",
      skill.startswith("---") and "name: command-center" in front, front[:80])
check("skill: beskrivelsen er 10-1024 tegn", bool(desc) and 10 < len(desc.group(1)) <= 1024)
check("agent+skill: ingen hemmeligheder i filerne",
      not any(t in (manifest + skill + "".join(texts.values())).lower()
              for t in ("sk-ant", "api_key=", "password=", "ghp_")))
check("agents: alle filer er danske/ascii (ingen utilsigtet fremmed tekst)",
      not any(_re.search(r"[\u4e00-\u9fff]", t) for t in (manifest, skill, *texts.values())))

# --- v7.20.0: budget-kort og job-heartbeat paa Cockpit ---
from datetime import timedelta as _td
with main.get_db() as _db:
    _db.execute("DELETE FROM alarms WHERE type='jobs'")
    for _k in [r["key"] for r in _db.execute("SELECT key FROM settings WHERE key LIKE 'job_%'").fetchall()]:
        _db.execute("DELETE FROM settings WHERE key=?", (_k,))
_now = datetime.now()
# Job 1 er ok for nylig, job 2 er ok for 30 timer siden (forsinket: max 26 t), job 3 fejlede
main._job_mark("keyword_checks", True, "")
with main.get_db() as _db:
    _db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('job_ok_cleanup', ?)", ((_now - _td(hours=30)).isoformat(timespec="seconds"),))
main._job_mark("db_backup", False, "RuntimeError('disk fuld')")
st = {j["id"]: j["state"] for j in main.job_status()}
check("heartbeat: ok, forsinket og fejlet skelnes", st["keyword_checks"] == "ok" and st["cleanup"] == "forsinket" and st["db_backup"] == "fejlet", st)
import asyncio as _aio
_aio.run(main.job_heartbeat_check())
_aio.run(main.job_heartbeat_check())  # anden koersel maa ikke give dubletter
with main.get_db() as _db:
    _al = [r["message"] for r in _db.execute("SELECT message FROM alarms WHERE type='jobs' ORDER BY id").fetchall()]
check("heartbeat: forsinket og fejl alarmeres praecis én gang", len(_al) == 2 and any("fejlede" in m for m in _al) and any("forsinket" in m for m in _al), _al)
# Jobbet der fejlede koerer ok igen -> ingen ny alarm, og tilstanden nulstilles
main._job_mark("db_backup", True, "")
_aio.run(main.job_heartbeat_check())
with main.get_db() as _db:
    _n = _db.execute("SELECT COUNT(*) FROM alarms WHERE type='jobs'").fetchone()[0]
check("heartbeat: et job der er ok igen giver ingen ekstra alarm", _n == 2, _n)
# Ny installation: et job der aldrig har koert alarmeres ikke foer appen har koert laenger end maks-alderen
with main.get_db() as _db:
    _db.execute("DELETE FROM settings WHERE key IN ('last_start') OR key LIKE 'job_%'")
    _db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_start', ?)", (_now.isoformat(timespec="seconds"),))
check("heartbeat: nyt job der aldrig har koert er ikke forsinket endnu", all(j["state"] == "ok" for j in main.job_status()),
      [(j["id"], j["state"]) for j in main.job_status() if j["state"] != "ok"])
with main.get_db() as _db:
    _db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_start', ?)", ((_now - _td(hours=30)).isoformat(timespec="seconds"),))
check("heartbeat: et job der aldrig har koert er forsinket efter maks-alderen", next(j for j in main.job_status() if j["id"] == "cleanup")["state"] == "forsinket")
# Cockpit viser budget-kortet og job-listen
with main.get_db() as _db:
    _db.execute("DELETE FROM settings WHERE key LIKE 'job_%'")
_h = TestClient(main.app).get("/health").json()
_bu = main.budget_usage()
check("budget: /health og budget_usage() giver samme tal", _h["budget"] == {s: {"used": u, "limit": l} for s, (u, l) in _bu.items()}, _h["budget"])

# --- CSRF og session-rotation (roadmap 2) ---
_cs = TestClient(main.app)
_cs.post("/login", data={"email": "iptest@example.dk", "password": "iptest-pass"}, follow_redirects=False)
_old_sid = _cs.cookies.get(main.SESSION_COOKIE)
_cross = _cs.post("/alerts/test", headers={"Sec-Fetch-Site": "cross-site", "Origin": "https://ondskab.example"}, follow_redirects=False)
check("csrf: cross-site POST afvises med 403", _cross.status_code == 403, _cross.status_code)
_cross2 = _cs.post("/alerts/test", headers={"Origin": "https://ondskab.example"}, follow_redirects=False)
check("csrf: fremmed Origin uden Sec-Fetch-Site afvises", _cross2.status_code == 403, _cross2.status_code)
_same = _cs.post("/alerts/test", headers={"Sec-Fetch-Site": "same-origin", "Origin": "http://testserver"}, follow_redirects=False)
check("csrf: same-origin POST gaar igennem (ikke 403)", _same.status_code != 403, _same.status_code)
_cs.post("/login", data={"email": "iptest@example.dk", "password": "iptest-pass"}, follow_redirects=False)
_new_sid = _cs.cookies.get(main.SESSION_COOKIE)
check("session: login giver ny sid", bool(_new_sid) and _new_sid != _old_sid)
_stale = TestClient(main.app, cookies={main.SESSION_COOKIE: _old_sid or "x"})
check("session: gammel sid er ugyldig efter login-rotation", _stale.get("/api/history/1", follow_redirects=False).status_code == 401 or _stale.get("/", follow_redirects=False).status_code in (303, 307), "")

# --- Offline dashboard: ingen CDN-scripts (roadmap 3) ---
_html = open(os.path.join(ROOT, "app", "templates", "dashboard.html"), encoding="utf-8").read()
_ext = _re.findall(r'<(?:script|link)[^>]+(?:src|href)="(https?://[^"]+)"', _html)
check("offline: dashboard.html har ingen eksterne script/link-URL'er", not _ext, _ext)
for _vf in ("tailwind.js", "alpine.min.js", "chart.umd.min.js"):
    _vr = _cs.get(f"/static/vendor/{_vf}")
    check(f"offline: /static/vendor/{_vf} serveres lokalt", _vr.status_code == 200 and len(_vr.content) > 1000, _vr.status_code)

# --- Backup og restore i UI (roadmap 2) ---
_bk_ok = _cs.post("/backup/now", headers={"Origin": "http://testserver"}, follow_redirects=False)
check("backup: manuel backup laver fil og redirect til Moduler", _bk_ok.status_code == 303 and "bk=ok" in _bk_ok.headers.get("location", ""), _bk_ok.headers.get("location"))
_bks = main.list_backups()
check("backup: list_backups viser manuel backup", any(b["name"].startswith("cc-manuel-") for b in _bks), _bks)
check("backup: navn med sti/.. afvises", main._backup_path("../center.db") is None and main._backup_path("cc-x/../../center.db") is None)
check("backup: fri filnavn afvises (kun cc-tag-YYYYMMDD-HHMM.db)", main._backup_path("center.db") is None and main._backup_path("cc-manuel-x.db") is None)
_no_confirm = _cs.post("/backup/restore", data={"name": _bks[0]["name"], "confirm": "nej"}, headers={"Origin": "http://testserver"}, follow_redirects=False)
check("restore: uden bekraeftelsesordet GENDAN gendannes intet", "bk=fejl" in _no_confirm.headers.get("location", ""), _no_confirm.headers.get("location"))
_bad = os.path.join(main.BASE_DIR, "backups", "cc-broken-20990101-0000.db")
with open(_bad, "wb") as _f:
    _f.write(b"ikke en database")
check("restore: ugyldig fil afvises af integritetstjek", main._check_backup_file(_bad) is not None and main.restore_backup_sync("cc-broken-20990101-0000.db")[0] is False)
os.remove(_bad)
_before = os.path.getsize(main.DB_PATH)
_good = _cs.post("/backup/restore", data={"name": _bks[0]["name"], "confirm": "GENDAN"}, headers={"Origin": "http://testserver"}, follow_redirects=False)
check("restore: med GENDAN gendannes og redirect viser ok", "bk=ok" in _good.headers.get("location", ""), _good.headers.get("location"))
check("restore: der tages en pre-restore-kopi foer gendannelse", any(b["name"].startswith("cc-pre-restore-") for b in main.list_backups()))
check("restore: login virker efter gendannelse", TestClient(main.app).post("/login", data={"email": "iptest@example.dk", "password": "iptest-pass"}, follow_redirects=False).status_code in (303, 307))
# Gendannelsen erstatter databasen, så den gamle session er ugyldig: log ind igen.
_cs2 = TestClient(main.app)
_cs2.post("/login", data={"email": "iptest@example.dk", "password": "iptest-pass"}, follow_redirects=False)
_dash = _cs2.get("/?tab=moduler&bk=ok&bk_msg=test").text
check("backup: dashboard viser backup-kort og feedback", "Database-backup" in _dash and "skriv GENDAN" in _dash and "Tag backup nu" in _dash, "")

# --- v7.24: Vækst - lokal indholdsoptimering uden API-nøgle ---
_kw = "steampunk goggles"
_filler = "Messing og læder giver en holdbar ramme med justerbar pasform til cosplay."
_para = "Steampunk goggles i messing og læder. " + " ".join([_filler] * 10)
_plain = " ".join([_filler] * 10)
_good_html = (
    "<html><head><title>Steampunk goggles - guide til køb og pasform</title>"
    "<meta name=\"description\" content=\"Guide til steampunk goggles i messing og læder: pasform, "
    "størrelser, priser og hvad du skal se efter.\"></head><body>"
    "<h1>Steampunk goggles</h1>"
    + "".join(f"<h2>Steampunk goggles: {x}</h2><p>{_para}</p>" for x in ("pasform", "pris", "vedligehold"))
    + f"<h2>Ofte stillede spørgsmål</h2><p>{_plain}</p>"
    + '<a href="/shop">shop</a><a href="/guide">guide</a></body></html>'
)
_terms = ["messing", "læder", "pasform"]
_good = main.local_content_optimizer(_good_html, _kw, _terms, 500)
check("vækst: komplet side scorer højt", _good["score"] >= 90, (_good["score"], [c["name"] for c in _good["checks"] if not c["ok"]]))
check("vækst: scoren bygger på vægtede kontroller", len(_good["checks"]) >= 10
      and all(c["weight"] > 0 for c in _good["checks"]) and _good["words"] > 400, _good["words"])
check("vækst: termdækning tælles for alle termer",
      len(_good["terms"]) == 4 and all(t["present"] for t in _good["terms"]), _good["terms"])
_thin = main.local_content_optimizer("<h2>Kort</h2><p>lidt tekst</p>", _kw, [], 800)
check("vækst: tynd tekst scorer lavt og får forbedringer",
      _thin["score"] < 40 and _thin["fixes"] and any("Ordantal" in f["text"] for f in _thin["fixes"]), _thin["score"])
_thin_no_kw = main.local_content_optimizer("<p>noget indhold</p>", "", [], 0)
check("vækst: uden fokus-keyword siges det højt",
      _thin_no_kw["fixes"] and any("Fokus-keyword" in f["text"] for f in _thin_no_kw["fixes"]))
check("vækst: hele ord tælles, ikke delstrenge",
      main.term_stats("goggles gogglesx goggles", "goggles")["count"] == 2, main.term_stats("goggles gogglesx goggles", "goggles"))
check("vækst: termlister renses og afdubles",
      main.parse_term_list("Messing, læder;  messing \n pasform") == ["messing", "læder", "pasform"],
      main.parse_term_list("Messing, læder;  messing \n pasform"))
check("vækst: toptermer ignorerer funktionsord og korte ord",
      all(t["term"] not in ("og", "er", "i") and len(t["term"]) >= 3 for t in main.content_top_terms(_plain)), main.content_top_terms(_plain)[:3])

_gw = TestClient(main.app)
check("vækst: login til rutetest", _gw.post("/login", data={"email": "iptest@example.dk", "password": "iptest-pass"},
                                           follow_redirects=False).status_code == 303)
_serp_before, _ai_before = main.SERPAPI_KEY, main.OPENROUTER_API_KEY
main.SERPAPI_KEY, main.OPENROUTER_API_KEY = "", ""      # vækst må ikke kræve nogen af dem
_opt = _gw.post("/growth/optimize", data={"content": _good_html, "keyword": _kw, "terms": ", ".join(_terms),
                                         "target_words": "500"})
check("vækst: /growth/optimize svarer med score uden API-nøgler",
      _opt.status_code == 200 and _opt.json().get("ok") and _opt.json()["score"] >= 90, _opt.status_code)
with main.get_db() as db:
    _audits = db.execute("SELECT COUNT(*) FROM content_audits").fetchone()[0]
check("vækst: hver optimering gemmes i historikken", _audits >= 1, _audits)
_empty = _gw.post("/growth/optimize", data={"content": "", "url": "", "keyword": "x"})
check("vækst: tomt input forklares i stedet for at give 200", _empty.status_code == 400 and _empty.json().get("error"))

# Konkurrent-sammenligning mod den lokale testserver (ingen SERP-API)
_page_a = f"http://127.0.0.1:{port}/a"
_cmp = _gw.post("/growth/compare", data={"content": "<p>kort tekst om noget andet</p>", "competitors": _page_a,
                                        "keyword": "brass goggles"})
_cmp_json = _cmp.json() if _cmp.status_code == 200 else {}
check("vækst: sammenligningen henter konkurrentsiden",
      _cmp.status_code == 200 and _cmp_json.get("averages", {}).get("pages") == 1
      and _cmp_json["competitors"][0]["words"] > 0, _cmp_json.get("averages"))
check("vækst: konkurrentens emner vi ikke dækker vises som muligheder",
      bool(_cmp_json.get("single_terms")) and all(t["in_competitors"] >= 1 for t in _cmp_json["single_terms"]),
      _cmp_json.get("single_terms"))
check("vækst: sammenligningen giver råd om længde eller H2",
      bool(_cmp_json.get("advice")) and any("ord" in a or "H2" in a for a in _cmp_json["advice"]), _cmp_json.get("advice"))
check("vækst: en side der ikke kan hentes rapporteres pr. URL",
      _gw.post("/growth/compare", data={"url": _page_a, "competitors": "http://127.0.0.1:1/nej"}).json()
      ["competitors"][0]["ok"] is False)
main.SERPAPI_KEY, main.OPENROUTER_API_KEY = _serp_before, _ai_before

# Indholdsplan: brief bygges lokalt, kan skiftes og slettes
_br = _gw.post("/growth/brief", data={"keyword": "steampunk goggles", "intent": "transaktionel",
                                      "terms": "messing, læder", "planned_for": "2026-12-01"},
               follow_redirects=False)
with main.get_db() as db:
    _brief = db.execute("SELECT * FROM content_briefs ORDER BY id DESC LIMIT 1").fetchone()
check("vækst: briefen gemmes med mål og overskrifter",
      _br.status_code == 303 and _brief and _brief["words"] >= 800 and "Hvad er" in _brief["headings"]
      and "messing" in (_brief["terms"] or ""), _brief and dict(_brief))
check("vækst: briefen husker planlagt dato og status",
      _brief["planned_for"] == "2026-12-01" and _brief["status"] == "Planlagt", _brief["status"])
_gw.post("/growth/brief/status", data={"id": _brief["id"], "status": "Skrevet"})
with main.get_db() as db:
    check("vækst: status kan flyttes i planen",
          db.execute("SELECT status FROM content_briefs WHERE id=?", (_brief["id"],)).fetchone()["status"] == "Skrevet")
_gw.post("/growth/brief/status", data={"id": _brief["id"], "status": "Ukendt"})
with main.get_db() as db:
    check("vækst: ukendt status afvises",
          db.execute("SELECT status FROM content_briefs WHERE id=?", (_brief["id"],)).fetchone()["status"] == "Skrevet")
_gw.post("/growth/brief/delete", data={"id": _brief["id"]})
with main.get_db() as db:
    check("vækst: briefen kan slettes",
          db.execute("SELECT COUNT(*) FROM content_briefs WHERE id=?", (_brief["id"],)).fetchone()[0] == 0)

# Linkmuligheder: manuel liste, samme URL kun én gang, ugyldig URL forklares
_gw.post("/links/target/add", data={"url": "https://partner.example.dk/ressourcer", "type_": "Ressourceside",
                                    "contact": "redaktionen@partner.example.dk", "reason": "Relevant guide"})
_gw.post("/links/target/add", data={"url": "https://partner.example.dk/ressourcer", "type_": "Forum"})
with main.get_db() as db:
    _links = db.execute("SELECT * FROM link_targets").fetchall()
check("vækst: linkmuligheden gemmes med type og status",
      len(_links) == 1 and _links[0]["type"] == "Ressourceside" and _links[0]["status"] == "Ny",
      [dict(l) for l in _links])
_bad_link = _gw.post("/links/target/add", data={"url": "ikke en url"}, follow_redirects=False)
with main.get_db() as db:
    _still = db.execute("SELECT COUNT(*) FROM link_targets").fetchone()[0]
check("vækst: ugyldig URL afvises med en forklaring",
      _bad_link.status_code == 303 and "link=fejl" in _bad_link.headers.get("location", "") and _still == 1,
      _bad_link.headers.get("location"))
_gw.post("/links/target/status", data={"id": _links[0]["id"], "status": "Link live"})
with main.get_db() as db:
    check("vækst: linkets status kan følges",
          db.execute("SELECT status FROM link_targets WHERE id=?", (_links[0]["id"],)).fetchone()["status"] == "Link live")
_gw.post("/links/target/delete", data={"id": _links[0]["id"]})
with main.get_db() as db:
    check("vækst: linket kan fjernes", db.execute("SELECT COUNT(*) FROM link_targets").fetchone()[0] == 0)

# Fanen selv: plan, linkliste og optimeringskortet skal være i dashboardet
_dash_growth = _gw.get("/?tab=vaekst")
check("vækst: fanen vises med alle fire værktøjer",
      _dash_growth.status_code == 200
      and all(t in _dash_growth.text for t in ("Indholdsoptimerer", "Sammenlign med konkurrenter",
                                               "Indholdsplan", "Linkmuligheder")), _dash_growth.status_code)
check("vækst: fanen er en del af navigationen og fanelisten",
      "vaekst" in main.DASHBOARD_TABS and "tab='vaekst'" in _dash_growth.text)
check("vækst: dashboardet har ingen eksterne scripts", "https://cdn" not in _dash_growth.text)

# --- v7.18: standardbrugeren oprettes ved opstart fra .env (rydder brugere, derfor sidst) ---
with main.get_db() as db:
    db.execute("DELETE FROM sessions"); db.execute("DELETE FROM login_attempts"); db.execute("DELETE FROM users")
os.environ.update(CC_ADMIN_EMAIL="standard@example.dk", CC_ADMIN_PASSWORD="standard-pass")
check("standardbruger: oprettes fra .env naar der ingen brugere er",
      main.seed_standard_user() == "oprettet" and main.user_count() == 1, main.user_count())
std = main.find_user("standard@example.dk")
check("standardbruger: koden fra .env virker",
      bool(std) and main.verify_password("standard-pass", std["password_hash"]), std and dict(std))
check("standardbruger: koden er hashet, ikke gemt i klartekst",
      bool(std) and std["password_hash"].startswith("pbkdf2_sha256$") and "standard-pass" not in std["password_hash"])
check("standardbruger: skal skiftes ved foerste login",
      bool(std) and std["must_change_password"] == 1, std and dict(std))
sd = TestClient(main.app)
check("standardbruger: login virker med det samme (uden /setup)",
      sd.post("/login", data={"email": "standard@example.dk", "password": "standard-pass"},
              follow_redirects=False).status_code == 303)
check("standardbruger: /setup er lukket for anonyme, naar brugeren findes",
      TestClient(main.app).get("/setup", follow_redirects=False).status_code == 303)
# --- v7.18.1: .env-koden og kontoen kan loebe fra hinanden ---
os.environ["CC_ADMIN_PASSWORD"] = "gammel-kode-1"
stale = main.env_password_mismatch()
check("advarsel: foraeldet .env-kode giver en advarsel", stale.startswith("CC_ADMIN_PASSWORD"), stale)
check("advarsel: teksten naevner kontoen, ikke koderne",
      "standard@example.dk" in stale and "gammel-kode-1" not in stale and "standard-pass" not in stale)
# Baren har sin egen klasse - alarmteksten paa samme side indeholder de samme ord.
check("advarsel: dashboardet viser baren", "border-red-500/40" in sd.get("/").text)
main.warn_stale_env_password()
with main.get_db() as db:
    env_warned = db.execute("SELECT COUNT(*) FROM alarms WHERE message LIKE '%CC_ADMIN_PASSWORD i .env%'"
                            ).fetchone()[0]
check("advarsel: opstarten laegger den i Alarmer", env_warned >= 1, env_warned)
os.environ["CC_ADMIN_PASSWORD"] = "standard-pass"
check("advarsel: ingen advarsel naar .env-koden passer", main.env_password_mismatch() == "",
      main.env_password_mismatch())
check("advarsel: baren forsvinder naar koden passer", "border-red-500/40" not in sd.get("/").text)
# --- v7.18.2: .env-linjen ryddes, naar standardbrugeren selv skifter kode ---
_envdir = tempfile.mkdtemp()
_envfile = os.path.join(_envdir, ".env")
with io.open(_envfile, "w", encoding="utf-8") as f:
    f.write("# test\nCC_HOST=127.0.0.1\nCC_ADMIN_EMAIL=standard@example.dk\n"
            "CC_ADMIN_PASSWORD=standard-pass\nCC_PORT=8000\n")
_real_env_path = main.ENV_PATH
main.ENV_PATH = _envfile


def _env_text():
    return io.open(_envfile, encoding="utf-8").read()


check("ryd .env: en anden brugers kodeskift roerer ikke filen",
      main.clear_env_admin_password("fremmed@example.dk") == "ikke-standardbruger"
      and "CC_ADMIN_PASSWORD=standard-pass" in _env_text())
check("ryd .env: en kode der stadig passer lades i fred",
      main.clear_env_admin_password("standard@example.dk") == "passer-endnu"
      and "CC_ADMIN_PASSWORD=standard-pass" in _env_text())
sd.post("/users/password", data={"current": "standard-pass", "new": "nyt-pass-2", "confirm": "nyt-pass-2"})
_after = _env_text()
check("ryd .env: kodeskiftet toemmer linjen", "CC_ADMIN_PASSWORD=\n" in _after, _after)
check("ryd .env: kommentarer og andre noegler staar urort",
      "# test" in _after and "CC_HOST=127.0.0.1" in _after and "CC_PORT=8000" in _after)
check("ryd .env: hverken den gamle eller den nye kode staar i filen",
      "standard-pass" not in _after and "nyt-pass-2" not in _after)
check("ryd .env: advarslen forsvinder med linjen", main.env_password_mismatch() == "",
      main.env_password_mismatch())
check("ryd .env: baren er væk efter kodeskiftet", "border-red-500/40" not in sd.get("/").text)
# --- v7.20.0: hele .env-forloebet er eet nyhedspunkt, ikke fire ---
check("release: toppunktet i NEWEST er APP_VERSION", main.NEWEST[0][0] == main.APP_VERSION, main.NEWEST[0])
_env_points = [(v, t) for v, t in main.NEWEST if ".env" in t]
check("release: kun eet .env-nedslag tilbage", len(_env_points) == 1, _env_points)
_env_text = _env_points[0][1] if _env_points else ""
check("release: det samlede punkt naevner alle fire trin",
      all(w in _env_text for w in ("deployment", "foraeldet", "rydder linjen selv", "dashboardet")), _env_text)
check("release: versionen i banner og nyheder stemmer",
      main.APP_VERSION in "\n".join(main.startup_banner())
      and all(f"nyhed {v}" in "\n".join(main.startup_banner()) for v, _ in main.NEWEST[:3]))
# Login-siden viser kun det nyeste punkt, saa den skal vise 7.23.0-linjen - .env-punktet er daekket ovenfor.
_login = TestClient(main.app).get("/login")
check("release: login-siden viser det nyeste punkt",
      main.NEWEST[0][0] in _login.text and main.NEWEST[0][1][:40] in _login.text, _login.status_code)
# --- v7.19.2: dashboardet viser, hvornaar og af hvem linjen blev ryddet ---
_notice = main.env_password_notice()
_when = main.danish_time(main.env_password_cleared().get("at", ""))
check("visning: dashboardet ved hvem der ryddede og hvornaar",
      _notice.get("state") == "tom" and "blev fjernet fra .env" in _notice.get("text", "")
      and "standard@example.dk" in _notice["text"] and bool(_when) and _when in _notice["text"],
      _notice)
check("visning: teksten naevner ingen koder",
      "standard-pass" not in _notice["text"] and "nyt-pass-2" not in _notice["text"], _notice["text"])
check("visning: baren staar i dashboardet", "border-sky-500/40" in sd.get("/").text)
check("visning: dansk tidsformat",
      main.danish_time("2026-11-05T16:12:33") == "5. november 2026 kl. 16:12",
      main.danish_time("2026-11-05T16:12:33"))
check("visning: skaev tidsvaerdi giver ingen tekst",
      main.danish_time("i gaar") == "" and main.danish_time("") == "")
# Linjen sat tilbage: baren maa ikke paastaa, at den stadig er væk.
os.environ["CC_ADMIN_PASSWORD"] = "nyt-pass-2"
with io.open(_envfile, "w", encoding="utf-8") as f:
    f.write("# test\nCC_HOST=127.0.0.1\nCC_ADMIN_EMAIL=standard@example.dk\n"
            "CC_ADMIN_PASSWORD=nyt-pass-2\nCC_PORT=8000\n")
_back = main.env_password_notice()
check("visning: en linje der er sat tilbage bliver sagt hoejt",
      _back.get("state") == "sat" and "står i .env igen" in _back.get("text", "")
      and "standard@example.dk" in _back["text"], _back)
check("visning: baren bliver ved med at vaere synlig", "border-sky-500/40" in sd.get("/").text)
# Ingen rydning gemt (fx en ny installation) = ingen bar.
with main.get_db() as db:
    db.execute("DELETE FROM settings WHERE key=?", (main.ENV_CLEARED_KEY,))
check("visning: uden en gemt rydning er der ingen bar",
      main.env_password_notice() == {} and "border-sky-500/40" not in sd.get("/").text)
with main.get_db() as db:      # en i stykker skrevet raekke maa ikke vaelte dashboardet
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?,?)",
               (main.ENV_CLEARED_KEY, "{ikke-json"))
check("visning: en i stykker skrevet raekke giver ingen bar", main.env_password_notice() == {})
# En fejl under skrivningen maa ikke vaelte skiftet: en mappe paa .env-stien giver en alarm i stedet.
os.environ["CC_ADMIN_PASSWORD"] = "gammel-kode-2"
main.ENV_PATH = _envdir
check("ryd .env: fejl giver status i stedet for en exception",
      main.clear_env_admin_password("standard@example.dk").startswith("fejl:"))
with main.get_db() as db:
    _env_failed = db.execute("SELECT COUNT(*) FROM alarms WHERE message LIKE "
                             "'%kunne ikke fjernes fra .env%'").fetchone()[0]
check("ryd .env: fejlen bliver en advarsel i Alarmer", _env_failed >= 1, _env_failed)
main.ENV_PATH = _real_env_path
shutil.rmtree(_envdir, ignore_errors=True)
os.environ["CC_ADMIN_PASSWORD"] = "andet-pass-1"
check("standardbruger: en rettet .env-kode roerer ikke en konto i brug",
      main.seed_standard_user() == "findes"
      and main.verify_password("nyt-pass-2", main.find_user("standard@example.dk")["password_hash"])
      and not main.verify_password("andet-pass-1", main.find_user("standard@example.dk")["password_hash"])
      and main.user_count() == 1)
os.environ.update(CC_ADMIN_EMAIL="", CC_ADMIN_PASSWORD="")
check("standardbruger: uden linjer i .env sker der intet (setup bruges)",
      main.seed_standard_user() == "mangler" and main.user_count() == 1)
with main.get_db() as db:
    db.execute("DELETE FROM users")
os.environ.update(CC_ADMIN_EMAIL="ikke-en-mail", CC_ADMIN_PASSWORD="kort-kode")
broken = main.seed_standard_user()
with main.get_db() as db:
    warned = db.execute("SELECT COUNT(*) FROM alarms WHERE message LIKE '%Standardbrugeren i .env blev afvist%'").fetchone()[0]
check("standardbruger: ugyldig .env-linje giver ingen konto, men en alarm",
      broken.startswith("fejl:") and main.user_count() == 0 and warned >= 1, (broken, warned))
os.environ.update(CC_ADMIN_EMAIL="", CC_ADMIN_PASSWORD="")

# ---------- AI via OpenRouter (v7.25.0) ----------
class _FakeAIResp:
    def __init__(self, status, payload):
        self.status_code, self._payload = status, payload
    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload
    def raise_for_status(self):
        if self.status_code >= 400:
            raise main.requests.HTTPError(f"HTTP {self.status_code}")

_ai_calls = []
_ai_queue = []
_real_http_post = main.HTTP.post
def _fake_http_post(url, **kw):
    _ai_calls.append((url, kw))
    return _ai_queue.pop(0)
main.HTTP.post = _fake_http_post
_ai_before = (main.OPENROUTER_API_KEY, main.CC_PUBLIC_URL)
main.OPENROUTER_API_KEY, main.CC_PUBLIC_URL = "sk-or-test-hemmelig", "https://cc.example.dk"

_ai_queue.append(_FakeAIResp(200, {"choices": [{"message": {"content": "Hej fra OpenRouter"}}]}))
_out = main.ai_chat("Sig hej", max_tokens=42, timeout=7)
_url, _kw = _ai_calls[-1]
check("openrouter: svaret laeses fra choices", _out == "Hej fra OpenRouter", _out)
check("openrouter: kaldet gaar til /api/v1/chat/completions",
      _url == "https://openrouter.ai/api/v1/chat/completions", _url)
check("openrouter: Bearer-noegle, X-Title og HTTP-Referer sendes",
      _kw["headers"]["Authorization"] == "Bearer sk-or-test-hemmelig"
      and _kw["headers"]["X-Title"] == "Command Center"
      and _kw["headers"]["HTTP-Referer"] == "https://cc.example.dk", _kw["headers"])
check("openrouter: model, max_tokens og timeout sendes videre",
      _kw["json"]["model"] == main.AI_MODEL and _kw["json"]["max_tokens"] == 42 and _kw["timeout"] == 7,
      _kw["json"])
check("openrouter: AI-budgettet taeller openrouter.ai (ikke aimlapi.com)",
      main.budget_service("https://openrouter.ai/api/v1/chat/completions") == "ai"
      and main.budget_service("https://api.aimlapi.com/v1/chat/completions") == "", main.API_BUDGETS["ai"])

def _ai_error(resp):
    _ai_queue.append(resp)
    try:
        main.ai_chat("x")
    except Exception as e:  # noqa: BLE001
        return e
    return None

_e = _ai_error(_FakeAIResp(200, {"error": {"code": 502, "message": "Provider returned error"}}))
check("openrouter: error-objekt i et 200-svar bliver en AIError med beskeden",
      isinstance(_e, main.AIError) and "Provider returned error" in str(_e), repr(_e))
_e = _ai_error(_FakeAIResp(401, {"error": {"message": "No auth credentials found"}}))
check("openrouter: 401 giver en forstaaelig fejl uden noeglen",
      isinstance(_e, main.AIError) and "401" in str(_e) and "sk-or-test" not in str(_e), repr(_e))
_e = _ai_error(_FakeAIResp(200, {"choices": []}))
check("openrouter: tomt choices giver AIError (ikke IndexError)", isinstance(_e, main.AIError), repr(_e))
_e = _ai_error(_FakeAIResp(200, {"choices": [{"message": {"content": ""}}]}))
check("openrouter: tom besked giver AIError", isinstance(_e, main.AIError), repr(_e))
_e = _ai_error(_FakeAIResp(502, ValueError("ikke json")))
check("openrouter: HTML-fejlside (ikke JSON) giver HTTPError", isinstance(_e, main.requests.HTTPError), repr(_e))
check("openrouter: AIError fanges af de eksisterende RequestException-grene",
      issubclass(main.AIError, main.requests.RequestException))

main.CC_PUBLIC_URL = ""
_ai_queue.append(_FakeAIResp(200, {"choices": [{"message": {"content": "ok"}}]}))
main.ai_chat("x")
check("openrouter: ingen HTTP-Referer uden CC_PUBLIC_URL", "HTTP-Referer" not in _ai_calls[-1][1]["headers"])

_legacy_before = main.LEGACY_AIMLAPI_KEY_SET
main.LEGACY_AIMLAPI_KEY_SET, main.OPENROUTER_API_KEY = True, ""
_legacy_msg = main.warn_legacy_aimlapi()
with main.get_db() as db:
    _legacy_alarm = db.execute("SELECT COUNT(*) FROM alarms WHERE message LIKE '%AIMLAPI_KEY bruges ikke%'").fetchone()[0]
check("openrouter: kun AIMLAPI_KEY i .env giver advarsel + alarm",
      "OPENROUTER_API_KEY" in _legacy_msg and _legacy_alarm >= 1, (_legacy_msg, _legacy_alarm))
main.OPENROUTER_API_KEY = "sk-or-test-hemmelig"
check("openrouter: ingen advarsel naar OPENROUTER_API_KEY er sat", main.warn_legacy_aimlapi() == "")
main.LEGACY_AIMLAPI_KEY_SET = _legacy_before
check("openrouter: ingen aimlapi-adresser tilbage i koden",
      "aimlapi.com" not in open(os.path.join(ROOT, "app", "main.py"), encoding="utf-8").read())

main.HTTP.post = _real_http_post
main.OPENROUTER_API_KEY, main.CC_PUBLIC_URL = _ai_before

srv.shutdown()
shutil.rmtree(os.path.join(ROOT, "app", "data"), ignore_errors=True)
print("ALL PASS" if not FAILED else f"{len(FAILED)} FAILED")
sys.exit(1 if FAILED else 0)
