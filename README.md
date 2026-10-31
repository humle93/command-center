# Command Center v7.10 PRO

Selv-hostet SEO- og drifts-center (FastAPI + SQLite) i stil med RankMath Pro / Yoast Premium — bygget til Steamgears.

## Funktioner
- 🎛️ **Cockpit** — domæneovervågning (uptime, svartid, SSL), daglig drift-kort (Woo/checkout via Juno-bro)
- 🔍 **SEO Scanner** — deep audit af enkelt side (20+ vægtede kontroller inkl. focus keyword, lesbarhed, mixed content, schema, OG/Twitter) + **site-crawl** med score per side og robots.txt/sitemap-tjek
- ✍️ **Artikler** — AI-generering (Gemini via aimlapi) eller skabelon, **push direkte til WordPress som udkast**, **fakta-prompt med SerpAPI-konkurrentanalyse** (top 5 resultater ind i prompten — artiklen skal slå dem), autopilot (idé → artikel → WP-kladde, ny idé via Google-autocomplete når puljen er tom)
- 🎯 **SEO-strategi-vælger** — dropdown (AdSense-indkomst / Affiliate / Backlink-vækst): styler AI-artikler (stil + længde) og autopiloten (artikel vs. prospecting), med automatisk pre-flight-tjek af nøgler, moduler, cron og DB efter hvert valg (grøn/rød-checkliste)
- 🛡️ **v7.9 Stabilitet** — daglig DB-backup (04:40, seneste 14 gemmes) + automatisk backup foer hver self-update; opstarts-selvtest (DB-skrivetest, noegler, rute-taelling → kritisk alarm ved fejl); login rate-limit (5 fejl = 10 min laas pr. IP); HTTPS-advarsel i UI; scripts/smoke_test.sh; run.bat (Windows-startscript, klar til fremtid - self-update er Linux-only)
- 🌱 **Growth Pack** — autopilot-nøgleord-side (05:15 dagligt), **backlink-prospector** (SerpAPI top 10 → sitetype + kontakt-e-mail + AI-outreach-draft), visibility-index
- 🧩 **Moduler** — slå funktioner fra/til i 3 niveauer (kerne/udvidet/fuld); alt visuelles følger modulet
- 🎯 **Keywords** — Google-positioner via SerpAPI, tjekket automatisk daglig kl. 06:00
- 🕷️ **SERP & Spy** — konkurrent-opdagelse + crawl af titel/H1/beskrivelse
- 🔗 **Links** — ekstern linktjek med brodte-links-rapport
- 📱 **Social** — opslagskø med CSV-export
- 🚨 **Alarmer** — SSL-udlob, nedetid, brodte links, fejlede scans; valgfrit Telegram-push
- 📈 **Historik** — svartid-grafer pr. domæne (Chart.js)
- 🌉 **Juno-broer** — `POST /api/bridge/gsc` og `/api/bridge/drift` (header `X-CC-Token`) sa Juno kan pushe GSC-tal og daglig drift

## v7.10 – fra v8-planen (Drive)
- **Kvalitetsgate**: autopilot-artikler sendes kun til WordPress, hvis de har nok ord (min. `QUALITY_MIN_WORDS`, eller 80 % af SERP-gennemsnittet fra Content Gap), indeholder fokus-keywordet og har mindst 2 H2. Ellers status "Stoppet af kvalitetsgate" + alarm. Manuel push er tilladt, men giver en info-alarm. Faerre end 2 interne links giver kun en advarsel.
- **API-budget**: hvert kald til SerpAPI og aimlapi taelles pr. maaned; ved `SERPAPI_MONTHLY_LIMIT` / `AI_MONTHLY_LIMIT` stoppes kaldene til den 1. Alarm (og Telegram) ved 80 % og 100 %.
- **/health**: tester at databasen kan skrive og hvor fuld disken er (advarsel ≥ 80 %, kritisk ≥ 90 % → HTTP 503) og viser maanedens API-forbrug.

