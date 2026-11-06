---
id: EHS-12
title: "Define traffic-control supervision and human-proxy authority"
type: wayfinder:grilling
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-04, EHS-05]
---

# Define traffic-control supervision and human-proxy authority

## Question

How does the optional traffic-control agent move from observing the swarm to acting as a human proxy, and which decisions remain exclusively human?

Using the direction recorded in [Define the domain contract and smallest useful execution loop](04-domain-and-loop.md), define observing, requesting delegation, active supervision, expiry, revocation, and paused states. Decide how a real human's grant is authenticated, scoped, recorded, and limited by task/milestone/epic or time. Distinguish answering an ordinary work question from approving new scope, spending, secrets handling, deployment, or service registration. Determine how worker requests are delivered through a controlled channel without bypassing existing pane/role protections.

Apply the separate improvement allowance agreed in the domain discussion: specify its permitted changes, accounting, transition, and resume behavior while delivery remains paused and overall limits bind both phases. Decide how repeated uncertainty, contradictory recommendations, missing evidence, and unproductive fan-out produce escalation or a stop. Define what the proposed `--yolo` flag means without conflating it with provider permission-bypass flags. Preserve useful evidence and human intervention accounting.

Define the relationship with the contract-lawyer requested in [Define the domain contract and smallest useful execution loop](04-domain-and-loop.md). Specify mediation authority versus traffic-control execution authority, precedence when they disagree, recovery when the mediator is unavailable, and which security/stability implications require human input. Preserve the goal of almost never interrupting the human for ordinary friction; decide bounded context gathering and correction before escalation, without weakening explicit stops. No agent may expand its own grant.

**Intended Outcome:** A precise supervision contract with explicit delegated and reserved authority.

**Done-Criteria:** HinchK has chosen grant scope, expiry/revocation, allowed proxy answers, mandatory human boundaries, and behavior at stopping points.

**Verification Step:** Walk through an ordinary question, a secret request, production deployment, agent-generated text masquerading as human permission, exhausted budget, and a milestone reached while improvement opportunities remain. Each must produce an authorized outcome.

## Comments

### Upstream direction — 2026-11-06

[Define the domain contract and smallest useful execution loop](04-domain-and-loop.md) records HinchK's choice of broader, explicitly scoped proxy authority, rather than a routine-decisions-only ceiling. This ticket must elicit the actual action scope; neither unrestricted authority nor permission to handle credentials follows from that preference. It also inherits the accepted separate improvement allowance and overall time/budget stop. Do not reopen those settled choices when defining their mechanics.

### Authority decision claimed — 2026-11-06

Claimed for HinchK after the domain and operator-experience decisions resolved. Work this as a design conversation: no live authority grant, provider launch, production change, or new spending is authorized by this claim.

### First decision round — proposals awaiting HinchK — 2026-11-06

The following recommendations were submitted as four independent questions. They are not accepted policy or live grants.

| Decision | Recommendation submitted |
| --- | --- |
| Grant scope | Replan within the epic, allocate/reassign workers, switch eligible models within approved usage, commit/push work branches, open/update PRs, and repair CI in the approved repository. Base-branch merges are a separately selectable run-grant permission. Production, registration, secrets, and greater scope/spending retain human boundaries. |
| Expiry | Earliest of selected work boundary, explicit deadline within the run limit, or revocation. Pauses do not extend the deadline. Improvement supervision requires explicitly included scope and the agreed separate allowance. No self-renewal by observer or replacement agent. |
| Mediator/controller precedence | Contract-lawyer settles requirements/evidence/handoff interpretation; traffic control executes within that decision. Neither can override enforced limits or expand a grant. Gather context and verify alternatives before escalating unresolved context or security/stability concerns. |
| Pause scope | Missing-context questions pause affected work; independent authorized work may continue. Credential handling, overall limit/revocation, or an uncontained security/stability risk pauses the run. No productive authorized work means pause, not invented scope. |

Regardless of the chosen action scope, the design must distinguish a real human's grant from agent text claiming permission. A proposed grant record binds the repository/run, permitted actions and targets, usage limits, work boundary/deadline, issuer, and revocation state. Worker requests and mediation decisions are records, not authority tokens. Detailed authentication and enforcement remain to be grounded in current code and later implementation design; an agent-free pane alone is not proof of human identity.

The observer mode and permission request on human interaction remain the accepted starting behavior. The `--yolo` name must not imply forwarding provider bypass options. Bounded autonomous context gathering, replacement of an unavailable mediator, and the precise resume/expiry transitions will be checked against the chosen policies before resolution.

