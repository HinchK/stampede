#!/usr/bin/env bash
#
# scripts/worktree-sweep.sh — single-command git worktree audit & safe prune
#
# Rapidly audits registered git worktrees, categorizes them against a base
# ref (origin/main or main), preserves unmerged work and dirty changes,
# and safely prunes clean merged worktrees with zero interactive token drag.
#
# Contract:
#   - Root checkout is inviolable and never pruned.
#   - Default mode is dry-run audit (read-only); no changes made without --apply.
#   - Unmerged worktrees are always preserved unless explicitly overridden.
#   - Dirty worktrees are preserved unless --force is passed; --force
#     checkpoints tracked modifications and salvages untracked files to
#     .herdr-swarm/salvage/ before removal.
#   - Usage: scripts/worktree-sweep.sh [dir] [--apply] [--force] [--base <ref>]

set -euo pipefail

usage() {
  cat <<EOF
Usage: scripts/worktree-sweep.sh [dir] [OPTIONS]

Audit and safely prune registered git worktrees.

Options:
  --apply          Execute removal of safe-to-prune worktrees (default: dry-run)
  --force          Allow pruning dirty worktrees after checkpointing and salvaging
  --base <ref>     Base reference for merge checks (default: origin/main or main)
  -h, --help       Show this help message
EOF
}

die() { printf 'worktree-sweep: %s\n' "$1" >&2; exit 1; }

TARGET="$PWD"
APPLY=0
FORCE=0
BASE_REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --base)
      [[ $# -ge 2 ]] || die "missing argument for --base"
      BASE_REF="$2"
      shift 2
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [[ "$TARGET" == "$PWD" ]]; then
        TARGET="$1"
      else
        die "unexpected additional argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -d "$TARGET" ]] || die "target directory does not exist: $TARGET"
TARGET=$(cd "$TARGET" && pwd -P) || die "cannot resolve target directory: $TARGET"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git work tree: $TARGET"

# Determine default base reference
if [[ -z "$BASE_REF" ]]; then
  if git -C "$TARGET" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    BASE_REF="origin/main"
  elif git -C "$TARGET" rev-parse --verify -q main >/dev/null 2>&1; then
    BASE_REF="main"
  elif git -C "$TARGET" rev-parse --verify -q master >/dev/null 2>&1; then
    BASE_REF="master"
  else
    BASE_REF="HEAD"
  fi
fi

# Collect worktree data via git worktree list --porcelain
declare -a WT_PATHS=()
declare -a WT_HEADS=()
declare -a WT_BRANCHES=()
declare -a WT_LOCKED=()
declare -a WT_PRUNABLE=()

cur_path=""
cur_head=""
cur_branch=""
cur_locked=0
cur_prunable=0

save_record() {
  if [[ -n "$cur_path" ]]; then
    WT_PATHS+=("$cur_path")
    WT_HEADS+=("${cur_head:-HEAD}")
    WT_BRANCHES+=("${cur_branch:-(detached)}")
    WT_LOCKED+=("$cur_locked")
    WT_PRUNABLE+=("$cur_prunable")
  fi
  cur_path=""
  cur_head=""
  cur_branch=""
  cur_locked=0
  cur_prunable=0
}

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ -z "$line" ]]; then
    save_record
    continue
  fi
  case "$line" in
    "worktree "*)
      cur_path="${line#worktree }"
      ;;
    "HEAD "*)
      cur_head="${line#HEAD }"
      ;;
    "branch "*)
      cur_branch="${line#branch }"
      cur_branch="${cur_branch#refs/heads/}"
      ;;
    "detached")
      cur_branch="(detached)"
      ;;
    "locked"*)
      cur_locked=1
      ;;
    "prunable"*)
      cur_prunable=1
      ;;
  esac
done < <(git -C "$TARGET" worktree list --porcelain 2>/dev/null || true)
save_record

