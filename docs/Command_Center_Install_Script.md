# Command Center — installationsscriptet

`install.sh` i repoets rod er den autoritative installer. Den er selvstændig (den indeholder kopier af
projektets filer i heredocs) og idempotent: kør den igen for at opdatere, eller brug
**Opdatering fra GitHub** i Cockpit / `POST /update/apply`.

> Denne side erstatter det tidligere dokument, der var en manuel kopi af v6.0-scriptet. Kopien var ude af
> trit med koden; brug `install.sh`, README og [bruger- og systemmanualen](Command_Center_Bruger_og_Systemmanual.md).

## Hvad scriptet gør

1. Opretter `~/command-center` med `app/templates`, `app/data`, `app/static`, `deploy`, `scripts`
2. Skriver alle projektfiler (valgfrit: `requirements.txt`, `.env.example`, `app/main.py`, skabeloner, `run.sh`, `run.bat`, `Dockerfile`, `docker-compose.yml`, systemd-units, nginx-config, README, smoke-test)
3. Opretter `.env` fra `.env.example` hvis den ikke findes (rører aldrig en eksisterende `.env`)
4. Sætter `run.sh` eksekverbar, kører smoke-test hvis appen allerede svarer, og printer den lokale + LAN-adresse samt login-trinnet

Appen læser `.env` selv (og systemd-units bruger desuden `EnvironmentFile`), så nøgler skal kun stå ét sted.

## Installation

```bash
mkdir -p ~/command-center && cd ~/command-center
curl -H "Authorization: Bearer <GITHUB_TOKEN>" -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/humle93/command-center/contents/install.sh -o install.sh
bash install.sh
```

Docker i stedet: `cp .env.example .env && docker compose up -d --build`.

## Efter installation

```bash
cd ~/command-center
./run.sh                       # printer adresse + LAN-IP, starter uvicorn
# eller som bruger-service (Ultra.cc):
systemctl --user enable --now command-center
bash scripts/smoke_test.sh     # /health, /login, /setup
```

Første besøg i browseren opretter din bruger (`/setup`). Der er ingen login-token i `.env`.

## Rollback

1. Stop appen: `systemctl --user stop command-center` (eller Ctrl+C)
2. Gendan databasen: `cp ~/command-center/app/backups/cc-pre-update-*.db ~/command-center/app/data/center.db` (vælg den nyeste; daglige backups hedder `cc-daglig-*`)
3. Kør `install.sh` igen, eller brug en tidligere commit med GitHub-opdateringen
4. Verificér med `bash scripts/smoke_test.sh`

## Vedligeholdelse

`install.sh` indeholder kopier af projektets filer, og CI tjekker at de matcher repoet. Ret derfor altid
kildefilerne — ret aldrig installeren direkte.
