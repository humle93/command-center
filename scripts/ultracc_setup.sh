#!/usr/bin/env bash
# ultracc_setup.sh - flytter Command Center fra en Cloudflare-tunnel til almindeligt login via Ultra.cc's
# egen nginx paa en understi (https://<bruger>.<server>.usbx.me/cc). Samme skridt som
# docs/Installation_og_udrulning.md afsnit 2e - bare samlet.
#
# Brug:
#   bash scripts/ultracc_setup.sh --url https://<bruger>.<server>.usbx.me/cc            # vis planen, skriv intet
#   bash scripts/ultracc_setup.sh --url https://<bruger>.<server>.usbx.me/cc --apply    # udfoer planen
#   bash scripts/ultracc_setup.sh --url ... --port 12345 --apply    # fast port (ellers .env / app-ports free)
#   bash scripts/ultracc_setup.sh --url ... --keep-tunnel --apply   # lad cloudflared vaere (fx under test)
#
# Skridt: 1) find og stop cloudflared (proces, systemd --user, crontab)  2) .env: CC_HOST, CC_PORT,
# CC_PUBLIC_URL, CC_FORWARDED_ALLOW_IPS (backup foerst, andre linjer uroerte)  3) nginx-blokken fra
# deploy/nginx-ultracc-proxy.conf med din port og sti  4) app-nginx restart  5) scripts/restart.sh
# 6) tjek /health lokalt og <url>/login udefra.
# Kode: 0 = ok (eller kun plan), 2 = forkerte argumenter, 3 = et skridt fejlede, 4 = tjekket fejlede.
# Kraever: bash, sed, awk og curl. app-ports/app-nginx er Ultra.cc's egne - mangler de, siger scriptet til.
# Miljoe (til test): ULTRACC_NGINX_DIR (standard ~/.apps/nginx/proxy.d), CC_SETUP_RESTART_CMD.
# Sidst aendret: 11. november 2026
set -u
cd "$(dirname "$0")/.."

URL="" PORT="" APPLY=0 KEEP_TUNNEL=0
usage() { awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; }
while [ $# -gt 0 ]; do
    case "$1" in
        --url) URL="${2:-}"; shift 2 ;;
        --port) PORT="${2:-}"; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --keep-tunnel) KEEP_TUNNEL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ukendt argument: $1 (se --help)" >&2; exit 2 ;;
    esac
done

# --- adressen: https://vaert/sti, stien er appens understi ---
URL="${URL%/}"
if ! printf '%s' "$URL" | grep -Eq '^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._-]+)+$'; then
    echo "--url skal vaere https://<bruger>.<server>.usbx.me/<sti>, fx https://humle.lw123.usbx.me/cc" >&2
    echo "  (https, ingen anfoerselstegn, en understi - Ultra.cc giver ikke en app sit eget domaene)" >&2
    exit 2
fi
BASE="/${URL#https://*/}"
case "$BASE" in */..*|*/.) echo "stien maa ikke indeholde .. eller ." >&2; exit 2 ;; esac

envget() { [ -f .env ] && sed -n "s/^$1=//p" .env | tail -1 | tr -d '"'"'"; }

# --- porten: --port, ellers CC_PORT fra .env (hvis ikke standarden 8000), ellers app-ports free ---
if [ -z "$PORT" ]; then
    cur="$(envget CC_PORT)"
    if [ -n "$cur" ] && [ "$cur" != "8000" ]; then
        PORT="$cur"
    elif command -v app-ports >/dev/null 2>&1; then
        PORT="$(app-ports free 2>/dev/null | grep -oE '\b[0-9]{4,5}\b' | head -1)"
    fi
fi
case "$PORT" in
    ''|*[!0-9]*) echo "ingen port: angiv --port <nr> (find en ledig med: app-ports free)" >&2; exit 2 ;;
