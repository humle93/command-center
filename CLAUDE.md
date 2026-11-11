# Command Center — statusnotat til Claude

**Opdateret:** 11. november 2026 · **Version:** 7.28.0 · **Branch:** `main` · **Seneste commit:** se `git log -1`
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
bash scripts/update.sh --version    # filer vs. koerende proces vs. install.sh (kode 1 ved uenighed)
```

Seneste kendte status: **begge suites ALL PASS**, og GitHub Actions (`.github/workflows/ci.yml`)
kørte grønt på `627cd87`. CI tjekker desuden at alle 17 indlejrede filer i `install.sh` matcher repoet.

## Ændringer i denne arbejdsperiode

### Ultra.cc uden Cloudflare (v7.28.0) — implementeret
- **Baggrund:** ønsket var "Fjern Cloudflare og lav almindelig login via Ultra cc serveren". Koden havde ingen Cloudflare-afhængighed; tunnellen (`trycloudflare`, ny URL ved hver genstart) fandtes kun fordi appen ikke kunne ligge på en understi, og Ultra.cc's nginx kun giver `location /<app>/` på `https://<bruger>.<server>.usbx.me` (filerne i `~/.apps/nginx/proxy.d/` er location-blokke, ikke `server { }` — den gamle vejledning var forkert der).
- **Nyt:** `cc_base_path()` → `CC_BASE_PATH` (env, ellers stien fra `CC_PUBLIC_URL`). `BasePathMiddleware` (ren ASGI, mellem GZip og `auth_middleware`) stripper `/cc` ind, sætter det på `Location`, `Set-Cookie Path`, `href/action/src/formaction` i HTML og injicerer `window.CC_BASE` + en `fetch`-indpakning. `/cc` → 307 `/cc/`. Uden understi: intet ændret. `ccEstimate` i dashboardet stripper præfikset.
- **Ny fil:** `deploy/nginx-ultracc-proxy.conf` (kun location-blokke, `X-Forwarded-Proto https` fast, ingen strip). Ikke indlejret i `install.sh` (kommer med self-update via `deploy/`).
- **Docs:** `docs/Installation_og_udrulning.md` §2e (stop/fjern `cloudflared`: proces, systemd, cron, screen/tmux; port, `.env`, nginx, fejlfinding), README, manual, migreringsplan §3.2, arkitektur §7c2, roadmap.
- **Script:** `scripts/ultracc_setup.sh --url … [--port N] [--keep-tunnel] [--apply]` gør §2e: stopper `cloudflared` (systemd `--user`, crontab fra backupfil, processer), retter fire `.env`-nøgler med backup, skriver nginx-blokken, `app-nginx restart`, `scripts/restart.sh`, tjekker `/health` og `<url>/login`. Uden `--apply` skrives intet. Ikke i `install.sh` (som `user_create.py`); kommer med self-update. Afprøvet end-to-end i en sandkasse med falske `systemctl`/`crontab`/`app-nginx`/`app-ports`, en rigtig `cloudflared`-navngivet proces og rigtig uvicorn bag en curl der efterligner nginx: alle skridt ok, anden crontab-linje bevaret, `.env`-mode bevaret, anden kørsel idempotent. Kapløbet `crontab -l | … | crontab -` blev fundet her og rettet.
- **Direkte på IP (brugerens ønske: "bare en IP, ingen Cloudflare, ingen token"):** `ultracc_setup.sh --ip [adresse]` — `CC_HOST=0.0.0.0`, `CC_PUBLIC_URL=http://<ip>:<port>`, ingen nginx. Tre fund undervejs: (1) `client_ip()` stolede på `X-Forwarded-For` fra alle → login-låsen kunne omgås direkte på IP'en (vist live mod den gamle kode: rigtig kode slap igennem efter 5 forfalskede fejl; nu 429). Rettet med `TRUSTED_PROXIES`. (2) Begge systemd-enheder havde `--host 127.0.0.1 --port 8000` hardkodet og ignorerede `.env` → nu `sh -c` med standardværdier (`CC_HOST:-127.0.0.1` osv., `$$` i unit-filen); scriptet skifter en gammel installeret enhed ud. (3) `pkill -f cloudflared` ramte enhver proces med ordet i kommandolinjen (dræbte test-shellen) → `-x`. `systemd-analyze verify` kan ikke køre i containeren (ingen manager); udvidelsen er tjekket ved at køre linjen med `sh`.
- **Kun offentlig adresse (brugerens næste ønske: "heller ikke en lokal netværks-IP — offentlig, som et eget domæne"):** `--ip` afviser nu private/CGNAT/loopback/link-local/multicast (før: advarsel); ny `--domain <navn>` slår A-posten op (`getent ahostsv4`, `CC_SETUP_RESOLVE` i test), kræver offentlige IP'er, giver NAT-bemærkning ved anden IP end netkortet, og port < 1024 kun som root (`CC_SETUP_UID` i test; adressen uden `:80`). Afprøvet end-to-end: login over `http://<testdomæne>:18771` (curl `--resolve` mod containerens IP, da containeren ingen DNS har) → 303 + dashboard 200. Domænets rigtige A-post er ikke slået op herfra.
- **CI-rettelse (PR #8):** `[skip docs]`/`[skip screenshots]` læses fra `HEAD_SHA` (PR-head), ikke merge-committen.
- **Test:** 16 `understi:`- og 8 `ultracc:`-checks i `tests/test_v8_features.py`; live afprøvet med uvicorn + `Host`/`X-Forwarded-Proto` som nginx sender (login → Secure-cookie `Path=/cc`, dashboard 200, alle absolutte stier præfikset, `/cc/api/*` og `/cc/static/*` 200).
- **Ikke verificeret:** rigtig nginx på Ultra.cc (ingen nginx i containeren) og at `app-ports`/`app-nginx` hedder sådan på brugerens server; selve `cloudflared` på `laser` er ikke rørt herfra — det er en manuel trin i §2e.

### Samlet installationsmanual (11. november) — kun dokumentation
- **Baggrund:** ønsket var "mangler installationsmanual eller script" for de tre dele, der hænger sammen efter v7.25-7.27.
- **Nyt:** [`docs/Installation_og_udrulning.md`](docs/Installation_og_udrulning.md) — rækkefølge (plugin 7.76.0 → CC 7.27.0 → wp-auto-deployer), forudsætninger, manuel plugin-upload (repoet er privat, så *Update now* virker ikke), flytning til OpenRouter med knappen *Switch to OpenRouter now*, `update.sh` + de nye `.env`-linjer, forbindelse af login-knappen (samme e-mail kræves), tjekliste, fejlfindingstabel og rollback. README og roadmappens dokumentoversigt linker til den.
- **wp-auto-deployer** fik samtidig `scripts/install.sh` (venv, `.env` med operatør-nøgle, database, `--service`, `--nginx`, `--check`) og en Authorize-knap i `/docs` — se det repo.
- Ingen kodeændring her; `install.sh` er regenereret, fordi README er indlejret.

### Log ind fra WordPress med ét klik (v7.27.0) — implementeret
- **Baggrund:** ønsket var "en log ind i Command Center-knap i Steamgears-pluginnet". Fundet: det gamle engangslink (v7.17.5) sendte til `POST /sgap/v1/login-link`, en rute pluginnet **aldrig** har haft (`git log -S login-link -- plugins` er tom i steamgears-site), så knappen kunne aldrig virke.
- **Nyt flow:** `cc_sso_secret()` (settings `cc_sso_secret`, `token_urlsafe(48)`), `cc_sso_push()` sender `{url: CC_PUBLIC_URL, secret, version}` til `POST /sgap/v1/cc-link` — i `sgap_sync()` kun når fingerprint (sha256 af url+nøgle) har ændret sig eller snapshottet siger `command_center.sso = false`, og med `force=True` fra knappen i Social (`/autopilot/login-link`, samme rute som før). `GET /cc-sso?t=` → `cc_sso_verify()`: HMAC først, `v=1`, levetid ≤ 120 s, ±30 s ur-forskel, `jti` i tabellen `sso_used`, kendt e-mail. Ingen ny konto oprettes.
- **Låsen:** afviste billetter tæller i `_LOGIN_FAILS` (5 = 10 min.), og `/login?sso=<årsag>` forklarer (tekster i `CC_SSO_REASONS`). Login fra WordPress logges som info-alarm.
- **Fjernet:** `cc_login_issue`, `cc_login_consume`, `CC_LOGIN_*`, `GET /cc-login` og `/cc-login` i middlewarens undtagelser; `fake_wp.py` har `/cc-link` i stedet for `/login-link`.
- **Pluginnet:** Steamgears Autopilot 7.76.0 (`beaffa1` på steamgears-site; bygget som 7.72.0 og flyttet oven på main's 7.75.0) har ruten, billetten og knappen, og P10 flytter samtidig pluginnet til OpenRouter som standard.
- **Test:** 25 `sso:`-checks i `tests/test_v8_features.py`, 7 i `tests/ci_check.sh`, og et interop-tjek kørt i sessionen: en billet lavet af pluginnets egen `SGAP_CC::ticket()` (PHP) blev godkendt af `cc_sso_verify()`, og anden gang afvist som `brugt`. Interop-tjekket ligger ikke i CI (repoet har ikke pluginnet).
- **Ikke verificeret:** et klik på det levende site — kræver at 7.76.0 er installeret og `CC_PUBLIC_URL` er sat på serveren.

### Chat med MCP-connectors (v7.26.0) — implementeret
- **Baggrund:** ønsket var "en separat chat-sektion med connector-MCP til GitHub, WordPress, Gmail, Google Drive og andre nyttige WordPress-sider".
- **Fanen 💬 Chat** (`tab=chat`, nav-gruppe med Cockpit): samtaleliste, valg af connectors pr. samtale, tråd med værktøjskald/svar, gule godkendelseskort og en connector-sektion (tabel + formular med skabeloner).
- **MCP-klient i `app/main.py`:** `mcp_open`/`mcp_request`/`mcp_list_tools`/`mcp_call_tool` (Streamable HTTP, JSON og SSE, `Mcp-Session-Id`, genåbning ved 404, `nextCursor`). Egen session `MCP_HTTP` (ikke budget-adapteren), `assert_public_url` + ingen redirects.
- **Skabeloner (`CONNECTOR_PRESETS`):** GitHub (`api.githubcopilot.com/mcp/`, PAT), Steamgears (`WP_URL/wp-json/mcp/novamira`, login `wp_env` = `WP_USER`/`WP_APP_PASSWORD`), WordPress MCP Adapter, WordPress.com, Gmail, Google Drive og "Anden". De fire sidste har bevidst ingen fast URL: de kræver OAuth hos udbyderen, og OAuth-flowet er ikke bygget (står i roadmappen under "Senere").
- **Godkendelse:** kun `readOnlyHint=true` kører automatisk; resten går i `chat_pending`. `chat_decide` låser med rowcount (dobbeltklik = én kørsel), samtaler er pr. bruger, og godkendte kald logges som info-alarm.
- **Chat-løkken:** `openrouter_complete()` (ny; `ai_chat()` er nu en tynd wrapper) med tools; højst `CHAT_MAX_STEPS = 8` runder og `CHAT_MAX_TOOLS = 80`. Ugyldige argumenter og ukendte værktøjer bliver tool-svar, ikke kald.
- **Nye tabeller:** `mcp_connectors`, `chat_conversations`, `chat_messages`, `chat_pending` (i `migrate_db`).
- **Nye ruter (9):** `GET /api/chat/state`, `GET /api/chat/{cid}`, `POST /chat/send|approve|delete`, `POST /connectors/add|refresh|toggle|delete`. `/connectors/add` og `/connectors/refresh` har `TASK_ESTIMATES`.
- **Test:** 45 checks i `tests/test_v8_features.py` mod en fake MCP-server (`_FakeMcp`: JSON/SSE, session, to sider, 401) og en fake OpenRouter: validering, SSRF, nøgler aldrig i UI/HTML/state, auto-kørsel af læseværktøj, godkend/afvis, dobbelt godkendelse, ukendt værktøj, loft, anden bruger.
- **Screenshots:** `scripts/screenshots.py` har `chat` i `TABS` og læser `CC_CHROMIUM_PATH`; alle 16 billeder er taget igen mod v7.26 (med demo-connectors mod en lokal fake MCP-server).
- **Ikke verificeret her:** kald mod de rigtige servere (GitHub, WordPress, Google) — containerens netværk tillader dem ikke. Kendt begrænsning: nøglerne ligger i klartekst i databasen (og i backups).

### AI via OpenRouter i stedet for aimlapi (v7.25.0) — implementeret
- **Baggrund:** ønsket var "Tilføj openrouter api i stedet for aimlapi". aimlapi er fjernet; der er ingen fallback til den gamle nøgle (den virker ikke mod OpenRouter).
- **Konfiguration:** `OPENROUTER_API_KEY` (erstatter `AIMLAPI_KEY`), `AI_MODEL` (nu en OpenRouter-slug, default uændret `google/gemini-3-8-flash`) og valgfri `OPENROUTER_BASE_URL` (default `https://openrouter.ai/api/v1`).
- **Ét kald:** `ai_chat(prompt, max_tokens, timeout)` er eneste vej til modellen; `generate_article_ai()` og outreach-draften brugte før hver sin kopi af `HTTP.post`. Den sender `X-Title: Command Center` og `HTTP-Referer: CC_PUBLIC_URL` (når sat), læser OpenRouters `error`-objekt før `choices` og kaster `AIError` (en `RequestException`), så de eksisterende `except`-grene fanger den.
- **Budget:** `API_BUDGETS["ai"]` tæller værtsnavnet fra `OPENROUTER_BASE_URL` (`openrouter.ai`), ikke `aimlapi.com`.
- **Gammel nøgle:** `warn_legacy_aimlapi()` i lifespan giver `[cc] advarsel:` + alarm (`ai`), når kun `AIMLAPI_KEY` er sat.
- **Test:** 15 `openrouter:`-checks i `tests/test_v8_features.py` (URL, headers, model/max_tokens/timeout, budget, fejl i 200-svar, 401 uden nøgle i teksten, tomt choices, tom besked, ikke-JSON, ingen Referer uden `CC_PUBLIC_URL`, advarsel, ingen `aimlapi.com` i koden).
- **Ikke verificeret her:** et rigtigt kald til openrouter.ai (containerens proxy afviser værten), og om slug'en `google/gemini-3-8-flash` findes hos OpenRouter — tjek den på openrouter.ai/models og sæt `AI_MODEL` efter behov.
- **Screenshots:** dashboardets AI-tekster er ændret, men `docs/img/` er ikke fotograferet om (commit med `[skip screenshots]`).
- **Lokal testkørsel i en container uden DNS:** `NO_PROXY=127.0.0.1,localhost,testserver` og en `sitecustomize.py`, der giver ukendte navne en offentlig IP; ellers fejler SSRF-tjekkene på `example.com`/`example.dk` (det sker også på main).

### Vækst uden API-nøgle + moderniseret UI (v7.24.0) — implementeret
- **Baggrund:** ønsket var "Surfer SEO, Ahrefs, Semrush og BabyLoveGrowth — vores egen version uden API-nøgle". Svaret er en lokal motor, ikke en kopi: vi kan måle tekst, men ikke genskabe deres webindekser.
- **Nyt i `app/main.py`:** `local_content_optimizer()` (vægtet 0-100-score, termdækning, prioriterede fixes), `content_profile()`/`content_top_terms()`/`term_stats()` (hele ord, dansk+engelsk stopord), `compare_with_competitors()` (op til 3 brugerangivne URL'er gennem `safe_request()`), `brief_from_keyword()` (mål for ord/H2 fra konkurrenternes snit, ellers 1200 ord/5 H2) samt `fetch_page_html()`.
- **Nye tabeller:** `content_briefs`, `link_targets` (`url` unik) og `content_audits` (de sidste 50 målinger). De oprettes i `migrate_db`, så eksisterende installationer også får dem.
- **Nye ruter (8):** `/growth/optimize`, `/growth/compare` (JSON til `fetch`), `/growth/brief`, `/growth/brief/status`, `/growth/brief/delete`, `/links/target/add`, `/links/target/status`, `/links/target/delete`. Alle tre tunge har poster i `TASK_ESTIMATES`.
- **UI:** ny fane **🚀 Vækst** med fire kort (optimerer, sammenligning, plan, linkliste). Derudover er skallen moderniseret: navigationen er delt i fem grupper med tydelig aktiv fane, hver fane har titel + beskrivelse øverst (`ccTabInfo`), og kort, felter, knapper, tabeller og fremdriftskort har fået én fælles visuel rytme via et designlag i `<style>`. Alle id'er og tekster, som tests og JS læser (`#cc-task`, `border-red-500/40`, `border-sky-500/40`, `Database-backup`, `Kladder venter` …), er bevaret.
- **Test:** 27 nye checks i `tests/test_v8_features.py` (score høj/lav, hele ord, termlister, toptermer, ruter uden `SERPAPI_KEY`/`AIMLAPI_KEY`, konkurrent-gab mod den lokale testserver, briefs, status, sletning, linkliste og dubletter) og 15 i `tests/ci_check.sh`.
- **Bevidst udeladt:** søgevolumen, sværhedsgrad, placeringer og backlink-profiler. Det kræver et eksternt indeks og står stadig i roadmappen.
- **`install.sh` er regenereret** (EOF_MAIN, EOF_HTML, EOF_README), så versionspariteten i CI er grøn.

### Backup/restore i UI (v7.23.0) — implementeret
- Fanen Moduler viser backup-kortet: `POST /backup/now` tager en `manuel`-backup, og `POST /backup/restore` gendanner en fil fra `backups/` når feltet `confirm` er `GENDAN`.
- Kun filer på formatet `cc-<tag>-YYYYMMDD-HHMM.db` accepteres (`_backup_path`). `_check_backup_file` kører `PRAGMA integrity_check` og kræver tabellen `users`. `restore_backup_sync` tager altid en `pre-restore`-backup først og afbryder, hvis den fejler.
- Test: "Backup og restore i UI" i `tests/test_v8_features.py`.

### Offline dashboard (v7.22.0) — implementeret
- Tailwind (play-CDN), Alpine og Chart.js ligger i `app/static/vendor/` og indlæses fra `/static/vendor/`. Dashboardet henter intet eksternt. `.gitignore` undtager `vendor/` fra `app/static/*`.
- Test: "Offline dashboard" i `tests/test_v8_features.py`.

### CSRF og session-rotation (v7.21.0) — implementeret
- `auth_middleware` afviser muterende kald med `Sec-Fetch-Site` fra et andet site eller `Origin` der ikke matcher `Host` (403). Kald uden browser-headers passerer. `/mcp` har egen kontrol.
- `start_session(user_id, ip, old_sid)` sletter den gamle sid ved login.
- Tests: blok "CSRF og session-rotation (roadmap 2)" i `tests/test_v8_features.py`.

### Budget og job-heartbeat (v7.20.0) — implementeret
- Cockpit viser "💳 API-budget denne måned" (`budget_rows` fra `budget_usage()`, samme tal som `/health`) og "⏱️ Planlagte jobs (heartbeat)" (`job_rows` fra `job_status()`).
- Alle 8 scheduler-jobs er pakket i `job_heartbeat(job_id, fn)`, som skriver `job_<id>_last_start/last_end/last_status` i `settings`. Async jobs pakkes som async, så APScheduler stadig ser coroutines.
- `job_heartbeat_check()` (hvert 15. min.) alarmerer forsinkede (`JOB_MAX_AGE_HOURS`) og fejlede jobs én gang pr. tilstand; tilstanden ligger i `settings.job_alarm_<id>`. Et aldrig-kørt job tæller først efter appens `last_start` er ældre end grænsen.
- 1 ny sektion i `tests/test_v8_features.py`, 2 checks i `tests/ci_check.sh`.

### SSRF-beskyttelse (v7.19.0) — implementeret
- `assert_public_url()` afviser loopback, private net, link-local (169.254.169.254), reserverede/multicast-adresser og navne som `.local`/`.internal`; den slår også værtsnavne op og afviser, hvis **nogen** adresse bag navnet er intern (DNS-rebinding). `BlockedURL` er en `ValueError`, så de eksisterende formular-grene fanger den.
- `safe_request()` følger viderestillinger manuelt (max 3 hop) og tjekker **hvert** hop — ellers kunne en 302 pege ind i det lokale net. `normalize_url()` tjekker med, så afvisningen sker før URL'en gemmes.
- `CC_SSRF_ALLOW=a,b` er den eneste undtagelse (fx en intern side under udvikling); testene bruger den til 127.0.0.1. 6 nye checks i `tests/test_v8_features.py`.

### WordPress-broen set fra begge sider (v7.18.0) — implementeret
- `sgap_api()` sender nu `X-Command-Center: <APP_VERSION>` (ny `sgap_headers()`). **Uden den header
  noterede pluginnet intet** — `SGAP_CC::note_call` kræver den — så WordPress-kortet ville altid sige
  "not yet", og CC kunne ikke se, om dets egne kald nåede frem.
- `sgap_sync()` henter også `/snapshot` og gemmer `status.command_center` (`ts`, `version`,
  `last_route`, `user`, `last_seen`) i `settings.sgap_snapshot`. Et ældre plugin uden ruten (før 7.33)
  vælter ikke synken; så forklares det i stedet.
- `cc_age_text()` / `cc_seen_view()` regner alderen ud **ved visning** (45 min. = misset runde, 2 t =
  tavs), og fanen Social viser WordPress' eget svar: "WordPress hørte sidst fra Command Center for
  12 min. siden" + version, rute og bruger. Samme tal som pluginnets kort (7.33.3), så de to sider
  ikke kan vise hver sin sandhed.
- Tests: 7 nye checks i `tests/test_v8_features.py` og 2 i `tests/ci_check.sh`; fake-WP har fået
  `/snapshot` og gemmer `X-Command-Center` i `<state>.cc`, så CI ser headeren.
### Release v7.20.0: `.env`-forløbet samlet (5. november)
- **Efter fletningen:** toppunktet i `NEWEST` er **7.23.0**, og `.env`-forløbet står som ét punkt på 7.19.0-linjen. Testen tjekker derfor mod `APP_VERSION` og mod det punkt, ikke mod indeks 0.
- **Hvad:** versionsbump til 7.20.0 og ét samlet nyhedspunkt i `NEWEST` i stedet for fire (7.18.0, 7.18.1, 7.19.1, 7.19.2). `NEWEST` er det, opstartsbanneret, `/health` og login-siden viser, så brugeren nu ser hele historien som én linje: “Standardbrugeren i .env: oprettes ved deployment, advarer naar koden er foraeldet, rydder linjen selv og viser rydningen i dashboardet”.
- **README:** afsnittet hedder nu “Nyheder i v7.20” og indledes med det samlede forløb, hvor de fire trin står som underpunkter. Titlen er `v7.20 PRO`.
- **Uændret:** al adfærd, ruter, tabeller og tests. De fire trin står stadig enkeltvis i `docs/Command_Center_Dokumentation.md` og i ROADMAP-tabellen, så historikken ikke er rørt.
- **Verifikation:** `tests/test_v8_features.py` tjekker at toppunktet er 7.20.0, at der kun er ét `.env`-nedslag tilbage, og at login-siden viser den samlede linje.

### Rydningen vises i dashboardet (5. november, v7.19.2)
- **Baggrund:** efter v7.19.1 var linjen væk — men der var ingen steder at se, at det var sket med vilje, eller hvem der skiftede koden.
- **Nyt:** `clear_env_admin_password()` gemmer `{at, by, account}` i `settings` under `env_password_cleared` (kun navn og tidspunkt, aldrig koden), og `env_password_notice()` læser den tilbage til en blå bjælke øverst i dashboardet: “CC_ADMIN_PASSWORD blev fjernet fra .env 5. november 2026 kl. 23:19 af henning — filen kan ikke blive forældet”.
- **Ærlig tilstand:** `env_admin_password_in_file()` læser `.env` selv (ikke miljøvariablen, der blev læst ved opstart), så en linje, der er sat tilbage, bliver sagt højt: baren skifter til “står i .env igen”. Forældet kode overlader baren til den røde advarsel, og uden en gemt rydning (fx ny installation) vises den ikke.
- **Verifikation:** `tests/test_v8_features.py` har ni “visning:”-tjek (navn/tidspunkt, ingen koder i teksten, blå bjælke i HTML, dansk tidsformat, tilbageført linje, ingen rydning, i stykker skrevet række).
- **Bemaerk:** tidsformatet er `danish_time()` (“5. november 2026 kl. 23:19”), som kan bruges andre steder i UI'et.

### `.env` rydder sig selv ved kodeskift (5. november, v7.19.1)
- **Baggrund:** advarslen i v7.18.1 fortalte, at linjen var forældet — men den blev stående, til nogen
  rettede den. Nu fjerner appen årsagen selv.
- **Nyt:** `POST /users/password` kalder `clear_env_admin_password(me["email"])`. Den gør kun noget, når
  kontoen er `CC_ADMIN_EMAIL`, og når den gemte hash **ikke** længere matcher `.env`-koden (så et skift
  til samme kode lader filen være). Den tømmer `CC_ADMIN_PASSWORD=` med regex på nøglen, skriver via
  `ENV_PATH + ".tmp"` og `os.replace` (filmode bevaret, `\r\n` bevaret), sætter miljøvariablen til tom og
  nulstiller `_ENV_PASSWORD_STATE`. Status: `fjernet`, `passer-endnu`, `ikke-standardbruger`,
  `ingen-linje`, `ingen-fil`, `fejl: …`.
- **Sikkerhed:** kun den ene linje ændres — kommentarer og de andre nøgler er urørte, og hverken den
  gamle eller den nye kode ender i filen, loggen eller alarmen. Fejler skrivningen (fx skrivebeskyttet
  `.env` i en container), kommer der en advarsel i `alarms`, og kodeskiftet gennemføres alligevel — så
  bliver v7.18.1-bjælken stående som fallback.
- **Test:** ni checks i `tests/test_v8_features.py` (tomning, urørte nøgler/kommentarer, ingen kode i
  filen, advarsel + bjælke væk, andre brugere, uændret kode, skrivefejl → alarm).

### Autopilot-broen: hele `/snapshot`, WP-Cron-ping og `X-Command-Center` (5. november, v7.19.0)
- **Beslutning:** koblingen til Steamgears Autopilot forbliver **envejs** (CC → site, roadmappens punkt
  #5 i steamgears-site): CC læser `GET /snapshot` og sender kladder med `POST /drafts`. Ingen pairing-kode
  og intet kald fra sitet til CC, som stadig kun lytter på 127.0.0.1.
- **Nyt i `sgap_sync()`:** prøver `/snapshot` først (`sgap_from_snapshot()` oversætter til det gamle
  format + `version`, `paused_because`, `cron_lag_minutes`, `problems`, `self_check_at`,
  `missing_tables`, `source`). Ved 404 bruges `sgap_from_stats()` (det gamle `/stats` + `/drafts`).
  Lagring og alarmer ligger i `sgap_store()`; nye selvtjek-problemer og manglende tabeller alarmerer kun
  ved ændring i forhold til forrige snapshot.
- **`sgap_api()`** sender altid `X-Command-Center: APP_VERSION`. Pluginnet 7.33+ noterer det
  (`sgap_cc_seen`) og melder i sit selvtjek, når CC har været tavs i over 2 timer.
- **`job_wp_cron()`** kalder `wp-cron.php?doing_wp_cron` hvert 5. min (samme betingelse som broen),
  så pluginnets job ikke venter på besøgende. Fejl er tavse med vilje.
- **Dashboardet** viser pluginversion, pause-årsag, cron-forsinkelse (≥ 30 min) og selvtjek-listen.
- **Tests:** `tests/test_v8_features.py` (oversættelse, sortering, tomt svar, ping-sti og header) og
  `tests/ci_check.sh` (snapshot-kilde, version, header, dashboard, alarm én gang, reserve til `/stats`).
  `tests/fake_wp.py` har fået `/snapshot`, `wp-cron.php`, tilstanden `old` og logger headeren.

### Advarsel når `.env`-koden er forældet (5. november, v7.18.1)
- **Baggrund:** `CC_ADMIN_PASSWORD` bruges kun ved seed. Skiftes koden under **Brugere**, lover `.env`
  stadig den gamle — og man kunne fristes til at "rette" kontoen tilbage til den.
- **Nyt:** `env_password_mismatch()` verificerer koden mod den gemte PBKDF2-hash og returnerer en
  advarselstekst med e-mailen (aldrig koden). Svaret caches på `(email, sha256(kode), hash)`, så
  dashboardet ikke betaler 240k iterationer ved hvert sidevisning. `warn_stale_env_password()` kaldes i
  lifespan og lægger advarslen i `alarms` (dedupe som de andre) + `[cc] advarsel: …` i opstartsloggen.
- **Dashboardet:** `env_password_warning` i konteksten giver en **rød** bjælke over den gule
  `must_change_password`-bjælke. Advarslen ændrer intet ved kontoen.
- **Tests:** `tests/test_v8_features.py` (seks checks: advarsel, e-mail i teksten, ingen kode i teksten,
  baren, alarmen, og at begge forsvinder når koden passer) + `tests/ci_check.sh` (ingen falsk advarsel
  uden `CC_ADMIN_PASSWORD`).

### Standardbruger ved deployment (5. november, v7.18)
- **Baggrund:** et nyt deployment startede på `/setup` og krævede, at nogen oprettede den første
  bruger i browseren. Ønsket var en standardkonto, der findes efter deployment, så login er det
  eneste, man møder.
- **Nyt:** `seed_standard_user()` kaldes i `lifespan` (før scheduler og selvtest). Er `users` tom, og
  har `.env` både `CC_ADMIN_EMAIL` og `CC_ADMIN_PASSWORD`, oprettes kontoen med
  `must_change_password=1`, så koden fra `.env` skal skiftes ved første login. Status skrives til
  opstartsloggen (`oprettet` / `findes` / `mangler` / `fejl: …`); en afvist linje giver en advarsel i
  `alarms` i stedet for en tavs opstart.
- **Ingen secrets i repoet:** koden læses kun fra miljøet/`.env`, gemmes som PBKDF2-hash og skrives
  aldrig til log. `install.sh` skriver fortsat kun `.env.example`.
- **Seed kun ved tom tabel:** en rettet `.env`-linje rører ikke en konto i brug (den skal skiftes i
  UI'et eller med `scripts/user_create.py`), så en gammel kode i `.env` ikke kan låse nogen ude.
- **`/setup` er reserve:** uden de to linjer opretter første besøg brugeren som før, og siden lukker
  sig selv, så snart der findes en bruger. `login.html` er skrevet om til ét login-formular med en
  kort note om `.env`-linjerne i stedet for en separat opsætningsmode.
- **Baren i dashboardet:** den gule bjælke ved `must_change_password` siger nu både "fra
  invitationsmailen" og "eller CC_ADMIN_PASSWORD i .env", så en seedet konto ikke får at vide, at
  koden kom med posten.
- **Tests:** `tests/test_v8_features.py` dækker seed, login uden `/setup`, hash (ingen klartekst),
  `must_change_password`, at en rettet `.env` ikke overskriver, og at en ugyldig linje giver alarm;
  `tests/ci_check.sh` tjekker at `/setup` svarer 303, når brugeren findes.

### Migreringsplan for serveren `laser` (4. november)
- **Nyt dokument:** [`docs/Command_Center_Migrering.md`](docs/Command_Center_Migrering.md) er arbejdsinstruksen
  for at flytte `laser`s `~/command-center` fra `Steamgears-site` (v8.3) over på dette repo: fase 0-6,
  stop-punkter, rollback, tjekliste og tidsestimat. Kun dokumentation — ingen kodeændring.
- **Fastsat i planen:** frisk database (v8.3-skemaet er ikke garanteret kompatibelt), fast domæne i
  stedet for `trycloudflare` (URL'en skifter ved hver genstart og `CC_PUBLIC_URL` styrer `/mcp`s
  Host-tjek), og at `install.sh` altid skriver til `$HOME/command-center` — derfor skal den gamle mappe
  flyttes asides før den nye flyttes ind.
- **Efterprøvet:** guard-testen i dokumentets fase 4 er kørt i en isoleret kopi — `--version` gav kode 1,
  `--no-restart` kode 7, og `app/main.py` havde samme `cksum` før og efter.
- **Versioner:** planen er skrevet mod v7.17.2, men er efter rebase på main rettet til v7.19.1, og
  første-login-trinnet nævner nu standardbrugeren fra `CC_ADMIN_EMAIL` + `CC_ADMIN_PASSWORD` (v7.18+).

### Versionskontrol: filer, proces og installatør (4. november)
- **Baggrund:** på en server lå en gammel `install.sh` (v7.9) i projektmappen, mens processen kørte
  v8.3. At køre den installatør overskrev koden på disken med den gamle version — usynligt indtil
  næste genstart. Paritetstjekket i CI fanger en installatør der ikke matcher repoet, men intet
  sammenlignede *versionerne* i en kørende installation.
- **Nyt:** `bash scripts/update.sh --version` sammenligner tre kilder — `app/main.py` på disken,
  `/health` fra den kørende proces, og `APP_VERSION` i `install.sh`s indlejrede `app/main.py` — og
  stopper med kode 1 ved uenighed med en `forskel`-linje der siger hvad der er galt (genstart
  mangler / installatøren er ældre / filerne er rullet tilbage). Virker uden venv, token og netværk:
  versionen læses med `sed` ud af `/health`, ikke med python.
- `install.sh` henter nu sit versionsnummer fra sin egen indlejrede `app/main.py` i stedet for den
  faste tekst på linje 5, så den ikke kan påstå en anden version end den skriver.
- `tests/ci_check.sh` kører `--version` mod CI-serveren, så tjekket selv er dækket.
- **Guarden i opdateringen:** `installer_guard()` kører i skrive-stierne (`apply` og `--no-restart`)
  *før* venv-, token- og netværkstrinnet. Er `install.sh` ældre end `app/main.py`, skriver
  opdateringen intet og stopper med **kode 7** (2 = venv, 3-6 = tjek/filer/genstart). `--check` og
  `--version` skriver intet og går uden om guarden, så de kan bruges til at diagnosticere. Ingen
  `--force`: vejen ud er `git checkout -- install.sh` (eller `git pull`), som beskeden siger.
  `ci_check` tester både at opdateringen nægter (kode 7) og at den ikke rører `app/main.py`.
- `scripts/update.sh` viser stadig de tre versioner øverst ved en rigtig opdatering, men fejler ikke
  der: under en opdatering *skal* processen være ældre end filerne indtil genstarten.

### `CC_PUBLIC_URL`: hvorfor den kan være tom (4. november)
- **Årsag 1 (den hyppige):** `install.sh` skriver kun `.env.example` — den kopierer aldrig til
  `.env` og spørger ikke om adressen — og self-update rører bevidst aldrig `.env`. En kopieret
  skabelon har derfor `CC_PUBLIC_URL=` fra dag ét, uden at noget siger til.
- **Årsag 2-4 (udfyldt, men virkningsløs), målt med `urlparse`:** `"https://x"` og `x` (uden scheme)
  giver begge `hostname = None` → `/mcp` svarer `421` på alle ikke-lokale værter; en sti
  (`https://x/app`) virker for `/mcp`, men login-linket bliver `…/app/login`.
- **Tom betyder ikke usynlig:** `_mcp_host_allowed()` returnerer `True`, når `CC_PUBLIC_URL` er tom,
  så Host-tjekket (DNS-rebinding) på `/mcp` slås helt fra. Det var ikke dokumenteret som en
  konsekvens, kun som "lokal udvikling virker".
- Retttet i dokumentationen: `.env.example` (format + hvad tom betyder), `README.md`,
  `docs/Command_Center_Bruger_og_Systemmanual.md` (nyt afsnit + tabel pr. skrivefejl) og
  `docs/Command_Center_MCP.md` (hvad man gør ved `421`). Ingen kodeændring — adfærden er den samme.

### Scripts-mappen ryddet op (4. november)
- Alle otte filer i `scripts/` har nu samme header: `navn - formål`, `Brug:`, `Kraever:` og
  `Sidst aendret: 4. november 2026`. Fire bash-scripts skiftede `#!/bin/bash` til
  `#!/usr/bin/env bash`, og `user_create.py` fik eksekverbar-bit (den var 644).
- `bash scripts/update.sh -h` læser nu header-kommentarerne med `awk` i stedet for `sed -n '2,8p'`:
  det faste interval printede `set -u` med og blev forkert, så snart headeren fik en linje mere.
- Bevidst valg: **ingen versionsnumre i headere**. `APP_VERSION` læses dynamisk i `run.sh`,
  `run.bat`, `restart.sh` og `update.sh`; en hardkodet version ville drive som roadmap-punkterne.
  Datoen er et snapshot — `git log -1 -- scripts/<fil>` er sandheden.
- `install.sh` er regenereret for `EOF_UPDATE`, `EOF_RESTART` og `EOF_SMOKE` (17/17 par matcher).

### Drift: version, login-adresse og brugere fra terminalen (4. november)
- `scripts/update.sh` viser nu øverst **hvilken version der kører** (fra `/health`, altså processen) ved
  siden af versionen i filerne, advarer hvis de er forskellige ("genstart mangler"), og skriver
  **login-adressen** (`CC_PUBLIC_URL` + `/login`, dvs. den adresse nginx videresender). Fejlen var, at
  version-blokken nederst i scriptet lå **efter** alle `exit`-kald og derfor aldrig kørte; den er nu en
  funktion (`show_versions`), der kaldes før tjekket og igen efter en genstart.
- `scripts/user_create.py` (nyt): opretter en bruger direkte i DB'en med e-mail, `--username`,
  `--password` (ellers skjult prompt to gange) og `--must-change`. Bruger `create_user()`, så reglen om
  min. 8 tegn og PBKDF2-hashing er den samme som i UI'et. Ikke en del af `install.sh` (som `invite.py`
  og `api_key.py`); filen kommer med ved første self-update.

### Adgang og brugere (v7.15)
- Token-login (`APP_TOKEN`) er fjernet. Første besøg opretter bruger via `/setup` med **e-mail**;
  derefter logger man ind med e-mail + adgangskode (PBKDF2-SHA256, 240k iterationer, salt pr. bruger).
- E-mailen er login-id: `normalize_email()` trimmer, sænker og validerer (max 254 tegn). Migreringen
  (`migrate_db`) ombygger `users` og giver gamle konti `<brugernavn>@local`; `find_user()` accepterer
  stadig det gamle brugernavn, så ingen bliver låst ude. `username` findes kun som legacy-kolonne.
- **Invitation uden tokens:** `POST /users/invite` (fanen Brugere) laver en tilfældig midlertidig
  adgangskode, mailer den med `send_email()` og opretter **først derefter** brugeren med
  `must_change_password=1`. Fejler SMTP, oprettes ingen bruger, og fejlen bliver en alarm.
  `/users/password` rydder flaget; dashboardet viser en gul bjælke indtil da.
- `send_email(to, subject, body)` er fælles for alarmer (`SMTP_TO`) og invitationer (modtageren).
- `invite_user(email, base_url, deliver=None)` kan sende ad en anden vej end SMTP: `scripts/invite.py
  bruger@ditfirma.dk --print` opretter brugeren og udskriver den færdige mail, så den kan sendes fra en
  anden mailkonto (fx Gmail) når `SMTP_HOST` ikke kan sættes op på serveren. Scriptet validerer
  argumenterne **før** `invite_user` kaldes: én adresse ad gangen, `--base-url` til adressen i mailen,
  ukendte flag afvises, og eksempel-adresser (`navn@domaene.dk`, `example.*`) stoppes med mindre
  `--force` — så en pladsholder ikke bliver en rigtig bruger. **Formularen i fanen Brugere bruger samme regel** (`example_email_hint()` i `app/main.py`): `POST /users/invite` svarer `invite_kind=adresse|eksempel|smtp`, forklarer afvisningen i formularen og tilbyder **Opret alligevel** (`force=1`). **Sletning svarer samme sted** (`users_delete_redirect()`): `POST /users/delete` tager `id` som tekst, redirecter til Brugere med `del=ok|fejl` + `del_kind=slettet|sidste|findes-ikke|ugyldig`, forklarer afvisningen i formularen og logger både afvist og gennemført sletning som alarm. **Login fra WordPress (v7.17.5)**: knappen i fanen Social (`POST /autopilot/login-link`) lægger et engangslink i pluginnet via `sgap_api`, og `GET /cc-login?code=…` logger ind med det én gang inden for 10 min. (`settings.cc_login_code` = sha256 + `exp`; koden slettes først når den er godkendt). Broen er stadig CC → site; pluginnet er 7.33.3.
- Sessioner ligger i `sessions` som `sha256(id)`, HttpOnly-cookie `cc_session` (30 dage, `Secure` på https).
- Fane **Brugere**: invitér/slet brugere og skift adgangskode (logger andre sessioner ud).
- Login-lås: 5 fejl pr. IP = 10 min. Adgangskode ≥ 8 tegn; invitationer kræver `SMTP_HOST` + `SMTP_FROM`.
- **Juno er fjernet helt** (se nedenfor): der findes ingen maskin-nøgle, kun bruger-sessioner.

### Hosting
- `run.sh` udskriver den rigtige adresse (LAN-IP når `CC_HOST=0.0.0.0`), understøtter
  `CC_HOST` / `CC_PORT` / `CC_PUBLIC_URL` og skriver pidfile `app/data/cc.pid`.
- `deploy/nginx-command-center.conf` (proxy-headers, `proxy_read_timeout 300s`, ingen understi) og
  `deploy/command-center.user.service` (systemd --user, `EnvironmentFile`).
- uvicorn kører med `--proxy-headers --forwarded-allow-ips`, så cookies bliver `Secure` og login-låsen ser klientens IP.

### MCP fase 2 (v7.17) — implementeret
- Fire skrive-værktøjer med `"scope": "write"`: `start_crawl`, `add_monitor`, `resolve_alarm`,
  `add_note`. `mcp_tool_start_crawl` er `async` (bruger `run_in_executor` + `site_crawl_sync`) — derfor
  tjekker `_mcp_handle` nu `inspect.isawaitable(result)`, så både sync- og async-værktøjer virker.
- Scope-tjekket er pr. værktøj (`tool["scope"]`), ikke længere hardcodet `read`; manglende scope giver
  `-32003` med scope-navnet. `tools/list` sender `annotations` (`readOnlyHint`, `destructiveHint`,
  `idempotentHint`).
- **Audit pr. nøgle:** `api_audit(client_id, method, tool, ok, detail, duration_ms, created_at)` +
  `idx_api_audit_client`. `log_api_call()` skriver ét spor pr. `tools/call` (også afviste kald, med
  årsag), `api_usage()` giver kald/fejl pr. nøgle, `api_audit_rows(limit)` de seneste til UI'et.
  Ingen nøgle i klartekst i auditten; rækker ældre end 90 dage ryddes i `cleanup_old_data`.
- UI: MCP-kortet viser "N kald · M fejl" pr. nøgle og de seneste 10 kald nederst. CLI:
  `python3 scripts/api_key.py audit [antal]`.
- `start_crawl` afvises når `CRAWL_STATE["running"]` (ingen dobbelt-crawl), `add_monitor` svarer
  `created: false` for samme url+type, `resolve_alarm` svarer `already_resolved` for gamle alarmer.
- Tests: 11 nye checks i `tests/test_v8_features.py` (annotations, skrivning, scope-afvisning, dublet,
  alarm, crawl-afvisning, ugyldig URL, audit, usage, ingen nøgle i audit) og 10 i `tests/ci_check.sh`.

### Invitation med svar (v7.17.2) — implementeret
- `POST /users/invite` redirecter nu til `/?tab=brugere&invite=ok|fejl&invite_msg=…`
  (`invite_redirect()`), og dashboardet starter på den fane (`initial_tab`, kun navne i
  `DASHBOARD_TABS`). Fejlen vises i formularen med mailserverens tekst + `--print`-vejen, så en
  invitation uden SMTP ikke længere ligner en tabt mail. Rapporteret som "modtog aldrig invite
  email": mailen var aldrig sendt, og svaret lå kun under Alarmer.
- Tests: 5 nye checks i `tests/test_v8_features.py`, 3 i `tests/ci_check.sh`.

### MCP-hærdning (v7.17.1) — implementeret
- **Klartekst-nøglen lever ikke længere i DB'en.** `settings.api_key_once` indeholder nu
  `{name, key, created_at}`, og `pending_api_key()` **sletter rækken i samme kald** som dashboardet
  læser den (returnerer værdien til netop den visning). `API_KEY_ONCE_TTL = 15 min.` er kun et
  sikkerhedsnet, hvis siden aldrig åbnes; `cleanup_old_data()` rydder en glemt række med **samme**
  DB-håndtag — et indlejret `get_db()` kunne ikke skrive i den åbne transaktion (fejlede stille).
- `POST /api-keys/dismiss` + `clear_api_key()` er fjernet (de gjorde intet efter ændringen), og knappen
  i dashboardet er erstattet af en linje om at kopiere nøglen nu.
- **Ukendte værktøjsnavne i auditten:** `_mcp_handle` kalder `log_api_call(..., False, "ukendt
  vaerktoej")` før `-32602`, så en nøgle der prøver navne af kan ses i "N kald · M fejl".
- Tests: 6 nye `mcp3:`-checks i `tests/test_v8_features.py` og 8 i `tests/ci_check.sh` (bl.a. at
  nøglen forsvinder fra DB efter én visning, TTL, oprydning og at dismiss-ruten er væk).
- Fase 3 (OAuth) er stadig ikke lavet; `_MCP_LOCAL_HOSTS` accepterer fortsat `localhost`/`testserver`
  ubetinget (lav risiko: nøgle + Origin kræves stadig).

### MCP fase 1 (v7.16) — implementeret
- `api_clients` (`name`, `key_hash` = sha256, `key_hint`, `scopes`, `last_used_at/ip`, `revoked_at`):
  én nøgle pr. klient, `cc_` + 32 tegn, vises **én gang** via `settings.api_key_once` i fanen Brugere.
  `scripts/api_key.py create|list|revoke` gør det samme fra terminalen.
- `POST /mcp` ligger **uden for** session-middlewaren (Bearer i stedet for cookie): JSON-RPC 2.0 med
  `initialize`, `ping`, `tools/list`, `tools/call`. Svar er almindelig JSON (ingen SSE), med
  `MCP-Protocol-Version: 2026-07-28` og `X-Accel-Buffering: no`.
- Syv læse-værktøjer: `health`, `crawl_summary`, `keywords`, `monitors`, `alarms_open`, `notes`,
  `history(domain_id)`. `tools/call` kræver `read`-scope, ellers `-32003`.
- Sikkerhed: ukendt nøgle → `401` + `WWW-Authenticate`, fremmed `Origin` → `403`, ukendt `Host` →
  `421` (valideres kun når `CC_PUBLIC_URL` er sat), og `last_used_at` opdateres ved hvert kald.
- **Ingen ny afhængighed:** SDK'en `mcp==2.3.0` kræver `starlette 1.10`, som `fastapi==0.115.6` ikke kan
  bruge (den kræver `<0.42`). Vi taler derfor JSON-RPC selv; skift til SDK'en når FastAPI understøtter
  starlette 1.x, og husk at et mounted sub-app kræver `session_manager.run()` i appens lifespan.
- Tests: `tests/test_v8_features.py` (13 checks) og `tests/ci_check.sh` (7 checks) dækker hash, scopes,
  tilbagekald, Origin, ugyldig JSON og at klartekst-nøglen ikke ligger i databasen.

### MCP-research (baggrund)
- [`docs/Command_Center_MCP.md`](docs/Command_Center_MCP.md) opsummerer protokollen pr. november 2026
  (spec `2026-07-28`, stateless, Streamable HTTP; HTTP+SSE er deprecated) og hvordan Command Center
  bedst får et `/mcp`-endpoint.
- Anbefaling: officiel Python-SDK (`mcp` 2.3.0, `MCPServer` + `streamable_http_app()`), mounted i den
  eksisterende FastAPI-app, med `session_manager.run()` i appens lifespan. Kendte faldgruber:
  mounted lifespan kører ikke, SDK'en svarer `421` uden `TransportSecuritySettings(allowed_hosts=…)`,
  og nginx buffer SSE uden `X-Accel-Buffering: no` + `proxy_buffering off`.
- Adgang i fase 1: **personlige nøgler pr. klient** (hash i DB, `read`/`write`-scopes, `Bearer`,
  `Origin`/`Host`-validering) — ikke én global token. OAuth 2.1 + RFC 9728 er fase 3.
- Fase 1-værktøjer (læs): `health`, `crawl_summary`, `keywords`, `monitors`, `alarms_open`, `notes`,
  `history`. Skrivende værktøjer først i fase 2 og med `TASK_ESTIMATES`-kvitteringer.

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
  Den kalder funktionerne direkte i venv'en, så der kræves hverken token eller login. Øverst viser den
  kørende version (fra `/health`) + filernes version + login-adressen, så man ikke fejrer en opdatering
  der aldrig blev genstartet.
- `scripts/user_create.py <email> [--username x] [--password y] [--must-change]` opretter en bruger
  uden invitation/SMTP; koden skal være min. 8 tegn.
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

### Opstart, login-IP og kørselsrapport (v7.13)
- `NEWEST` + `NEWEST_LINE` i `app/main.py` er kilden til "hvad er nyt". `log_startup()` skriver
  version + nyheder til stdout, `app/data/startup.log` og `settings.last_start`; `/health` har
  `newest` og `started_at`. `run.sh`, `run.bat`, `restart.sh`, `update.sh` og `install.sh` viser dem.
- Login-spor: `users.last_login_ip/last_login_at`, `sessions.ip`, `login_attempts` (30 dage).
  `client_ip()` bruger X-Forwarded-For kun fra `TRUSTED_PROXIES` (hoejre-mest ubetroede hop), ellers socket (v7.28).
- `/login` viser `last_run_report()`: version/commit, seneste opstart, åbne alarmer, taellinger,
  seneste tjek/crawl, DB-størrelse og klientens IP - uden alarmtekster eller brugernavne.

### Fremdrift (beholdes)
- Fremdriftskortet i dashboardet (`#cc-task`, `ccTaskStart/ccRender/ccTaskDone`, `ccPollCrawl`) er en
  fast del af UI'et - fjern det ikke. `crawl_progress()` giver rigtig procent for crawl, mens
  `TASK_ESTIMATES` giver ærlige skøn for de øvrige tunge handlinger.
- Nye formular-actions der tager mere end ~5 s skal have en `TASK_ESTIMATES`-post (label + seconds),
  ellers kører de uden fremdrift. Crud-handlinger og `/alarms/resolve` er undtaget.

### Oprydning (v7.13.1)
- AST-gennemgang: ingen døde funktioner. `/api/history/{domain_id}` bruges af dashboardets JS.
- Fjernet: `Header`/`HTTPException`/`sys`-importer og `cols = {}` i `migrate_db`.
- `migrate_db` dropper nu `drift`/`gsc_daily`/`gsc_queries` **kun hvis de er tomme**.
- `run_in_executor`-mønstret (35 steder) er bevidst ikke refaktoreret - se arkitektur §15.

### Agent + skill (v7.13.2-v7.13.3)
- Seks agenter, grupperet i `.agents/README.md` efter de tre repos der horer sammen: Command Center
  (`command-center-reviewer`, `cc-verifier`, `site-seo-auditor`, `mcp-access-auditor`), Social Autopilot
  (`social-autopilot-auditor`) og Social Autopilot Android (`social-autopilot-android`).
- Kun Command Center ligger i denne arbejdsmappe; de to andre agenter arbejder ud fra den kontrakt
  Command Center implementerer (`/drafts`, `/autopilot/sync`, `socialqueue`, **lokal tid**) og skal
  sige til naar de mangler filer i stedet for at gaette.
- De ligger fladt i `.agents/` fordi Freebuff laeser `<id>.ts` direkte der; grupperingen er
  id-prefix + manifest, ikke undermapper.
- Testen validerer nu ALLE agentfiler (id = filnavn, model, vaerktoejer, prompt), at de er naevnt i
  manifestet, og at der ikke er fremmedsprog/rester eller hemmeligheder i dem.
- `scripts/agents_md_rollout.sh` (ny): lægger den fælles `AGENTS.md` ind i alle repoer under kontoen som
  branch `chore/agents-md` + PR. `--dry-run` viser planen, `--only`/`--skip` styrer hvilke repoer der
  køres, og en eksisterende fil overskrives kun med `--overwrite`; `main` pushes der aldrig til. Kræver
  `gh` logget ind lokalt, indgår ikke i `install.sh` og kører ikke i CI — testet offline mod tre lokale
  bare-repoer (opret, identisk, afvigende, genkørsel, `--skip` og `--only`) samt tørkørsel mod
  `steamgears-site`. **Bemærk:** `steamgears-site` har allerede en repo-specifik `AGENTS.md` (procenter,
  `projektstatus.py`, natlig push) og bliver derfor sprunget over — dér skal der lægges sammen, ikke
  overskrives, og push-reglen i §5 der vinder over den fælles "push kun når der bedes om det".
  Den sammenlagte udgave (lokal §1-§6 urørt + fælles §7-§10) ligger i
  `docs/agents-md/steamgears-site.md`: kør
  `bash scripts/agents_md_rollout.sh --only steamgears-site --overwrite --source docs/agents-md/steamgears-site.md`.
  `--overwrite` er nødvendig, fordi også den sammenlagte fil afviger fra den nuværende.
- `.agents/mcp-access-auditor.ts` (v7.17.1): read-only revisor for MCP-adgangen. Laeser `api_clients`
  og `api_audit` med `mode=ro` og rapporterer noegler der boer tilbagekaldes (ubrugte, for brede
  scopes, brug efter tilbagekaldelse), scope-afvisninger i auditten, om `CC_PUBLIC_URL` er sat
  (ellers er Host-tjekket slaaet fra), og om de fire skrive-vaerktoejer gaar gennem appens egne
  funktioner. `params.focus` = noegler/scopes/audit/transport/skrivning; `live` kalder kun 127.0.0.1.
- `.agents/command-center-reviewer.ts`: read-only reviewer (id = filnavn, jf. Codebuff-kravet), kender
  regler/kontrakter/faldgruber og kan koere begge testsuiter via `params.run_tests`.
- `.agents/skills/command-center/SKILL.md`: frontmatter `name: command-center` + de otte regler.
- Begge er dev-vaerktoej, indgaar ikke i `install.sh` og hentes ikke af self-update.
- `tests/test_v8_features.py` tjekker at filerne findes, at id matcher filnavn, og at frontmatter er
  gyldig - saa de ikke raadner stille.

### Flettet med fjern-sessionen (v7.13.2)
- Remote havde to commits fra en anden session; de er flettet ind (merge `b72f3f5`).
- Deres oprydning fjernede `sitemap_missing = 0`, `import urllib.parse as _up` og `result =`.
  `sitemap_missing` findes stadig som **kolonnenavn** i SQL og i `migrate_db` - det er ikke den
  fjernede variabel, saa den skal ikke "genoprettes".
- `install.sh` er regenereret efter flettet, og pariteten er verificeret (17/17).

### Tider (v7.14.0)
- Planlagte opslag gemmer `scheduled_at` (lokal) + `scheduled_at_utc`, og `created_at_utc` ved siden af
  `created_at`. Konvertering kun ved graenserne: `local_to_utc()` / `utc_to_local()`.
- Ikke-eksisterende sommertid afvises; tvetydig tid giver foerste forekomst (`fold=0`). Testene daekker
  baade 29/3 og 25/10 2026.
- Zonen er `CC_TZ` (standard Europe/Copenhagen). Ukendt zone falder tilbage, den crasher ikke.

### Idempotens paa Autopilot-broen (v7.14.1)
- `/social/to-autopilot` laaser raekken med `social_claim()` **foer** kaldet: status bliver
  `sender til autopilot`, og et dobbeltklik eller genforsoeg rammer `rowcount = 0` og sender intet.
  Uden laasen gav et tabt svar to kladder i WordPress til det samme opslag.
- Svar fra WordPress (4xx/5xx) slipper raekken tilbage til sin gamle status, saa den kan sendes igen.
  Timeout/`ConnectionError` goer det modsatte: status bliver `sendt? (svar udeblev)` + alarm, fordi vi
  ikke ved om kladden blev oprettet. Gentagen sending er vaerre end en manuel kontrol.

- Status-konstanterne er `SOCIAL_SENT` / `SOCIAL_SENDING` / `SOCIAL_UNCERTAIN`; `social_claim` er den
  eneste skriver af laasen, saa en ny kaldevej skal bruge den i stedet for selv at saette status.
- Tests: `tests/test_v8_features.py` (tre POSTs mod en fake sgap-server = én kladde, og laasen kan kun
  tages én gang) samt `tests/ci_check.sh` (genforsoeg mod `fake_wp` lader kladdetallet vaere 1).

### Screenshot-script (v7.13.1)
- `scripts/screenshots.py` tager `cc-login.png` og alle 16 fanebilleder i `docs/img/` mod en kørende
  app: `python3 scripts/screenshots.py --base http://127.0.0.1:8000 --user X --password Y`.
  `--only cockpit,notes`, `--viewport` og `--skip-login` findes til delkørsler; login sker via
  `context.request.post("/login")`, og fanerne skiftes med `Alpine.$data(body).tab = <key>`.
  Scriptet fejler med en klar besked, hvis Playwright/Chromium mangler, hvis appen stadig er på
  `/setup`, eller hvis login afvises.
- Playwright er **ikke** i `requirements.txt` (kun dette script bruger det):
  `pip install playwright && python3 -m playwright install chromium`.
- Fane-listen i `TABS` skal foelge nav-knapperne i `app/templates/dashboard.html`.
- Chromium crashede foerst paa dashboardet i denne VM - det er **miljoeet, ikke appen**: der findes
  intet `/etc/fonts`, saa Skia aborterer med `FATAL: SkFontMgr_FontConfigInterface.cpp:163 Not
  implemented` (SIGTRAP). Loesning: lav en `fonts.conf` med `<dir>` (DejaVu/Noto) + `<cachedir>` og
  saet `FONTCONFIG_FILE`/`FONTCONFIG_PATH`. Derefter kan alle 15 faner fotograferes headless.
- Containeren kan mangle baade `/etc/fonts` **og** de delte biblioteker (libfontconfig, libnspr4,
  libnss3, libatk*, libxkbcommon m.fl.), og der er hverken root eller apt-lister. Uden root: hent
  `.deb`-filerne via Packages-indexet (`archive.ubuntu.com/ubuntu/dists/noble/{main,universe}/
  binary-amd64/Packages.gz`), udpak med `dpkg -x` i en lokal mappe og saet `LD_LIBRARY_PATH` samt
  `FONTCONFIG_PATH`/`FONTCONFIG_FILE` til den udpakkede `fontconfig-config`. Bruger man kun en egen
  `fonts.conf` uden `conf.d` fra `fontconfig-config`, bliver al braedtekst tofu, mens fed tekst tegnes
  korrekt - det ser ud som en app-fejl, men er font-matching. `fonts-dejavu-core` + `fonts-liberation`
  + `fonts-noto-color-emoji` giver baade dansk tekst og farve-emoji paa billederne.
- Mangler der en emoji-font i det saet, bliver emoji i UI'et tomme kasser paa billederne. Det er kun
  kosmetisk - layout og tekst er korrekt.

### Dokumentation og CI
- `README.md`, manualen og arkitektur-dokumentet er skrevet om til v7.11; `docs/Command_Center_Install_Script.md`
  er erstattet af en kort, korrekt side (den gamle var en 1.362-linjers kopi af v6.0-scriptet).
- `docs/ROADMAP.md` er ny. CI's paritets-trin dækker nu alle 17 indlejrede filer (før 5).
- `docs/ROADMAP.md` har nu en **dokumentationsoversigt** øverst og et **Endgoal**-afsnit: det
  langsigtede mål, succeskriteriet og hvilke roadmap-punkter der trækker derhen.
- Dokumentationen er suppleret med det, der manglede i forhold til koden: **AI-synlighed** og **Noter**
  i manual/README, fane 9-12 (Alarmer, Brugere, Noter, Moduler) i manualen, fuld tabel- og jobliste
  (`alert_outbox`, `login_attempts`, `notes`, `_selftest`, alarmkø hvert minut), de 11 moduler og en
  samlet ruteoversigt i `Command_Center_Dokumentation.md` (§16).
- CI **fejler** når `docs/img/` er ældre end `app/templates/dashboard.html` (siden 10. november 2026 - foer var det
  kun en advarsel). Trinnet "Screenshots are not older than the dashboard" sammenligner
  commit-tidspunkter (ikke fil-mtimes, som checkout nulstiller), henviser til `scripts/screenshots.py`
  og springes over med `[skip screenshots]` i commit-beskeden - samme moenster som `[skip docs]`.
- **PR-kørsler (11. november):** på `pull_request` er HEAD en merge-commit, så `[skip docs]`/`[skip screenshots]`
  blev aldrig set dér (push-kørslen var grøn, PR-kørslen rød). Begge trin læser nu beskeden og tidspunkterne fra
  `HEAD_SHA` = `github.event.pull_request.head.sha || github.sha`. Markøren skal stå i PR'ens **seneste** commit.

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

- Regelsættet ligger i [`AGENTS.md`](AGENTS.md): afsnit 1-7 er fælles for alle repoer (roadmap før kode,
  dokumentation, test, sikkerhed, git, pakning), afsnit 8 har profilen for WordPress/PHP, Python/FastAPI
  og frontend, og afsnit 9 er dette repos egne otte regler. Kopiér filen til de øvrige repoer i stedet
  for at skrive reglerne igen.
- Start hver opgave med et tidsestimat (fx "~25 min") — også små opgaver — og afslut med det faktiske
  tidsforbrug. Skrider det, sig det straks.
- Rapportér fremgang i **procent** undervejs ("~40 %: reglerne er rettet, research mangler"), så brugeren
  kan se hvor langt arbejdet er. Procenter i UI'et skal komme fra rigtige data, ikke fra et fastlåst skøn.
- Rapportér kun det, der faktisk er kørt: hvilke tests, CI-status, og hvad der ikke kunne verificeres her.

## Kendte begrænsninger

- Én proces + SQLite + APScheduler: ingen vandret skalering; et job deler event-loop med HTTP.
- Dashboardet henter Tailwind/Alpine/Chart.js fra CDN; login-siden er selvstændig.
- Crawleren bruger `requests` (ingen JS-rendering) og ca. 20 kontroller — ikke Sitebulb-niveau.
- Chat-connectors: Gmail, Google Drive og WordPress.com kræver et token fra en MCP-server/gateway (intet OAuth-flow i CC endnu), og connector-nøgler ligger i klartekst i `center.db` og dermed i backups.
- Vækst-fanen måler tekst og de sider, brugeren selv peger på; der er ingen søgevolumen, placeringer eller backlink-data (det kræver et eksternt indeks). Konkurrentsammenligning henter højst tre sider pr. kald.
- `docs/img/` er fotograferet mod v7.26-UI'et (login + alle 16 faner), og CI fejler nu, hvis et UI-commit går forbi uden nye billeder.
- Efter Juno-fjernelsen: ingen GSC-data, og `drift`/`gsc_*`-tabeller kan stadig ligge tomme i en
  eksisterende `center.db` (intet læser eller skriver dem).
- Systemd-genstartsstien er ikke testet i denne VM (ingen systemd); pidfile-stien er verificeret.
- `docs/img/`-screenshots er opdateret med `scripts/screenshots.py` (kræver Playwright + Chromium, som ikke er en del af appens requirements); headless Chromium skal have en `FONTCONFIG_FILE`, se Screenshot-script ovenfor.
- Opdatering kræver `GITHUB_TOKEN`; et rigtigt tarball-download er ikke afprøvet her.

## Roadmap (kort — detaljer i `docs/ROADMAP.md`)

Roadmappen blev **genoptrænet 3. november 2026**: listens punkter er tjekket mod koden, ikke mod tidligere
noter, og hvert punkt har nu en verifikationslinje (et grep, en rute eller en tabel).

1. **Google Search Console** (read-only): clicks/impressions/queries/pages, striking distance,
   content decay, indexation. Største hul efter Juno-fjernelsen — der findes ingen GSC-kode i dag.
2. **CSRF + session-rotation**: ingen CSRF-token og ingen session-rotation ved login i dag.
3. **Offline dashboard-assets**: Tailwind, Alpine og Chart.js hentes stadig fra CDN.
4. **E2E-test af opdateringen** mod en fake GitHub-API.
6. **Tests for login-rate-limit og job-guards** (dækket indirekte i dag).
7. **Alarmer, resten**: maintenance windows, ugentlig digest, evt. Apprise. Dedup, stille timer, backoff
    og fire kanaler er færdige i v7.12.

Færdige punkter fra den gamle liste: alarm-routing (v7.12), API-nøgler/MCP fase 1-2 (v7.16-v7.17) og
MCP-hærdning (v7.17.1). De står nu under "Færdigt" i roadmappen i stedet for under "Næste".

## Åbne tråde

- Brugeren delte et Claude-share-link (`claude.ai/code/...`). Det kan **ikke** hentes herfra:
  Cloudflare svarer 403 ("Just a moment…") og reader-proxyen afviser IP'en. Afvent at brugeren
  paster indholdet (diff/plan) — og mind dem om at fjerne tokens fra teksten.
- Ingen secrets i repoet: brug `.env` (gitignored) eller miljøvariabler. `GITHUB_TOKEN`,
  `SERPAPI_KEY`, `OPENROUTER_API_KEY`, `WP_APP_PASSWORD` og `TELEGRAM_*` må ikke committes.
- Vue: hold UI-tekster på dansk, og opdater README + manual + roadmap i samme ændring som koden.
