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
  templates/dashboard.html # hele UI'et (Alpine.js + Chart.js lokalt i static/vendor)
  templates/login.html     # login/setup, helt selvstændig (ingen CDN)
  data/center.db           # SQLite (gitignored)
  backups/cc-*.db          # daglige + pre-update-backups
  static/                  # oprettes ved start (git kan ikke gemme tomme mapper)
deploy/                    # nginx-config (rod + Ultra.cc-understi), systemd-units
scripts/smoke_test.sh      # /health, /login, /setup
scripts/ultracc_setup.sh   # v7.28: tunnel -> Ultra.cc-understi (plan, --apply)
tests/                     # enhedstests, CI-boot-test, link-audit
install.sh                 # selvstændig installer (indeholder kopier af filerne)
```

## 2. Opstart

1. `load_dotenv()` læses **før** konfigurationsblokken (rigtige miljøvariabler vinder; inline-kommentarer fjernes)
2. `init_db()` → `migrate_db()` → `create_indexes()` køres i `_safe()`, så en fejl ikke kan crashe importen (ét retry, derefter videre)
3. `seed_standard_user()` kaldes i lifespan **før** scheduler og selvtest: er `users` tom, og har `.env` både `CC_ADMIN_EMAIL` og `CC_ADMIN_PASSWORD`, oprettes standardbrugeren med `must_change_password`. Status skrives til opstartsloggen (`oprettet`, `findes`, `mangler`, `fejl: …`), og en afvist linje giver en advarsel i `alarms`. Derefter kaldes `warn_stale_env_password()`: passer `CC_ADMIN_PASSWORD` ikke til den gemte hash (fordi koden er skiftet i UI'et), skrives `[cc] advarsel: …` og en advarsel i `alarms`, og dashboardet viser en rød bjælke via `env_password_warning`
4. Lifespan registrerer APScheduler-jobs og starter en selvtest i en worker-tråd (DB-skrivetest, nøgler, ruteantal → kritisk alarm ved fejl)
5. Alt netværk går gennem én `requests.Session` med **BudgetAdapter**, der tæller kald til SerpAPI/OpenRouter

## 3. Auth-model (v7.15–v7.18)

| Emne | Implementering |
| --- | --- |
| Brugere | `users(id, email UNIQUE, username (legacy, kan vaere NULL), password_hash, must_change_password, created_at, last_login_ip, last_login_at)` |
| Login-id | e-mail i smaa bogstaver (`normalize_email`); et gammelt brugernavn accepteres stadig, saa migrerede konti ikke laases ude |
| Invitation | `POST /users/invite` → `send_email()` med en midlertidig adgangskode. Brugeren oprettes **først naar mailen er sendt**; fejler SMTP, oprettes ingen bruger, fejlen bliver en alarm og svares tilbage i URL'en. Adressen valideres **før** SMTP: `normalize_email()` og `example_email_hint()` afviser ugyldige adresser og pladsholdere fra dokumentationen (`invite_kind=adresse|eksempel`, `force=1` opretter alligevel). `must_change_password` ryddes af `/users/password` |
| Hash | `pbkdf2_sha256$240000$<salt>$<hash>` (salt pr. bruger, `hmac.compare_digest`) |
| Sessioner | `sessions(id=sha256(cookie), user_id, created_at, last_seen, expires_at)`, 30 dage |
| Cookie | `cc_session`, HttpOnly, SameSite=Lax, `Secure` når scheme er https |
| Standardbruger (v7.18) | `seed_standard_user()` i lifespan: `CC_ADMIN_EMAIL` + `CC_ADMIN_PASSWORD` fra `.env` opretter kontoen, når `users` er tom (`must_change_password=1`, alarm ved oprettelse og ved afvist linje). Der seedes aldrig oven på en eksisterende konto, og klartekst findes kun i `.env` |
| Rydningen vises i dashboardet (v7.19.2) | `clear_env_admin_password()` gemmer `{at, by, account}` i `settings` under `env_password_cleared` (kun navn og tidspunkt, aldrig koden), og `env_password_notice()` læser rækken tilbage. Om linjen står der, afgøres af `env_admin_password_in_file()`, som læser `.env` — ikke miljøvariablen, der blev læst ved opstart og derfor ikke ser en rettelse undervejs — og svarer `sat`, `tom`, `ingen-fil` eller `fejl`; `danish_time()` laver tiden om til dansk. Er koden blevet forældet, returnerer funktionen tom, så den røde advarsel vinder, og uden en gemt rydning vises baren ikke |
| `.env` ryddes ved kodeskift (v7.19.1) | `POST /users/password` kalder `clear_env_admin_password(email)`, men kun når den konto, der skiftede, er `CC_ADMIN_EMAIL`: den tømmer `CC_ADMIN_PASSWORD=` i `.env` (regex på nøglen, atomisk `os.replace`, oprindelig filmode bevaret), sætter miljøvariablen til tom og nulstiller cachet, så advarslen forsvinder. Fejler skrivningen, kommer der en advarsel i `alarms`, og kodeskiftet gennemføres alligevel |
| Forældet `.env`-kode (v7.18.1) | `env_password_mismatch()` verificerer `CC_ADMIN_PASSWORD` mod den gemte hash og cacher svaret på `(email, sha256(kode), hash)`, så dashboardet ikke kører PBKDF2 ved hvert sidevisning. Advarslen ændrer intet ved kontoen; den forsvinder, når linjen rettes eller fjernes |
| Første bruger (reserve) | `/setup` — kun åben når `users` er tom, altså når `.env` ikke har de to linjer |
| Rate limit | 5 fejl pr. IP = 10 min lås (bounded dict) |
| UI-adgang | Middleware sætter `request.state.user`; ikke-loggede sendes til `/setup` eller `/login` |
| API-nøgler (v7.16) | `api_clients(id, name, key_hash UNIQUE, key_hint, scopes, created_at, last_used_at, last_used_ip, revoked_at)`. Nøglen er `cc_` + 32 tegn, vises **én gang** (klartekst ligger kun i `settings.api_key_once` til den er vist — rækken slettes i samme kald, med 15 min. TTL som sikkerhedsnet), gemmes som sha256 og kan tilbagekaldes pr. klient |
| MCP | `POST /mcp` er **uden for** session-middlewaren: `Authorization: Bearer cc_…` → `find_api_client()`, `Origin`/`Host` valideres, svaret er JSON-RPC 2.0 (spec `2026-07-28`, stateless). Hvert værktøj har et `scope` (`read`/`write`), og `tools/call` afvises med `-32003`, hvis nøglen mangler det |
| MCP-audit (v7.17) | `api_audit(id, client_id, method, tool, ok, detail, duration_ms, created_at)` — ét spor pr. `tools/call`, også afviste kald og ukendte værktøjsnavne. Vist i fanen Brugere og via `scripts/api_key.py audit`; ryddes efter 90 dage |

`APP_TOKEN` er fjernet, og der er ingen invite-tokens: en invitation er en mail med en midlertidig adgangskode, som brugeren skifter. Sessioner slettes ved logout, bruger-sletning og adgangskode-skift (bortset fra den aktuelle session).

## 4. Datalag

Tabeller i grupper:

- **Overvågning**: `domains`, `check_history`, `monitors`, `health_history`, `alarms`
- **Alarmer og login**: `alert_outbox` (én række pr. kanal), `login_attempts`
- **SEO**: `seopages`, `crawl_runs`, `keywords`, `keyword_difficulty`, `keyword_ideas`, `content_gap`, `visibility`, `internal_links`
- **Vækst (v7.24)**: `content_briefs` (planen), `link_targets` (manuel linkliste, `url` unik) og `content_audits` (de sidste 50 målinger fra optimereren, ryddet af ruten selv)
- **Indhold**: `articles`, `backlink_prospects`, `outreach`
- **Drift/integrationer**: `socialqueue`, `competitors`, `linkcheck`, `ai_visibility`
- **Adgang**: `api_clients` (MCP-nøgler, hash + scopes), `api_audit` (kald pr. nøgle)
- **Login fra WordPress (v7.27)**: `sso_used` (`jti` primærnøgle + `exp`; rækker ældre end en time ryddes ved hvert login) og `settings.cc_sso_secret` / `settings.cc_sso_link`
- **Chat (v7.26)**: `mcp_connectors` (eksterne MCP-servere: url, login, `secret` + `secret_hint`, værktøjsfilter, `tools_json`), `chat_conversations` (pr. bruger), `chat_messages` (user/assistant/tool i OpenAI-format) og `chat_pending` (skrivende kald der venter på godkendelse)
- **System**: `users`, `sessions`, `settings` (nøgle/værdi: moduler, strategi, budget, snapshots, `deployed_commit`, `github_update`), `notes` og `_selftest` (resultat af opstarts-selvtesten)

Alle queries er parameteriserede. `settings` bruges til små tilstande (JSON), så nye funktioner ikke kræver migration.

## 5. Jobs (APScheduler, Europe/Copenhagen)

| Job | Tidspunkt | Guard |
| --- | --- | --- |
| Domæne-tjek | hvert 6. time | modul `domains` |
| Keyword-positioner | 06:00 | modul `keywords` + `SERPAPI_KEY` |
| Growth-autopilot | 05:15 | modul `growth` + `OPENROUTER_API_KEY` |
| Oprydning | 04:30 | — (lokale ISO-cutoffs) |
| DB-backup | 04:40 | 14 kopier pr. tag |
| GitHub-opdaterings-tjek | 05:00 | `GITHUB_TOKEN` |
| Autopilot-bro (WordPress) | hvert 30. min | modul `autopilot` + WP-creds · `sgap_sync()` henter `GET /snapshot` (reserve: `/stats` + `/drafts` ved 404), `sgap_from_snapshot()` oversætter, `sgap_store()` gemmer i `settings.sgap_snapshot` og alarmerer kun ved ændringer |
| WP-Cron-ping | hvert 5. min | samme som Autopilot-bro · `job_wp_cron()` → `wp_cron_ping()` kalder `wp-cron.php?doing_wp_cron`; fejl er tavse (sitet nede fanges af broen og monitorerne) |
| Alarmkø (`alert_outbox`) | hvert minut | — (leverer med dedupe, backoff og stille timer) |
| Job-heartbeat | hvert 15. min. | — (alarmerer forsinkede og fejlede jobs, se §8b) |

Modulerne (`MODULES` i `app/main.py`, 11 stk.): `domains`, `keywords`, `ai`, `monitors`, `social`,
`links`, `spy`, `wp_push`, `telegram`, `growth` og `autopilot`. Et slukket modul skjuler UI'et
(`module_labels` i skabelonen) og springer det tilhørende job over.

## 6. Crawler og SEO-analyse

- `analyze_page()` giver 20+ vægtede kontroller (titel, meta, H1/H2, canonical, schema, OG, alt-tekster, læsbarhed, interne links, mixed content, focus keyword) og en score 0-100
- Crawleren følger samme-host-links, gemmer `content_hash` (ændret indhold), `redirects` (kæder/loops) og validerer op til 50 sitemap-URL'er
- Der gemmes **to** crawl-runs: det nye og det forrige, så `/api/crawl/diff` kan sammenligne. Dashboard, duplikat-rapport, redirect-audit og link-forslag læser kun den seneste run
- Ikke-200-sider analyseres uden at hente dem igen (HTML videregives)
- Under crawl rapporterer `/api/crawl/status` `percent`, `eta_seconds` og `elapsed_seconds` (beregnet i `crawl_progress()`); dashboardet poller den og viser fremdrift. Øvrige tunge opgaver bruger estimaterne i `TASK_ESTIMATES`

## 6b. Vækst: lokal indholdsoptimering (v7.24)

Fanen Vækst måler indhold uden at hente data fra en søgemaskine eller en betalt API. Det er et bevidst
valg: Surfer, Ahrefs og Semrush bygger på egne webindekser, og den slags kan en enkelt installation ikke
genskabe. Til gengæld kan alt det, der står i teksten, måles præcist.

| Funktion | Implementering |
| --- | --- |
| Optælling | `content_text()` fjerner scripts/styles, `content_words()` tæller ord, `content_term_counts()` tæller termer uden `CONTENT_STOPWORDS` (dansk + engelsk), og `term_stats()` tæller hele ord/fraser med regex-grænser — ikke delstrenge |
| Score | `local_content_optimizer()` vægter hver kontrol (keyword i titel/H1/første 10 %/2 H2 = 6+5+4+4, tæthed 5, H2 5, ordantal 7, sætninger 3, afsnit 2, interne links 4, meta 3, termdækning 10) og regner `earned/total*100`. Manglende kontroller sorteres efter vægt til `fixes` |
| Konkurrenter | `compare_with_competitors()` henter op til `COMPETITOR_MAX` (3) URL'er gennem `safe_request()` (SSRF-guarden gælder også her), laver et `content_profile()` pr. side og finder termer, som mindst to konkurrenter bruger men egen tekst ikke nævner |
| Briefs | `brief_from_keyword()` sætter mål for ord/H2 ud fra konkurrenternes gennemsnit (ellers standard 1200 ord og 5 H2), samler termer og bygger overskrifter med `brief_headings()`. Gemmes i `content_briefs` med status fra `BRIEF_STATUS` |
| Linkliste | `POST /links/target/add` validerer URL'en med `normalize_url()` og gemmer med `INSERT OR IGNORE` (samme URL kun én gang). Status følger `LINK_STATUS` |

Ruterne er `POST /growth/optimize` og `/growth/compare` (JSON, bruges af `fetch` i dashboardet),
`/growth/brief`, `/growth/brief/status`, `/growth/brief/delete` samt `/links/target/add`,
`/links/target/status` og `/links/target/delete`. De tre tunge har poster i `TASK_ESTIMATES`, så
fremdriftskortet også dækker dem.

Begrænsning: der er ingen søgevolumen, sværhedsgrad, placeringer eller backlink-data. Tallene kommer
fra teksten og fra de sider, brugeren selv angiver.

## 7. Indhold og kvalitetsgate

`generate_article_ai()` bygger prompten ud fra strategien (AdSense/Affiliate/Backlink) og top 5 SERP-resultater.
`quality_check()` er deterministisk: ordantal (min. `QUALITY_MIN_WORDS` eller 80 % af SERP-gennemsnit), fokus-keyword,
mindst 2 H2 — ellers blokeres autopilot-push til WordPress (manuel push giver info-alarm).

Artikel-HTML, der vises i dashboardet, kører gennem `sanitize_article_html()` (allow-list af tags; ingen scripts,
handlers, `javascript:`-links eller billeder), fordi indholdet kommer fra en ekstern AI-model.

### 7c2. Understi bag nginx (v7.28.0)

Ultra.cc's nginx giver kun `location /<app>/` på brugerens faste adresse, ikke et eget domæne. `CC_BASE_PATH`
(`cc_base_path()`: `CC_BASE_PATH` fra miljøet, ellers stien i `CC_PUBLIC_URL`; kun `[A-Za-z0-9._-]`-segmenter, ellers
roden) bestemmer understien. `BasePathMiddleware` er et rent ASGI-lag, registreret **efter** `auth_middleware` og **før**
GZip, så rækkefølgen udefra er GZip → understi → auth → ruter:

- **Ind:** `/cc/x` → `scope.path = /x` (og `raw_path`); `/cc` → 307 til `/cc/`. Kald uden præfiks (127.0.0.1, `scripts/update.sh`) går uændret igennem.
- **Ud:** `Location: /x` → `/cc/x` (ikke `//…` og ikke allerede præfikset), `Set-Cookie …; Path=/` → `Path=/cc`.
- **HTML** (`text/html`, buffret, ny `Content-Length`): `href|action|src|formaction="/x"` → `"/cc/x"`, og et `<script>` lige efter `<head>` sætter `window.CC_BASE` og pakker `window.fetch`, så `fetch('/api/…')` rammer `/cc/api/…`. Dashboardets tidsestimat (`ccEstimate`) fjerner præfikset igen, før det slår ruten op i `TASK_ESTIMATES`.
- Er `CC_BASE_PATH` tom, kalder laget blot videre — ingen omskrivning.

