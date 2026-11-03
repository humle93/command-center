#!/usr/bin/env python3
"""Inviterer en bruger paa mail - samme vej som fanen Brugere, men fra terminalen.

Brug: python3 scripts/invite.py navn@domaene.dk [adresse-i-mailen]
Kraever SMTP_HOST + SMTP_FROM i .env (se .env.example). Brugeren oprettes foerst, naar
mailen er sendt, og skal skifte den midlertidige adgangskode ved foerste login.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from app import main  # noqa: E402


def run() -> int:
    if len(sys.argv) < 2:
        print("Brug: python3 scripts/invite.py navn@domaene.dk [adresse-i-mailen]")
        return 2
    email = sys.argv[1]
    base_url = sys.argv[2] if len(sys.argv) > 2 else main.CC_PUBLIC_URL
    ok, err = main.invite_user(email, base_url)
    if ok:
        print(f"Invitation sendt til {main.normalize_email(email)} - brugeren skal skifte kode ved foerste login.")
        return 0
    print(f"Kunne ikke invitere: {err}")
    return 1


if __name__ == "__main__":
    sys.exit(run())
