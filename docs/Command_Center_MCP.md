# Command Center — MCP-adgang (research)

**Status:** research, ikke implementeret · **Dato:** 3. november 2026 · **Gælder:** v7.15.x

Formålet er at lade en MCP-klient (Claude, Codebuff, en editor) læse og senere styre Command Center
direkte — uden at nogen kopierer tal ud af dashboardet. Notatet opsummerer protokollen som den ser ud
nu, hvad der passer til denne app (FastAPI + SQLite i én proces bag nginx), og hvad det kræver.

## 1. Protokollen nu: 2026-07-28

- Nyeste endelige spec er **`2026-07-28`** (forrige: `2025-11-25`). Den er **stateless**: `initialize`-
  håndtrykket og `Mcp-Session-Id` er væk, og hver request beskriver sig selv i `_meta`
  (`io.modelcontextprotocol/protocolVersion`, `clientCapabilities`, `clientInfo`). Der findes en
  valgfri `server/discover`.
- Der er **to transportformer**: `stdio` (klienten starter processen — passer ikke til en server, der
  allerede kører) og **Streamable HTTP** (ét endpoint, `POST` pr. JSON-RPC-besked, svar som
  `application/json` eller request-scoped SSE).
- **HTTP+SSE fra 2024-11-05 er deprecated** (formelt nedgraderet med 12 måneders afvikling). Nye
  servere skal bruge Streamable HTTP.
- Krav til headers på `2026-07-28`: `MCP-Protocol-Version` (skal matche `_meta`, ellers `400`
  `HeaderMismatch`), `Mcp-Method` på alle requests og `Mcp-Name` på `tools/call`, `resources/read` og
  `prompts/get`. De to sidste kan nginx route på uden at læse body.
- Servere **bør** sende `X-Accel-Buffering: no` på SSE-svar, netop fordi omvendte proxies (spec'en
  nævner nginx) ellers buffer streamen.

## 2. Anbefalet arkitektur for Command Center

MCP-endpointet skal ligge i **samme proces** som appen — `/mcp` ved siden af dashboardet. Alternativet
(en separat MCP-proces, der taler med appen over HTTP) giver kun ekstra hop og endnu en ting at drifte.

Der findes to Python-implementeringer, og man skal ikke blande deres dokumentation:

| | Officiel SDK | FastMCP (Prefect) |
| --- | --- | --- |
| Pakke | `mcp` (2.3.0, okt. 2026) | `fastmcp` (4.1.6, nov. 2026) |
| Serverklasse | `from mcp.server import MCPServer` (tidligere `FastMCP`, omdøbt i v2) | `from fastmcp import FastMCP` |
| ASGI-app | `mcp.streamable_http_app()` → Starlette-app med ruten `/mcp` | `mcp.http_app(path="/mcp")` |
| Ind i FastAPI | `Mount("/", app=...)` | `FastAPI(lifespan=mcp_app.lifespan)` + `app.mount(...)` |

**Anbefaling:** den officielle SDK (`mcp` 2.x) — færrest afhængigheder, og den følger spec'en direkte.
FastMCP er først interessant, hvis man vil generere værktøjer automatisk fra OpenAPI (`FastMCP.from_fastapi`),
men den vej spejler hele API'et til modellen, hvilket er præcis det, man ikke vil have.

Tre faldgruber, som koster timer, hvis man ikke kender dem:

1. **Lifespan kører ikke for et mounted sub-app.** Værts-appen skal selv ind i
   `mcp.session_manager.run()` (gerne i en `AsyncExitStack`), ellers fejler første kald med
   `RuntimeError: Task group is not initialized`.
2. **Transport-sikkerhed afviser alt andet end localhost** med `421 Misdirected Request`, indtil man
   angiver `TransportSecuritySettings(allowed_hosts=["cc.eksempel.dk", "cc.eksempel.dk:*"], allowed_origins=[...])`.
   Det er den klassiske "virker lokalt, fejler i produktion".
3. **nginx buffer SSE.** Sæt `X-Accel-Buffering: no` server-side og `proxy_buffering off; proxy_cache off;`
   i location-blokken, og hæv `proxy_read_timeout`/`proxy_send_timeout` (standard 60 s dræber en lang
   stream). Prefixet i `proxy_pass` og den offentlige URL skal matche, når OAuth senere kommer ind.

Til `deploy/nginx-command-center.conf` betyder det en ekstra `location = /mcp { ... }` med
`proxy_buffering off`, `proxy_read_timeout 300s` (samme som resten) og `client_max_body_size 1m`.

## 3. Adgangskontrol: personlige nøgler først, OAuth senere

Spec'ens vej er **OAuth 2.1**: MCP-serveren er resource server, skal udstille Protected Resource
Metadata (RFC 9728) i `/.well-known/oauth-protected-resource`, svare `401` med
`WWW-Authenticate: Bearer resource_metadata="…"`, og klienten skal sende `resource` (RFC 8707) og
bruge PKCE. Dynamisk klientregistrering er på vej ud til fordel for Client ID Metadata Documents.