`scripts/ultracc_setup.sh --url https://<bruger>.<server>.usbx.me/cc [--port N] [--apply]` udfører skridtene: stopper `cloudflared` (systemd `--user`, crontab — skrevet fra en backupfil, så der aldrig læses og skrives samtidig — og processer), sætter `CC_HOST`/`CC_PORT`/`CC_PUBLIC_URL`/`CC_FORWARDED_ALLOW_IPS` i `.env` (backup, filmode bevaret, andre linjer urørte, en sat `CC_BASE_PATH` tømmes), skriver nginx-blokken med sti og port (kun ikke-kommentarlinjer omskrives), kører `app-nginx restart` og `scripts/restart.sh` og tjekker `/health` lokalt og `<url>/login` udefra. Uden `--apply` skrives intet. Kode 0/2/3/4 = ok/argumenter/skridt/tjek.

`CC_PUBLIC_URL` beholder stien, så login-linket, invitationsmailen og `cc_sso_push()` (WordPress-knappen) automatisk peger
på `…/cc/…`. Host-tjekket på `/mcp` bruger kun værten og er uændret.

### 7d. Log ind fra WordPress (v7.27.0)

Billetten er `base64url(json) + "." + base64url(HMAC-SHA256(nøgle, base64url(json)))`, med JSON-felterne `v` (1),
`email`, `login`, `site`, `iat`, `exp` og `jti` (32 hex). `cc_sso_verify()` tjekker i denne rækkefølge: format og
længde (≤ 2048), signaturen (`hmac.compare_digest`, før noget i JSON læses), `v`, `exp - iat ≤ 120` og `jti`-formatet,
udløb med ±30 s ur-forskel, engangsbrug (`INSERT` i `sso_used`; `IntegrityError` = brugt) og til sidst en bruger med
samme normaliserede e-mail. Nøglen laves med `secrets.token_urlsafe(48)` og forlader kun CC i `POST /cc-link` til
pluginnet over den autentificerede bro. Pluginnet gemmer den uden autoload og viser kun `sso: true/false` i `/snapshot`.