## Steamgears Autopilot-bro (WordPress-plugin 7.5+)
Command Center og WordPress-pluginnet **Steamgears Autopilot** snakker sammen via pluginnets REST-API
(`/wp-json/sgap/v1`) med de samme `WP_URL` / `WP_USER` / `WP_APP_PASSWORD` som WordPress-push
(`WP_USER` skal vaere administrator).
- **Status hver 30. min** (fanen Social → "Steamgears Autopilot"): koe (i koe / sendes / udgivet / fejlet),
  kladder der venter paa godkendelse, og udgivet/klik/ordrer/omsaetning pr. kanal de sidste 30 dage.
- **Alarmer + Telegram** naar noget aendrer sig: nye fejlede opslag, nye kladder til godkendelse, eller pluginnet svarer ikke.
- **"→ Autopilot"** paa hvert opslag i CC's sociale koe sender det som kladde til pluginnet (godkendes i WordPress
  under Steamgears → AI Drafts, hvorefter pluginnet udgiver via Publer).
- Slaa til/fra under Moduler ("Autopilot-bro"). Retningen er altid CC → site, saa CC kan blive paa 127.0.0.1.

## Installering
```bash
curl -H "Authorization: Bearer <TOKEN>" -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/humle93/command-center/contents/install.sh -o install.sh && bash install.sh
```

Eller med Docker: `cp .env.example .env && docker compose up -d --build`

## Opsaetning
1. `cp .env.example .env` og udfyld noegler
2. `./run.sh` → http://127.0.0.1:8000
3. (VPS) saet `APP_TOKEN` i `.env` og kør bag reverse proxy, eller brug `deploy/command-center.service` + SSH-tunnel

## v7.5 — performance & drift
- **Pull-bro**: Juno committer JSON-filer til repoets bridge/pending/, CC henter selv hver time (GITHUB_TOKEN i .env) — ingen tunnel eller FTP noedvendig
- **Selv-opdatering**: Opdater-knap i toppen henter nyeste install.sh og koerer den
- **SQLite**: WAL-mode, busy_timeout, 8 indekser, daglig oprydning kl. 04:30
- **HTTP**: connection-pooling og gzip-komprimering
- **UI**: sticky nav, preconnect, spinner, hover/focus-puds, mobile-forbedringer

## v7.4 PRO tilfoejelser
- **Crawl-diff** (Screaming Frog-stil): sammenlign to crawls — nye/fjernede sider, aendret indhold (hash), score-fald >10
- **Redirect-audit**: kæder (2+ hop), redirect-loops og usikre http-redirects fra crawleren
- **Sitemap-generator**: download sitemap.xml bygget fra seneste crawl (/api/sitemap.xml)
- **Keyword-svaerhedsgrad** (Ahrefs-kopi): heuristic over top 10 — autoritetsdomaener, unikke domaener, annoncer → 0-100 score
- **AI titel/meta-rewrite**: Gemini foreslar 3 titler + 3 meta descriptions direkte fra deep audit (klik for at kopiere)

## PRO-funktioner (betalt-varktoej-kloner)
- **Content Gap** (Semrush-kopi): top 10 SERP hentes via SerpAPI, gennemsnit af ord/H2 beregnes, og dine artikel-kladder scores mod markedet (Content Score)
- **Keyword-ideer** (Ubersuggest-kopi): Google + DuckDuckGo autocomplete, gratis
- **Email-finder** (Hunter.io-kopi): scan sider for kontakt-emails til linkbuilding-outreach
- **Pris-overvaagning**: monitors med typen "pris" laeser JSON-LD/product:price og alarmerer ved pris-andringer hos konkurrenter
- **Visibility Index** (SE Ranking-kopi): samlet synlighedstal ud fra dine keyword-positioner, graf over tid
- **Core Web Vitals**: valgfri Google PageSpeed API-noegle (PSI_API_KEY) giver perf/LCP/CLS i deep audit
- **Flesch-lesbarhed** (Hemingway-kopi) i hver side-audit

## Sikkerhed
- `APP_TOKEN` = login til hele UI'et og noeglen til Juno-broerne (header `X-CC-Token`)
- Default binding er 127.0.0.1 — saet aldrig `0.0.0.0` uden reverse proxy + auth
