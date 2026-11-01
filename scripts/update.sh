#!/bin/bash
# Opdaterer Command Center fra GitHub: tjek -> filsynk (med backup) -> requirements -> genstart.
# Appens update-endpoints bruges, saa logikken findes kun ét sted.
#
#   bash scripts/update.sh              # opdater + genstart, vent til appen svarer
#   bash scripts/update.sh --no-restart # opdater, men genstart selv bagefter
#   bash scripts/update.sh --check      # kun tjek, skriv intet
#
# Kraever JUNO_TOKEN i .env (maskin-noegle til /api/*).
set -u
cd "$(dirname "$0")/.."

if [ -f .env ]; then
    set -a; source .env; set +a
fi

MODE="apply"
case "${1:-}" in
    --no-restart) MODE="apply-no-restart" ;;
    --check) MODE="check" ;;
    -h|--help)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    "") ;;
    *) echo "Ukendt argument: $1 (brug --check, --no-restart eller -h)" >&2; exit 64 ;;
esac

HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
case "$HOST" in
    0.0.0.0|::|"") PROBE=127.0.0.1 ;;
    *) PROBE="$HOST" ;;
esac
BASE="http://$PROBE:$PORT"
TOKEN="${JUNO_TOKEN:-}"

PY="./venv/bin/python"
[ -x "$PY" ] || PY="python3"
field() {
    printf '%s' "$1" | "$PY" -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]))' "$2" 2>/dev/null
}

if [ -z "$TOKEN" ]; then
    echo "❌ JUNO_TOKEN mangler i .env - update-endpoints kraever maskin-noeglen." >&2
    exit 2
fi
if ! curl -sf -o /dev/null --max-time 5 -H "X-CC-Token: $TOKEN" "$BASE/api/update"; then
    echo "❌ Appen svarer ikke paa $BASE - start den foerst (./run.sh)." >&2
    exit 3
fi

echo "→ Tjekker GitHub mod $BASE..."
CHECK="$(curl -s --max-time 120 -X POST -H "X-CC-Token: $TOKEN" "$BASE/api/update/check")"
[ -n "$CHECK" ] || { echo "❌ Tomt svar fra /api/update/check" >&2; exit 4; }
echo "   installeret: $(field "$CHECK" current)"
echo "   nyeste:      $(field "$CHECK" latest)  $(field "$CHECK" message)"
if [ "$(field "$CHECK" ok)" != "True" ]; then
    echo "❌ Tjekket fejlede: $(field "$CHECK" error)" >&2
    exit 4
fi
if [ "$(field "$CHECK" behind)" != "True" ]; then
    echo "✅ Du kører nyeste version."
    exit 0
fi

if [ "$MODE" = "check" ]; then
    echo "⬆️  Ny version tilgængelig."
    exit 0
fi

RESTART=1
[ "$MODE" = "apply-no-restart" ] && RESTART=0
echo "→ Henter og skriver filer (DB-backup foerst, requirements installeres hvis de er aendret)..."
RESULT="$(curl -s --max-time 600 -X POST -H "X-CC-Token: $TOKEN" "$BASE/api/update/apply?restart=$RESTART")"
[ -n "$RESULT" ] || { echo "❌ Tomt svar fra /api/update/apply" >&2; exit 5; }

echo "   ok:           $(field "$RESULT" ok)"
echo "   filer:        $(printf '%s' "$RESULT" | "$PY" -c 'import json,sys;print(len(json.load(sys.stdin).get("files") or []))' 2>/dev/null)"
echo "   requirements: $(printf '%s' "$RESULT" | "$PY" -c 'import json,sys;d=json.load(sys.stdin).get("requirements_install") or {};print(("OK" if d.get("ok") else "FEJL")+": "+(d.get("output") or "")[:200])' 2>/dev/null)"
if [ "$(field "$RESULT" ok)" != "True" ]; then
    echo "❌ Opdateringen fejlede: $(field "$RESULT" error)" >&2
    exit 5
fi
echo "   genstart:     $(printf '%s' "$RESULT" | "$PY" -c 'import json,sys;r=json.load(sys.stdin).get("restart") or {};print(("planlagt ("+str(r.get("mode"))+")") if r.get("scheduled") else "IKKE planlagt: "+str(r.get("reason")))' 2>/dev/null)"

if [ "$RESTART" = "0" ]; then
    echo "✅ Filer opdateret. Genstart selv: bash scripts/restart.sh"
    exit 0
fi

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