### 7c. Chat og MCP-connectors (v7.26.0)

Command Center er her MCP-**klient** (det modsatte af `/mcp`, hvor CC er server). Klienten taler Streamable HTTP:
`initialize` → `notifications/initialized` → `tools/list` (op til 10 sider) / `tools/call`, med `Mcp-Session-Id` og
`MCP-Protocol-Version` fra svaret. Svar kan være `application/json` eller `text/event-stream` (`_mcp_parse`). En session
caches pr. connector i `_MCP_SESSIONS` og åbnes igen én gang ved 400/404. Kald går gennem en egen `requests.Session`
(`MCP_HTTP`), så de ikke tæller i AI-budgettet; adressen tjekkes med `assert_public_url`, og 3xx følges ikke.

`chat_run(cid)` bygger tools fra de valgte connectors (`chat_tools`: funktionsnavn `c<id>_<værktøj>`, højst
`CHAT_MAX_TOOLS`), kalder `openrouter_complete()` med system-prompt + historik og håndterer `tool_calls`:
`readOnlyHint=true` udføres straks; alt andet skrives i `chat_pending` og returnerer `afventer`. `chat_decide()` låser
rækken med `UPDATE … WHERE status='afventer'` (rowcount = 1), udfører eller afviser, og samtalen fortsætter, når intet
venter. `_CHAT_RUNNING` forhindrer to samtidige kørsler af samme samtale. Svar fra værktøjer afkortes til 12.000 tegn.

