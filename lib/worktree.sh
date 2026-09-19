#!/usr/bin/env bash
# lib/worktree.sh — Worktree Lifecycle Library (provision / prune / reconcile)
# Prototype for Ticket: P2-1 · Implements ADR 0006 (Git Worktree Worker Isolation)
# and the PM Phase 2 advisory rules H3 (branch namespacing), H8 (checkpoint via
# `git add -u`, never `-A`), and lock-as-live-seat-marker.
#
# Layout (ADR 0006 §A/§C):
#   worktree:  ${TARGET_DIR}/.herdr-swarm/worktrees/<seat>
#   branch:    swarm/<slug>/<seat>       (retained after prune until integrated)
#   lock:      "seated: <seat>"          (survives `git worktree prune`)
#
# Safety rules:
#   - The ROOT checkout is never removed or checked out to a swarm branch.
#   - Prune checkpoints dirty tracked changes (add -u) onto the seat branch and
#     marks them with a `swarm/<slug>/<seat>-checkpoint-<ts>` ref before removal.
#   - Branches survive worktree removal; work is recoverable (ADR 0006 §D).

set -euo pipefail

# worktree_provision SEAT SLUG [BASE_REF] [TARGET_DIR]
#   Creates + locks the seat's isolated worktree on branch swarm/<slug>/<seat>.
#   Prints two lines: <worktree_path> <branch>
worktree_provision() {
  local seat="$1"
  local slug="$2"
  local base_ref="${3:-HEAD}"
  local target_dir="${4:-$PWD}"
  local branch="swarm/${slug}/${seat}"
  local wt_path="${target_dir}/.herdr-swarm/worktrees/${seat}"

  mkdir -p "$(dirname "$wt_path")"

  # Idempotent re-seat: a worktree already registered at this path is
  # re-locked and reported with its actual branch (no reset, no duplicate —
  # re-running `up` must not fail or fork a second tree).
  local wt_real=""
  [[ -d "$wt_path" ]] && wt_real=$(cd "$wt_path" && pwd -P)
  if [[ -n "$wt_real" ]] \
     && git -C "$target_dir" worktree list --porcelain 2>/dev/null | grep -q "^worktree ${wt_real}\$"; then
    local cur_branch
    cur_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD)
    git -C "$target_dir" worktree lock --reason "seated: $seat" "$wt_path" >/dev/null 2>&1 || true
    printf '%s\n%s\n' "$wt_path" "$cur_branch"
    return 0
  fi

  # H4 mitigation note: an in-repo worktree root relies on the ecosystem
  # ignoring dot-dirs; warn loudly when the parent is not git-ignored.
  if ! git -C "$target_dir" check-ignore -q "$(dirname "$wt_path")" 2>/dev/null; then
    printf 'worktree: WARNING: %s is not git-ignored; suite runners may crawl it\n' \
      "$(dirname "$wt_path")" >&2
  fi

  # -B: create the branch at base_ref, or reset it if it already exists
  # (ADR 0006 §C permits attach-or-create; -B makes re-seating deterministic).
  git -C "$target_dir" worktree add -B "$branch" "$wt_path" "$base_ref" >/dev/null

  # Lock = live-seat marker: survives `git worktree prune`, refuses remove.
  git -C "$target_dir" worktree lock --reason "seated: $seat" "$wt_path" >/dev/null

  printf '%s\n%s\n' "$wt_path" "$branch"
}

# worktree_is_locked WT_PATH TARGET_DIR -> 0 if locked
# (compares physical paths: git porcelain always prints realpath)
worktree_is_locked() {
  local wt_path="$1"
  local target_dir="${2:-$PWD}"
  local wt_real="$wt_path"
  [[ -d "$wt_path" ]] && wt_real=$(cd "$wt_path" && pwd -P)
  git -C "$target_dir" worktree list --porcelain 2>/dev/null \
    | awk -v wt="$wt_real" '
      /^worktree / { cur = substr($0, 10) }
      /^locked/ && cur == wt { found = 1 }
      END { exit !found }'
}

