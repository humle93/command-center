# Command Center — migrering af serveren `laser` til dette repo

Denne side er arbejdsinstruksen for at flytte serveren `laser`s `~/command-center` fra den gamle
`Steamgears-site`-linje (v8.3) over på **dette** repo (v7.19.1 og frem), så
`bash scripts/update.sh --version` og versionsguarden beskytter installationen bagefter.

Den er skrevet til at blive fulgt fra serveren, linje for linje, med et stop-punkt i hver fase. Alle
kommandoer køres som **den bruger der ejer installationen** (ikke root), med start i `~`.

**Estimat:** ~60 min i alt, hvoraf ~5 min er nedetid i fase 3. Fase 0 er beslutninger uden kommandoer.

---

## 1. Hvad der flyttes, og hvorfor

| | I dag på `laser` | Efter migreringen |
| --- | --- | --- |
| Kode | `Steamgears-site`, app v8.3 fra CDN | dette repo, `main` |
| `app/main.py` på disken | v7.5 | v7.19.1 (eller nyere) |
| `install.sh` på disken | v7.9 | samme version som koden |
| Database | skema fra v8.3 | frisk database (se fase 0) |
| Versionskontrol | findes ikke | `bash scripts/update.sh --version` = kode 0 |

Problemet i dag er ikke at appen kører — det er at **tre filer i samme mappe kan være tre forskellige
versioner**, og at en gammel `install.sh` overskriver `app/main.py` med sin indlejrede, ældre kopi, hvis
nogen kører den. Det sker uden en fejlmeddelelse og viser sig først ved næste genstart.

Efter migreringen gælder:

- `--version` sammenligner **tre** kilder: processen (`/health`), filerne (`app/main.py`) og
  installatøren (`install.sh`s indlejrede `app/main.py`). Kode 0 = ens, kode 1 = uenighed.
- Opdateringen (`bash scripts/update.sh`, også fra Cockpit) **nægter at skrive filer** med kode 7, hvis
  `install.sh` på disken er ældre end koden. Intet røres; vejen ud er `git checkout -- install.sh`
  eller `git pull`.

Detaljerne i kontrollen står i [README](../README.md) og i
[bruger- og systemmanualen](Command_Center_Bruger_og_Systemmanual.md).

## 2. Sådan bruges dokumentet

Faserne køres i rækkefølge. Hver fase har **Mål**, **Kommandoer**, **Forventet** og **Stop-punkt**.
Stop-punktet er det sted, hvor du skal stoppe og spørge, hvis noget ikke ser ud som forventet — ikke
køre videre og håbe.

Tre ting skal du have ved hånden, før du begynder: din `GITHUB_TOKEN`, den offentlige adresse du vil
bruge, og en ledig halv time uden for kundernes travleste tid.

## 3. Fase 0 — Beslutninger (5 min, ingen kommandoer)

### 3.1 Data: frisk database

v8.3 kommer fra en anden projektlinje end dette repo. Skemaet er derfor **ikke** garanteret kompatibelt,
og en app der starter mod et fremmed skema kan ændre tabeller undervejs. Beslutningen er derfor:

- den gamle database **flyttes med til side** (den slettes ikke),
- den nye installation starter på en **frisk** database,
- nøgler og integrationer indtastes igen fra den gamle `.env`.

| Data | Hvad der sker |
| --- | --- |
| Brugere og adgangskode-hashes | oprettes igen (standardbruger fra `.env` eller via `/setup`, resten i fanen **Brugere** eller med `scripts/user_create.py`) |
| SerpAPI, WordPress, Telegram | kopieres fra den gamle `.env` ind i den nye; AI kræver nu `OPENROUTER_API_KEY` (en gammel `AIMLAPI_KEY` bruges ikke) |
| Artikler, søgeord, planlagte opslag | starter tomt. Skal de med, gøres det som et **separat** arbejde med en gennemgang af skemaet først — ikke som en del af cutover |

### 3.2 Adresse: fast domæne, ikke `trycloudflare`

