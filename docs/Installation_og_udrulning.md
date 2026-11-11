# Installation og udrulning — Steamgears Autopilot, Command Center og wp-auto-deployer

Samlet manual for de tre dele, der hænger sammen fra 11. november 2026:

| Del | Version | Repo | Hvor den kører |
| --- | --- | --- | --- |
| **Steamgears Autopilot** (WordPress-plugin) | 7.76.0 | `humle93/steamgears-site` → `plugins/steamgears-autopilot-v7.76.0.zip` | steamgears.eu (Simply) |
| **Command Center** | 7.27.0 | `humle93/command-center` | din server (`laser`, Ultra.cc eller Docker) bag nginx |
| **wp-auto-deployer** | 1.0.0 | `humle93/wp-auto-deployer` | en Linux-server med Docker (eller lokalt i dry-run) |

Følg rækkefølgen: **1 → 2 → 3**. Login-knappen i WordPress virker først, når både 1 og 2 er på plads.
wp-auto-deployer (3) er uafhængig af de to andre og kan installeres når som helst.

> **Hemmeligheder:** OpenRouter-nøglen, `WP_APP_PASSWORD`, `GITHUB_TOKEN` og operatør-nøglen til
> wp-auto-deployer hører kun hjemme i `.env` eller i pluginnets nøgleside — aldrig i en chat, en
> commit, et skærmbillede eller en e-mail.

---

## 0. Forudsætninger

- **En OpenRouter-nøgle:** openrouter.ai/keys → *Create key*. Sæt et kreditloft på nøglen.
- **To modelnavne fra openrouter.ai/models:** en tekstmodel med *tool calling* (til chat og
  artikler) og, hvis pluginnet skal lave billeder, en model med *image output*. Navnene skrives
  præcis som på siden, fx `udbyder/model`.
- **Adgang:** administrator i wp-admin på steamgears.eu, SSH til Command Center-serveren og
  læseadgang til de tre private repoer på GitHub.
- **Command Centers offentlige adresse** med `https://`, fx `https://cc.steamgears.eu`. Det er
  adressen, du åbner i browseren — ikke `127.0.0.1`.

---

## 1. Steamgears Autopilot 7.76.0 på steamgears.eu

Repoet er privat, så knappen *Update now* i wp-admin kan **ikke** hente versionen selv
(se `steamgears-site/docs/library/repo-privat-2026-11-08.md`). Zip'en lægges ind manuelt.

### 1a. Hent zip'en

GitHub → `humle93/steamgears-site` → `plugins/` → `steamgears-autopilot-v7.76.0.zip` → **Download raw file**.
Der ligger altid præcis én zip i mappen, og den matcher koden på `main`.

### 1b. Installér

**I wp-admin (anbefalet):** *Plugins → Tilføj nyt → Upload plugin* → vælg zip'en → *Installér nu* →
**Erstat nuværende med uploadet**. Indstillinger, nøgler, kø og kladder bevares.

**Med WP-CLI (har du SSH til sitet):**

```bash
wp plugin install /sti/til/steamgears-autopilot-v7.76.0.zip --force --activate
wp plugin get steamgears-autopilot --field=version     # skal give 7.76.0
```

> **Kendt fælde:** den første side efter installationen kan svare **500** i hele REST-laget, fordi
> W3 Total Caches database-cache rammer pluginnets tabelopdatering. Genindlæs siden én gang; den
> næste request færdiggør opdateringen (målt 9/11, `plugin-installation-via-mcp-2026-11-09.md`).
> Tøm derefter cachen: *Performance → Purge All Caches*.

### 1c. Flyt AI'en til OpenRouter

1. *Steamgears → Settings → Keys* → kortet **OpenRouter (backup)**: indsæt OpenRouter-nøglen og vælg
   tekstmodellen fra listen. Gem — nøgletesten kører på næste side og skal være grøn.
2. Øverst på pluginnets sider står nu **»AIMLAPI is being phased out«** med knappen
   **Switch to OpenRouter now**. Tryk på den. OpenRouter bliver hovedudbyder med præcis den nøgle og
   model; den gamle AIMLAPI-nøgle røres ikke, så du kan skifte tilbage under *AI content*.
   *(Bruger sitet i forvejen en anden udbyder end AIMLAPI, vises knappen ikke; vælg så OpenRouter
   direkte under Settings → AI content → AI provider.)*
