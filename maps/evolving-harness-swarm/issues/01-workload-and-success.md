---
id: EHS-01
title: "Define the first engineering workload and what better means"
type: wayfinder:grilling
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: []
---

# Define the first engineering workload and what better means

## Question

For the first Stampede pilot, what engineering work and user experience must the design support, and which outcomes would justify adopting it?

Choose a representative project or task family, what counts as long-horizon work, the intended engineer's normal interaction, and the quality, human-time, elapsed-time, and resource tradeoffs that matter. Decide how to treat negative results. Identify any hard constraints on environments, subscriptions, paid APIs, or preserving current workflows; do not assume a provider or model roster.

A concrete scenario to discuss: the swarm finishes faster but takes twice as much human review. Would that count as a win, a loss, or a tradeoff to report?

**Intended Outcome:** A bounded pilot brief and success criteria that can guide the design and evaluation.

**Done-Criteria:** HinchK has chosen the pilot profile, priorities, non-negotiables, and meaning of a useful result.

**Verification Step:** Check the resolution against the user's live answers and record remaining uncertainties as new questions, not invented preferences.

## Comments

### Pilot framing from HinchK — 2026-11-06

- **Workload:** changes to Stampede itself, working with the Herdr core and a guided setup CLI that checks the current terminal for agent providers and walks the user through assembling a team.
- **Run horizon:** initially four hours; later eight hours, then forty hours, with further expansion after that. These are progressive targets, not evidence of current capability.
- **Primary adoption criterion:** reduced human effort; "set it and forget it."
- **Interaction:** milestone check-ins are an accepted starting point. Users should also be able to select sprint, milestone, or epic stopping points and time-based breaks at 2, 4, 8, or 20 hours.
- **Action boundaries:** support stops before pushing code to production and registering for a service.
- **Mandatory secrets boundary:** hard-stop whenever secrets need to be handled. The user suggested an instruction/code snippet to run in an outside session or a suitable `.env` workflow. No particular mechanism has been selected and no permission to read, collect, or change secrets has been granted.

At this point in the exchange, the finish line, existing-authentication boundary, and effort/time tradeoff remained open. The resolution below records HinchK's subsequent answers. Detailed stopping, checkpoint, resource, and credential-handoff mechanics belong to the later experience, continuity, and authority decisions.

### Resolution — 2026-11-06

HinchK selected Stampede itself as the pilot project and confirmed the following brief through the live exchange.

**Pilot and finish line.** Improve guided CLI setup around the Herdr core. Discover the agent providers available from the user's terminal, guide team assembly, launch the configured team, complete a small user-initiated task, and demonstrate stopping and resuming. Configuration generation alone is not completion. Setup must include the user's choice or definition of a starter task: containerization, preparation for public/open-source release, a custom sprint, or a bugfix are candidate task families, not a requirement to implement all of them at once. Choosing a release-preparation task does not authorize publishing or exposing private material.

**Run horizon and stopping controls.** Initially design for four-hour runs, then eight-hour and forty-hour targets, with further expansion later. Milestone check-ins are the starting interaction pattern. Support selectable sprint, milestone, and epic stopping boundaries; time-based breaks at 2, 4, 8, or 20 hours; and stops before production deployment and service registration. The relationship between a run horizon and intermediate breaks, timing semantics, checkpoint behavior, precedence, and resume authority must be specified by the later domain, experience, continuity, and authority tickets.

**Secrets boundary.** Existing authenticated provider CLIs may use their stored login normally. When credentials must be added, changed, recovered, or revealed, Stampede must stop for a human handoff. Secret values must stay outside agent conversations, logs, and generated instructions. A provider login flow, a non-secret instruction/code snippet executed in an outside session, or a local `.env` workflow with named placeholders may support the handoff. Resume requires a readiness check that does not return secret values. The mechanism and its enforcement remain design work; this decision does not authorize reading or modifying credentials now.

**Adoption and measurement.** Reduced human effort is the primary benefit: "set it and forget it." HinchK accepted slower elapsed completion when it materially reduces involvement while preserving equivalent quality and all stopping boundaries. Measure active human minutes and unplanned interventions, and report elapsed time separately. Also require efficiency reporting that includes token velocity per model over time. The experiment protocol must define the token categories, measurement windows, accounting sources, version attribution, and missing-data behavior; token velocity alone does not establish useful engineering progress. Quality floors, numeric thresholds, budgets, and repeat counts remain protocol decisions.

**Scope and evidence.** This is a design and experiment-protocol decision. No runtime has been implemented or benchmark executed. The first four-hour pilot is a target, not a measured capability. Evidence is HinchK's explicit answers selecting this workload, the end-to-end finish line and starter task, the existing-login exception with external secrets handling, the effort/time tradeoff, and per-model token-velocity reporting.

**Downstream handoff.** [Define the domain contract and smallest useful execution loop](04-domain-and-loop.md) is now unblocked. [Choose the runtime boundary and operator experience](05-runtime-and-experience.md), [Define durable progress, recovery, and integration](06-continuity-and-integration.md), [Set replication, routing, resource, and authority limits](07-replication-and-routing.md), and [Choose the pilot configurations and freeze the experiment protocol](09-experiment-protocol.md) must carry these requirements forward without silently reopening them.

### Subsequent secret-mode refinement — 2026-11-06

HinchK later approved optional credential-scoped agent/provider access with a required managed cycling pass, recorded in [Set replication, routing, resource, and authority limits](07-replication-and-routing.md). The no-secret-access/human-handoff rule remains the default; that explicitly agreed mode is the exception. This pilot brief does not itself grant access to any live secret.
