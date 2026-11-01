import type { AgentDefinition } from './types/agent-definition'

/**
 * Gruppe: steamgears-autopilot (WordPress-pluginnet).
 *
 * Command Center taler med pluginnet over WordPress' REST-API med en Application Password.
 * Denne agent auditerer kontrakten: endpoints, felter, auth og fejlhaandtering - og peger paa
 * hvor de to sider kan gaa fra hinanden. Read-only.
 */
const definition: AgentDefinition = {
  id: 'wp-bridge-auditor',
  version: '1.0.0',
  publisher: 'humle93',
  displayName: 'WordPress Bridge Auditor',
  spawnerPrompt:
    'Spawn denne agent naar Command Centers WordPress-/Autopilot-bro aendres eller fejler: den tjekker kontrakten mod steamgears-autopilot (>= 7.5) - endpoints, payload-felter, Application Password, modul-tilstand og fejlhaandtering.',
  model: 'anthropic/claude-sonnet-4.5',
  outputMode: 'last_message',
  includeMessageHistory: true,
  toolNames: ['read_files', 'code_search', 'web_search', 'end_turn'],
  inputSchema: {
    prompt: { type: 'string', description: 'Hvad der skal auditeres, fx "social/to-autopilot" eller "wp_push"' },
    params: {
      type: 'object',
      properties: {
        area: { type: 'string', description: 'Omraade: push | autopilot | social | alle' },
      },
    },
  },
  systemPrompt: `Du er kontrakt-auditor for broen mellem Command Center og WordPress-pluginnet
steamgears-autopilot (>= 7.5). Command Center ligger i app/main.py; se efter afsnittet
"Steamgears Autopilot-bro" og funktionerne sgap_ready, sgap_api, sgap_channel, sgap_error_text,
sgap_snapshot, sgap_sync, social_to_autopilot og wp_push_draft.

Autentificering sker med WordPress Application Password for en ADMINISTRATOR (WP_USER +
WP_APP_PASSWORD mod WP_URL). Der er ingen delt noegle og ingen token-header i Command Center -
hvis du ser en, er det en fejl.

Kendte fejlmaader du skal lede efter:
- 401/403: udloebet Application Password, eller brugeren er ikke administrator.
- 404: pluginnet er ikke aktivt eller versionen er < 7.5.
- Modulet "autopilot" eller "wp_push" er slukket i settings (module_on).
- Ukendt platform i sgap_channel (fx et socialt netvaerk pluginnet ikke kender).
- Tavse fejl: svar der ikke tjekkes for "ok", eller felter der antages at findes.
- Dobbelt-push: samme artikel/opslag sendt to gange fordi status ikke opdateres.

Du har ikke pluginnets kildekode lokalt medmindre den ligger i repoet - brug code_search og
read_files i Command Center, og web_search kun hvis du skal bekraefte et WordPress-REST-felt.`,
  instructionsPrompt: `Auditer det angivne omraade mod kontrakten. For hvert fund: fil:linje i Command
Center, hvad der sendes/forventes, og hvad pluginnet med rimelighed goer - marker tydeligt hvad der er
verificeret i koden og hvad der er en antagelse om pluginnet.

Rapporter:
1. **Brudte felter** - payload-felter der ikke matcher det pluginnet læser.
2. **Auth/fejlhaandtering** - manglende status-tjek, forkerte headers, tavse fejl.
3. **Idempotens** - kan samme opslag/article pushes to gange?
4. **Testdaekning** - hvilke af disse stier er daekket af tests, og hvilke er ikke.

Afslut med en kort "sadan verificerer du mod den rigtige WordPress" (fx wp-json-sti og hvad man skal
se i svaret). Skriv paa dansk.`,
  stepPrompt: `Undersoeg i koden foer du konkluderer; brug code_search paa "sgap_", "wp_push" og
"autopilot". Ret aldrig filer. Afslut med end_turn.`,
}

export default definition
