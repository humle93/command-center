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
curl -s -o /dev/null -c "$JAR" -X POST $U/setup -d email=ciadmin@example.dk -d password=citest-pass -d confirm=citest-pass
check "auth: /setup created the first user" "$(q "SELECT email FROM users")" "ciadmin@example.dk"
check "auth: anonymous dashboard redirects to login" "$(curl -s -o /dev/null -w '%{http_code}' $U/)" "303"
check "auth: anonymous API is rejected" "$(curl -s -o /dev/null -w '%{http_code}' $U/api/visibility)" "401"
check "auth: wrong password is rejected" "$(curl -s -o /dev/null -w '%{http_code}' -X POST $U/login -d email=ciadmin@example.dk -d password=wrong)" "401"
check "auth: session cookie opens the dashboard" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" $U/)" "200"
# Uden SMTP kan invitationen ikke sendes - saa oprettes brugeren ikke, og fejlen bliver en alarm.
curl -s -o /dev/null -b "$JAR" -X POST $U/users/invite -d email=ci2@example.dk
check "invite: no user without SMTP" "$(q "SELECT COUNT(*) FROM users")" "1"
check "invite: the failure is visible as an alarm" "$(q "SELECT COUNT(*) FROM alarms WHERE message LIKE '%blev ikke sendt%'")" "1"
# --- MCP fase 1: personlige noegler + laese-vaerktoejer paa /mcp ---
mcp() { curl -s -X POST $U/mcp -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$1"; }
check "mcp: uden noegle svarer 401" "$(curl -s -o /dev/null -w '%{http_code}' -X POST $U/mcp \
    -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')" "401"
KEY=$(python3 scripts/api_key.py create "CI-agent" read | tail -1)
check "mcp: initialize svarer med protokolversion" "$(mcp '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["protocolVersion"])')" "2026-07-28"
check "mcp: tools/list giver 11 vaerktoejer" "$(mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["result"]["tools"]))')" "11"
check "mcp: alarms_open svarer uden fejl" "$(mcp '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"alarms_open","arguments":{}}}' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["isError"])')" "False"
check "mcp: noeglen er hashet og kun halen gemt" "$(q "SELECT COUNT(*) FROM api_clients WHERE length(key_hash)=64 AND length(key_hint)=4")" "1"
check "mcp: klartekst-noeglen ligger ikke i databasen" "$(q "SELECT COUNT(*) FROM api_clients WHERE key_hash='$KEY' OR key_hint='$KEY'")" "0"
python3 scripts/api_key.py revoke 1 > /dev/null
check "mcp: tilbagekaldt noegle afvises" "$(curl -s -o /dev/null -w '%{http_code}' -X POST $U/mcp \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":4,"method":"tools/list"}')" "401"
# --- MCP fase 2: skrivende vaerktoejer + audit pr. noegle ---
WKEY=$(python3 scripts/api_key.py create "CI-skriver" read,write | tail -1)
RKEY=$(python3 scripts/api_key.py create "CI-laeser" read | tail -1)
wmcp() { curl -s -X POST $U/mcp -H "Authorization: Bearer $WKEY" -H 'Content-Type: application/json' -d "$1"; }
rmcp() { curl -s -X POST $U/mcp -H "Authorization: Bearer $RKEY" -H 'Content-Type: application/json' -d "$1"; }
NOTE='{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"add_note","arguments":{"content":"MCP-note fra CI"}}}'
MON='{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"add_monitor","arguments":{"name":"CI-monitor","url":"https://example.dk/pris","type":"price","expected":"199"}}}'
check "mcp2: write-noegle skriver en note" "$(wmcp "$NOTE" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["isError"])')" "False"
check "mcp2: noten ligger i databasen" "$(q "SELECT COUNT(*) FROM notes WHERE content='MCP-note fra CI'")" "1"
check "mcp2: read-noegle afvises paa add_note" "$(rmcp "$NOTE" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["error"]["code"])')" "-32003"
wmcp "$MON" > /dev/null
check "mcp2: add_monitor genbruger samme url" "$(wmcp "$MON" \
    | python3 -c 'import json,sys;print("allerede" in json.load(sys.stdin)["result"]["content"][0]["text"] and "ja" or "nej")')" "ja"
check "mcp2: kun én monitor blev oprettet" "$(q "SELECT COUNT(*) FROM monitors WHERE name='CI-monitor'")" "1"
check "mcp2: resolve_alarm loeser alarmen" "$(wmcp '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"resolve_alarm","arguments":{"id":1}}}' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["isError"])')" "False"
check "mcp2: alarmen er markeret loest i DB" "$(q "SELECT resolved FROM alarms WHERE id=1")" "1"
check "mcp2: auditten har kald med noeglenavn" "$(q "SELECT COUNT(*) FROM api_audit WHERE tool='add_monitor' AND ok=1")" "2"
check "mcp2: scope-afvisning staar i auditten" "$(q "SELECT COUNT(*) FROM api_audit WHERE ok=0 AND detail LIKE '%scope: write%'")" "1"
check "mcp2: auditten gemmer ikke noeglen" "$(q "SELECT COUNT(*) FROM api_audit WHERE detail LIKE '%$WKEY%'")" "0"
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

curl -s -o /dev/null -b "$JAR" -X POST $U/social/to-autopilot -d id=1
DRAFTS=$(curl -s -u 'admin:app pass' http://127.0.0.1:8770/wp-json/sgap/v1/drafts | grep -o '"id":' | wc -l | tr -d ' ')
check "bridge: genforsoeg sender ikke kladden igen" "$DRAFTS" "1"
check "bridge: status er uaendret efter genforsoeg" "$(q "SELECT status FROM socialqueue WHERE id=1")" "sendt til autopilot (kladde #1)"
echo 404 > "$TMP/state"
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
check "bridge: missing plugin raises one alarm" "$(q "SELECT COUNT(*) FROM alarms WHERE message LIKE '%findes ikke (404)%'")" "1"

curl -s -o /dev/null -b "$JAR" -X POST $U/settings/module -d name=autopilot -d state=off
check "modules: switching off takes effect at once (cache cleared)" "$(curl -s -b "$JAR" $U/ | grep -c 'Autopilot-bro (WordPress)\" er slukket\|Modulet \"Autopilot-bro\" er slukket')" "1"
curl -s -o /dev/null -b "$JAR" -X POST $U/settings/module -d name=autopilot -d state=on

# --- logout afslutter sessionen (eget cookie-jar, saa CI-sessionen overlever) ---
curl -s -o /dev/null -c "$TMP/jar2" -X POST $U/login -d email=ciadmin@example.dk -d password=citest-pass
check "auth: login sets a session" "$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/jar2" $U/)" "200"
curl -s -o /dev/null -b "$TMP/jar2" -c "$TMP/jar2" $U/logout
check "auth: logout ends the session" "$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/jar2" $U/)" "303"

check "ui: task progress card is rendered" "$(curl -s -b "$JAR" $U/ | grep -c 'id="cc-task"')" "1"
check "ui: crawl status exposes percent and ETA" "$(curl -s -b "$JAR" $U/api/crawl/status | python3 -c 'import json,sys;d=json.load(sys.stdin);print("percent" in d and "eta_seconds" in d and "elapsed_seconds" in d)')" "True"
check "no Python tracebacks" "$(grep -c Traceback "$TMP/cc.log")" "0"
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; tail -40 "$TMP/cc.log"; }
exit $FAIL
