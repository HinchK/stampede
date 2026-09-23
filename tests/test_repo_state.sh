#!/usr/bin/env bash
# tests/test_repo_state.sh — scripts/repo-state.sh suite (DOG-17)
# Hermetic: scratch git repos under /tmp, gh absent or stubbed, zero network.
# Covers the five sections, the gh degrade ladder (missing / unauthenticated /
# offline), read-only guarantees, and the [dir]-argument conventions.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-repostate-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SCRIPT="$SCRIPT_DIR/scripts/repo-state.sh"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()  { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
# check LABEL DESCRIPTION 'ASSERTION (eval)'
check() {
  local label="$1" desc="$2" body="$3"
  if eval "$body" >/dev/null 2>&1; then ok "$label" "$desc"; else bad "$label" "$desc"; fi
}

# A PATH that has git but cannot see gh: a bin dir holding only a git symlink.
NOGH_BIN="$TEST_DIR/nogh-bin"; mkdir -p "$NOGH_BIN"
ln -s "$(command -v git)" "$NOGH_BIN/git"
NOGH_PATH="$NOGH_BIN:/usr/bin:/bin"

# gh stubs (see tests/test_gh_sync.sh for the stubbing precedent)
STUB_BIN="$TEST_DIR/stub-bin"; mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 1\n' > "$STUB_BIN/gh-unauth"
printf '#!/bin/sh\n[ "$1" = auth ] && exit 0\nexit 1\n' > "$STUB_BIN/gh-offline"
chmod +x "$STUB_BIN/gh-unauth" "$STUB_BIN/gh-offline"

# Fixture: main with 12 commits, a merged branch, an unmerged branch, dirty tree.
REPO="$TEST_DIR/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name "T"
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
  printf 'c%s\n' "$i" > "$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -qm "c$i"
done
git -C "$REPO" checkout -qb feature-merged
printf 'merged work\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam "merged work"
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q --no-ff -m "merge feature-merged" feature-merged
git -C "$REPO" checkout -qb feature-open
printf 'open work\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam "open work"
git -C "$REPO" checkout -q main
printf 'dirty\n' >> "$REPO/file.txt"   # leave main dirty

# Clean minimal fixture (fresh repo, one commit, clean tree, no merges)
CLEAN="$TEST_DIR/clean"; mkdir -p "$CLEAN"
git -C "$CLEAN" init -q -b main
git -C "$CLEAN" config user.email t@example.com
git -C "$CLEAN" config user.name "T"
printf 'x\n' > "$CLEAN/x.txt"
git -C "$CLEAN" add x.txt && git -C "$CLEAN" commit -qm "init"

# Run harness: OUT/RC/ERR reflect one script invocation under a chosen PATH.
run() { # PATH_VALUE [arg...]
  OUT=$(PATH="$1" "$SCRIPT" "${@:2}" 2>"$TEST_DIR/err") && RC=0 || RC=$?
  ERR=$(cat "$TEST_DIR/err")
}

echo "── repo-state suite (scratch: $TEST_DIR)"

# ── 1. Sections and content, gh absent from PATH ───────────────────────────
run "$NOGH_PATH" "$REPO"
check 1a  "exits 0 with no gh on PATH" '[[ $RC -eq 0 ]]'
check 1b  "prints all five section headers" \
  'grep -q "^── branch$" <<<"$OUT" && grep -q "^── commits" <<<"$OUT" && grep -q "^── merged branches$" <<<"$OUT" && grep -q "^── ci" <<<"$OUT" && grep -q "^── dirty tree$" <<<"$OUT"'
check 1c  "repo header names the resolved target" \
  'grep -q "^repo: $REPO$" <<<"$OUT"'
check 1d  "branch section shows current branch" \
  'grep -A1 "^── branch$" <<<"$OUT" | grep -qx "main"'
check 1e  "commits section is capped at 10" \
  '[[ $(sed -n "/^── commits/,/^── merged/p" <<<"$OUT" | grep -cE "^[0-9a-f]{7,} ") -eq 10 ]]'
check 1f  "commits section leads with newest commit" \
  'sed -n "/^── commits/,/^── merged/p" <<<"$OUT" | grep -q " c12$"'
check 1g  "commits section drops oldest beyond 10" \
  '! sed -n "/^── commits/,/^── merged/p" <<<"$OUT" | grep -q " c01$"'
check 1h  "merged lists merged branch, not main or open branch" \
  'sed -n "/^── merged branches/,/^── ci/p" <<<"$OUT" | grep -q "feature-merged"'
check 1i  "merged section omits main itself" \
  '! grep -A3 "^── merged branches$" <<<"$OUT" | grep -qx "  main"'
check 1j  "merged section omits unmerged branch" \
  '! grep -A5 "^── merged branches$" <<<"$OUT" | grep -q "feature-open"'
check 1k  "ci degrades to gh: unavailable (missing binary)" \
  'grep -A1 "^── ci" <<<"$OUT" | grep -qxF "gh: unavailable (not on PATH)"'
check 1l  "dirty tree shows the modified file" \
  'grep -A2 "^── dirty tree$" <<<"$OUT" | grep -q "M file.txt"'

