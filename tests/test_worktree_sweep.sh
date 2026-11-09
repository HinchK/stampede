#!/usr/bin/env bash
# tests/test_worktree_sweep.sh — test suite for scripts/worktree-sweep.sh
# Hermetic: scratch git repositories under /tmp, zero external network.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
# shellcheck disable=SC2034  # harness variables (OUT/RC/ERR) are consumed in eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-wtsweep-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SWEEP="$SCRIPT_DIR/scripts/worktree-sweep.sh"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()  { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
check() {
  local label="$1" desc="$2" body="$3"
  if eval "$body" >/dev/null 2>&1; then ok "$label" "$desc"; else bad "$label" "$desc"; fi
}

printf '── worktree-sweep test suite (scratch: %s)\n' "$TEST_DIR"

# 1. Help flag
OUT=$("$SWEEP" --help)
RC=$?
check "1a" "--help exits 0" '[[ "$RC" -eq 0 ]]'
check "1b" "--help mentions --apply" '[[ "$OUT" == *"--apply"* ]]'

# Setup fixture repo
REPO="$TEST_DIR/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name "T"
printf 'initial\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -qm "initial commit"

# Create a merged branch and worktree
git -C "$REPO" branch branch-merged
WT_MERGED="$TEST_DIR/wt-merged"
git -C "$REPO" worktree add "$WT_MERGED" branch-merged >/dev/null 2>&1

# Create an unmerged branch and worktree with a commit
git -C "$REPO" branch branch-unmerged
WT_UNMERGED="$TEST_DIR/wt-unmerged"
git -C "$REPO" worktree add "$WT_UNMERGED" branch-unmerged >/dev/null 2>&1
printf 'unmerged work\n' >> "$WT_UNMERGED/file.txt"
git -C "$WT_UNMERGED" commit -qam "unmerged commit"

# Create a dirty worktree (on merged branch)
git -C "$REPO" branch branch-dirty
WT_DIRTY="$TEST_DIR/wt-dirty"
git -C "$REPO" worktree add "$WT_DIRTY" branch-dirty >/dev/null 2>&1
printf 'dirty edit\n' >> "$WT_DIRTY/file.txt"

# Create a locked worktree
git -C "$REPO" branch branch-locked
WT_LOCKED="$TEST_DIR/wt-locked"
git -C "$REPO" worktree add "$WT_LOCKED" branch-locked >/dev/null 2>&1
git -C "$REPO" worktree lock "$WT_LOCKED" --reason "testing lock" >/dev/null 2>&1

# 2. Dry run audit
OUT=$("$SWEEP" "$REPO")
RC=$?
check "2a" "dry-run exits 0" '[[ "$RC" -eq 0 ]]'
check "2b" "identifies ROOT" '[[ "$OUT" == *"[ROOT]"* ]]'
check "2c" "identifies SAFE merged worktree" '[[ "$OUT" == *"[SAFE]"*"wt-merged"* ]]'
check "2d" "identifies UNMERGED worktree" '[[ "$OUT" == *"[UNMERGED]"*"wt-unmerged"* ]]'
check "2e" "identifies DIRTY worktree" '[[ "$OUT" == *"[DIRTY]"*"wt-dirty"* ]]'
check "2f" "identifies LOCKED worktree" '[[ "$OUT" == *"[LOCKED]"*"wt-locked"* ]]'
check "2g" "dry run leaves wt-merged intact" '[[ -d "$WT_MERGED" ]]'

# 3. Apply mode
OUT=$("$SWEEP" "$REPO" --apply)
RC=$?
check "3a" "--apply exits 0" '[[ "$RC" -eq 0 ]]'
check "3b" "removes safe merged worktree" '[[ ! -d "$WT_MERGED" ]]'
check "3c" "preserves unmerged worktree" '[[ -d "$WT_UNMERGED" ]]'
check "3d" "preserves dirty worktree" '[[ -d "$WT_DIRTY" ]]'
check "3e" "preserves locked worktree" '[[ -d "$WT_LOCKED" ]]'

# 4. Force mode on dirty worktree with untracked files
printf 'untracked scratch\n' > "$WT_DIRTY/scratch.txt"
OUT=$("$SWEEP" "$REPO" --apply --force)
RC=$?
check "4a" "--apply --force exits 0" '[[ "$RC" -eq 0 ]]'
check "4b" "removes dirty worktree under --force" '[[ ! -d "$WT_DIRTY" ]]'
check "4c" "salvaged untracked file to .herdr-swarm/salvage" 'find "$REPO/.herdr-swarm/salvage" -name "scratch.txt" | grep -q scratch.txt'
check "4d" "checkpoint branch created" 'git -C "$REPO" branch | grep -q "checkpoint/branch-dirty"'

# 5. Missing worktree pruning
# Create another worktree and then rm -rf directory manually to simulate vanished directory
WT_VANISHED="$TEST_DIR/wt-vanished"
git -C "$REPO" worktree add "$WT_VANISHED" -b branch-vanished >/dev/null 2>&1
rm -rf "$WT_VANISHED"
OUT=$("$SWEEP" "$REPO")
check "5a" "detects missing worktree directory" '[[ "$OUT" == *"[MISSING]"*"wt-vanished"* ]]'
OUT=$("$SWEEP" "$REPO" --apply)
check "5b" "--apply prunes missing worktree metadata" '! git -C "$REPO" worktree list | grep -q "wt-vanished"'


