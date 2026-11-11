#!/usr/bin/env bash
# ultracc_setup.sh - flytter Command Center fra en Cloudflare-tunnel til almindeligt login med e-mail og
# adgangskode. To maader:
#   --ip   direkte paa serverens IP:   http://<ip>:<port>            (ingen nginx, ingen tunnel, ingen token)
#   --url  bag Ultra.cc's nginx:      https://<bruger>.<server>.usbx.me/cc   (understi, https)
#
# Brug:
#   bash scripts/ultracc_setup.sh --ip                            # vis planen (IP findes selv), skriv intet
#   bash scripts/ultracc_setup.sh --ip --apply                    # udfoer den
#   bash scripts/ultracc_setup.sh --ip 203.0.113.5 --port 12345 --apply
#   bash scripts/ultracc_setup.sh --url https://<bruger>.<server>.usbx.me/cc --apply
#   ... --keep-tunnel                                             # lad cloudflared vaere
#
# Skridt: 1) stop cloudflared (proces, systemd --user, crontab)  2) .env: CC_HOST (0.0.0.0 ved --ip),
# CC_PORT, CC_PUBLIC_URL, CC_FORWARDED_ALLOW_IPS - backup foerst, andre linjer uroerte  3) en installeret
# systemd-enhed med fast "--host 127.0.0.1 --port 8000" skiftes til deploy/-udgaven, der foelger .env
# 4) kun --url: nginx-blok + app-nginx restart  5) scripts/restart.sh  6) tjek /health og <adresse>/login.
# Kode: 0 = ok (eller kun plan), 2 = forkerte argumenter, 3 = et skridt fejlede, 4 = tjekket fejlede.
# Kraever: bash, sed, awk og curl. app-ports/app-nginx er Ultra.cc's egne - mangler de, siger scriptet til.
# Miljoe (til test): ULTRACC_NGINX_DIR, CC_SETUP_UNIT_DIR, CC_SETUP_RESTART_CMD, CC_SETUP_IPS.
# Sidst aendret: 11. november 2026
set -u
cd "$(dirname "$0")/.."

MODE="" URL="" IP="" PORT="" APPLY=0 KEEP_TUNNEL=0
usage() { awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; }
is_ipv4() { printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' && \
    [ "$(printf '%s' "$1" | tr '.' '\n' | awk '$1>255' | wc -l)" -eq 0 ]; }
while [ $# -gt 0 ]; do
    case "$1" in
        --url) [ -n "$MODE" ] && { echo "brug enten --ip eller --url" >&2; exit 2; }; MODE=url; URL="${2:-}"; shift 2 ;;
        --ip) [ -n "$MODE" ] && { echo "brug enten --ip eller --url" >&2; exit 2; }; MODE=ip
              if [ $# -ge 2 ] && is_ipv4 "$2"; then IP="$2"; shift 2; else shift; fi ;;
        --port) PORT="${2:-}"; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --keep-tunnel) KEEP_TUNNEL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ukendt argument: $1 (se --help)" >&2; exit 2 ;;
    esac
done
[ -n "$MODE" ] || { echo "angiv --ip (direkte paa serverens IP) eller --url https://... (se --help)" >&2; exit 2; }

envget() { [ -f .env ] && sed -n "s/^$1=//p" .env | tail -1 | tr -d '"'"'"; }
is_private() { case "$1" in 10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;; esac; return 1; }

# --- porten: --port, ellers CC_PORT fra .env, ellers app-ports free ---
if [ -z "$PORT" ]; then
    cur="$(envget CC_PORT)"
    if [ -n "$cur" ] && { [ "$cur" != "8000" ] || [ "$MODE" = ip ]; }; then
        PORT="$cur"
    elif command -v app-ports >/dev/null 2>&1; then
        PORT="$(app-ports free 2>/dev/null | grep -oE '\b[0-9]{4,5}\b' | head -1)"
    fi
    [ -z "$PORT" ] && [ "$MODE" = ip ] && PORT=8000
fi
case "$PORT" in
    ''|*[!0-9]*) echo "ingen port: angiv --port <nr> (find en ledig med: app-ports free)" >&2; exit 2 ;;
