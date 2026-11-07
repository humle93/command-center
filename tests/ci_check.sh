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
# Standardbrugeren seedes fra .env ved opstart; her er linjerne tomme, saa /setup er reserven -
# og den lukker sig selv, saa snart der findes en bruger.
check "auth: /setup lukker sig selv naar brugeren findes" "$(curl -s -o /dev/null -w '%{http_code}' $U/setup)" "303"
check "auth: session cookie opens the dashboard" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" $U/)" "200"
# Uden CC_ADMIN_PASSWORD i .env maa advarslen om en foraeldet kode ikke dukke op.
check "advarsel: ingen falsk advarsel uden CC_ADMIN_PASSWORD" \
    "$(curl -s -b "$JAR" $U/ | grep -c 'passer ikke l')" "0"
# Uden SMTP kan invitationen ikke sendes - saa oprettes brugeren ikke, og fejlen bliver en alarm.
curl -s -o /dev/null -b "$JAR" -X POST $U/users/invite -d email=ci2@example.dk
check "invite: no user without SMTP" "$(q "SELECT COUNT(*) FROM users")" "1"
check "invite: the failure is visible as an alarm" "$(q "SELECT COUNT(*) FROM alarms WHERE message LIKE '%blev ikke sendt%'")" "1"
# ... og svaret lander i Brugere-fanen, saa fejlen ikke ser ud som en tabt mail.
check "invite: failure redirects to the Brugere tab" \
    "$(curl -s -o /dev/null -b "$JAR" -X POST $U/users/invite -d email=ci3@example.dk -w '%{redirect_url}' | sed "s|^$U||")" \
    "/?tab=brugere&invite=fejl&invite_msg=SMTP_HOST%20/%20SMTP_FROM%20mangler%20i%20.env%20-%20der%20blev%20ikke%20sendt%20noget&invite_email=ci3%40example.dk&invite_kind=smtp"
check "invite: the page shows the error in the form" \
    "$(curl -s -b "$JAR" "$U/?tab=brugere&invite=fejl&invite_msg=SMTP_HOST%20mangler" | grep -c 'Invitationen blev ikke sendt')" "1"
check "invite: the Brugere tab opens from the URL" \
    "$(curl -s -b "$JAR" "$U/?tab=brugere" | grep -c "tab: 'brugere'")" "1"
# v7.17.3: samme tjek i formularen som i scripts/invite.py - en pladsholder bliver ikke en bruger.
check "invite: a placeholder address is refused in the form" \
    "$(curl -s -o /dev/null -b "$JAR" -X POST $U/users/invite -d email=dit.navn@domaene.dk -w '%{redirect_url}' | grep -c 'invite_kind=eksempel')" "1"
check "invite: the placeholder never becomes a user" "$(q "SELECT COUNT(*) FROM users")" "1"
check "invite: the form explains the refusal and offers to continue" \
    "$(curl -s -b "$JAR" "$U/?tab=brugere&invite=fejl&invite_msg=x&invite_kind=eksempel&invite_email=dit.navn%40domaene.dk" | grep -c 'Opret alligevel')" "1"
# v7.17.4: en afvist eller gennemfoert sletning svarer i fanen, ikke kun i Alarmer.
check "delete: the last user is refused with a reason" \
    "$(curl -s -o /dev/null -b "$JAR" -X POST $U/users/delete -d id=1 -w '%{redirect_url}' | grep -c 'del_kind=sidste')" "1"
check "delete: the last user survives" "$(q "SELECT COUNT(*) FROM users")" "1"
check "delete: the page explains the refusal" \
    "$(curl -s -b "$JAR" "$U/?tab=brugere&del=fejl&del_msg=x&del_kind=sidste" | grep -c 'Brugeren blev ikke slettet')" "1"
check "delete: an unknown id does not look like a deletion" \
    "$(curl -s -o /dev/null -b "$JAR" -X POST $U/users/delete -d id=999999 -w '%{redirect_url}' | grep -c 'del_kind=findes-ikke')" "1"
