# Command Center — statusnotat til Claude

**Opdateret:** 3. november 2026 · **Version:** 7.17.2 · **Branch:** `main` · **Seneste commit:** se `git log -1`
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
kørte grønt på `627cd87`. CI tjekker desuden at alle 17 indlejrede filer i `install.sh` matcher repoet.

## Ændringer i denne arbejdsperiode

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
  navn@domaene.dk --print` opretter brugeren og udskriver den færdige mail, så den kan sendes fra en
  anden mailkonto (fx Gmail) når `SMTP_HOST` ikke kan sættes op på serveren.
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

### Opstart, login-IP og kørselsrapport (v7.13)
- `NEWEST` + `NEWEST_LINE` i `app/main.py` er kilden til "hvad er nyt". `log_startup()` skriver
  version + nyheder til stdout, `app/data/startup.log` og `settings.last_start`; `/health` har
  `newest` og `started_at`. `run.sh`, `run.bat`, `restart.sh`, `update.sh` og `install.sh` viser dem.
- Login-spor: `users.last_login_ip/last_login_at`, `sessions.ip`, `login_attempts` (30 dage).
  `client_ip()` bruger X-Forwarded-For (foerste hop) med socket som reserve.
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
- `scripts/screenshots.py` tager `cc-login.png` og alle 14 fanebilleder i `docs/img/` mod en kørende
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
  saet `FONTCONFIG_FILE`/`FONTCONFIG_PATH`. Derefter kan alle 14 faner fotograferes headless.
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
- CI advarer (men fejler ikke) når `docs/img/` er ældre end `app/templates/dashboard.html`. Trinnet
  "Screenshots are not older than the dashboard" sammenligner commit-tidspunkter (ikke fil-mtimes,
  som checkout nulstiller) og henviser til `scripts/screenshots.py`.

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
2. **SSRF-beskyttelse** på de syv URL-felter; ingen IP-/værts-guard findes (`ipaddress` er ikke importeret).
3. **CSRF + session-rotation**: ingen CSRF-token og ingen session-rotation ved login i dag.
4. **Offline dashboard-assets**: Tailwind, Alpine og Chart.js hentes stadig fra CDN.
5. **Backup/restore i UI**: backup skrives på disk, men der er ingen visning eller gendan-rute.
6. **Månedligt budget i UI**: tallet findes i `/health`, men ikke på Cockpit.
7. **Job-heartbeat (dead-man's switch)**: ingen pr.-job `last_run`/`next_run`.
8. **E2E-test af opdateringen** mod en fake GitHub-API.
9. **Tests for login-rate-limit og job-guards** (dækket indirekte i dag).
10. **Alarmer, resten**: maintenance windows, ugentlig digest, evt. Apprise. Dedup, stille timer, backoff
    og fire kanaler er færdige i v7.12.

Færdige punkter fra den gamle liste: alarm-routing (v7.12), API-nøgler/MCP fase 1-2 (v7.16-v7.17) og
MCP-hærdning (v7.17.1). De står nu under "Færdigt" i roadmappen i stedet for under "Næste".

## Åbne tråde

- Brugeren delte et Claude-share-link (`claude.ai/code/...`). Det kan **ikke** hentes herfra:
  Cloudflare svarer 403 ("Just a moment…") og reader-proxyen afviser IP'en. Afvent at brugeren
  paster indholdet (diff/plan) — og mind dem om at fjerne tokens fra teksten.
- Ingen secrets i repoet: brug `.env` (gitignored) eller miljøvariabler. `GITHUB_TOKEN`,
  `SERPAPI_KEY`, `AIMLAPI_KEY`, `WP_APP_PASSWORD` og `TELEGRAM_*` må ikke committes.
- Vue: hold UI-tekster på dansk, og opdater README + manual + roadmap i samme ændring som koden.