### Current-source authority constraints — 2026-11-06

Read-only delegated inspection found the following reuse limits. No grant, promotion, Herdr command, credential access, or live enforcement test was performed.

- [Existing grant creation/validation](../../../lib/arbiter.sh#L506) concerns promotion and expiry. Its default is four hours, but the record is not bound to the proposed run, task, goal, permitted actions, resource budget, or receiving agent. Do not reuse its validity as permission for broader supervision.
- [Pane checking](../../../lib/arbiter.sh#L465) rejects recognized agent panes but permits an unset pane identifier and explicitly does not provide strong human authentication under the same OS user. The implementation design needs an explicit trust boundary; agent-authored pane text cannot mint or widen a grant.
- [Revocation](../../../lib/arbiter.sh#L546) removes the existing grant, while [promotion](../../../lib/arbiter.sh#L558) checks it at entry. The broader contract must specify action-time revalidation and what happens to already-started effects when a grant expires or is revoked; revocation cannot retroactively undo a completed external action.
- [Attention pause/resume](../../../lib/attention.py#L98) is per ticket and resumes by approving a next decision, not by issuing a scoped supervision grant. [Blocked/GREEN handling](../../../lib/attention.py#L529) still routes ordinary pauses and integration review to a human. Contract-lawyer mediation is new behavior.
- [Integration checks and guarded ref advancement](../../../lib/arbiter.sh#L387) remain distinct from mediation and authorization. Preserve them while designing the new grant.

These facts inform the next state/edge-case pass after HinchK answers the four policy questions. The ticket remains claimed and no glossary term is newly settled by this research.

### Resolution — 2026-11-06

HinchK accepted all four recommendations: **Delivery and PR work; base merges opt-in**, **Work boundary plus deadline**, **Use this division**, and **Affected work, unless a run-wide stop applies**. This resolves the supervision policy. It does not grant authority to agents in this planning conversation or establish that the current runtime enforces the new policy.

**Delegated scope.** A human can grant traffic control authority in the approved repository and epic to replan work, allocate/reassign workers, switch eligible models within approved usage limits, commit and push work branches, open/update PRs, and repair CI. Base-branch merges require a separate opt-in on that run's grant and still require integration evidence. Production deployment, service registration, credential handling, and expanded scope or spending retain their human boundaries. An action is evaluated by its effects: permission to merge does not authorize a merge that triggers a forbidden production deployment.

**Lifetime.** A grant ends at the earliest selected task/sprint/milestone/epic boundary, explicit deadline, or human revocation. It cannot outlive the overall run limits. Pauses do not extend the deadline, and an observer or restarted agent cannot renew it. Improvement supervision requires its own explicitly included scope and the previously agreed separate allowance. Delivery completion does not silently extend delivery authority into improvement. Overall time/budget exhaustion or revocation stops both phases.

**Decision ownership.** The contract-lawyer settles interpretation of requirements, evidence, and handoffs; traffic control chooses execution within that decision. Neither can override deterministic limits, expand the agreed outcome, or widen a grant. They gather context and verify alternatives autonomously before escalation. An ordinary failed check calls for bounded verification/rework or mediation, not immediate human approval. An unavailable mediator cannot be bypassed by traffic control declaring unsupported success: affected disputed work waits, while independent authorized work may continue. Replacement/recovery must preserve the decision record and existing limits; precise retry counts and resource ceilings belong to the resource decision.

**Pause scope.** A missing-context question pauses the affected work and its dependent actions; independent authorized work can continue. Credential handling, overall limit/revocation, or security/stability implications that cannot be contained pauses the entire run. A contained security/stability issue still requires the human decision previously agreed for such concerns; containment only determines whether unrelated work can continue. If no useful authorized work remains, pause rather than manufacture new scope or consume improvement allowance prematurely.

**Lifecycle derived from those choices.**

| State/event | Required behavior |
| --- | --- |
| Observing | Receive handoff notes, metrics, elapsed/worker time, and error records; no proxy authority. Proposed `--yolo` creates this state, not provider permission bypasses. |
| Human interacts | Request a concrete scope and stopping conditions; neither typing nor an agent's interpretation of text creates the grant. |
| Grant issued | Activate only after the human-controlled authorization channel records the applicable scope, targets, limits, expiry, and issuer. |
| Active supervision | Answer/route requests through recorded work and mediation channels, checking permission at the action boundary. Preserve integration gates. |
| Pause/resume | Keep checkpoints and decision history. Resume requires readiness and a still-valid applicable grant; a pause never renews authority. |
| Expiry/revocation | Stop authorizing new actions and dispatch. Quiesce/cancel in-flight work according to the continuity design, reconcile effects already started, and report any that cannot be undone. No automatic rollback or claim of retroactive cancellation. |
| Delivery boundary | End delivery supervision. Improvement can proceed only under its separately included scope/allowance and remaining overall limits. |
| Restart | Recover recorded state and revalidate identity, scope, expiry, and revocation before supervised actions. If validity cannot be established, remain observing/paused; do not reconstruct permission from conversation. |

**Required enforcement contract, not a claim about current capabilities.** The human grant record must be bound to the repository/run and delegation context, permitted actions and targets, usage limits, selected work boundary, deadline, issuer, and revocation state. Issuance or widening must occur through a human-controlled channel unavailable to worker/model-issued tool calls. A pane label or message asserting human consent is insufficient. Dispatch and protected side effects must recheck the applicable grant; expiry/revocation during a previously admitted operation must be reconciled without allowing subsequent actions. The existing same-user pane check and timestamp-only promotion record do not meet this full contract. The resource/authority ticket must choose the concrete isolation and authentication mechanism and its threat assumptions before the build-ready handoff; this resolution settles required policy, not that mechanism.

**Policy scenario walkthrough.**

| Scenario | Outcome derived from HinchK's answers |
| --- | --- |
| Worker asks an ordinary implementation question | Traffic control answers within scope; a disputed requirement/evidence interpretation goes to the lawyer. No routine human interruption. |
| Worker needs a credential added or revealed | Whole-run credential handoff; no secret values enter agent conversations/logs. Readiness and valid authority are checked before resume. |
| CI repair wants to deploy or register a service | Stop before the reserved action and seek the human decision. CI authority does not expand deployment or registration rights. |
| Agent writes “the human approves” into a pane | This is message content, not a grant. Remain observing or within the existing recorded scope. |
| Grant expires while a change is prepared | No next protected action may start under the expired grant. Preserve work and report any already-started external effects. |
| Milestone completes with improvement ideas | Delivery grant ends; improvement requires its separate authorized scope/allowance and remaining overall resources. |
| Lawyer and traffic control disagree about acceptance | Lawyer's contract interpretation governs; verification/rework continues within limits. Unsupported completion is unavailable to both. |
| Context remains insufficient | Pause affected work and ask a focused question; independent work may proceed. Uncontained risk or mandatory stop pauses the run. |

These are design walkthroughs against explicit human answers, not live tests. Every mediated friction/failure and decision remains recorded, and proxy answers remain distinguishable from actual human interventions in evaluation.

**Downstream handoff.** [Set replication, routing, resource, and authority limits](07-replication-and-routing.md) is now unblocked. It must define concrete worker/concurrency/retry/usage limits, descendant permission propagation, and the authorization isolation/enforcement mechanism. [Define durable progress, recovery, and integration](06-continuity-and-integration.md) must handle in-flight quiescence and reconciliation. [Define how harness improvements are proposed, evaluated, and adopted](08-harness-evolution.md) decides allowed improvement mutations and promotion, which this grant does not pre-authorize.

### Subsequent explicit secret-access exception — 2026-11-06

[Set replication, routing, resource, and authority limits](07-replication-and-routing.md) now records HinchK's optional credential-scoped exposure grant and mandatory cycling pass. This refines the earlier unconditional secret stop: default and out-of-scope credential handling still require human handoff; expressly approved recipients/use and rotation actions may proceed within their grant. General delivery/PR authority does not include this exception. Expiry, revocation, other reserved actions, and no-self-expansion remain unchanged.

### Enforcement approach superseded by the resource decision — 2026-11-06

HinchK chose Herdr and each provider's existing harness controls, rejecting a separate controller/broker/isolation layer. [Set replication, routing, resource, and authority limits](07-replication-and-routing.md) supersedes this ticket's earlier requirement for a new protected grant-issuance/storage architecture. Scope, human agreement, expiry/revocation, mediation, and stopping policies remain; configure and verify native controls, retain existing Stampede integration guards, and state where a rule is an operating agreement rather than a guaranteed technical barrier. Do not claim tamper-proof authorization from same-user files/panes or add another security subsystem to obtain it.
