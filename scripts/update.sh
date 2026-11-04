#!/usr/bin/env bash
# update.sh - opdaterer Command Center fra GitHub: tjek -> filer (med DB-backup) -> requirements ->
# genstart.
#
# Brug:
#   bash scripts/update.sh              # opdater + genstart, vent til /health svarer
#   bash scripts/update.sh --no-restart # opdater, men genstart selv bagefter
#   bash scripts/update.sh --check      # kun tjek, skriv intet
#
# Viser foerst hvilken version der koerer (/health) ved siden af filernes, og hvor man logger ind
# (CC_PUBLIC_URL via nginx). Koerer appens funktioner direkte i venv'en - ingen token eller login.
# Kraever: venv (./venv) og GITHUB_TOKEN i .env til tjekket.
# Sidst aendret: 4. november 2026
set -u
cd "$(dirname "$0")/.."

if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Hjaelpen er header-kommentarerne efter shebang: retter man dem, retter man hjaelpen.
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

MODE="apply"
case "${1:-}" in
    --no-restart) MODE="apply-no-restart" ;;
    --check) MODE="check" ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "Ukendt argument: $1 (brug --check, --no-restart eller -h)" >&2; exit 64 ;;
esac

PY="./venv/bin/python"
if [ ! -x "$PY" ]; then
    echo "❌ venv mangler ($PY) - start appen en gang med ./run.sh foerst." >&2
    exit 2
fi

HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
case "$HOST" in
    0.0.0.0|::|"") PROBE=127.0.0.1 ;;
    *) PROBE="$HOST" ;;
esac
BASE="http://$PROBE:$PORT"

# ---------- Version og login-adresse ----------
# APP_VERSION i app/main.py er FILERNE; /health svarer med den proces der faktisk koerer. Er de to
# forskellige, er appen ikke genstartet efter en opdatering - og det er praecis den forskel scriptet
# her skal goere synlig, saa man ikke tror man koerer den nye version naar man ikke goer.
login_url() { local b="${CC_PUBLIC_URL:-$BASE}"; echo "${b%/}/login"; }
file_version() { sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' app/main.py 2>/dev/null | head -1; }
running_version() {
    local h
    h="$(curl -sf --max-time 3 "$BASE/health" 2>/dev/null || true)"
    [ -n "$h" ] || return 0
    printf '%s' "$h" | "$PY" -c 'import json,sys;print(json.load(sys.stdin).get("version",""))' 2>/dev/null || true
}
show_versions() {
    local run file
    run="$(running_version)"
    file="$(file_version)"
    echo "Command Center"
    if [ -n "$run" ]; then echo "   kører nu:    v$run"; else echo "   kører nu:    ukendt - appen svarer ikke på $BASE/health"; fi
    if [ -n "$file" ]; then echo "   filer:       v$file"; else echo "   filer:       ukendt"; fi
    if [ -n "$run" ] && [ -n "$file" ] && [ "$run" != "$file" ]; then
        echo "   forskel:     filerne er nyere end processen - genstart mangler (bash scripts/restart.sh)"
    fi
    if [ -n "${CC_PUBLIC_URL:-}" ]; then
        echo "   login:       $(login_url)   (via nginx)"
    else
        echo "   login:       $(login_url)   (lokal adresse - sæt CC_PUBLIC_URL i .env for den offentlige)"
    fi
    echo
}
show_versions

# Et felt ud af JSON paa stdin ("None" -> tom)
field() { "$PY" -c 'import json,sys;d=json.load(sys.stdin);v=d.get(sys.argv[1]);print("" if v is None else v)' "$1"; }
count() { "$PY" -c 'import json,sys;print(len(json.load(sys.stdin).get(sys.argv[1]) or []))' "$1"; }
req_line() {
    "$PY" -c 'import json,sys;d=json.load(sys.stdin).get("requirements_install") or {};print(("OK" if d.get("ok") else "FEJL")+": "+(d.get("output") or "")[:200])'
}

echo "→ Tjekker GitHub..."
CHECK="$("$PY" -c 'import json;from app import main;print(json.dumps(main.update_check_sync(), ensure_ascii=False))')"
[ -n "$CHECK" ] || { echo "❌ Tomt svar fra tjekket." >&2; exit 3; }

echo "   installeret: $(printf '%s' "$CHECK" | field current)"
echo "   nyeste:      $(printf '%s' "$CHECK" | field latest)  $(printf '%s' "$CHECK" | field message)"
if [ "$(printf '%s' "$CHECK" | field ok)" != "True" ]; then
    echo "❌ Tjekket fejlede: $(printf '%s' "$CHECK" | field error)" >&2
    exit 4
fi
if [ "$(printf '%s' "$CHECK" | field behind)" != "True" ]; then
    echo "✅ Du kører nyeste version."
    exit 0
fi
if [ "$MODE" = "check" ]; then
    echo "⬆️  Ny version tilgængelig."
    exit 0
fi

echo "→ Henter og skriver filer (DB-backup foerst, requirements installeres hvis de er aendret)..."
RESULT="$("$PY" -c 'import json;from app import main;print(json.dumps(main.update_apply_sync(), ensure_ascii=False))')"
[ -n "$RESULT" ] || { echo "❌ Tomt svar fra opdateringen." >&2; exit 5; }

echo "   ok:           $(printf '%s' "$RESULT" | field ok)"
echo "   filer:        $(printf '%s' "$RESULT" | count files)"
echo "   requirements: $(printf '%s' "$RESULT" | req_line)"
if [ "$(printf '%s' "$RESULT" | field ok)" != "True" ]; then
    echo "❌ Opdateringen fejlede: $(printf '%s' "$RESULT" | field error)" >&2
    exit 5
fi

if [ "$MODE" = "apply-no-restart" ]; then
    echo "✅ Filer opdateret til v$(file_version) (processen kører stadig den gamle). Genstart selv: bash scripts/restart.sh"
    exit 0
fi

echo "→ Genstarter..."
bash scripts/restart.sh || { echo "❌ Genstart fejlede - se logs." >&2; exit 6; }
echo "→ Venter paa at appen svarer igen..."
for _ in $(seq 1 60); do
    sleep 1
    if curl -sf -o /dev/null --max-time 3 "$BASE/health"; then
        echo "✅ Opdateret og genstartet - $BASE svarer igen."
        echo "   kører nu:    v$(running_version)"
        echo "   login:       $(login_url)"
        exit 0
    fi
done
echo "⚠️  Appen svarede ikke inden 60 s. Se logs: journalctl --user -u command-center (eller nohup.out)" >&2
exit 6
