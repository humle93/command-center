#!/usr/bin/env bash
# smoke_test.sh - tjekker at appen svarer efter install eller self-update.
#
# Brug:
#   bash scripts/smoke_test.sh                           # 127.0.0.1:8000
#   CC_HOST=0.0.0.0 CC_PORT=8000 bash scripts/smoke_test.sh
#
# Kraever: en koerende app. CC_PUBLIC_URL vises som den offentlige adresse, hvis den er sat.
# Sidst aendret: 4. november 2026
HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
PUBLIC="${CC_PUBLIC_URL:-}"
PROBE="$HOST"
case "$HOST" in
    0.0.0.0|::|"") PROBE=127.0.0.1 ;;
esac
BASE="http://$PROBE:$PORT"
echo "Smoke-test mod $BASE (lytter paa $HOST:$PORT)"
[ -n "$PUBLIC" ] && echo "Offentlig adresse (bag nginx): $PUBLIC"
ok=1
for p in /health /login /setup; do
  code=$(curl -s -o /dev/null --max-time 5 -w "%{http_code}" "$BASE$p" 2>/dev/null) || code=000
  case "$code" in
    200|303) echo "OK   $p -> $code" ;;
    *) echo "FAIL $p -> $code"; ok=0 ;;
  esac
done
if [ "$ok" = "1" ]; then
  echo "✅ Smoke-test OK — åbn ${PUBLIC:-$BASE} (første besøg opretter din bruger)"
else
  echo "❌ Smoke-test FEJLEDE - tjek logs: journalctl --user -u command-center ellers journalctl -u command-center"
fi
exit $((1 - ok))  # 0 = alt OK (shell-konvention)
