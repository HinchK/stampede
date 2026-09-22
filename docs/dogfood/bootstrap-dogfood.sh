#!/usr/bin/env bash
set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE="$SRC_DIR/docs/dogfood"
DOGFOOD_DIR="${1:-$HOME/Fun/stampede-dogfood}"
GH_REPO="${DOGFOOD_GH_REPO:-HinchK/stampede}"

say() { printf '  %s\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
die() { printf '  \033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

printf '\n\033[1mStampede dogfood bootstrap\033[0m\n'
say "source (orchestration, never mutated): $SRC_DIR"
say "target (all work happens here):        $DOGFOOD_DIR"
printf '\n'

[[ "$(cd "$DOGFOOD_DIR" 2>/dev/null && pwd || echo _)" != "$SRC_DIR" ]] \
  || die "target == source: agents would rewrite the code the supervisor is executing"

if ! python3 -c 'import tomllib' 2>/dev/null; then
  printf '\n  \033[31m✖ python3 on PATH lacks tomllib (needs >= 3.11)\033[0m\n'
  say "found $(python3 --version 2>&1) at $(command -v python3)"
  say "This is the very defect DOG-1 fixes, and it blocks the swarm from starting."
  say "Fix this shell first, then re-run:    export PATH=\"/opt/homebrew/bin:\$PATH\""
  die "interpreter precondition not met"
fi
ok "python3 $(python3 -c 'import sys;print(".".join(map(str,sys.version_info[:3])))') has tomllib"

if [[ -e "$DOGFOOD_DIR" ]]; then
  [[ "${DOGFOOD_FORCE:-0}" == "1" ]] || die "target exists: $DOGFOOD_DIR (DOGFOOD_FORCE=1 to replace)"
  say "target exists, DOGFOOD_FORCE=1, removing"
  rm -rf "$DOGFOOD_DIR"
fi

git clone --quiet "$SRC_DIR" "$DOGFOOD_DIR"
ok "cloned local HEAD $(git -C "$DOGFOOD_DIR" rev-parse --short HEAD) (origin/main on GitHub is 39 behind)"

git -C "$DOGFOOD_DIR" remote set-url origin "https://github.com/${GH_REPO}.git"
git -C "$DOGFOOD_DIR" remote add local-source "$SRC_DIR" 2>/dev/null || true
ok "origin -> github.com/${GH_REPO}; a local-path origin would fail detect_repo closed"

mkdir -p "$DOGFOOD_DIR/.herdr-swarm"
cat > "$DOGFOOD_DIR/.herdr-swarm/profile.env" << PROFILE
REPO="${GH_REPO}"
TEST_CMD="make test"
ECOSYSTEM="make"
DOCS_DIR="docs"
PROFILE
ok 'seeded .herdr-swarm/profile.env (TEST_CMD="make test")'

TIX="$DOGFOOD_DIR/maps/tickets"
PARKED="$DOGFOOD_DIR/maps/tickets-parked"
STAGED="$DOGFOOD_DIR/maps/tickets-staged"
mkdir -p "$PARKED" "$STAGED"

parked=0
for f in "$TIX"/*.md; do
  case "$(sed -n 's/^status: //p' "$f" | head -1)" in
    backlog|ready|in_progress) git -C "$DOGFOOD_DIR" mv "maps/tickets/$(basename "$f")" \
                                 "maps/tickets-parked/$(basename "$f")" && parked=$((parked+1)) ;;
  esac
done
ok "parked ${parked} pre-existing pullable tickets so the looper cannot pull P3-4 instead of DOG-1"

cp "$HERE/public-readiness.md" "$DOGFOOD_DIR/maps/public-readiness.md"
cp "$HERE"/tickets/*.md "$STAGED/"
mv "$STAGED/python-interpreter-resolver.md" "$TIX/"
n_staged=$(find "$STAGED" -name '*.md' | wc -l | tr -d ' ')
ok "wave 1 live in maps/tickets/ (DOG-1); ${n_staged} later tickets held in maps/tickets-staged/"
say "gating is by FILE PRESENCE, not status: 'blocked' is an unknown status that"
say "lib/partition.sh:198 treats as ACTIVE, which would hold a phantom lease."

if [[ -d "$DOGFOOD_DIR/docs/dogfood" ]]; then
  git -C "$DOGFOOD_DIR" rm -r -q --ignore-unmatch docs/dogfood
  rm -rf "$DOGFOOD_DIR/docs/dogfood"
  ok "removed docs/dogfood from the clone so agents cannot read ahead of the wave"
fi

git -C "$DOGFOOD_DIR" add -A maps docs
git -C "$DOGFOOD_DIR" -c user.email=dogfood@local -c user.name=dogfood \
  commit -q -m "chore: stage public-readiness dogfood backlog; park in-flight tickets"
ok "committed: root tree clean (a dirty root makes arbiter promote refuse)"

printf '\n  establishing the baseline gate in the clone\n'
if ( cd "$DOGFOOD_DIR" && make check >/tmp/dogfood-gate.log 2>&1 ); then
  ok "make check GREEN in the clone — baseline established"
else
  printf '  \033[33m! make check RED in the clone\033[0m (see /tmp/dogfood-gate.log)\n'
  say "Baseline must be green before starting the loop, or every verdict will be RED."
fi

printf '\n\033[1mNext:\033[0m docs/dogfood/STAMPEDE-DOGFOOD-PLAN.md section 4 to launch.\n\n'
