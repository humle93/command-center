#!/usr/bin/env python3
"""api_key.py - styrer MCP-noegler fra terminalen. Samme tabel og hash som fanen Brugere.

Brug:
    python3 scripts/api_key.py list
    python3 scripts/api_key.py create "Claude Desktop" [read|read,write]
    python3 scripts/api_key.py revoke <id>
    python3 scripts/api_key.py audit [antal]

Noeglen skrives kun ud ved oprettelse; i databasen ligger der en sha256-hash.
Klienten sender den som "Authorization: Bearer <noegle>" til /mcp.
Kraever: venv (./venv) - scriptet importerer app.main og skriver i den samme DB.
Sidst aendret: 4. november 2026
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from app import main  # noqa: E402

USAGE = ('Brug:\n'
         '  python3 scripts/api_key.py list\n'
         '  python3 scripts/api_key.py create "Navn" [read|read,write]\n'
         '  python3 scripts/api_key.py revoke <id>\n'
         '  python3 scripts/api_key.py audit [antal]')


def run() -> int:
    args = sys.argv[1:]
    if not args:
        print(USAGE)
        return 2
    cmd = args[0]
    if cmd == "list":
        rows = main.api_client_rows()
        if not rows:
            print("Ingen noegler endnu.")
            return 0
        for r in rows:
            state = "tilbagekaldt " + (r["revoked_at"] or "") if r["revoked_at"] else "aktiv"
            print(f'{r["id"]:>3}  {r["name"][:28]:<28} …{r["key_hint"] or "????"}  {r["scopes"]:<11} '
                  f'{state:<21} sidst brugt: {r["last_used_at"] or "-"}')
        return 0
    if cmd == "create":
        if len(args) < 2:
            print(USAGE)
            return 2
        name = args[1]
        scopes = args[2] if len(args) > 2 else "read"
        try:
            client_id, key = main.create_api_client(name, scopes)
        except ValueError as e:
            print(f"Kunne ikke oprette noeglen: {e}")
            return 1
        print(f"Noegle #{client_id} oprettet til '{name}' med scopes {main.normalize_scopes(scopes)}.")
        print("Den vises kun nu - gem den et sikkert sted:")
        print(key)
        return 0
    if cmd == "revoke":
        if len(args) < 2 or not args[1].isdigit():
            print(USAGE)
            return 2
        main.revoke_api_client(int(args[1]))
        print(f"Noegle #{args[1]} er tilbagekaldt.")
        return 0
    if cmd == "audit":
        limit = int(args[1]) if len(args) > 1 and args[1].isdigit() else 20
        rows = main.api_audit_rows(limit)
        if not rows:
            print("Ingen MCP-kald endnu.")
            return 0
        for r in rows:
            state = "ok " if r["ok"] else "fejl"
            detail = f' - {r["detail"]}' if r["detail"] else ""
            print(f'{(r["created_at"] or "")[0:19]:<19} {state}  {(r["client"] or "ukendt")[:22]:<22} '
                  f'{r["tool"] or r["method"]:<16} {r["duration_ms"] or 0:>5} ms{detail}')
        return 0
    print(USAGE)
    return 2


if __name__ == "__main__":
    sys.exit(run())
