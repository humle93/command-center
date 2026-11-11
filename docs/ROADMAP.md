# Command Center — Roadmap

**Baseline:** v7.10.0 · **Opdateret:** 3. november 2026 · **Ejer:** Steamgears

Dette er den samlede plan frem til v9. Den bygger på den kode, der ligger i repoet nu
(`app/main.py` 2.853 linjer, 25 data-tabeller, 56 ruter, 12 moduler, 7 cron-jobs), ikke på
løse noter i Drive. Alt nedenfor er rangeret efter "hvad låser hvad" — ikke efter hvad
der er sjovest at bygge.

---

## 1. Hvor vi står

| Område | Status | Bevis i koden |
| --- | --- | --- |
| Cockpit (uptime, svartid, SSL, Juno-drift) | ✅ Færdig | `job_check_domains` (hver 6. time), `check_history` |
| SEO Scanner + site-crawl + crawl-diff + redirect-audit | ✅ Færdig | `/seo/audit`, `/seo/crawl`, `/api/crawl/diff`, `crawl_runs` |
| Artikler (AI, WP-kladde, autopilot, kvalitetsgate) | ✅ Færdig | `/articles/*`, `quality_check()`, `job_growth_autopilot` (05:15) |
| Keywords (positioner, ideer, sværhedsgrad, visibility) | ✅ Færdig | `job_check_keywords` (06:00), `keyword_difficulty`, `visibility` |
| Spy / Content Gap / backlink-prospector / outreach | ✅ Færdig | `/serp/gap`, `/backlinks/prospect`, `/outreach/scan` |
| Links, Social, Monitors, AI Tools, Noter, Alarmer | ✅ Færdig | `/links/check`, `socialqueue`, `monitors`, `add_alarm()` |
| Autopilot-bro til WordPress-plugin (7.5+) | ✅ Færdig | `/autopilot/sync`, `job_sgap_sync` (hver 30. min) |
| Stabilitet (backup, selvtest, rate-limit, /health) | ✅ Færdig | `job_backup_db` (04:40), `startup_selftest_sync`, `/health` |
| **v8-planen** (kvalitetsgate, API-budget, `/health`) | ✅ Leveret i v7.10 | `quality_check()`, `API_BUDGETS`, `/health` |

v8-planen er dermed **lukket**. Det, der står tilbage, er den gæld og de huller, som
v7.x har efterladt — ikke nye features. Det er hele pointen med v8-serien nedenfor.

---

## 2. v8.0 — Fundament (est. 2–3 dage)

Målet er at gøre det billigt at ændre systemet. Alt her er forudsætningen for, at
v8.1–v8.3 ikke koster mere, end de giver.

### M1 · Installer genereres, ikke vedligeholdes i hånden ✅
`install.sh` er ~4.050 linjer og indeholder kopier af 12 filer (`app/main.py`,
`dashboard.html`, `login.html`, `requirements.txt`, `README.md`, `run.sh`, `run.bat`,
Docker-filerne, servicen, `smoke_test.sh` og `.env.example`). Før fangede CI kun, at
fem af kopierne drev fra hinanden — resten var utjekket.
- **Leverance:** `scripts/build_installer.py` udvider `scripts/installer.template.sh`
  til `install.sh`; templaten er 74 linjer shell-flow med en markør pr. indlejret fil.
  CI kører `--check` i stedet for den gamle diff-løkke.
- **Færdig når:** `python3 scripts/build_installer.py --check` er grønt i CI. ✅

### M2 · Schema-version i stedet for gætteri ✅
`init_db()` opretter tabeller med `CREATE TABLE IF NOT EXISTS` og tilføjer manglende
kolonner via en `ALTER TABLE`-løkke. Det virker, men der var ingen sporbarhed: man kunne
ikke se, hvilken version en given DB er på, og en fejlet migrering var usynlig — hvert
trin havde sit eget `_safe()`-kald og kørte bare videre.
- **Leverance:** `SCHEMA_VERSION` i `app/main.py`, tabellen `schema_meta` med stemplet
  (ikke `settings`, så drift-nøgler og schema-version ikke blandes sammen), ét samlet
  `init_schema()`-løb der stempler til sidst, og `schema_version` /
  `schema_version_expected` / `schema_ok` i `GET /health`. Mangler stemplet eller
  afviger det, gives `advarsel` (ikke 503), der logges en skarp linje, og der oprettes
  en `kritisk` alarm, så det også ses i UI'et.
- **Færdig når:** en DB fra v7.9 opgraderes uden tab af data, og `/health` melder
  `schema: ok`. ✅ (testet: `DROP TABLE schema_meta` → `init_schema()` stempler 1;
  simuleret fejl i `migrate_db()` → intet stempel + alarm)

