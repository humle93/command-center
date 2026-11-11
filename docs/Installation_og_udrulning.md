# Installation og udrulning — Steamgears Autopilot, Command Center og wp-auto-deployer

Samlet manual for de tre dele, der hænger sammen fra 11. november 2026:

| Del | Version | Repo | Hvor den kører |
| --- | --- | --- | --- |
| **Steamgears Autopilot** (WordPress-plugin) | 7.76.0 | `humle93/steamgears-site` → `plugins/steamgears-autopilot-v7.76.0.zip` | steamgears.eu (Simply) |
| **Command Center** | 7.28.0 | `humle93/command-center` | din server (`laser`, Ultra.cc eller Docker) bag nginx |
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

## 2. Command Center 7.28.0

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

### 2e0. Eget domæne eller offentlig IP (enklest — ingen nginx, ingen tunnel)

```bash
cd ~/command-center
bash scripts/ultracc_setup.sh --domain www.ditdomaene.dk                     # plan - skriver intet
bash scripts/ultracc_setup.sh --domain www.ditdomaene.dk --apply             # http://www.ditdomaene.dk:<port>
bash scripts/ultracc_setup.sh --domain www.ditdomaene.dk --port 80 --apply   # uden :port (kræver root)
bash scripts/ultracc_setup.sh --ip --apply                                   # uden domæne: http://<offentlig-ip>:<port>
```

**Domænet:** opret først en A-post hos din DNS-udbyder: `www.ditdomaene.dk → <serverens offentlige IP>`. Scriptet slår
domænet op og stopper, hvis der ingen A-post er, eller hvis den peger på lokalnet. Peger den på en anden offentlig IP end
serverens netkort, siger det til (det er rigtigt bag en router med portviderestilling, ellers er A-posten forkert).

**Kun offentligt:** localhost og lokalnet (10.x, 192.168.x, 172.16-31.x, 100.64-127.x, 169.254.x) afvises altid.

**Port 80** (adressen uden `:port`) kræver root. På Ultra.cc har du ikke root, så adressen bliver `http://www.ditdomaene.dk:<port>`
med en port fra `app-ports free`.

Scriptet stopper `cloudflared`, sætter `CC_HOST=0.0.0.0`, `CC_PORT` og `CC_PUBLIC_URL=http://<ip>:<port>` i `.env`
(backup først), skifter en gammel systemd-enhed ud og genstarter. Til sidst tjekker det, at `http://<ip>:<port>/login`
svarer 200. Så åbner du `http://<ip>:<port>/` og logger ind med e-mail og adgangskode.

- **IP'en (`--ip`):** findes selv (`hostname -I`), kun offentlige. Har serveren kun lokalnet-adresser (bag NAT), stopper scriptet; angiv så den offentlige: `--ip 203.0.113.5`.
- **Porten:** `--port`, ellers `CC_PORT` i `.env`, ellers `app-ports free`.
- **Svarer den fra serveren, men ikke fra din computer:** porten er blokeret af en firewall hos udbyderen.
- **Ingen TLS:** adgangskoden sendes ukrypteret over nettet. Brug en stærk, unik kode — eller nginx-vejen i §2e for https.
- **systemd:** enheder fra før v7.28 havde `--host 127.0.0.1 --port 8000` skrevet fast og ignorerede `.env`; scriptet skifter dem ud (backup `.bak-<tid>`) og kører `systemctl --user daemon-reload`.

### 2e. Ultra.cc uden Cloudflare

Fra v7.28 logger man ind direkte på Ultra.cc-serverens faste adresse — ingen `cloudflared`/`trycloudflare`-tunnel.
Ultra.cc giver en egen app en **understi** (`https://<bruger>.<server>.usbx.me/cc/`), og den kan appen nu ligge på.

**Hurtigst: scriptet.** Det gør skridt 1-4 nedenfor og tjekker bagefter, at login-siden svarer udefra:

```bash
cd ~/command-center
bash scripts/ultracc_setup.sh --url https://<bruger>.<server>.usbx.me/cc            # vis planen - skriver intet
bash scripts/ultracc_setup.sh --url https://<bruger>.<server>.usbx.me/cc --apply    # udfør den
```

