# Command Center v7.18 PRO

[![CI](https://github.com/humle93/command-center/actions/workflows/ci.yml/badge.svg)](https://github.com/humle93/command-center/actions/workflows/ci.yml)

Selv-hostet SEO- og drifts-center (FastAPI + SQLite) i stil med RankMath Pro / Yoast Premium — bygget til Steamgears.
Alt kører på din egen server: dine data, ingen abonnement. Se [docs/ROADMAP.md](docs/ROADMAP.md) for hvad der er færdigt og hvad der er næste.

## Nyheder i v7.18

- **Standardbruger ved deployment (v7.18)** — skriv `CC_ADMIN_EMAIL` + `CC_ADMIN_PASSWORD` i `.env`, så oprettes kontoen ved opstart, og du kan logge ind med det samme; opsætningssiden er ikke længere en del af et normalt deployment. Koden gemmes kun som PBKDF2-hash, kontoen oprettes med `must_change_password` (gul bjælke indtil du skifter den under fanen **Brugere**), og der seedes kun, når `users` er tom — en senere ændring af `.env` rører ikke en konto i brug. Er linjerne tomme, er `/setup` stadig reserven. Adgangskoden står kun i `.env` (gitignored), aldrig i repoet eller i loggen
- **Advarsel når `.env`-koden er forældet (v7.18.1)** — skifter du koden under **Brugere**, passer `CC_ADMIN_PASSWORD` ikke længere. Så skriver opstartsloggen `[cc] advarsel: …`, advarslen ligger under **Alarmer**, og dashboardet viser en rød bjælke, indtil du retter eller fjerner linjen i `.env`. Kontoen røres ikke — login bruger den nye kode
- **MCP-hærdning (v7.17.1)** — nøglen ligger ikke længere i klartekst i databasen: rækken i `settings` slettes i samme kald som dashboardet viser den (højst 15 min. hvis siden aldrig åbnes, og oprydningen fjerner resten). "Jeg har gemt nøglen"-knappen er derfor væk. Ukendte værktøjsnavne på `/mcp` havner nu også i auditten, så en nøgle der famler kan ses.
- **MCP skriver nu også (fase 2)** — med `read,write` på nøglen kan en agent starte et site-crawl, oprette en monitor, løse en alarm og skrive en note (`start_crawl`, `add_monitor`, `resolve_alarm`, `add_note`). Hvert kald — også afviste — havner i en **audit pr. nøgle** (`api_audit`) med værktøj, varighed og fejl, som du ser i fanen **Brugere** og med `python3 scripts/api_key.py audit`. Værktøjerne har `readOnlyHint`/`destructiveHint`, så klienten kan advare før et kald.
- **MCP-adgang (fase 1)** — agenter og editorer kan læse Command Center direkte. Under fanen **Brugere** opretter du en nøgle pr. klient (ingen fælles token); den vises én gang, gemmes kun som sha256 og kan tilbagekaldes enkeltvis. `POST /mcp` tilbyder syv læse-værktøjer: `health`, `crawl_summary`, `keywords`, `monitors`, `alarms_open`, `notes` og `history`. Endpointet validerer `Origin`/`Host` (DNS-rebinding) og svarer `401` med `WWW-Authenticate` uden nøgle — se [docs/Command_Center_MCP.md](docs/Command_Center_MCP.md).
- **E-mail er login (v7.15)** — første besøg opretter din bruger med e-mail + adgangskode (`/setup`), derefter logger du ind med e-mail og adgangskode (PBKDF2-SHA256, salt pr. bruger, 30 dages HttpOnly-session). Gamle konti fra brugernavn-tiden kan stadig logge ind med deres brugernavn, indtil de får en e-mail.
- **Invitation på mail (v7.15, svar i v7.17.2)** — fanen **Brugere** har "Inviter bruger": du skriver en e-mail, og appen sender en invitation med en midlertidig adgangskode, som brugeren skifter ved første login (dashboardet minder om det). Der er ingen invite-links og ingen tokens - kun en adgangskode. Svaret lander i den samme formular: blev mailen sendt, står der hvilken adresse den gik til, og fejler den, står mailserverens fejl der med det samme i stedet for kun under Alarmer.
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
- 📱 **Social** — opslagskø med CSV-export og "→ Autopilot" (kladde i WordPress-pluginnet — kun **én** kladde pr. opslag, også ved dobbeltklik). Planlagt tid indtastes i lokal tid og gemmes som **lokal tid + UTC**, så sommertid ikke flytter opslaget
- 🩺 **Monitors** — tekst/JSON/pris-overvågning med alarmer ved ændring
- 🤖 **AI-synlighed** — stil en kundes spørgsmål til AI-modellen og se, om `TRACK_DOMAIN` nævnes i svaret (historik i `ai_visibility`)
- 📝 **Noter** — hurtige workflow-noter i dashboardet (`/notes/add`, `/notes/delete`)
- 👤 **Brugere** — invitér/slet brugere, skift adgangskode og opret **MCP-nøgler** pr. klient (hash, scopes, tilbagekald); den sidste bruger kan ikke slettes
- 🚨 **Alarmer** — SSL-udløb, nedetid, brudte links, fejlede scans, nye GitHub-commits; valgfrit Telegram-push
- 📈 **Historik** — svartid per domæne, site-health og visibility over tid (Chart.js)

## Skærmbilleder

![Cockpit](docs/img/cc-cockpit.png)

Cockpit med opdaterings-panel og alarmer. Login-siden og alle 14 faner ligger i `docs/img/`
(`cc-login.png`, `cc-cockpit.png` … `cc-notes.png`); billederne er taget med
`python3 scripts/screenshots.py` mod den kørende app, og samme kommando opdaterer dem — se
[manualens afsnit om screenshots](docs/Command_Center_Bruger_og_Systemmanual.md#opdater-screenshots).

## Login & opsætning

1. `cp .env.example .env` og udfyld nøgler — bl.a. `CC_ADMIN_EMAIL` + `CC_ADMIN_PASSWORD` til standardbrugeren, så den findes efter deployment
2. `./run.sh` — scriptet udskriver den adresse appen lytter på (samt LAN-IP når `CC_HOST=0.0.0.0`)
3. Åbn adressen: **standardbrugeren oprettes ved opstart**, så du logger ind med e-mail + adgangskode med det samme (koden fra `.env` skal skiftes under fanen **Brugere** ved første login). Er de to linjer tomme, opretter første besøg brugeren via `/setup` i stedet — det er reserven. Der er ingen token i `.env`.
4. Nye brugere inviteres på mail, og sletning/adgangskode-skift klares under fanen **Brugere** (kræver `SMTP_HOST` + `SMTP_FROM`); fra serveren kan samme invitation sendes med `python3 scripts/invite.py navn@domaene.dk` — og med `--print` udskrives mailen i stedet, så den kan sendes fra en anden mailkonto når SMTP ikke er sat op. Helt uden mail kan brugeren oprettes direkte med `python3 scripts/user_create.py navn@domaene.dk --username humle91` (koden skrives skjult og skal være min. 8 tegn)
5. (VPS) kør bag reverse proxy med TLS, eller brug `deploy/command-center.service` + SSH-tunnel
6. Vil du have en agent på? Opret en nøgle under **Brugere → MCP-adgang** og peg klienten på `https://<din-adresse>/mcp` (se nedenfor)

## MCP-adgang (v7.16)

Fase 1 er **læse-adgang** (syv værktøjer); fase 2 tilføjer fire **skrive-værktøjer** med `write`-scope
og audit pr. nøgle. Alt over MCP (Streamable HTTP, JSON-svar) på `/mcp`.

```bash
# nøgle fra terminalen (samme tabel som UI'et) - vises kun én gang
python3 scripts/api_key.py create "Claude Desktop" read

# prøv endpointet
curl -s https://<din-adresse>/mcp -H "Authorization: Bearer cc_..." \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

- Nøglen sendes altid i `Authorization: Bearer …` (aldrig i query string) og gemmes kun som hash. Den vises **én gang** — rækken med klartekst slettes i samme kald som dashboardet viser den.
- `scopes`: `read` (kun læsning) eller `read,write` (læsning + de fire skrive-værktøjer). Manglende scope giver `-32003`.
- `Origin`/`Host` valideres mod `CC_PUBLIC_URL`; ukendt vært giver `421`, fremmed origin `403`.
- Ukendte værktøjsnavne og manglende scopes havner også i auditten (`ok=0`), så et nøgle der prøver ting af kan ses.
- `python3 scripts/api_key.py list` viser nøglerne (kun halen), `revoke <id>` slår dem fra med det samme, og `audit [antal]` viser de seneste kald pr. nøgle.
- Læse-værktøjer: `health`, `crawl_summary`, `keywords`, `monitors`, `alarms_open`, `notes`, `history`.
- Skrive-værktøjer (`write`): `start_crawl` (afvises hvis et crawl kører), `add_monitor` (samme url+type oprettes ikke to gange), `resolve_alarm`, `add_note`.

## Ultra.cc / nginx (reverse proxy)

1. `.env`: `cp .env.example .env` og udfyld nøglerne. Sæt `CC_PUBLIC_URL` til **præcis** den adresse du åbner i browseren — med `https://`, uden anførselstegn og uden sti (`CC_PUBLIC_URL=https://humle91.ultra.cc`). Lad `CC_HOST=127.0.0.1` og `CC_FORWARDED_ALLOW_IPS=127.0.0.1` stå. `install.sh` skriver kun `.env.example`, og opdateringer rører aldrig `.env` — så linjen forbliver tom, indtil du selv udfylder den
2. Start appen: `./run.sh`, eller `deploy/command-center.user.service` med `systemctl --user enable --now command-center`
3. Læg `deploy/nginx-command-center.conf` ind i den `server { }` du bruger (Ultra.cc: `~/.apps/nginx/proxy.d/`), og genindlæs nginx
4. Åbn `CC_PUBLIC_URL` — standardbrugeren fra `.env` kan logge ind med det samme (er linjerne tomme, opretter første besøg din bruger via `/setup`)

`CC_PUBLIC_URL` styrer login-linket i `scripts/update.sh` og `scripts/user_create.py`, adressen i invitationsmailen og Host-tjekket på `/mcp`. Tjek med `bash scripts/update.sh --check`: står der `127.0.0.1` som login-adresse, er linjen tom eller skrevet forkert. Er `/mcp` utilgængelig med `421`, er det samme linje — værten skal matche ord for ord, og et sæt anførselstegn omkring værdien er nok til at ødelægge den.

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
- **Fra terminalen**: `bash scripts/update.sh` gør hele kæden (tjek → filer → requirements → genstart) og venter til `/health` svarer igen; `--check` tjekker kun, `--no-restart` springer genstarten over. Øverst viser scriptet **tre** versioner ved siden af hinanden: den der **kører nu** (fra `/health`), den **filerne** indeholder (`app/main.py`), og den **installatøren** vil skrive (`install.sh`s indlejrede `app/main.py`) — plus login-adressen fra `CC_PUBLIC_URL`. `bash scripts/update.sh --version` er den samme kontrol som rent svar: kode 0 kun når alle tre stemmer, ellers kode 1 med en linje om hvad der er galt. Opdateringen bruger kontrollen selv: er `install.sh` på disken ældre end koden, skriver den **ingen** filer — den stopper med kode 7 og siger, at installatøren skal hentes fra git først (`git checkout -- install.sh`). `bash scripts/restart.sh` genstarter uden at opdatere.
- Status som JSON: `GET /api/update` (inkl. `restart_mode` og `auto_restart`). Kræver `GITHUB_TOKEN` (privat repo). `/self-update` findes stadig som alias for `/update/apply`.

## Steamgears Autopilot-bro (WordPress-plugin 7.5+)

Command Center og WordPress-pluginnet **Steamgears Autopilot** snakker sammen via pluginnets REST-API
(`/wp-json/sgap/v1`) med de samme `WP_URL` / `WP_USER` / `WP_APP_PASSWORD` som WordPress-push
(`WP_USER` skal være administrator).

- **Status hver 30. min** (fanen Social → "Steamgears Autopilot"): kø, kladder der venter på godkendelse, og udgivet/klik/ordrer/omsætning pr. kanal de sidste 30 dage
- **Alarmer** når noget ændrer sig: nye fejlede opslag, nye kladder, eller pluginnet svarer ikke
- **"→ Autopilot"** sender et opslag som kladde til pluginnet (godkendes i WordPress under Steamgears → AI Drafts). Opslaget sendes **kun én gang**: rækken låses før kaldet, så et dobbeltklik eller et genforsøg ikke giver to kladder. Svarer WordPress ikke (timeout), bliver status "sendt? (svar udeblev)" — tjek AI Drafts, før du sender igen
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
- **Fælles agentregler i alle repoer**: `bash scripts/agents_md_rollout.sh --dry-run` viser planen, og uden `--dry-run` lægger den `AGENTS.md` ind i alle dine repoer som branch + PR (kræver `gh` logget ind). En eksisterende fil overskrives kun med `--overwrite`, og `main` røres aldrig
- **Scripts i `scripts/`**: alle otte har samme header — `navn - formål`, `Brug:`, `Kraever:` og `Sidst aendret` — og er eksekverbare. `bash scripts/update.sh -h` (og `--help` på de øvrige med flag) læser headeren, så hjælpen ikke kan drive fra scriptet. Versionsnumre står ikke i headere: de læses fra `APP_VERSION` i `app/main.py`

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
saa man ikke skal huske hvilken version der kører. `scripts/update.sh` går to skridt videre: den viser
versionen på disken, den version processen svarer med i `/health` **og** den version `install.sh` vil
skrive, advarer hvis de er forskellige, og skriver login-adressen (`CC_PUBLIC_URL` + `/login`, dvs. den
adresse nginx videresender). `bash scripts/update.sh --version` giver samme kontrol som rent svar:
kode 0 kun når alle tre stemmer, ellers kode 1 med en linje om hvad der er galt — så en gammel
`install.sh`, der ville overskrive koden med en ældre version, bliver opdaget før man kører den.

Login logger nu IP: `users.last_login_ip`/`last_login_at`, `sessions.ip` og tabellen `login_attempts`
(ok/fejl, 30 dage) - vist under fanen **Brugere** sammen med de seneste forsoeg. IP'en hentes fra
`X-Forwarded-For` (foerste hop) med socket-adressen som reserve, saa den er korrekt bag nginx.
Login-siden viser en kort **kørselsrapport** uden at man er logget ind: version + commit, seneste
opstart, åbne alarmer, antal domæner/keywords/monitors, seneste domænetjek og crawl, DB-størrelse og
din IP - ingen alarmtekster eller brugernavne.

## Agenter og skills (v7.13.2)

Fem agenter i tre grupper, plus en skill. Se `.agents/README.md` for detaljer og spawn-eksempler.

| Repo | Agenter |
|---|---|
| **Command Center** (dette repo) | `command-center-reviewer` (regler/kontrakter), `cc-verifier` (tests, ruter, installer-paritet), `site-seo-auditor` (SEO ud fra appens DB), `mcp-access-auditor` (MCP-nøgler, scopes, audit, transport) |
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