### 7b. AI-kald via OpenRouter (v7.25.0)

Alle AI-kald går gennem `ai_chat(prompt, max_tokens, timeout)`: `POST {OPENROUTER_BASE_URL}/chat/completions`
(standard `https://openrouter.ai/api/v1`) med `Authorization: Bearer OPENROUTER_API_KEY`, `X-Title: Command Center`
og `HTTP-Referer: CC_PUBLIC_URL`, når den er sat (OpenRouters valgfri app-attribution). Kaldet går gennem den fælles
`HTTP`-session, så `BudgetAdapter` tæller det som `ai`, og budgettets værtsnavn læses af `OPENROUTER_BASE_URL`.

OpenRouter kan svare 200 med et `error`-objekt, når udbyderen bag modellen fejler. `ai_chat()` læser derfor `error`
før `choices` og kaster `AIError` (en `requests.RequestException`) med OpenRouters besked, også ved tomt `choices` eller
en tom besked. Eksisterende `except`-grene fanger den uændret, og nøglen indgår aldrig i fejlteksten.

`AIMLAPI_KEY` bruges ikke længere. `warn_legacy_aimlapi()` kaldes i lifespan og giver en advarsel i opstartsloggen og en
alarm (`ai`), når kun den gamle nøgle er sat.

## 8. API-budget

`budget_spend()` tælles pr. kalendermåned i `settings` og kaster `BudgetExceeded` **før** kaldet sendes, når loftet er nået.
Alarm (og Telegram) ved 80 % og 100 %. `/health` viser `budget: {serpapi: {used, limit}, ai: {...}}`.
Cockpit viser de samme tal i kortet "💳 API-budget denne måned" (`budget_rows` i dashboard-konteksten).

### 8b. Job-heartbeat (v7.20.0)

