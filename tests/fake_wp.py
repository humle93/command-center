# Fake WordPress with the Steamgears Autopilot REST API (sgap/v1), for tests/ci_check.sh.
# Usage: python3 tests/fake_wp.py <state-file>   (state file holds: ok | failed2 | 404 | old)
# old = a plugin without /snapshot (CC falls back to /stats + /drafts).
# Every request records its X-Command-Center header in <state-file>.header, and the last
# /snapshot call also writes it to <state-file>.cc (empty when missing).
import json, base64, os, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
STATE = sys.argv[1]  # file: "ok" | "404" | "failed2" | "old"
drafts = []
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body):
        b = json.dumps(body).encode(); self.send_response(code); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(b)
    def auth_ok(self):
        return self.headers.get("Authorization") == "Basic " + base64.b64encode(b"admin:app pass").decode()
    def mode(self):
        return open(STATE).read().strip()
    def note(self):
        open(STATE + ".header", "w").write(self.headers.get("X-Command-Center", ""))
    def do_GET(self):
        self.note()
        if self.path.startswith("/wp-cron.php"):
            open(STATE + ".cron", "a").write("ping\n")
            return self.send(200, {})
        if not self.auth_ok(): return self.send(401, {"code": "rest_not_logged_in"})
        if self.mode() == "404": return self.send(404, {"code": "rest_no_route"})
        if self.path.startswith("/wp-json/sgap/v1/snapshot"):
            if self.mode() == "old": return self.send(404, {"code": "rest_no_route"})
            # Headeren gemmes, saa CI kan se at CC markerer sig som Command Center.
            open(STATE + ".cc", "w").write(self.headers.get("X-Command-Center") or "")
            failed = 2 if self.mode() == "failed2" else 0
            queue = {"published": 3, "queued": 1, **({"failed": failed} if failed else {})}
            # WordPress' eget svar paa hvornaar CC sidst kaldte (SGAP_CC::status()).
            ts = int(time.time()) - 120
            return self.send(200, {"version": "7.33.0", "missing_tables": [],
                "status": {"autopilot": True, "full_auto": False, "sending_paused_because": None, "cron_lag_minutes": 45,
                           "last_self_check": {"at": "2026-11-05 06:00:00", "problems": ["The autopilot is off."] if failed else []},
                           "command_center": {
                               "state": "connected", "connected": True, "ts": ts, "age": 120, "minutes_ago": 2,
                               "last_seen": time.strftime("%Y-%m-%d %H:%M", time.localtime(ts)),
                               "version": "7.18.0", "last_route": "/sgap/v1/snapshot", "user": "admin"}},
                "counts": {"queue": queue, "drafts": {"pending": len([d for d in drafts if d["status"] == "pending"])}},
                "results": {"by_channel": [
                    {"channel": "facebook", "published": "3", "clicks": "12", "orders": "0", "revenue": "0"},
                    {"channel": "pinterest", "published": "0", "clicks": "0", "orders": "1", "revenue": "49.90"}]}})
        if self.path.startswith("/wp-json/sgap/v1/stats"):
            failed = 2 if self.mode() == "failed2" else 0
            return self.send(200, {"days": 30, "events": [
                {"channel": "facebook", "event_type": "publish", "count": "3", "value": "0.00"},
                {"channel": "facebook", "event_type": "click", "count": "12", "value": "0.00"},
                {"channel": "pinterest", "event_type": "order", "count": "1", "value": "49.90"}],
                "learning": [], "queue": [{"status": "published", "count": "3"}, {"status": "queued", "count": "1"}] + ([{"status": "failed", "count": str(failed)}] if failed else [])})
        if self.path.startswith("/wp-json/sgap/v1/drafts"):
            return self.send(200, [d for d in drafts if d["status"] == "pending"])
        self.send(404, {})
    def do_POST(self):
        if not self.auth_ok(): return self.send(401, {})
        n = int(self.headers.get("content-length", 0)); data = json.loads(self.rfile.read(n) or b"{}")
        if self.path == "/wp-json/sgap/v1/cc-link":
            open(STATE + ".cclink", "w").write(json.dumps(data))
            return self.send(200, {"ok": True, "linked": bool(data.get("secret")), "url": data.get("url")})
        if self.path == "/wp-json/sgap/v1/priorities":
            open(STATE + ".priorities", "w").write(json.dumps(data))
            items = data.get("items") or []
            return self.send(200, {"saved": len(items), "skipped": [], "status": {"active": len(items)}})
        if self.path == "/wp-json/sgap/v1/drafts":
            drafts.append({"id": len(drafts) + 1, "status": "pending", **data})
            open(STATE + ".last", "w").write(json.dumps(data))
            return self.send(201, {"id": len(drafts)})
        self.send(404, {})
HTTPServer(("127.0.0.1", 8770), H).serve_forever()
