#!/usr/bin/env bash
# update.sh - opdaterer Command Center fra GitHub: tjek -> filer (med DB-backup) -> requirements ->
# genstart.
#
# Brug:
#   bash scripts/update.sh              # opdater + genstart, vent til /health svarer
#   bash scripts/update.sh --no-restart # opdater, men genstart selv bagefter
#   bash scripts/update.sh --check      # kun tjek, skriv intet
#   bash scripts/update.sh --version    # sammenlign de tre versioner og stop med kode 1 ved uenighed
#
# Viser foerst hvilken version der koerer (/health) ved siden af filernes og installatoerens, og hvor
# man logger ind (CC_PUBLIC_URL via nginx). --version er den strenge kontrol: den stopper med kode 1,
# hvis en gammel install.sh eller en manglende genstart kan snige sig ind. Opdateringen selv skriver
# intet, hvis install.sh paa disken er aeldre end koden (kode 7) - hent den fra git foerst.
# Koerer appens funktioner direkte i venv'en - ingen token eller login.
# Kraever: venv (./venv) og GITHUB_TOKEN i .env til opdateringen; --version kraever ingen af dem.
# Sidst aendret: 4. november 2026
set -u
cd "$(dirname "$0")/.."

if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Hjaelpen er header-kommentarerne efter shebang: retter man dem, retter man hjaelpen.
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

MODE="apply"
case "${1:-}" in
    --no-restart) MODE="apply-no-restart" ;;
    --check) MODE="check" ;;
    --version) MODE="version" ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "Ukendt argument: $1 (brug --version, --check, --no-restart eller -h)" >&2; exit 64 ;;
esac

HOST="${CC_HOST:-127.0.0.1}"
PORT="${CC_PORT:-8000}"
case "$HOST" in
    0.0.0.0|::|"") PROBE=127.0.0.1 ;;
    *) PROBE="$HOST" ;;
esac
BASE="http://$PROBE:$PORT"

# ---------- Version: filer, proces og installatoer ----------
# Tre kilder kan vaere uenige, og alle tre kan snige sig ind: app/main.py (det der ligger paa disken),
# /health (den proces der svarer lige nu) og install.sh (installatoeren nogen maaske koerer bagefter og
# overskriver det hele med). --version tjekker alle tre og stopper med kode 1 ved uenighed.
RUN=""; FILE=""; INST=""
login_url() { local b="${CC_PUBLIC_URL:-$BASE}"; echo "${b%/}/login"; }
file_version() { sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' app/main.py 2>/dev/null | head -1; }
# Versionen af den proces der svarer - laeses ud af JSON uden python, saa --version ogsaa virker uden venv.
running_version() {
    curl -sf --max-time 3 "$BASE/health" 2>/dev/null \
        | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}
# Versionen installatoeren vil skrive: APP_VERSION i install.sh's indlejrede app/main.py. Linjen staar
# i spalte 0 i den indlejrede fil, saa den findes uden at parse heredocs (og uden at skrive
# heredoc-markoeren her - den streng leder paritetstjekket i CI efter).
installer_version() {
    [ -f install.sh ] || return 0
    sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' install.sh 2>/dev/null | head -1
}
read_versions() { RUN="$(running_version)"; FILE="$(file_version)"; INST="$(installer_version)"; }
# 0 hvis $1 er nyere end $2 - sammenlignet tal for tal, saa 7.9 er aeldre end 7.17.
ver_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x,".");m=split(b,y,".");k=(n>m?n:m)
        for(i=1;i<=k;i++){if(x[i]+0>y[i]+0)exit 0; if(x[i]+0<y[i]+0)exit 1} exit 1}'
}
# Etiketterne har selv deres polstring (13 tegn): printf '%-13s' taelier bytes, ikke tegn, saa de
# danske bogstaver skubbede kolonnen ud af flugt.
ver_row() { if [ -n "$2" ]; then echo "   $1v$2   ($3)"; else echo "   $1ukendt   ($3)"; fi; }
version_rows() {
    ver_row "kører nu:    " "$RUN" "processen, fra $BASE/health"
    ver_row "filer:       " "$FILE" "app/main.py på disken"
    if [ -f install.sh ]; then
        ver_row "installatør: " "$INST" "install.sh, indlejret app/main.py"
    else
        echo "   installatør:  ingen install.sh i denne mappe"
    fi
}
# Forklarer uenigheden i klartekst; ingen linjer betyder at alt stemmer. Kode 1 = der er en forskel.
version_diff() {
    local bad=0
    if [ -z "$RUN" ]; then
        echo "   forskel:     processen svarer ikke på $BASE/health - kan ikke sammenlignes"
        bad=1
    elif [ -n "$FILE" ] && [ "$RUN" != "$FILE" ]; then
        if ver_gt "$FILE" "$RUN"; then
            echo "   forskel:     filerne er nyere end processen - genstart mangler (bash scripts/restart.sh)"
        else
            echo "   forskel:     processen kører nyere kode end filerne - filerne er rullet tilbage, kør opdateringen igen"
        fi
        bad=1
    fi
    if [ -n "$INST" ] && [ -n "$FILE" ] && [ "$INST" != "$FILE" ]; then
        if ver_gt "$INST" "$FILE"; then
            echo "   forskel:     install.sh er nyere end koden - kør den for at skrive de nye filer"
        else
            echo "   forskel:     install.sh er ældre (v$INST) end koden (v$FILE) - kør den IKKE; den overskriver app/main.py med den gamle version. Hent den fra git (git checkout -- install.sh eller git pull); opdateringen nægter selv at skrive, indtil den er rettet."
        fi
        bad=1
    fi
    return $bad
}
show_versions() {
    read_versions
    echo "Command Center"
    version_rows
    version_diff || true
    if [ -n "${CC_PUBLIC_URL:-}" ]; then
        echo "   login:       $(login_url)   (via nginx)"
    else
        echo "   login:       $(login_url)   (lokal adresse - sæt CC_PUBLIC_URL i .env for den offentlige)"
    fi
    echo
}
# Den strenge kontrol: kode 0 kun naar alle tre kilder svarer med samme version.
version_check() {
    read_versions
    echo "Command Center - versionskontrol"
    version_rows
    if version_diff; then
        [ -n "$FILE" ] || { echo "❌ Kan ikke læse APP_VERSION fra app/main.py."; exit 1; }
        echo "✅ Alle kilder stemmer: v$FILE."
        exit 0
    fi
    echo
    echo "❌ Versionskontrol fejlede - se 'forskel' ovenfor."
    exit 1
}