### M3 · Config-drift fanges automatisk ✅
`PSI_API_KEY` læses i `app/main.py` (linje 55) og dokumenteres i README, men fandtes ikke
i `.env.example`, så en frisk installation fik ingen nøgle at udfylde. Samme fejlklasse
ville opstå igen.
- **Leverance:** `tests/test_config_drift.py` læser koden med `ast` (ikke regex, så
  `dict.get("x")` ikke giver falske positiver) og finder alle `os.environ.get(...)`,
  `os.getenv(...)` og `os.environ[...]` i hele `app/`; en lille ignore-liste dækker
  systemvariable som `PATH`. Testen fejler hvis en nøgle mangler i `.env.example`,
  advarer (uden at fejle) om nøgler der er dokumenteret men aldrig læst, og CI kører
  den som eget trin. `.env.example` har fået `PSI_API_KEY`.
- **Færdig når:** testen er grøn, og `.env.example` har `PSI_API_KEY`. ✅

### M4 · `main.py` deles op — uden at røre ruterne ✅
2.853 linjer i én fil er den største enkeltrisiko i projektet. Ruterne bliver, hvor de
er; rene funktioner flyttes ud, så de kan testes isoleret.
- **Leverance:** `app/core.py` (konfiguration, `get_db`, schema, fælles hjælpere) og
  `app/services/{audit,content,wp,budget,alarms}.py`, alle gen-eksporteret fra `main.py`,
  så `install.sh`-flowet og alle eksisterende imports virker uændret. `install.sh`
  skriver nu også `app/services/`.
- **Færdig når:** `app/main.py` er under 2.000 linjer, og `tests/ci_check.sh` +
  `test_v8_features.py` er grønne. ✅ (`main.py` 1.705 linjer; `ci_check.sh` sweeper
  alle GET-ruter, og en frisk `install.sh`-installation importerer `app.main`)
- **Bemærkning:** budget-*tællingen* (`HTTP`-adapteren) blev liggende i `app/core.py`,
  fordi den sidder på requests-sessionen; `app/services/budget.py` har rapporteringen,
  og adapteren importerer den inde i `send()` for at undgå en cirkulær import.

---

## 3. v8.1 — Drift & pålidelighed (est. 2–3 dage)

### M1 · Backup testes, ikke bare tages
Der tages backup kl. 04:40 (14 kopier i `app/backups/`), men intet bekræfter, at
backuppen kan åbnes.
- **Leverance:** `scripts/restore_test.sh` der tager nyeste backup, kører
  `PRAGMA integrity_check`, tæller rækker pr. tabel og sammenligner med den kørende DB.
  Fejl → alarm af typen `backup`. Plus en kort restore-procedure i manualen.
- **Færdig når:** testen kører ugentligt via cron og har været grøn to gange.

### M2 · Cron-synlighed
7 jobs kører i processen (`domain_checks`, `keyword_checks`, `growth_autopilot`,
`cleanup`, `pull_bridge`, `db_backup`, `sgap_sync`). Fejler ét af dem, opdager man det
kun indirekte.
- **Leverance:** `last_run` + `last_status` pr. job i `settings`, vist i Cockpit, og en
  alarm hvis et job ikke har kørt inden for 2× sin periode. `/health` udvides med
  `jobs: {navn: {sidst, status}}`.
- **Færdig når:** et bevidst crashet job giver en alarm inden for én periode.

### M3 · API-budgettet dækker alle betalte kald
`API_BUDGETS` tæller SerpAPI og aimlapi. Google PageSpeed (`PSI_API_KEY`) og
GitHub-kaldene i pull-bro/self-update er ikke omfattet.
- **Leverance:** PSI føjes til budgettet med eget loft (`PSI_MONTHLY_LIMIT`), og
  budget-oversigten i `/health` viser alle services.
- **Færdig når:** `budget_service()` returnerer `psi` for `googleapis.com`-hosts, og
  testen i `tests/test_v8_features.py` dækker det.

### M4 · Logning der kan læses af maskiner
Alt logges til stdout. Efter en selv-opdatering eller et cron-crash findes der intet
spor på disken.
- **Leverance:** JSON-lines til `app/logs/cc.log` med rotation (7 dage), request-id pr.
  kald og `level`. Ingen ændring af UI.
- **Færdig når:** en fejlet WP-push kan findes i logfilen ud fra tidspunkt alene.

---

## 4. v8.2 — SEO-dybde (est. 4–5 dage)

Her begynder det at ligne nye features igen — men de tre første bygger på data, der
allerede ligger i DB'en.

### M1 · Intern link-graf
`internal_links` fyldes af crawleren, men bruges ikke til analyser.
- **Leverance:** rapport for orphan pages (ingen indgående links), klik-dybde fra
  forsiden, og "denne side mangler links fra disse 3 sider" i side-rapporten.