En `trycloudflare`-tunnel får **ny URL ved hver genstart**. `CC_PUBLIC_URL` styrer tre ting: login-linket
i `scripts/update.sh` og `scripts/user_create.py`, adressen i invitationsmailen og Host-tjekket på `/mcp`
(nøgler afvises med 421 ved forkert vært). Skiftende URL betyder derfor, at `.env` skal rettes hver gang.

Brug den faste adresse serveren har, med understi: `CC_PUBLIC_URL=https://<bruger>.<server>.usbx.me/cc`
og `deploy/nginx-ultracc-proxy.conf` i `~/.apps/nginx/proxy.d/` (v7.28 — før kunne appen ikke ligge på en understi,
og det var grunden til tunnellen). Tunnellen stoppes og fjernes som beskrevet i
[Installation og udrulning §2e](Installation_og_udrulning.md#2e-ultracc-uden-cloudflare).

### 3.3 Stien er ikke valgfri

`install.sh` skriver til **`$HOME/command-center`** (linje 3, hardkodet). Den nye installation skal derfor
ligge præcis der, og den gamle mappe skal flyttes asides først. Det er grunden til rækkefølgen i fase 3:
stop → flyt til side → flyt ny ind på pladsen.

## 4. Fase 1 — Kortlægning (10 min, ingen ændringer)

**Mål:** vide hvad der kører, hvem der ejer porten, og have en kopi af nøglerne — før noget flyttes.

```bash
# 1) Hvordan startes appen? (mest sandsynligt en systemd-brugerenhed)
systemctl --user list-units --all | grep -i command-center
systemctl list-units --all | grep -i command-center

# 2) Hvem lytter på 8000?
ss -ltnp | grep ':8000'

# 3) Hvad er der i mappen - og er den committet?
ls -la ~/command-center
git -C ~/command-center remote -v
git -C ~/command-center status --short | head

# 4) Databasen og dens størrelse
ls -la ~/command-center/app/data/

# 5) Nøglerne - kopi ud af huset, før noget flyttes (fast navn: bruges i fase 2)
cp ~/command-center/.env ~/.env-backup-laser
chmod 600 ~/.env-backup-laser

# 6) Hvad peger ind udefra? (tunnel eller nginx)
ps -eo pid,args | grep -i -e cloudflared -e nginx | grep -v grep
```

**Forventet:** én unit eller én proces på 8000, en `app/data/*.db`, og en `.env` med nøgler.

**Stop-punkt:** hvis port 8000 ejes af noget andet end Command Center, eller hvis
`git -C ~/command-center status --short` viser ændringer du ikke kender — stop og afklar det først.
(Filer du selv har ændret, er ikke et problem — mappen flyttes som den er.)

Skriv ned i din notesblok: unit-navnet, tunnel-kommandoen, den offentlige adresse og databasens filnavn.

## 5. Fase 2 — Skyggeinstallation på anden port (15 min)

**Mål:** bevise at den nye kode starter på maskinen — Python-version, afhængigheder, database — uden at
nogen bruger mærker det. Den kørende app røres ikke i denne fase.

```bash
git clone https://github.com/humle93/command-center.git ~/cc-test
cd ~/cc-test
git log -1 --oneline        # seneste commit på main (i skrivende stund d3d4502)
cp ~/.env-backup-laser .env
sed -i 's/^CC_PORT=.*/CC_PORT=8010/' .env
chmod 600 .env
```

**Kør `./run.sh` — ikke `./install.sh`.** Installatøren peger på `~/command-center` og ville skrive ind i
den kørende installation.

```bash
./run.sh        # opretter venv, installerer requirements, starter på 8010
```

I en anden terminal:

```bash
curl -s localhost:8010/health | python3 -m json.tool | head -20
curl -s -o /dev/null -w '%{http_code}\n' localhost:8010/login     # 200
curl -s -o /dev/null -w '%{http_code}\n' localhost:8010/setup     # 200 (ingen brugere endnu)
```

**Forventet:** `/health` svarer `"status": "ok"`, `"version": "7.19.1"`, `"db_write": true`,
`"users": 0`; `/login` og `/setup` giver 200.

Versionskontrollen virker også her, fordi `update.sh` læser `CC_PORT` fra `.env`:

```bash
bash scripts/update.sh --version
```

**Forventet:** `✅ Alle kilder stemmer: v7.19.1.` og kode 0 (`echo $?`). Alle tre kilder er ens, fordi
skyggen er et rent klon af samme commit.

**Stop-punkt:** svarer `/health` ikke, eller fejler `pip install` i `run.sh`, så læs de første fejllinjer
og smid mappen væk (`rm -rf ~/cc-test`). Produktion er stadig urørt, og intet er tabt.

## 6. Fase 3 — Cutover (15 min, kort nedetid)

**Mål:** den nye installation på den sti `install.sh` forventer, med samme port som i dag, så tunnel og
nginx ikke skal ændres.

```bash
# 1) Stop den gamle app - med unit, ikke med pkill -f
systemctl --user stop command-center         # eller det unit-navn fase 1 viste
# uden systemd: kill <pid fra ss-output i fase 1>   (aldrig pkill -f / killall)

# 2) Flyt den gamle til side - flyt, slet ikke
mv ~/command-center ~/command-center-v83-$(date +%F)

# 3) Den nye ind på pladsen
mv ~/cc-test ~/command-center
cd ~/command-center
sed -i 's/^CC_PORT=.*/CC_PORT=8000/' .env
```

Ret `.env` før start. Kendt fejl på serveren: `run.sh` laver `set -a; source .env`, så en værdi uden
anførselstegn med specialtegn giver `line 11: 7pkI: command not found`.

```bash
# Værdier med mellemrum eller specialtegn SKAL i anførselstegn:
#   WP_APP_PASSWORD="abcd efgh ijkl"
# Ingen mellemrum omkring =, ingen kommentar efter værdien.
grep -n "'" .env | head        # apostroffer i værdier er den anden klassiske fælde
```

De tre linjer der skal stemme:

```bash
CC_HOST=127.0.0.1
CC_PORT=8000
CC_PUBLIC_URL=https://din-faste-adresse      # med https://, uden anførselstegn
```

Og til opdateringen:

```bash
GITHUB_TOKEN=github_pat_...                  # så --check og opdateringen virker
```

Start:

```bash
./run.sh
```

Eller som bruger-service, hvis serveren bruger det i dag (unit-filen ligger i repoet og peger på
`%h/command-center`):

```bash
mkdir -p ~/.config/systemd/user
cp deploy/command-center.user.service ~/.config/systemd/user/command-center.service
systemctl --user daemon-reload
systemctl --user enable --now command-center
```

Brugeren oprettes på én af to måder — der er ingen token i denne version:

- **Automatisk (v7.18+):** står `CC_ADMIN_EMAIL` og `CC_ADMIN_PASSWORD` i `.env` **før** første start,
  opretter appen kontoen i opstartsloggen (`[cc] standardbruger: oprettet`) med `must_change_password`,
  så koden skal skiftes ved første login. Det er den nemmeste vej på en server uden browser.
- **I browseren:** ellers går første besøg til **`/setup`**, som opretter brugeren og derefter lukker sig
  selv.

Derefter: nye brugere i fanen **Brugere** (kræver `SMTP_HOST` + `SMTP_FROM`) eller

```bash
python3 scripts/user_create.py dig@domaene.dk --username ditbrugernavn
```

**Forventet:** login virker (koden fra `.env` skal skiftes med det samme), dashboardet tegner, og
`/health` viser `"version": "7.19.1"`.

**Stop-punkt:** virker login ikke, eller crasher appen ved opstart, så gå til **Rollback** nedenfor.
Den gamle mappe står urørt med kode, `.env` og database.

## 7. Fase 4 — Bevis at guarden beskytter installationen (5 min)

**Mål:** ikke bare at versionerne er ens, men at en gammel installatør faktisk bliver afvist.

```bash
cd ~/command-center
bash scripts/update.sh --version ; echo "kode: $?"
```

**Forventet:**

```
Command Center - versionskontrol
   kører nu:    v7.19.1   (processen, fra http://127.0.0.1:8000/health)
   filer:       v7.19.1   (app/main.py på disken)
   installatør: v7.19.1   (install.sh, indlejret app/main.py)
✅ Alle kilder stemmer: v7.19.1.
kode: 0
```

Kører processen ikke (fx fordi du tjekker fra en anden mappe uden app), står der `kører nu: ukendt` og
koden er 1 med linjen "kan ikke sammenlignes". Det er ikke en versionsfejl — start appen og kør igen.

Den ægte prøve — fremkald en gammel installatør og se at intet skrives:

```bash
cp install.sh /tmp/install.sh.bak
cksum app/main.py                             # notér summen
sed -i '0,/^APP_VERSION = "/s/^APP_VERSION = ".*"/APP_VERSION = "0.0.1"/' install.sh
bash scripts/update.sh --version ; echo "kode: $?"     # forventet: kode 1 + "install.sh er ældre"
bash scripts/update.sh --no-restart ; echo "kode: $?"  # forventet: kode 7, intet skrevet
cksum app/main.py                             # samme sum som før
cp /tmp/install.sh.bak install.sh
bash scripts/update.sh --version ; echo "kode: $?"     # tilbage til 0
```

**Forventet ved kode 7:**

```
❌ Stopper før der bliver skrevet filer: install.sh på disken er ældre (v0.0.1) end koden (v7.19.1).
   Den installatør ville overskrive app/main.py med v0.0.1, hvis nogen kørte den nu.
   Hent den rette version først:   git checkout -- install.sh   (eller git pull)
   Intet er ændret - kør scriptet igen bagefter. (--check og --version skriver intet og virker stadig.)
```

| Kode | Betydning |
| --- | --- |
| 0 | alle tre kilder stemmer |
| 1 | uenighed — `forskel`-linjen siger hvilken (genstart mangler / installatør ældre / filer rullet tilbage) |
| 7 | opdateringen nægtede at skrive, fordi `install.sh` er ældre end koden. Intet er rørt |
| 2 | `venv` mangler — start appen én gang med `./run.sh` |

**Stop-punkt:** giver `cksum app/main.py` en anden sum efter testen, er noget skrevet alligevel — stop og
undersøg, før du fortsætter. (Det bør ikke kunne ske: guarden kører før både venv-, token- og netværkskald.)

## 8. Fase 5 — Adgang udefra (5 min)

**Mål:** samme adresse som før, men pegende på den nye proces.

- Tunnel eller nginx skal pege på `127.0.0.1:8000` (uændret, hvis du beholdt porten).
- Går trafikken gennem nginx, skal `CC_FORWARDED_ALLOW_IPS=127.0.0.1` stå i `.env` — ellers logges
  proxyens IP i stedet for brugerens, og cookien bliver ikke `Secure`.
- `CC_PUBLIC_URL` skal være **præcis** den adresse du skriver i browseren, ellers afviser `/mcp` med 421.

```bash
bash scripts/smoke_test.sh          # /health, /login, /setup
curl -s https://din-faste-adresse/health | python3 -m json.tool | head -5
```

**Forventet:** 200 gennem proxyen, `"version": "7.19.1"`, og login i browseren virker.

**Stop-punkt:** 502/504 betyder at proxyen peger det forkerte sted hen — ret proxyen, ikke appen.

## 9. Fase 6 — Oprydning (5 min, gerne en uge senere)

```bash
# Den gamle mappe: behold en uge, derefter arkivér .env + DB og slet resten
tar czf ~/command-center-v83-$(date +%F).tar.gz \
    -C ~ command-center-v83-$(date +%F)/.env command-center-v83-$(date +%F)/app/data
```

- Kontrollér at ingen unit, cron-job eller tunnel-kommando stadig peger på den gamle mappe:
  `systemctl --user cat command-center | grep -i command` og `crontab -l | grep -i command`.
- Lad være med at sætte upstream manuelt. Et friskt klon har allerede `main` → `origin/main`; den gamle
  fejl ("There is no tracking information for the current branch") kommer fra et repo, hvor det manglede.
- `.env` bliver liggende i mappen (gitignored). Kopien i `~/.env-backup-*` må gerne slettes, når du har
  verificeret at den nye installation har alle nøgler.

## 10. Rollback

Rollback er to `mv` og et `start`, fordi den gamle mappe blev flyttet og ikke ændret.

```bash
systemctl --user stop command-center
mv ~/command-center ~/cc-forsoeg-$(date +%F)
mv ~/command-center-v83-$(date +%F) ~/command-center
systemctl --user start command-center     # eller: cd ~/command-center && ./run.sh
```

Den gamle mappe indeholder både kode, `.env` og database, så den kører som før. Intet i migreringen
skriver i den.

## 11. Hvad guarden dækker — og ikke dækker

| Situation | Dækket? |
| --- | --- |
| `install.sh` på disken er ældre end `app/main.py` | **Ja** — opdateringen stopper med kode 7, `--version` med kode 1 |
| Koden er opdateret, men processen kører videre | **Ja** — `--version` siger "genstart mangler" |
| Filerne er rullet tilbage til en ældre version | **Ja** — `--version` siger "filerne er rullet tilbage" |
| Der køres en installatør fra en *anden* mappe | Nej — den ved ikke hvad den overskriver |
| Den aktive mappe er den forkerte | Nej — det er derfor fase 1 og fase 6 findes |
| Gamle data i en fremmed database | Nej — se fase 0 |

## 12. Tjekliste

- [ ] Fase 0: frisk database valgt, fast adresse valgt
- [ ] Fase 1: unit-navn, portejer, tunnel og `.env`-backup noteret
- [ ] Fase 2: `/health` på 8010 svarer v7.19.1, `/setup` og `/login` giver 200, `--version` = 0
- [ ] Fase 3: gammel app stoppet, gammel mappe flyttet, ny mappe på plads, `.env` rettet, login kørt
- [ ] Fase 4: `--version` = 0, `--check` grøn, guard-test gav kode 7 og urørt `app/main.py`
- [ ] Fase 5: adgang udefra virker, `/health` gennem proxyen viser v7.19.1
- [ ] Fase 6: ingen unit/cron peger på den gamle mappe

## 13. Kendte fejl på serveren og løsningen

| Fejl | Årsag | Løsning |
| --- | --- | --- |
| `.env: line 11: 7pkI: command not found` | værdi uden anførselstegn; `run.sh` laver `set -a; source .env` | sæt værdien i `"..."` (fase 3) |
| `git pull` → "There is no tracking information" | klon uden upstream | friskt klon har det; sæt det ikke manuelt |
| `./install.sh` → Permission denied | filen er ikke eksekverbar | `chmod +x install.sh` — men i denne plan køres den ikke |
| port 8000 "address already in use" | den gamle proces kører stadig | stop unit'en først (fase 3, trin 1) |
| `/mcp` svarer 421 | `CC_PUBLIC_URL` matcher ikke den vært klienten bruger | ret `CC_PUBLIC_URL` i `.env` og genstart |
| `--version` giver kode 1 uden grund | processen kører en anden port end `.env` siger | tjek `CC_PORT` og `ss -ltnp` |

## 14. Tidsestimat

| Fase | Indhold | Estimat |
| --- | --- | --- |
| 0 | beslutninger om data og adresse | 5 min |
| 1 | kortlægning og backup af `.env` | 10 min |
| 2 | skyggeinstallation på 8010 | 15 min |
| 3 | cutover og første login | 15 min |
| 4 | versionskontrol og guard-test | 5 min |
| 5 | adgang udefra | 5 min |
| 6 | oprydning (kan vente en uge) | 5 min |
| | **i alt** | **~60 min**, heraf ~5 min nedetid |

Det, der kan trække ud, er ikke kommandoerne men de tre ukendte: hvordan appen startes i dag, hvordan
tunnelen er sat op, og om `.env` indeholder værdier der skal citeres. Fase 1 finder de to første, fase 3
det tredje.

---

Sidst ændret: 4. november 2026
