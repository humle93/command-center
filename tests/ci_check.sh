#!/bin/bash
# Boots Command Center against a fake WordPress, creates the first user, calls every page
# and the Autopilot bridge, and fails on any 500 or Python traceback.
# Usage: bash tests/ci_check.sh   (needs the requirements installed)
set -u
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got '$2', want '$3')"; FAIL=1; fi; }

echo ok > "$TMP/state"
python3 tests/fake_wp.py "$TMP/state" > /dev/null 2>&1 & WP_PID=$!
rm -rf app/data
python3 tests/check_paths.py && echo "PASS template paths" || { echo "FAIL template paths"; FAIL=1; }
WP_URL=http://127.0.0.1:8770 WP_USER=admin WP_APP_PASSWORD='app pass' \
    python3 -m uvicorn app.main:app --host 127.0.0.1 --port 8765 > "$TMP/cc.log" 2>&1 & CC_PID=$!
trap 'kill $CC_PID $WP_PID 2>/dev/null; rm -rf app/data' EXIT
for _ in $(seq 1 40); do curl -s -o /dev/null http://127.0.0.1:8765/health && break; sleep 0.5; done

U=http://127.0.0.1:8765; JAR="$TMP/cookies"
q() { python3 -c "import sqlite3,sys;print(sqlite3.connect('app/data/center.db').execute(sys.argv[1]).fetchone()[0])" "$1"; }

# --- auth: first user via /setup, then the session cookie for everything else ---
curl -s -o /dev/null -c "$JAR" -X POST $U/setup -d username=ciadmin -d password=citest-pass -d confirm=citest-pass
check "auth: /setup created the first user" "$(q "SELECT username FROM users")" "ciadmin"
check "auth: anonymous dashboard redirects to login" "$(curl -s -o /dev/null -w '%{http_code}' $U/)" "303"
check "auth: anonymous API is rejected" "$(curl -s -o /dev/null -w '%{http_code}' $U/api/visibility)" "401"
check "auth: wrong password is rejected" "$(curl -s -o /dev/null -w '%{http_code}' -X POST $U/login -d username=ciadmin -d password=wrong)" "401"
check "auth: session cookie opens the dashboard" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" $U/)" "200"
curl -s -o /dev/null -b "$JAR" -X POST $U/users/add -d username=ci2 -d password=citest-pass2
check "auth: a second user can be created" "$(q "SELECT COUNT(*) FROM users")" "2"
check "update: /api/update is available" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" $U/api/update)" "200"
check "update: /api/update reports the repo" "$(curl -s -b "$JAR" $U/api/update | python3 -c 'import json,sys;print(bool(json.load(sys.stdin).get("repo")))')" "True"

CC_PORT=8765 bash scripts/smoke_test.sh > /dev/null && echo "PASS smoke test" || { echo "FAIL smoke test"; FAIL=1; }
for r in $(grep -oE '@app\.get\("[^"\{]+"\)' app/main.py | sed 's/@app.get("//;s/")$//' | sort -u); do
    [ "$r" = "/logout" ] && continue  # afslutter sessionen - testes separat nedenfor
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -b "$JAR" "$U$r")
    case "$code" in 200|303|400) ;; *) echo "FAIL GET $r -> $code"; FAIL=1 ;; esac
done
echo "PASS GET routes swept"

curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
check "bridge: snapshot ok" "$(q "SELECT json_extract(value,'\$.ok') FROM settings WHERE key='sgap_snapshot'")" "1"
check "bridge: dashboard shows panel" "$(curl -s -b "$JAR" $U/ | grep -c 'Kladder venter')" "1"
curl -s -o /dev/null -b "$JAR" -X POST $U/social/add -d platform=X -d message=Hello
curl -s -o /dev/null -b "$JAR" -X POST $U/social/to-autopilot -d id=1
check "bridge: social post sent as draft" "$(q "SELECT status FROM socialqueue WHERE id=1")" "sendt til autopilot (kladde #1)"
echo 404 > "$TMP/state"
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
check "bridge: missing plugin raises one alarm" "$(q "SELECT COUNT(*) FROM alarms WHERE message LIKE '%findes ikke (404)%'")" "1"

curl -s -o /dev/null -b "$JAR" -X POST $U/settings/module -d name=autopilot -d state=off
check "modules: switching off takes effect at once (cache cleared)" "$(curl -s -b "$JAR" $U/ | grep -c 'Autopilot-bro (WordPress)\" er slukket\|Modulet \"Autopilot-bro\" er slukket')" "1"
curl -s -o /dev/null -b "$JAR" -X POST $U/settings/module -d name=autopilot -d state=on

# --- logout afslutter sessionen (eget cookie-jar, saa CI-sessionen overlever) ---
curl -s -o /dev/null -c "$TMP/jar2" -X POST $U/login -d username=ciadmin -d password=citest-pass
check "auth: login sets a session" "$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/jar2" $U/)" "200"
curl -s -o /dev/null -b "$TMP/jar2" -c "$TMP/jar2" $U/logout
check "auth: logout ends the session" "$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/jar2" $U/)" "303"

check "no Python tracebacks" "$(grep -c Traceback "$TMP/cc.log")" "0"
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; tail -40 "$TMP/cc.log"; }
exit $FAIL
