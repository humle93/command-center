#!/usr/bin/env bash
# Lægger den fælles AGENTS.md ind i alle repoer under en GitHub-konto — som PR, aldrig direkte på main.
#
#   bash scripts/agents_md_rollout.sh --dry-run          # vis hvad der ville ske, rør intet
#   bash scripts/agents_md_rollout.sh                    # spørg om lov, og kør
#   bash scripts/agents_md_rollout.sh --yes              # uden bekræftelse
#   bash scripts/agents_md_rollout.sh --owner humle93 --only steamgears-site --dry-run
#   bash scripts/agents_md_rollout.sh --owner humle93 --skip thredup-cart-hoarding
#   bash scripts/agents_md_rollout.sh --source ~/AGENTS.md --branch chore/delte-regler
#
# Krav: gh (https://cli.github.com/) logget ind med adgang til repoerne, og git.
# For hvert repo laves branchen (standard: chore/agents-md) med AGENTS.md, og der åbnes en PR.
# Findes filen allerede og er identisk, springes repoet over. Afviger den, springes det også over —
# medmindre du giver --overwrite, så den nye fil erstatter den gamle i PR'en.
set -euo pipefail

OWNER="${OWNER:-humle93}"
BRANCH="${BRANCH:-chore/agents-md}"
SOURCE="${SOURCE:-}"
TITLE="docs: fælles AGENTS.md"
DRY_RUN=0
ASSUME_YES=0
OVERWRITE=0
SKIP_LIST=""
ONLY_LIST=""

read -r -d '' BODY <<'EOF_BODY' || true
Tilføjer en fælles `AGENTS.md`, så agenter (Claude, Codebuff m.fl.) møder de samme regler i alle repoer.

- Afsnit 1-7: generelle regler — roadmap før kode, dokumentation i samme commit, test før commit,
  sikkerhed, sprog, git og pakning.
- Afsnit 8: profil pr. projekttype (WordPress/WooCommerce, Python/FastAPI, frontend).
- Repo-specifikke afsnit tilpasses efter behov; Command Centers egne regler står i afsnit 9 i det repo.

Kun dokumentation — ingen kode, ingen afhængigheder. Ret gerne teksten, hvis repoet har behov den
ikke dækker.
EOF_BODY

usage() {
  cat <<'EOF_USAGE'
Brug: bash scripts/agents_md_rollout.sh [muligheder]

  --owner NAVN       GitHub-konto eller organisation (standard: humle93)
  --source STI       AGENTS.md der skal kopieres (standard: filen i dette repo)
  --branch NAVN      Branchen der laves i hvert repo (standard: chore/agents-md)
  --skip NAVN        Spring repo over; kan gentages eller angives med komma
  --only NAVN        Kør kun disse repoer (fx --only steamgears-site); kan gentages
  --overwrite        Erstat en eksisterende, afvigende AGENTS.md (standard: spring over)
  --dry-run          Vis kun planen; klon, commit og PR springes over
  --yes              Spørg ikke om bekræftelse
  -h, --help         Vis denne hjælp

Eksempler:
  bash scripts/agents_md_rollout.sh --dry-run
  bash scripts/agents_md_rollout.sh --skip command-center,thredup-cart-hoarding
  bash scripts/agents_md_rollout.sh --only steamgears-site --dry-run
EOF_USAGE
}

die() { printf 'Fejl: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)    [ $# -ge 2 ] || die "--owner mangler en værdi"; OWNER="$2"; shift 2 ;;
    --source)   [ $# -ge 2 ] || die "--source mangler en værdi"; SOURCE="$2"; shift 2 ;;
    --branch)   [ $# -ge 2 ] || die "--branch mangler en værdi"; BRANCH="$2"; shift 2 ;;
    --skip)     [ $# -ge 2 ] || die "--skip mangler en værdi"; SKIP_LIST="$SKIP_LIST,$2"; shift 2 ;;
    --only)     [ $# -ge 2 ] || die "--only mangler en værdi"; ONLY_LIST="$ONLY_LIST,$2"; shift 2 ;;
    --overwrite) OVERWRITE=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --yes)      ASSUME_YES=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          printf 'Ukendt argument: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || die "gh mangler — installér https://cli.github.com/ og kør 'gh auth login'"
