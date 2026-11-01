import type { AgentDefinition } from './types/agent-definition'

/**
 * Gruppe: site/content (den overvaagede domaene, TRACK_DOMAIN).
 *
 * Agenten laeser Command Centers egne data (SQLite) og de SEO-funktioner der allerede findes,
 * og omsaetter dem til en prioriteret handlingsliste. Read-only: ingen skrivninger i DB eller filer.
 */
const definition: AgentDefinition = {
  id: 'site-seo-auditor',
  version: '1.0.0',
  publisher: 'humle93',
  displayName: 'Site SEO Auditor',
  spawnerPrompt:
    'Spawn denne agent naar den overvaagede side (TRACK_DOMAIN) skal analyseres: striking distance, indhold der falder i position, tynde sider, content gaps og kvalitetsgaten - baseret paa Command Centers egne tabeller og funktioner.',
  model: 'anthropic/claude-sonnet-4.5',
  outputMode: 'last_message',
  includeMessageHistory: true,
  toolNames: ['read_files', 'code_search', 'run_terminal_command', 'end_turn'],
  inputSchema: {
    prompt: { type: 'string', description: 'Hvad der skal analyseres, fx "striking distance" eller "hele siden"' },
    params: {
      type: 'object',
      properties: {
        focus: { type: 'string', description: 'striking | decay | thin | gap | alle' },
        limit: { type: 'number', description: 'Maks antal anbefalinger (standard 10)' },
      },
    },
  },
  systemPrompt: `Du analyserer den side Command Center overvaager (TRACK_DOMAIN, standard steamgears.eu)
ud fra appens egne data. Du skriver ikke til databasen og aendrer ingen filer.

Data du maa laese (read-only, aabn altid med mode=ro):
  sqlite3 "file:app/data/center.db?mode=ro" "SELECT ..."
eller: ./venv/bin/python -c "import sqlite3;c=sqlite3.connect('file:app/data/center.db?mode=ro',uri=True);..."

Relevante tabeller: keywords (position, target_url, checked_at), keyword_difficulty, content_gap
(stats_json: avg_words/avg_h2), seopages (score, issues, words, title, meta_len), crawl_runs,
articles (status, keyword), visibility (daglig score), ai_visibility, health_history.

Relevante funktioner i app/main.py: quality_check (kvalitetsgate), content_score, serp_gap_sync,
keyword_difficulty_sync, analyze_page (audit-regler).`,
  instructionsPrompt: `Lav en prioriteret handlingsliste for den overvaagede side:

1. **Striking distance** - keywords med position 8-20 (naesten side 1). Sortér efter position og
   svaerhedsgrad; naevn den URL der rangerer.
2. **Decay** - sider/keywords hvor positionen er blevet daarligere over tid (sammenlign nyeste
   maaling med tidligere; hvis der kun findes én maaling, sig det i stedet for at gaette).
3. **Tynde sider** - seopages med lavt ordantal eller lav score, og hvilke issues der gentager sig.
4. **Content gap** - keywords hvor SERP-gennemsnittet er laengere end vores indhold (content_gap.stats_json).
5. **Kvalitetsgaten** - artikler der blev stoppet, og hvorfor (mangler keyword, < 2 H2, for kort).

Hver anbefaling: hvad, hvorfor (med tal fra data), og den mindste konkrete aendring.
Vær eksplicit naar data mangler (fx ingen historik, ingen SERPAPI_KEY) - foreslaa da det tjek der
ville give svaret, ikke en gaettet konklusion. Skriv paa dansk, maks params.limit anbefalinger.`,
  stepPrompt: `Brug run_terminal_command til read-only SQL mod app/data/center.db, og read_files til at
se de funktioner du refererer til. Skriv aldrig i databasen, ret aldrig filer, og start ikke serveren.
Afslut med end_turn.`,
}

export default definition
