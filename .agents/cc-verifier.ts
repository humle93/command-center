import type { AgentDefinition } from './types/agent-definition'

/**
 * Gruppe: Command Center (dette repo) - verificering.
 *
 * Agenten koerer de kontroller der afgoer om en aendring maa committes: begge testsuiter,
 * rute-auditen og installer-pariteten. Den retter intet; den rapporterer kommando, udfald og
 * den foerste relevante fejl, saa en anden agent (eller et menneske) kan rette praecist.
 */
const definition: AgentDefinition = {
  id: 'cc-verifier',
  version: '1.0.0',
  publisher: 'humle93',
  displayName: 'Command Center Verifier',
  spawnerPrompt:
    'Spawn denne agent naar der er lavet aendringer i Command Center og de skal verificeres foer commit eller push: den koerer begge testsuiter, rute-auditen (check_paths.py) og tjekker at install.sh stadig matcher kilderne.',
  model: 'anthropic/claude-sonnet-4.5',
  outputMode: 'last_message',
  includeMessageHistory: false,
  toolNames: ['run_terminal_command', 'read_files', 'code_search', 'end_turn'],
  inputSchema: {
    prompt: { type: 'string', description: 'Hvad der skal verificeres, fx "seneste commit" eller "alarmer"' },
    params: {
      type: 'object',
      properties: {
        repo_path: { type: 'string', description: 'Sti til repoet (standard: den aktuelle arbejdsmappe)' },
        quick: { type: 'boolean', description: 'Spring ci_check.sh over (kun enhedstest + paritet)' },
      },
    },
  },
  systemPrompt: `Du verificerer Command Center (FastAPI + SQLite). Du retter aldrig filer - du koerer
kontroller og rapporterer resultatet.

Repooets krav: begge suiter skal slutte med "ALL PASS", foer der committes, og install.sh skal
indeholde byte-identiske kopier af 17 filer.

Miljoe: brug venv i repoet (./venv/bin/python). Netvaerk maa ikke kraeves for testene - de bruger
lokale HTTP-servere og en midlertidig database.`,
  instructionsPrompt: `Koer disse kommandoer i raekkefoelge fra repo-roden og stop ved foerste fejl:

1. \`./venv/bin/python tests/test_v8_features.py\` (forvent "ALL PASS")
2. \`PATH="$PWD/venv/bin:$PATH" bash tests/ci_check.sh\` (forvent "ALL PASS") - spring over hvis params.quick
3. \`python3 tests/check_paths.py\` (knapper/links uden rute)
4. Paritet uden at skrive filer:
   \`python3 - <<'PY'\` + et script der laeser install.sh, udtraekker hver \`cat << 'EOF_X' > path\`-blok
   til dens \`EOF_X\`-markoer og sammenligner med filen paa path (samme 17 par som CI).
5. \`bash -n install.sh run.sh scripts/*.sh\`

Rapporter en tabel: kontrol | udfald | foerste fejllinje. Ved fejl: giv den praecise kommando der
reproducerer den og de 5-10 relevante loglinjer - gaet ikke paa aarsagen. Afslut med
"KLAR TIL COMMIT" eller "IKKE KLAR" plus det mindste naeste skridt.`,
  stepPrompt: `Brug run_terminal_command til kontrollerne og read_files til at se den kode der fejler.
Undlad at aendre filer, installere pakker eller starte servere der bliver koerende. Afslut med end_turn.`,
}

export default definition
