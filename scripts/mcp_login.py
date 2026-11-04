#!/usr/bin/env python3
"""Login til Steamgears.eu's MCP-server (OAuth 2.1 + PKCE).

MCP-serveren bag https://steamgears.eu/wp-json/mcp/v1 kraever et Bearer-token fra
WordPress-login. Dette script klarer hele flowet: dynamisk client-registrering,
PKCE, lokal callback, token-udveksling og gemmer token'et i
.mcp/steamgears-token.json (git-ignoreret, chmod 600).

Koer det paa din egen maskine - ikke paa en server/Cloud-miljoe: Simply.com's
firewall blokerer wp-login.php for datacenter-IP'er (HTTP 454/455).

    python3 scripts/mcp_login.py            # login (aabner browser-URL)
    python3 scripts/mcp_login.py --manual   # login naar callback-porten er optaget
    python3 scripts/mcp_login.py --status   # er der et gyldigt token?
    python3 scripts/mcp_login.py --refresh  # forny token uden browser
    python3 scripts/mcp_login.py --verify   # initialize + tools/list mod serveren

Kun standardbibliotek - ingen pip-pakker noedvendige.
"""

import argparse
import base64
import hashlib
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MCP_BASE = os.environ.get("STEAMGEARS_MCP_BASE", "https://steamgears.eu/wp-json/mcp/v1").rstrip("/")
MCP_ENDPOINT = os.environ.get("STEAMGEARS_MCP_ENDPOINT", MCP_BASE + "/http")
SCOPE = os.environ.get("STEAMGEARS_MCP_SCOPE", "mcp")
PROTOCOL = os.environ.get("STEAMGEARS_MCP_PROTOCOL", "2025-06-18")
DEFAULT_PORT = int(os.environ.get("STEAMGEARS_MCP_PORT", "8765"))
TIMEOUT = 30

_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_DIR = os.path.join(_BASE_DIR, ".mcp")
TOKEN_FILE = os.path.join(STATE_DIR, "steamgears-token.json")
CLIENT_FILE = os.path.join(STATE_DIR, "steamgears-client.json")


# --- HTTP-hjaelpere -------------------------------------------------------

def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def pkce_pair():
    """Returnerer (code_verifier, code_challenge) til S256."""
    verifier = _b64url(os.urandom(48))
    challenge = _b64url(hashlib.sha256(verifier.encode()).digest())
    return verifier, challenge


