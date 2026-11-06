---
id: EHS-04
title: "Define the domain contract and smallest useful execution loop"
type: wayfinder:grilling
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-01, EHS-02]
---

# Define the domain contract and smallest useful execution loop

## Question

What are the minimum concepts and transitions needed to run the selected workload across providers without recreating the current roster of permanent seats?

Define work, harness configuration, agent run, evidence, project checkpoint, and completion; settle terminology against CONTEXT.md. Decide the contract for inputs, permitted tools, outputs, acceptance checks, and stopping. Specify where deterministic control suffices and where a model decision is warranted. Clarify how several bounded runs constitute a swarm and how small models versus small assignments differ.

Stress-test a successful run with missing evidence, a duplicate completion, and a model switch halfway through a task.

Use the settled [pilot brief](01-workload-and-success.md) to distinguish the starter task from the project being developed, a run horizon from a break interval, and sprint/milestone/epic completion boundaries. Define how each boundary is evidenced so a model's declaration alone cannot trigger success or conceal unfinished work.

**Intended Outcome:** An agreed minimal domain and loop contract.

**Done-Criteria:** Terms, transitions, evidence requirements, and provider boundary are settled; accepted terms are recorded in the glossary.

**Verification Step:** Walk the contract through the pilot and edge cases with HinchK; every terminal outcome must have an unambiguous meaning.

## Comments

### Domain direction from HinchK — 2026-11-06

- Accepted a team configuration of providers and specialist harness recipes, with workers started on demand.
- Accepted autonomous decomposition and ordinary replanning within the agreed outcome and boundaries. Added an optional startup interview that helps engineer the initial prompt/epic, using multiple Herdr agents for research and contrasting opinions (including conservative review, feature exploration, and cleanup perspectives). The interview must establish the goal and boundaries with the human.
- Replaced a small-model-first default with a Sonnet-level capability baseline, recommending stronger available models for demanding planning/work and cheaper/faster models for appropriate easy tasks after considering usage. The example mappings across Claude, Codex/Astra, Gemini Flash, OpenCode, ZCode, Cursor, and AGY are hypotheses explicitly submitted for research, not accepted rankings.
- Accepted deterministic routine loop control, with an optional loop-traffic-control agent. Proposed `--yolo` creates an observing panel receiving handoff notes, recording metrics, per-agent time, and errors. Human interaction prompts it to request permission and stopping conditions before becoming a human proxy. The proxy would answer routine worker questions using recommendations or best guesses and keep work progressing. The flag alone does not constitute the later takeover permission described by the user.
- Normal operation should target a sprint or milestone and fan out useful work. The user also proposes pivoting to insights/improvements at a milestone boundary, including agent directives, hooks, and skills. The relationship between this pivot and an explicitly selected stopping boundary remains to be clarified.

These directions do not authorize live launches, credential handling, permission bypasses, changes to production, or runtime edits in this planning session. Human-proxy authority and the inherited mandatory secret boundary need an explicit design reconciliation.

### Work boundaries and supervision direction confirmed — 2026-11-06

HinchK selected **broader authority, explicitly scoped** for traffic-control supervision. Do not narrow the intended proxy to routine implementation questions only. The grant's delegable actions, limits, expiry, and reserved human actions remain to be decided in [Define traffic-control supervision and human-proxy authority](12-traffic-control-authority.md). This answer does not itself enumerate those actions or revoke the previously mandatory credential handoff.

HinchK accepted an optional **separate improvement allowance**, agreed at startup. On reaching the selected sprint/milestone stopping point, delivery pauses; improvement work may proceed only under that allowance. Without it, the swarm pauses. An overall time or budget limit stops both phases.

HinchK accepted the work definitions: **epic** is the overall agreed outcome; **milestone** is a demonstrable result with acceptance checks; **sprint** is a bounded selection of work toward milestones. A **timed break** pauses progress without declaring any work boundary complete. These terms are recorded in CONTEXT.md.

The ticket remains claimed pending agreement on the minimal work/evidence contract and its failure, duplicate-result, and model-switch scenarios.

### Minimum execution contract proposed for discussion — 2026-11-06

Proposal, not yet accepted: a work item carries its goal, dependencies, allowed changes/tools, acceptance checks, and limits. A worker attempt uses a particular harness/model configuration and returns changes or findings plus check evidence. A result is accepted only when the agreed checks support it; missing evidence means awaiting verification, failed checks mean rework or escalation, and a pause preserves unfinished work rather than declaring success. Required accepted work determines sprint/milestone/epic completion; a worker's declaration alone is insufficient.

Proposal, not yet accepted: retain one work-item identity through retries and model switches, but record each worker attempt separately. A checkpoint preserves accepted progress, unfinished changes, evidence, and the next action. A successor revalidates inherited state. Repeated delivery of an already processed result does not integrate or count it twice; a late result from a replaced attempt requires reconciliation before acceptance. Replacement cannot silently create concurrent writers to the same work. These are proposed domain rules; persistence, locking, and recovery mechanics belong to the continuity ticket.

### Handoff accepted; completion contract requires adjustment — 2026-11-06

