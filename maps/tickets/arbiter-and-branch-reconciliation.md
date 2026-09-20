---
id: P2-4
title: "Phase 2 Arbiter and Branch Reconciliation"
type: wayfinder:prototype
status: resolved
commit: 3c4a584
assignee: arch
prototype_asset: lib/arbiter.sh,tests/test_arbiter.sh
owns: lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/universal-herdr-swarm.md
---

# Phase 2 Arbiter and Branch Reconciliation (P2-4)

## Context & Problem Statement

In Phase 2, multiple worker agents develop concurrently in isolated Git worktrees (`.herdr-swarm/worktrees/<seat>`). Once a worker's task achieves a verified GREEN suite gate in its isolated worktree, the resulting branch must be merged cleanly without race conditions or corrupting the root working checkout.

PM's comprehensive specification in [docs/audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md) defines the exact deterministic shell tooling (`lib/arbiter.sh`) for serializing integration into a dedicated `swarm/<slug>/integration` branch using Compare-and-Swap (CAS), gating the combined tree in a detached worktree, and providing human-supervised promotion.

## Preamble

1. **Intended Outcome**: `arch` implements `lib/arbiter.sh` and test suite `tests/test_arbiter.sh` following PM's specification in `docs/audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md`.
2. **Explicit Done-Criteria**:
   - `lib/arbiter.sh`:
     - `arbiter_enqueue <ticket> <seat> <sha>`: Appends `{status: "queued"}` to `.herdr-swarm/integration.jsonl`. Handles supersession if newer green verdict arrives for the same ticket.
     - `arbiter_drain`: Serialized queue processor using atomic directory lock (`.herdr-swarm/arbiter.lock`).
       - Resolves `I0 = rev-parse swarm/<slug>/integration` (initialized from base branch if missing).
       - In detached worktree (`.herdr-swarm/worktrees/arbiter-<slug>`):
         - Fast-forward if `is-ancestor(I0, sha)`, otherwise builds merge commit off-branch (`--no-ff`). On conflict, aborts and records `status: "conflict"`.
         - Pre-gates candidate: runs `TEST_CMD` with arbiter `TMPDIR`. If RED, records `status: "integration_red"` and ref is not advanced.
         - CAS ref update: `git update-ref refs/heads/swarm/<slug>/integration <candidate> <I0>`.
         - Records `status: "integrated"` and emits `arbiter.integrated` telemetry.
     - `arbiter_promote [--pr]`: Human promotion step.
       - Local mode: runs `git merge --ff-only swarm/<slug>/integration` in the root working checkout.
       - PR mode: pushes `swarm/<slug>/integration` and creates GitHub PR linking to resolved tickets.
   - `tests/test_arbiter.sh`:
     - Unit test suite verifying queue, CAS merge, conflict rejection, integration gating, and promotion.
   - Quality checks:
     - `shellcheck lib/arbiter.sh` passes cleanly with 0 warnings.
     - `bash tests/test_arbiter.sh` passes all assertions.
3. **Verification Step**:
   - Run `bash tests/test_arbiter.sh`.
   - Run `shellcheck lib/arbiter.sh`.
   - Commit changes and emit `ARCH DONE #24 <commit_sha>`.
