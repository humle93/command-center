# Command Center — Roadmap

Status pr. **3. november 2026 (v7.17.2)**. Koden er 4.579 linjer i `app/main.py`, 69 ruter, 25 tabeller,
8 jobs, 11 moduler og 14 faner. Rækkefølgen i "Næste" er den anbefalede prioritering: sikkerhed og
driftsstabilitet før nye features.

**Genoptrænet 3. november 2026.** Listen er gennemgået mod koden — ikke mod tidligere noter. Tre punkter
stod stadig som "Næste", selvom de er implementeret: alarm-dedup og Telegram ud af transaktionen (v7.12)
samt API-nøgler og MCP (v7.16-v7.17). Samtidig manglede det største hul helt: **Google Search Console**.
Derfor har hvert punkt i "Næste" nu en linje med *hvad der findes i koden i dag*, så status kan tjekkes
med et grep i stedet for at blive gættet. Et punkt flyttes først til "Færdigt", når koden **og** testene
findes.

## Dokumentation i repoet

| Fil | Rolle |
| --- | --- |
| [`README.md`](../README.md) | Funktioner, installering, opdatering og sikkerhed |
| [`Command_Center_Bruger_og_Systemmanual.md`](Command_Center_Bruger_og_Systemmanual.md) | Bruger- og systemmanual: faner, moduler, nginx, WP-bro, `.env` |
| [`Command_Center_Dokumentation.md`](Command_Center_Dokumentation.md) | Arkitektur: ruter, tabeller, jobs og sikkerhedsmodel |
| [`Command_Center_Install_Script.md`](Command_Center_Install_Script.md) | Installation og `install.sh` |
| [`Command_Center_MCP.md`](Command_Center_MCP.md) | Research og plan for MCP-adgang: protokol, nøgler, OAuth, værktøjer |
| [`agents-md/steamgears-site.md`](agents-md/steamgears-site.md) | Sammenlagt `AGENTS.md` til `steamgears-site` (lokal §1-§6 + fælles §7-§10) |
| `docs/ROADMAP.md` | Dette dokument: dokumentation, færdigt, næste, senere og endgoal |
| [`CLAUDE.md`](../CLAUDE.md) | Status/handoff, kendte begrænsninger og næste skridt |
| [`AGENTS.md`](../AGENTS.md) | Faste regler for agenter (docs i samme commit, test før commit) |

## Færdigt