HinchK accepted the handoff contract: retain the same work item when a worker stops or switches models, record each attempt separately, and hand over accepted progress, unfinished changes, evidence, and the next action. The successor rechecks inherited state. Duplicate results count once; late results from replaced workers require reconciliation. This settles those domain semantics; detailed ownership, persistence, and recovery mechanisms remain in the continuity ticket.

HinchK selected **Adjust the completion contract**. The proposed work-item requirements, evidence/acceptance rules, and failure outcomes are therefore not accepted as a complete contract. A clarification is pending on what should change. Do not infer that this answer waives verification or requires human approval of every subtask; previously accepted autonomous decomposition within agreed boundaries remains in place. The ticket stays claimed.

### Contract-lawyer mediation requested — 2026-11-06

HinchK clarified the completion-contract adjustment: one **contract-lawyer agent** helps with handoffs, handles decisions arising from them, and records every friction event or failure event that requires mediation together with what was decided. Mediation should almost never require human input; escalate when the agent lacks sufficient context or security/stability implications are involved. This is a requested autonomous mediation role, not a requirement for per-task human approval.

The previously accepted handoff semantics remain in force. The completion proposal is being refined with this mediation role; it is not yet a fully resolved acceptance policy. The earlier mandatory credential handoff and selected action/time/budget stops have not been revoked.

Proposed division of responsibility: traffic control observes or, under its grant, coordinates continued execution; the contract-lawyer resolves disputed requirements, evidence, and handoffs within the agreed authority. Ordinary passing work need not wait for model-mediated arbitration. Recover context and request checks or corrective work autonomously before escalating an unresolved context gap. A mediation record should link the event and work/attempts, timestamps, available evidence, decision and rationale, follow-up, and outcome. Detailed precedence, unavailable-mediator behavior, bounded recovery, and escalation mechanics belong to the authority and continuity tickets.

One remaining completion-policy question: may the mediator clarify or replace an inadequate check while preserving the agreed outcome and quality requirements, with recorded justification and supporting evidence, but never declare unsupported success merely to keep the swarm moving? This recommendation awaits HinchK's answer.

### Resolution — 2026-11-06

HinchK accepted the contract-lawyer's proposed completion authority, resolving the remaining domain-contract question. This resolution supersedes the pending/proposed status of the completion and handoff contracts in the earlier discussion; it does not settle the downstream implementation or detailed supervision mechanisms.

**Work and loop.** The human establishes the epic goal and boundaries, optionally through research-assisted kickoff. A team configuration supplies providers and harness recipes; workers start as useful work becomes ready. The swarm decomposes and replans routine work within those boundaries without per-subtask human approval. Work carries an outcome, dependencies, permitted changes/tools, acceptance checks, and limits. The minimal loop is select ready work, start an attempt, collect its result and evidence, verify or mediate, accept or rework, checkpoint, and continue subject to the stop policy. Routine bookkeeping and limits belong to deterministic control; decomposition, research, and disputed handoffs use model judgment.

**Completion and mediation.** One contract-lawyer agent mediates handoffs and disputed completion. It may autonomously clarify requirements, replace a faulty check with an equivalent one, and order verification or rework, recording its rationale. It must preserve the agreed outcome, quality requirements, and hard stops; it cannot mark unsupported work complete to keep agents moving. Every friction/failure event requiring mediation and its decision is recorded. Human input should be rare, reserved for insufficient context or security/stability implications and the previously agreed mandatory boundaries. This authority does not confer new production, service-registration, credential, or spending permissions.

**Handoff and evidence scenarios.** Missing evidence prevents acceptance and leads to verification or mediation, rather than a false success. Failed checks lead to correction or an evidence-backed equivalent check where the original was faulty. A duplicate result counts once; late results from replaced workers require reconciliation. A model switch preserves the work-item identity while creating a separate attempt; the successor receives accepted progress, unfinished changes, evidence, and next action and rechecks inherited state. Pausing preserves unfinished work. These are the agreed outcomes of the scenarios discussed with HinchK, not results of live tests.

**Boundaries.** An epic is the overall agreed outcome, a milestone a demonstrable result with acceptance checks, and a sprint a bounded selection of work toward milestones. A timed break is a pause, not completion. At a selected delivery stop, improvement work requires the separate startup allowance; overall time/budget limits stop both phases. The optional traffic-control observer can take broader explicitly scoped proxy authority only through a human grant. Its exact scope and interaction with mediation remain a downstream authority decision.

**Provider boundary.** Work identity, accepted progress, and evidence survive changes of provider or model; attempts record their particular configuration. Sonnet-level is the default capability tier, with stronger or cheaper suitable routes recommended according to available access, usage, and evidence. Named provider-role assignments remain hypotheses from the routing research, not fixed rankings.

**Handoff to remaining decisions.** [Choose the runtime boundary and operator experience](05-runtime-and-experience.md) is now unblocked. It will make this contract concrete in the guided setup and operator workflow. Detailed persistence, ownership, integration, supervision precedence, escalation thresholds, resource limits, improvement promotion, and experiment measurements remain with their existing tickets. No runtime implementation or live reliability claim is part of this resolution.
