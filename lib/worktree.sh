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

# ── advisory provision lock (P3-FLAKE-1) ───────────────────────────────────
# mkdir-based (atomic create-or-fail, bash 3.2 / macOS safe — same pattern as
# arbiter_lock). Stamped with the holder's pid: a dead holder means a crashed
# provision, and the lock is broken deliberately with a warning.
_wt_lock() { # TARGET_DIR
  local lk="$1/.herdr-swarm/provision.lock"
  local tries=0 pid
  mkdir -p "$1/.herdr-swarm"
  while ! mkdir "$lk" 2>/dev/null; do
    pid=""
    [[ -f "$lk/pid" ]] && pid=$(cat "$lk/pid" 2>/dev/null || true)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      printf 'worktree: WARNING breaking stale provision lock (holder pid %s is dead)\n' "$pid" >&2
      rm -rf "$lk"
      continue
    fi
    tries=$((tries + 1))
    (( tries >= 50 )) && return 1
    sleep 0.1
  done
  printf '%s\n' "$$" > "$lk/pid"
}

_wt_unlock() { # TARGET_DIR
  rm -rf "$1/.herdr-swarm/provision.lock" 2>/dev/null || true
}

# Idempotent add with state re-evaluation (P3-FLAKE-1 §4.2). On failure the
# retry re-runs the branch-existence check instead of repeating the same `-b`
# command — a first attempt that created the branch and then failed would
# otherwise collide with its own branch forever.
_wt_add_with_retry() { # WT_PATH BRANCH BASE_REF TARGET_DIR
  local wt_path="$1" branch="$2" base_ref="$3" target_dir="$4"
  local existed_at_entry=0 attempt err=""
  git -C "$target_dir" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null && existed_at_entry=1

  for attempt in 1 2 3; do
    if git -C "$target_dir" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
      # branch exists (pre-existing or created by our own failed attempt):
      # ATTACH — never `-b`, never reset
      if err=$(git -C "$target_dir" worktree add "$wt_path" "$branch" 2>&1); then
        return 0
      fi
    else
      if err=$(git -C "$target_dir" worktree add -b "$branch" "$wt_path" "$base_ref" 2>&1); then
        return 0
      fi
    fi
    (( attempt < 3 )) || break
    # jittered backoff: uncorrelated retries avoid lockstep re-collision
    sleep $(( (RANDOM % 3 + 1) / 10 )) 2>/dev/null || sleep 0.1
  done

  # give-up: surface the real error (never swallow the last one), then clean
  # up an orphan branch this call created (no worktree, no commits beyond
  # base) so later runs do not meet a stale branch the P2-H gate would refuse
  printf 'worktree: provision failed for %s after %d attempts: %s\n' "$branch" "$attempt" "$err" >&2
  if (( ! existed_at_entry )) \
     && git -C "$target_dir" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null \
     && ! git -C "$target_dir" worktree list --porcelain 2>/dev/null | grep -q "^worktree ${wt_path}\$" \
     && [[ "$(git -C "$target_dir" rev-list --count "${base_ref}..${branch}" 2>/dev/null || printf 1)" == 0 ]]; then
    git -C "$target_dir" branch -D "$branch" >/dev/null 2>&1 || true
    printf 'worktree: removed orphan branch %s (created by failed provision)\n' "$branch" >&2
  fi
  return 1
}

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

  # Serialize the whole compound sequence (show-ref → add → lock): two
  # interleaved provisions are what produce branch-without-worktree states.
  # The RETURN trap guarantees release on every path, including errors.
  _wt_lock "$target_dir" || {
    printf 'worktree: could not acquire provision lock for %s\n' "$seat" >&2
    return 1
  }
  local _wt_locked_target="$target_dir"
  trap '_wt_unlock "$_wt_locked_target"' RETURN

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

  # Branch creation: -b ONLY for brand-new branches. Never -B — it resets an
  # existing branch to base_ref, destroying unmerged work (P2-3 spec §0 probe:
  # 20 unmerged commits → re-seat with -B → 0).
  #
  # Stale branch gate (ADR 0007 §C / P2-H H1): attaching to an existing branch
  # is allowed only when it carries NO commits unmerged into base_ref —
  # otherwise this run would silently inherit a previous run's leftover work.
  # Override deliberately with WORKTREE_ADOPT_BRANCHES=1.
  if git -C "$target_dir" show-ref --verify --quiet "refs/heads/${branch}"; then
    local unmerged
    unmerged=$(git -C "$target_dir" rev-list --count "${base_ref}..${branch}" 2>/dev/null || printf '0')
    if [[ "$unmerged" -gt 0 && "${WORKTREE_ADOPT_BRANCHES:-0}" != "1" ]]; then
      printf 'worktree: REFUSING stale branch %s (%s commit(s) not on %s); integrate or delete it, or set WORKTREE_ADOPT_BRANCHES=1 to adopt\n' \
        "$branch" "$unmerged" "$base_ref" >&2
      return 1
    fi
  fi

  # Idempotent add: re-evaluates branch existence per attempt (see
  # _wt_add_with_retry) instead of repeating the same -b command.
  # HL-WT-1: the rc is LOAD-BEARING. Callers run this inside
  # `if ! prov=$(worktree_provision …)` where set -e is suspended — an
  # ignored failure here prints a phantom path and reads as success all the
  # way up (a fully green-looking no-op). Fail loudly, print no shape.
  if ! _wt_add_with_retry "$wt_path" "$branch" "$base_ref" "$target_dir"; then
    printf 'worktree: provision failed for %s — not printing a path\n' "$branch" >&2
    return 1
  fi

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
#   Unlocks, checkpoints dirty tracked work (H8: add -u, never -A), salvages
#   untracked files (P2-H H2: `remove --force` would destroy them), then
#   removes the worktree. The seat branch (and checkpoint ref, if any) always
#   survives.
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

  # 3. Salvage untracked files (always, forced or not): `worktree remove
  #    --force` deletes them outright — copy them out so worker output,
  #    scratch scripts, and reports are never lost.
  local untracked
  untracked=$(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null || true)
  if [[ -n "$untracked" ]]; then
    local salvage_dir
    salvage_dir="${target_dir}/.herdr-swarm/salvage/${seat}-$(date +%s)"
    local f
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      mkdir -p "${salvage_dir}/$(dirname "$f")"
      cp -R "${wt_path}/${f}" "${salvage_dir}/${f}"
    done <<<"$untracked"
    printf 'worktree: salvaged untracked files from %s -> %s\n' "$seat" "$salvage_dir" >&2
  fi

  # 4. Remove (branch survives; ADR 0006 §D)
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
