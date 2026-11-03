# AGENTS.md — fælles regler for alle repoer

**Sådan bruges filen:** kopiér den til roden af hvert repo, så agenter (Claude, Codebuff m.fl.) møder
de samme regler overalt. Afsnit 1-7 gælder alle sprog og projekter, afsnit 8 har en profil pr.
projekttype, og afsnit 9 er det repo-specifikke, der kun gælder Command Center. Alt andet
repo-specifikt hører i `CLAUDE.md` og `README.md` — ikke her.

## 1. Arbejdsform: roadmap før kode, og så helt i mål

- Start **aldrig** på koden før du har præsenteret et roadmap med:
  1. komplet filstruktur for det, der skal bygges eller ændres,
  2. estimeret tidsforbrug og procentvis opdeling (0 % → 100 %).
- Når roadmappet er godkendt: stop ikke undervejs. Skriv samtlige filer færdige — ingen placeholders,
  ingen `// TODO`, ingen "kommer senere".
- Rapportér status ved hvert skridt, fx `[50 % – REST API og admin-UI færdigt]`.
- Start hver opgave med et tidsestimat (fx "~25 min"), også når opgaven virker lille, og afslut med
  det **faktiske** tidsforbrug. Skrider estimatet, sig det straks i stedet for at tie.
- Procenter skal komme fra rigtige data, ikke fra et fastlåst skøn.
- Rapportér kun det, der faktisk er kørt: hvilke tests, CI-status, og hvad der ikke kunne verificeres
  i det miljø du arbejder i.

## 2. Dokumentation er en del af opgaven

- Hver ændring opdaterer dokumentationen i **samme commit** som koden:
  - ny eller ændret funktion → `README.md` + brugervejledning/manual,
  - ændret arkitektur, job, rute, tabel eller sikkerhedsmodel → arkitektur-/systemdokumentet,
  - ny eller flyttet prioritet → roadmap-filen,
  - status og handoff → `CLAUDE.md`.
- Findes der en CI-regel om det (fx "docs skal røres sammen med koden"), så overhold den i stedet for
  at bruge en `[skip docs]`-genvej.
- Genereret indhold (installationsscripts, samlede filer, minificerede bundles) rettes aldrig direkte:
  ret kilden og kør generatoren. Kan generatoren ikke køres, så sig det — gæt ikke.

## 3. Test og syntaks før commit

- **PHP:** `find . -name "*.php" -not -path "./vendor/*" -exec php -l {} +` efter hver fil du skriver.
  Melder `php -l` fejl, retter du fejlen med det samme, før du går videre.
- **Python:** kør projektets testsuite(r). De skal slutte grønt.
- **JS/TS:** `npm test` og `npm run build` (eller tilsvarende) skal gå igennem.
- Ret altid årsagen til et fejlende tjek. Spring ikke et tjek over, slæk ikke på en assertion, og
  tilføj ikke en type-/lint-suppression for at få grønt — hvis det er nødvendigt for den ønskede
  adfærd, skal du forklare hvorfor og verificere adfærden.
- Kør kun de tjek, der dækker ændringen. Er der rettet en fejl, køres kun det berørte tjek igen.

## 4. Sikkerhed

- **Ingen secrets i repoet.** Nøgler, tokens og adgangskoder hører i `.env` (gitignored), i
  miljøvariabler eller i en secret-store — aldrig i kode, commits, logs eller eksempler.
- Valider alt input og escape alt output. Brug mindst mulig privilegium for den kode, der læser eller
  skriver data.
- **WordPress:** brug altid `check_ajax_referer()` / `wp_verify_nonce()`,
  `current_user_can( 'manage_options' )` (eller den rette capability), `sanitize_text_field()` og
  slægtninge på input samt `esc_html()` / `esc_attr()` / `esc_url()` på output.
- **Database:** `$wpdb->prepare()` ved custom tabeller (og `dbDelta` ved aktivering) eller
  Options/Transients API. Andre stacks: parameteriserede forespørgsler, aldrig strengsammensætning.

## 5. Sprog

- UI-tekster og dokumentation er på **dansk**. Kodekommentarer og commit-beskeder må gerne være korte
  og tekniske.
- Ingen rester på fremmedsprog, ingen "lorem ipsum", ingen halvfærdige sætninger i UI'et.

## 6. Git

