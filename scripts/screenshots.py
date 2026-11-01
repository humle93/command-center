#!/usr/bin/env python3
"""Tager screenshots af login-siden og alle faner i dashboardet.

    python3 scripts/screenshots.py                    # app paa http://127.0.0.1:8000
    python3 scripts/screenshots.py --base http://127.0.0.1:8099 --user demo --password 'xxx'
    python3 scripts/screenshots.py --only cockpit,alarms,notes
    python3 scripts/screenshots.py --viewport          # kun det synlige omraade

Billederne skrives til docs/img/ som cc-login.png og cc-<fane>.png.

Krav (kun for dette script - appen selv bruger det ikke):
    pip install playwright && python3 -m playwright install chromium
"""
from __future__ import annotations

import argparse
import os
import sys

# (Alpine-fane, filnavn uden .png) - holdes i takt med nav-knapperne i dashboard.html
TABS = [
    ("cockpit", "cc-cockpit"),
    ("seo", "cc-seo"),
    ("keywords", "cc-keywords"),
    ("articles", "cc-articles"),
    ("links", "cc-links"),
    ("spy", "cc-spy"),
    ("social", "cc-social"),
    ("monitors", "cc-monitors"),
    ("ai", "cc-ai"),
    ("pro", "cc-pro"),
    ("moduler", "cc-moduler"),
    ("brugere", "cc-brugere"),
    ("alarms", "cc-alarms"),
    ("notes", "cc-notes"),
]

SET_TAB_JS = """(key) => {
  const el = document.querySelector('[x-data]');
  if (!el || !window.Alpine) return false;
  window.Alpine.$data(el).tab = key;
  return true;
}"""

GET_TAB_JS = """() => {
  const el = document.querySelector('[x-data]');
  return el && window.Alpine ? window.Alpine.$data(el).tab : null;
}"""


class SetupError(Exception):
    """Fejl der skal vises som en kort besked, ikke en traceback."""


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Screenshots af login + alle dashboard-faner.")
    p.add_argument("--base", default=os.environ.get("CC_BASE", "http://127.0.0.1:8000"),
                   help="Appens adresse (default: %(default)s)")
    p.add_argument("--user", default=os.environ.get("CC_USER", ""), help="Brugernavn")
    p.add_argument("--password", default=os.environ.get("CC_PASSWORD", ""), help="Adgangskode")
    p.add_argument("--out", default="docs/img", help="Mappe til billederne (default: %(default)s)")
    p.add_argument("--width", type=int, default=1440, help="Vinduesbredde (default: %(default)s)")
    p.add_argument("--height", type=int, default=950, help="Vindueshoejde (default: %(default)s)")
    p.add_argument("--only", default="", help="Kommasepareret liste af faner, fx 'cockpit,seo'")
    p.add_argument("--viewport", action="store_true", help="Tag kun det synlige omraade")
    p.add_argument("--settle-ms", type=int, default=1200,
                   help="Pause efter faneskift, saa grafer kan naa at tegne (default: %(default)s)")
    p.add_argument("--timeout-ms", type=int, default=30000,
                   help="Timeout pr. handling (default: %(default)s)")
    p.add_argument("--skip-login", action="store_true", help="Spring login-siden over")
    return p.parse_args()


def shot(page, path: str, full_page: bool, written: list) -> None:
    try:
        page.screenshot(path=path, full_page=full_page)
    except Exception:
        # Meget hoeje sider kan ikke tages i fuld hoejde - fald tilbage til viewport
        page.screenshot(path=path, full_page=False)
    written.append((os.path.basename(path), os.path.getsize(path)))


