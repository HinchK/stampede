# ADR 0010: Worktree Teardown Lifecycle, Untracked File Salvage, and Stale Branch Re-attachment Gating

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [Phase 2 Milestone Audit](../audits/2026-09-19-phase2-worktree-milestone-audit.md), [Ticket P2-H](../../maps/tickets/worktree-lifecycle-teardown-and-salvage.md), [Phase 2 Advisory](../audits/2026-09-19-phase2-worktree-advisory.md), [ADR 0006](0006-git-worktree-worker-isolation.md), [ADR 0007](0007-split-pane-cwd-order-and-ledger-v2.md)

---

## 1. Context and Problem Statement

Following the initial implementation of Phase 2 Git worktree worker isolation ([ADR 0006](0006-git-worktree-worker-isolation.md), [ADR 0007](0007-split-pane-cwd-order-and-ledger-v2.md), [ADR 0008](0008-supervisor-worktree-suite-gating-and-drift.md)), comprehensive empirical auditing ([Phase 2 Milestone Audit](../audits/2026-09-19-phase2-worktree-milestone-audit.md)) against live scratch repositories identified three severe operational defects in worktree lifecycle management:

1. **Silent Stale Branch Re-attachment (Audit Finding H1)**:
   In [`lib/worktree.sh`](../../lib/worktree.sh), while the dangerous `-B` flag was successfully eliminated to avoid resetting branches, `worktree_provision` blindly attached to any pre-existing branch `refs/heads/$branch` without evaluating its staleness. When an earlier aborted run left unmerged commits on a seat-scoped branch, subsequent launches silently adopted that branch. The worker inherited an obsolete, contaminated baseline without warning, violating [ADR 0007 §4.C](0007-split-pane-cwd-order-and-ledger-v2.md).
2. **Untracked File Destruction during Worktree Pruning (Audit Finding H2)**:
   [`lib/worktree.sh`](../../lib/worktree.sh) implemented dirty worktree checkpointing via `git add -u` onto a temporary checkpoint branch before calling `git worktree remove --force`. However, `git add -u` strictly stages *tracked* file modifications. Any **untracked files** written by an autonomous worker—such as newly created test files (`*_test.py`), new source modules, or scratch notes—were completely omitted from the checkpoint commit. When `git worktree remove --force` subsequently executed, Git silently wiped all untracked files from disk, resulting in permanent data loss. Widening the checkpoint command to `git add -A` was strictly forbidden by Advisory Hazard H8 because blind `-A` commits credentials, `.env` files, build caches, and large binary artifacts.
3. **Orphaned Worktree Leakage across Teardown Cycles (Audit Finding H3)**:
   [`lib/lifecycle.sh`](../../lib/lifecycle.sh) (`swarm_down`) closed Herdr terminal panes but contained no logic to manage or prune Git worktrees. Furthermore, `worktree_provision` sets administrative locks (`git worktree lock --reason "herd:<ws>:<seat>"`) to mark active seats. Because `swarm_down` never unlocked or pruned worktrees, every `up`/`down` cycle leaked locked worktrees on disk. Native `git worktree prune` intentionally skips locked worktrees, resulting in disk bloat and stale worktree registries across development sessions.

---

## 2. Decision Drivers

- **Zero Data Loss Invariant**: No uncommitted work—whether tracked or untracked—may ever be deleted or destroyed during automated worktree pruning or teardown.
- **Stale Baseline Protection**: An autonomous worker must never unknowingly execute on top of unmerged commits from an earlier session.
- **Clean Lifecycle Convergence**: Calling `swarm_down` must retire all allocated system resources (panes, agent processes, administrative worktree locks, and clean disposable worktrees).
- **Safe Checkpointing without Environment Contamination**: Prevent untracked file loss without resorting to dangerous `git add -A` commits that sweep up local secrets or build artifacts (Advisory H8).
- **Deterministic Operator Visibility**: Retained dirty worktrees and salvaged untracked files must be organized into deterministic, auditable local paths.

---

## 3. Considered Options

- **Option A (Blind Force Deletion with Warning)**: Retain `git worktree remove --force` and warn operators not to leave untracked files. (Rejected: completely unacceptable for autonomous coding systems where models routinely create new untracked files).
- **Option B (Widen Checkpoint to `git add -A`)**: Stage everything before pruning. (Rejected: directly violates Advisory Hazard H8; commits ignored artifacts, credentials, `.env` files, and garbage into Git branch history).
- **Option C (Stale Branch Gating, Untracked File Salvage Directory, and Teardown Lifecycle Integration)**: Enforce strict `rev-list` staleness checks at provisioning, copy untracked files to `.herdr-swarm/salvage/<seat>-<timestamp>/` before worktree removal, and integrate worktree unlocking and pruning into `swarm_down`.

---

## 4. Decision

We adopted **Option C**. We established the following architectural standards across [`lib/worktree.sh`](../../lib/worktree.sh) and [`lib/lifecycle.sh`](../../lib/lifecycle.sh):

### A. Stale Branch Re-attachment Gating (`worktree_provision`)
When `worktree_provision` checks for an existing branch `refs/heads/$branch`:
1. It queries Git for unmerged commits ahead of the baseline ref:
   ```bash
   unmerged_count=$(git -C "$target_dir" rev-list --count "$base_ref..$branch" 2>/dev/null || echo 0)
   ```
