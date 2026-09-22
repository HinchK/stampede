---
id: T-016-docs
title: "ADR 0006: Git Worktree Worker Isolation & Phase 2 Architecture Spec"
type: wayfinder:prototype
status: resolved
assignee: agy-docs
prototype_asset: docs/adr/0006-git-worktree-worker-isolation.md,docs/worktree-swarm.md
owns: docs/adr/0006-git-worktree-worker-isolation.md,docs/worktree-swarm.md
parent: maps/universal-herdr-swarm.md
resolution:
  commit: pending
  verified_by: looper
  date: "2026-09-19"
github_issue: 55
github_url: "https://github.com/HinchK/stampede/issues/55"
synced_at: "2026-09-22T03:16:07Z"
---

# ADR 0006: Git Worktree Worker Isolation & Phase 2 Architecture Spec (T-016-docs)

## Question

How should the Universal Herdr Swarm support concurrent, conflict-free worker development across seats (e.g. `arch`, `docs`, `pm`) using Git worktrees, and how should worktree lifecycle state be tracked in `.herdr-swarm/seats.json` and cleaned up safely during `swarm_down`?

## Preamble

1. **Intended Outcome**: `agy-docs` authors `docs/adr/0006-git-worktree-worker-isolation.md` following the repository's ADR standard (Context, Decision, Invariants, Guarantees, Edge Cases, Consequences), updates `docs/adr/README.md`, and authors the Phase 2 architecture specification `docs/worktree-swarm.md`.
2. **Explicit Done-Criteria**:
   - `docs/adr/0006-git-worktree-worker-isolation.md` created:
     - Defines the Git Worktree topology for seated workers: root workspace (`wM:p1` orchestrator, `wM:p2` ops) vs dedicated worker worktrees (`.worktrees/<seat>-<slug>` or `.herdr-swarm/worktrees/<seat>`).
     - Documents ledger tracking: `.herdr-swarm/seats.json` stores `"worktree_dir"` and `"branch"` per seat.
     - Outlines safe teardown semantics: `swarm_down` prunes worker worktrees (`git worktree remove --force`) only for registered worker seats, never touching the root working tree.
     - Documents merge & promotion workflow: worker branches must be reviewed and merged into target branch via PR or fast-forward after test suite gate passes.
   - `docs/adr/README.md` updated to include ADR 0006 in its index table.
   - `docs/worktree-swarm.md` created with clear implementation blueprint for Phase 2.
3. **Verification Step**:
   - Verify files exist, markdown formatting is clean, and links in `docs/adr/README.md` are valid.

## Verification Log

- Authored `docs/adr/0006-git-worktree-worker-isolation.md` detailing root vs worktree floor layout, `.herdr-swarm/seats.json` worktree tracking schema, safe teardown pruning, and arbiter merge promotion.
- Updated `docs/adr/README.md` to index ADR 0006 and link to `docs/worktree-swarm.md`.
- Authored comprehensive Phase 2 specification `docs/worktree-swarm.md` including Mermaid diagrams, task partitioning invariants, and implementation roadmap.
- Validated markdown formatting and file paths.
