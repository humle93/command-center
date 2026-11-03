# AGENTS.md — arbejdsregler for steamgears-site

Reglerne her gælder alt arbejde i dette repo, og de gælder også når arbejdet udføres af en AI-agent.

> **Læs også [`docs/agent-profil.md`](docs/agent-profil.md)** — den er indholdet (hvad projektet er,
> verificerede fakta, adgangsmatrix, opskrifter, fælder). Denne fil er formen (procenter, status, AUTO-blokke).
> Profilen kan også hentes over MCP som `project_profile`, `project_status` og `roadmap_index`
> (serveren `steamgears-profil` i [`.mcp.json`](.mcp.json), ingen site-credential nødvendig).

## 1. Fremskridtsprocent (obligatorisk)

Alt arbejde — hvert modul, hver opgave, hver batch — skal melde sin **procentvise fremgang**.
Ingen undtagelser: gælder både når noget laves færdigt, og når der bare arbejdes videre på det.

Ved hvert arbejdspas skal der meldes:

| Felt | Krav |
| --- | --- |
| Modul | Navnet på det modul/den opgave der blev arbejdet på |
| % før | Status før passet |
| % efter | Status efter passet |
| Δ | Ændringen i procentpoint |
| Grundlag | Regnestykket bag tallet (fx `3 af 5 faser` eller `0,75 af 21,1 d`) |

Regler for tallene:

- **Procenten skal kunne genberegnes** ud fra grundlaget. Ingen tal uden regnestykke, ingen "føles som 70 %".
  Brug de dokumenterede estimater (developer-dage i `docs/roadmap.md`, timer i
  `docs/library/om-maerkning-dark-academia-2026-11-01.md` osv.) som nævner.
- **Første måling** skrives som `% før: —` (ingen tidligere baseline).
- **Procenten må ikke falde** uden at årsagen står i loggen (fx at scope er ændret eller et modul er opdelt).
- **100 % betyder færdigt og verificeret**, ikke "kode skrevet". Er noget blokeret, bliver modulet stående
  under 100 % med blokeringen noteret.
- **Blokeret arbejde tæller ikke som fremgang.** S0.4 er 0 %, selv om den er forsøgt.

## 2. Daglig projektstatus (obligatorisk)

Hvert **aktivt projekt** skal have en procentstatus hver dag i [`docs/projektstatus.md`](docs/projektstatus.md).

- Filen har to dele: **§1 Daglig status** (én række pr. aktivt projekt, dags dato) og **§2 Log** (alle målinger,
  nyeste først).
- En dag uden arbejde skrives stadig: samme procent, med grundlaget `ingen ændring`.
- `§1` overskrives hver dag; `§2` er append-only og må ikke ryddes.
- Daglig status skal **også meldes i svaret til ejeren**, ikke kun stå i filen.

## 3. Format

```
Modul: Dark academia-rebrand — batch 4 (mockups)
Før: 63 %  →  Efter: 78 %  (Δ +15)
Grundlag: 2 af 5 mockup-faser klar (4,5 t af 6,5 t i mockup-brief)
```

## 4. Automation og værn (`projektstatus.py`)

Reglen over holdes automatisk, så lidt som muligt afhænger af hukommelse:

- Procenterne **beregnes** ud fra [`projektstatus.json`](projektstatus.json) (moduler med `done`/`total`/`unit`).
  Ingen procenter tastes ind i Markdown.
- [`docs/projektstatus.md`](docs/projektstatus.md) skrives kun mellem `AUTO:`-markørerne. **Manuel tekst i en
  AUTO-blok er forbudt**, og `--check` fejler hvis den ændres — ret i stedet JSON-filen.
- Sådan opdateres en procent: ret `done`/`total` i `projektstatus.json`, kør `python3 projektstatus.py --update`.
  Scriptet beregner procenter, skriver filerne og tilføjer historik-rækken selv.
- `python3 projektstatus.py --brief` skriver samme status ind i `docs/daily-briefs/<dato>.md` (markør
  `AUTO:PROJEKTSTATUS`), så procenterne også står i det brief der læses hver dag. CI kører den efter `--update`.

**Værn før skrivning** (`--selftest`, `--check`):

- 22 selftest-fixtures bekræfter at værnene fanger fejl, før noget installeres eller skrives.
- Skema og typer, `done <= total`, `total > 0`, duplikerede id'er, blandede enheder i samme projekt,
  manglende enhed/grundlag, internationally gyldige datoer og ingen dato i fremtiden.
- **100 % kræver `"verified": true`** — ellers er tallet en påstand, ikke en status.
- **Fald i procent afvises** både i forhold til forrige række og til modulernes tal, medmindre rækken har
  `"scope_change": true` (og så skal årsagen stå i `module`/`basis`).
