#!/bin/bash
# Boots Command Center against a fake WordPress, calls every page and the
# Autopilot bridge, and fails on any 500 or Python traceback.
# Usage: bash tests/ci_check.sh   (needs the requirements installed)
set -u
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got '$2', want '$3')"; FAIL=1; fi; }

echo ok > "$TMP/state"
python3 tests/fake_wp.py "$TMP/state" > /dev/null 2>&1 & WP_PID=$!
rm -rf app/data
APP_TOKEN=citest WP_URL=http://127.0.0.1:8770 WP_USER=admin WP_APP_PASSWORD='app pass' \
    python3 -m uvicorn app.main:app --host 127.0.0.1 --port 8765 > "$TMP/cc.log" 2>&1 & CC_PID=$!
trap 'kill $CC_PID $WP_PID 2>/dev/null; rm -rf app/data' EXIT
for _ in $(seq 1 40); do curl -s -o /dev/null http://127.0.0.1:8765/health && break; sleep 0.5; done

U=http://127.0.0.1:8765; A='x-cc-token: citest'
q() { python3 -c "import sqlite3,sys;print(sqlite3.connect('app/data/center.db').execute(sys.argv[1]).fetchone()[0])" "$1"; }

CC_PORT=8765 bash scripts/smoke_test.sh > /dev/null && echo "PASS smoke test" || { echo "FAIL smoke test"; FAIL=1; }
for r in $(grep -oE '@app\.get\("[^"{]+"\)' app/main.py | sed 's/@app.get("//;s/")$//' | sort -u); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H "$A" "$U$r")
    case "$code" in 200|303|400) ;; *) echo "FAIL GET $r -> $code"; FAIL=1 ;; esac
done
echo "PASS GET routes swept"
check "anonymous dashboard redirects to login" "$(curl -s -o /dev/null -w '%{http_code}' $U/)" "303"

curl -s -o /dev/null -H "$A" -X POST $U/autopilot/sync
check "bridge: snapshot ok" "$(q "SELECT json_extract(value,'\$.ok') FROM settings WHERE key='sgap_snapshot'")" "1"
check "bridge: dashboard shows panel" "$(curl -s -H "$A" $U/ | grep -c 'Kladder venter')" "1"
curl -s -o /dev/null -H "$A" -X POST $U/social/add -d platform=X -d message=Hello
curl -s -o /dev/null -H "$A" -X POST $U/social/to-autopilot -d id=1
check "bridge: social post sent as draft" "$(q "SELECT status FROM socialqueue WHERE id=1")" "sendt til autopilot (kladde #1)"
echo 404 > "$TMP/state"
curl -s -o /dev/null -H "$A" -X POST $U/autopilot/sync
curl -s -o /dev/null -H "$A" -X POST $U/autopilot/sync
check "bridge: missing plugin raises one alarm" "$(q "SELECT COUNT(*) FROM alarms WHERE message LIKE '%findes ikke (404)%'")" "1"

curl -s -o /dev/null -H "$A" -X POST $U/settings/module -d name=autopilot -d state=off
check "modules: switching off takes effect at once (cache cleared)" "$(curl -s -H "$A" $U/ | grep -c 'Autopilot-bro (WordPress)\" er slukket\|Modulet \"Autopilot-bro\" er slukket')" "1"
curl -s -o /dev/null -H "$A" -X POST $U/settings/module -d name=autopilot -d state=on

check "no Python tracebacks" "$(grep -c Traceback "$TMP/cc.log")" "0"
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; tail -40 "$TMP/cc.log"; }
exit $FAIL
