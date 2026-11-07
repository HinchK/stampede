---
id: EHS-10
title: "Agree the migration sequence and build-ready handoff"
type: wayfinder:grilling
status: resolved
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

There is always one agent dedicated exclusively to self-improvement when the feature is enabled, as refined by the toggle decision below. Its responsibilities and closeout coordination must be reflected in the handoff; it is not assigned delivery work. The four metric definitions and missing-data treatment are settled below; available measurement sources still need implementation verification. Handling unfinished work is settled by the cleanup decision below. The handoff must reconcile closeout with existing stop and authority boundaries. This records desired behavior, not an implemented capability or authorization to delete current worktrees.

### 2026-11-06 — Unfinished work leaves the worktree for focused follow-up

HinchK directed that uncommitted or unmerged work be brought out of an associated worktree onto an ordinary local branch, to be focused on in the normal repository checkout. Cleanup must preserve that work and make its follow-up visible rather than leave the worktree indefinitely or discard it.

Implementation interpretation: retain an existing suitable local branch or create a recovery branch; preserve unmerged commits and snapshot unfinished changes before removing the associated checkout. A branch reference alone does not preserve uncommitted or untracked files. Preserve relevant files that cannot belong in Git separately without committing secrets. Record the recovery branch, preserved-file location if needed, remaining work, and next action in the milestone closeout. Verify the transfer before removing the worktree, and preserve existing changes in the normal checkout when bringing the recovery branch into focus. If preservation cannot be verified, report cleanup as incomplete. This is a future cleanup contract; no current worktree is removed by recording it.

### 2026-11-06 — Four-T scorecard accepted

HinchK accepted these standard definitions for every applicable milestone closeout:

| Metric | Accounting |
| --- | --- |
| Tokens | Usage by agent/model, including self-improvement overhead; unknown where unavailable. |
| Time | Milestone elapsed time and active human minutes. |
| Toil | Human interventions, manual recovery steps, and repeated work. |
| Trouble | Tool failures, retries, and collisions, grouped by cause. |

The self-improvement agent produces a short closeout explaining wasted effort, helpful practices, proposed changes, and where unfinished work was preserved. Measurements must identify their source; unavailable values must not be fabricated.

### 2026-11-06 — Self-improvement feature toggle

HinchK requires this feature to be toggleable. Implementation interpretation: one project-level self-improvement toggle controls the dedicated agent and its milestone closeout, including retrospective, failure/collision accounting, associated-worktree cleanup, and the four-T scorecard. Default to enabled to retain the previously requested behavior; the default and this whole-feature interpretation are agent choices, not additional human selections. When disabled, do not launch the dedicated agent or schedule its closeout work. Disabling does not authorize discarding unfinished work, interrupting a preservation operation unsafely, or clearing pending recovery obligations. Ordinary delivery verification and safe worktree handling remain required. No runtime toggle is implemented by this planning record.

### 2026-11-06 — Draft handoff prepared after instruction to proceed

HinchK instructed continuation following the whole-feature toggle/default proposal. [Simple startup and milestone self-improvement](../../../docs/superpowers/specs/2026-11-06-simple-startup-and-milestone-closeout-design.md) consolidates the migration sequence, source reuse, accepted closeout requirements and acceptance checks. The proposed team/shared-worktree change remains on hold. The draft explicitly identifies the remaining coaching-default and lightweight adoption-gate proposals for human review; this ticket remains claimed until the handoff is accepted. No runtime behavior has been changed.

### 2026-11-06 — Review decisions on the draft handoff

HinchK accepted the three open proposals:

- **Coaching default:** at most three focused questions, then a compact saved brief; consequential gaps stay explicit; no permanent coaching seat.
- **Improvement gate:** the per-candidate gate in the draft handoff, with at least two repeat comparisons as the initial requirement (the exact count is tunable when built). It replaces the numeric gate from the bypassed experiment.
- **Topology:** proceed on the current topology; the held team and shared-worktree change is recorded as deferred in the map's Not yet specified section.

HinchK also approved: landing these planning edits on a separate `docs/ehs-handoff` branch for merge review (this agent does not touch or move `main`); five new glossary terms (milestone closeout, Four-T scorecard, self-improvement toggle, recovery branch, improvement gate) with no ADR; and clearing the three remaining fog items, since two depended on bypassed work and one is resolved by this handoff. Final acceptance of the handoff is still pending, so this ticket stays claimed.

### 2026-11-06 — Resolution: handoff accepted

HinchK accepted [Simple startup and milestone self-improvement](../../../docs/superpowers/specs/2026-11-06-simple-startup-and-milestone-closeout-design.md) as the build-ready implementation handoff. It orders four steps (coached setup and saved brief; recovered startup; toggle, exclusive improvement role and milestone closeout; safe cleanup and recipe improvement), each placed in an existing owner and paired with acceptance checks that end in `make check` on the final candidate and a visible Herdr walkthrough. The accepted decisions are the three-question coaching default, the per-candidate improvement gate with at least two repeat comparisons, and the current topology as baseline; the held team and shared-worktree change stays deferred in the map. Each requirement traces to a resolved decision in the spec's traceability section. This epic stops before implementation: no runtime behaviour, provider spending, merge or deployment is authorized by it.
