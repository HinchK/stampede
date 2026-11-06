---
id: EHS-05
title: "Choose the runtime boundary and operator experience"
type: wayfinder:prototype
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-01, EHS-04]
---

# Choose the runtime boundary and operator experience

## Question

What should an engineer actually do and see when starting, steering, pausing, resuming, and reviewing this loop, and which existing Stampede components should support that experience?

Create only a cheap workflow outline or mock interaction for human reaction. Work within the Herdr-based pilot selected in [Define the first engineering workload and what better means](01-workload-and-success.md); decide which responsibilities belong to Herdr and which belong to Stampede. Ground reuse/removal choices in the existing code and pilot needs. Show the user's starter-task selection, team launch, task completion, selectable stopping controls, credential handoff, and resume. Avoid building a new dashboard or provider abstraction before the workflow is agreed.

**Intended Outcome:** A human-reviewed workflow prototype and runtime boundary decision.

Include the optional research-assisted kickoff requested in [Define the domain contract and smallest useful execution loop](04-domain-and-loop.md): how initial research agents are selected before the final team/epic is agreed, how contrasting views inform the interview, and how the human settles the goal and boundaries. Show the observing traffic-control panel and the separate request for a human grant; its authority is decided in [Define traffic-control supervision and human-proxy authority](12-traffic-control-authority.md).

Show how the operator can inspect contract-lawyer mediation records and receives a concise escalation for insufficient context or security/stability concerns. Routine mediation should proceed without requiring the user to approve every handoff.

**Done-Criteria:** HinchK has reacted to the prototype and chosen the experience plus the retain/replace boundary.

**Verification Step:** Link the artifact and actual human feedback; ensure the chosen workflow covers normal progress and intervention.

## Comments

### Prototype claim — 2026-11-06

Claimed for HinchK to walk through guided setup, assisted kickoff, ordinary progress, mediation, and stop/resume. The artifact is a proposal for human reaction, not a running swarm or a resolved runtime boundary.

### Walkthrough ready for human feedback — 2026-11-06

Artifacts: [operator workflow and source-grounded runtime boundary](../../../docs/prototypes/PROTOTYPE-stampede-operator.md), with a linked [interactive throwaway simulation](../../../docs/prototypes/PROTOTYPE-stampede-operator.html). Both are local proposals, not implementation or an accepted verdict.

The proposal preserves the existing public command, configuration, status, and integration foundations, with a new guided front door and on-demand team. Source review found that current setup requires AGY and detects only AGY/Claude/OpenCode; broader eligibility-aware setup is new work. Current source already supports bounded Resume Map, which corrects older memory but does not prove the proposed full continuity contract.

Verification: JavaScript parsed; nine in-memory transition assertions passed; all seven guided walkthroughs were exercised in a browser. No providers, Herdr sessions, credentials, deployments, or live runtime tests were used. The initial browser file-URL restriction was handled with a loopback-only preview server serving only the prototype directory. A missing favicon was cosmetic and has been removed.

Awaiting feedback on the guided front door, default operator view, and Herdr/Stampede retain/replace boundary. Keep this ticket claimed. Capture the prototype on a throwaway branch after its verdict is settled, per the prototype workflow.

### Resolution — 2026-11-06

HinchK selected **Keep setup and launch separate**, **Summary with worker drill-down**, and **Use this boundary and reuse plan** after the walkthrough was presented.

**Entry experience.** Keep preparation and execution distinct. Setup discovers eligible providers, guides team configuration and preparation of the starter-task brief, and saves the configuration without launching delivery workers. Launch is a separate action that revalidates the saved configuration, access, goal, and limits. Reuse the existing `setup` and `up` command vocabulary; the proposed combined `stampede start` front door is not adopted. Existing command behavior must be preserved through migration. Optional requested research-assisted kickoff remains bounded preparation, not implicit implementation authority. Returning users reuse saved setup after readiness checks.

**Default view.** One operator summary shows progress, stopping boundaries, usage/unknowns, and mediation. Live worker panes and detailed decision history remain available to inspect. The exact Herdr layout mechanism must use supported controls rather than assume pane-hiding features.

**Ownership and reuse.** Herdr operates terminal workspaces, panes, and agent sessions. Stampede owns goals, team configuration, scheduling, evidence, checkpoints, integration, enforced limits, and the operator summary. Retain configuration preservation, source-attributed status, and the hardened integration/promotion foundations; redesign fixed-seat setup and ordinary interruptions around on-demand work and contract-lawyer mediation. Model judgment does not replace deterministic authority enforcement.

**Verification and limits.** Revised the prototype to make setup completion explicit and block launch before setup is saved. Twelve in-memory assertions passed; all eight guided walkthroughs passed browser exercise, including setup-only, ordinary completion, mediation, escalation, credential handoff, proxy takeover, break/model handoff, and overall-limit stopping of improvements. These are simulation checks, not live Herdr, provider, persistence, or permission-enforcement tests.

**Artifact capture.** Reviewed prototype preserved on `codex/prototype-stampede-operator` at `2dda6b9a271ee11d8f670c6d1953273a62b206d5`. That local branch captures only the two prototype files relative to its base. The current branch and real staging index were preserved; nothing was pushed. Untracked preview copies remain locally accessible through the artifact links above. The prototype is not part of a main-branch commit and must not be shipped as runtime code.

**Next decision.** [Define traffic-control supervision and human-proxy authority](12-traffic-control-authority.md) is now unblocked. It settles actual grants, mediator/proxy precedence, revocation/expiry, and reserved human boundaries. Detailed recovery and integration semantics remain with their existing decision tickets. This closes the operator-experience decision, not the whole planning epic.

### Subsequent quota experience requirement — 2026-11-06

[Set replication, routing, resource, and authority limits](07-replication-and-routing.md) now records HinchK's requirement that capacity/quota management be requested at startup. Show this choice separately from setup versus launch and the supervision grant. When quota management is enabled, warnings appear in all panels at 20/15/10/5% remaining, offering wrap-up/wait or handoff/fork to another model. A summary-only warning is insufficient. The captured prototype predates this requirement and does not demonstrate it; its historical verdict remains valid for the setup/launch separation and runtime boundary it tested.

### Unanswered quota alerts — 2026-11-06

HinchK confirmed in [Set replication, routing, resource, and authority limits](07-replication-and-routing.md) that unanswered threshold alerts leave work running. When quota management is enabled, exhaustion triggers automatic designated-backup handoff; two distinct exhausted providers stop the run. The alert interface must offer early wrap-up/wait or transfer without turning every warning into a blocking prompt.

### Recovery and integration experience settled — 2026-11-06

[Define durable progress, recovery, and integration](06-continuity-and-integration.md) now specifies automatic continuation of unambiguous recovered work within valid authority, milestone-default integration, and an offer (not silent switch) to task-level batches when repeated friction warrants it. Show checkpointed work separately from integrated work, stop requested separately from observed stopped, and engineering progress separately from pending credential cycling. Local work and secret-free review PRs may continue while cycling is pending; base merges/final completion wait for verification.
