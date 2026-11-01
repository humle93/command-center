#!/bin/bash
# Opdaterer Command Center fra GitHub: tjek -> filer (med DB-backup) -> requirements -> genstart.
# Koerer appens opdateringsfunktioner direkte i venv'en, saa der kraves hverken token eller login.
#
#   bash scripts/update.sh              # opdater + genstart, vent til /health svarer
#   bash scripts/update.sh --no-restart # opdater, men genstart selv bagefter
#   bash scripts/update.sh --check      # kun tjek, skriv intet
set -u
cd "$(dirname "$0")/.."

if [ -f .env ]; then
    set -a; source .env; set +a
fi

MODE="apply"
case "${1:-}" in
    --no-restart) MODE="apply-no-restart" ;;
    --check) MODE="check" ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
    echo "✅ Filer opdateret. Genstart selv: bash scripts/restart.sh"
    exit 0
fi

echo "→ Genstarter..."
bash scripts/restart.sh || { echo "❌ Genstart fejlede - se logs." >&2; exit 6; }
echo "→ Venter paa at appen svarer igen..."
for _ in $(seq 1 60); do
    sleep 1
    if curl -sf -o /dev/null --max-time 3 "$BASE/health"; then
        echo "✅ Opdateret og genstartet - $BASE svarer igen."
        exit 0
    fi
done
echo "⚠️  Appen svarede ikke inden 60 s. Se logs: journalctl --user -u command-center (eller nohup.out)" >&2
exit 6