Hvert scheduler-job pakkes i `job_heartbeat(job_id, fn)`. Den skriver `job_<id>_last_start`, `job_<id>_last_end` og `job_<id>_last_status` (`ok` eller `fejl`) i `settings`, og fejlen rethrows, så APScheduler stadig logger den. Async jobs pakkes som async.
`job_heartbeat_check()` kører hvert 15. min. og markerer et job som **forsinket**, når `last_end` er ældre end `JOB_MAX_AGE_HOURS` (domæne 7 t, sgap_sync 1,5 t, alert_outbox 6 min., øvrige 26 t). Et job der aldrig er kørt tæller først, når appens `last_start` er ældre end grænsen, så en frisk installation ikke alarmerer. Hver tilstand (`ok`/`forsinket`/`fejlet`) alarmeres én gang; tilstanden gemmes i `settings.job_alarm_<id>`, og genopretning nulstiller stille. Cockpit viser kortet "⏱️ Planlagte jobs (heartbeat)".

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
- CSRF (v7.21): muterende kald (POST/PUT/DELETE) med `Sec-Fetch-Site` der ikke er `same-origin`/`none`, eller `Origin` der ikke matcher `Host`, afvises med 403. `/mcp` har egen Origin-kontrol. Kald uden browser-headers roeres ikke (API-noegler, scripts)
- Session-rotation (v7.21): hvert login giver ny sid, og den gamle sid slettes; SameSite=Lax beholdes
- HTML fra AI/SERP saniteres før `|safe` i skabelonen
- Netværkskald: alle med timeout; budget-guard stopper betalte API'er
- Invitationer: midlertidig adgangskode er tilfældig (12 tegn), staar kun i mailen, og `must_change_password` vises som gul bjælke i dashboardet indtil koden er skiftet
- MCP-nøgler: `cc_` + 32 tegn, kun `sha256` i DB, `Bearer` i header (aldrig query), `read`/`write`-scopes, tilbagekald pr. nøgle, `Origin`/`Host`-validering mod `CC_PUBLIC_URL` (DNS-rebinding) og samme rate-limit-tænkning som login
- MCP-hærdning (v7.17.1): klartekst-nøglen lever kun til den er vist (slettes i samme kald, TTL 15 min.), og et ukendt værktøjsnavn giver både `-32602` og en række i `api_audit`, så et nøgle der prøver navne af ikke er usynligt
- MCP-skrivning (v7.17): kun nøgler med `write` kan kalde `start_crawl`, `add_monitor`, `resolve_alarm` og `add_note`; handlingerne går gennem de samme funktioner som UI'et (validering, `normalize_url`, dublet-tjek), og alt logges i `api_audit` uden nøglen i klartekst
- **SSRF (v7.19.0)**: `assert_public_url()` afviser loopback/private/link-local/reserverede adresser og interne navne (også når et værtsnavn peger på en intern IP), og `safe_request()` følger viderestillinger manuelt (max 3 hop) og tjekker hvert hop; `normalize_url()` tjekker med, så en intern URL forklares i formularen. `CC_SSRF_ALLOW` er den eneste undtagelse
- Kendte, ikke-lukkede punkter (se ROADMAP): Telegram-kald sker inde i en åben DB-transaktion, og der er ingen CSRF-token (SameSite dækker cross-site POST)

## 11. Test og CI

- `tests/test_v8_features.py` — in-process tests: kvalitetsgate, API-budget, `/health`, sanitering, pris-monitor, crawl-historik/diff, monitor-input og opdaterings-udtræk (whitelist + traversal)
- `tests/ci_check.sh` — boot mod fake WordPress: opretter bruger via `/setup` (e-mail), tester anonym adgang (401/303), cookie-login, logout, at en invitation uden SMTP hverken opretter en bruger eller tier stille, alle sider, Autopilot-broen og fravær af tracebacks
- `tests/check_paths.py` — hver `action`/`href`/`fetch` i skabelonerne skal matche en route (fanger døde knapper)
- CI kører desuden en diff af `install.sh`s indlejrede kopier mod repo-filerne
- CI fejler, hvis `app/`, `scripts/`, `deploy/`, requirements eller start-/container-filer ændres uden at `README.md` eller `docs/` også er opdateret (`[skip docs]` i commit-beskeden springer tjekket over). `install.sh` er undtaget, fordi den er genereret og tjekkes af paritetstrinnet

## 12. Versionshistorik (kort)

