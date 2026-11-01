---
name: command-center
description: Regler, kontrakter og verifikation for Command Center (FastAPI + SQLite SEO-dashboard) - brug den foer enhver aendring i app/, scripts/, templates eller docs, og naar du skal vide hvordan man tester, regenererer install.sh eller undgaar de kendte faldgruber.
license: MIT
metadata:
  category: project-conventions
  language: python
  framework: fastapi
---

# Command Center — projektkonventioner

Selvhostet SEO- og driftsdashboard: FastAPI + SQLite i `app/main.py` (~3.600 linjer), Jinja-skabeloner
i `app/templates/`, shell-scripts i `scripts/`, dansk dokumentation i `docs/`, tests i `tests/`, og
`install.sh` som selvstaendig installer med indlejrede kopier af projektets filer.

## De otte faste regler

1. **Dokumentation i samme commit.** Ændringer i `app/`, `scripts/`, `deploy/`, `requirements.txt`,
   `run.sh`, `run.bat`, `Dockerfile`, `docker-compose.yml` kræver at `README.md` eller `docs/` også
   røres. CI fejler ellers. `install.sh` er undtaget (genereret). `[skip docs]` i commit-beskeden er
   escape-hatchen til rene undtagelser.
2. **Ret aldrig `install.sh` direkte.** 17 heredocs med kopier; CI tjekker byte-paritet.
3. **Tests før commit.** `./venv/bin/python tests/test_v8_features.py` og
   `PATH="$PWD/venv/bin:$PATH" bash tests/ci_check.sh` skal begge ende med `ALL PASS`.
4. **Ingen secrets i repoet.** Nøgler i `.env` (gitignored) eller miljøvariabler.
5. **Dansk UI og dansk dokumentation.** Kodekommentarer må være korte og tekniske.
6. **Push kun når brugeren beder om det**, og vent på grøn GitHub Actions på commiten.
7. **Fremdriftskortet bliver.** `#cc-task` i dashboardet er fast UI. Nye handlinger over ~5 s skal have
   en `TASK_ESTIMATES`-post (label + seconds), ellers kører de uden fremdrift.
8. **Tidsestimater.** Skriv estimat før arbejdet og faktisk tid bagefter.

## Kontrakter

- `GET /health`: `status`, `db_write`, `disk_used_pct`, `budget`, `version`, `newest`, `started_at`,
  `ai`, `wordpress`, `serpapi`, `telegram`, `auth`, `users`. Returnerer 503 kun ved `kritisk`.
- `add_alarm(db, type, message, severity)`: skriver i `alarms` og køer i `alert_outbox`. Ingen
  netværkskald i request-stien — levering sker i `job_drain_alerts` med dedupe, stille timer og backoff.
- Login-spor: `users.last_login_ip`/`last_login_at`, `sessions.ip`, `login_attempts`.
  `client_ip()` bruger første hop af `X-Forwarded-For` og falder tilbage til socket-adressen.
- `NEWEST` / `NEWEST_LINE` i `app/main.py` er kilden til versionsbanneret; scripts læser dem med `sed`.
- Enkelt-projekt: `TRACK_DOMAIN` er én domæne, og der findes ingen `projects`-tabel.

## Sådan verificerer du

```bash
./venv/bin/python tests/test_v8_features.py     # enheds-/integrationsniveau
PATH="$PWD/venv/bin:$PATH" bash tests/ci_check.sh   # boot, alle sider, auth, WordPress-bro
python3 tests/check_paths.py                    # knapper/links uden rute
bash -n install.sh run.sh scripts/*.sh          # shell-syntaks
```

## Kendte faldgruber

- **Filgrænse:** `app/main.py` er for stor til at redigere med et værktøj der sender hele filen
  (64 KiB-grænse). Brug et Python-patch-script med `count(old) == 1`-assertions pr. anker.
- **Tid:** SQLite-tider gemmes som lokal ISO-tid via `now_iso()`, ikke UTC.
- **Migreringer:** Nye kolonner/tabeller til eksisterende installationer hører i `migrate_db()`;
  `init_db()` rammer kun nye databaser.
- **Installer:** Efter ændringer i en indlejret fil skal `install.sh` regenereres (17 blokke), og
  pariteten skal verificeres før commit.
- **Undgå:** `pkill -f`/mønsterbaseret kill; stop kun kendte PID'er. Kør ikke destruktive
  git-kommandoer (push/reset/deploy) uden at brugeren har bedt om det.

## Arbejdsform

Undersøg før du ændrer: læs `CLAUDE.md` (status/handoff), find de faktiske linjer med `code_search`,
og verificér antagelser mod koden i stedet for at gætte. Rapportér ærligt hvad der blev testet, og
hvad der ikke kunne testes (fx browser-visning eller rigtige API-kald).
