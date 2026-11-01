# Command Center — statusnotat til Claude

**Opdateret:** 1. november 2026 · **Version:** 7.12.0 · **Branch:** `main` · **Seneste commit:** se `git log -1`
Dette er et handoff-notat: hvad der er lavet, hvordan du verificerer det, og hvad der er næste skridt.
Den kanoniske roadmap er [`docs/ROADMAP.md`](docs/ROADMAP.md); brugervejledning er
[`docs/Command_Center_Bruger_og_Systemmanual.md`](docs/Command_Center_Bruger_og_Systemmanual.md) og
arkitekturen er [`docs/Command_Center_Dokumentation.md`](docs/Command_Center_Dokumentation.md).

## Hvad projektet er

Selv-hostet SEO- og drifts-center til steamgears.eu: FastAPI + SQLite i én proces, server-rendered
dashboard (Alpine.js), APScheduler-jobs og integrationer til SerpAPI, aimlapi, WordPress
(Steamgears Autopilot) og Telegram. Kører på `127.0.0.1` bag nginx (Ultra.cc) eller på Docker.

## Kør og test

```bash
./run.sh                      # opretter venv, installerer requirements, printer adressen
python3 tests/test_v8_features.py    # in-process enhedstests
bash tests/ci_check.sh              # boot + alle sider + auth + WordPress-bro + link-audit
bash scripts/update.sh --check      # GitHub-opdatering (kraever GITHUB_TOKEN i .env)
```

Seneste kendte status: **begge suites ALL PASS**, og GitHub Actions (`.github/workflows/ci.yml`)
kørte grønt på `ed97575`. CI tjekker desuden at alle 17 indlejrede filer i `install.sh` matcher repoet.

## Ændringer i denne arbejdsperiode

### Adgang og brugere
- Token-login (`APP_TOKEN`) er fjernet. Første besøg opretter bruger via `/setup`; derefter
  brugernavn + adgangskode (PBKDF2-SHA256, 240k iterationer, salt pr. bruger).
- Sessioner ligger i `sessions` som `sha256(id)`, HttpOnly-cookie `cc_session` (30 dage, `Secure` på https).
- Fane **Brugere**: opret/slet brugere og skift adgangskode (logger andre sessioner ud).
- Login-lås: 5 fejl pr. IP = 10 min. Brugernavn 3–32 tegn `[A-Za-z0-9._-]`, adgangskode ≥ 8 tegn.
- **Juno er fjernet helt** (se nedenfor): der findes ingen maskin-nøgle, kun bruger-sessioner.

### Hosting
- `run.sh` udskriver den rigtige adresse (LAN-IP når `CC_HOST=0.0.0.0`), understøtter
  `CC_HOST` / `CC_PORT` / `CC_PUBLIC_URL` og skriver pidfile `app/data/cc.pid`.
- `deploy/nginx-command-center.conf` (proxy-headers, `proxy_read_timeout 300s`, ingen understi) og
  `deploy/command-center.user.service` (systemd --user, `EnvironmentFile`).
- uvicorn kører med `--proxy-headers --forwarded-allow-ips`, så cookies bliver `Secure` og login-låsen ser klientens IP.

### Rettelser fra kodegennemgang
- `sanitize_article_html()` (allow-list) omkring AI-indhold, der vises med `|safe` — lukker XSS.
- `.env` læses før konfigurationen, og inline-kommentarer fjernes.
- Pris-monitor sammenligner `last_value` numerisk; crawl gemmer to runs, så `/api/crawl/diff` virker.
- `/monitors/add` validerer input (ingen 500); HTTPS-advarsel via `request.url.scheme`.
- SSL-tjek uden port-fejl, lokale tids-cutoffs i oprydningen, ingen dubleret side-hentning,
  `asyncio.get_running_loop()` i stedet for deprecated API.

### Opdatering fra GitHub
- `GET /api/update` (status), `POST /update/check`, `POST /update/apply`; `/self-update` er alias.
- Henter commit-tarball og skriver **kun** whitelistede stier (`app/`, `scripts/`, `deploy/`,
  requirements, start-scripts, `install.sh`, Dockerfile, compose, `.env.example`); afviser `..`,
  absolutte stier, symlinks og `.env`. DB-backup (`pre-update`) køres først.
- `requirements.txt` geninstalleres automatisk ved ændring, og appen **genstarter selv** via
  `scripts/restart.sh` (systemd-unit → pidfile + `run.sh`). Slås fra med `UPDATE_AUTO_RESTART=0`;
  `UPDATE_RESTART_CMD` overstyrer kommandoen.