python3 -c "import app.main as m; m.create_user('slettes@example.dk','slettes-pass-1')"
DEL_ID=$(q "SELECT id FROM users WHERE email='slettes@example.dk'")
check "delete: a second user can be deleted" \
    "$(curl -s -o /dev/null -b "$JAR" -X POST $U/users/delete -d id=$DEL_ID -w '%{redirect_url}' | grep -c 'del=ok')" "1"
check "delete: the deleted user is gone" "$(q "SELECT COUNT(*) FROM users WHERE email='slettes@example.dk'")" "0"
# v7.17.5: knappen i WordPress faar et engangslink fra CC - og det link logger ind én gang.
check "cc-login: CC pushes a one-time link to WordPress" \
    "$(curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/login-link -w '%{redirect_url}' | grep -c 'cc_link=ok')" "1"
LINK=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['url'])" "$TMP/state.link")
check "cc-login: the link points at this app" "$(printf '%s' "$LINK" | grep -c '^http://127.0.0.1:8765/cc-login?code=')" "1"
curl -s -o /dev/null -c "$TMP/ccjar" "$LINK"
check "cc-login: the link opens the dashboard" "$(curl -s -o /dev/null -b "$TMP/ccjar" -w '%{http_code}' $U/)" "200"
check "cc-login: the button is in the Social tab" \
    "$(curl -s -b "$JAR" "$U/?tab=social" | grep -c 'Log ind på Command Center')" "1"
