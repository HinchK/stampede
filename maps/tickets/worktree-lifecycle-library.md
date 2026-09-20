---
id: P2-1
title: "Worktree Lifecycle Library: Provisioning, Locking, Pruning & Reconcile"
type: wayfinder:prototype
status: resolved
assignee: arch
prototype_asset: lib/worktree.sh,tests/test_worktree.sh
owns: lib/worktree.sh,tests/test_worktree.sh
parent: maps/universal-herdr-swarm.md
---

# Worktree Lifecycle Library: Provisioning, Locking, Pruning & Reconcile (P2-1)

## Question

How should the swarm manage the physical lifecycle of isolated worker worktrees, ensuring that concurrent agents have dedicated file spaces, branches are properly tracked, locked against accidental pruning, and cleanly retired without losing uncommitted operator edits?

## Preamble

1. **Intended Outcome**: `arch` implements `lib/worktree.sh` following the specifications in [ADR 0006](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0006-git-worktree-worker-isolation.md) and [PM Phase 2 Advisory](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-phase2-worktree-advisory.md), accompanied by an automated test suite `tests/test_worktree.sh`.
2. **Explicit Done-Criteria**:
   - `lib/worktree.sh` provides:
     - `worktree_provision(seat, slug, [base_ref], [target_dir])`:
       - Computes worktree path: `${TARGET_DIR}/.herdr-swarm/worktrees/${seat}`.
       - Generates branch name: `swarm/${slug}/${seat}`.
       - Provisions worktree via `git -C "$target_dir" worktree add -B "$branch" "$wt_path" "${base_ref:-HEAD}"`.
       - Locks worktree via `git -C "$target_dir" worktree lock --reason "seated: $seat" "$wt_path"`.
       - Returns path and branch.
     - `worktree_prune(seat, slug, [force], [target_dir])`:
       - Unlocks worktree.
       - If worktree has dirty uncommitted changes and `force` != 1, creates a checkpoint commit or branch (`swarm/${slug}/${seat}-checkpoint-$(date +%s)`).
       - Removes worktree via `git -C "$target_dir" worktree remove --force "$wt_path"`.
     - `worktree_reconcile(target_dir)`:
       - Runs `git -C "$target_dir" worktree list --porcelain` and cleans prunable entries.
   - `tests/test_worktree.sh`:
     - Creates a scratch git repository in `/tmp/test-wt-$$`.
     - Tests `worktree_provision`, verifies locked status (`git worktree list --porcelain`).
     - Tests `worktree_prune` (both clean and dirty with checkpoint).
     - Exits 0 on success.
   - Quality checks:
     - `shellcheck lib/worktree.sh tests/test_worktree.sh` passes with 0 warnings.
3. **Verification Step**:
   - Run `bash tests/test_worktree.sh` and verify all assertions pass.
   - Run `shellcheck lib/worktree.sh tests/test_worktree.sh`.
   - Commit with message 'feat: worktree lifecycle library with provisioning, locking, and pruning (#P2-1)' and emit `ARCH DONE #20 <commit_sha>`.
