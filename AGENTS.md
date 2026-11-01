# Agent-instruktioner for Command Center

Dette repo arbejdes på af flere agenter (Claude, Codebuff m.fl.). **Læs [`CLAUDE.md`](CLAUDE.md) først** —
den indeholder status, hvad der er ændret, konventioner og roadmap.

## Faste regler

1. **Dokumentation er en del af opgaven.** Hver ændring opdaterer `README.md` og de relevante filer i
   `docs/` i **samme commit**:
   - ny eller ændret funktion → `README.md` (funktionsliste/nyheder) + `docs/Command_Center_Bruger_og_Systemmanual.md`
   - ændret arkitektur, job, rute, tabel eller sikkerhedsmodel → `docs/Command_Center_Dokumentation.md`
   - ny eller flyttet prioritet → `docs/ROADMAP.md`
   - status/handoff → `CLAUDE.md`
   CI (`.github/workflows/ci.yml`) fejler, hvis `app/`, `scripts/`, `deploy/`, `requirements.txt`,
   `run.sh`, `run.bat`, `Dockerfile` eller `docker-compose.yml` ændres uden at README/docs også er rørt.
   Brug `[skip docs]` i commit-beskeden til rene undtagelser (fx formatering) `install.sh` er undtaget,
   fordi den genereres fra kilderne og allerede tjekkes af paritetstrinnet.
2. **Ret aldrig `install.sh` direkte.** Den indeholder kopier af projektets filer (17 heredocs), og CI
   tjekker paritet. Ret kilderne og regenerér installeren bagefter.
3. **Test før commit:** `python3 tests/test_v8_features.py` og `bash tests/ci_check.sh` skal begge
   slutte med `ALL PASS`. `tests/check_paths.py` fanger knapper/links uden rute.
4. **Ingen secrets i repoet.** Nøgler hører i `.env` (gitignored) eller miljøvariabler.
5. **Dansk UI og dansk dokumentation.** Kodekommentarer og commits må gerne være korte og tekniske.
6. **Push kun når brugeren beder om det**, og vent på at GitHub Actions er grøn på commiten.
7. **Tidsestimater:** skriv et estimat (fx "~10 min") før arbejdet starter, og det faktiske tidsforbrug til sidst. Skrider estimatet, sig det med det samme i stedet for at tie.