- `delta` skal passe med `after - before`. Drift i dokumentet (håndredigerede AUTO-blokke) fanges.

**Værn efter skrivning:**

- Atomisk skrivning (temp-fil + `os.replace`) og backup til `.projektstatus-backups/` (de 10 nyeste).
- Filerne læses og valideres igen bagefter; matcher indholdet ikke det beregnede, rulles den forrige version
  tilbage og kommandoen fejler.
- Kørselslås (`.projektstatus.lock`) så to samtidige kørsler ikke kan overskrive hinanden.
- CI (`.github/workflows/projektstatus.yml`) kører selftest → check → update → efterkontrol **hver dag**, fejler
  jobbet med en annotation ved brud og committer kun når noget faktisk ændrede sig.
- **Natlig auto-push** (`.github/workflows/natlig-push.yml`): hver nat **kl. 02 dansk tid** kører værnene,
  opdaterer daglig status + brief og committer **alt** i træet og pusher til `main`, med tre genforsøg og
  `pull --rebase` hvis nogen kom først. Kørslen ligger på begge de UTC-timer der kan være kl. 02 lokalt og
  springer selv over når den lokale time ikke er 2, så sommertid ikke skal rettes. Den kan kun pushe det der
  ligger i repoet — ucommittet arbejde i en agent-sandkasse ser den ikke — så reglen om at committe og pushe i
  samme tur gælder stadig; nattens kørsel er sikkerhedsnettet, ikke en erstatning.
  Efter pushet kører kørslen **alle repoets værn** via [`tools/natlige-vaern.sh`](tools/natlige-vaern.sh):
  `php -l` på alle plugin-filer, `projektstatus.py --selftest` og `--check`, `load_campaign.py --selftest`,
  `plugins/tests/smoke.php`, `test_mcp_rest.py`, `test_mcp_oauth.py`, `test_niche_scanner.py` og en
  PDF-render-kontrol af tre biblioteksdokumenter. Et rødt værn
  giver en `::error`-annotation, skriver en tabel og de fejlende linjer i job-summaryen og fejler jobbet. Det
  ligger bevidst efter pushet, så en testfejl ikke holder status-dokumenterne tilbage — men det kan ikke
  overses. Den samme kommando kan køres lokalt før et push: `bash tools/natlige-vaern.sh`.

- **Natlig niche-scanning** (`.github/workflows/niche-scan.yml`): kl. 02:30 dansk tid scanner de 11 søgeord
  fra `tools/niche_seeds.txt` mod Pinterest Trends, skriver `reports/niche-scan-<dato>.md`/`.json` og
  committer kørselsdagen i `reports/niche-scan-history.json` — så tre-dages-gaten passer sig selv. Kræver
  repository-secret `PINTEREST_ACCESS_TOKEN`; mangler det, springes scanningen over med en `::notice`, og
  gaten flyttes ikke. Er tokenet udløbet (401), fejler jobbet rødt. Hvad et token kræver, og hvad kørslen
  ikke kan: se [`docs/library/niche-scan-ci-2026-11-03.md`](docs/library/niche-scan-ci-2026-11-03.md).

Automationen dækker **den daglige status**. Det manuelle i §1 — at vurdere hvad der reelt blev udført og melde
`% før → % efter` i svaret og commit-beskeden — kan scriptet ikke gøre og falder stadig på den der arbejder.

## 5. Øvrige regler

- **Alt arbejde skal ende på `main`.** Push i samme tur som arbejdet blev lavet (`cloud_git`), og senest af den
  natlige kørsel kl. 02. Efterlad ikke commits lokalt "til senere".
- Repoet er dokumentation og assets for **steamgears.eu**; WordPress-kernen ligger hos Simply. Ændringer på
  selve sitet sker over MCP, ikke her.
- Sproget i commits og dokumentation er dansk, med tekniske termer på engelsk.
- Nye dokumenter lægges i `docs/` (audits og research i `docs/library/`), og refereres fra `README.md` eller
  roadmap'en, så de ikke bliver forældreløse.
- **Ny viden skal ud som PDF.** Viden der er værd at gemme — målte fakta, diagnoser, opskrifter, fejl der kostede
  en runde — skrives som dokument i `docs/library/` og renderes til en PDF i `reports/`, som lægges i det lukkede
  research-bibliotek:

  ```bash
  PYTHONPATH=tools/_deps python3 tools/md_to_pdf.py docs/library/<emne>-<dato>.md \
      reports/<emne>-<dato>.pdf --kicker "STEAMGEARS.EU · <EMNE>"
  ```

  Markdown-kilden er sandheden, PDF'en er eksporten, og **begge** skal stå i `docs/library/README.md`. Tjek siden
  visuelt før den regnes som færdig (`pypdfium2` → PNG). Rendereren klarer selv de tre ting der tidligere gik
  galt: enkelt-stjerne kursiv (`*sådan*`, også med `**fed**` indeni) skrives som «sådan», glyffer DejaVu ikke har
  oversættes (`✅`→`✓`, `❌`→`✗`) eller fjernes **med en advarselslinje** i stedet for i stilhed, og kodelinjer
  ombrydes inden for den grå boks. Et sidebrud midt i et afsnit flytter resten korrekt med over — det gjorde det
  ikke før 3/11, hvor en side fyldt til bunden kunne blive til 20 næsten tomme sider. Værnet `PDF-renderer` i
  [`tools/natlige-vaern.sh`](tools/natlige-vaern.sh) renderer tre dokumenter og fejler på sideantal, glyf-advarsler
  og tilbageværende stjerner.