esac
if [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then echo "porten skal vaere 1024-65535" >&2; exit 2; fi

NGINX_DIR="${ULTRACC_NGINX_DIR:-$HOME/.apps/nginx/proxy.d}"
NGINX_FILE="$NGINX_DIR/command-center.conf"
TEMPLATE="deploy/nginx-ultracc-proxy.conf"
RESTART_CMD="${CC_SETUP_RESTART_CMD:-bash scripts/restart.sh}"
STAMP="$(date +%Y%m%d-%H%M%S)"
[ -f "$TEMPLATE" ] || { echo "mangler $TEMPLATE - koer fra en opdateret installation (v7.28+)" >&2; exit 3; }

render_nginx() {   # kun ikke-kommentarlinjer faar ny sti/port
    sed -e "/^[[:space:]]*#/!s#/cc#${BASE}#g" -e "/^[[:space:]]*#/!s#12345#${PORT}#g" "$TEMPLATE"
}

# --- 1) tunnellen ---
TUN_PIDS="$(pgrep -f cloudflared 2>/dev/null | grep -v "^$$\$" || true)"
TUN_UNITS="$(systemctl --user list-units --all --no-legend 2>/dev/null | grep -oiE '[^[:space:]]*cloudflared[^[:space:]]*\.service' | sort -u || true)"
TUN_CRON="$(crontab -l 2>/dev/null | grep -i cloudflared || true)"

echo "== Command Center -> Ultra.cc uden Cloudflare =="
echo "   adresse:  $URL/   (understi $BASE, port $PORT)"
echo "   tilstand: $([ $APPLY = 1 ] && echo 'UDFOERER' || echo 'kun plan - tilfoej --apply for at udfoere')"
echo
echo "1) Cloudflare-tunnel"
if [ $KEEP_TUNNEL = 1 ]; then
    echo "   springes over (--keep-tunnel)"
elif [ -z "$TUN_PIDS$TUN_UNITS$TUN_CRON" ]; then
    echo "   ingen cloudflared fundet (proces, systemd --user eller crontab)"
else
    [ -n "$TUN_UNITS" ] && printf '   systemd --user: %s -> disable --now\n' $TUN_UNITS
    [ -n "$TUN_CRON" ] && printf '   crontab: %s -> fjernes (backup ~/.crontab-backup-%s)\n' "$TUN_CRON" "$STAMP"
    [ -n "$TUN_PIDS" ] && echo "   processer: $(echo $TUN_PIDS) -> stoppes"
fi
echo
echo "2) .env  (backup .env.bak-$STAMP)"
for kv in "CC_HOST=127.0.0.1" "CC_PORT=$PORT" "CC_PUBLIC_URL=$URL" "CC_FORWARDED_ALLOW_IPS=127.0.0.1"; do
    k="${kv%%=*}"; old="$(envget "$k")"
    if [ "$old" = "${kv#*=}" ]; then echo "   $kv (uaendret)"; else echo "   $k: '${old}' -> '${kv#*=}'"; fi
done
[ -n "$(envget CC_BASE_PATH)" ] && echo "   CC_BASE_PATH: '$(envget CC_BASE_PATH)' -> '' (stien kommer fra CC_PUBLIC_URL)"
echo
echo "3) nginx: $NGINX_FILE"
if [ -f "$NGINX_FILE" ] && render_nginx | cmp -s - "$NGINX_FILE"; then
    echo "   findes allerede og er identisk"
else
    [ -f "$NGINX_FILE" ] && echo "   findes og afviger -> backup $NGINX_FILE.bak-$STAMP"
    render_nginx | grep -vE '^[[:space:]]*(#|$)' | sed 's/^/   | /'
fi
echo
echo "4) app-nginx restart$(command -v app-nginx >/dev/null 2>&1 || echo '   (kommandoen findes ikke her - genindlaes nginx selv)')"
echo "5) genstart: $RESTART_CMD"
echo "6) tjek: http://127.0.0.1:$PORT/health og $URL/login"

[ $APPLY = 1 ] || exit 0
echo
fail() { echo "FEJL: $*" >&2; exit 3; }

# 1) tunnel
if [ $KEEP_TUNNEL = 0 ]; then
    for u in $TUN_UNITS; do systemctl --user disable --now "$u" && echo "ok   $u stoppet og slaaet fra" || fail "kunne ikke stoppe $u"; done
    if [ -n "$TUN_CRON" ]; then
        cronbak="$HOME/.crontab-backup-$STAMP"
        crontab -l > "$cronbak" 2>/dev/null || fail "kunne ikke laese crontab"
        # Fra backupfilen, ikke et nyt "crontab -l": saa laeses og skrives der aldrig samtidig.
        grep -vi cloudflared "$cronbak" | crontab - && echo "ok   cloudflared fjernet fra crontab (backup $cronbak)" \
            || fail "crontab kunne ikke skrives - den gamle ligger i $cronbak"
    fi
    if [ -n "$TUN_PIDS" ]; then
        pkill -f cloudflared 2>/dev/null; sleep 1
        pgrep -f cloudflared >/dev/null 2>&1 && pkill -9 -f cloudflared 2>/dev/null
        echo "ok   cloudflared-processer stoppet"
    fi
fi

# 2) .env - kun de fire noegler (og en tom CC_BASE_PATH) aendres; filmode bevares
if [ ! -f .env ]; then
    [ -f .env.example ] || fail ".env og .env.example mangler"
    cp .env.example .env && chmod 600 .env && echo "ok   .env oprettet fra .env.example"
else
    cp -p .env ".env.bak-$STAMP"
fi
setenv() {
    if grep -q "^$1=" .env; then
        awk -v k="$1" -v v="$2" 'BEGIN{FS=OFS="="} $1==k && !d {print k "=" v; d=1; next} $1==k {next} {print}' .env > .env.tmp
    else
        { cat .env; [ -n "$(tail -c1 .env)" ] && echo; echo "$1=$2"; } > .env.tmp
    fi
    chmod --reference=.env .env.tmp 2>/dev/null; mv .env.tmp .env
}
setenv CC_HOST 127.0.0.1; setenv CC_PORT "$PORT"; setenv CC_PUBLIC_URL "$URL"; setenv CC_FORWARDED_ALLOW_IPS 127.0.0.1
[ -n "$(envget CC_BASE_PATH)" ] && setenv CC_BASE_PATH ""
echo "ok   .env opdateret"

# 3) nginx
mkdir -p "$NGINX_DIR" || fail "kan ikke oprette $NGINX_DIR"
if ! { [ -f "$NGINX_FILE" ] && render_nginx | cmp -s - "$NGINX_FILE"; }; then
    [ -f "$NGINX_FILE" ] && cp -p "$NGINX_FILE" "$NGINX_FILE.bak-$STAMP"
    render_nginx > "$NGINX_FILE" || fail "kunne ikke skrive $NGINX_FILE"
fi
echo "ok   $NGINX_FILE"

# 4) nginx genindlaes
if command -v app-nginx >/dev/null 2>&1; then
    app-nginx restart >/dev/null 2>&1 && echo "ok   app-nginx restart" || fail "app-nginx restart fejlede"
else
    echo "obs  app-nginx findes ikke - genindlaes nginx selv"
fi

# 5) appen
$RESTART_CMD >/dev/null 2>&1 || fail "genstart fejlede: $RESTART_CMD"
echo "ok   genstartet"

# 6) tjek
up=0
for _ in $(seq 1 30); do
    curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/health" 2>/dev/null && { up=1; break; }
    sleep 1
done
[ $up = 1 ] || { echo "FEJL: /health svarer ikke paa 127.0.0.1:$PORT efter 30 s - se nohup.out eller journalctl --user -u command-center" >&2; exit 4; }
echo "ok   /health svarer paa 127.0.0.1:$PORT"
code="$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' "$URL/login" 2>/dev/null || true)"
case "$code" in
    200) echo "ok   $URL/login svarer 200 - log ind med e-mail og adgangskode" ;;
    502|504) echo "FEJL: $URL/login svarer $code - nginx naar ikke appen (port i $NGINX_FILE?)" >&2; exit 4 ;;
    404) echo "FEJL: $URL/login svarer 404 - er nginx genindlaest, og er stien $BASE den samme i blokken?" >&2; exit 4 ;;
    *) echo "FEJL: $URL/login svarer '${code:-intet}' - tjek DNS/certifikat og nginx" >&2; exit 4 ;;
esac
echo
echo "Faerdig. WordPress-knappen faar den nye adresse ved naeste sync (eller: Social -> Forbind login-knappen nu)."
