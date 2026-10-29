# ⚡ Command Center v8.0 — Reliable Autopilot Edition

Selvhelende driftscockpit, SEO-motor og indholds-autopilot (FastAPI + SQLite WAL-mode) til **Steamgears.eu**.

## Nyheder i v8.0
- **Persistent Job-kø (`app/jobs.py`):** Trådsikker SQLite WAL-mode med zombie-reset.
- **Off-site Backup (`app/backup.py`):** Hot-backup med 14-dages retention.
- **API-Budgetstyring (`app/budgets.py`):** Hard-stop ved API-fejl eller budgetloft.
- **WordPress Bridge (`app/wp_bridge.py`):** REST API helbredstjek mod Steamgears.eu.
- **Artikel Kvalitetsgate (`app/quality_gate.py`):** Automatisk SEO/AEO-validering før publicering.
