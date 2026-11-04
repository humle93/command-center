#!/usr/bin/env python3
"""invite.py - inviterer en bruger paa mail. Samme vej som fanen Brugere, men fra terminalen.

Brug:
    python3 scripts/invite.py navn@domaene.dk [adresse-i-mailen] [--print]

Uden --print kraever scriptet SMTP_HOST + SMTP_FROM i .env, og brugeren oprettes foerst, naar
mailen er sendt. Med --print oprettes brugeren med det samme, og den faerdige mail (med den
midlertidige adgangskode) skrives til skaermen, saa den kan sendes fra en anden mailkonto.
Brugeren skal skifte koden ved foerste login.
Kraever: venv (./venv) og SMTP_HOST + SMTP_FROM i .env - eller --print, saa intet sendes.
Sidst aendret: 4. november 2026
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from app import main  # noqa: E402

USAGE = "Brug: python3 scripts/invite.py navn@domaene.dk [adresse-i-mailen] [--print]"


def run() -> int:
    print_mode = "--print" in sys.argv[1:]
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(USAGE)
        return 2
    email = args[0]
    base_url = args[1] if len(args) > 1 else main.CC_PUBLIC_URL

    held = []  # (emne, tekst) - printes foerst naar brugeren er oprettet

    def hold(subject, body):
        held.append((subject, body))
        return True, ""

    ok, err = main.invite_user(email, base_url, deliver=hold if print_mode else None)
    if not ok:
        print(f"Kunne ikke invitere: {err}")
        return 1
    if print_mode:
        print(f"Invitation klar til {main.normalize_email(email)} - ingen mail sendt herfra.")
        print("Send teksten nedenfor fra din egen mailkonto:\n")
        for subject, body in held:
            print(f"Emne: {subject}")
            print("-" * 60)
            print(body)
            print("-" * 60)
        return 0
    print(f"Invitation sendt til {main.normalize_email(email)} - brugeren skal skifte kode ved foerste login.")
    return 0


if __name__ == "__main__":
    sys.exit(run())