- **Push kun når brugeren beder om det**, og vent derefter på at CI er grøn på commiten — rapportér
  den faktiske status, ikke en formodning.
- Små, forklarende commits med en besked om *hvorfor* ændringen er lavet.
- Commit aldrig `.venv`, `node_modules`, `vendor`, `app/data`, byggede artefakter eller `.env`.
- Arbejd i din egen worktree/branch; omskriv ikke andres uafsluttede arbejde.

## 7. Levering og pakning

- Et WordPress-plugin pakkes som sidste trin (100 %) i en installationsklar `.zip` i rodmappen, så den
  kan uploades direkte under *Plugins → Tilføj nyt*. Udelad `.git`, `AGENTS.md` og `node_modules`
  (og `vendor`, hvis den ikke er påkrævet ved kørsel).
- Kontrollér før aflevering at zip-filen indeholder hovedfilen med gyldig plugin-header, alle
  inkluderede filer og ingen udviklingsfiler.

## 8. Profiler pr. projekttype

### 8.1 WordPress og WooCommerce (PHP)

- PHP 8.2+ kompatibel, objektorienteret struktur (OOP) eller tydeligt namespacede klasser.
- Hovedfilen skal indeholde en gyldig WordPress Plugin Header og starte med:
  `if ( ! defined( 'ABSPATH' ) ) exit;`
- Aktivering/deaktivering skal rydde op efter sig (tabeller, options, transients, cron).
- **SEO / AEO / GEO:** genererer pluginnet frontend-indhold eller produktsider, skal det understøtte
  gyldig JSON-LD efter Schema.org og indlæses hurtigt — enqueue scripts/styles kun på de sider, hvor
  de bruges, og undgå tunge forespørgsler i frontend.

### 8.2 Python / FastAPI (Command Center m.fl.)

- FastAPI + SQLite i én proces, server-rendered dashboard, APScheduler-jobs.
- Kør `.venv/bin/python` fra projektets venv; læg ikke afhængigheder i systemets Python.
- Tunge handlinger skal have et ærligt estimat og vise fremdrift fra rigtige data.

### 8.3 Frontend (JS/TS)

- Byg og test lokalt før commit; hold UI-teksterne danske og tilgængelige (labels, fokus, kontrast).
- Ingen CDN-afhængigheder i kritiske stier, hvis projektet kan køre offline.

## 9. Command Center (dette repo)

Dette repo har ud over ovenstående otte faste regler. `CLAUDE.md` er status- og handoff-notatet og
skal læses først.

1. **Dokumentation i samme commit.** Ny funktion → `README.md` +
   `docs/Command_Center_Bruger_og_Systemmanual.md`; ændret arkitektur/job/rute/tabel/sikkerhedsmodel →
   `docs/Command_Center_Dokumentation.md`; prioritet → `docs/ROADMAP.md`; status → `CLAUDE.md`.
   CI fejler, hvis `app/`, `scripts/`, `deploy/`, `requirements.txt`, `run.sh`, `run.bat`, `Dockerfile`
   eller `docker-compose.yml` ændres uden at README/docs også er rørt (`[skip docs]` til rene undtagelser).
2. **Ret aldrig `install.sh` direkte.** Den indeholder kopier af projektets filer (17 heredocs), og CI
   tjekker paritet. Ret kilderne og regenerér installeren bagefter.
3. **Test før commit:** `python3 tests/test_v8_features.py` og `bash tests/ci_check.sh` skal begge
   slutte med `ALL PASS`. `python3 tests/check_paths.py` fanger knapper/links uden rute.
4. **Ingen secrets i repoet.** `GITHUB_TOKEN`, `SERPAPI_KEY`, `AIMLAPI_KEY`, `WP_APP_PASSWORD`,
   `TELEGRAM_*` og SMTP-oplysninger hører i `.env`.
5. **Dansk UI og dansk dokumentation.**
6. **Push kun når brugeren beder om det**, og vent på at GitHub Actions er grøn på commiten.
7. **Tidsestimat, fremgang i procent og faktisk tid** — også ved små opgaver.
8. **Fremdriftskortet bliver.** `#cc-task` i dashboardet og `TASK_ESTIMATES` er en fast del af UI'et.
   Nye tunge handlinger (> ~5 s) skal have en post i `TASK_ESTIMATES`, og procenterne skal komme fra
   rigtige data (`crawl_progress()`), ikke fra et fastlåst skøn.
