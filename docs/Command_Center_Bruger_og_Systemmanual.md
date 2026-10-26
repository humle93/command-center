# Command Center v7.7 PRO — Bruger- og systemmanual

Selv-hostet SEO- og drifts-center til steamgears.eu (FastAPI + SQLite). Alt kører på din egen server — dine data, ingen abonnement.

![Cockpit](img/cc-cockpit.png)

---

## Login

Siden er beskyttet med én adgangstoken (`APP_TOKEN` i `.env`). Indtast token → du er logget ind (session-cookie, 30 dage).

![Login](img/cc-login.png)

**JUNO_TOKEN** (separat token i `.env`) giver Juno API-adgang til de samme endpoints uden at bruge din personlige token til automatisering.

---

## Guidet fanerækkefølge

Fanerne er nummereret i den rækkefølge, et normalt arbejdsflow bruger dem:

### 1. Cockpit — dit daglige overblik
- Domæneovervågning: uptime, svartid, SSL-udløb (daglig historik + graf).
- Drift-kort via **Juno-broen**: Woo/checkout-status m.m. hentes fra Juno og vises her.
- **"Sådan bruger du Command Center"-guiden**: 4 klikbare trin der fører dig gennem workflowet (SEO-audit → keywords → indhold → links).
- Alarmer og noter samlet i sidepanelet.

### 2. SEO & Audit
- **Deep audit** af en enkelt side (RankMath-stil): titel, meta, H1-struktur, alt-tekster, intern link-tæthed, Core Web Vitals (hvis PSI-nøgle er sat). Score 0-100 + "AI-rewrite titel/meta"-knap.
- **Site-crawl**: flerside-scan med score pr. side, sammenligning med forrige crawl, sitemap-download, redirect-audit.
- **Duplicater & redirects**: duplikat-titler/H1, næsten-identisk indhold, redirect-kæder.

![SEO](img/cc-seo.png)

### 3. Keywords
- Tilføj keywords → daglig Google-positionstjek kl. 06:00 (via SerpAPI).
- **Keyword-ideer**: forslag indsamlet automatisk (autopiloten sower nye via Google-autocomplete, når puljen er tom).
- **Visibility Index**: samlet synlighed over tid.
- Difficulty-tjek og diff-rapport.

### 4. Indhold (Artikler)
- **Generér artikel**: indtast emne/keyword → AI-artikel (Gemini via aimlapi). Prompten henter **top 5 Google-resultater via SerpAPI** og kræver, at artiklen er fakta-baseret og dækker deres content gap — ingen sludder.
- **Kladde-liste**: hver artikel har knapperne *Score vs SERP* (position + score), *Meta/social* (AI-genereret titel/meta), *Push til WP (kladde)* og slet.
- **Autopilot**: én knap kører hele cyklussen — vælg idé → AI-artikel → WP-kladde. Kører også automatisk hver dag kl. 05:15 (kræver modul *Growth* aktiveret). Nye idéer hentes automatisk fra Google-autocomplete.

![Indhold](img/cc-articles.png)

- **Backlink-prospector** (nederst på fanen): indtast keyword → top 10 Google-resultater klassificeret (blog/liste/artikel/shop) + fundne kontakt-e-mails + AI-outreach-draft. Gemmes i prospekt-tabel; slet enkeltlinjer. Kræver SERPAPI_KEY (AIMLAPI_KEY for AI-drafts).

### 5. Links
- Tjek eksterne links på et domæne: status (ok/brudt/redirect) med historik. Brudte links = hurtige fix-muligheder.

![Links](img/cc-links.png)

### 6. Spy
- **SERP Discovery**: find konkurrenter for et keyword.
- **Konkurrent-crawl**: titel/H1/meta-beskrivelse fra konkurrent-sider — se hvad de ranke med, som du ikke dækker.

![Spy](img/cc-spy.png)

### 7. Social
- Opslagskø til sociale medier med CSV-export. Planlæg opslag, eksportér til Buffer/andet værktøj.

![Social](img/cc-social.png)

### 8. Monitors
- Overvågning af specifikke URL'er/ord: cron-tjek med alarm ved ændring (pris, lagerstatus, tekst).

![Monitors](img/cc-monitors.png)

---

## AI Tools
Samlede AI-værktøjer: title/meta-rewrites, outreach-drafts, artikel-meta m.m. Bruger AIMLAPI_KEY + AI_MODEL (default `google/gemini-3-8-flash`, max_tokens 3000 pga. reasoning-tokens).

## Pro
Redirect-audit, rewrite-historik, sitemap-værktøjer m.m. (se screenshot).

![Pro](img/cc-pro.png)

## Moduler
Slå funktionsområder fra/til: `domains, keywords, ai, monitors, social, links, bridge, spy, wp_push, telegram, growth`. Tre niveauer:
- **Kerne**: domains + keywords + ai
- **Udvidet**: + monitors, social, links, spy
- **Fuld**: alt inkl. bridge, wp_push, telegram, growth

Deaktiverede moduler skjuler både UI og cron-jobs (fx kører growth-autopiloten kun når `growth` er til).

![Moduler](img/cc-moduler.png)

---

## Juno-broen (pull)
Command Center **trækker** selv data fra Juno (GitHub raw) med `JUNO_TOKEN` hvert `BRIDGE_POLL_MINUTES` (default 30). Giver Woo/checkout-drift-data i Cockpit uden at exponere din server udadtil. Ingen webhook/port-slagning nødvendig.

## API (til Juno/automatisering)
Alle endpoints kræver `Authorization: Bearer <token>`. Vigtigste:
- `POST /articles/generate` (form: keyword) · `POST /articles/push` · `POST /articles/autopilot`
- `POST /keywords/add` · `GET /api/visibility` · `GET /api/health-history`
- `POST /backlinks/prospect` · `POST /seo/audit` · `POST /seo/crawl`
- `GET /health` · `POST /settings/module` · `POST /self-update`

`/self-update` trækker nyeste install.sh fra det private repo og geninstallerer — opdatering på under et minut.

## Environment-variabler (.env)
`APP_TOKEN`, `JUNO_TOKEN`, `GITHUB_TOKEN`, `GITHUB_REPO`, `BRIDGE_POLL_MINUTES`, `AIMLAPI_KEY`, `AI_MODEL`, `WP_URL/USER/APP_PASSWORD`, `TELEGRAM_*`, `SERPAPI_KEY`, `TRACK_DOMAIN`, `PSI_API_KEY`, `SSL_WARN_DAYS`, `LINKCHECK_LIMIT`.

## Installation
```
# 1) Hent install.sh fra det private repo (raw-download med din token)
# 2) Koer: bash install.sh
```
Scriptet selv-installerer (venv, deps, systemd, .env-skabelon) og er idempotent.
