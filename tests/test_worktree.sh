#!/usr/bin/env bash
# tests/test_worktree.sh — automated suite for lib/worktree.sh (P2-1)
# Runs against an ephemeral scratch git repo in /tmp/test-wt-$$ and cleans up
# after itself. Exit 0 = all assertions pass.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
# shellcheck disable=SC2034  # vars are consumed inside those eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-wt-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)   # physical: match git porcelain output
REPO="$TEST_DIR/repo"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()   { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# shellcheck disable=SC1091  # sibling lib under test
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/worktree.sh"

echo "── worktree lifecycle suite (scratch: $REPO)"

# ── fixture: scratch repo with a commit and ignored swarm dir ──────────────
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "baseline"
printf '.herdr-swarm/\n' > "$REPO/.gitignore"
git -C "$REPO" add .gitignore
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "ignore swarm dir"
BASE_SHA=$(git -C "$REPO" rev-parse --short HEAD)

# ── 1. provision ───────────────────────────────────────────────────────────
OUT=$(worktree_provision arch-probe myproj HEAD "$REPO" 2>/dev/null)
WT=$(sed -n 1p <<<"$OUT")
BR=$(sed -n 2p <<<"$OUT")
check "provision returns worktree path under .herdr-swarm/worktrees/" \
  '[[ "$WT" == "$REPO/.herdr-swarm/worktrees/arch-probe" ]]'
check "provision returns branch swarm/<slug>/<seat>" \
  '[[ "$BR" == "swarm/myproj/arch-probe" ]]'
check "worktree directory exists" '[[ -d "$WT" ]]'
check "branch exists at base" \
  '[[ "$(git -C "$REPO" rev-parse --short "$BR")" == "$BASE_SHA" ]]'
check "worktree is LOCKED (porcelain)" \
  'worktree_is_locked "$WT" "$REPO"'
check "lock reason recorded (seated: seat)" \
  'git -C "$REPO" worktree list --porcelain | grep -A3 "^worktree $WT\$" | grep -q "locked seated: arch-probe"'
check "locked worktree survives git worktree prune" \
  'git -C "$REPO" worktree prune >/dev/null 2>&1; worktree_is_locked "$WT" "$REPO"'

# ── 2. prune (clean tree) ──────────────────────────────────────────────────
worktree_prune arch-probe myproj 0 "$REPO" 2>/dev/null
check "clean prune removes the worktree" '[[ ! -d "$WT" ]]'
check "clean prune RETAINS the seat branch (ADR 0006 §D)" \
  'git -C "$REPO" rev-parse --verify --quiet "refs/heads/$BR" >/dev/null'
check "no checkpoint branch from a clean prune" \
  '! git -C "$REPO" for-each-ref -- "refs/heads/swarm/myproj/arch-probe-checkpoint-*" | grep -q .'

# ── 3. prune (dirty tracked edit, no force → checkpoint) ───────────────────
OUT=$(worktree_provision dirty-probe myproj HEAD "$REPO" 2>/dev/null)
WT2=$(sed -n 1p <<<"$OUT")
printf '\n# operator edit\n' >> "$WT2/.gitignore"   # TRACKED modification
printf 'disposable untracked\n' > "$WT2/scratch.txt"
worktree_prune dirty-probe myproj 0 "$REPO" 2>/dev/null
check "dirty prune removes the worktree" '[[ ! -d "$WT2" ]]'
check "dirty prune leaves dirty-probe branch" \
  'git -C "$REPO" rev-parse --verify --quiet "refs/heads/swarm/myproj/dirty-probe" >/dev/null'
check "dirty prune creates checkpoint branch" \
  'git -C "$REPO" for-each-ref --format="%(refname:short)" -- "refs/heads/swarm/myproj/dirty-probe-checkpoint-*" | grep -q .'
CP_BRANCH=$(git -C "$REPO" for-each-ref --format="%(refname:short)" \
  -- "refs/heads/swarm/myproj/dirty-probe-checkpoint-*" | head -n1)
check "checkpoint preserves the tracked edit" \
  'git -C "$REPO" show "$CP_BRANCH:.gitignore" | grep -q "# operator edit"'

# ── 4. prune forced dirty (no checkpoint expected) ─────────────────────────
OUT=$(worktree_provision forced-probe myproj HEAD "$REPO" 2>/dev/null)
WT3=$(sed -n 1p <<<"$OUT")
printf 'discard me\n' >> "$WT3/.gitignore"
worktree_prune forced-probe myproj 1 "$REPO" 2>/dev/null
check "forced dirty prune removes the worktree" '[[ ! -d "$WT3" ]]'
check "forced prune creates NO checkpoint branch" \
  '! git -C "$REPO" for-each-ref -- "refs/heads/swarm/myproj/forced-probe-checkpoint-*" | grep -q .'

# ── 5. parallel provisioning smoke (advisory P2-1 done-when) ───────────────
pids=()
for i in 1 2 3 4 5; do
  worktree_provision "par-$i" myproj HEAD "$REPO" >/dev/null 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=$((fail + 1)); done
check "5 concurrent provisions all succeed" '(( fail == 0 ))'
check "5 parallel worktrees + branches all present" '
  n_ok=0
  for i in 1 2 3 4 5; do
    [[ -d "$REPO/.herdr-swarm/worktrees/par-$i" ]] \
      && git -C "$REPO" rev-parse --verify --quiet "refs/heads/swarm/myproj/par-$i" >/dev/null \
      && n_ok=$((n_ok + 1))
  done
  (( n_ok == 5 ))'
for i in 1 2 3 4 5; do worktree_prune "par-$i" myproj 1 "$REPO" >/dev/null 2>&1; done

# ── 6. reconcile cleans stale admin entries ────────────────────────────────
OUT=$(worktree_provision stale-probe myproj HEAD "$REPO" 2>/dev/null)
WT4=$(sed -n 1p <<<"$OUT")
rm -rf "$WT4"                                  # simulate crash: dir vanished
worktree_reconcile "$REPO" 2>/dev/null
check "LOCKED stale entry survives prune (lock = live-seat marker)" \
  'git -C "$REPO" worktree list --porcelain | grep -q "^worktree $WT4\$"'
git -C "$REPO" worktree unlock "$WT4" >/dev/null 2>&1 || true   # agent gone
worktree_reconcile "$REPO" 2>/dev/null
check "unlocked stale entry is pruned" \
  '! git -C "$REPO" worktree list --porcelain | grep -q "^worktree $WT4\$"'
check "stale-probe branch survives reconcile" \
  'git -C "$REPO" rev-parse --verify --quiet "refs/heads/swarm/myproj/stale-probe" >/dev/null'

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
