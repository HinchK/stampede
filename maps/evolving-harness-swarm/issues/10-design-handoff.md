---
id: EHS-10
title: "Agree the migration sequence and build-ready handoff"
type: wayfinder:grilling
status: claimed
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-05, EHS-06, EHS-07, EHS-08]
---

# Agree the migration sequence and build-ready handoff

## Question

What is the smallest implementation sequence for a simpler Herdr-based Stampede with a short prompt-coach startup, startup recovery, and harness self-improvement, while preserving required behavior?

Reconcile the resolved decisions, identify reuse and deletion candidates, define interfaces and acceptance boundaries, and order the implementation handoff. Explicitly account for current review authorization, queue consistency, integration drift checks, recovery, and human promotion controls. Any proposed replacement must preserve the required behavior or carry a separately agreed policy change. Assemble links to the design and protocol assets without duplicating ticket answers.

If any in-scope question remains open, create it and keep this ticket blocked rather than treating an incomplete handoff as done.

**Intended Outcome:** A complete implementation handoff backed by the map's applicable decisions.

**Done-Criteria:** The human accepts the handoff, all in-scope fog is examined, and no prerequisite design decision remains open.

**Verification Step:** Trace each requirement to a resolved decision and future acceptance check; confirm the epic stops before implementation or experiment execution.

## Comments

### 2026-11-06 — Claimed for the revised handoff

The comparative experiment is out of scope. Reuse existing setup, provider checks, Herdr session management, recovery, and harness-improvement decisions where applicable. HinchK put the proposed initial team and shared-worktree arrangement on hold, so neither is settled by this claim. The previously accepted automatic-adoption policy depended on numerical criteria from the bypassed experiment; a practical evidence rule still needs an explicit decision before automatic adoption can be specified.

### 2026-11-06 — Milestone closeout and dedicated improvement role

HinchK requires a closeout at the end of every milestone in which code is merged to `main`:

1. A short retrospective on efficiency.
2. An accounting of tool failures and collisions.
3. Complete cleanup of all worktrees associated with that milestone.
4. Simple metrics covering tokens, time, toil, and trouble.

There is always one agent dedicated exclusively to self-improvement. Its responsibilities and closeout coordination must be reflected in the handoff; it is not assigned delivery work. The four metric definitions, available sources and missing-data treatment remain to be specified without inventing measurements. Handling unfinished work is settled by the cleanup decision below. The handoff must reconcile mandatory closeout with existing stop and authority boundaries. This records desired behavior, not an implemented capability or authorization to delete current worktrees.

### 2026-11-06 — Unfinished work leaves the worktree for focused follow-up

HinchK directed that uncommitted or unmerged work be brought out of an associated worktree onto an ordinary local branch, to be focused on in the normal repository checkout. Cleanup must preserve that work and make its follow-up visible rather than leave the worktree indefinitely or discard it.

Implementation interpretation: retain an existing suitable local branch or create a recovery branch; preserve unmerged commits and snapshot unfinished changes before removing the associated checkout. A branch reference alone does not preserve uncommitted or untracked files. Preserve relevant files that cannot belong in Git separately without committing secrets. Record the recovery branch, preserved-file location if needed, remaining work, and next action in the milestone closeout. Verify the transfer before removing the worktree, and preserve existing changes in the normal checkout when bringing the recovery branch into focus. If preservation cannot be verified, report cleanup as incomplete. This is a future cleanup contract; no current worktree is removed by recording it.