esac
if [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then echo "porten skal vaere 1024-65535" >&2; exit 2; fi

IP_NOTE=""
if [ "$MODE" = ip ]; then
    if [ -z "$IP" ]; then
        cands="${CC_SETUP_IPS:-$( { hostname -I 2>/dev/null; ip -4 -o addr show 2>/dev/null | awk '{sub(/\/.*/,"",$4); print $4}'; } | tr ' ' '\n')}"
        cands="$(printf '%s\n' $cands | grep -Ev '^(127\.|169\.254\.|$)' | awk '!s[$0]++')"
        for c in $cands; do is_ipv4 "$c" && ! is_private "$c" && { IP="$c"; break; }; done
        if [ -z "$IP" ]; then
            IP="$(printf '%s\n' $cands | head -1)"
            [ -n "$IP" ] && IP_NOTE="privat adresse - kun naaelig fra samme net. Angiv den offentlige med --ip <adresse>"
        fi
    fi
    is_ipv4 "$IP" || { echo "fandt ingen IP-adresse: angiv den med --ip <adresse>" >&2; exit 2; }
    case "$IP" in 127.*|0.*) echo "$IP er ikke en adresse andre kan naa - angiv serverens IP" >&2; exit 2 ;; esac
    URL="http://$IP:$PORT"; BASE=""; HOST_VALUE="0.0.0.0"
else
    URL="${URL%/}"
    if ! printf '%s' "$URL" | grep -Eq '^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._-]+)+$'; then
        echo "--url skal vaere https://<bruger>.<server>.usbx.me/<sti>, fx https://humle.lw123.usbx.me/cc" >&2
        echo "  (https, ingen anfoerselstegn, en understi) - eller brug --ip for http://<ip>:<port>" >&2
        exit 2
    fi
    BASE="/${URL#https://*/}"
    case "$BASE" in */..*|*/.) echo "stien maa ikke indeholde .. eller ." >&2; exit 2 ;; esac
    HOST_VALUE="127.0.0.1"
fi

NGINX_DIR="${ULTRACC_NGINX_DIR:-$HOME/.apps/nginx/proxy.d}"
NGINX_FILE="$NGINX_DIR/command-center.conf"
TEMPLATE="deploy/nginx-ultracc-proxy.conf"
UNIT_FILE="${CC_SETUP_UNIT_DIR:-$HOME/.config/systemd/user}/command-center.service"
UNIT_SRC="deploy/command-center.user.service"
RESTART_CMD="${CC_SETUP_RESTART_CMD:-bash scripts/restart.sh}"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ "$MODE" = url ]; then
    [ -f "$TEMPLATE" ] || { echo "mangler $TEMPLATE - koer fra en opdateret installation (v7.28+)" >&2; exit 3; }
fi
render_nginx() {   # kun ikke-kommentarlinjer faar ny sti/port
    sed -e "/^[[:space:]]*#/!s#/cc#${BASE}#g" -e "/^[[:space:]]*#/!s#12345#${PORT}#g" "$TEMPLATE"
}
# En enhed fra foer v7.28 har vaert/port skrevet fast og ignorerer .env - den skal skiftes ud.
unit_is_old() { [ -f "$UNIT_FILE" ] && grep -q -- '--host 127.0.0.1 --port 8000' "$UNIT_FILE" && ! grep -q 'CC_HOST' "$UNIT_FILE"; }

TUN_PIDS="$(pgrep -x cloudflared 2>/dev/null | grep -v "^$$\$" || true)"
TUN_UNITS="$(systemctl --user list-units --all --no-legend 2>/dev/null | grep -oiE '[^[:space:]]*cloudflared[^[:space:]]*\.service' | sort -u || true)"
TUN_CRON="$(crontab -l 2>/dev/null | grep -i cloudflared || true)"

echo "== Command Center: login med e-mail og adgangskode, uden Cloudflare =="
echo "   adresse:  $URL/   ($([ "$MODE" = ip ] && echo "direkte paa IP, lytter paa 0.0.0.0:$PORT" || echo "understi $BASE bag nginx, port $PORT"))"
[ -n "$IP_NOTE" ] && echo "   OBS:      $IP_NOTE"
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
for kv in "CC_HOST=$HOST_VALUE" "CC_PORT=$PORT" "CC_PUBLIC_URL=$URL" "CC_FORWARDED_ALLOW_IPS=127.0.0.1"; do
    k="${kv%%=*}"; old="$(envget "$k")"
    if [ "$old" = "${kv#*=}" ]; then echo "   $kv (uaendret)"; else echo "   $k: '${old}' -> '${kv#*=}'"; fi
