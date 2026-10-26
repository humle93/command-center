# Command Center v7.8 PRO

Selv-hostet SEO- og drifts-center (FastAPI + SQLite) i stil med RankMath Pro / Yoast Premium — bygget til Steamgears.

## Funktioner
- 🎛️ **Cockpit** — domæneovervågning (uptime, svartid, SSL), daglig drift-kort (Woo/checkout via Juno-bro)
- 🔍 **SEO Scanner** — deep audit af enkelt side (20+ vægtede kontroller inkl. focus keyword, lesbarhed, mixed content, schema, OG/Twitter) + **site-crawl** med score per side og robots.txt/sitemap-tjek
- ✍️ **Artikler** — AI-generering (Gemini via aimlapi) eller skabelon, **push direkte til WordPress som udkast**, **fakta-prompt med SerpAPI-konkurrentanalyse** (top 5 resultater ind i prompten — artiklen skal slå dem), autopilot (idé → artikel → WP-kladde, ny idé via Google-autocomplete når puljen er tom)
- 🎯 **SEO-strategi-vælger** — dropdown (AdSense-indkomst / Affiliate / Backlink-vækst): styler AI-artikler (stil + længde) og autopiloten (artikel vs. prospecting), med automatisk pre-flight-tjek af nøgler, moduler, cron og DB efter hvert valg (grøn/rød-checkliste)
- 🌱 **Growth Pack** — autopilot-nøgleord-side (05:15 dagligt), **backlink-prospector** (SerpAPI top 10 → sitetype + kontakt-e-mail + AI-outreach-draft), visibility-index\n- 🧩 **Moduler** — slå funktioner fra/til i 3 niveauer (kerne/udvidet/fuld); alt visuelles følger modulet
- 🎯 **Keywords** — Google-positioner via SerpAPI, tjekket automatisk daglig kl. 06:00
- 🕷️ **SERP & Spy** — konkurrent-opdagelse + crawl af titel/H1/beskrivelse
- 🔗 **Links** — ekstern linktjek med brodte-links-rapport
- 📱 **Social** — opslagskø med CSV-export
- 🚨 **Alarmer** — SSL-udlob, nedetid, brodte links, fejlede scans; valgfrit Telegram-push
- 📈 **Historik** — svartid-grafer pr. domæne (Chart.js)
- 🌉 **Juno-broer** — `POST /api/bridge/gsc` og `/api/bridge/drift` (header `X-CC-Token`) sa Juno kan pushe GSC-tal og daglig drift

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