# The main checkout is always the first porcelain record. show-toplevel from a
# linked worktree is that worktree, which would let a sweep commit on the real
# checkout and miss the seat ledger.
[[ ${#WT_PATHS[@]} -gt 0 ]] || die "no worktrees registered"
ROOT_WT="${WT_PATHS[0]}"
[[ -d "$ROOT_WT" ]] && ROOT_WT=$(cd "$ROOT_WT" && pwd -P)

# Live seats (ledger) are never swept: a freshly seated worker sits on a branch
# equal to base, which otherwise reads as "merged and clean".
SEAT_DIRS=""
if [[ -f "$ROOT_WT/.herdr-swarm/seats.json" ]]; then
  while IFS= read -r d; do
    [[ -n "$d" && -d "$d" ]] && SEAT_DIRS+="$(cd "$d" && pwd -P)"$'\n'
  done < <(jq -r '.seats[]? | .worktree_dir // empty' "$ROOT_WT/.herdr-swarm/seats.json" 2>/dev/null || true)
fi

TOTAL=${#WT_PATHS[@]}
COUNT_SEAT=0
COUNT_ROOT=0
COUNT_SAFE=0
COUNT_DIRTY=0
COUNT_UNMERGED=0
COUNT_LOCKED=0
COUNT_PRUNABLE=0

declare -a REMOVE_PATHS=()
declare -a REMOVE_FORCE_PATHS=()
declare -a REMOVE_BRANCHES=()
declare -a REMOVE_FORCE_BRANCHES=()

printf 'repo: %s (base: %s, mode: %s)\n\n' "$ROOT_WT" "$BASE_REF" "$([[ $APPLY -eq 1 ]] && printf 'APPLY' || printf 'DRY-RUN')"
printf '── registered worktrees (%d total)\n' "$TOTAL"

for ((i = 0; i < TOTAL; i++)); do
  wt="${WT_PATHS[i]}"
  head="${WT_HEADS[i]}"
  branch="${WT_BRANCHES[i]}"
  locked="${WT_LOCKED[i]}"
  prunable="${WT_PRUNABLE[i]}"
  short_head="${head:0:7}"

  # Check root
  wt_canon="$wt"
  [[ -d "$wt" ]] && wt_canon=$(cd "$wt" && pwd -P)
  if [[ "$wt_canon" == "$ROOT_WT" ]]; then
    COUNT_ROOT=$((COUNT_ROOT + 1))
    printf '  %-12s %s [%s @ %s] (root checkout)\n' "[ROOT]" "$wt" "$branch" "$short_head"
    continue
  fi

  # Check seated (live) worktree
  if [[ -n "$SEAT_DIRS" ]] && grep -qxF -- "$wt_canon" <<<"$SEAT_DIRS"; then
    COUNT_SEAT=$((COUNT_SEAT + 1))
    printf '  %-12s %s [%s @ %s] (live seat in seats.json - preserved)\n' "[SEAT]" "$wt" "$branch" "$short_head"
    continue
  fi

  # A lock is kept even when the directory is already gone. git worktree
  # prune will not remove it, and this sweep must not either.
  if [[ $locked -eq 1 ]]; then
    COUNT_LOCKED=$((COUNT_LOCKED + 1))
    printf '  %-12s %s [%s @ %s] (porcelain locked)\n' "[LOCKED]" "$wt" "$branch" "$short_head"
    continue
  fi

  # Check missing/prunable
  if [[ ! -d "$wt" || $prunable -eq 1 ]]; then
    COUNT_PRUNABLE=$((COUNT_PRUNABLE + 1))
    printf '  %-12s %s [%s] (directory missing or prunable)\n' "[MISSING]" "$wt" "$branch"
    continue
  fi

  # Check merge status
  is_merged=0
  ref_to_check="$head"
  if [[ "$branch" != "(detached)" ]]; then
    ref_to_check="refs/heads/$branch"
  fi
  if git -C "$TARGET" merge-base --is-ancestor "$ref_to_check" "$BASE_REF" 2>/dev/null; then
    is_merged=1
  fi

  # Check dirty state
  is_dirty=0
  dirty_desc=""
  if ! git -C "$wt" diff --quiet HEAD 2>/dev/null || ! git -C "$wt" diff --cached --quiet HEAD 2>/dev/null; then
    is_dirty=1
    dirty_desc="tracked modifications"
  fi
  untracked=$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null || true)
  if [[ -n "$untracked" ]]; then
    is_dirty=1
    if [[ -n "$dirty_desc" ]]; then
      dirty_desc="$dirty_desc + untracked files"
    else
      dirty_desc="untracked files"
    fi
  fi

  if [[ $is_merged -eq 1 && $is_dirty -eq 0 ]]; then
    COUNT_SAFE=$((COUNT_SAFE + 1))
    printf '  %-12s %s [%s @ %s]\n' "[SAFE]" "$wt" "$branch" "$short_head"
    REMOVE_PATHS+=("$wt")
    REMOVE_BRANCHES+=("$branch")
  elif [[ $is_dirty -eq 1 ]]; then
    COUNT_DIRTY=$((COUNT_DIRTY + 1))
    if [[ $FORCE -eq 1 ]]; then
      printf '  %-12s %s [%s @ %s] (%s - will salvage/prune)\n' "[DIRTY!]" "$wt" "$branch" "$short_head" "$dirty_desc"
      REMOVE_FORCE_PATHS+=("$wt")
      REMOVE_FORCE_BRANCHES+=("$branch")
    else
      printf '  %-12s %s [%s @ %s] (%s - preserved)\n' "[DIRTY]" "$wt" "$branch" "$short_head" "$dirty_desc"
    fi
  else
    COUNT_UNMERGED=$((COUNT_UNMERGED + 1))
    ahead_count=$(git -C "$TARGET" rev-list --count "${BASE_REF}..${ref_to_check}" 2>/dev/null || printf 'unknown')
    printf '  %-12s %s [%s @ %s] (%s commits ahead - preserved)\n' "[UNMERGED]" "$wt" "$branch" "$short_head" "$ahead_count"
  fi
done

printf '\n── audit summary\n'
printf '  Total: %d | Root: %d | Safe to prune: %d | Missing: %d | Dirty: %d | Unmerged: %d | Locked: %d | Seated: %d\n' \
  "$TOTAL" "$COUNT_ROOT" "$COUNT_SAFE" "$COUNT_PRUNABLE" "$COUNT_DIRTY" "$COUNT_UNMERGED" "$COUNT_LOCKED" "$COUNT_SEAT"

if [[ $APPLY -eq 0 ]]; then
  if (( COUNT_SAFE > 0 || COUNT_PRUNABLE > 0 )); then
    printf '\nRun with --apply to remove %d safe worktree(s) and prune metadata.\n' "$((COUNT_SAFE + COUNT_PRUNABLE))"
  else
    printf '\nWorktree state is clean; nothing to prune.\n'
  fi
  exit 0
fi

# APPLY MODE
printf '\n── applying worktree sweep\n'

# 1. Prune missing/stale worktrees
if (( COUNT_PRUNABLE > 0 )); then
  git -C "$TARGET" worktree prune >/dev/null 2>&1 || true
  printf '  ✓ pruned stale/missing worktree metadata\n'
fi

# 2. Remove safe clean worktrees
for ((j = 0; j < ${#REMOVE_PATHS[@]}; j++)); do
  wt_to_remove="${REMOVE_PATHS[j]}"
  br="${REMOVE_BRANCHES[j]}"
  if git -C "$TARGET" worktree remove "$wt_to_remove" 2>/dev/null; then
    printf '  ✓ removed worktree: %s [%s]\n' "$wt_to_remove" "$br"
  else
    printf '  ✗ failed to remove worktree: %s\n' "$wt_to_remove" >&2
  fi
done

# 3. Handle force removals if any
for ((j = 0; j < ${#REMOVE_FORCE_PATHS[@]}; j++)); do
  wt_to_force="${REMOVE_FORCE_PATHS[j]}"
  br_force="${REMOVE_FORCE_BRANCHES[j]}"
  name=$(basename "$wt_to_force")
  ts=$(date +%s)
  salvage_dir="${TARGET}/.herdr-swarm/salvage/${name}-${ts}"

  # Every save step must succeed before anything is removed; any failure
  # keeps the worktree and says so.
  if [[ -n "$(git -C "$wt_to_force" ls-files --others --ignored --exclude-standard 2>/dev/null | head -n1)" ]]; then
    printf '  ✗ kept %s: git-ignored files present (not salvaged)\n' "$wt_to_force" >&2
    continue
  fi
  salvage_ok=1
  untracked_files=$(git -C "$wt_to_force" ls-files --others --exclude-standard 2>/dev/null || true)
  if [[ -n "$untracked_files" ]]; then
    while IFS= read -r uf; do
      [[ -n "$uf" ]] || continue
      mkdir -p "${salvage_dir}/$(dirname "$uf")" \
        && cp -R "${wt_to_force}/${uf}" "${salvage_dir}/${uf}" || salvage_ok=0
    done <<<"$untracked_files"
  fi
  if (( salvage_ok == 0 )); then
    printf '  ✗ kept %s: salvage copy failed (see %s)\n' "$wt_to_force" "$salvage_dir" >&2
    continue
  fi
  [[ -z "$untracked_files" ]] || printf '  ✓ salvaged untracked files from %s to %s\n' "$name" "$salvage_dir"

  if ! git -C "$wt_to_force" diff --quiet HEAD 2>/dev/null || ! git -C "$wt_to_force" diff --cached --quiet HEAD 2>/dev/null; then
    cp_branch="checkpoint/${br_force}-${ts}"
    if git -C "$wt_to_force" add -u \
       && git -C "$wt_to_force" commit -q -m "worktree-sweep: force checkpoint at ${ts}" \
       && git -C "$wt_to_force" branch -f "$cp_branch" HEAD \
       && git -C "$wt_to_force" diff --quiet HEAD && git -C "$wt_to_force" diff --cached --quiet HEAD; then
      printf '  ✓ checkpointed tracked changes to %s\n' "$cp_branch"
    else
      printf '  ✗ kept %s: checkpoint commit failed\n' "$wt_to_force" >&2
      continue
    fi
  fi

  git -C "$TARGET" worktree unlock "$wt_to_force" 2>/dev/null || true
  if git -C "$TARGET" worktree remove --force "$wt_to_force" 2>/dev/null; then
    printf '  ✓ force removed worktree: %s\n' "$wt_to_force"
  else
    printf '  ✗ failed to force remove worktree: %s\n' "$wt_to_force" >&2
  fi
done

# Final git worktree prune
git -C "$TARGET" worktree prune >/dev/null 2>&1 || true
printf '\nSweep complete.\n'