# worktree_is_dirty WT_PATH -> 0 if tracked changes exist (staged or unstaged)
worktree_is_dirty() {
  local wt_path="$1"
  ! git -C "$wt_path" diff --quiet --ignore-submodules HEAD 2>/dev/null \
    || ! git -C "$wt_path" diff --cached --quiet --ignore-submodules HEAD 2>/dev/null
}

# worktree_prune SEAT SLUG [FORCE=0] [TARGET_DIR]
#   Unlocks, checkpoints dirty tracked work (H8: add -u, never -A), removes the
#   worktree. The seat branch (and checkpoint ref, if any) always survives.
worktree_prune() {
  local seat="$1"
  local slug="$2"
  local force="${3:-0}"
  local target_dir="${4:-$PWD}"
  local branch="swarm/${slug}/${seat}"
  local wt_path="${target_dir}/.herdr-swarm/worktrees/${seat}"

  if [[ ! -d "$wt_path" ]]; then
    printf 'worktree: nothing to prune at %s\n' "$wt_path" >&2
    return 0
  fi

  # Never prune the root checkout (ADR 0006 §D: root inviolability)
  if [[ "$(cd "$wt_path" && pwd -P)" == "$(cd "$target_dir" && pwd -P)" ]]; then
    printf 'worktree: REFUSING to prune the root checkout\n' >&2
    return 1
  fi

  # 1. Unlock (remove refuses locked worktrees)
  git -C "$target_dir" worktree unlock "$wt_path" >/dev/null 2>&1 || true

  # 2. Checkpoint dirty tracked work unless forced
  if (( ! force )) && worktree_is_dirty "$wt_path"; then
    local cp_branch
    cp_branch="${branch}-checkpoint-$(date +%s)"
    # H8: stage tracked modifications only; never `git add -A`
    git -C "$wt_path" add -u >/dev/null
    if git -C "$wt_path" diff --cached --quiet HEAD 2>/dev/null; then
      printf 'worktree: %s dirty but nothing stageable via add -u (untracked only)\n' "$seat" >&2
    else
      git -C "$wt_path" commit -q -m "herd: checkpoint at down (${seat})" >/dev/null
    fi
    # Marker ref so the checkpoint is discoverable long after the tree is gone
    git -C "$wt_path" branch -f "$cp_branch" HEAD >/dev/null 2>&1 || true
    printf 'worktree: checkpointed %s dirty state -> %s\n' "$seat" "$cp_branch" >&2
  fi

  # 3. Remove (branch survives; ADR 0006 §D)
  git -C "$target_dir" worktree remove --force "$wt_path" >/dev/null
}

# worktree_reconcile [TARGET_DIR]
#   Reports and cleans prunable worktree metadata (stale admin entries whose
#   directories vanished). Locked/live worktrees are never pruned by git.
worktree_reconcile() {
  local target_dir="${1:-$PWD}"
  local prunable
  prunable=$(git -C "$target_dir" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { wt = substr($0, 10) } /^prunable/ { print wt }')
  if [[ -n "$prunable" ]]; then
    while IFS= read -r entry; do
      [[ -n "$entry" ]] && printf 'worktree: prunable entry: %s\n' "$entry" >&2
    done <<<"$prunable"
  fi
  git -C "$target_dir" worktree prune >/dev/null 2>&1 || true
}

# CLI dispatcher (manual smoke: provision/prune/reconcile)
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-}"
  shift 2>/dev/null || true
  case "$cmd" in
    provision) worktree_provision "$@" ;;
    prune)     worktree_prune "$@" ;;
    reconcile) worktree_reconcile "${1:-$PWD}" ;;
    *)
      printf 'Usage: %s provision <seat> <slug> [base_ref] [target_dir]\n' "$0" >&2
      printf '       %s prune <seat> <slug> [force] [target_dir]\n' "$0" >&2
      printf '       %s reconcile [target_dir]\n' "$0" >&2
      exit 1 ;;
  esac
fi
