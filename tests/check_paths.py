"""Fails if a form action, link or fetch() in the templates points at a route that does not exist.

Usage: python3 tests/check_paths.py   (from the repo root)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)
os.environ.setdefault("AIMLAPI_KEY", "")

from app import main  # noqa: E402

routes = {getattr(r, "path", "") for r in main.app.routes if getattr(r, "path", "")}


def known(url: str) -> bool:
    if not url or url.startswith(("http://", "https://", "mailto:", "#", "javascript:")):
        return True
    url = url.split("?")[0].split("#")[0]
    if not url.startswith("/"):
        return True      # relativ sti eller JS-udtryk
    if url in routes:
        return True
    if url.endswith("/") and any(p.startswith(url) for p in routes if "{" in p):
        return True      # fx fetch('/api/history/' + id)
    for path in routes:
        if "{" in path:
            pattern = "^" + re.sub(r"\{[^}]+\}", "[^/]+", path) + "$"
            if re.match(pattern, url):
                return True
    return False


missing = []
checked = 0
for name in ("dashboard.html", "login.html"):
    text = open(os.path.join("app", "templates", name)).read()
    candidates = re.findall(r'(?:action|href|formaction)="([^"]+)"', text)
    candidates += re.findall(r"fetch\('([^']+)'", text)
    candidates += re.findall(r'fetch\("([^"]+)"', text)
    for url in candidates:
        if "{{" in url or "{%" in url:
            continue     # dynamisk sti - kan ikke slaaes op statisk
        checked += 1
        if not known(url):
            missing.append((name, url))

if missing:
    for name, url in missing:
        print(f"FAIL {name}: {url} -> ingen route i main.py")
    sys.exit(1)

print(f"PASS alle {checked} formular-actions/links/fetch-stier findes ({len(routes)} routes)")
