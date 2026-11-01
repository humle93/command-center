# Command Center — Roadmap

Status pr. **november 2026 (v7.13.x)**. Rækkefølgen i "Næste" er den anbefalede prioritering: sikkerhed og
driftsstabilitet før nye features.

## Dokumentation i repoet

| Fil | Rolle |
| --- | --- |
| [`README.md`](../README.md) | Funktioner, installering, opdatering og sikkerhed |
| [`Command_Center_Bruger_og_Systemmanual.md`](Command_Center_Bruger_og_Systemmanual.md) | Bruger- og systemmanual: faner, moduler, nginx, WP-bro, `.env` |
| [`Command_Center_Dokumentation.md`](Command_Center_Dokumentation.md) | Arkitektur: ruter, tabeller, jobs og sikkerhedsmodel |
| [`Command_Center_Install_Script.md`](Command_Center_Install_Script.md) | Installation og `install.sh` |
| `docs/ROADMAP.md` | Dette dokument: dokumentation, færdigt, næste, senere og endgoal |
| [`CLAUDE.md`](../CLAUDE.md) | Status/handoff, kendte begrænsninger og næste skridt |
| [`AGENTS.md`](../AGENTS.md) | Faste regler for agenter (docs i samme commit, test før commit) |

## Færdigt

| Version | Indhold |
| --- | --- |
| **v7.13.x** | Screenshot-værktøj (`scripts/screenshots.py`, alle 14 faner + login) · CI advarer når `docs/img/` er ældre end dashboard-skabelonen · CI-badge og screenshot-afsnit i README · `docs/img/` opdateret til den kørende UI |
| **v7.11** | Brugere + sessioner (PBKDF2, `/setup`, "Brugere"-fane) i stedet for token-login · GitHub-opdatering (tjek/opdater med backup og fil-whitelist, dagligt tjek 05:00) · nginx/Ultra.cc-deploy (proxy-headers, systemd user-unit, nginx-config) · rettelser fra kodegennemgang: saniteret artikel-HTML (XSS), `.env` læses før konfiguration, pris-monitor sammenligner tal, crawl-diff virker (to runs gemmes), `/monitors/add` validerer input, HTTPS-advarsel via `request.url.scheme`, ingen dubleret side-hentning, SSL-tjek uden port-fejl, lokal-tids-cutoffs i oprydningen · link-audit i CI · GitHub-opdatering erstatter "kør install.sh fra nettet" · opdateringen installerer requirements og genstarter selv (`scripts/update.sh`, `scripts/restart.sh`) |
| **v7.10** | Kvalitetsgate før WP-push · API-budget pr. måned med 80 %/100 %-alarmer · rigtig `/health` (DB/disk/forbrug) · CI med fake WordPress og Autopilot-bro |
| **v7.9** | Daglig DB-backup (14 kopier) + pre-update-backup · opstarts-selvtest med alarmer · login-rate-limit · HTTPS-advarsel i UI · smoke-test-script · Windows-startscript |
| **v7.8** | SEO-strategi-vælger (AdSense/Affiliate/Backlink) med automatisk pre-flight-checkliste |
| **v7.7** | Growth Pack: autopilot, backlink-prospector, keyword-ideer, visibility-index · guidet navigation |
| **v7.5–7.6** | Pull-bro via GitHub · WAL/busy-timeout/indekser · connection-pooling + gzip · daglig oprydning |
| **v7.4** | Crawl-diff, redirect-audit, sitemap-generator, keyword-sværhedsgrad, AI titel/meta-rewrite |

## Næste (anbefalet rækkefølge)

