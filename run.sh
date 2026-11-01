#!/bin/bash
cd "$(dirname "$0")"
if [ -f .env ]; then
    set -a; source .env; set +a
fi
HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
PUBLIC="${CC_PUBLIC_URL:-}"
FORWARDED="${CC_FORWARDED_ALLOW_IPS:-127.0.0.1}"

# Maskinens rigtige IPv4 (bruges naar der lyttes paa 0.0.0.0)
lan_ip() {
    { hostname -I 2>/dev/null | awk '{print $1}'
      ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}'
    } | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt

mkdir -p app/data
echo $$ > app/data/cc.pid   # pidfile: scripts/restart.sh kan genstarte en app startet med ./run.sh
echo "⚡ Starter Command Center v7.11..."
echo "   Lokalt:   http://127.0.0.1:$PORT"
if [ -n "$PUBLIC" ]; then
    echo "   Offentlig: $PUBLIC   (via nginx -> http://$HOST:$PORT)"
    echo "   nginx:    proxy_set_header X-Forwarded-Proto \$scheme;  (ellers bliver cookien ikke Secure)"
fi
case "$HOST" in
    0.0.0.0|::|"")
        echo "   Netvaerk: http://$(lan_ip || echo '<din-ip>'):$PORT   (lytter paa $HOST:$PORT)"
        ;;
    *)
        echo "   Lytter paa $HOST:$PORT — brug CC_HOST=0.0.0.0 for adgang uden nginx"
        ;;
esac
echo "   Login:    opret din bruger ved foerste besoeg (ingen token), derefter brugernavn + adgangskode"

if [ "$DEV" = "1" ]; then
    exec uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips "$FORWARDED" --reload
else
    exec uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips "$FORWARDED"
fi
