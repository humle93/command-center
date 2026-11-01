# Command Center v7.11 — Dokumentation og Arkitektur

Teknisk gennemgang af hvordan Command Center er bygget: dataflow, tabeller, jobs, sikkerhed og test.
Brugervejledning findes i [Command_Center_Bruger_og_Systemmanual.md](Command_Center_Bruger_og_Systemmanual.md),
og hvad der er næste skridt i [ROADMAP.md](ROADMAP.md).

## 1. Stack og opbygning

- **FastAPI + Uvicorn** (Python 3.12), Jinja2-skabeloner, SQLite i WAL-mode
- **Alt i én proces**: HTTP-API, server-rendered dashboard (Alpine.js) og APScheduler-jobs
- **Ingen ekstern database eller kø** — `app/data/center.db` er hele tilstanden, med daglig backup
- **Standardbinding**: `127.0.0.1`; bag nginx via `X-Forwarded-*` (se `deploy/nginx-command-center.conf`)

```
app/
  main.py                  # routes, jobs, DB, integrationer (én fil, ~2.900 linjer)
  templates/dashboard.html # hele UI'et (Alpine.js + Chart.js fra CDN)
  templates/login.html     # login/setup, helt selvstændig (ingen CDN)
  data/center.db           # SQLite (gitignored)
  backups/cc-*.db          # daglige + pre-update-backups
  static/                  # oprettes ved start (git kan ikke gemme tomme mapper)
deploy/                    # nginx-config, systemd-units
scripts/smoke_test.sh      # /health, /login, /setup
tests/                     # enhedstests, CI-boot-test, link-audit
install.sh                 # selvstændig installer (indeholder kopier af filerne)
```

## 2. Opstart

1. `load_dotenv()` læses **før** konfigurationsblokken (rigtige miljøvariabler vinder; inline-kommentarer fjernes)
2. `init_db()` → `migrate_db()` → `create_indexes()` køres i `_safe()`, så en fejl ikke kan crashe importen (ét retry, derefter videre)
3. Lifespan registrerer APScheduler-jobs og starter en selvtest i en worker-tråd (DB-skrivetest, nøgler, ruteantal → kritisk alarm ved fejl)
4. Alt netværk går gennem én `requests.Session` med **BudgetAdapter**, der tæller kald til SerpAPI/aimlapi

## 3. Auth-model (v7.11)

| Emne | Implementering |
| --- | --- |
| Brugere | `users(id, username UNIQUE, password_hash, created_at)` |
| Hash | `pbkdf2_sha256$240000$<salt>$<hash>` (salt pr. bruger, `hmac.compare_digest`) |
| Sessioner | `sessions(id=sha256(cookie), user_id, created_at, last_seen, expires_at)`, 30 dage |
| Cookie | `cc_session`, HttpOnly, SameSite=Lax, `Secure` når scheme er https |
| Første bruger | `/setup` — kun åben når `users` er tom |
| Rate limit | 5 fejl pr. IP = 10 min lås (bounded dict) |
| UI-adgang | Middleware sætter `request.state.user`; ikke-loggede sendes til `/setup` eller `/login` |

`APP_TOKEN` er fjernet. Sessioner slettes ved logout, bruger-sletning og adgangskode-skift (bortset fra den aktuelle session).

## 4. Datalag

Tabeller i grupper:

- **Overvågning**: `domains`, `check_history`, `monitors`, `health_history`, `alarms`
- **Alarmer og login**: `alert_outbox` (én række pr. kanal), `login_attempts`
- **SEO**: `seopages`, `crawl_runs`, `keywords`, `keyword_difficulty`, `keyword_ideas`, `content_gap`, `visibility`, `internal_links`
- **Indhold**: `articles`, `backlink_prospects`, `outreach`
- **Drift/integrationer**: `socialqueue`, `competitors`, `linkcheck`, `ai_visibility`
- **System**: `users`, `sessions`, `settings` (nøgle/værdi: moduler, strategi, budget, snapshots, `deployed_commit`, `github_update`), `notes` og `_selftest` (resultat af opstarts-selvtesten)

Alle queries er parameteriserede. `settings` bruges til små tilstande (JSON), så nye funktioner ikke kræver migration.

## 5. Jobs (APScheduler, Europe/Copenhagen)

