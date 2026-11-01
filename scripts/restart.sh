#!/bin/bash
# Genstarter Command Center. Bruges af opdateringen (POST /update/apply) og kan koeres manuelt.
#
#   bash scripts/restart.sh              # genstart med det samme
#   bash scripts/restart.sh --delay 2    # vent 2 s (saa HTTP-svaret kan naa frem)
#
# Raekkefoelge:
#   1. UPDATE_RESTART_CMD (hvis sat i .env)
#   2. systemd --user unit "command-center"  (Ultra.cc)
#   3. systemd system unit "command-center"
#   4. pidfile app/data/cc.pid + ./run.sh    (naar appen er startet med ./run.sh)
set -u
cd "$(dirname "$0")/.."

DELAY=0
if [ "${1:-}" = "--delay" ]; then
    DELAY="${2:-2}"
fi
case "$DELAY" in
    ''|*[!0-9]*) DELAY=0 ;;
esac
[ "$DELAY" -gt 0 ] && sleep "$DELAY"

PIDFILE="app/data/cc.pid"
LOG="nohup.out"

restart_systemd_user() {
    systemctl --user cat "$1" > /dev/null 2>&1 || return 1
    systemctl --user restart "$1"
}

restart_systemd_system() {
    systemctl cat "$1" > /dev/null 2>&1 || return 1
    systemctl restart "$1"
}

if [ -n "${UPDATE_RESTART_CMD:-}" ]; then
    echo "Genstarter med UPDATE_RESTART_CMD: $UPDATE_RESTART_CMD"
    # shellcheck disable=SC2086
    eval "$UPDATE_RESTART_CMD"
    exit $?
fi

for unit in command-center steamgears-command-center; do
    if restart_systemd_user "$unit"; then
        echo "Genstartede systemd --user unit '$unit'."
        exit 0
    fi
done

if restart_systemd_system command-center; then
    echo "Genstartede systemd unit 'command-center'."
    exit 0
fi

# Ingen unit: brug pidfile fra run.sh og start appen igen i baggrunden.
if [ -f "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Stopper proces $OLD_PID..."
        kill "$OLD_PID" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$OLD_PID" 2>/dev/null || break
            sleep 0.5
        done
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
fi

echo "Starter appen igen (log: $LOG)..."
nohup ./run.sh >> "$LOG" 2>&1 &
echo "Ny proces startet - foelg opstarten i $LOG"
exit 0