- `scripts/update.sh` kører tjek → filer → requirements → genstart og venter på `/health`.
  Den kalder funktionerne direkte i venv'en, så der kræves hverken token eller login.
- Den gamle "hent `install.sh` og kør `bash`"-vej er fjernet.

### UI-audit og fremdrift
- `tests/check_paths.py`: hver `action`/`href`/`formaction`/`fetch` i skabelonerne skal matche en
  route (kører i CI). Rettede bl.a. historik-kortet (Alpine-flag i stedet for `x-show="false"`),
  domain-URL via `data-url`, `.catch()` på audit, og links kun for `http(s)`.
- `TASK_ESTIMATES` (24 tunge handlinger) + `crawl_progress()`: `/api/crawl/status` giver
  `percent`, `eta_seconds`, `elapsed_seconds`. Dashboardet viser et fremdriftskort (timer, procent,
  "~N s igen"), poller crawl hvert 3. sekund og viser en kvittering efter tunge formular-post.

### Juno fjernet (vigtigt)
- Væk: `JUNO_TOKEN`, `is_juno()`, `X-CC-Token`, `POST /api/bridge/gsc`, `POST /api/bridge/drift`,
  `pull_bridge_sync` + `pull_bridge`-jobbet, `BRIDGE_POLL_MINUTES`, modulet `bridge`,
  Cockpit-kortet "Daglig drift (pushet fra Juno)" og skemaet for `drift`, `gsc_daily`, `gsc_queries`.
- Tilbage: kun WordPress-broen (Steamgears Autopilot, `sgap/v1`) — den er **ikke** Juno.
- Konsekvens: der er **ingen Google Search Console-data** længere. Det er roadmap-punkt 1.

### Alarmer og outbox (v7.12)
- `add_alarm` sender ikke længere inline til Telegram: alarmen skrives i `alert_outbox` pr. kanal
  (telegram/e-mail/ntfy/webhook) og leveres af `job_drain_alerts` hvert minut.
- Dedupe pr. `sha256(type|message)` i `ALERT_DEDUPE_MINUTES`; stille timer udskyder alt under
  "kritisk"; backoff 30 s → 2 min → 10 min → 1 t, derefter `failed` + synlig fejl i UI.
- Webhook signeres efter Standard Webhooks (`webhook-id`, `webhook-timestamp`,
  `webhook-signature: v1,...`), e-mail via `smtplib` (STARTTLS/SSL, 15 s timeout).
- UI: fanen **Alarmer** viser kanaler, test-knapper (`POST /alerts/test`) og fejlede leveringer;
  status som JSON på `GET /api/alerts/status`.
- Nye tests i `tests/test_v8_features.py` dækker kanalvalg, signatur, dedupe, backoff, stille timer
  og at `add_alarm` ikke laver HTTP.

### Dokumentation og CI
- `README.md`, manualen og arkitektur-dokumentet er skrevet om til v7.11; `docs/Command_Center_Install_Script.md`
  er erstattet af en kort, korrekt side (den gamle var en 1.362-linjers kopi af v6.0-scriptet).
- `docs/ROADMAP.md` er ny. CI's paritets-trin dækker nu alle 17 indlejrede filer (før 5).

### Commits
`d48854e` (v7.11: brugere, opdatering, nginx, rettelser) · `d47a920` (Juno fjernet) ·
`e519a65` (fremdrift) · `df37281` (CI-checks + docs) · `ed97575` (README) · `cc2bf30` (dette notat) ·
`1958ef6` (dokumentationsregel + CI-guard).

## Sådan undgår du at ødelægge installeren

`install.sh` indeholder **kopier** af projektets filer i heredocs, og CI fejler hvis de afviger.
Ret derfor altid kildefilerne og kør regen-scriptet (samme mønster som i `tests/ci_check.sh`-pariteten):

```bash
for f in app/main.py app/templates/dashboard.html app/templates/login.html README.md .env.example \
         run.sh run.bat scripts/smoke_test.sh scripts/restart.sh scripts/update.sh requirements.txt \
         Dockerfile docker-compose.yml deploy/command-center.service deploy/command-center.user.service \
         deploy/nginx-command-center.conf; do echo "$f"; done   # -> heredoc-markører EOF_MAIN, EOF_HTML, ...
```

