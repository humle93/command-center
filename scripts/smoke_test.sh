#!/bin/bash
# Command Center smoke-test (v7.9) - koer efter install eller self-update.
# Brug: bash scripts/smoke_test.sh
PORT="${CC_PORT:-8000}"
ok=1
for p in /health /login; do
  code=$(curl -s -o /dev/null --max-time 5 -w "%{http_code}" "http://127.0.0.1:$PORT$p" 2>/dev/null) || code=000
  case "$code" in
    200) echo "OK   $p -> 200" ;;
    *) echo "FAIL $p -> $code"; ok=0 ;;
  esac
done
if [ "$ok" = "1" ]; then
  echo "✅ Smoke-test OK"
else
  echo "❌ Smoke-test FEJLEDE - tjek logs: journalctl -u command-center ellers tail -50 ~/command-center/nohup.out"
fi
exit $ok
