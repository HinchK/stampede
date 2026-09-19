---
id: P2-4
title: "Phase 2 Arbiter and Branch Reconciliation"
type: wayfinder:prototype
status: backlog
assignee: arch
parent: maps/universal-herdr-swarm.md
---

# Phase 2 Arbiter and Branch Reconciliation (P2-4)

## Context & Problem Statement

In Phase 2, multiple worker agents develop in parallel on isolated worktree branches (`swarm/<slug>/<seat>`). Once a worker's task achieves a verified GREEN suite gate in its isolated worktree, the resulting branch must be merged into the base branch (`main`) cleanly.

The Arbiter engine provides:
1. **Task Intake & Partition Check:** Rejects overlapping file ownership (`owns`) before any worktree is provisioned.
2. **Atomic Compare-and-Swap Fast-Forward Merge:** Merges verified worker commits into the base branch without merge conflicts or clobbering root state.
3. **Integration PR Synthesis:** When direct fast-forward is not possible or remote pull request workflow is enabled, opens an upstream pull request linking to the local ticket (`Closes #<github_issue>`).

## Preamble

1. **Intended Outcome**: `arch` implements `lib/arbiter.sh` providing safe branch reconciliation, partition checking, and pull request integration for verified worktree branches.
2. **Explicit Done-Criteria**:
   - `lib/arbiter.sh` provides:
     - `partition_check`: Validates file patterns owned by active seats to ensure conflict-free parallel work.
     - `arbiter_merge(seat, branch, base_branch)`: Verifies suite verdict, checks fast-forward eligibility, and executes compare-and-swap merge.
     - `arbiter_pr(seat, branch, repo)`: Creates GitHub pull request via `gh pr create` linked to the associated ticket.
   - Passes `shellcheck` with 0 warnings.
3. **Verification Step**:
   - Run `shellcheck lib/arbiter.sh`.
   - Run integration merge test in scratch git repository.