Porten tages fra `--port`, ellers fra `CC_PORT` i `.env` (hvis den ikke er standarden 8000), ellers fra `app-ports free`.
Der tages backup af `.env` (`.env.bak-<tid>`), crontab (`~/.crontab-backup-<tid>`) og en afvigende nginx-fil, før de
ændres. `--keep-tunnel` lader `cloudflared` være. Slutter scriptet med `ok … /login svarer 200`, er du færdig — gå til 5).
Kode 2 = forkerte argumenter, 3 = et skridt fejlede, 4 = appen eller nginx svarer ikke (beskeden siger hvad du tjekker).

Manuelt, skridt for skridt:

**1) Find tunnellen og stop den** (den kan være startet på flere måder — tjek alle fire):

```bash
ps -eo pid,args | grep -i cloudflared | grep -v grep          # kører den?
systemctl --user list-units --all | grep -i cloudflared       # som systemd-brugerenhed?
crontab -l 2>/dev/null | grep -i cloudflared                  # fra cron (@reboot)?
screen -ls; tmux ls 2>/dev/null                               # i en screen/tmux?

systemctl --user disable --now cloudflared                    # ret navnet til enheden fra listen
crontab -e                                                    # slet cloudflared-linjen, hvis der er en
pkill -x cloudflared                                          # stop det, der stadig kører (-x: kun procesnavnet)
```

Står `cloudflared` i en enhed eller et script, du selv har lavet (fx `~/.config/systemd/user/cloudflared.service`
eller `~/bin/tunnel.sh`), så slet filen bagefter og kør `systemctl --user daemon-reload`.

**2) Port og adresse i `.env`** (`~/command-center/.env`):

```bash
app-ports free                       # Ultra.cc: vælg en ledig port fra listen
```

```
CC_HOST=127.0.0.1
CC_PORT=<porten>
CC_FORWARDED_ALLOW_IPS=127.0.0.1
CC_PUBLIC_URL=https://<bruger>.<server>.usbx.me/cc
```

Adressen er den faste fra Ultra.cc-panelet (samme vært som dine andre apps) + `/cc`. Ingen anførselstegn, intet `/` til sidst.

**3) nginx-blokken:**

```bash
cp deploy/nginx-ultracc-proxy.conf ~/.apps/nginx/proxy.d/command-center.conf
sed -i 's/12345/<porten>/' ~/.apps/nginx/proxy.d/command-center.conf
app-nginx restart
```

Filen er kun `location`-blokke: Ultra.cc har selv `server { }` og certifikatet. Den sætter `X-Forwarded-Proto https`
fast, så session-cookien bliver `Secure`. `proxy_pass` har **ikke** `/` til sidst — appen fjerner selv `/cc`.

**4) Genstart og log ind:**

```bash
bash scripts/restart.sh
bash scripts/update.sh --check       # "login:" skal vise https://<bruger>.<server>.usbx.me/cc/login
```

Åbn `https://<bruger>.<server>.usbx.me/cc/` → login-siden → e-mail + adgangskode (standardbrugeren fra
`CC_ADMIN_EMAIL`/`CC_ADMIN_PASSWORD` eller en bruger fra fanen **Brugere**).

**5) WordPress-knappen og MCP får den nye adresse:** næste sync sender den nye `CC_PUBLIC_URL` til pluginnet af sig selv
(fingerprintet har ændret sig), eller tryk **🔑 Forbind login-knappen nu** under Social. MCP-klienter skal pege på
`https://<bruger>.<server>.usbx.me/cc/mcp`.

| Symptom | Årsag | Løsning |
| --- | --- | --- |
| 502 Bad Gateway på `/cc/` | Appen kører ikke, eller porten i nginx-blokken ≠ `CC_PORT` (før v7.28 ignorerede systemd-enheden `CC_PORT` — scriptet skifter den ud) | `bash scripts/update.sh --version`, ret porten, `app-nginx restart` |
| 404 fra appen på alle sider | `CC_PUBLIC_URL` uden `/cc` (appen kender ikke understien) | Tilføj `/cc`, genstart |
| Siden uden layout, knapper gør intet | nginx stripper stien (`proxy_pass …/;`) **og** et ældre CC end 7.28 | Opdatér til 7.28; fjern `/` efter porten |
| Login lykkes, men man sendes tilbage til login | Cookien er `Secure`, men siden er åbnet på `http://` | Brug `https://`-adressen |
| HTTPS-advarsel i dashboardet | `X-Forwarded-Proto` mangler i blokken | Brug `deploy/nginx-ultracc-proxy.conf` uændret |

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
| Command Center-version | `bash scripts/update.sh --version` | 7.28.0 tre steder, kode 0 |
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
