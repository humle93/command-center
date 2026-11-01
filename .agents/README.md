# Agenter i `.agents/`

Freebuff/Codebuff læser agent-filer direkte i `.agents/` (filnavn = agent-id + `.ts`), så de ligger
bevidst **fladt** her i stedet for i undermapper. Grupperingen sker via id-prefix og tabellen nedenfor.

| Gruppe | Repo / system | Agenter | Formål |
|---|---|---|---|
| 1. App | `humle93/command-center` (dette repo) | `command-center-reviewer`, `cc-verifier` | Review mod repoets regler og kontrakter; verificér tests, ruter og installer-paritet før commit |
| 2. Integration | `steamgears-autopilot` (WordPress-plugin, ≥ 7.5) | `wp-bridge-auditor` | Audit af broen: endpoints, payload-felter, Application Password, idempotens |
| 3. Indhold | den overvågede side (`TRACK_DOMAIN`, fx steamgears.eu) | `site-seo-auditor` | Striking distance, decay, tynde sider, content gap, kvalitetsgate — ud fra appens egne data |

## Sådan bruges de

- **Review før commit:** `command-center-reviewer` med `scope` = den ændrede fil/område.
- **Verificér før push:** `cc-verifier` (sæt `params.quick=true` for kun enhedstest + paritet).
- **Plugin-kontrakt:** `wp-bridge-auditor` med `area` = `push`/`autopilot`/`social`.
- **Indholdsanalyse:** `site-seo-auditor` med `focus` = `striking`/`decay`/`thin`/`gap`.

## Regler for agenterne

De er **read-only** med vilje: de rapporterer fund med `fil:linje` og den mindste rettelse, men retter
ikke selv. Undtagelsen er `cc-verifier`, der må køre kommandoer — den skriver stadig ikke filer.

De er udviklerværktøj: de indgår ikke i `install.sh`, og self-update henter dem ikke.

## Kendt usikkerhed

Gruppe 2 og 3 er navngivet efter det koden faktisk refererer til (`steamgears-autopilot`, `TRACK_DOMAIN`).
Hvis de rigtige repo-navne er anderledes, er det kun beskrivelserne i de to agenters `systemPrompt`,
der skal rettes — id'er og filnavne skal blive, fordi de er referencer fra `spawn_agents`.
