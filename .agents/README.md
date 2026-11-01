# Agenter i `.agents/`

De tre repos hører sammen: **Command Center** er dashboards/klienten, **Social Autopilot** er tjenesten
der udgiver opslag, og **Social Autopilot Android** er mobilklienten til samme tjeneste.
Agentfilerne ligger bevidst **fladt** i `.agents/`, fordi Freebuff læser `<id>.ts` direkte her;
grupperingen sker via id-prefix og tabellen nedenfor.

| # | Repo | Agenter | Formål |
|---|---|---|---|
| 1 | **Command Center** (dette repo) | `command-center-reviewer`<br>`cc-verifier`<br>`site-seo-auditor` | Review mod repoets regler og kontrakter · verificér tests, ruter og installer-paritet · analysér den overvågede sides SEO ud fra appens egen DB |
| 2 | **Social Autopilot** (tjenesten) | `social-autopilot-auditor` | Kontrakten `/drafts` + `/autopilot/sync`, Application Password, kanal-mapping, `socialqueue`, idempotens og tidszoner |
| 3 | **Social Autopilot Android** (mobilklienten) | `social-autopilot-android` | API-paritet med gruppe 2, token i Keystore, offline-kø og genforsøg, planlagte opslag, release-blokeringer |

## Sådan bruges de

- **Før commit:** `command-center-reviewer` med `scope` = det ændrede område.
- **Før push:** `cc-verifier` (`params.quick=true` = kun enhedstest + paritet).
- **Broen til tjenesten:** `social-autopilot-auditor` med `area` = `push`/`sync`/`kanaler`.
- **Mobilklienten:** `social-autopilot-android` med `focus` = `api`/`auth`/`offline`/`release`.
- **Indhold:** `site-seo-auditor` med `focus` = `striking`/`decay`/`thin`/`gap`.

## Regler for agenterne

De er **read-only** med vilje: de rapporterer fund med `fil:linje` og den mindste rettelse, men retter
ikke selv. Undtagelsen er `cc-verifier`, der må køre kommandoer — den skriver stadig ikke filer.

De er udviklerværktøj: de indgår ikke i `install.sh`, og self-update henter dem ikke.

## Kendt usikkerhed

Kun Command Center ligger i denne arbejdsmappe. Gruppe 2 og 3 arbejder derfor ud fra den kontrakt
Command Center allerede implementerer (`/drafts`, `/autopilot/sync`, `socialqueue`, lokal tid).
Er repoet for gruppe 3 tjekket ud ved siden af, kan `params.android_path` pege på det; ellers beder
agenten om de filer den mangler i stedet for at gætte.