def capture(pw, args, tabs, out_dir, written, problems) -> None:
    base = args.base.rstrip("/")
    try:
        browser = pw.chromium.launch(args=["--no-sandbox", "--disable-dev-shm-usage"])
    except Exception as exc:
        raise SetupError("Kunne ikke starte Chromium (%s). Kør: python3 -m playwright install "
                         "--with-deps chromium" % str(exc).splitlines()[0])

    try:
        context = browser.new_context(
            viewport={"width": args.width, "height": args.height},
            locale="da-DK",
            timezone_id="Europe/Copenhagen",
        )
        context.set_default_timeout(args.timeout_ms)
        page = context.new_page()

        if not args.skip_login:
            page.goto(base + "/login", wait_until="domcontentloaded")
            if "/setup" in page.url:
                raise SetupError("Appen har ingen brugere endnu. Opret brugeren i browseren foerst (%s/setup)." % base)
            path = os.path.join(out_dir, "cc-login.png")
            shot(page, path, not args.viewport, written)
            print("  %-15s -> %s" % ("login", path))

        if not tabs:
            return

        # Session via API (samme cookie-jar), saa vi ikke afhaenger af formular-submit
        resp = context.request.post(base + "/login",
                                    form={"username": args.user, "password": args.password})
        if resp.status >= 400:
            raise SetupError("Login som '%s' fejlede (HTTP %d)." % (args.user, resp.status))

        page.goto(base + "/", wait_until="domcontentloaded")
        if "/login" in page.url or "/setup" in page.url:
            raise SetupError("Login lykkedes ikke - appen sendte os til %s" % page.url.replace(base, ""))
        page.wait_for_selector("nav button", timeout=args.timeout_ms)
        page.wait_for_function("() => !!window.Alpine", timeout=args.timeout_ms)
        page.wait_for_timeout(args.settle_ms)

        for key, name in tabs:
            if not page.evaluate(SET_TAB_JS, key):
                problems.append("%s: kunne ikke skifte fane" % key)
                continue
            page.wait_for_timeout(args.settle_ms)
            current = page.evaluate(GET_TAB_JS)
            if current != key:
                problems.append("%s: fanen blev '%s' i stedet" % (key, current))
                continue
            path = os.path.join(out_dir, name + ".png")
            shot(page, path, not args.viewport, written)
            print("  %-15s -> %s" % (key, path))
    finally:
        browser.close()


def main() -> int:
    args = parse_args()

    if not args.user or not args.password:
        print("FEJL: Angiv --user og --password (eller CC_USER/CC_PASSWORD); scriptet skal kunne logge ind.",
              file=sys.stderr)
        return 2

    wanted = [t.strip() for t in args.only.split(",") if t.strip()]
    unknown = sorted(set(wanted) - {t[0] for t in TABS})
    if unknown:
        print("FEJL: Ukendte faner: %s (gyldige: %s)"
              % (", ".join(unknown), ", ".join(t[0] for t in TABS)), file=sys.stderr)
        return 2
    tabs = [t for t in TABS if not wanted or t[0] in wanted]
    if not tabs and args.skip_login:
        print("FEJL: Intet at tage - --only matcher ingen faner.", file=sys.stderr)
        return 2

    try:
        from playwright.sync_api import Error as PlaywrightError
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("FEJL: Playwright mangler. Kør: pip install playwright && python3 -m playwright install chromium",
              file=sys.stderr)
        return 2

    out_dir = args.out
    os.makedirs(out_dir, exist_ok=True)
    written, problems = [], []

    try:
        with sync_playwright() as pw:
            capture(pw, args, tabs, out_dir, written, problems)
    except SetupError as exc:
        print("FEJL: %s" % exc, file=sys.stderr)
        return 1
    except PlaywrightError as exc:
        detail = str(exc).splitlines()[0]
        print("FEJL: Browseren stoppede under optagelsen: %s" % detail, file=sys.stderr)
        if written:
            print("%d billede(r) blev skrevet foer fejlen." % len(written), file=sys.stderr)
        if "has been closed" in detail and not os.environ.get("FONTCONFIG_FILE"):
            print("Tip: crasher browseren straks paa dashboardet (FATAL: SkFontMgr_FontConfigInterface),"
                  " mangler der fontconfig. Saet FONTCONFIG_FILE til en fonts.conf med mindst én font.",
                  file=sys.stderr)
        return 1

    print("\n%d billede(r) skrevet til %s" % (len(written), out_dir))
    if problems:
        print("Mislykkedes:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