| Version | Indhold |
| --- | --- |
| **v7.17.2** | **Invitationen svarer selv**: `POST /users/invite` sender resultatet med tilbage (`/?tab=brugere&invite=ok|fejl&invite_msg=…`), dashboardet åbner Brugere-fanen og viser enten "sendt til X" eller mailserverens fejl. Før forsvandt svaret på Cockpit, og en invitation uden SMTP lignede en mail der var blevet væk · begge suiter dækker ok- og fejl-stien |
| **v7.17.1** | **MCP-hærdning** efter adgangsrevision: klartekst-nøglen ligger ikke længere i databasen — rækken i `settings.api_key_once` slettes i samme kald som dashboardet viser den (TTL 15 min. som sikkerhedsnet, oprydningen fjerner resten), og `POST /api-keys/dismiss` er fjernet · ukendte værktøjsnavne på `/mcp` giver `-32602` **og** en række i `api_audit`, så et nøgle der prøver navne af ikke er usynligt · begge suiter dækker begge dele |
| **v7.17** | **MCP fase 2 (skriv)**: `start_crawl`, `add_monitor`, `resolve_alarm` og `add_note` bag `write`-scope · `start_crawl` afvises når et crawl kører og svarer med overslag + status-sti · `add_monitor` genbruger samme url+type · `readOnlyHint`/`destructiveHint` i `tools/list` · **audit pr. nøgle** i `api_audit` (værktøj, ok/fejl, årsag, varighed) vist i fanen Brugere og via `scripts/api_key.py audit`, ryddet efter 90 dage · begge testsuiter dækker scope-afvisning, skrivning, dublet, audit og at nøglen ikke ligger i auditten |
| **v7.16** | **MCP-adgang, fase 1**: hver klient får sin egen nøgle (`api_clients`, kun sha256, `read`/`write`-scopes, tilbagekald pr. nøgle) i fanen **Brugere** · `POST /mcp` taler JSON-RPC 2.0 efter spec `2026-07-28` (Streamable HTTP med JSON-svar) med syv læse-værktøjer: `health`, `crawl_summary`, `keywords`, `monitors`, `alarms_open`, `notes`, `history` · `Origin`/`Host`-validering mod `CC_PUBLIC_URL`, `401` + `WWW-Authenticate` uden nøgle, `-32003` uden `read`-scope · `scripts/api_key.py` til serveren · begge testsuiter dækker nøgler, værktøjer, scopes, tilbagekald og ugyldig JSON |
| **v7.15** | E-mail er login-id (små bogstaver, valideret) i stedet for brugernavn; gamle brugernavne virker stadig som fallback efter migreringen · **Inviter bruger** sender en mail med en midlertidig adgangskode via `send_email()`; brugeren oprettes først når mailen er sendt, og skal skifte koden ved første login (`must_change_password` + gul bjælke) · ingen invite-tokens eller links · begge testsuiter dækker mail-login og invitationens fejlsti uden SMTP |
| **v7.14.x** | Planlagt tid gemmes som lokal tid + UTC, og ugyldig sommertid afvises i stedet for at gættes · **Autopilot-broen er idempotent**: `/social/to-autopilot` låser rækken (`social_claim()`) før kaldet, så et dobbeltklik eller et genforsøg ikke giver to kladder; svar fra WordPress frigiver låsen igen, mens en timeout blokerer med status `sendt? (svar udeblev)` · begge testsuiter dækker dobbeltklik |
| **v7.13.x** | Screenshot-værktøj (`scripts/screenshots.py`, alle 14 faner + login) · CI advarer når `docs/img/` er ældre end dashboard-skabelonen · CI-badge og screenshot-afsnit i README · `docs/img/` opdateret til den kørende UI |
| **v7.12** | **Alarmer er en kø, ikke et inline-kald** (tidligere "Næste" 2-3, nu færdigt): `add_alarm()` skriver i `alert_outbox` pr. kanal (telegram/e-mail/ntfy/webhook), og `job_drain_alerts` leverer hvert minut med backoff 30 s → 2 min → 10 min → 1 t og derefter `failed` · **dedupe** pr. `sha256(type|message)` i `ALERT_DEDUPE_MINUTES` (standard 180), **stille timer** i `ALERT_QUIET_HOURS` (fx `23-7`) udskyder alt under "kritisk" · webhook signeres efter Standard Webhooks (`webhook-id`, `webhook-timestamp`, `webhook-signature: v1,…`), e-mail via `smtplib` med STARTTLS/SSL og 15 s timeout · fanen **Alarmer** viser kanaler, test-knapper (`POST /alerts/test`) og fejlede leveringer; `GET /api/alerts/status` som JSON · enhedstestene dækker kanalvalg, signatur, dedupe, backoff, stille timer og at `add_alarm` ikke laver HTTP |
| **v7.11** | Brugere + sessioner (PBKDF2, `/setup`, "Brugere"-fane) i stedet for token-login · GitHub-opdatering (tjek/opdater med backup og fil-whitelist, dagligt tjek 05:00) · nginx/Ultra.cc-deploy (proxy-headers, systemd user-unit, nginx-config) · rettelser fra kodegennemgang: saniteret artikel-HTML (XSS), `.env` læses før konfiguration, pris-monitor sammenligner tal, crawl-diff virker (to runs gemmes), `/monitors/add` validerer input, HTTPS-advarsel via `request.url.scheme`, ingen dubleret side-hentning, SSL-tjek uden port-fejl, lokal-tids-cutoffs i oprydningen · link-audit i CI · GitHub-opdatering erstatter "kør install.sh fra nettet" · opdateringen installerer requirements og genstarter selv (`scripts/update.sh`, `scripts/restart.sh`) |
| **v7.10** | Kvalitetsgate før WP-push · API-budget pr. måned med 80 %/100 %-alarmer · rigtig `/health` (DB/disk/forbrug) · CI med fake WordPress og Autopilot-bro |
| **v7.9** | Daglig DB-backup (14 kopier) + pre-update-backup · opstarts-selvtest med alarmer · login-rate-limit · HTTPS-advarsel i UI · smoke-test-script · Windows-startscript |
| **v7.8** | SEO-strategi-vælger (AdSense/Affiliate/Backlink) med automatisk pre-flight-checkliste |
| **v7.7** | Growth Pack: autopilot, backlink-prospector, keyword-ideer, visibility-index · guidet navigation |
| **v7.5–7.6** | Pull-bro via GitHub · WAL/busy-timeout/indekser · connection-pooling + gzip · daglig oprydning |
| **v7.4** | Crawl-diff, redirect-audit, sitemap-generator, keyword-sværhedsgrad, AI titel/meta-rewrite |