# ── 6. Fix 1: a live seat on a base-equal branch is never swept
REPO6="$TEST_DIR/repo6"; mkdir -p "$REPO6"
git -C "$REPO6" init -q -b main
git -C "$REPO6" config user.email t@example.com; git -C "$REPO6" config user.name T
git -C "$REPO6" commit -q --allow-empty -m init
SEAT_WT="$REPO6/.herdr-swarm/worktrees/arch_1"
git -C "$REPO6" worktree add -q -b swarm/x/arch_1 "$SEAT_WT"
printf '{"seats":[{"name":"arch_1","worktree_dir":"%s"}]}\n' "$SEAT_WT" > "$REPO6/.herdr-swarm/seats.json"
"$SWEEP" "$REPO6" --apply >/dev/null 2>&1 || true
check "6a" "live seat worktree preserved by --apply" '[[ -d "$SEAT_WT" ]]'
rm -f "$REPO6/.herdr-swarm/seats.json"
"$SWEEP" "$REPO6" --apply >/dev/null 2>&1 || true
check "6b" "seatless merged worktree is swept" '[[ ! -d "$SEAT_WT" ]]'

# ── 7. Fix 2: --force keeps the worktree when the checkpoint commit fails
REPO7="$TEST_DIR/repo7"; mkdir -p "$REPO7"
git -C "$REPO7" init -q -b main
git -C "$REPO7" config user.email t@example.com; git -C "$REPO7" config user.name T
printf 'a\n' > "$REPO7/f.txt"; git -C "$REPO7" add f.txt; git -C "$REPO7" commit -qm init
WT7="$TEST_DIR/wt7"
git -C "$REPO7" worktree add -q -b b7 "$WT7"
printf 'edit\n' >> "$WT7/f.txt"
mkdir -p "$REPO7/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$REPO7/.git/hooks/pre-commit"; chmod +x "$REPO7/.git/hooks/pre-commit"
"$SWEEP" "$REPO7" --apply --force >/dev/null 2>&1 || true
check "7a" "failed checkpoint keeps worktree and edit" '[[ -d "$WT7" ]] && grep -q edit "$WT7/f.txt"'
rm -f "$REPO7/.git/hooks/pre-commit"
printf 'ign\n' > "$WT7/ignored.log"; printf 'ignored.log\n' > "$REPO7/.git/info/exclude"
"$SWEEP" "$REPO7" --apply --force >/dev/null 2>&1 || true
check "7b" "git-ignored files keep the worktree" '[[ -d "$WT7" ]]'

# ── 8. sweep started in a linked worktree must not treat that seat as the root
REPO8="$TEST_DIR/repo8"; mkdir -p "$REPO8"
git -C "$REPO8" init -q -b main
git -C "$REPO8" config user.email t@example.com; git -C "$REPO8" config user.name T
printf 'base\n' > "$REPO8/f.txt"; git -C "$REPO8" add f.txt; git -C "$REPO8" commit -qm init
printf 'wip on main\n' >> "$REPO8/f.txt"
SEAT8="$REPO8/.herdr-swarm/worktrees/arch_1"
SEAT8B="$REPO8/.herdr-swarm/worktrees/arch_2"
mkdir -p "$REPO8/.herdr-swarm"
git -C "$REPO8" worktree add -q -b swarm/x/arch_1 "$SEAT8"
git -C "$REPO8" worktree add -q -b swarm/x/arch_2 "$SEAT8B"
printf '{"seats":[{"name":"arch_1","worktree_dir":"%s"},{"name":"arch_2","worktree_dir":"%s"}]}\n' \
  "$SEAT8" "$SEAT8B" > "$REPO8/.herdr-swarm/seats.json"
EXTRA8="$TEST_DIR/wt-extra8"
git -C "$REPO8" worktree add -q -b branch-extra8 "$EXTRA8"
before8=$(git -C "$REPO8" rev-parse HEAD)
OUT=$("$SWEEP" "$SEAT8" --apply --force)
RC=$?
check "8a" "sweep from a seat exits 0" '[[ "$RC" -eq 0 ]]'
check "8b" "main checkout is the root, not the seat" 'grep -F "[ROOT]" <<<"$OUT" | grep -F "$REPO8 [" | grep -q "root checkout"'
check "8c" "sibling live seat is preserved" '[[ -d "$SEAT8" && -d "$SEAT8B" ]]'
check "8d" "dirty main is not checkpoint-committed" '[[ "$(git -C "$REPO8" rev-parse HEAD)" == "$before8" ]] && grep -q "wip on main" "$REPO8/f.txt"'
check "8e" "clean merged non-seat is still removed" '[[ ! -d "$EXTRA8" ]]'

# ── 9. a locked worktree whose directory is gone stays registered
REPO9="$TEST_DIR/repo9"; mkdir -p "$REPO9"
git -C "$REPO9" init -q -b main
git -C "$REPO9" config user.email t@example.com; git -C "$REPO9" config user.name T
git -C "$REPO9" commit -q --allow-empty -m init
WT9="$TEST_DIR/wt-lockmiss"
git -C "$REPO9" worktree add -q -b branch-lockmiss "$WT9"
git -C "$REPO9" worktree lock "$WT9" --reason "keep"
rm -rf "$WT9"
OUT=$("$SWEEP" "$REPO9")
check "9a" "locked missing worktree is labeled locked" 'grep -F "[LOCKED]" <<<"$OUT" | grep -q "wt-lockmiss"'
check "9b" "locked missing worktree is not labeled missing" '! grep -F "[MISSING]" <<<"$OUT" | grep -q "wt-lockmiss"'
"$SWEEP" "$REPO9" --apply >/dev/null 2>&1 || true
check "9c" "apply leaves the locked registration in place" 'git -C "$REPO9" worktree list | grep -q "wt-lockmiss"'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