done
[ -n "$(envget CC_BASE_PATH)" ] && echo "   CC_BASE_PATH: '$(envget CC_BASE_PATH)' -> ''"
echo
echo "3) systemd-enhed: $UNIT_FILE"
if unit_is_old; then echo "   har fast --host 127.0.0.1 --port 8000 (ignorerer .env) -> skiftes til $UNIT_SRC (backup)"
elif [ -f "$UNIT_FILE" ]; then echo "   foelger allerede .env"
else echo "   ingen installeret (appen startes med run.sh/pidfile)"; fi
echo
if [ "$MODE" = url ]; then
    echo "4) nginx: $NGINX_FILE"
    if [ -f "$NGINX_FILE" ] && render_nginx | cmp -s - "$NGINX_FILE"; then
        echo "   findes allerede og er identisk"
    else
        [ -f "$NGINX_FILE" ] && echo "   findes og afviger -> backup $NGINX_FILE.bak-$STAMP"
        render_nginx | grep -vE '^[[:space:]]*(#|$)' | sed 's/^/   | /'
    fi
    echo "   + app-nginx restart$(command -v app-nginx >/dev/null 2>&1 || echo '   (kommandoen findes ikke her - genindlaes nginx selv)')"
else
    echo "4) nginx: bruges ikke (--ip)"
fi
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
        pkill -x cloudflared 2>/dev/null; sleep 1
        pgrep -x cloudflared >/dev/null 2>&1 && pkill -9 -x cloudflared 2>/dev/null
        echo "ok   cloudflared-processer stoppet"
    fi
fi

# 2) .env - kun de fire noegler (og en sat CC_BASE_PATH) aendres; filmode bevares
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
setenv CC_HOST "$HOST_VALUE"; setenv CC_PORT "$PORT"; setenv CC_PUBLIC_URL "$URL"; setenv CC_FORWARDED_ALLOW_IPS 127.0.0.1
[ -n "$(envget CC_BASE_PATH)" ] && setenv CC_BASE_PATH ""
echo "ok   .env opdateret"

# 3) systemd-enheden
if unit_is_old; then
    [ -f "$UNIT_SRC" ] || fail "mangler $UNIT_SRC"
    cp -p "$UNIT_FILE" "$UNIT_FILE.bak-$STAMP" && cp "$UNIT_SRC" "$UNIT_FILE" || fail "kunne ikke skrive $UNIT_FILE"
    systemctl --user daemon-reload 2>/dev/null
    echo "ok   $UNIT_FILE foelger nu .env (backup .bak-$STAMP)"
fi

# 4) nginx (kun --url)
if [ "$MODE" = url ]; then
    mkdir -p "$NGINX_DIR" || fail "kan ikke oprette $NGINX_DIR"
    if ! { [ -f "$NGINX_FILE" ] && render_nginx | cmp -s - "$NGINX_FILE"; }; then
        [ -f "$NGINX_FILE" ] && cp -p "$NGINX_FILE" "$NGINX_FILE.bak-$STAMP"
        render_nginx > "$NGINX_FILE" || fail "kunne ikke skrive $NGINX_FILE"
    fi
    echo "ok   $NGINX_FILE"
    if command -v app-nginx >/dev/null 2>&1; then
        app-nginx restart >/dev/null 2>&1 && echo "ok   app-nginx restart" || fail "app-nginx restart fejlede"
    else
        echo "obs  app-nginx findes ikke - genindlaes nginx selv"
    fi
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
    000|"") if [ "$MODE" = ip ]; then
                echo "FEJL: $URL svarer ikke - lytter appen paa 0.0.0.0 (ss -ltnp | grep :$PORT), og er porten aaben?" >&2
            else echo "FEJL: $URL/login svarer ikke - tjek DNS/certifikat og nginx" >&2; fi; exit 4 ;;
    502|504) echo "FEJL: $URL/login svarer $code - nginx naar ikke appen (port i $NGINX_FILE?)" >&2; exit 4 ;;
    404) echo "FEJL: $URL/login svarer 404 - er nginx genindlaest, og er stien $BASE den samme i blokken?" >&2; exit 4 ;;
    *) echo "FEJL: $URL/login svarer '$code'" >&2; exit 4 ;;
esac
if [ "$MODE" = ip ]; then
    echo
    echo "Aabn $URL/ fra din egen computer. Svarer den ikke dér, men her, blokerer en firewall porten."
    echo "OBS: http uden TLS - adgangskoden sendes ukrypteret. Brug en staerk, unik kode."
fi
echo
echo "Faerdig."