3. *Settings → AI content* → **OpenRouter image model**: indsæt billedmodellen. Derefter laves
   billeder via OpenRouter; uden feltet bruges AIMLAPI som før.
4. Tjek: dashboardet viser `Images: <din billedmodel>`, og en kladde fra *AI Drafts → Generate*
   lykkes.

---

## 2. Command Center 7.27.0

### 2a. Opdatér koden

På serveren, i `~/command-center`:

```bash
bash scripts/update.sh --check      # hvad der er nyt, skriver intet
bash scripts/update.sh              # DB-backup → filer → requirements → genstart → venter på /health
bash scripts/update.sh --version    # filer, kørende proces og install.sh skal alle sige 7.27.0
```

`update.sh` kræver `GITHUB_TOKEN` i `.env`, fordi repoet er privat. Stopper den med **kode 7**, er
`install.sh` på disken ældre end koden: kør `git checkout -- install.sh` (eller `git pull`) og prøv igen.

**Ny installation** (ingen eksisterende mappe): kopiér `install.sh` fra repoet til serveren og kør
`bash install.sh` — se `docs/Command_Center_Install_Script.md`. Flyttes en gammel installation, så
følg `docs/Command_Center_Migrering.md`.

### 2b. Nye linjer i `.env`

Åbn `~/command-center/.env` og sæt (resten af filen røres ikke):

```ini
OPENROUTER_API_KEY=sk-or-...          # nøglen fra trin 0
AI_MODEL=udbyder/model                # tekstmodellen (skal kunne bruge tools, hvis chatten skal bruges)
CC_PUBLIC_URL=https://cc.steamgears.eu  # præcis den adresse du åbner i browseren, med https://
```

- Står der stadig `AIMLAPI_KEY=`, kan linjen slettes. Den bruges ikke længere og giver en advarsel
  ved opstart, så længe `OPENROUTER_API_KEY` mangler.
- `CC_PUBLIC_URL` styrer nu fire ting: login-linket i scripts, adressen i invitationsmails,
  Host-tjekket på `/mcp` **og login-knappen i WordPress**. Uden `https://` bliver knappen ikke forbundet.
- Genstart bagefter: `bash scripts/restart.sh` (eller `systemctl --user restart command-center`).

### 2c. Forbind login-knappen

1. Log ind i Command Center med e-mail og adgangskode → fanen **📱 Social** → kortet
   *Steamgears Autopilot* → **🔑 Forbind login-knappen nu**. Svaret skal være
   »Login-knappen i WordPress er forbundet til https://…«. (Det sker også selv ved næste sync, højst
   30 min.)
2. **Din WordPress-bruger skal have samme e-mail som din Command Center-bruger.** Knappen opretter
   aldrig en ny konto. Mangler den, så invitér e-mailen under **👤 Brugere** — eller ret e-mailen i
   WordPress under *Brugere → Profil*.
3. I wp-admin: *Steamgears → Dashboard* → **Log ind i Command Center**. Der åbnes en ny fane, og du er
   logget ind uden adgangskode. Billetten holder 1 minut og virker én gang.

### 2d. Chat og connectors (valgfrit)

Fanen **💬 Chat** bruger `OPENROUTER_API_KEY` og `AI_MODEL` (eller `CHAT_MODEL`). Tilføj connectors
nederst på fanen — GitHub (personal access token), Steamgears (bruger `WP_USER`/`WP_APP_PASSWORD` fra
`.env`) eller andre MCP-servere. Gmail, Google Drive og WordPress.com kræver en URL og et token fra en
MCP-server/gateway; et OAuth-login direkte fra Command Center findes ikke endnu.

---

## 3. wp-auto-deployer

Den fulde trin-for-trin-guide ligger i repoet: `docs/installationsguide-for-begyndere.md`. Kort:

```bash
git clone https://github.com/humle93/wp-auto-deployer.git && cd wp-auto-deployer
bash scripts/install.sh --check                        # lokalt: venv, .env med nøgle, database, livstjek
bash scripts/install.sh --service --nginx deployer.ditdomæne.dk --check   # på en server
loginctl enable-linger "$USER"                         # servicen kører videre efter logout
```

- Scriptet viser **operatør-nøglen én gang**. Den står også i `.env` som `DEPLOYER_API_KEYS`.
  Alt under `/api/` kræver den (`Authorization: Bearer <nøgle>` eller `X-API-Key`); i `/docs` trykker
  du **Authorize**.