| Job | Tidspunkt | Guard |
| --- | --- | --- |
| Domæne-tjek | hvert 6. time | modul `domains` |
| Keyword-positioner | 06:00 | modul `keywords` + `SERPAPI_KEY` |
| Growth-autopilot | 05:15 | modul `growth` + `AIMLAPI_KEY` |
| Oprydning | 04:30 | — (lokale ISO-cutoffs) |
| DB-backup | 04:40 | 14 kopier pr. tag |
| GitHub-opdaterings-tjek | 05:00 | `GITHUB_TOKEN` |
| Autopilot-bro (WordPress) | hvert 30. min | modul `autopilot` + WP-creds |
| Alarmkø (`alert_outbox`) | hvert minut | — (leverer med dedupe, backoff og stille timer) |

Modulerne (`MODULES` i `app/main.py`, 11 stk.): `domains`, `keywords`, `ai`, `monitors`, `social`,
`links`, `spy`, `wp_push`, `telegram`, `growth` og `autopilot`. Et slukket modul skjuler UI'et
(`module_labels` i skabelonen) og springer det tilhørende job over.

## 6. Crawler og SEO-analyse

- `analyze_page()` giver 20+ vægtede kontroller (titel, meta, H1/H2, canonical, schema, OG, alt-tekster, læsbarhed, interne links, mixed content, focus keyword) og en score 0-100
- Crawleren følger samme-host-links, gemmer `content_hash` (ændret indhold), `redirects` (kæder/loops) og validerer op til 50 sitemap-URL'er
- Der gemmes **to** crawl-runs: det nye og det forrige, så `/api/crawl/diff` kan sammenligne. Dashboard, duplikat-rapport, redirect-audit og link-forslag læser kun den seneste run
- Ikke-200-sider analyseres uden at hente dem igen (HTML videregives)
- Under crawl rapporterer `/api/crawl/status` `percent`, `eta_seconds` og `elapsed_seconds` (beregnet i `crawl_progress()`); dashboardet poller den og viser fremdrift. Øvrige tunge opgaver bruger estimaterne i `TASK_ESTIMATES`

## 7. Indhold og kvalitetsgate

`generate_article_ai()` bygger prompten ud fra strategien (AdSense/Affiliate/Backlink) og top 5 SERP-resultater.
`quality_check()` er deterministisk: ordantal (min. `QUALITY_MIN_WORDS` eller 80 % af SERP-gennemsnit), fokus-keyword,
mindst 2 H2 — ellers blokeres autopilot-push til WordPress (manuel push giver info-alarm).

Artikel-HTML, der vises i dashboardet, kører gennem `sanitize_article_html()` (allow-list af tags; ingen scripts,
handlers, `javascript:`-links eller billeder), fordi indholdet kommer fra en ekstern AI-model.

## 8. API-budget

`budget_spend()` tælles pr. kalendermåned i `settings` og kaster `BudgetExceeded` **før** kaldet sendes, når loftet er nået.
Alarm (og Telegram) ved 80 % og 100 %. `/health` viser `budget: {serpapi: {used, limit}, ai: {...}}`.

## 9. Opdatering fra GitHub

1. `POST /update/check` → `GET /repos/{repo}/commits?sha=main&per_page=1`, sammenlign med `settings.deployed_commit`
2. `POST /update/apply` → `backup_db_sync(tag="pre-update")` → `GET /repos/{repo}/tarball/{sha}` → `_safe_extract()`
3. `_safe_extract()` skriver kun stier fra `UPDATE_PATHS`-whitelisten og afviser `..`, absolutte stier, symlinks og `.env`
4. Ny commit gemmes i `deployed_commit`; svaret indeholder filantal, `needs_restart` og `requirements_install`
5. Er `requirements.txt` ændret, køres `venv/bin/pip install -r requirements.txt` (best effort, 5 min timeout, output i svaret)
6. Genstart planlægges ~1,5 s efter svaret (så HTTP-svaret når frem): `UPDATE_RESTART_CMD` → systemd `--user` unit → system unit → `scripts/restart.sh` (pidfile + `run.sh`). `UPDATE_AUTO_RESTART=0` slår det fra
7. `/api/update` giver status som JSON; `/api/update/check` og `/api/update/apply` er maskin-endpoints til `scripts/update.sh`; `/self-update` er alias

Den tidligere "hent `install.sh` og kør `bash`"-funktion er fjernet — appen kører ikke længere fjernkode.

## 10. Sikkerhedsnoter

