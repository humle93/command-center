# Fake WordPress with the Steamgears Autopilot REST API (sgap/v1), for tests/ci_check.sh.
# Usage: python3 tests/fake_wp.py <state-file>   (state file holds: ok | failed2 | 404)
import json, base64, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
STATE = sys.argv[1]  # file: "ok" | "404" | "failed2"
drafts = []
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body):
        b = json.dumps(body).encode(); self.send_response(code); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(b)
    def auth_ok(self):
        return self.headers.get("Authorization") == "Basic " + base64.b64encode(b"admin:app pass").decode()
    def mode(self):
        return open(STATE).read().strip()
    def do_GET(self):
        if not self.auth_ok(): return self.send(401, {"code": "rest_not_logged_in"})
        if self.mode() == "404": return self.send(404, {"code": "rest_no_route"})
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
        if self.path == "/wp-json/sgap/v1/drafts":
            drafts.append({"id": len(drafts) + 1, "status": "pending", **data})
            open(STATE + ".last", "w").write(json.dumps(data))
            return self.send(201, {"id": len(drafts)})
        self.send(404, {})
HTTPServer(("127.0.0.1", 8770), H).serve_forever()