Markører: `EOF_REQ, EOF_ENVDOT, EOF_MAIN, EOF_HTML, EOF_LOGIN, EOF_RUNSH, EOF_DOCKER, EOF_COMPOSE,
EOF_SERVICE, EOF_README, EOF_SMOKE, EOF_WINBAT, EOF_RUN, EOF_NGINX, EOF_USERSVC, EOF_RESTART, EOF_UPDATE`.

## Dokumentation (fast regel)

Hver ændring opdaterer **`README.md`** og den relevante fil i `docs/` i samme commit:
ny funktion → README + manualen; ændret arkitektur/job/rute/tabel → `Command_Center_Dokumentation.md`;
ny prioritet → `ROADMAP.md`; status → denne fil. Derefter regenereres `install.sh`, fordi README er indlejret.

CI håndhæver det: ændres `app/`, `scripts/`, `deploy/`, `requirements.txt`, `run.sh`, `run.bat`,
`Dockerfile` eller `docker-compose.yml` uden at `README.md`, `docs/`, `CLAUDE.md` eller `AGENTS.md`
ogsa er rørt, fejler jobbet med en liste over de ændrede filer. `[skip docs]` i commit-beskeden
springer tjekket over til rene undtagelser.

## Arbejdsform

- Start hver opgave med et tidsestimat (fx "~10 min") og afslut med det faktiske tidsforbrug. Skrider det, sig det straks.
- Rapportér kun det, der faktisk er kørt: hvilke tests, CI-status, og hvad der ikke kunne verificeres her.

## Kendte begrænsninger

- Én proces + SQLite + APScheduler: ingen vandret skalering; et job deler event-loop med HTTP.
- Dashboardet henter Tailwind/Alpine/Chart.js fra CDN; login-siden er selvstændig.
- Crawleren bruger `requests` (ingen JS-rendering) og ca. 20 kontroller — ikke Sitebulb-niveau.
- Efter Juno-fjernelsen: ingen GSC-data, og `drift`/`gsc_*`-tabeller kan stadig ligge tomme i en
  eksisterende `center.db` (intet læser eller skriver dem).
- Systemd-genstartsstien er ikke testet i denne VM (ingen systemd); pidfile-stien er verificeret.
- `docs/img/`-screenshots er fra v7.8.
- Opdatering kræver `GITHUB_TOKEN`; et rigtigt tarball-download er ikke afprøvet her.

## Roadmap (kort — detaljer i `docs/ROADMAP.md`)

1. **Google Search Console** (read-only): clicks/impressions/queries/pages, striking distance,
   content decay, indexation. Største hul efter Juno-fjernelsen.
2. **Alarm-routing**: email/SMTP, webhook, ntfy/Apprise; dedup pr. `(type, message)` indtil resolved,
   quiet hours, maintenance windows, ugentlig digest.
3. **API-nøgler + udgående webhooks (+ lille MCP)**: gendan automations-adgang uden at genindføre en
   enkelt global token.
4. **Rank-tracking i dybden**: device, geo, SERP-features (inkl. AI Overviews), konkurrent-positioner,
   alarm ved fald, "quick wins" (position 8–20).
5. **Content optimizer**: term-map fra top 10 → 0–100 score → rangeret fix-liste; re-score publicerede
   artikler for decay.
6. **Keyword-volumen, intent og clustering** (Google Ads API eller DataForSEO).
7. **Backlink-monitorering** via GSC/CSV (referring domains, nye/tabte, anchors, disavow-eksport).
8. **Site-wide change monitoring** med changelog (og evt. screenshot-diff).
9. **Crawler-opgraderinger**: JS-rendering, hreflang, field Core Web Vitals, IndexNow/indexation.
10. **Drift**: job-heartbeat (dead-man's switch), backup/restore i UI, multi-projekt/roller,
    offline dashboard-assets, tag en release.

## Åbne tråde

- Brugeren delte et Claude-share-link (`claude.ai/code/...`). Det kan **ikke** hentes herfra:
  Cloudflare svarer 403 ("Just a moment…") og reader-proxyen afviser IP'en. Afvent at brugeren
  paster indholdet (diff/plan) — og mind dem om at fjerne tokens fra teksten.
- Ingen secrets i repoet: brug `.env` (gitignored) eller miljøvariabler. `GITHUB_TOKEN`,
  `SERPAPI_KEY`, `AIMLAPI_KEY`, `WP_APP_PASSWORD` og `TELEGRAM_*` må ikke committes.
- Vue: hold UI-tekster på dansk, og opdater README + manual + roadmap i samme ændring som koden.