if [ "$MODE" = "version" ]; then
    version_check
fi

# ---------- Guard foer skrivning: en installatoer der ruller koden tilbage ----------
# install.sh skriver app/main.py med den version der ligger indlejret i den selv. Er den aeldre end
# koden paa disken, rulles koden tilbage hvis nogen koerer den. Derfor skrives der ikke filer oven paa
# en saadan installation: stop foerst, ret installatoren, koer igen. Kode 7 = naegtet, intet er roert.
installer_guard() {
    local inst file
    inst="$(installer_version)"; file="$(file_version)"
    [ -n "$inst" ] && [ -n "$file" ] || return 0
    ver_gt "$file" "$inst" || return 0
    echo "❌ Stopper før der bliver skrevet filer: install.sh på disken er ældre (v$inst) end koden (v$file)."
    echo "   Den installatør ville overskrive app/main.py med v$inst, hvis nogen kørte den nu."
    echo "   Hent den rette version først:   git checkout -- install.sh   (eller git pull)"
    echo "   Intet er ændret - kør scriptet igen bagefter. (--check og --version skriver intet og virker stadig.)"
    exit 7
}
case "$MODE" in
    apply|apply-no-restart) installer_guard ;;
esac

PY="./venv/bin/python"
if [ ! -x "$PY" ]; then
    echo "❌ venv mangler ($PY) - start appen en gang med ./run.sh foerst." >&2
    exit 2
fi

show_versions

# Et felt ud af JSON paa stdin ("None" -> tom)
field() { "$PY" -c 'import json,sys;d=json.load(sys.stdin);v=d.get(sys.argv[1]);print("" if v is None else v)' "$1"; }
count() { "$PY" -c 'import json,sys;print(len(json.load(sys.stdin).get(sys.argv[1]) or []))' "$1"; }
req_line() {
    "$PY" -c 'import json,sys;d=json.load(sys.stdin).get("requirements_install") or {};print(("OK" if d.get("ok") else "FEJL")+": "+(d.get("output") or "")[:200])'
}

echo "→ Tjekker GitHub..."
CHECK="$("$PY" -c 'import json;from app import main;print(json.dumps(main.update_check_sync(), ensure_ascii=False))')"
[ -n "$CHECK" ] || { echo "❌ Tomt svar fra tjekket." >&2; exit 3; }

echo "   installeret: $(printf '%s' "$CHECK" | field current)"
echo "   nyeste:      $(printf '%s' "$CHECK" | field latest)  $(printf '%s' "$CHECK" | field message)"
if [ "$(printf '%s' "$CHECK" | field ok)" != "True" ]; then
    echo "❌ Tjekket fejlede: $(printf '%s' "$CHECK" | field error)" >&2
    exit 4
fi
if [ "$(printf '%s' "$CHECK" | field behind)" != "True" ]; then
    echo "✅ Du kører nyeste version."
    exit 0
fi
if [ "$MODE" = "check" ]; then
    echo "⬆️  Ny version tilgængelig."
    exit 0
fi

echo "→ Henter og skriver filer (DB-backup foerst, requirements installeres hvis de er aendret)..."
RESULT="$("$PY" -c 'import json;from app import main;print(json.dumps(main.update_apply_sync(), ensure_ascii=False))')"
[ -n "$RESULT" ] || { echo "❌ Tomt svar fra opdateringen." >&2; exit 5; }

echo "   ok:           $(printf '%s' "$RESULT" | field ok)"
echo "   filer:        $(printf '%s' "$RESULT" | count files)"
echo "   requirements: $(printf '%s' "$RESULT" | req_line)"
if [ "$(printf '%s' "$RESULT" | field ok)" != "True" ]; then
    echo "❌ Opdateringen fejlede: $(printf '%s' "$RESULT" | field error)" >&2
    exit 5
fi

if [ "$MODE" = "apply-no-restart" ]; then
    echo "✅ Filer opdateret til v$(file_version) (processen kører stadig den gamle). Genstart selv: bash scripts/restart.sh"
    exit 0
fi

echo "→ Genstarter..."
bash scripts/restart.sh || { echo "❌ Genstart fejlede - se logs." >&2; exit 6; }
echo "→ Venter paa at appen svarer igen..."
for _ in $(seq 1 60); do
    sleep 1
    if curl -sf -o /dev/null --max-time 3 "$BASE/health"; then
        echo "✅ Opdateret og genstartet - $BASE svarer igen."
        echo "   kører nu:    v$(running_version)"
        echo "   login:       $(login_url)"
        exit 0
    fi
done
echo "⚠️  Appen svarede ikke inden 60 s. Se logs: journalctl --user -u command-center (eller nohup.out)" >&2
exit 6
