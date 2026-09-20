---
id: P2-H
title: "Worktree Lifecycle Teardown, Untracked Salvage, and Stale Branch Gate"
type: wayfinder:prototype
status: resolved
commit: d7c9558
assignee: arch
prototype_asset: lib/worktree.sh,lib/lifecycle.sh,tests/test_worktree.sh
owns: lib/worktree.sh,lib/lifecycle.sh,tests/test_worktree.sh
parent: maps/universal-herdr-swarm.md
---

# Worktree Lifecycle Teardown, Untracked Salvage, and Stale Branch Gate (P2-H)

## Context & Problem Statement

In the [Phase 2 Worktree Swarm Milestone Audit](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-phase2-worktree-milestone-audit.md), `pm` verified that P2-1 through P2-4 are functionally implemented with 100% test pass rates. However, empirical probes identified three critical lifecycle hardening defects:

1. **H1 (Stale Branch Gate):** `worktree_provision` attaches to pre-existing seat branches without checking if they contain unmerged commits from previous runs, violating ADR 0007 §C.
2. **H2 (Untracked File Deletion):** `worktree_prune` checkpoints tracked edits via `git add -u`, but then runs `git worktree remove --force`, destroying untracked files written by workers.
3. **H3 (Teardown Leakage):** `swarm_down` in `lib/lifecycle.sh` closes panes but does not unlock or prune worktrees, leaving orphaned locked trees behind on disk after every session.

## Preamble

1. **Intended Outcome**: `arch` hardens `lib/worktree.sh` and `lib/lifecycle.sh` to resolve audit findings H1, H2, and H3.
2. **Explicit Done-Criteria**:
   - `lib/worktree.sh`:
     - Stale branch check (H1): If `refs/heads/$branch` exists, verify `rev-list --count $base_ref..$branch == 0`. If unmerged commits exist and `--adopt-branches` is not passed, fail closed with an explicit error.
     - Untracked salvage (H2): In `worktree_prune`, if untracked files exist (`git status --porcelain | grep '^??'`), copy them to `.herdr-swarm/salvage/<seat>-<timestamp>/` before removal so uncommitted files are preserved.
   - `lib/lifecycle.sh`:
     - In `swarm_down`, inspect `.herdr-swarm/seats.json` v2 for isolated seats (`isolated == true`), unlock their worktrees via `git worktree unlock`, and safely call `worktree_prune` (or report retained dirty worktrees per ADR 0007 §B).
   - `tests/test_worktree.sh`:
     - Add assertions verifying stale branch refusal, untracked file salvage, and teardown unlocking.
   - Quality checks:
     - `shellcheck lib/worktree.sh lib/lifecycle.sh tests/test_worktree.sh` passes with 0 warnings.
     - `bash tests/test_worktree.sh` passes all tests.
3. **Verification Step**:
   - Run `bash tests/test_worktree.sh`.
   - Run `shellcheck lib/worktree.sh lib/lifecycle.sh tests/test_worktree.sh`.
   - Commit changes and emit `ARCH DONE #25 <commit_sha>`.