- **Færdig når:** rapporten kan køres på steamgears.eu og giver en liste, der ikke er tom.

### M2 · Content decay
`gsc_daily` og `gsc_queries` indeholder historik, men intet sammenligner over tid.
- **Leverance:** alarm når en URL taber >25 % klik over 28 dage, plus en "refresh"-liste
  i Indhold-fanen, der kan sende et indlæg til kvalitetsgaten igen.
- **Færdig når:** mindst én ægte side er fanget i en manuel gennemkørsel.

### M3 · GSC direkte i stedet for via Juno-bro
Broen virker (`POST /api/bridge/gsc`), men kræver Juno som mellemled.
- **Leverance:** valgfri direkte GSC-hentning (service account) med query-niveau data,
  så broen kan pensioneres for GSC's vedkommende.
- **Færdig når:** samme tal kommer ind ad begge veje i en uge uden afvigelse.

### M4 · Canonical/hreflang/sitemap-audit
`/api/sitemap.xml` genererer fra seneste crawl; canonical og hreflang tjekkes ikke.
- **Leverance:** tre nye vægtede kontroller i deep audit + visning i side-rapporten.
- **Færdig når:** kontrollerne kører på 20 sider uden falske positiver.

---

## 5. v8.3 — Autopilot & kvalitet (est. 3–4 dage)

### M1 · Kvalitetsgate v2
Gaten fra v7.10 tjekker ord, fokus-keyword, 2× H2 og interne links (advarsel).
- **Leverance:** læsbarhed (Flesch findes allerede), nær-duplikat mod egne publicerede
  sider, og interne links som hårdt krav ved autopilot (blød ved manuel push).
- **Færdig når:** en autopilot-artikel uden interne links stoppes, og alarmen forklarer hvorfor.

### M2 · WP-synk, ikke kun nye kladder
I dag pushes der kun nye kladder.
- **Leverance:** `keyword → post_id`-mapping og en "opdater eksisterende indlæg"-kø, så
  refresh af gamle artikler er samme flow som nye.
- **Færdig når:** en eksisterende artikel kan opdateres uden at miste permalink.

### M3 · Prioriteret autopilot-kø
Autopiloten tager næste idé i rækkefølge.
- **Leverance:** prioritet ud fra keyword-gap og position 5–20 ("hurtige wins" først),
  med synlig begrundelse pr. kø-element.
- **Færdig når:** køen vælger en position-11-side før en urelateret ny idé.

---

## 6. v9 — Flere sites (est. 1–2 uger, kun hvis behovet opstår)

I dag er alt bundet til ét site (`TRACK_DOMAIN`) og én bruger (`APP_TOKEN`).
- **Site-isolation:** `site_id` på alle 25 tabeller, site-vælger i UI, pr-site nøgler.
- **Brugere/roller:** mere end én login, adskilt læse/skrive-adgang.
- **Storage:** Postgres som valgfrit alternativ til SQLite ved flere samtidige sites.
- **Krav før start:** mindst to reelle sites i drift. Ellers er arbejdet spildt.

---

## 7. Rækkefølge og hvad vi ikke gør

**Rækkefølge:** v8.0 → v8.1 → v8.2 → v8.3. v8.0 og v8.1 kan ikke byttes om: uden
genereret installer og synlig cron er hver senere ændring dyrere at rulle ud.

**Uden for roadmap (bevidst):**
- Flere AI-modeller/leverandører — aimlapi dækker behovet, og budgettet er bygget til én.
- Graf-dashboarder og nye UI-temaer — Cockpit løser opgaven.
- Mobil-app, Slack-integration, e-mail-udsendelser — Telegram + Juno-bro dækker alarmerne.
- Automatisk linkbuilding (kun prospecting, aldrig automatisk outreach) — det er et
  kvalitets- og omdømmespørgsmål, ikke et teknikspørgsmål.

**Definition of done for hver milepæl:** kode + test i `tests/` + opdateret afsnit i
`docs/Command_Center_Dokumentation.md` + grøn CI. Intet punkt er færdigt, fordi det
"virker lokalt".

---

## 8. Kendt teknisk gæld (ikke planlagt, men kendt)

- `docs/Command_Center_Dokumentation.md` hedder stadig v6.0 i titlen, med v7.x-afsnit
  hængt på i bunden; manualen er på v7.7.
- ~~`README.md` findes også som kopi inde i `install.sh`~~ — løst i M1 (genereres nu).
- Selv-opdatering er Linux-only (`self_update_sync()` afviser Windows); `run.bat` er
  parkeret.
- `add_alarm()` indsætter ubetinget — et job, der fejler hver 30. minut, giver 48 alarmer i døgnet.