check "cc-login: the same link cannot be used twice" "$(curl -s -o /dev/null -w '%{redirect_url}' "$LINK" | sed "s|^$U||")" "/login?cc=udloebet"
# --- v7.20.0: Cockpit viser budget-kort og job-heartbeat ---
check "cockpit: budgetkort vises" "$(curl -s -b "$JAR" $U/ | grep -c 'API-budget denne m')" "1"
check "cockpit: job-heartbeat vises" "$(curl -s -b "$JAR" $U/ | grep -c 'Planlagte jobs (heartbeat)')" "1"

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
# --- v7.17.1: ukendt vaerktoej i auditten + noeglen vises kun én gang ---
check "mcp3: ukendt vaerktoej giver -32602" "$(wmcp '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"findes_ikke","arguments":{}}}' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["error"]["code"])')" "-32602"
check "mcp3: ukendt vaerktoej staar i auditten" "$(q "SELECT COUNT(*) FROM api_audit WHERE tool='findes_ikke' AND ok=0 AND detail LIKE '%ukendt%'")" "1"
check "mcp3: fejl i auditten taelles med i api_usage" "$(q "SELECT COUNT(*) FROM api_audit WHERE client_id=(SELECT id FROM api_clients WHERE name='CI-skriver') AND ok=0")" "1"
curl -s -o /dev/null -b "$JAR" -X POST $U/api-keys/create -d name=UI-noegle -d scopes=read
UIKEY=$(python3 -c "import sqlite3,json;r=sqlite3.connect('app/data/center.db').execute(\"SELECT value FROM settings WHERE key='api_key_once'\").fetchone();print(json.loads(r[0])['key'] if r else '')")
check "mcp3: UI-noeglen har et tidsstempel" "$(python3 -c "import sqlite3,json;r=sqlite3.connect('app/data/center.db').execute(\"SELECT value FROM settings WHERE key='api_key_once'\").fetchone();print('ja' if r and json.loads(r[0]).get('created_at') else 'nej')")" "ja"
check "mcp3: noeglen vises paa dashboardet" "$(curl -s -b "$JAR" $U/ | grep -c "$UIKEY")" "1"
check "mcp3: anden visning viser ingen noegle" "$(curl -s -b "$JAR" $U/ | grep -c "$UIKEY")" "0"
check "mcp3: noeglen er slettet fra DB efter visning" "$(q "SELECT COUNT(*) FROM settings WHERE key='api_key_once'")" "0"
check "mcp3: dismiss-ruten er væk" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -X POST $U/api-keys/dismiss)" "404"
check "update: /api/update is available" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" $U/api/update)" "200"
check "update: /api/update reports the repo" "$(curl -s -b "$JAR" $U/api/update | python3 -c 'import json,sys;print(bool(json.load(sys.stdin).get("repo")))')" "True"
# Versionskontrollen: filer, koerende proces og installatoer skal sige det samme. Koeres mod
# CI-serveren paa 8765, saa den ogsaa daekker /health-linjen - ikke kun de to filer.
CC_PORT=8765 bash scripts/update.sh --version > "$TMP/version.log" 2>&1; VRC=$?
check "version: filer, proces og installatoer stemmer" "$VRC" "0"
[ "$VRC" = 0 ] || cat "$TMP/version.log"
# Guarden foer skrivning: en aeldre install.sh skal stoppe en rigtig opdatering, foer den roerer
# filer - og uden venv, token eller netvaerk, saa den kan testes her. Kode 7 = naegtet.
VT="$(mktemp -d)"; mkdir -p "$VT/scripts" "$VT/app"
cp scripts/update.sh "$VT/scripts/"; cp app/main.py "$VT/app/"; cp install.sh "$VT/"
awk 'BEGIN{d=0} /^APP_VERSION = /{if(!d){print "APP_VERSION = \"0.0.1\""; d=1; next}} {print}' "$VT/install.sh" > "$VT/i" && mv "$VT/i" "$VT/install.sh"
SUM_BEFORE="$(cksum "$VT/app/main.py")"
(cd "$VT" && bash scripts/update.sh --no-restart > "$TMP/guard.log" 2>&1); GRC=$?
check "version: opdateringen naegter naar install.sh er aeldre" "$GRC" "7"
[ "$GRC" = 7 ] || cat "$TMP/guard.log"
check "version: naegtelsen skriver intet" "$(cksum "$VT/app/main.py")" "$SUM_BEFORE"
rm -rf "$VT"

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
check "bridge: reads the full /snapshot" "$(q "SELECT json_extract(value,'\$.source') FROM settings WHERE key='sgap_snapshot'")" "snapshot"
check "bridge: plugin version from the snapshot" "$(q "SELECT json_extract(value,'\$.version') FROM settings WHERE key='sgap_snapshot'")" "7.33.0"
check "bridge: sends X-Command-Center with its version" "$(cat "$TMP/state.header")" "$(grep -oP '^APP_VERSION = "\K[^"]+' app/main.py)"
check "bridge: dashboard shows the plugin version and cron lag" "$(curl -s -b "$JAR" $U/ | grep -c 'Autopilot 7.33.0\|WP-Cron er 45 min bagud')" "2"
echo failed2 > "$TMP/state"
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
check "bridge: a new self-check problem raises an alarm" "$(q "SELECT COUNT(*) FROM alarms WHERE message LIKE 'Autopilot-selvtjek: The autopilot is off.%'")" "1"
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
check "bridge: the same problem does not alarm twice" "$(q "SELECT COUNT(*) FROM alarms WHERE message LIKE 'Autopilot-selvtjek:%'")" "1"
echo old > "$TMP/state"
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
check "bridge: older plugin without /snapshot falls back to /stats" "$(q "SELECT json_extract(value,'\$.source') || '/' || json_extract(value,'\$.ok') FROM settings WHERE key='sgap_snapshot'")" "stats/1"
echo ok > "$TMP/state"
curl -s -o /dev/null -b "$JAR" -X POST $U/autopilot/sync
# v7.18.0: CC markerer sig som Command Center, og fanen Social viser WordPress' eget svar.
check "bridge: CC markerer sig med X-Command-Center" \
    "$(cat "$TMP/state.cc" 2>/dev/null)" "$(grep -oP 'APP_VERSION = "\K[^"]+' app/main.py)"
check "bridge: Social viser hvornaar WordPress sidst hoerte fra CC" \
    "$(curl -s -b "$JAR" "$U/?tab=social" | grep -c 'WordPress hoerte sidst fra Command Center')" "1"
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