def http_call(url, payload=None, form=False, headers=None):
    """Returnerer (status, headers-dict, tekst). HTTP-fejl returneres, ikke kastet."""
    data = None
    hdrs = {"Accept": "application/json", "User-Agent": "command-center-mcp-login/1.0"}
    if payload is not None and form:
        data = urllib.parse.urlencode(payload).encode()
        hdrs["Content-Type"] = "application/x-www-form-urlencoded"
    elif payload is not None:
        data = json.dumps(payload).encode()
        hdrs["Content-Type"] = "application/json"
    hdrs.update(headers or {})
    req = urllib.request.Request(url, data=data, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read().decode("utf-8", "replace")


def _json(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def _save(path, data):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    with open(path, "w") as handle:
        json.dump(data, handle, indent=2)
    os.chmod(path, 0o600)


def _load(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path) as handle:
            return json.load(handle)
    except (ValueError, OSError):
        return None


# --- OAuth-flow -----------------------------------------------------------

def get_client(redirect_uri):
    """Genbrug gemt client_id, ellers registrer en ny public client (RFC 7591)."""
    saved = _load(CLIENT_FILE)
    if saved and saved.get("client_id") and saved.get("redirect_uri") == redirect_uri:
        return saved
    status, _, body = http_call(MCP_BASE + "/oauth/register", {
        "client_name": "Command Center MCP login",
        "redirect_uris": [redirect_uri],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none",
        "scope": SCOPE,
    })
    payload = _json(body) or {}
    if status not in (200, 201) or not payload.get("client_id"):
        raise SystemExit("Client-registrering fejlede (HTTP %s): %s" % (status, body[:300]))
    client = {"client_id": payload["client_id"], "redirect_uri": redirect_uri, "scope": SCOPE}
    _save(CLIENT_FILE, client)
    print("Registrerede ny MCP-client: %s" % client["client_id"])
    return client


def build_authorize_url(client_id, redirect_uri, challenge, state):
    query = {
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "scope": SCOPE,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "resource": MCP_ENDPOINT,
    }
    return MCP_BASE + "/oauth/authorize?" + urllib.parse.urlencode(query)


class _CallbackHandler(BaseHTTPRequestHandler):
    params = {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/callback":
            self.send_error(404)
            return
        _CallbackHandler.params = {k: v[0] for k, v in urllib.parse.parse_qs(parsed.query).items()}
        ok = "code" in _CallbackHandler.params
        text = "Login gennemfoert - luk vinduet og gaa tilbage til terminalen."
        if not ok:
            text = "Login fejlede: %s" % _CallbackHandler.params.get("error", "ukendt fejl")
        body = ("<!doctype html><meta charset='utf-8'><title>Steamgears MCP</title>"
                "<p style='font:16px system-ui;padding:2rem'>%s</p>" % text).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def wait_for_code(port, expected_state, url, timeout=300):
    server = ThreadingHTTPServer(("127.0.0.1", port), _CallbackHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print("\nAabn denne URL i din browser og log ind med din WordPress-konto:\n\n%s\n" % url)
    print("Venter paa callback paa http://127.0.0.1:%d/callback (max %d sek.) ..." % (port, timeout))
    try:
        deadline = time.time() + timeout
        while time.time() < deadline and not _CallbackHandler.params:
            time.sleep(0.3)
    finally:
        server.shutdown()
        server.server_close()
    return _check_callback(expected_state)


def manual_code(expected_state):
    raw = input("\nIndsæt hele callback-URL'en (eller kun code-vaerdien): ").strip()
    if not raw:
        raise SystemExit("Intet input.")
    if raw.startswith("http"):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(raw).query)
        _CallbackHandler.params = {k: v[0] for k, v in query.items()}
    else:
        _CallbackHandler.params = {"code": raw}
    return _check_callback(expected_state)


def _check_callback(expected_state):
    params = _CallbackHandler.params
    if not params:
        raise SystemExit("Timeout: ingen callback modtaget. Proev --manual.")
    if params.get("error"):
        raise SystemExit("Autorisation afvist: %s %s"
                         % (params.get("error"), params.get("error_description", "")))
    if expected_state and params.get("state") != expected_state:
        raise SystemExit("State matcher ikke - afbrudt (muligt CSRF).")
    if not params.get("code"):
        raise SystemExit("Callback uden code.")
    return params["code"]


def token_request(client, form):
    status, _, body = http_call(MCP_BASE + "/oauth/token", form, form=True)
    payload = _json(body) or {}
    if status != 200 or not payload.get("access_token"):
        raise SystemExit("Token-kald fejlede (HTTP %s): %s" % (status, body[:400]))
    return payload


def store_token(payload):
    expires_in = payload.get("expires_in")
    token = {
        "access_token": payload["access_token"],
        "refresh_token": payload.get("refresh_token", ""),
        "token_type": payload.get("token_type", "Bearer"),
        "scope": payload.get("scope", SCOPE),
        "obtained_at": int(time.time()),
        "expires_at": int(time.time()) + int(expires_in) if expires_in else None,
        "mcp_endpoint": MCP_ENDPOINT,
    }
    _save(TOKEN_FILE, token)
    return token


# --- MCP-kald -------------------------------------------------------------

def mcp_call(method, params, token, session_id=None):
    body = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params is not None:
        body["params"] = params
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": "Bearer " + token,
        "Mcp-Protocol-Version": PROTOCOL,
    }
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    req = urllib.request.Request(MCP_ENDPOINT, data=json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            text = resp.read().decode("utf-8", "replace")
            return resp.getheader("Mcp-Session-Id"), _parse_rpc(text)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise SystemExit("MCP-kald %s fejlede (HTTP %s): %s" % (method, exc.code, detail[:400]))


def _parse_rpc(text):
    """Svar kan vaere ren JSON eller SSE (data:-linjer)."""
    stripped = text.strip()
    if stripped.startswith("{"):
        return _json(stripped)
    for line in stripped.splitlines():
        if line.startswith("data:"):
            doc = _json(line[5:].strip())
            if doc:
                return doc
    return None


def verify(token):
    session_id, doc = mcp_call("initialize", {
        "protocolVersion": PROTOCOL,
        "capabilities": {},
        "clientInfo": {"name": "command-center-mcp-login", "version": "1.0"},
    }, token)
    result = (doc or {}).get("result") or {}
    info = result.get("serverInfo") or {}
    print("Forbundet til: %s %s (protokol %s)"
          % (info.get("name", "?"), info.get("version", ""), result.get("protocolVersion", "?")))
    _, tools_doc = mcp_call("tools/list", {}, token, session_id)
    tools = ((tools_doc or {}).get("result") or {}).get("tools") or []
    print("Vaerktoejer: %d" % len(tools))
    for tool in tools[:25]:
        print("  - %s" % tool.get("name"))


# --- Kommandoer -----------------------------------------------------------

def cmd_login(port, manual):
    redirect_uri = "http://127.0.0.1:%d/callback" % port
    client = get_client(redirect_uri)
    verifier, challenge = pkce_pair()
    state = _b64url(os.urandom(16))
    url = build_authorize_url(client["client_id"], redirect_uri, challenge, state)
    code = manual_code(state) if manual else wait_for_code(port, state, url)
    token = store_token(token_request(client, {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "client_id": client["client_id"],
        "code_verifier": verifier,
        "resource": MCP_ENDPOINT,
    }))
    print("\nToken gemt i %s" % os.path.relpath(TOKEN_FILE, _BASE_DIR))
    verify(token["access_token"])


def cmd_refresh():
    token = _load(TOKEN_FILE)
    client = _load(CLIENT_FILE)
    if not token or not token.get("refresh_token"):
        raise SystemExit("Ingen refresh-token - koer login igen.")
    if not client:
        raise SystemExit("Mangler client-info - koer login igen.")
    fresh = store_token(token_request(client, {
        "grant_type": "refresh_token",
        "refresh_token": token["refresh_token"],
        "client_id": client["client_id"],
        "resource": MCP_ENDPOINT,
    }))
    print("Token fornyet, gyldigt til %s" % _expiry_text(fresh))


def cmd_status():
    token = _load(TOKEN_FILE)
    if not token:
        print("Ikke logget ind: %s findes ikke. Koer: python3 scripts/mcp_login.py"
              % os.path.relpath(TOKEN_FILE, _BASE_DIR))
        return
    print("Token: %s..." % token["access_token"][:12])
    print("Udløber: %s" % _expiry_text(token))
    print("Endpoint: %s" % token.get("mcp_endpoint", MCP_ENDPOINT))


def cmd_verify():
    token = _load(TOKEN_FILE)
    if not token:
        raise SystemExit("Ikke logget ind - koer login foerst.")
    verify(token["access_token"])


def _expiry_text(token):
    expires_at = token.get("expires_at")
    if not expires_at:
        return "ukendt"
    left = int(expires_at - time.time())
    if left <= 0:
        return "udloebet (%s)" % time.strftime("%Y-%m-%d %H:%M", time.localtime(expires_at))
    return "%s (om %d min.)" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(expires_at)), left // 60)


def main():
    parser = argparse.ArgumentParser(description="Login til Steamgears.eu MCP (OAuth 2.1 + PKCE)")
    parser.add_argument("--manual", action="store_true", help="indsæt callback-URL manuelt")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="lokal callback-port (default %d)" % DEFAULT_PORT)
    parser.add_argument("--status", action="store_true", help="vis gemt token")
    parser.add_argument("--refresh", action="store_true", help="forny token")
    parser.add_argument("--verify", action="store_true", help="kald initialize + tools/list")
    args = parser.parse_args()
    if args.status:
        cmd_status()
    elif args.refresh:
        cmd_refresh()
    elif args.verify:
        cmd_verify()
    else:
        cmd_login(args.port, args.manual)


if __name__ == "__main__":
    main()