| # | Opgave | Hvorfor | Omfang |
| --- | --- | --- | --- |
| 1 | **SSRF-beskyttelse på alle udgående kald** | URL-felter (`/links/check`, `/monitors/add`, `/seo/crawl`, `/outreach/scan`, `/domains/add`) henter vilkårlige værter — også `127.0.0.1` og link-local. En vært-allow-list/lokale IP'er blokeret lukker den flade | M |
| 2 | **Alarm-hygiejne** | Samme fejl alarmerer igen hver 6. time/hver time (domæne nede, monitor) og spammer Telegram. Dedup på `(type, message)` indtil alarmen resolves, plus "quiet hours" | S |
| 3 | **Telegram ud af DB-transaktionen** | `add_alarm()` kalder Telegram synkront inde i en åben skrive-transaktion (op til 8 s lås). Læg notifikationer på en kø/worker | S |
| 4 | **CSRF + session-rotation** | Der er ingen CSRF-token (SameSite dækker det meste), og sessionen roterer ikke ved login. Token pr. formular + ny session ved login/logout | S |
| 5 | **Tests for auth-middleware og jobs** | Rate-limit, `/setup`-lukning, API-sessioner og job-guards er kun dækket indirekte | S |
| 6 | **Offline dashboard** | Tailwind, Alpine.js og Chart.js hentes fra CDN. Bundl dem lokalt (eller byg Tailwind-stylesheet) så UI'et også virker uden internet | M |
| 7 | **Monthly budget-visning i UI** | Forbruget findes i `/health`, men vises ikke i dashboardet | S |
| 8 | **Backup/restore i UI** | Backups findes på disk; en liste + "gendan"-knap med bekræftelse gør rollback mulig uden SSH | M |
| 9 | **Ende-til-ende-test af opdateringen** | Kæden er dækket af enhedstests (mode, opt-out, whitelist), men ikke af en kørsel mod en fake GitHub-API | S |

## Senere / idéer

- **Planlagt crawl** (ugentligt) med alarm ved score-fald, og crawl pr. domæne i stedet for én global
- **Content-gap-historik** pr. keyword med udvikling over tid (i dag kun seneste række)
- **WordPress-publicering med planlagt dato** (i dag kun kladde)
- **Flere brugere med roller** (læse/skrive/admin) — nu er alle brugere ligestillede
- **2FA (TOTP)** for brugere, som eksponerer dashboardet mod internettet
- **Docker-healthcheck + Compose-secrets** i stedet for `.env` i containeren
- **i18n**: UI-tekster er danske og hardcodede i skabelonerne
- **Screenshot-opdatering** af `docs/img/` — ✅ opdateret med `scripts/screenshots.py` mod v7.13.x-UI'et; kør den igen efter større UI-ændringer
- **install.sh-afvikling**: undgå de indlejrede filkopier (fx udgiv en zip/tarball eller brug GitHub-opdateringen til første install)
- **Ekstern overvågning**: valgfri heartbeat til Uptime Kuma/healthchecks.io
- **Alarm-routing (v7.12)**: SMTP, ntfy, signeret webhook, dedupe og stille timer er på plads; mangler
  Apprise, maintenance windows og ugentlig digest
- **SERP-udgiftsprognose**: vis estimeret forbrug for resten af måneden baseret på kørende keywords

## Kendte begrænsninger (bevidste valg)

- **En proces, én database**: SQLite + APScheduler betyder, at appen ikke kan skaleres vandret, og at et job
  deler event-loop med HTTP. Det er et bevidst valg for et selvhostet værktøj til én bruger/organisation.
- **Ingen websockets**: status hentes ved sideskift/redirect, ikke live. Crawl-status har en JSON-endpoint.
- **`install.sh` duplikerer kildekoden** (CI tjekker paritet). Det gør første install mulig uden `git`, men
  koster vedligeholdelse — se "Senere".
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
dashboard-assets** gør systemet sikkert og selvstændigt nok til punkt 6; **alarm-routing og -hygiejne,
backup/restore i UI og job-heartbeat** giver punkt 5; **planlagt crawl med score-alarm og
crawler-opgraderinger** giver punkt 2; og **content optimizer, keyword-volumen/intent og GSC-/rank-data**
giver punkt 3 og 4. Rækkefølgen er bevidst: sikkerhed og driftsstabilitet før nye features, fordi et
system der ikke kan stoles på, ikke kan automatisere noget som helst.

## Sådan bidrager du

1. Ret kildefilerne (ikke `install.sh`), og kør:
   `python3 tests/test_v8_features.py && bash tests/ci_check.sh`
2. Opdater `README.md` og relevante docs i samme ændring — og denne roadmap, hvis noget flytter sig.
3. Ny funktion? Tilføj en test i `tests/test_v8_features.py` (in-process) eller `tests/ci_check.sh` (boot/HTTP)
