# Command Center v7.11 PRO — Bruger- og systemmanual

Selv-hostet SEO- og drifts-center til steamgears.eu (FastAPI + SQLite). Alt kører på din egen server — dine data, ingen abonnement.

![Cockpit](img/cc-cockpit.png)

> Screenshots i `docs/img/` er taget med `scripts/screenshots.py` mod den kørende version (v7.13.x-UI'et). Kør scriptet igen, når UI'et ændrer sig (se "Opdater screenshots" nedenfor).

---

## Login og brugere

Første besøg opretter din bruger (`/setup`): **e-mail** (den er dit login-id og gemmes med små bogstaver) og adgangskode (min. 8 tegn). Adgangskoder gemmes som PBKDF2-SHA256-hash med salt pr. bruger — der er ingen token i `.env`.

Derefter logger du ind med e-mail og adgangskode. Konti fra før v7.15 (oprettet med brugernavn) kan stadig logge ind med deres brugernavn; de får adressen `<brugernavn>@local`, indtil de bliver inviteret igen med en rigtig e-mail. Sessionen er en HttpOnly-cookie, der varer 30 dage, og kan tilbagekaldes ved at logge ud, slette brugeren eller skifte adgangskode.

Under fanen **Brugere**:

- **Inviter bruger** — skriv en e-mail, og appen sender en invitation med en midlertidig adgangskode (12 tegn). Brugeren skal skifte den ved første login, og dashboardet viser en gul bjælke indtil da. Invitationen kræver `SMTP_HOST` + `SMTP_FROM` i `.env`: kan mailen ikke sendes, bliver brugeren **ikke** oprettet, og fejlen står under fanen Alarmer
- **Slet bruger** gør det samme som før, og den sidste bruger kan ikke slettes, så du ikke låser dig ude
- Sletter du dig selv, bliver du logget ud

Invitationen kan også sendes fra serveren uden browser — samme funktion, samme krav til SMTP:

```bash
python3 scripts/invite.py cpaleadsis@gmail.com                      # adressen kommer fra CC_PUBLIC_URL
python3 scripts/invite.py navn@domaene.dk https://cc.example.dk     # eller angiv den selv
python3 scripts/invite.py cpaleadsis@gmail.com --print              # ingen SMTP: udskriv mailen
```

Scriptet skriver, hvad der blev sendt, og stopper med en fejl (intet oprettes), hvis mailen ikke kan sendes.
Med `--print` kræves ingen SMTP: brugeren oprettes med en midlertidig kode, og den færdige mail
(emne + tekst med koden) skrives til skærmen, så den kan sendes fra en anden mailkonto.
- **Skift min adgangskode** — kræver den nuværende; dine andre sessioner logges ud

Efter 5 fejlede logins fra samme IP er login låst i 10 minutter.

![Login](img/cc-login.png)


---

## Guidet fanerækkefølge

Fanerne er nummereret i den rækkefølge, et normalt arbejdsflow bruger dem.

### 1. Cockpit — dit daglige overblik

- **Opdatering fra GitHub**: installeret commit vs. seneste commit på `main`, "Tjek for nye commits" og "Opdater" (se nedenfor)
- Domæneovervågning: uptime, svartid, SSL-udløb (historik + graf via 📈)
- **"Sådan bruger du Command Center"**: 4 klikbare trin gennem workflowet
- Alarmer og noter

### Fremdrift på opgaver

Alle tunge handlinger viser et lille kort nederst til højre med timer, procent og forventet resttid ("~20 s igen"). Crawl viser de rigtige tal (sider/total + ETA) fra `/api/crawl/status`, mens de øvrige bruger estimater fra `TASK_ESTIMATES` i `app/main.py`. Tunge formularer viser en kvittering ("… færdig på 14 s"), når siden er genindlæst.

### 2. SEO & Audit

- **Deep audit** af en enkelt side (RankMath-stil): titel, meta, H1-struktur, alt-tekster, intern link-tæthed, Core Web Vitals (hvis `PSI_API_KEY` er sat). Score 0-100 + "AI-rewrite titel/meta"
- **Site-crawl**: flerside-scan med score pr. side, robots.txt/sitemap-tjek, sammenligning med **forrige crawl** (crawl-diff), sitemap-download og redirect-audit
- **Duplikater & redirects**: duplikat-titler/H1, næsten-identisk indhold og redirect-kæder — altid for den seneste crawl

Crawleren gemmer de **to seneste** crawls, så diffen har noget at sammenligne med; ældre ryddes automatisk.

![SEO](img/cc-seo.png)

### 3. Keywords

- Tilføj keywords → dagligt Google-positionstjek kl. 06:00 (SerpAPI)
- **Keyword-ideer**: Google/DDG-autocomplete, og autopiloten sår nye når puljen er tom
- **Keyword-sværhedsgrad**: heuristik over top 10 (autoritetsdata, unikke domæner, annoncer)
- **Visibility Index**: samlet synlighed over tid

### 4. Indhold (Artikler)

**SEO-strategi-vælger** (øverst): *AdSense-indkomst*, *Affiliate* eller *Backlink-vækst*. Valget styrer AI-artiklernes stil og længde (manuel generering OG autopilot) og hvad autopiloten gør (artikel vs. prospecting). Efter hvert valg kører CC et **pre-flight-tjek** af nøgler, WordPress-creds, moduler, cron og DB — vist som grøn/rød-checkliste med kritisk alarm ved mangler.

- **Generér artikel**: emne/keyword → AI-artikel (Gemini via aimlapi). Prompten henter top 5 Google-resultater (SerpAPI) og kræver fakta-baseret indhold, der dækker deres content gap
- **Kladde-liste**: hver artikel har *Score vs SERP*, *Meta/social*, *Push til WP (kladde)* og slet
- **Autopilot**: én knap kører hele cyklussen (idé → artikel → WP-kladde). Kører også automatisk kl. 05:15 (modulet *Growth*)
- **Kvalitetsgate**: artikler under `QUALITY_MIN_WORDS` (eller 80 % af SERP-gennemsnittet), uden fokus-keyword eller med under 2 H2 sendes **ikke** til WordPress som autopilot — status bliver "Stoppet af kvalitetsgate" + alarm. Manuel push er tilladt men giver en info-alarm

Artikel-forhåndsvisningen i dashboardet vises med saniteret HTML: kun formatering (h2/h3/p/lister/tabeller/links), ingen scripts, handlers eller `javascript:`-links.

![Indhold](img/cc-articles.png)

- **Backlink-prospector** (nederst): keyword → top 10 Google-resultater klassificeret (blog/liste/artikel/shop) + kontakt-e-mails + AI-outreach-draft

### 5. Links

- Tjek eksterne links på en side: status (ok/brudt/timeout) med historik. Brudte links = hurtige fixes
- **AI interne link-forslag** (AI Tools): kræver et crawl og `AIMLAPI_KEY`

![Links](img/cc-links.png)

### 6. Spy

- **SERP Discovery**: find konkurrenter for et keyword
- **Konkurrent-crawl**: titel/H1/meta fra konkurrent-sider — se hvad de ranker med, som du ikke dækker

![Spy](img/cc-spy.png)

### 7. Social

- **Steamgears Autopilot**: kø, kladder der venter på godkendelse, og udgivet/klik/ordrer/omsætning pr. kanal (30 dage). "→ Autopilot" sender et opslag som kladde til WordPress-pluginnet
- **Kun én kladde pr. opslag**: rækken låses før kaldet til WordPress. Et dobbeltklik eller et genforsøg sender derfor intet ekstra, og status skifter til "sender til autopilot" mens kaldet kører. Afviser WordPress kaldet, får opslaget sin gamle status tilbage og kan sendes igen. Svarer WordPress slet ikke (timeout), bliver status "sendt? (svar udeblev)" med en alarm — tjek AI Drafts i WordPress, før du sender igen
- **Planlagt tid**: vælg et tidspunkt i feltet under opslaget. Det viser zonen (`CC_TZ`, standard Europe/Copenhagen), og tiden gemmes både som lokal tid og UTC. "→ Autopilot" sender begge med, så tjenesten og Android-klienten ikke skal gætte. En tid der ikke findes (fx 02:30 den nat sommertiden starter) **afvises** med en alarm i stedet for at blive gættet
- Opslagskø med CSV-export (kolonner for både lokal tid og UTC + zone)

![Social](img/cc-social.png)

### 8. Monitors

- Tekst-, JSON- og **pris**-overvågning. Pris-monitors læser `product:price:amount` eller JSON-LD og alarmerer når prisen ændrer sig (sammenligningen bruger den gemte talværdi, ikke visningsteksten)

![Monitors](img/cc-monitors.png)

### 9. Alarmer

- Listen over åbne alarmer med type, besked og tid; "Løst" lukker en alarm (`POST /alarms/resolve`)
- **Kanaler**: hvilke af Telegram/e-mail/ntfy/webhook der er sat op, en testalarm pr. kanal og fejlede leveringer med årsag og antal forsøg (se "Alarmer og kanaler")
- Alarmer leveres fra køen `alert_outbox`, så en langsom modtager aldrig blokerer UI'et

### 10. Brugere

- Inviter og slet brugere, skift adgangskode, og se seneste login samt de seneste forsøg med e-mail og IP (se "Login og brugere")
- **MCP-adgang**: opret en nøgle pr. klient (navn + scopes), se hvor mange kald nøglen har lavet, hvornår den sidst blev brugt, og tilbagekald den med ✕. Nøglen vises kun én gang efter oprettelse — gem den med det samme. Under listen står de seneste MCP-kald (audit) med værktøj, varighed og fejl

### 11. Noter

- Hurtige workflow-noter: skriv en note, se de nyeste og slet enkelte (`/notes/add`, `/notes/delete`). Gemmes i tabellen `notes`

### 12. Moduler

- Slå de 11 funktionsområder fra/til med det samme (se "Moduler" nedenfor)

---

## AI Tools

Samlede AI-værktøjer: titel/meta-rewrites, outreach-drafts, artikel-meta, interne link-forslag og AI-synlighed. Bruger `AIMLAPI_KEY` + `AI_MODEL` (default `google/gemini-3-8-flash`, max_tokens 3000 pga. reasoning-tokens). Månedens forbrug tælles og stoppes ved `AI_MONTHLY_LIMIT`.

**AI-synlighed** (fanen *AI*, `/ai/visibility`): stil det spørgsmål en kunde ville stille en AI-assistent (fx "hvor køber jeg steampunk-goggles?"). CC beder modellen om at nævne konkrete butikker og registrerer, om `TRACK_DOMAIN` optræder i svaret — med et uddrag af svaret som dokumentation. Hvert tjek gemmes i `ai_visibility`, så du kan følge, om sitet bliver nævnt i AI-svar over tid. Kræver `AIMLAPI_KEY`.

## Pro

Redirect-audit, crawl-diff, sitemap-generator, keyword-sværhedsgrad, content gap, email-finder og pris-overvågning.

![Pro](img/cc-pro.png)

## Moduler

Slå funktionsområder fra/til: `domains, keywords, ai, monitors, social, links, spy, wp_push, telegram, growth, autopilot`.

- **Kerne**: domains + keywords + ai
- **Udvidet**: + monitors, social, links, spy
- **Fuld**: alt inkl. wp_push, telegram, growth og autopilot (WordPress-broen)

Deaktiverede moduler skjuler UI-knapper og stopper cron-jobs (fx kører growth-autopiloten kun når `growth` er til). Ændringer slår igennem med det samme.

![Moduler](img/cc-moduler.png)

---

## Opdater screenshots

Billederne i `docs/img/` laves af `scripts/screenshots.py`, så de altid viser den kørende version:

```bash
pip install playwright && python3 -m playwright install chromium   # kun foerste gang
python3 scripts/screenshots.py --base http://127.0.0.1:8000 --user din@mail.dk --password 'din-adgangskode'
```

Scriptet logger ind, tager `cc-login.png` og skifter derefter gennem alle 14 faner og gemmer
`cc-cockpit.png` … `cc-notes.png`. Vil du kun opdatere enkelte faner, så brug `--only alarms,notes`,
og vil du kun have det synlige omraade i stedet for hele siden, så tilføj `--viewport`.
Brug `--base`, `--user` og `--password` (eller `CC_BASE`, `CC_USER`, `CC_PASSWORD`).

## Opdatering fra GitHub

Cockpit-panelet viser **installeret commit** og **seneste commit på `main`**:

- **Tjek for nye commits** (`POST /update/check`) — SHA, dato og commit-besked, eller den præcise fejl: manglende `GITHUB_TOKEN`, 401/403 (udløbet token) eller 404 (forkert `GITHUB_REPO`). Tjekket kører også automatisk kl. 05:00
- **Opdater** (`POST /update/apply`) — tager en `pre-update`-backup af databasen, henter commit-tarballen fra GitHub og skriver **kun** projektets filer (`app/`, `scripts/`, `deploy/`, `requirements.txt`, `run.sh`, `run.bat`, `install.sh`, `Dockerfile`, `docker-compose.yml`, `.env.example`). `.env`, databasen, `app/backups/` og `..`-stier røres ikke
- **Requirements og genstart klarer den selv**: er `requirements.txt` ændret, køres `pip install -r` i venv'en (5 min timeout, resultatet vises i panelet), og appen genstarter ~1,5 s efter svaret — via systemd-unit hvis den findes, ellers `scripts/restart.sh` (pidfile `app/data/cc.pid` + `run.sh`). Genindlæs siden om et øjeblik
- **Fravalg**: fjern fluebenet “genstart” i panelet, sæt `UPDATE_AUTO_RESTART=0`, eller brug `UPDATE_RESTART_CMD` til din egen supervisor-kommando
- **Fra terminalen**: `bash scripts/update.sh` (tjek + filer + requirements + genstart, venter til `/health` svarer), `--check` kun tjek, `--no-restart` uden genstart. `bash scripts/restart.sh` genstarter uden at opdatere
- Status som JSON: `GET /api/update` (inkl. `restart_mode`/`auto_restart`), `POST /api/update/check`, `POST /api/update/apply` (bruges af scriptet). `/self-update` er alias for `/update/apply`

## nginx / Ultra.cc

Appen skal blive på `127.0.0.1`; nginx står for TLS:

1. `.env`: `CC_HOST=127.0.0.1`, `CC_PUBLIC_URL=https://<din-adresse>`, `CC_FORWARDED_ALLOW_IPS=127.0.0.1`
2. Start via `./run.sh` eller `deploy/command-center.user.service` (systemd --user, indlæser `.env` som `EnvironmentFile`)
3. `deploy/nginx-command-center.conf` ind i den `server { }` du bruger, derefter genindlæs nginx
4. Åbn `CC_PUBLIC_URL` — første besøg opretter din bruger

Proxy-blokken skal sende `X-Forwarded-Proto` (ellers bliver cookien ikke `Secure`, og der vises en HTTPS-advarsel), `X-Forwarded-For` (så login-låsen rammer klienten) og have `proxy_read_timeout 300s` (crawl/AI-kald tager minutter). Understi (`/apps/cc/`) virker ikke — brug subdomæne eller egen port.



## MCP-adgang (v7.17)

Agenter og editorer (Claude, Codebuff m.fl.) kan både læse og handle i Command Center over **MCP** på
`/mcp` (Streamable HTTP med JSON-svar).

1. Fanen **Brugere → MCP-adgang**: skriv et navn (fx "Claude Desktop"), vælg `read` (kun læsning)
   eller `read,write` (læsning + handlinger), og tryk **Opret nøgle**. Nøglen (`cc_…`) vises én gang —
   kopiér den med det samme.
2. Peg klienten på `https://<din-adresse>/mcp` og send nøglen som `Authorization: Bearer cc_…`.
3. Vil du hellere gøre det fra terminalen:

```bash
python3 scripts/api_key.py create "Claude Desktop" read   # nøglen skrives ud én gang
python3 scripts/api_key.py list                           # navn, halen af nøglen, scopes, sidst brugt
python3 scripts/api_key.py revoke 2                        # virker med det samme
python3 scripts/api_key.py audit 20                       # de seneste MCP-kald pr. nøgle
```

Læse-værktøjer: `health` (version, DB, brugere, åbne alarmer, seneste crawl), `crawl_summary`,
`keywords`, `monitors`, `alarms_open`, `notes` og `history` (kræver `domain_id`).

Skrive-værktøjer (kun med `write`-scope):

| Værktøj | Gør | Argumenter |
| --- | --- | --- |
| `start_crawl` | starter et site-crawl i baggrunden | `url`, `level` (quick/standard/deep), `max_pages` (5–100) |
| `add_monitor` | opretter en monitor | `name`, `url`, `type` (contains/json/price), `expected` |
| `resolve_alarm` | markerer en alarm som løst | `id` (fra `alarms_open`) |
| `add_note` | skriver en note i dashboardet | `content` (2–2000 tegn) |

`start_crawl` afvises, hvis der allerede kører et crawl, og svarer med et overslag og
`/api/crawl/status`, så agenten kan følge fremdriften. `add_monitor` opretter ikke samme url+type to
gange (den svarer `created: false` med den eksisterende id).

- Nøglen gemmes kun som sha256; databasen kan ikke genskabe den. Selve nøglen har ingen udløbsdato —
  tilbagekald den, når klienten ikke skal have adgang mere.
- `scopes` er `read` eller `read,write`; skrivende værktøjer kommer i fase 2, så `write` giver i dag
  ingen ekstra rettigheder.
- Endpointet validerer `Host` mod `CC_PUBLIC_URL` (ellers `421`) og `Origin` (fremmed origin giver `403`),
  så en fremmed webside ikke kan bruge nøglen fra browseren. Uden nøgle svarer det `401` med
  `WWW-Authenticate: Bearer`.
- Brug af en nøgle opdaterer "sidst brugt" i tabellen, så en glemt nøgle er nem at få øje på.
- **Audit pr. nøgle**: hvert værktøjskald gemmes i `api_audit` (nøgle, værktøj, ok/fejl, årsag,
  varighed, tid) og vises under nøglerne. Også afviste kald (fx manglende `write`-scope) gemmes, så et
  misbrugt eller glemt nøgle kan ses. Rækker ældre end 90 dage ryddes af den daglige oprydning.
- Plan og baggrund: [`Command_Center_MCP.md`](Command_Center_MCP.md).

## API (til automatisering)

Alle routes kræver en indlogget bruger (cookie) - samme session som UI'et. Vigtigste:

- `POST /articles/generate` (form: keyword) · `POST /articles/push` · `POST /articles/autopilot`
- `POST /keywords/add` · `GET /api/visibility` · `GET /api/health-history`
- `POST /backlinks/prospect` · `POST /seo/audit` · `POST /seo/crawl`
- `GET /health` · `POST /settings/module` · `GET /api/update` · `POST /update/check` · `POST /update/apply`
- `POST /mcp` (MCP, kræver `Authorization: Bearer cc_…` i stedet for cookie) · `POST /api-keys/create`, `/api-keys/revoke`, `/api-keys/dismiss` (cookie)
- `POST /self-update` (alias for `/update/apply`)

## Environment-variabler (.env)

`CC_HOST`, `CC_PORT`, `CC_PUBLIC_URL`, `CC_FORWARDED_ALLOW_IPS`, `GITHUB_TOKEN`, `GITHUB_REPO`, `UPDATE_AUTO_RESTART`, `UPDATE_RESTART_CMD`, `AIMLAPI_KEY`, `AI_MODEL`, `WP_URL/USER/APP_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `SMTP_TO`, `SMTP_TLS`, `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN`, `ALERT_WEBHOOK_URL`, `ALERT_WEBHOOK_SECRET`, `ALERT_MIN_SEVERITY`, `ALERT_QUIET_HOURS`, `ALERT_DEDUPE_MINUTES`, `SERPAPI_KEY`, `TRACK_DOMAIN`, `PSI_API_KEY`, `SSL_WARN_DAYS`, `LINKCHECK_LIMIT`, `SERPAPI_MONTHLY_LIMIT`, `AI_MONTHLY_LIMIT`, `QUALITY_MIN_WORDS`.

Rigtige miljøvariabler vinder over `.env`. `.env` læses før appens konfiguration, og inline-kommentarer (`KEY=  # note`) fjernes.

## Drift

- **Cron**: domæne-tjek hver 6. time · keywords 06:00 · autopilot 05:15 · oprydning 04:30 · DB-backup 04:40 · GitHub-tjek 05:00 · Autopilot-bro hver 30. min · alarmkøen (`alert_outbox`) leveres hvert minut
- **Backup**: `app/backups/cc-daglig-*.db` (14 gemmes) og `cc-pre-update-*.db` før hver opdatering
- **Health**: `/health` returnerer 503 ved kritisk DB/disk-tilstand og viser månedens API-forbrug
- **Tests**: `python3 tests/test_v8_features.py` og `bash tests/ci_check.sh` (boot, alle sider, auth, WordPress-bro og link-audit)
- **Rollback**: stop appen, gendan `app/data/center.db` fra `app/backups/`, og kør `install.sh`/GitHub-opdatering igen

## Fejlfinding

| Symptom | Tjek |
| --- | --- |
| Bliver logget ud hele tiden | Bag nginx: mangler `X-Forwarded-Proto`? Så sættes cookien ikke `Secure` korrekt, og HTTPS-advarslen vises |
| "GITHUB_TOKEN mangler" i opdaterings-panelet | Sæt token i `.env` (privat repo) og genstart appen |
| 504 fra nginx ved crawl/AI-kald | `proxy_read_timeout 300s` i nginx-blokken |
| Login låst | 5 fejl = 10 min pr. IP; vent eller genstart appen |
| Kan ikke invitere en bruger | Gyldig e-mail + `SMTP_HOST`/`SMTP_FROM` i `.env`; fejlen står under Alarmer. Adgangskode ved direkte oprettelse: min. 8 tegn |
| Ingen adgang til `/api/*` | Log ind igen - API'et kræver en aktiv session (cookie), ikke en token |
| Appen starter ikke efter opdatering | `pip install -r requirements.txt` (gør `./run.sh`), og se `journalctl --user -u command-center` |

## Installation

```bash
# Hent install.sh fra det private repo (raw-download med din GitHub-token) og kør den
bash install.sh
```

Scriptet selv-installerer (venv, deps, `.env`-skabelon, nginx-config, systemd-unit) og er idempotent.


## Alarmer og kanaler (v7.12)

Alarmer (døde domæner, ændrede priser, fejlede keyword-tjek, budgetloft, strategi-mangler) sendes nu
til de kanaler du sætter i `.env`:

| Kanal | Variabler |
|---|---|
| Telegram | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |
| E-mail | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `SMTP_TO`, `SMTP_TLS` |
| ntfy | `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN` |
| Webhook | `ALERT_WEBHOOK_URL`, `ALERT_WEBHOOK_SECRET` |

`ALERT_MIN_SEVERITY` (info/advarsel/kritisk) filtrerer støj, `ALERT_QUIET_HOURS=23-7` holder
ikke-kritiske alarmer væk om natten, og `ALERT_DEDUPE_MINUTES` (standard 180) sikrer at den samme
alarm ikke spammer. Genstart efter ændringer. Under fanen **Alarmer** ser du hvilke kanaler der er
aktive, kan sende en testalarm pr. kanal, og se hvorfor en levering eventuelt fejlede — appen prøver
automatisk igen med stigende interval i op til fem forsøg.

E-mail kræver en app-adgangskode (Google/Fastmail), ikke din normale adgangskode.
Webhooken kan verificeres med `webhook-signature`-headeren, hvis modtageren kender hemmeligheden.


## Opstart, login-IP og kørselsrapport (v7.13)

Ved opstart printer appen version og de nyeste ændringer. Samme tekst havner i `app/data/startup.log`,
og `run.sh`, `run.bat`, `scripts/restart.sh`, `scripts/update.sh` og `install.sh` viser versionen, så
du altid kan se hvad der kører.

Login registrerer IP'en bag hvert forsøg: under fanen **Brugere** ser du seneste login pr. bruger
(IP + tid) og de sidste otte forsøg, inkl. fejlede. Bag nginx kræver det, at `CC_FORWARDED_ALLOW_IPS`
matcher proxyens adresse (standard `127.0.0.1`), ellers vises proxyens IP.

Login-siden viser en kort kørselsrapport, før du logger ind: version og commit, seneste opstart, åbne
alarmer, antal domæner/keywords/monitors, seneste domænetjek og crawl, database-størrelse og din IP.
Rapporten indeholder bevidst ikke alarmtekster eller brugernavne.