## Næste (anbefalet rækkefølge)

| # | Opgave | Hvad der findes i koden i dag | Hvorfor nu | Omfang |
| --- | --- | --- | --- | --- |
| 1 | **Google Search Console (read-only)** | Intet. `gsc_daily`/`gsc_queries` bliver kun *droppet* i `migrate_db` hvis de er tomme; der er ingen klient, ingen tabeller og ingen visning | Det største hul efter Juno-fjernelsen: uden GSC-data er positioner, visninger og "striking distance" gætværk, og backlink- og decay-arbejdet kan ikke måles | L |
| 2 | **SSRF-beskyttelse på alle udgående kald** | Ingen IP- eller værts-guard: `ipaddress`, `is_private` og `is_loopback` findes ikke i `app/main.py`. URL'er valideres kun for scheme/værtsnavn (`normalize_url`), og der hentes videre med `HTTP.get`/`HTTP.post` | Syv URL-felter (`/links/check`, `/monitors/add`, `/seo/crawl`, `/outreach/scan`, `/domains/add` m.fl.) henter vilkårlige værter — også `127.0.0.1`, `169.254.169.254` og interne hostnavne. En allow-list og blokering af private IP'er lukker den flade | M |
| 3 | **CSRF + session-rotation** | Ingen CSRF-token nogen steder (`grep -i csrf` = 0 træf). Sessionen roterer ikke ved login; `sessions` får først en ny række ved næste login | SameSite dækker det meste, men ikke alt (gamle browsere, subdomæner, `SameSite=None`-fremtid). Token pr. formular + ny session ved login/logout er billigt at lave nu | S |
| 4 | **Offline dashboard** | Tre CDN-afhængigheder i `dashboard.html`: `cdn.tailwindcss.com`, `alpinejs` og `chart.js@4.4.1` fra jsdelivr (+ to `preconnect`) | Uden internet (eller med blokeret CDN) er UI'et ustylet og uden Alpine — hele dashboardet er dødt, mens API'et kører. Bundl dem lokalt eller byg et Tailwind-stylesheet | M |
| 5 | **Backup/restore i UI** | `job_backup_db` og `backup_db_sync()` skriver `backups/cc-<tag>-<tid>.db` (14 kopier) og alarmerer ved fejl. Der er **ingen** rute eller knap til at se eller gendanne dem (`grep -i restore` = 0 træf) | Rollback kræver i dag SSH. En liste + "gendan" med bekræftelse gør backupen brugbar, når det gælder | M |
| 6 | **Månedligt budget i UI** | `API_BUDGETS`, `budget_usage()` og `budget_spend()` findes, og `/health` viser `budget` pr. tjeneste. Dashboardet nævner det ikke (`grep -i budget` i `dashboard.html` = 0) | Forbruget er allerede beregnet — det mangler kun på Cockpit, hvor man beslutter sig | S |
| 7 | **Job-heartbeat (dead-man's switch)** | Kun `last_run_report()` (opstart, åbne alarmer, tællinger) og `settings.last_start`. Ingen pr.-job `last_run`/`next_run`, ingen alarm hvis et job holder op med at køre | Et job der stille stopper (crawl, backup, alert-drain) opdages først, når nogen savner resultatet. Det er præcis den slags fejl Endgoal punkt 5 kræver at systemet selv finder | S |
| 8 | **Ende-til-ende-test af opdateringen** | `tests/ci_check.sh` tjekker kun at `/api/update` svarer med et repo. Der er ingen kørsel mod en fake GitHub-API (whitelist, `..`-afvisning, tarball, genstart) | Opdateringskæden er den mest risikable kode i repoet (den overskriver filer og genstarter appen) og er kun dækket af enhedstests for mode/opt-out/whitelist | S |
| 9 | **Tests for auth-middleware og jobs** | `/setup`, logout og sessioner er dækket i `ci_check.sh`; login-låsen (`_LOGIN_MAX_FAILS`, `_LOGIN_LOCK_SECONDS`, 5 fejl = 10 min.) og job-guards er kun dækket indirekte | Rate-limit og job-guards er sikkerhedskritiske og lette at brække ved en refaktorering. Test dem direkte, før der bygges mere ovenpå | S |
| 10 | **Alarmer, resten** | Dedup, stille timer, backoff og fire kanaler er færdige (v7.12). Tilbage: maintenance windows, ugentlig digest og eventuelt Apprise som ekstra kanal | Resten er "nice to have" nu hvor spam-problemet er løst — derfor sidst i rækken | S |

## Senere / idéer

- **Planlagt crawl** (ugentligt) med alarm ved score-fald, og crawl pr. domæne i stedet for én global
- **Rank-tracking i dybden**: device, geo, SERP-features (inkl. AI Overviews), konkurrent-positioner,
  alarm ved fald og "quick wins" (position 8–20). I dag gemmes position pr. keyword uden disse dimensioner
- **Content optimizer**: term-map fra top 10 → 0–100 score → rangeret fix-liste; re-score publicerede
  artikler for decay (kvalitetsgaten findes, scoringsmodellen gør ikke)
- **Keyword-volumen, intent og clustering** (Google Ads API eller DataForSEO)
- **Backlink-monitorering** via GSC/CSV: referring domains, nye/tabte, anchors, disavow-eksport
- **Content-gap-historik** pr. keyword med udvikling over tid (i dag kun seneste række)
- **Site-wide change monitoring** med changelog (og evt. screenshot-diff)
- **Crawler-opgraderinger**: JS-rendering, hreflang, field Core Web Vitals, IndexNow/indexation
- **WordPress-publicering med planlagt dato** (i dag kun kladde)
- **Flere brugere med roller** (læse/skrive/admin) — nu er alle brugere ligestillede
- **2FA (TOTP)** for brugere, som eksponerer dashboardet mod internettet
- **MCP fase 3**: OAuth 2.1 + Protected Resource Metadata (RFC 9728) hvis fremmede klienter skal kunne
  koble sig på uden en nøgle, og eventuelt `server.json` til MCP-registry
- **Docker-healthcheck + Compose-secrets** i stedet for `.env` i containeren
- **i18n**: UI-tekster er danske og hardcodede i skabelonerne
- **install.sh-afvikling**: undgå de indlejrede filkopier (fx udgiv en zip/tarball eller brug
  GitHub-opdateringen til første install)
- **Ekstern overvågning**: valgfri heartbeat til Uptime Kuma/healthchecks.io
- **SERP-udgiftsprognose**: vis estimeret forbrug for resten af måneden baseret på kørende keywords
- **Screenshot-opdatering** af `docs/img/` — kør `scripts/screenshots.py` efter større UI-ændringer
  (senest gjort mod v7.13.x-UI'et)

## Kendte begrænsninger (bevidste valg)

- **En proces, én database**: SQLite + APScheduler betyder, at appen ikke kan skaleres vandret, og at et job
  deler event-loop med HTTP. Det er et bevidst valg for et selvhostet værktøj til én bruger/organisation.
- **Ingen websockets**: status hentes ved sideskift/redirect, ikke live. Crawl-status har en JSON-endpoint.
- **`install.sh` duplikerer kildekoden** (CI tjekker paritet, 17 indlejrede filer). Det gør første install
  mulig uden `git`, men koster vedligeholdelse — se "Senere".
- **Login-låsen ligger i hukommelsen** (`_LOGIN_FAILS` pr. IP): en genstart nulstiller den. Selve
  forsøgene logges i `login_attempts` i 30 dage.
- **AI-kvalitet afhænger af ekstern model**: kvalitetsgaten fanger længde/keyword/H2, ikke faktuelle fejl.
- **Screenshots** holdes opdaterede med `scripts/screenshots.py`, og CI advarer når de er ældre end
  dashboard-skabelonen; enkelte docs-afsnit kan stadig være ældre end koden.
- **Headless screenshots kræver fontconfig**: uden en `fonts.conf` (via `FONTCONFIG_FILE`) aborterer
  Chromium med `SkFontMgr_FontConfigInterface ... Not implemented`. Det rammer kun optagelsen, ikke appen.

## Endgoal

**Command Center skal være steamgears' egen, selvhostede SEO- og driftscentral — ét sted hvor daglig
drift, teknisk SEO, indholdsproduktion og vækstarbejde bliver overvåget, prioriteret og delvist
automatiseret, uden abonnementer og uden at data forlader egen server.**

Når målet er nået:

1. **Én indgang til driften.** Cockpit viser uptime, svartid, SSL, opdateringsstatus og åbne alarmer, og
   hver alarm har en kanal, en modtager og en vej til "løst".
2. **Teknisk SEO er proaktivt.** Crawl, redirect-audit, duplikater og sitemap kører planlagt, og et nyt
   problem giver en alarm samme dag — ikke en gennemgang en gang om måneden.
3. **Indholdet produceres mod et målt marked.** Artikler skrives ud fra faktiske SERP-konkurrenter og den
   valgte strategi, går gennem kvalitetsgaten og lander som kladde — ikke som automatisk publicering.
4. **Væksten er systematiseret.** Keywords, positioner, visibility-index og backlink-prospects giver en
   pipeline fra idé til rangering, med tal der kan følges over tid.
5. **Systemet er kedeligt at drive.** Selvtest, backup med restore, smoke-test og tydelige logs gør, at
   fejl opdages af systemet selv — ikke af kunden eller en manuel gennemgang.
6. **Alt kører på egen server.** FastAPI + SQLite bag nginx/TLS, egne data og egne nøgler. Skalering sker
   ved at gøre det eksisterende mere sikkert og testet, ikke ved at lægge flere tjenester ovenpå.

Succeskriterium: **en hel uge hvor ingen SEO- eller driftsfejl opdages manuelt**, fordi Command Center
allerede har fanget, prioriteret og rapporteret dem.

Roadmap-punkterne er ikke tilfældige: **SSRF-beskyttelse, CSRF/session-rotation og offline
dashboard-assets** (punkt 2-4) gør systemet sikkert og selvstændigt nok til punkt 6; **backup/restore i
UI og job-heartbeat** (punkt 5 og 7) giver punkt 5 sammen med den alarmkø, der allerede er færdig;
**planlagt crawl med score-alarm og crawler-opgraderinger** giver punkt 2; og **GSC-data, content
optimizer samt keyword-volumen/intent** (punkt 1 og "Senere") giver punkt 3 og 4. Rækkefølgen er bevidst:
sikkerhed og driftsstabilitet før nye features, fordi et system der ikke kan stoles på, ikke kan
automatisere noget som helst.

## Sådan holder vi den ærlig

Roadmappen er kun nyttig, hvis den ikke samler støv. Derfor:

1. Hvert punkt i "Næste" har en **verifikationslinje** — et grep, en rute eller en tabel, man kan tjekke.
   Kan man ikke finde det i koden, er punktet ikke færdigt.
2. Er et punkt gennemført, flyttes det til "Færdigt" **med** den version og de tests, der dækker det.
3. Nye prioriteter indsættes i rækkefølgen med en begrundelse — ikke bare som idé nederst.
4. Roadmappen opdateres i **samme commit** som ændringen, jf. [`AGENTS.md`](../AGENTS.md) §2 og §9.

## Sådan bidrager du

1. Ret kildefilerne (ikke `install.sh`), og kør:
   `python3 tests/test_v8_features.py && bash tests/ci_check.sh`
2. Opdater `README.md` og relevante docs i samme ændring — og denne roadmap, hvis noget flytter sig.
3. Ny funktion? Tilføj en test i `tests/test_v8_features.py` (in-process) eller `tests/ci_check.sh` (boot/HTTP)