## 6. Agent-kørsel og værktøjs-gaten

Platformen har en **instruktions-gate**: hvis en turns **første værktøjs-batch** ikke indeholder en læsning af
projektinstruktionerne, afvises hele batchen med _»The workspace is ready, og dette kald blev ikke kørt«_ og
en henvisning til denne fil. Gaten ligger i platformen — den findes **ikke** i repoet (ingen `.claude/`,
`.freebuff/` eller hook-scripts indeholder den besked).

Derfor:

- **Start hver tur med at læse `AGENTS.md` i samme batch som arbejdet**, fx `read_files(["AGENTS.md"])` plus de
  søgninger eller redigeringer der skal køre. Så afvises intet, og der spares en runde pr. tur.
- **Skrivninger og deres efterkontrol må ikke køre parallelt i samme batch.** Blokeres en skrivning mens en
  søskende-redigering går igennem, står repoet halvt opdateret — det er sket med et README-link til et
  dokument der endnu ikke var oprettet. Skriv først, verificér i næste kald.
- Afvises et kald alligevel: gentag det uændret i samme tur sammen med en `AGENTS.md`-læsning. Det er ikke
  nødvendigt at ændre noget i repoet for at komme videre.

## 7. Sikkerhed og data (fælles)

- **Ingen secrets i repoet.** Tokens og nøgler hører i repository-secrets, i `.env` (gitignored) eller i en
  secret-store — aldrig i kode, commits, logs eller eksempler.
- Valider alt input og escape alt output. Brug mindst mulig privilegium for den kode, der læser eller
  skriver data.
- **WordPress:** brug altid `check_ajax_referer()` / `wp_verify_nonce()`, `current_user_can()` med den
  rette capability, `sanitize_text_field()` og slægtninge på input samt `esc_html()` / `esc_attr()` /
  `esc_url()` på output.
- **Database:** parameteriserede forespørgsler — `$wpdb->prepare()` ved custom tabeller og `dbDelta()`
  ved aktivering. Aldrig strengsammensætning med værdier i.

## 8. PHP og WordPress-kode (fælles)

- PHP 8.2+ kompatibel, objektorienteret eller tydeligt namespaced.
- En plugin-hovedfil skal have en gyldig WordPress Plugin Header og starte med
  `if ( ! defined( 'ABSPATH' ) ) exit;`.
- Aktivering/deaktivering rydder op efter sig: tabeller, options, transients og cron.
- Genererer koden frontend-indhold, skal den understøtte gyldig JSON-LD efter Schema.org og enqueue
  scripts/styles **kun** på de sider, hvor de bruges. Ingen tunge forespørgsler i frontend.

## 9. Syntaks og test før commit (fælles)

- `find . -name "*.php" -not -path "./vendor/*" -exec php -l {} +` efter hver PHP-fil du skriver — ret
  fejlen med det samme, før du går videre.
- Kør repoets egne værn før et push: `bash tools/natlige-vaern.sh` (samme kommando som den natlige kørsel
  bruger, se §4).
- Ret altid årsagen til et rødt tjek. Spring ikke et tjek over, slæk ikke på en assertion, og tilføj ikke
  en suppression for at få grønt.

## 10. Forholdet til de fælles regler

§7-§9 er de fælles regler fra Command Center-repoet, tilpasset her. Hvor de støder mod de lokale, gælder
de lokale — de er skrevet til dette repo og dets automation:

- **Push:** den fælles regel er "push kun når ejeren beder om det". Dette repo kræver det modsatte (§5: alt
  arbejde skal ende på `main` i samme tur, med den natlige kørsel som sikkerhedsnet). **§5 vinder her.**
- **Procent:** den fælles regel beder om tidsestimat før og faktisk tid efter. Dette repo kræver derudover
  det fulde `% før → % efter`-format med grundlag (§1-§3), som er strengere. **§1 vinder.**
- **Pakning:** den fælles regel om en installationsklar `.zip` gælder kun, hvis et plugin en dag skal
  afleveres som fil. WordPress-kernen ligger hos Simply, og ændringer på sitet sker over MCP (§5).
