#!/usr/bin/env python3
"""Opretter en bruger direkte i databasen - samme tabel og hash som fanen Brugere.

Brug:
    python3 scripts/user_create.py cpaleadsis@gmail.com --username humle91
    python3 scripts/user_create.py navn@domaene.dk --password 'en-lang-kode'
    python3 scripts/user_create.py navn@domaene.dk --username humle91 --must-change

Uden --password spoerges der (skjult input, to gange). Koden skal vaere mindst 8 tegn - samme regel
som i UI'et (MIN_PASSWORD_LEN). Brugeren kan logge ind med e-mailen eller med brugernavnet, og
adressen i svaret kommer fra CC_PUBLIC_URL i .env (ellers den lokale adresse).

Noeglen gemmes kun som PBKDF2-hash med salt pr. bruger - derfor staar koden aldrig i databasen.
"""
import argparse
import getpass
import os
import re
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from app import main  # noqa: E402

USERNAME_RE = re.compile(r"[A-Za-z0-9._-]{2,32}")


def parse(argv):
    p = argparse.ArgumentParser(
        description="Opret en bruger i Command Center fra terminalen.",
        epilog="Eksempel: python3 scripts/user_create.py cpaleadsis@gmail.com --username humle91")
    p.add_argument("email", help="brugerens e-mail (login-id)")
    p.add_argument("--username", default="", help="kort brugernavn, fx humle91 (kan også bruges til login)")
    p.add_argument("--password", default="", help="adgangskode; udelades den, spørges der (skjult input)")
    p.add_argument("--must-change", action="store_true",
                   help="brugeren skal skifte koden ved første login (som en invitation)")
    return p.parse_args(argv)


def read_password(given: str) -> str:
    """Koden fra --password, ellers to gange skjult input - saa en tastefejl ikke laaser kontoen."""
    if given:
        return given
    first = getpass.getpass("Adgangskode (min. 8 tegn): ")
    second = getpass.getpass("Gentag adgangskode: ")
    if first != second:
        raise ValueError("De to adgangskoder er ikke ens")
    return first


def run(argv=None) -> int:
    args = parse(argv if argv is not None else sys.argv[1:])
    username = (args.username or "").strip()
    if username and not USERNAME_RE.fullmatch(username):
        print("❌ Brugernavn: brug 2-32 tegn, kun bogstaver, tal, punktum, bindestreg og underscore")
        return 2
    try:
        password = read_password(args.password)
        user_id = main.create_user(args.email, password, must_change=args.must_change, username=username)
    except ValueError as e:
        print(f"❌ {e}")
        return 2
    except sqlite3.IntegrityError:
        print(f"❌ Der findes allerede en bruger med {main.normalize_email(args.email)}"
              + (f" eller brugernavnet {username}" if username else ""))
        return 1

    base = (main.CC_PUBLIC_URL or "http://127.0.0.1:8000").rstrip("/")
    print(f"✅ Bruger oprettet: id {user_id}, {main.normalize_email(args.email)}"
          + (f", brugernavn {username}" if username else ""))
    print(f"   login:       {base}/login   (e-mail eller brugernavn + adgangskode)")
    if args.must_change:
        print("   kode:        brugeren skal skifte den ved første login")
    print("   koden ligger kun som PBKDF2-hash i databasen - gem den nu, den kan ikke læses ud igen")
    return 0


if __name__ == "__main__":
    sys.exit(run())