- Adgangskoder: PBKDF2-SHA256 (240k iterationer), salt pr. bruger
- Sessioner: tilfældig 256-bit id, kun `sha256(id)` i DB, HttpOnly + SameSite
- Token-sammenligning: `secrets.compare_digest` (sessioner)
- HTML fra AI/SERP saniteres før `|safe` i skabelonen
- Netværkskald: alle med timeout; budget-guard stopper betalte API'er
- Kendte, ikke-lukkede punkter (se ROADMAP): udgående requests kan pege på private IP'er (SSRF-flade), Telegram-kald sker inde i en åben DB-transaktion, og der er ingen CSRF-token (SameSite dækker cross-site POST)

## 11. Test og CI

- `tests/test_v8_features.py` — in-process tests: kvalitetsgate, API-budget, `/health`, sanitering, pris-monitor, crawl-historik/diff, monitor-input og opdaterings-udtræk (whitelist + traversal)
- `tests/ci_check.sh` — boot mod fake WordPress: opretter bruger via `/setup`, tester anonym adgang (401/303), cookie-login, logout, alle sider, Autopilot-broen og fravær af tracebacks
- `tests/check_paths.py` — hver `action`/`href`/`fetch` i skabelonerne skal matche en route (fanger døde knapper)
- CI kører desuden en diff af `install.sh`s indlejrede kopier mod repo-filerne
- CI fejler, hvis `app/`, `scripts/`, `deploy/`, requirements eller start-/container-filer ændres uden at `README.md` eller `docs/` også er opdateret (`[skip docs]` i commit-beskeden springer tjekket over). `install.sh` er undtaget, fordi den er genereret og tjekkes af paritetstrinnet

## 12. Versionshistorik (kort)

- **v7.11** — brugere/sessioner i stedet for token, GitHub-opdatering, nginx/Ultra.cc-deploy, sanitering + rettelser fra kodegennemgang, link-audit i CI
- **v7.10** — kvalitetsgate, API-budget, rigtig `/health`, CI med fake WordPress
- **v7.9** — DB-backup, opstarts-selvtest, login-rate-limit, HTTPS-advarsel, smoke-test
- **v7.8** — SEO-strategi-vælger med pre-flight-tjek
- **v7.7** — Growth Pack (autopilot, backlink-prospector, keyword-ideer, visibility)
- **v7.5–7.6** — pull-bro, selv-opdatering (senere erstattet), performance (WAL, pooling, gzip)


## 13. Alarmer og outbox (v7.12)

`add_alarm()` skriver alarmen i `alarms` og kalder `enqueue_alert()`, som lægger én række pr.
konfigureret kanal i `alert_outbox` (telegram, email, ntfy, webhook). Der laves ingen
netværkskald i request-stien. `job_drain_alerts` kører hvert minut og leverer ventende rækker:

- **Dedupe:** nøgle = `sha256(type|message)`; en identisk alarm inden for `ALERT_DEDUPE_MINUTES`
  køres ikke igen (uanset kanal).
- **Stille timer:** `in_quiet_hours()` læser `ALERT_QUIET_HOURS` (fx `23-7`, også over midnat).
  Alt under "kritisk" udskydes til `quiet_hours_end_iso()` — det tabes ikke.
- **Backoff:** `ALERT_BACKOFF = [30, 120, 600, 3600]`; efter 5 forsøg markeres rækken `failed`
  med `last_error`, og fejlen vises i UI'et.
- **Webhook:** POST med `webhook-id` (samme på alle forsøg = idempotens), `webhook-timestamp` og
  `webhook-signature: v1,<base64 HMAC-SHA256>` over `"{id}.{timestamp}.{body}"`, secret som
  `whsec_<base64>` (Standard Webhooks). 2xx = leveret, 410 = modtageren er nedlagt.
- **E-mail:** `smtplib` med `SMTP_TLS=starttls` (587) eller `ssl` (465), 15 s timeout, app-adgangskode.

Status findes på `GET /api/alerts/status` (kanaler, kø, problemer) og test på `POST /alerts/test`
(`channel=all|email|ntfy|webhook|telegram`).


## 14. Opstart, login-IP og kørselsrapport (v7.13)

- `NEWEST` (i `app/main.py`) er den ene kilde til "hvad er nyt". `startup_banner()` laver teksten,
  `log_startup()` skriver den til stdout, `app/data/startup.log` og `settings.last_start`, og
  `GET /health` udstiller `newest` + `started_at`. Scripts læser `APP_VERSION` og `NEWEST_LINE` med
  `sed`, saa de ikke kan komme ud af sync med koden.