2. If `unmerged_count == 0`: the branch is clean and is attached safely without reset.
3. If `unmerged_count > 0`:
   - If `--adopt-branches` was explicitly passed by the operator (or this is a documented resume from an active `seats.json` ledger), attachment proceeds.
   - Otherwise, `worktree_provision` **fails closed** with exit code 1:
     ```
     ERROR: Stale branch 'swarm/<slug>/<seat>' has N unmerged commit(s) ahead of '<base>'.
     Pass --adopt-branches to reuse this branch, or delete it with:
       git branch -D 'swarm/<slug>/<seat>'
     ```
   This prevents autonomous agents from building upon orphaned or conflicting historical experiments.

### B. Untracked File Salvage Protocol (`.herdr-swarm/salvage/`)
To resolve the data-loss vulnerability (H2) without violating the Hazard H8 constraint (`git add -A` prohibition), [`lib/worktree.sh`](../../lib/worktree.sh) introduces the **Untracked File Salvage Protocol** inside `worktree_prune`:

```
[worktree_prune]
       │
       ▼
[1. Check Tracked Edits] ──(Modified)──> [Commit to checkpoint ref via git add -u]
       │
       ▼
[2. Check Untracked Files (status --porcelain '^??')]
       ├── If untracked files exist:
       │     salvage_dir = ".herdr-swarm/salvage/<seat>-<timestamp>"
       │     Mirror untracked files recursively to salvage_dir
       │     Log salvage archive path for operator review
       └── If none: proceed
       │
       ▼
[3. Safe Worktree Removal]
       git worktree remove --force "$wt_dir"
       git worktree prune
```

1. **Tracked Edits**: Tracked modifications are committed via `git add -u` to a dedicated, timestamped checkpoint branch (`refs/heads/swarm/<slug>/<seat>-checkpoint-<ts>`).
2. **Untracked Salvage**: Any untracked file (matching `^??` in `git status --porcelain`) is copied preserving relative directory hierarchy into:
   ```
   ${TARGET_DIR}/.herdr-swarm/salvage/<seat>-<timestamp>/
   ```
3. **Safe Removal**: Once all tracked edits are committed to the checkpoint ref and all untracked files are mirrored into `.herdr-swarm/salvage/`, `git worktree remove --force` can execute safely without risking permanent data loss.
4. **Transparency**: The salvage location is logged to the terminal and recorded in telemetry.

### C. Teardown Lifecycle Integration in `swarm_down`
[`lib/lifecycle.sh`](../../lib/lifecycle.sh) is updated to fully manage the worktree lifecycle during `swarm_down`:

1. **Ledger Inspection**: Reads `.herdr-swarm/seats.json` v2 to identify all seats with `"isolated": true`.
2. **Pane Teardown**: Closes Herdr agent terminal panes.
3. **Worktree Unlock**: Calls `git -C "$abs_target" worktree unlock "$worktree_dir" 2>/dev/null || true` to release administrative seat locks.
4. **Safe Pruning / Retained Work**:
   - Calls `worktree_prune` for each isolated worktree path registered in the ledger.
   - If a worktree cannot be pruned (e.g. locks held by another process or manual override), it is left in place, locked, and reported under `Retained Work`.
5. **Administrative Prune**: Executes `git -C "$abs_target" worktree prune` to purge dangling Git administrative metadata.
6. **Root Inviolability**: Worktree commands are strictly prohibited from targeting `$TARGET_DIR` (root repository).

---

## 5. Invariants & Safety Guarantees

1. **Zero Data Loss Invariant**: Automated worktree pruning must never delete files without first archiving untracked files in `.herdr-swarm/salvage/` and committing tracked edits to a checkpoint ref.
2. **No Blind Staging Invariant**: Scripts must never execute `git add -A` during automated checkpointing or teardown (Hazard H8 protection).
3. **Stale Baseline Protection**: A swarm launch must never silently adopt a pre-existing branch containing unmerged commits without explicit operator authorization (`--adopt-branches`).
4. **Administrative Cleanliness**: Every worktree locked by `worktree_provision` must be unlocked and pruned during clean `swarm_down`.
5. **Root Directory Inviolability**: Teardown pruning routines must explicitly verify that target paths are strictly subdirectories of `.herdr-swarm/worktrees/` and never the repository root.

---

## 6. Consequences

### Positive
- **Guaranteed Work Preservation**: Both committed diffs, uncommitted tracked edits, and uncommitted untracked files survive swarm teardown and crashes.
- **Clean Development Baselines**: Autonomous agents are guaranteed to start from clean base commits, eliminating phantom regressions caused by leftover branches.
- **Resource Hygiene**: Disposing a swarm via `down` leaves zero orphaned worktrees or locked directories on disk.
- **Auditability**: Salvaged files in `.herdr-swarm/salvage/` give operators immediate access to scratch scripts or half-finished files created by agents during interrupted runs.

### Negative / Trade-offs
- **Salvage Directory Growth**: Repeated interrupted runs with large untracked files will accumulate storage in `.herdr-swarm/salvage/` until manually cleaned or purged by the operator.
- **Explicit Branch Adoption Requirement**: When intentionally resuming an older branch that was not tracked in `seats.json`, operators must provide the `--adopt-branches` flag.

---

## 7. References

- [Phase 2 Worktree Swarm Milestone Audit (Findings H1–H3)](../audits/2026-09-19-phase2-worktree-milestone-audit.md)
- [Ticket P2-H: Worktree Lifecycle Teardown, Untracked Salvage, and Stale Branch Gate](../../maps/tickets/worktree-lifecycle-teardown-and-salvage.md)
- [ADR 0006: Git Worktree Worker Isolation and Lifecycle Management](0006-git-worktree-worker-isolation.md)
- [ADR 0007: Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2](0007-split-pane-cwd-order-and-ledger-v2.md)
- [ADR 0008: Supervisor Worktree Suite Gating, Provenance, and Drift Detection](0008-supervisor-worktree-suite-gating-and-drift.md)