Det er den rigtige løsning, når **fremmede** klienter skal kunne koble sig på. For dette projekt er
det overkill i første fase, og det bryder med husreglen om **ingen global token**: adgang skal kunne
tilbagekaldes pr. klient.

**Fase 1 (anbefalet): personlige API-nøgler.**

- Tabel `api_clients`: `id`, `name` (fx "Claude Desktop"), `key_hash` (sha256, som `sessions`),
  `scopes` (`read`, `write`), `created_at`, `last_used_at`, `revoked_at`.
- Nøglen vises **én gang** ved oprettelse i fanen **Brugere** (eller en ny **Adgang**-fane) og gemmes
  kun hashet. `Authorization: Bearer <nøgle>` — aldrig i query string.
- `401` med `WWW-Authenticate: Bearer realm="command-center"`; forkerte nøgler tælles i samme
  rate-limit som login.
- **Origin/Host-validering** er normative krav i spec'en (DNS-rebinding): ugyldig `Origin` → `403`,
  ukendt `Host` → `421`. Enten via SDK'ens `TransportSecuritySettings` eller i nginx.
- Hver skrivende handling logges som alarm/hændelse, så man kan se hvad en nøgle har gjort.

**Fase 3 (hvis eksterne klienter kræver det):** OAuth 2.1 + PRM oven på de samme scopes. Nøglerne
bliver så en "personal access token"-genvej ved siden af.

## 4. Hvilke data som værktøjer

Spec'ens arbejdsdeling: **værktøjer** er modelstyrede (modellen vælger dem), **resources** er
applikationsstyrede (værten vælger kontekst), **prompts** er brugerstyrede skabeloner.

| Fase | Værktøj | Genbruger |
| --- | --- | --- |
| 1 | `health` | `GET /health` (version, DB, disk, budget, åbne alarmer) |
| 1 | `crawl_summary` | seneste `crawl_runs` + score pr. domæne |
| 1 | `keywords` (med `limit`, `min_volume`) | keywords-tabellen |
| 1 | `monitors` | pris-/positions-monitorer |
| 1 | `alarms_open` | `alarms` hvor `resolved_at IS NULL` |
| 1 | `notes` | `notes` |
| 1 | `history(domain_id)` | samme data som `/api/history/{domain_id}` |
| 2 | `start_crawl`, `add_monitor`, `resolve_alarm`, `add_note` | eksisterende POST-ruter + `TASK_ESTIMATES` |
| 3 | `social_draft` (kladde til Autopilot) | `/social/to-autopilot` med `social_claim()` |

- Store datasæt og snapshots passer bedre som **resources** (`seo://site/{domain}/crawl-summary`) med
  `ttlMs`, så klienten kan cache. Værktøjer bruges til filtrering og aggregering.
- Skrivende værktøjer kræver scope `write` og skal svare med den samme kvittering som UI'et
  (fremdrift/procent), så en agent ikke tror et crawl er færdigt efter 2 sekunder.
- Ressourcer og værktøjer skal have deterministisk rækkefølge i listerne, så prompt-cachen ikke
  invalideres ved hver forespørgsel.

## 5. Implementeringsplan

| Fase | Indhold | Estimat |
| --- | --- | --- |
| 1 | `api_clients` + nøgle-UI + `Authorization`-guard + `Origin`/`Host`-validering + 7 read-only værktøjer + tests + docs | ~4-6 timer |
| 2 | Skrivende værktøjer med scopes, audit pr. nøgle, rate-limit, `TASK_ESTIMATES`-kvitteringer | ~3-4 timer |
| 3 | OAuth 2.1 + PRM (`/.well-known/oauth-protected-resource`), valgfri `server.json` til registry | ~1-2 dage |

Fase 1 kan leveres uden at røre dashboardets øvrige funktioner: alt er nye ruter og én ny tabel.

## 6. Kilder

- Spec, transports: <https://modelcontextprotocol.io/specification/2026-07-28/basic/transports>
- Streamable HTTP: <https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http>
- Ændringslog: <https://modelcontextprotocol.io/specification/2026-07-28/changelog>
- Authorization (OAuth 2.1, RFC 9728, RFC 8707): <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization>
- Værktøjer/ressourcer/prompts: <https://modelcontextprotocol.io/specification/2026-07-28/server/tools> ·
  <https://modelcontextprotocol.io/specification/2026-07-28/server/resources> ·
  <https://modelcontextprotocol.io/specification/2026-07-28/server/prompts>
- Officiel Python-SDK (ASGI-mount, `TransportSecuritySettings`): <https://py.sdk.modelcontextprotocol.io/run/asgi/>
- FastMCP + FastAPI (alternativet): <https://gofastmcp.com/integrations/fastapi> · <https://gofastmcp.com/deployment/http>
- Registry (preview, `server.json`, reverse-DNS-navne): <https://modelcontextprotocol.io/registry/about>