- Login-spor: `users.last_login_ip`/`last_login_at`, `sessions.ip` (migreres med `ALTER TABLE`) og
  `login_attempts(username, ip, ok, created_at)` med 30 dages oprydning. `client_ip()` tager første
  hop af `X-Forwarded-For` og falder tilbage til socket-adressen.
- `last_run_report()` giver login-siden et bevidst minimalt overblik (ingen alarmtekster eller
  brugernavne, fordi `/login` er offentlig).


## 15. Oprydning (v7.13.1)

Gennemgang med AST: 107 ikke-rute-funktioner, alle refereret mindst to steder - der var ingen døde
funktioner tilbage efter Juno-fjernelsen. `/api/history/{domain_id}` ser ubrugt ud i en ren
tekstsøgning, men kaldes fra dashboardets JS (`fetch('/api/history/' + domainId)`), så den bliver.

Fjernet: ubrugte importer (`Header`, `HTTPException`, `sys`) og den døde lokale `cols = {}` i
`migrate_db`. Tilføjet: `migrate_db` dropper `drift`, `gsc_daily` og `gsc_queries` fra Juno-tiden,
men **kun hvis de er tomme** - en tabel med data røres aldrig.

De 35 `run_in_executor`-kald er bevidst ikke slået sammen til en hjælpefunktion: mønstret varierer
(await, tildeling, fire-and-forget, `loop2`), og en mekanisk omskrivning ville være kosmetisk churn
med risiko for at stall'e event-loopet. Det er dokumenteret her, så det ikke bliver "opdaget" igen.


## 16. Ruteoversigt

Alle ruter registreres i `app/main.py` med `@app.get`/`@app.post`. Undtagen `/setup`, `/login`,
`/health` og `/static` kræver de en indlogget bruger (cookie-session, se §3); API-svar til
`/api/*` er JSON, resten er formular-POST med redirect. `/static` er et mount, og FastAPI tilføjer
selv `/docs`, `/openapi.json` og `/redoc`. `tests/check_paths.py` rapporterer det aktuelle antal
ved hvert CI-løb, så tabellen og koden ikke kan glide fra hinanden ubemærket.

| Område | Ruter |
| --- | --- |
| Opstart og auth | `GET /setup`, `POST /setup`, `GET /login`, `POST /login`, `GET /logout` |
| Brugere | `POST /users/add`, `POST /users/delete`, `POST /users/password` |
| Dashboard | `GET /` |
| Domæner | `POST /domains/check`, `POST /domains/add`, `POST /domains/delete`, `GET /api/history/{domain_id}` |
| SEO og crawl | `POST /seo/audit`, `POST /seo/crawl`, `POST /seo/crawl/delete`, `POST /seo/linksuggest`, `POST /seo/rewrite`, `GET /api/crawl/status`, `GET /api/crawl/diff`, `GET /api/sitemap.xml`, `GET /api/redirects`, `GET /api/duplicates` |
| Keywords | `POST /keywords/add`, `POST /keywords/delete`, `POST /keywords/check`, `POST /keywords/ideas`, `POST /keywords/difficulty`, `GET /api/visibility` |
| Artikler | `POST /articles/generate`, `POST /articles/push`, `POST /articles/delete`, `POST /articles/autopilot`, `POST /articles/meta`, `POST /articles/score` |
| Vækst | `POST /backlinks/prospect`, `POST /backlinks/delete`, `POST /outreach/scan`, `POST /serp/discover`, `POST /serp/gap`, `POST /competitors/delete` |
| Links, social og bro | `POST /links/check`, `POST /social/add`, `POST /social/delete`, `GET /social/export.csv`, `POST /social/to-autopilot`, `POST /autopilot/sync` |
| Monitors og historik | `POST /monitors/add`, `POST /monitors/delete`, `POST /monitors/check`, `GET /api/health-history` |
| Alarmer | `POST /alarms/resolve`, `POST /alerts/test`, `GET /api/alerts/status` |
| AI | `POST /ai/visibility` |
| Indstillinger og noter | `POST /settings/module`, `POST /settings/strategy`, `POST /notes/add`, `POST /notes/delete` |
| Drift og opdatering | `GET /health`, `GET /api/update`, `POST /update/check`, `POST /update/apply`, `POST /api/update/check`, `POST /api/update/apply`, `POST /self-update` (alias) |