command -v git >/dev/null 2>&1 || die "git mangler"
gh auth status >/dev/null 2>&1 || die "gh er ikke logget ind — kør 'gh auth login' først (og vælg repo-adgang)"

if [ -z "$SOURCE" ]; then
  SOURCE="$(cd "$(dirname "$0")/.." && pwd)/AGENTS.md"
fi
[ -f "$SOURCE" ] || die "kan ikke finde kilden: $SOURCE"
SOURCE="$(cd "$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"

in_list() {
  local list="$1" repo="$2" name entry
  name="${repo#*/}"
  # shellcheck disable=SC2086
  for entry in $(printf '%s' "$list" | tr ',' ' '); do
    [ -n "$entry" ] || continue
    if [ "$entry" = "$repo" ] || [ "$entry" = "$name" ]; then return 0; fi
  done
  return 1
}

printf 'Kilde:  %s\n' "$SOURCE"
printf 'Konto:  %s\n' "$OWNER"
printf 'Branch: %s\n' "$BRANCH"
[ "$DRY_RUN" -eq 1 ] && printf 'Tilstand: tørkørsel (intet pushes, ingen PR oprettes)\n'
printf '\n'

# Måske er feltet defaultBranchRef null for tomme repoer; derfor falder vi tilbage til main.
REPOS="$(gh repo list "$OWNER" --limit 200 \
  --json nameWithOwner,isArchived,isFork,viewerPermission,defaultBranchRef \
  --jq '.[] | select(.isArchived == false) | select(.isFork == false)
        | select(.viewerPermission == "ADMIN" or .viewerPermission == "MAINTAIN" or .viewerPermission == "WRITE")
        | "\(.nameWithOwner)\t\(.defaultBranchRef.name // "main")"')" \
  || die "kunne ikke hente repo-listen for $OWNER (mangler gh adgang?)"

[ -n "$REPOS" ] || die "fandt ingen repoer under $OWNER med skriveadgang"

if [ -n "$ONLY_LIST" ]; then
  filtered=""
  while IFS=$'\t' read -r repo base; do
    [ -n "${repo:-}" ] || continue
    if in_list "$ONLY_LIST" "$repo"; then filtered+="$repo"$'\t'"$base"$'\n'; fi
  done <<< "$REPOS"
  REPOS="${filtered%$'\n'}"
  [ -n "$REPOS" ] || die "ingen af repoerne i --only ($(printf '%s' "$ONLY_LIST" | sed 's/^,//')) blev fundet med skriveadgang"
fi

TOTAL=$(printf '%s\n' "$REPOS" | wc -l | tr -d ' ')
printf 'Fandt %s repo(er) med skriveadgang.\n\n' "$TOTAL"

if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
  printf 'Kør mod %s repo(er)? [j/N] ' "$TOTAL"
  read -r reply
  case "$reply" in
    j|J|ja|JA|y|Y|yes) ;;
    *) echo "Afbrudt."; exit 0 ;;
  esac
fi

git_name="$(git config --global user.name 2>/dev/null || true)"
git_email="$(git config --global user.email 2>/dev/null || true)"
git_name="${git_name:-AGENTS.md rollout}"
git_email="${git_email:-agents-md@localhost.invalid}"

created=0
skipped=0
failed=0
PR_URLS=""