# ── 2. gh present but unauthenticated: degraded, not failed ────────────────
ln -sf "$STUB_BIN/gh-unauth" "$STUB_BIN/gh"
run "$STUB_BIN:$NOGH_PATH" "$REPO"
check 2a  "exits 0 with unauthenticated gh" '[[ $RC -eq 0 ]]'
check 2b  "ci degrades to gh: unavailable (unauthenticated)" \
  'grep -A1 "^── ci" <<<"$OUT" | grep -qxF "gh: unavailable (not authenticated)"'
check 2c  "other sections still print under unauthenticated gh" \
  'grep -q "^── dirty tree$" <<<"$OUT" && grep -q " c12$" <<<"$OUT"'

# ── 3. gh authenticated but offline (run list fails): degraded ─────────────
ln -sf "$STUB_BIN/gh-offline" "$STUB_BIN/gh"
run "$STUB_BIN:$NOGH_PATH" "$REPO"
check 3a  "exits 0 when gh run list fails" '[[ $RC -eq 0 ]]'
check 3b  "ci degrades to gh: unavailable (run list failed)" \
  'grep -A1 "^── ci" <<<"$OUT" | grep -qxF "gh: unavailable (gh run list failed — offline?)"'
rm -f "$STUB_BIN/gh"

# ── 4. Clean tree and no merged branches ───────────────────────────────────
run "$NOGH_PATH" "$CLEAN"
check 4a  "clean repo exits 0" '[[ $RC -eq 0 ]]'
check 4b  "dirty tree prints clean" \
  'grep -A1 "^── dirty tree$" <<<"$OUT" | grep -qx "clean"'
check 4c  "merged section prints (none) when only main exists" \
  'grep -A1 "^── merged branches$" <<<"$OUT" | grep -qxF "  (none)"'

# ── 5. Argument conventions ────────────────────────────────────────────────
OUT=$(cd "$REPO" && PATH="$NOGH_PATH" "$SCRIPT" 2>/dev/null) && RC=0 || RC=$?
check 5a  "no arg defaults to \$PWD" \
  '[[ $RC -eq 0 ]] && grep -q "^repo: $REPO$" <<<"$OUT"'
run "$NOGH_PATH" --help
check 5b  "--help exits 0" '[[ $RC -eq 0 ]]'
run "$NOGH_PATH" "$TEST_DIR/does-not-exist"
check 5c  "missing dir fails with stderr message" \
  '[[ $RC -ne 0 ]] && grep -q "does not exist" <<<"$ERR"'
mkdir -p "$TEST_DIR/not-a-repo"
run "$NOGH_PATH" "$TEST_DIR/not-a-repo"
check 5d  "non-repo dir fails closed" \
  '[[ $RC -ne 0 ]] && grep -q "not a git work tree" <<<"$ERR"'
run "$NOGH_PATH" "$REPO" extra
check 5e  "too many args rejected" '[[ $RC -ne 0 ]]'

# ── 6. Detached HEAD and repo without main ─────────────────────────────────
DET="$TEST_DIR/detached"
git clone -q "$CLEAN" "$DET"
git -C "$DET" checkout -q --detach HEAD
run "$NOGH_PATH" "$DET"
check 6a  "detached HEAD still exits 0" '[[ $RC -eq 0 ]]'
check 6b  "detached HEAD reported, not blank" \
  'grep -A1 "^── branch$" <<<"$OUT" | grep -q "detached at"'

TRUNK="$TEST_DIR/trunk"; mkdir -p "$TRUNK"
git -C "$TRUNK" init -q -b trunk
git -C "$TRUNK" config user.email t@example.com
git -C "$TRUNK" config user.name "T"
printf 'x\n' > "$TRUNK/x.txt"
git -C "$TRUNK" add x.txt && git -C "$TRUNK" commit -qm "init"
run "$NOGH_PATH" "$TRUNK"
check 6c  "repo without main exits 0" '[[ $RC -eq 0 ]]'
check 6d  "merged section notes missing main" \
  'grep -A1 "^── merged branches$" <<<"$OUT" | grep -q "no local main branch"'

EMPTY="$TEST_DIR/empty"; mkdir -p "$EMPTY"
git -C "$EMPTY" init -q -b main
run "$NOGH_PATH" "$EMPTY"
check 6e  "repo with no commits exits 0" '[[ $RC -eq 0 ]]'
check 6f  "commits section reports (no commits yet)" \
  'grep -A1 "^── commits" <<<"$OUT" | grep -qxF "(no commits yet)"'

# ── 7. Read-only guarantees: no writes, no .herdr-swarm/ ───────────────────
BEFORE=$(git -C "$REPO" status --porcelain | sort)
run "$NOGH_PATH" "$REPO"
AFTER=$(git -C "$REPO" status --porcelain | sort)
check 7a  "tree state unchanged by the run" '[[ "$BEFORE" == "$AFTER" ]]'
check 7b  "no .herdr-swarm/ created in target" '[[ ! -e "$REPO/.herdr-swarm" ]]'
check 7c  "git log unchanged by the run" \
  '[[ $(git -C "$REPO" rev-parse HEAD) == $(cd "$REPO" && git rev-parse HEAD) ]]'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
