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
# shellcheck disable=SC1091  # sibling lib under teardown test
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/lifecycle.sh"

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

# ── 5. parallel provisioning smoke (P3-FLAKE-1: N=12 under the advisory lock)
pids=()
for i in $(seq 1 12); do
  worktree_provision "par-$i" myproj HEAD "$REPO" >/dev/null 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=$((fail + 1)); done
check "12 concurrent provisions all succeed" '(( fail == 0 ))'
check "12 parallel worktrees + branches all present" '
  n_ok=0
  for i in $(seq 1 12); do
    [[ -d "$REPO/.herdr-swarm/worktrees/par-$i" ]] \
      && git -C "$REPO" rev-parse --verify --quiet "refs/heads/swarm/myproj/par-$i" >/dev/null \
      && n_ok=$((n_ok + 1))
  done
  (( n_ok == 12 ))'
check "no branch-without-worktree orphans after the storm" '
  n_orphan=0
  for i in $(seq 1 12); do
    git -C "$REPO" rev-parse --verify --quiet "refs/heads/swarm/myproj/par-$i" >/dev/null \
      && [[ ! -d "$REPO/.herdr-swarm/worktrees/par-$i" ]] && n_orphan=$((n_orphan + 1))
  done
  (( n_orphan == 0 ))'
for i in $(seq 1 12); do worktree_prune "par-$i" myproj 1 "$REPO" >/dev/null 2>&1; done

# ── 5b. advisory lock blocks, then is acquired after release ───────────────
mkdir -p "$REPO/.herdr-swarm/provision.lock"
sleep 1 & LOCK_HOLDER=$!
printf '%s\n' "$LOCK_HOLDER" > "$REPO/.herdr-swarm/provision.lock/pid"
t0=$(date +%s%N 2>/dev/null || date +%s)
OUT=$(worktree_provision lockblock myproj HEAD "$REPO" 2>/dev/null)
t1=$(date +%s%N 2>/dev/null || date +%s)
blocked_ms=$(( (t1 - t0) / 1000000 ))
wait "$LOCK_HOLDER" 2>/dev/null || true
if [[ -d "$REPO/.herdr-swarm/worktrees/lockblock" ]]; then
  if (( blocked_ms >= 400 )); then
    ok "live-holder lock blocks second provision, then acquires (${blocked_ms}ms wait)"
  else
    bad "lock blocking (${blocked_ms}ms — acquired too early?)"
  fi
else
  bad "lock blocking (provision failed)"
fi
worktree_prune lockblock myproj 1 "$REPO" >/dev/null 2>&1

# ── 5c. dead-pid stale lock is broken with a warning ───────────────────────
mkdir -p "$REPO/.herdr-swarm/provision.lock"
sleep 5 & DEAD_PID=$!
kill "$DEAD_PID" 2>/dev/null || true
wait "$DEAD_PID" 2>/dev/null || true
printf '%s\n' "$DEAD_PID" > "$REPO/.herdr-swarm/provision.lock/pid"
LOCK_OUT=$(worktree_provision lockstale myproj HEAD "$REPO" 2>&1 >/dev/null || true)
if [[ -d "$REPO/.herdr-swarm/worktrees/lockstale" ]] \
   && printf '%s' "$LOCK_OUT" | grep -q "stale provision lock"; then
  ok "dead-pid lock broken with warning; provision proceeds"
else
  bad "stale lock recovery (dir exists: $([[ -d $REPO/.herdr-swarm/worktrees/lockstale ]] && echo yes || echo no))"
fi
worktree_prune lockstale myproj 1 "$REPO" >/dev/null 2>&1

# ── 5d. idempotent retry: first `worktree add -b` fails after creating the
# branch (simulated via a fail-once git stub) — retry re-evaluates, attaches,
# and the worktree registers on the expected branch ─────────────────────────
STUB="$TEST_DIR/gitstub"; mkdir -p "$STUB"
cat > "$STUB/git" <<'STUBEOF'
#!/bin/sh
# fail-once / fail-all worktree-add wrapper (P3-FLAKE-1 test double)
real=/usr/bin/git
case "$*" in
  *"worktree add"*)
    if [ "$GIT_STUB_MODE" = "failall" ]; then
      case "$*" in *" -b "*) stub_create_branch=1 ;; esac
    else
      case "$*" in
        *" -b "*)
          [ -f "$STUB_MARKER" ] && exec "$real" "$@"
          touch "$STUB_MARKER"
          stub_create_branch=1
          ;;
      esac
    fi
    if [ -n "$stub_create_branch" ]; then
      # simulate git's observed failure mode: create the branch, then die
      set -- "$@"
      dir=""; br=""; base=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -C) dir=$2; shift 2 ;;
          -b) br=$2; shift 2 ;;
          add|worktree) shift ;;
          *) base=$1; shift ;;
        esac
      done
      [ -n "$br" ] && "$real" -C "$dir" branch "$br" "${base:-HEAD}" >/dev/null 2>&1 || true
      echo "stub: simulated worktree add failure (branch $br created)" >&2
      exit 1
    fi
    [ "$GIT_STUB_MODE" = "failall" ] && { echo "stub: simulated worktree add failure" >&2; exit 1; }
    ;;