while IFS=$'\t' read -r repo base; do
  [ -n "${repo:-}" ] || continue
  short="${repo#*/}"

  if in_list "$SKIP_LIST" "$repo"; then
    printf -- '- %-30s sprunget over (--skip)\n' "$short"
    skipped=$((skipped + 1))
    continue
  fi

  work="$(mktemp -d "${TMPDIR:-/tmp}/agents-md.XXXXXX")"

  if ! gh repo clone "$repo" "$work/src" -- --depth 1 --quiet 2>"$work/clone.err"; then
    printf -- '- %-30s FEJL: kunne ikke klone\n' "$short"
    sed 's/^/    /' "$work/clone.err" >&2 || true
    failed=$((failed + 1)); rm -rf "$work"; continue
  fi

  target="$work/src/AGENTS.md"
  action="opret"
  if [ -f "$target" ]; then
    if cmp -s "$SOURCE" "$target"; then
      printf -- '- %-30s findes allerede og er identisk\n' "$short"
      skipped=$((skipped + 1)); rm -rf "$work"; continue
    fi
    if [ "$OVERWRITE" -eq 0 ]; then
      printf -- '- %-30s AGENTS.md findes og afviger — sprunget over (brug --overwrite)\n' "$short"
      skipped=$((skipped + 1)); rm -rf "$work"; continue
    fi
    action="erstat"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf -- '- %-30s ville %s AGENTS.md og åbne PR mod %s\n' "$short" "$action" "$base"
    created=$((created + 1)); rm -rf "$work"; continue
  fi

  push_status=0
  (
    cd "$work/src"
    if git fetch -q origin "$BRANCH" 2>/dev/null; then
      # Branchen findes i forvejen (fx et tidligere forsøg): byg ovenpå den, så intet går tabt.
      git checkout -q -B "$BRANCH" FETCH_HEAD
    else
      git checkout -q -b "$BRANCH"
    fi
    cp "$SOURCE" AGENTS.md
    git add AGENTS.md
    if git diff --cached --quiet; then exit 3; fi
    git -c user.name="$git_name" -c user.email="$git_email" \
      commit -q -m "docs: tilføj fælles AGENTS.md" \
      -m "Samme regler som de øvrige repoer: roadmap før kode, dokumentation i samme commit, test før commit, sikkerhed, sprog, git og pakning — plus profil pr. projekttype."
    git push -q -u origin "$BRANCH"
  ) 2>"$work/push.err" || push_status=$?

  if [ "$push_status" -eq 3 ]; then
    existing="$(gh pr view "$BRANCH" --repo "$repo" --json url --jq '.url' 2>/dev/null || true)"
    printf -- '- %-30s branchen er allerede opdateret%s\n' "$short" "${existing:+ — $existing}"
    if [ -n "$existing" ]; then PR_URLS="$PR_URLS$existing"$'\n'; fi
    skipped=$((skipped + 1)); rm -rf "$work"; continue
  fi

  if [ "$push_status" -ne 0 ]; then
    printf -- '- %-30s FEJL: kunne ikke committe/pushe\n' "$short"
    if [ -s "$work/push.err" ]; then sed 's/^/    /' "$work/push.err" >&2; fi
    failed=$((failed + 1)); rm -rf "$work"; continue
  fi

  url="$(gh pr create --repo "$repo" --head "$BRANCH" --base "$base" \
          --title "$TITLE" --body "$BODY" 2>"$work/pr.err" || true)"
  if [ -z "$url" ]; then
    url="$(gh pr view "$BRANCH" --repo "$repo" --json url --jq '.url' 2>/dev/null || true)"
  fi

  if [ -n "$url" ]; then
    printf -- '- %-30s %s: %s\n' "$short" "$action" "$url"
    PR_URLS="$PR_URLS$url"$'\n'
    created=$((created + 1))
  else
    printf -- '- %-30s FEJL: branchen er pushet, men PR kunne ikke oprettes\n' "$short"
    sed 's/^/    /' "$work/pr.err" 2>/dev/null >&2 || true
    failed=$((failed + 1))
  fi

  rm -rf "$work"
done <<< "$REPOS"

printf '\nOpsummering: %s klargjort, %s sprunget over, %s fejlet.\n' "$created" "$skipped" "$failed"
if [ -n "$PR_URLS" ]; then
  printf '\nPull requests:\n%s' "$PR_URLS"
fi
if [ "$DRY_RUN" -eq 1 ]; then
  printf '\nTørkørsel — intet er pushet. Kør igen uden --dry-run for at gennemføre.\n'
fi
[ "$failed" -eq 0 ] || exit 1
