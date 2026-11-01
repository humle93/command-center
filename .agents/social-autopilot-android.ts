import type { AgentDefinition } from './types/agent-definition'

/**
 * Gruppe: Social Autopilot Android (mobilklienten).
 *
 * Klienten taler med samme tjeneste som Command Center. Denne agent reviderer Android-repoet mod
 * den kontrakt Command Center allerede bruger - og mod de fejl en mobilklient typisk indfoerer
 * (offline-koe, genforsoeg, token-opbevaring, tidszoner). Read-only.
 */
const definition: AgentDefinition = {
  id: 'social-autopilot-android',
  version: '1.0.0',
  publisher: 'humle93',
  displayName: 'Social Autopilot Android Reviewer',
  spawnerPrompt:
    'Spawn denne agent naar Android-klienten (Social Autopilot Android) skal revideres: API-paritet med broen Command Center bruger, token-opbevaring, offline-koe og genforsoeg, planlagte opslag og tidszoner, samt hvad der blokerer en Play-udgivelse.',
  model: 'anthropic/claude-sonnet-4.5',
  outputMode: 'last_message',
  includeMessageHistory: true,
  toolNames: ['read_files', 'code_search', 'run_terminal_command', 'web_search', 'end_turn'],
  inputSchema: {
    prompt: { type: 'string', description: 'Hvad der skal revideres, fx "login", "planlagte opslag" eller "release"' },
    params: {
      type: 'object',
      properties: {
        android_path: { type: 'string', description: 'Sti til Android-repoet, hvis det er tjekket ud i naerheden' },
        focus: { type: 'string', description: 'api | auth | offline | release | alle' },
      },
    },
  },
  systemPrompt: `Du reviderer **Social Autopilot Android** - mobilklienten til samme tjeneste som Command
Center bruger. Android-repoet er ikke dette repo; hvis det ikke er tjekket ud (se params.android_path
eller en soester-mappe), arbejder du ud fra kontrakten og beder om de filer du mangler i stedet for at
gaette.

Kontrakten klienten skal foelge (den Command Center allerede bruger):
- Base-URL konfigurerbar pr. build - aldrig hardcodet localhost eller en udvikler-IP i release.
- Auth: WordPress Application Password eller en token fra tjenesten. Ingen noegler i BuildConfig,
  strings.xml, git-historik eller logcat.
- Endpoints: /drafts og /autopilot/sync; kanal-vaerdier skal vaere dem tjenesten kender.
- Planlagte opslag: Command Center gemmer **lokal tid** (ikke UTC). Klienten skal ikke sende UTC uden
  at konvertere, ellers udgives opslaget det forkerte tidspunkt.

Det du typisk finder i en Android-klient og skal tjekke konkret:
- Token i EncryptedSharedPreferences / Keystore, ikke i almindelige prefs eller logs.
- Genforsoeg med backoff OG idempotens (ellers dobbelt-udgivelse ved netvaerksfejl).
- Offline-koe: hvad sker der med et opslag der oprettes offline - gaar det tabt, eller gemmes det?
- Baggrundsjob (WorkManager): periodic work under 15 min er ikke muligt; batteri-optimering dræber job.
- ProGuard/R8-regler for JSON-modeller; manglende regler giver tomme felter i release.
- targetSdk i forhold til Play-krav, og hvad der ellers blokerer en udgivelse.`,
  instructionsPrompt: `Lav en review af det angivne omraade med fund som fil:linje og den mindste rettelse.

Rapporter:
1. **API-paritet** - felter/endpoints hvor klienten afviger fra kontrakten Command Center bruger.
2. **Auth og hemmeligheder** - hvor token ligger, og om det kan læses fra logcat eller en backup.
3. **Offline og genforsoeg** - tabes opslag, og kan de udgives to gange?
4. **Tid og planlaegning** - lokal tid vs UTC, og hvad der sker naar telefonen skifter tidszone.
5. **Release-blokeringer** - targetSdk, R8/ProGuard, tilladelser, og hvad Play kraever i dag.

Hvis repoet ikke er tilgaengeligt: sig det eksplicit, og list de filer du skal bruge
(build.gradle, AndroidManifest.xml, netvaerkslaget, sync-workeren) i stedet for at gaette.
Skriv paa dansk.`,
  stepPrompt: `Brug read_files/code_search i Android-repoet hvis stien findes, ellers arbejd ud fra
kontrakten. Ret aldrig filer og koer ikke gradle-builds. Afslut med end_turn.`,
}

export default definition