esac
exec "$real" "$@"
STUBEOF
chmod +x "$STUB/git"
rm -f "$TEST_DIR/stub-marker"
STUB_MARKER="$TEST_DIR/stub-marker" PATH="$STUB:$PATH" \
  worktree_provision retrycoll myproj HEAD "$REPO" >/dev/null 2>&1
if [[ -d "$REPO/.herdr-swarm/worktrees/retrycoll" ]] \
   && [[ "$(git -C "$REPO/.herdr-swarm/worktrees/retrycoll" rev-parse --abbrev-ref HEAD)" == "swarm/myproj/retrycoll" ]]; then
  ok "fail-once add: retry re-evaluates and attaches (worktree on expected branch)"
else
  bad "fail-once retry"
fi
worktree_prune retrycoll myproj 1 "$REPO" >/dev/null 2>&1

# ── 5e. all attempts fail → no orphan branch, real error surfaced ─────────
BEFORE_BRANCHES=$(git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads/swarm | sort)
rm -f "$TEST_DIR/stub-marker"
FAIL_OUT=$(STUB_MARKER="$TEST_DIR/stub-marker" GIT_STUB_MODE=failall PATH="$STUB:$PATH" \
  worktree_provision allfail myproj HEAD "$REPO" 2>&1 >/dev/null || true)
AFTER_BRANCHES=$(git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads/swarm | sort)
if worktree_provision_ok_probe=$(true); then :; fi
if [[ "$BEFORE_BRANCHES" == "$AFTER_BRANCHES" ]] \
   && ! git -C "$REPO" rev-parse --verify --quiet "refs/heads/swarm/myproj/allfail" >/dev/null; then
  if printf '%s' "$FAIL_OUT" | grep -q "provision failed"; then
    ok "all-attempts-fail: no orphan branch left, real error surfaced"
  else
    bad "all-fail error surfaced (branch cleaned but error swallowed)"
  fi
else
  bad "orphan cleanup (branch list changed or allfail remains)"
fi
[[ ! -d "$REPO/.herdr-swarm/worktrees/allfail" ]] && rm -f "$REPO/.herdr-swarm/worktrees/allfail" 2>/dev/null
rm -f "$STUB/git"

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

# ── 7. stale branch gate (P2-H H1) ────────────────────────────────────────
OUT=$(worktree_provision stale1 myproj HEAD "$REPO" 2>/dev/null)
WT5=$(sed -n 1p <<<"$OUT")
(cd "$WT5" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "leftover run commit")
git -C "$REPO" worktree unlock "$WT5" >/dev/null 2>&1 || true
git -C "$REPO" worktree remove --force "$WT5" >/dev/null 2>&1 || true
if worktree_provision stale1 myproj HEAD "$REPO" >/dev/null 2>&1; then
  bad "stale branch (unmerged commits) refused without adopt"
else
  ok "stale branch (unmerged commits) refused without adopt"
fi
if WORKTREE_ADOPT_BRANCHES=1 worktree_provision stale1 myproj HEAD "$REPO" >/dev/null 2>&1; then
  ok "WORKTREE_ADOPT_BRANCHES=1 adopts stale branch"
  [[ $(git -C "$REPO" rev-list --count "main..swarm/myproj/stale1") == 1 ]] \
    && ok "adopted branch retains its unmerged commit (no reset)"
else
  bad "WORKTREE_ADOPT_BRANCHES=1 adopts stale branch"
fi
git -C "$REPO" worktree unlock "$REPO/.herdr-swarm/worktrees/stale1" >/dev/null 2>&1 || true
git -C "$REPO" worktree remove --force "$REPO/.herdr-swarm/worktrees/stale1" >/dev/null 2>&1 || true

# clean branch (0 unmerged) still attaches without adopt
OUT=$(worktree_provision stale2 myproj HEAD "$REPO" 2>/dev/null)
WT6=$(sed -n 1p <<<"$OUT")
check "clean pre-existing branch attaches without adopt" \
  '[[ -d "$WT6" ]]'
worktree_prune stale2 myproj 1 "$REPO" >/dev/null 2>&1

