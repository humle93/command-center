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
| Maskin-adgang | `JUNO_TOKEN` + `X-CC-Token` giver **kun** `/api/*` (POST begrænset til bridge-push) |
| UI-adgang | Middleware sætter `request.state.user`; ikke-loggede sendes til `/setup` eller `/login` |

`APP_TOKEN` er fjernet. Sessioner slettes ved logout, bruger-sletning og adgangskode-skift (bortset fra den aktuelle session).

## 4. Datalag

Tabeller i grupper:

- **Overvågning**: `domains`, `check_history`, `monitors`, `health_history`, `alarms`
- **SEO**: `seopages`, `crawl_runs`, `keywords`, `keyword_difficulty`, `keyword_ideas`, `content_gap`, `visibility`, `internal_links`
- **Indhold**: `articles`, `backlink_prospects`, `outreach`
- **Drift/integrationer**: `gsc_daily`, `gsc_queries`, `drift`, `socialqueue`, `competitors`, `linkcheck`, `ai_visibility`
- **System**: `users`, `sessions`, `settings` (nøgle/værdi: moduler, strategi, budget, snapshots, `deployed_commit`, `github_update`)

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
| Pull-bro (bridge/pending) | hvert `BRIDGE_POLL_MINUTES` | modul `bridge` + `GITHUB_TOKEN` |

## 6. Crawler og SEO-analyse

- `analyze_page()` giver 20+ vægtede kontroller (titel, meta, H1/H2, canonical, schema, OG, alt-tekster, læsbarhed, interne links, mixed content, focus keyword) og en score 0-100
- Crawleren følger samme-host-links, gemmer `content_hash` (ændret indhold), `redirects` (kæder/loops) og validerer op til 50 sitemap-URL'er
- Der gemmes **to** crawl-runs: det nye og det forrige, så `/api/crawl/diff` kan sammenligne. Dashboard, duplikat-rapport, redirect-audit og link-forslag læser kun den seneste run
- Ikke-200-sider analyseres uden at hente dem igen (HTML videregives)

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
- Token-sammenligning: `secrets.compare_digest` (både session og `JUNO_TOKEN`)
- HTML fra AI/SERP saniteres før `|safe` i skabelonen
- Netværkskald: alle med timeout; budget-guard stopper betalte API'er
- Kendte, ikke-lukkede punkter (se ROADMAP): udgående requests kan pege på private IP'er (SSRF-flade), Telegram-kald sker inde i en åben DB-transaktion, og der er ingen CSRF-token (SameSite dækker cross-site POST)

## 11. Test og CI

- `tests/test_v8_features.py` — in-process tests: kvalitetsgate, API-budget, `/health`, sanitering, pris-monitor, crawl-historik/diff, monitor-input og opdaterings-udtræk (whitelist + traversal)
- `tests/ci_check.sh` — boot mod fake WordPress: opretter bruger via `/setup`, tester anonym adgang (401/303), cookie-login, logout, alle sider, Autopilot-broen og fravær af tracebacks
- `tests/check_paths.py` — hver `action`/`href`/`fetch` i skabelonerne skal matche en route (fanger døde knapper)
- CI kører desuden en diff af `install.sh`s indlejrede kopier mod repo-filerne

## 12. Versionshistorik (kort)

- **v7.11** — brugere/sessioner i stedet for token, GitHub-opdatering, nginx/Ultra.cc-deploy, sanitering + rettelser fra kodegennemgang, link-audit i CI
- **v7.10** — kvalitetsgate, API-budget, rigtig `/health`, CI med fake WordPress
- **v7.9** — DB-backup, opstarts-selvtest, login-rate-limit, HTTPS-advarsel, smoke-test
- **v7.8** — SEO-strategi-vælger med pre-flight-tjek
- **v7.7** — Growth Pack (autopilot, backlink-prospector, keyword-ideer, visibility)
- **v7.5–7.6** — pull-bro, selv-opdatering (senere erstattet), performance (WAL, pooling, gzip)