- `--nginx` skriver `deploy/nginx-wp-auto-deployer.<domæne>.conf`. Kopiér den til
  `/etc/nginx/sites-available/`, aktivér den, kør `sudo certbot --nginx -d <domæne>` og
  `sudo nginx -t && sudo systemctl reload nginx`.
- Appen starter i **dry-run** (`DEPLOYER_DRY_RUN=1`). Live-udrulning (Docker, Cloudflare, rigtige
  WordPress-sites) kræver alt i guidens afsnit 6, før du sætter den til `0`.

---

## 4. Tjekliste efter udrulning

| Tjek | Hvordan | Forventet |
| --- | --- | --- |
| Plugin-version | wp-admin → Plugins | Steamgears Autopilot **7.76.0** |
| AI via OpenRouter | Settings → Keys | AI-nøgletest grøn, udbyder *OpenRouter* |
| Billeder | Dashboard | `Images: <billedmodel>` |
| Command Center-version | `bash scripts/update.sh --version` | 7.27.0 tre steder, kode 0 |
| AI i Command Center | Cockpit → Setup-linjen | `AI ✅` |
| Login-knappen forbundet | Command Center → Social | »Knappen … i WordPress: forbundet« |
| Login med ét klik | wp-admin → Steamgears → *Log ind i Command Center* | Command Center-dashboardet åbner |
| Login står i loggen | Command Center → Alarmer | »Login fra WordPress (ét klik): <e-mail>« |
| wp-auto-deployer | `bash scripts/install.sh --check` | `/healthz` OK, 401 uden nøgle, 200 med nøgle |

---

## 5. Fejlfinding

| Symptom | Årsag | Løsning |
| --- | --- | --- |
| *Update now* i wp-admin siger »Could not read the latest version from GitHub« | Repoet er privat | Upload zip'en manuelt (1b) |
| 500 på alle sider lige efter plugin-upload | W3TC's DB-cache og tabelopdateringen | Genindlæs én gang, tøm cachen |
| Ingen knap *Switch to OpenRouter now* | Udbyderen er ikke AIMLAPI, eller reserven mangler nøgle/model | Vælg OpenRouter under *AI content*, eller udfyld reservekortet |
| Billeder fejler med »is … a model with image output?« | Billedmodellen kan ikke lave billeder | Vælg en model med *image output* på openrouter.ai/models |
| Social siger »kræver CC_PUBLIC_URL (https)« | `CC_PUBLIC_URL` mangler, er `http://` eller har forkert format | Ret `.env` (2b) og genstart |
| Social siger »Pluginnet kender ikke /cc-link (404)« | Sitet kører en ældre plugin end 7.76.0 | Installér 7.76.0 (trin 1) |
| WordPress-knappen siger »needs Command Center 7.27+« | Command Center har ikke sendt adresse og nøgle endnu | *Forbind login-knappen nu* i Social |
| Login-siden: »Din WordPress-e-mail findes ikke som bruger« | E-mailerne er forskellige | Invitér e-mailen i Command Center, eller ret den i WordPress |
| Login-siden: »billetten er udløbet« | Mere end 1 minut, eller urene er langt fra hinanden | Tryk igen; tjek `timedatectl` på serveren |
| Login-siden: »for mange fejlede logins« | 5 fejl fra samme IP | Vent 10 minutter |
| wp-auto-deployer `/api/` giver 503 | `DEPLOYER_API_KEYS` er tom | `bash scripts/install.sh --env-only` og genstart |

---

## 6. Rollback

- **Plugin:** upload den forrige zip (`git show <commit>:plugins/steamgears-autopilot-v7.75.0.zip >
  forrige.zip` i steamgears-site) med *Erstat nuværende*. 7.76.0 tilføjer kun indstillingen
  `sgap_openrouter_image_model` og optionen `sgap_cc_link`, som en ældre version ignorerer.
- **Command Center:** `update.sh` tager en `pre-update`-backup af databasen i `backups/`; gendan den
  under *Moduler → Gendan* (skriv `GENDAN`) og check en ældre commit ud. Tabellerne fra 7.26/7.27
  (`mcp_connectors`, `chat_*`, `sso_used`) ignoreres af ældre versioner.
- **wp-auto-deployer:** `systemctl --user stop wp-auto-deployer`; `.env` og `command_center.db` ligger
  i projektmappen og overlever en ny `git checkout`.