# ── 8. untracked file salvage (P2-H H2) ───────────────────────────────────
OUT=$(worktree_provision salv myproj HEAD "$REPO" 2>/dev/null)
WT7=$(sed -n 1p <<<"$OUT")
mkdir -p "$WT7/reports"
printf 'precious worker output\n' > "$WT7/reports/findings.md"
printf 'scratch\n' > "$WT7/scratch.sh"
worktree_prune salv myproj 0 "$REPO" 2>/dev/null
check "prune removed the worktree after salvage" '[[ ! -d "$WT7" ]]'
SALV=$(find "$REPO/.herdr-swarm/salvage" -maxdepth 1 -type d -name 'salv-*' 2>/dev/null | sort | head -n1)
if [[ -n "$SALV" ]]; then
  ok "salvage directory created"
  [[ "$(cat "$SALV/reports/findings.md")" == "precious worker output" ]] \
    && ok "nested untracked file content preserved"
  [[ -f "$SALV/scratch.sh" ]] && ok "flat untracked file preserved"
else
  bad "salvage directory created"
fi

# forced prune ALSO salvages (insurance is unconditional)
OUT=$(worktree_provision salv2 myproj HEAD "$REPO" 2>/dev/null)
WT8=$(sed -n 1p <<<"$OUT")
printf 'force-salvage me\n' > "$WT8/keeper.txt"
worktree_prune salv2 myproj 1 "$REPO" 2>/dev/null
SALV2=$(find "$REPO/.herdr-swarm/salvage" -maxdepth 1 -type d -name 'salv2-*' 2>/dev/null | sort | head -n1)
if [[ -n "$SALV2" && "$(cat "$SALV2/keeper.txt")" == "force-salvage me" ]]; then
  ok "forced prune still salvages untracked files"
else
  bad "forced prune still salvages untracked files"
fi

# ── 9. teardown unlocks + prunes isolated ledger seats (P2-H H3) ──────────
OUT=$(worktree_provision iso-seat myproj HEAD "$REPO" 2>/dev/null)
WT9=$(sed -n 1p <<<"$OUT")
BR9=$(sed -n 2p <<<"$OUT")
printf 'iso v1\n' > "$WT9/iso.txt"
git -C "$WT9" add iso.txt
git -C "$WT9" -c user.email=t@t -c user.name=t commit -q -m "track iso.txt"
printf 'iso edit\n' > "$WT9/iso.txt"          # tracked, uncommitted modification
printf 'loose notes\n' > "$WT9/notes.txt"     # untracked → salvage path
jq -cn --arg ws "wTEST" \
  '{version: 2, workspace_id: $ws, seats: [
     {name: "iso-seat", kind: "opencode", pane: "wTEST:p9",
      worktree_dir: "'"$WT9"'", branch: "'"${BR9}"'", isolated: true},
     {name: "root-seat", kind: "agy", pane: "wTEST:p1",
      worktree_dir: "'"${REPO}"'", branch: "main", isolated: false}]}' \
  > "$REPO/.herdr-swarm/seats.json"
if swarm_down "$REPO" 1 0 >/dev/null 2>&1; then
  ok "swarm_down completes with isolated ledger seats (headless --yes)"
else
  bad "swarm_down completes with isolated ledger seats (headless --yes)"
fi
check "teardown pruned the isolated worktree" '[[ ! -d "$WT9" ]]'
check "teardown kept the seat branch" \
  'git -C "$REPO" rev-parse --verify --quiet "refs/heads/'"$BR9"'" >/dev/null'
check "teardown checkpointed the dirty tracked edit" '
  git -C "$REPO" for-each-ref --format="%(refname:short)" -- "refs/heads/'"$BR9"'-checkpoint-*" | grep -q .'
CP9=$(git -C "$REPO" for-each-ref --format="%(refname:short)" -- "refs/heads/${BR9}-checkpoint-*" | head -n1)
[[ "$(git -C "$REPO" show "$CP9:iso.txt" 2>/dev/null)" == "iso edit" ]] \
  && ok "checkpoint preserves the isolated seat's tracked edit"
SALV9=$(find "$REPO/.herdr-swarm/salvage" -maxdepth 1 -type d -name 'iso-seat-*' 2>/dev/null | head -n1)
[[ -n "$SALV9" && "$(cat "$SALV9/notes.txt" 2>/dev/null)" == "loose notes" ]] \
  && ok "teardown salvaged the isolated seat's untracked file"
check "root checkout untouched by teardown" \
  '[[ -z "$(git -C "$REPO" status --porcelain | grep -v "^?? .herdr-swarm")" ]]'

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
