#!/usr/bin/env bash
#
# scripts/repo-state.sh — single-command git/gh repo state summary (DOG-17)
#
# One read-only run answers "where does this repo stand right now": current
# branch, last 10 commits, local branches already merged to main (prune
# candidates), best-effort CI for the current branch, and the dirty-tree
# summary. Purely informational, in the same spirit as
# `herdr-loop-swarm.sh status` — it replaces no suite or lint gate.
#
# Contract:
#   - Read-only: no writes to the target, never touches .herdr-swarm/.
#   - The branch/commits/merged/dirty sections need no network. Only the
#     ci section may touch it, and every gh failure mode (missing binary,
#     unauthenticated, offline) degrades to one "gh: unavailable" line:
#     a status readout is not a gate and must never fail the whole run
#     over an optional signal.
#   - Usage: scripts/repo-state.sh [dir]   (default: $PWD)

set -euo pipefail

N_COMMITS=10
N_RUNS=5

usage() {
  cat <<EOF
Usage: scripts/repo-state.sh [dir]

Read-only state summary for the git repo at <dir> (default: \$PWD):
branch, last ${N_COMMITS} commits, local branches merged to main,
best-effort CI (gh run list -L ${N_RUNS}), dirty tree.
EOF
}

die() { printf 'repo-state: %s\n' "$1" >&2; exit 1; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
[[ $# -le 1 ]] || { usage >&2; die "too many arguments (expected: [dir])"; }

TARGET="${1:-$PWD}"
[[ -d "$TARGET" ]] || die "target directory does not exist: $TARGET"
TARGET=$(cd "$TARGET" && pwd) || die "cannot resolve target: $TARGET"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "not a git work tree: $TARGET"

section() { printf '\n── %s\n' "$1"; }

if git -C "$TARGET" rev-parse -q --verify HEAD >/dev/null 2>&1; then
  HAS_COMMITS=1
else
  HAS_COMMITS=0
fi
BRANCH=$(git -C "$TARGET" branch --show-current)

printf 'repo: %s\n' "$TARGET"

# ── branch ─────────────────────────────────────────────────────────────────
section "branch"
if [[ -n "$BRANCH" ]]; then
  printf '%s\n' "$BRANCH"
elif (( HAS_COMMITS )); then
  printf 'HEAD (detached at %s)\n' "$(git -C "$TARGET" rev-parse --short HEAD)"
else
  printf '(no commits yet)\n'
fi

# ── commits ────────────────────────────────────────────────────────────────
section "commits (last $N_COMMITS)"
if (( HAS_COMMITS )); then
  git -C "$TARGET" log --oneline "-$N_COMMITS"
else
  printf '(no commits yet)\n'
fi

# ── merged branches ────────────────────────────────────────────────────────
section "merged branches"
if git -C "$TARGET" show-ref --verify --quiet refs/heads/main; then
  MERGED=$(git -C "$TARGET" branch --merged main \
             | sed 's/^[*+ ]*//' | awk '$0 != "main"' || true)
  if [[ -n "$MERGED" ]]; then
    printf '%s\n' "$MERGED" | sed 's/^/  /'
  else
    printf '  (none)\n'
  fi
else
  printf '  (no local main branch)\n'
fi

# ── ci ─────────────────────────────────────────────────────────────────────
section "ci (gh run list -L $N_RUNS)"
if ! command -v gh >/dev/null 2>&1; then
  printf 'gh: unavailable (not on PATH)\n'
elif ! gh auth status >/dev/null 2>&1; then
  printf 'gh: unavailable (not authenticated)\n'
else
  CI_RC=0
  if (( HAS_COMMITS )) && [[ -n "$BRANCH" ]]; then
    CI_OUT=$(cd "$TARGET" && gh run list -L "$N_RUNS" --branch "$BRANCH" 2>/dev/null) \
      || CI_RC=$?
  else
    CI_OUT=$(cd "$TARGET" && gh run list -L "$N_RUNS" 2>/dev/null) \
      || CI_RC=$?
  fi
  if (( CI_RC != 0 )); then
    printf 'gh: unavailable (gh run list failed — offline?)\n'
  elif [[ -z "$CI_OUT" ]]; then
    printf '(no workflow runs)\n'
  else
    printf '%s\n' "$CI_OUT"
  fi
fi

# ── dirty tree ─────────────────────────────────────────────────────────────
section "dirty tree"
DIRTY=$(git -C "$TARGET" status --short)
if [[ -z "$DIRTY" ]]; then
  printf 'clean\n'
else
  printf '%s\n' "$DIRTY"
fi

exit 0
