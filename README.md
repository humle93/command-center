# Command Center v7.11 PRO

[![CI](https://github.com/humle93/command-center/actions/workflows/ci.yml/badge.svg)](https://github.com/humle93/command-center/actions/workflows/ci.yml)

Selv-hostet SEO- og drifts-center (FastAPI + SQLite) i stil med RankMath Pro / Yoast Premium — bygget til Steamgears.
Alt kører på din egen server: dine data, ingen abonnement. Se [docs/ROADMAP.md](docs/ROADMAP.md) for hvad der er færdigt og hvad der er næste.

## Nyheder i v7.11

- **Brugere i stedet for token-login** — første besøg opretter din bruger (`/setup`), derefter logger du ind med brugernavn + adgangskode (PBKDF2-SHA256, salt pr. bruger, 30 dages HttpOnly-session). Fanen **Brugere** opretter/sletter brugere og skifter adgangskode. `APP_TOKEN` findes ikke længere, og der er ingen maskin-nøgle - al adgang kræver en bruger.
- ⏱️ **Fremdrift på opgaver** — tunge handlinger (crawl, AI-artikel, keyword-tjek, backlink-prospecting …) viser timer, procent og "~N s igen"; crawl læser de rigtige tal (sider/total + ETA) fra `/api/crawl/status`
- **Opdatering fra GitHub** — Cockpit viser installeret commit vs. seneste commit på `main`, tjekker selv kl. 05:00, og "Opdater" laver DB-backup og henter kun projektets filer. Den gamle "hent install.sh og kør den"-vej er fjernet.
- **nginx / Ultra.cc** — `deploy/nginx-command-center.conf`, `deploy/command-center.user.service` og proxy-header-understøttelse, så appen bliver på `127.0.0.1` bag nginx med korrekte Secure-cookies og rigtig klient-IP.
- **Rettelser fra kodegennemgang** — saniteret artikel-HTML (XSS), `.env` læses før konfigurationen, pris-monitors registrerer ændringer igen, crawl-diff virker (to crawls gemmes), `/monitors/add` giver ikke længere 500, HTTPS-advarslen rammer rigtigt, plus mindre korrekthedsrettelser.

## Funktioner

- 🎛️ **Cockpit** — domæneovervågning (uptime, svartid, SSL), opdaterings-panel og alarmer
- 🔍 **SEO Scanner** — deep audit af enkelt side (20+ vægtede kontroller inkl. focus keyword, læsbarhed, mixed content, schema, OG/Twitter) + **site-crawl** med score per side, robots.txt/sitemap-tjek og crawl-diff mod forrige crawl
- ✍️ **Artikler** — AI-generering (Gemini via aimlapi) eller skabelon, **push til WordPress som udkast**, **fakta-prompt med SerpAPI-konkurrentanalyse**, autopilot (idé → artikel → WP-kladde) og **kvalitetsgate** før publicering
- 🎯 **SEO-strategi** — AdSense / Affiliate / Backlink-vækst styrer AI-artiklernes stil + længde og autopilotens arbejde, med automatisk pre-flight-checkliste
- 🌱 **Growth Pack** — backlink-prospector (SerpAPI top 10 → sitetype + kontakt-e-mail + AI-outreach-draft), keyword-ideer via Google/DDG-autocomplete, visibility-index
- 🎯 **Keywords** — Google-positioner via SerpAPI (dagligt kl. 06:00), sværhedsgrads-heuristik, content gap mod top 10
- 🕷️ **SERP & Spy** — konkurrent-opdagelse + crawl af titel/H1/beskrivelse
- 🔗 **Links** — ekstern linktjek + AI-forslag til interne links
- 📱 **Social** — opslagskø med CSV-export og "→ Autopilot" (kladde i WordPress-pluginnet). Planlagt tid indtastes i lokal tid og gemmes som **lokal tid + UTC**, så sommertid ikke flytter opslaget
- 🩺 **Monitors** — tekst/JSON/pris-overvågning med alarmer ved ændring
- 🤖 **AI-synlighed** — stil en kundes spørgsmål til AI-modellen og se, om `TRACK_DOMAIN` nævnes i svaret (historik i `ai_visibility`)
- 📝 **Noter** — hurtige workflow-noter i dashboardet (`/notes/add`, `/notes/delete`)
- 👤 **Brugere** — opret/slet brugere, skift adgangskode; den sidste bruger kan ikke slettes
- 🚨 **Alarmer** — SSL-udløb, nedetid, brudte links, fejlede scans, nye GitHub-commits; valgfrit Telegram-push
- 📈 **Historik** — svartid per domæne, site-health og visibility over tid (Chart.js)

## Skærmbilleder

![Cockpit](docs/img/cc-cockpit.png)

Cockpit med opdaterings-panel og alarmer. Login-siden og alle 14 faner ligger i `docs/img/`
(`cc-login.png`, `cc-cockpit.png` … `cc-notes.png`); billederne er taget med
`python3 scripts/screenshots.py` mod den kørende app, og samme kommando opdaterer dem — se
[manualens afsnit om screenshots](docs/Command_Center_Bruger_og_Systemmanual.md#opdater-screenshots).

## Login & opsætning

1. `cp .env.example .env` og udfyld nøgler
2. `./run.sh` — scriptet udskriver den adresse appen lytter på (samt LAN-IP når `CC_HOST=0.0.0.0`)
3. Åbn adressen: **første besøg opretter din bruger** (`/setup`) — derefter log ind med brugernavn + adgangskode. Der er ingen token i `.env`.
4. Nye brugere, sletning og adgangskode-skift klares under fanen **Brugere**
5. (VPS) kør bag reverse proxy med TLS, eller brug `deploy/command-center.service` + SSH-tunnel

## Ultra.cc / nginx (reverse proxy)

1. `.env`: udfyld nøgler, sæt `CC_PUBLIC_URL=https://<din-adresse>`, lad `CC_HOST=127.0.0.1` og `CC_FORWARDED_ALLOW_IPS=127.0.0.1`
2. Start appen: `./run.sh`, eller `deploy/command-center.user.service` med `systemctl --user enable --now command-center`
3. Læg `deploy/nginx-command-center.conf` ind i den `server { }` du bruger (Ultra.cc: `~/.apps/nginx/proxy.d/`), og genindlæs nginx
4. Åbn `CC_PUBLIC_URL` — første besøg opretter din bruger

Det skal med i proxy-blokken:

- `proxy_set_header X-Forwarded-Proto $scheme;` — ellers tror appen den kører på http: session-cookien bliver ikke `Secure`, og der vises en HTTPS-advarsel
- `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` — så login-låsen pr. IP rammer klienten i stedet for nginx
- `proxy_read_timeout 300s;` — crawl, content gap og backlink-prospecting kan tage minutter (ellers 504 fra nginx)
- Appen kan **ikke** ligge på en understi (`https://host/apps/cc/`): alle links er absolutte — brug et subdomæne eller en egen port

## Opdatering fra GitHub

Panelet i Cockpit sammenligner installeret commit med seneste commit på `main`:

- **Tjek for nye commits** (`POST /update/check`) — viser SHA, dato og commit-besked, eller den præcise fejl (manglende token, 401/403, 404). Kører også automatisk kl. 05:00.
- **Opdater** (`POST /update/apply`) — tager en `pre-update`-backup af databasen, henter commit-tarballen og skriver **kun** projektets filer (`app/`, `scripts/`, `deploy/`, requirements, start-scripts, `install.sh`, Dockerfile, compose, `.env.example`). `.env`, databasen og `..`-stier røres ikke.
- **Alt i ét hug**: er `requirements.txt` ændret, køres `pip install -r` automatisk, og appen **genstarter sig selv** ~1,5 s efter svaret (systemd-unit, ellers `scripts/restart.sh` med pidfile + `run.sh`). Fjern fluebenet "genstart" i panelet, eller sæt `UPDATE_AUTO_RESTART=0`, for at genstarte manuelt. `UPDATE_RESTART_CMD` overstyrer kommandoen (fx din egen supervisor).
- **Fra terminalen**: `bash scripts/update.sh` gør hele kæden (tjek → filer → requirements → genstart) og venter til `/health` svarer igen; `--check` tjekker kun, `--no-restart` springer genstarten over. `bash scripts/restart.sh` genstarter uden at opdatere.
- Status som JSON: `GET /api/update` (inkl. `restart_mode` og `auto_restart`). Kræver `GITHUB_TOKEN` (privat repo). `/self-update` findes stadig som alias for `/update/apply`.

## Steamgears Autopilot-bro (WordPress-plugin 7.5+)

Command Center og WordPress-pluginnet **Steamgears Autopilot** snakker sammen via pluginnets REST-API
(`/wp-json/sgap/v1`) med de samme `WP_URL` / `WP_USER` / `WP_APP_PASSWORD` som WordPress-push
(`WP_USER` skal være administrator).

- **Status hver 30. min** (fanen Social → "Steamgears Autopilot"): kø, kladder der venter på godkendelse, og udgivet/klik/ordrer/omsætning pr. kanal de sidste 30 dage
- **Alarmer** når noget ændrer sig: nye fejlede opslag, nye kladder, eller pluginnet svarer ikke
- **"→ Autopilot"** sender et opslag som kladde til pluginnet (godkendes i WordPress under Steamgears → AI Drafts)
- Slå til/fra under Moduler ("Autopilot-bro"). Retningen er altid CC → site, så CC kan blive på 127.0.0.1

## Installering

```bash
curl -H "Authorization: Bearer <TOKEN>" -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/humle93/command-center/contents/install.sh -o install.sh && bash install.sh
```

Eller med Docker: `cp .env.example .env && docker compose up -d --build`. `install.sh` er selvstændig og
skriver alle filer (inkl. `deploy/nginx-command-center.conf` og `deploy/command-center.user.service`).

## Drift & test

- **Cron**: domæne-tjek hver 6. time, keyword-tjek 06:00, autopilot 05:15, oprydning 04:30, DB-backup 04:40, GitHub-tjek 05:00, Autopilot-bro hver 30. min
- **Backup**: `app/backups/cc-daglig-*.db` (14 gemmes) + `cc-pre-update-*.db` før hver opdatering
- **Health**: `/health` (200, eller 503 ved kritisk DB/disk-tilstand) viser også månedens API-forbrug
- **Tests**: `python3 tests/test_v8_features.py` (enhedstests), `bash tests/ci_check.sh` (boot + alle sider + auth + WordPress-bro + link-audit)
- **Screenshots**: `python3 scripts/screenshots.py` tager login-siden og alle 14 faner ind i `docs/img/` (kræver `pip install playwright` + `python3 -m playwright install chromium`; kør mod en kørende app med `--base/--user/--password`). CI advarer, hvis billederne er ældre end dashboard-skabelonen

## Alarmer (v7.12)

Alarmer går til flere kanaler: **Telegram**, **e-mail** (SMTP), **ntfy** og en **signeret webhook**.
De sendes ikke inline — de skrives i køen `alert_outbox` og leveres af et job med backoff
(30 s → 2 min → 10 min → 1 t, maks. 5 forsøg), så en langsom modtager aldrig blokerer appen.
Ens alarmer dedupliceres inden for `ALERT_DEDUPE_MINUTES`, stille timer (`ALERT_QUIET_HOURS=23-7`)
udskyder alt under "kritisk" til vinduet slutter, og webhooken signeres efter Standard Webhooks
(`webhook-id`, `webhook-timestamp`, `webhook-signature: v1,...` = HMAC-SHA256 over
`id.timestamp.body`). Fanen **Alarmer** viser hvilke kanaler der er sat op, har test-knapper pr.
kanal og lister fejlede leveringer med årsag og antal forsøg. Fremdriftskortet dækker alle tunge
handlinger — crawl med rigtig procent, resten med ærlige skøn (`TASK_ESTIMATES`), nu også
testalarmer og GitHub-opdatering.

## Opstart, login og IP (v7.13)

Ved hver opstart skriver appen version og de nyeste aendringer til skaermen, til
`app/data/startup.log` og til `settings.last_start` - og de samme nyheder er med i `GET /health`.
`run.sh`, `run.bat`, `scripts/restart.sh`, `scripts/update.sh` og `install.sh` viser version + nyheder,
saa man ikke skal huske hvilken version der kører.

Login logger nu IP: `users.last_login_ip`/`last_login_at`, `sessions.ip` og tabellen `login_attempts`
(ok/fejl, 30 dage) - vist under fanen **Brugere** sammen med de seneste forsoeg. IP'en hentes fra
`X-Forwarded-For` (foerste hop) med socket-adressen som reserve, saa den er korrekt bag nginx.
Login-siden viser en kort **kørselsrapport** uden at man er logget ind: version + commit, seneste
opstart, åbne alarmer, antal domæner/keywords/monitors, seneste domænetjek og crawl, DB-størrelse og
din IP - ingen alarmtekster eller brugernavne.

## Agenter og skills (v7.13.2)

Fire agenter i tre grupper, plus en skill. Se `.agents/README.md` for detaljer og spawn-eksempler.

| Repo | Agenter |
|---|---|
| **Command Center** (dette repo) | `command-center-reviewer` (regler/kontrakter), `cc-verifier` (tests, ruter, installer-paritet), `site-seo-auditor` (SEO ud fra appens DB) |
| **Social Autopilot** (tjenesten) | `social-autopilot-auditor` (`/drafts`, `/autopilot/sync`, kanaler, idempotens, tidszoner) |
| **Social Autopilot Android** (mobilklienten) | `social-autopilot-android` (API-paritet, Keystore, offline-kø, release) |

- `.agents/skills/command-center/SKILL.md` — en **skill** med reglerne, kontrakterne,
  verify-kommandoerne og faldgruberne. Den bliver slash-kommandoen `/skill:command-center`.
- Alle agenter er **read-only** med vilje; kun `cc-verifier` må køre kommandoer, og den skriver ikke.

De er udviklerværktøj, ikke app-funktioner: de indgår ikke i `install.sh`, og self-update henter dem
ikke. Modellen i agenten står som `anthropic/claude-sonnet-4.5` (Codebuff-docsenes eksempel) — skift
den linje hvis kontoen ikke kan tilgå modellen.

## Dokumentation

Kodeændringer kræver dokumentation i samme commit: `README.md` plus den relevante fil i `docs/`
(manual ved funktioner, arkitektur ved struktur/jobs/ruter, roadmap ved prioriteringer). `install.sh`
regenereres bagefter, fordi den indeholder kopier af filerne. CI fejler, hvis der ændres kode uden
dokumentation — `[skip docs]` i commit-beskeden springer tjekket over. `CLAUDE.md` er statusnotatet
og handoff, `AGENTS.md` er de korte regler for agenter.

## Sikkerhed

- **Brugere**: PBKDF2-SHA256 med salt pr. bruger; sessioner er HttpOnly-cookies (30 dage) gemt som `sha256(id)` i databasen, så en DB-kopi ikke giver adgang. Skift af adgangskode logger dine andre sessioner ud.
- **Cookie/HTTPS**: cookien sættes `Secure` når appen ser https (kræver `X-Forwarded-Proto` bag proxy — se nginx-afsnittet).
- **API-budget**: SerpAPI og aimlapi tælles pr. måned og stoppes ved loftet (`SERPAPI_MONTHLY_LIMIT`, `AI_MONTHLY_LIMIT`), med alarm ved 80 % og 100 %.
- Default binding er 127.0.0.1 — sæt aldrig `0.0.0.0` uden reverse proxy + TLS.

## Kendte begrænsninger

- Dashboardet henter Tailwind, Alpine.js og Chart.js fra CDN (login-siden er helt selvstændig). Uden internetadgang ser dashboardet stadig ud, men uden styling/interaktivitet.
- Opdatering kræver `GITHUB_TOKEN`; ændringer i `requirements.txt` rapporteres men installeres først ved næste `./run.sh`.
- `install.sh` indeholder kopier af projektets filer (CI tjekker at de matcher); ret derfor altid kildefilerne og kør regen, ikke installeren.
- Screenshots i `docs/img/` er taget med `python3 scripts/screenshots.py` mod v7.13.x-UI'et; kør scriptet igen efter større UI-ændringer.