- **v7.33.0** — Nye tabeller `keyword_history` (keyword, position, url, checked_at; skrives i `check_all_keywords_sync`) og `page_history` (kopi af `seopages` for hvert run, skrives sidst i `site_crawl_sync`), begge i grundskemaet og `migrate_db`, ryddes aldrig. `KEEP_DAYS` med 0 = for altid (`cutoff()` giver `"0000"`). `keyword_trends()`, `history_series()`, ruter `GET /api/trend/keyword` og `/api/trend/page`. Prioritetsbro: `cc_priority_items(skip_urls)` (plads 4-20, eget site, unik URL, højst 30), `sgap_push_priorities()` → `POST /sgap/v1/priorities` og `settings.cc_priorities_last`. Flow-blokken `prioriteter` (`WP_URL`), 18 blokke.
- **v7.32.0** — Oprydning styres af `KEEP_DAYS` (check_history/health_history/keyword_ideas/api_audit 365, løste alarmer 180), `KEEP_ROWS` (content_audits 500, flow_runs 500, optimize_runs 200) og `BACKUP_KEEP` (env `CC_BACKUP_KEEP`, 60). `login_attempts` uændret 30 dage, crawl beholder stadig kun forrige run.
- **v7.31.0** — `openrouter_complete()` deler kaldet i `_openrouter_post()`; ved kreditfejl (`ai_wants_free_retry`: 402 eller »can only afford«/»more credits«) sendes samme body med `model=AI_FREE_MODELS[0]` og `models=AI_FREE_MODELS`. `AI_LAST_FALLBACK` + info-alarm `ai`. Ny env `AI_FREE_MODELS`.
- **v7.30.1** — `AI_MODEL`-standard `google/gemini-3.8-flash`. Ansvarsdeling: Steamgears Autopilot ejer sociale opslag; CC ejer analyse, SEO og artikler (kun kladder) og læser `/snapshot`.
- **v7.30.0** — Flows: tabellerne `flows` (name, enabled, schedule `manual|hourly|daily@HH|weekly@D@HH`, `steps_json`, template, last/next run) og `flow_runs` (log pr. trin, de sidste 50). `FLOW_BLOCKS` (17 blokke: label, gruppe, krævet nøgle, funktion `(ctx, params) -> (ok, note, fund)`, tilladte parametre), `FLOW_TEMPLATES` (4), `FLOW_CONDITIONS` (altid/hvis_fund/hvis_hoej). `run_flow_sync()` deler `ctx` (url, actions, striking, missing_kw, articles) mellem blokke; en sprunget blok (ok=None) ændrer ikke "forrige fund". `flow_next_run()`, `run_due_flows_sync()` + jobbet `flows` (hvert 5. min, heartbeat 0,5 t). Lås: `flow_claim()` deler tilstand med 1-klik optimeringen. WordPress kun via `wp_push_draft` (status draft) og kun efter `quality_check`. Ruter: `POST /flows/template|save|toggle|delete|run`, `GET /api/flows/status`
- **v7.29.0** — 1-klik optimering: tabellen `optimize_runs` (scope, url, status, started/finished, `summary_json` med trin + handlinger; de sidste 20 beholdes), `OPTIMIZE_PARTS`/`OPTIMIZE_STATE`, `optimize_project_sync()` (trin: teknik, crawl, onpage, meta, indhold, soegeord, monitors — genbruger `check_domain_sync`, `site_crawl_sync`, seopages-issues + `ONPAGE_FIXES`, `rewrite_meta_sync` (højst `OPTIMIZE_AI_PAGES`=3), `local_content_optimizer` (5 sider), `check_all_keywords_sync`, `check_all_monitors_sync`), ruterne `POST /optimize/run`, `GET /api/optimize/status`, `POST /optimize/done`. Ét trins fejl vælter ikke resten; lås mod dobbeltklik. `_latest_crawl_pages()` fjerner forsiden med/uden `/`. Rettet: tomt `:class=""` i SEO-fanens crawl-linje (Alpine-fejl)
- **v7.28.1** — Funktionsrevision: `rewrite_meta_sync()` kaldte `ai_chat(temperature=...)` (fjernet i v7.25) → 500; nu uden argumentet, med `requests.RequestException`-gren og JSON-udtræk til `{titles, descriptions, note}`. `POST /monitors/add`: `expected` kræves ikke for `price`, og manglende felter giver en `monitor`-alarm + `/?tab=monitors` i stedet for en tavs 303
- **v7.28.0** — Offentlig adresse: `scripts/ultracc_setup.sh --domain <navn>` (A-posten slås op og skal være offentlig) eller `--ip` (kun offentlige IP'er; lokalnet/loopback/CGNAT/link-local afvises), `CC_HOST=0.0.0.0`, port 80 kun som root, systemd-enhederne følger `CC_HOST`/`CC_PORT`/`CC_FORWARDED_ALLOW_IPS` (`sh -c` med standardværdier), `client_ip()` stoler kun på `X-Forwarded-For` fra `TRUSTED_PROXIES`. Understi bag nginx (Ultra.cc uden Cloudflare-tunnel): `cc_base_path()`/`CC_BASE_PATH`, `BasePathMiddleware` (pure ASGI, mellem GZip og `auth_middleware`), `rewrite_html_for_base()` og `base_path_script()` (fetch-indpakning + `window.CC_BASE`), `deploy/nginx-ultracc-proxy.conf`
- **v7.27.0** — Log ind fra WordPress med ét klik: `cc_sso_secret()`, `cc_sso_push()` (POST `/cc-link` i sync, kun ved ændring), `GET /cc-sso` med `cc_sso_verify()` (HMAC, udløb ±30 s, maks. 120 s levetid, `jti` én gang, kendt e-mail). Det døde `/cc-login`-flow fra v7.17.5 er fjernet
- **v7.26.0** — Chat-fanen med MCP-connectors (GitHub, WordPress, Gmail, Google Drive m.fl.): MCP-klient (JSON + SSE, sessioner, sider), godkendelse af skrivende værktøjer (`chat_pending`), nøgler kun som hint i UI'et
- **v7.25.0** — AI via OpenRouter i stedet for aimlapi: `OPENROUTER_API_KEY`, `OPENROUTER_BASE_URL`, fælles `ai_chat()` med `AIError` for OpenRouters fejlsvar, budget på `openrouter.ai` og advarsel ved en tilbageblevet `AIMLAPI_KEY`
- **v7.24.0** — Vækst-fanen: lokal indholdsoptimerer (`local_content_optimizer`, vægtet score + termdækning), konkurrent-sammenligning mod brugerangivne URL'er, indholdsplan (`content_briefs`) og manuel linkliste (`link_targets`) — ingen API-nøgle. UI'et er samtidig moderniseret: grupperet navigation, fanebeskrivelser og fælles visuel rytme for kort, felter og knapper
- **v7.23.0** — Backup i UI: `POST /backup/now` og `POST /backup/restore` (kræver `GENDAN`), kort i fanen Moduler, `pre-restore`-backup før hver gendannelse
- **v7.22.0** — Offline dashboard: Tailwind, Alpine og Chart.js serveres fra `app/static/vendor/` i stedet for CDN
- **v7.21.0** — CSRF-beskyttelse (Origin/Sec-Fetch-Site-kontrol på muterende kald) og ny session ved hvert login
- **v7.20.0** — månedligt API-budget og job-heartbeat vises på Cockpit; jobs pakkes i `job_heartbeat()` og alarmeres ved forsinkelse eller fejl (én gang pr. tilstand)  · **Release:** de fire `.env`-nedslag står nu som ét punkt i `NEWEST`, så opstartsbanner, `/health` og login-siden viser forløbet samlet
- **v7.19.2** — rydningen kan ses i dashboardet: en blå bjælke øverst viser hvornår og af hvem `CC_ADMIN_PASSWORD` blev fjernet fra `.env`. Rækken `env_password_cleared` i `settings` holder navn og tidspunkt (aldrig koden), og "står linjen der?" læses fra filen selv
- **v7.19.1** — `.env` rydder sig selv: når standardbrugeren skifter kode under Brugere, tømmer `clear_env_admin_password()` `CC_ADMIN_PASSWORD`-linjen (kun den linje, atomisk skrivning, filmode bevaret) og nulstiller advarsels-cachet
- **v7.18.1** — advarsel når `.env`-koden er forældet: `env_password_mismatch()` sammenligner `CC_ADMIN_PASSWORD` med den gemte hash, `warn_stale_env_password()` skriver den til opstartsloggen og `alarms`, og dashboardet viser en rød bjælke (`env_password_warning`)
- **v7.18.0** — WordPress-broen er tovejs i *læsning*: `sgap_headers()` giver hvert kald `X-Command-Center` (pluginnet noterer tid, version, rute og bruger i `sgap_cc_seen`), `sgap_sync()` gemmer `status.command_center` fra `/snapshot` i `settings.sgap_snapshot`, og `cc_seen_view()` regner alderen ud ved visning (45 min. = misset runde, 2 t = tavs) til fanen Social; retningen CC → site er uændret
- **v7.17.5** — login fra WordPress: `POST /autopilot/login-link` lægger et engangslink i pluginnet (`settings.cc_login_code` = sha256 + `exp`), og `GET /cc-login` logger ind med det én gang inden for 10 min. Knappen i WordPress viser linket; CC → site-retningen er uændret
- **v7.17.4** — sletning svarer i fanen: `POST /users/delete` tager `id` som tekst (tomt/forkert id giver en forklaring i stedet for 422), afviser den sidste bruger og ukendte id'er med `del_kind` og redirecter til Brugere i stedet for Cockpit; en gennemført sletning giver `del=ok` og en info-alarm
- **v7.17.3** — invitationen afviser pladsholdere: `POST /users/invite` tjekker adressen med `normalize_email()` + `example_email_hint()` før SMTP, svarer `invite_kind=adresse|eksempel|smtp` og tilbyder **Opret alligevel** (`force=1`). Samme regel bruges af `scripts/invite.py` (`--force`)
- **v7.17.2** — invitationen svarer i sin egen formular: `POST /users/invite` redirecter til `/?tab=brugere&invite=ok|fejl&invite_msg=…`, dashboardet åbner den fane (`initial_tab`, kun kendte faner) og viser enten "sendt til X" eller mailserverens fejl. Før landede svaret på Cockpit, og en mislykket invitation var kun synlig som alarm
- **v7.17.1** — MCP-hærdning: nøglen ligger ikke længere i klartekst i databasen (rækken i `settings.api_key_once` slettes ved visning, TTL 15 min., oprydningen fjerner resten; `POST /api-keys/dismiss` er fjernet), og ukendte værktøjsnavne på `/mcp` logges nu i `api_audit`
- **v7.17** — MCP fase 2: fire skrive-værktøjer bag `write`-scope (`start_crawl`, `add_monitor`, `resolve_alarm`, `add_note`), `readOnlyHint`/`destructiveHint` i `tools/list`, audit pr. nøgle i `api_audit` (vist i UI + `scripts/api_key.py audit`) og oprydning efter 90 dage
- **v7.16** — MCP-adgang fase 1: `api_clients` med hash og scopes, `POST /mcp` (JSON-RPC, Streamable HTTP uden SSE) med syv læse-værktøjer, `Origin`/`Host`-validering og `scripts/api_key.py`
- **v7.15** — login med e-mail i stedet for brugernavn (migrering beholder gamle brugernavne som fallback) · invitation på mail med midlertidig adgangskode og `must_change_password` · fælles `send_email()` til alarmer og invitationer
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
  `login_attempts(username, ip, ok, created_at)` med 30 dages oprydning. `client_ip()` bruger
  `X-Forwarded-For` kun når socket-adressen er en betroet proxy (`TRUSTED_PROXIES` = 127.0.0.1, ::1 +
  `CC_FORWARDED_ALLOW_IPS`, `*` = alle), og tager så den højre-mest adresse, der ikke selv er en betroet proxy.
  Ellers socket-adressen. Før v7.28 blev første hop brugt fra alle, så en klient direkte på IP'en kunne omgå
  login-låsen ved at skifte header.
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


## 16. Tider: lokal tid og UTC (v7.14)

Tidsstempler skrives fortsat som **lokal tid** (`now_iso()`), fordi UI, jobplanlægningen (APScheduler
på `Europe/Copenhagen`) og historikken er dansk tid. Det er læsbart, men ikke entydigt: 02:30 findes
ikke den nat sommertiden starter, og findes to gange den nat den slutter. Derfor gemmes **UTC ved
siden af** de tider hvor det betyder noget:

| Kolonne | Indhold |
|---|---|
| `socialqueue.created_at` + `created_at_utc` | oprettelsestid, lokal + UTC |
| `socialqueue.scheduled_at` + `scheduled_at_utc` | planlagt udgivelse, lokal + UTC |

Konverteringen sker ved **grænserne**:

- **Ind**: `/social/add` får `scheduled_at` fra et `datetime-local`-felt (lokal tid), kalder
  `local_to_utc()` og gemmer begge former. En ikke-eksisterende tid afvises med en alarm; en tvetydig
  tid vælger den **første** forekomst (`fold=0`) — dokumenteret i koden, ikke tilfældigt.
- **Ud**: UI viser lokal tid, CSV har begge kolonner plus `timezone`, og payloaden til Social
  Autopilot har `scheduled_at_utc`, `scheduled_at_local` og `timezone`.

Zonen sættes med `CC_TZ`; en ukendt zone falder tilbage til `Europe/Copenhagen` i stedet for at
crashe opstarten. Gamle rækker backfill'es i `migrate_db()`, hvor den lokale tid fortolkes i `CC_TZ`.

## 17. Ruteoversigt

Alle ruter registreres i `app/main.py` med `@app.get`/`@app.post`. Undtagen `/setup`, `/login`,
`/health` og `/static` kræver de en indlogget bruger (cookie-session, se §3); API-svar til
`/api/*` er JSON, resten er formular-POST med redirect. `/static` er et mount, og FastAPI tilføjer
selv `/docs`, `/openapi.json` og `/redoc`. `tests/check_paths.py` rapporterer det aktuelle antal
ved hvert CI-løb, så tabellen og koden ikke kan glide fra hinanden ubemærket.

| Område | Ruter |
| --- | --- |
| Opstart og auth | `GET /setup`, `POST /setup`, `GET /login`, `POST /login`, `GET /logout` |
| Brugere | `POST /users/invite` (mail med midlertidig kode), `POST /users/delete` (svar `del=ok|fejl` + `del_kind=slettet|sidste|findes-ikke|ugyldig`), `POST /users/password` |
| Login fra WordPress | `POST /autopilot/login-link` (kræver session) sender adresse + nøgle til pluginnet nu (`cc_sso_push(force=True)`) og svarer i Social med `cc_link=ok|fejl`; `GET /cc-sso?t=<billet>` (uden session) logger ind med en signeret billet fra pluginnet og sender ellers til `/login?sso=ugyldig|udloebet|brugt|ukendt-bruger|ikke-forbundet|laast` |
| API-nøgler | `POST /api-keys/create`, `POST /api-keys/revoke` (nøglen vises én gang og slettes fra `settings` i samme kald) |
| MCP | `POST /mcp` — JSON-RPC 2.0 (`initialize`, `ping`, `tools/list`, `tools/call`) med Bearer-nøgle |
| Dashboard | `GET /` |
| Domæner | `POST /domains/check`, `POST /domains/add`, `POST /domains/delete`, `GET /api/history/{domain_id}` |
| SEO og crawl | `POST /seo/audit`, `POST /seo/crawl`, `POST /seo/crawl/delete`, `POST /seo/linksuggest`, `POST /seo/rewrite`, `GET /api/crawl/status`, `GET /api/crawl/diff`, `GET /api/sitemap.xml`, `GET /api/redirects`, `GET /api/duplicates` |
| Keywords | `POST /keywords/add`, `POST /keywords/delete`, `POST /keywords/check`, `POST /keywords/ideas`, `POST /keywords/difficulty`, `GET /api/visibility` |
| Artikler | `POST /articles/generate`, `POST /articles/push`, `POST /articles/delete`, `POST /articles/autopilot`, `POST /articles/meta`, `POST /articles/score` |
| Chat og connectors | `GET /api/chat/state`, `GET /api/chat/{cid}`, `POST /chat/send`, `POST /chat/approve` (`decision=godkend|afvis`), `POST /chat/delete` (JSON) · `POST /connectors/add`, `POST /connectors/refresh`, `POST /connectors/toggle`, `POST /connectors/delete` (redirect til `?tab=chat&conn=ok|fejl`) |
| Vækst | `POST /backlinks/prospect`, `POST /backlinks/delete`, `POST /outreach/scan`, `POST /serp/discover`, `POST /serp/gap`, `POST /competitors/delete` |
| Links, social og bro | `POST /links/check`, `POST /social/add`, `POST /social/delete`, `GET /social/export.csv`, `POST /social/to-autopilot`, `POST /autopilot/sync` |
| Monitors og historik | `POST /monitors/add`, `POST /monitors/delete`, `POST /monitors/check`, `GET /api/health-history` |
| Alarmer | `POST /alarms/resolve`, `POST /alerts/test`, `GET /api/alerts/status` |
| AI | `POST /ai/visibility` |
| Indstillinger og noter | `POST /settings/module`, `POST /settings/strategy`, `POST /notes/add`, `POST /notes/delete` |
| Drift og opdatering | `GET /health`, `GET /api/update`, `POST /update/check`, `POST /update/apply`, `POST /api/update/check`, `POST /api/update/apply`, `POST /self-update` (alias) |

