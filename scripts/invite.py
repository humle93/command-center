#!/usr/bin/env python3
"""invite.py - inviterer en bruger paa mail. Samme vej som fanen Brugere, men fra terminalen.

Brug: python3 scripts/invite.py <e-mail> [--base-url <adresse-i-mailen>] [--print] [--force]

Argumenterne tjekkes, foer der oprettes noget: der skal vaere praecis én e-mailadresse (flere
kraever et kald hver), ukendte flag afvises, og en ekstra adresse til mailen skal vaere en
http(s)-URL. Ligner adressen det eksempel, der staar i dokumentationen (fx navn@domaene.dk),
stopper scriptet i stedet for at oprette en konto, ingen kan bruge - med --force oprettes den
alligevel.

Uden --print kraever scriptet SMTP_HOST + SMTP_FROM i .env, og brugeren oprettes foerst, naar
mailen er sendt. Med --print oprettes brugeren med det samme, og den faerdige mail (med den
midlertidige adgangskode) skrives til skaermen, saa den kan sendes fra en anden mailkonto.
Brugeren skal skifte koden ved foerste login.
Kraever: venv (./venv) og SMTP_HOST + SMTP_FROM i .env - eller --print, saa intet sendes.
Sidst aendret: 4. november 2026
"""
import os
import sys
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from app import main  # noqa: E402

USAGE = ("Brug: python3 scripts/invite.py <e-mail> [--base-url <adresse-i-mailen>] "
         "[--print] [--force]")

HINT_PRINT = ("--prnt", "--printt", "-print", "--prit", "--print-mode")


def looks_like_url(value: str) -> bool:
    """Er argumentet en adresse, der kan staa i mailen (http/https med et vaertnavn)?"""
    try:
        parsed = urlparse(value or "")
    except ValueError:
        return False
    return parsed.scheme in ("http", "https") and bool(parsed.netloc)


def parse_args(argv: list) -> tuple:
    """Returnerer (valg, fejl). valg er None naar der blev spurgt om --help."""
    email = None
    base_url = None
    print_mode = False
    force = False
    errors = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            return None, []
        elif arg == "--print":
            print_mode = True
        elif arg == "--force":
            force = True
        elif arg in ("--base-url", "--adresse"):
            i += 1
            if i >= len(argv):
                errors.append(f"{arg} mangler en adresse, fx {arg} https://cc.example.dk")
            elif base_url:
                errors.append("--base-url er angivet flere gange")
            elif not looks_like_url(argv[i]):
                errors.append(f"{arg} skal vaere en http(s)-adresse, ikke '{argv[i]}'")
            else:
                base_url = argv[i]
        elif arg.startswith("-"):
            hint = " - mente du --print?" if arg.lower() in HINT_PRINT else ""
            errors.append(f"ukendt flag '{arg}'{hint}")
        elif email is None:
            email = arg
        elif base_url is None and looks_like_url(arg):
            base_url = arg          # den gamle form: <e-mail> <adresse-i-mailen>
        elif "@" in arg:
            errors.append(f"'{arg}' er endnu en e-mailadresse - inviter én adresse ad gangen; "
                          "intet blev oprettet")
        else:
            errors.append(f"for mange argumenter: '{arg}' (en ekstra adresse skal vaere en "
                          "http(s)-URL, fx --base-url https://cc.example.dk)")
        i += 1
    if not errors and email is None:
        errors.append("e-mailadressen mangler")
    return {"email": email, "base_url": base_url, "print": print_mode, "force": force}, errors


def run() -> int:
    opts, errors = parse_args(sys.argv[1:])
    if opts is None:                                     # --help
        print(USAGE)
        return 0
    if errors:
        for err in errors:
            print(f"Fejl: {err}")
        print(USAGE)
        print("Intet blev oprettet.")
        return 2
    raw = opts["email"]
    try:
        email = main.normalize_email(raw)
    except ValueError:
        print(f"Fejl: '{raw}' er ikke en gyldig e-mailadresse (fx bruger@ditfirma.dk)")
        print(USAGE)
        print("Intet blev oprettet.")
        return 2
    hint = main.example_email_hint(email)   # samme regel som formularen i fanen Brugere
    if hint and not opts["force"]:
        print(f"Fejl: '{email}' ligner eksemplet fra dokumentationen ({hint}), og der kan ikke "
              "sendes post til den.")
        print("Skriv den rigtige adresse - eller tilfoej --force, hvis adressen nu er korrekt.")
        print("Intet blev oprettet.")
        return 2
    if hint:
        print(f"Bemærk: '{email}' ligner et eksempel ({hint}) - opretter alligevel pga. --force.")
    base_url = opts["base_url"] or main.CC_PUBLIC_URL

    held = []  # (emne, tekst) - printes foerst naar brugeren er oprettet

    def hold(subject, body):
        held.append((subject, body))
        return True, ""

    ok, err = main.invite_user(email, base_url, deliver=hold if opts["print"] else None,
                               allow_example=opts["force"])
    if not ok:
        print(f"Kunne ikke invitere: {err}")
        return 1
    if opts["print"]:
        print(f"Invitation klar til {email} - ingen mail sendt herfra.")
        print("Send teksten nedenfor fra din egen mailkonto:\n")
        for subject, body in held:
            print(f"Emne: {subject}")
            print("-" * 60)
            print(body)
            print("-" * 60)
        return 0
    print(f"Invitation sendt til {email} - brugeren skal skifte kode ved foerste login.")
    return 0


if __name__ == "__main__":
    sys.exit(run())
