#!/usr/bin/env python3
"""stdio <-> Streamable HTTP-bro til Steamgears.eu's MCP-server.

Freebuff's MCP-klienter taler JSON-RPC over stdio, mens Steamgears-serveren
taler Streamable HTTP med et OAuth-bearer-token. Broen videresender beskeder
begge veje, saetter token'et fra .mcp/steamgears-token.json paa (lavet af
scripts/mcp_login.py) og fornyer det via refresh-token, hvis serveren svarer 401.

Startes automatisk af .agents/mcp.json - koer ikke scriptet i haanden.
Ingen hemmeligheder ligger i .agents/mcp.json; token'et bliver i .mcp/.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

import mcp_login as ml

ENDPOINT = os.environ.get("STEAMGEARS_MCP_ENDPOINT", ml.MCP_ENDPOINT)
OAUTH_BASE = os.environ.get("STEAMGEARS_MCP_BASE", ml.MCP_BASE)
TOKEN_FILE = os.environ.get("STEAMGEARS_TOKEN_FILE", ml.TOKEN_FILE)
CLIENT_FILE = os.environ.get("STEAMGEARS_CLIENT_FILE", ml.CLIENT_FILE)
PROTOCOL = os.environ.get("STEAMGEARS_MCP_PROTOCOL", ml.PROTOCOL)
TIMEOUT = float(os.environ.get("STEAMGEARS_MCP_TIMEOUT", "120"))

_SESSION = {"id": None}


def log(message):
    sys.stderr.write("[steamgears-mcp] %s\n" % message)
    sys.stderr.flush()


def write_token(payload):
    expires_in = payload.get("expires_in")
    token = {
        "access_token": payload["access_token"],
        "refresh_token": payload.get("refresh_token", ""),
        "token_type": payload.get("token_type", "Bearer"),
        "scope": payload.get("scope", ml.SCOPE),
        "obtained_at": int(time.time()),
        "expires_at": int(time.time()) + int(expires_in) if expires_in else None,
        "mcp_endpoint": ENDPOINT,
    }
    folder = os.path.dirname(TOKEN_FILE) or "."
    os.makedirs(folder, mode=0o700, exist_ok=True)
    with open(TOKEN_FILE, "w") as handle:
        json.dump(token, handle, indent=2)
    os.chmod(TOKEN_FILE, 0o600)
    return token


def refresh_token():
    """Fornyer access-token via gemt refresh-token. Returnerer ny token eller None."""
    saved = ml._load(TOKEN_FILE) or {}
    client = ml._load(CLIENT_FILE) or {}
    if not saved.get("refresh_token") or not client.get("client_id"):
        log("kan ikke forny: mangler refresh-token eller client-info")
        return None
    status, _, body = ml.http_call(OAUTH_BASE + "/oauth/token", {
        "grant_type": "refresh_token",
        "refresh_token": saved["refresh_token"],
        "client_id": client["client_id"],
        "resource": ENDPOINT,
    }, form=True)
    payload = ml._json(body) or {}
    if status != 200 or not payload.get("access_token"):
        log("fornyelse fejlede (HTTP %s): %s" % (status, body[:200]))
        return None
    return write_token(payload)


def access_token(force_refresh=False):
    token = ml._load(TOKEN_FILE)
    if not token or not token.get("access_token"):
        raise RuntimeError("Ingen token i %s - koer: python3 scripts/mcp_login.py" % TOKEN_FILE)
    expires_at = token.get("expires_at")
    if force_refresh or (expires_at and expires_at - time.time() < 60):
        fresh = refresh_token()
        if fresh:
            return fresh["access_token"]
        if force_refresh:
            raise RuntimeError("Token afvist og kunne ikke fornyes - koer login igen")
    return token["access_token"]


def post(payload):
    """Sender én JSON-RPC-besked. Returnerer (status, content-type, tekst)."""
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Mcp-Protocol-Version": PROTOCOL,
        "Authorization": "Bearer " + access_token(),
    }
    if _SESSION["id"]:
        headers["Mcp-Session-Id"] = _SESSION["id"]
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(), headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            _remember_session(response.getheader("Mcp-Session-Id"))
            return (response.status, (response.getheader("Content-Type") or "").lower(),
                    response.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as exc:
        _remember_session(exc.headers.get("Mcp-Session-Id") if exc.headers else None)
        return (exc.code, (exc.headers.get("Content-Type") or "").lower() if exc.headers else "",
                exc.read().decode("utf-8", "replace"))


def _remember_session(session_id):
    if session_id:
        _SESSION["id"] = session_id


def parse_messages(text):
    """Svar er enten ren JSON eller en SSE-stroem med data:-linjer."""
    stripped = text.strip()
    if not stripped:
        return []
    if stripped[0] in "{[":
        doc = ml._json(stripped)
        if isinstance(doc, list):
            return doc
        return [doc] if doc else []
    messages, buffer = [], []
    for line in stripped.splitlines():
        if line.startswith("data:"):
            buffer.append(line[5:].strip())
        elif not line.strip() and buffer:
            doc = ml._json("\n".join(buffer))
            buffer = []
            if doc:
                messages.append(doc)
    if buffer:
        doc = ml._json("\n".join(buffer))
        if doc:
            messages.append(doc)
    return messages


def rpc_error(payload, message):
    log(message)
    if "id" not in payload or payload.get("id") is None:
        return None
    return {"jsonrpc": "2.0", "id": payload["id"], "error": {"code": -32000, "message": message}}


def forward(payload):
    status, content_type, text = post(payload)
    if status == 401:
        log("401 fra serveren - fornyer token og proever igen")
        access_token(force_refresh=True)
        status, content_type, text = post(payload)
    if status >= 400:
        return [rpc_error(payload, "HTTP %s fra MCP-serveren: %s" % (status, text[:300]))]
    if status in (202, 204) or not text.strip():
        return []  # notifications har intet svar
    return parse_messages(text)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except ValueError:
            log("ugyldig JSON paa stdin - springer over")
            continue
        try:
            messages = forward(payload)
        except RuntimeError as exc:
            messages = [rpc_error(payload, str(exc))]
        except Exception as exc:  # netvaerksfejl maa ikke draebe broen
            messages = [rpc_error(payload, "bro-fejl: %s" % exc)]
        for message in messages:
            if message:
                sys.stdout.write(json.dumps(message) + "\n")
                sys.stdout.flush()


if __name__ == "__main__":
    main()
