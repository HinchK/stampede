---
id: EHS-06
title: "Define durable progress, recovery, and integration"
type: wayfinder:grilling
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-04, EHS-05, EHS-07]
---

# Define durable progress, recovery, and integration

## Question

How does a long-horizon project make durable progress when agents stop, providers change, workers overlap, or the process restarts?

Decide authoritative state, checkpoints, dependency readiness, claim/retry semantics, context handoff, isolation, and integration evidence. Address a crash after a commit but before its receipt, exhausted quota mid-run, conflicting changes, and a stale checkpoint. Establish what survives every running agent disappearing and what requires a human decision.

Include the scheduled breaks and action/credential handoffs required by the [pilot brief](01-workload-and-success.md). Specify the state preserved at a pause, handling of in-flight workers, readiness revalidation, and resumption without duplicated actions or secret values entering checkpoints. Coordinate authority and stop precedence with [Set replication, routing, resource, and authority limits](07-replication-and-routing.md).

Include contract-lawyer mediation for disputed handoffs, missing context, stale or conflicting evidence, and failed recovery. Preserve the mediation decision alongside the checkpoint so replacement agents can recover what was decided; define behavior when the mediator itself stops.

Apply the optional scoped secret-exposure and credential-cycling policy from [Set replication, routing, resource, and authority limits](07-replication-and-routing.md). Design a durable cycling obligation using references and receipts rather than values, with replacement verification, old-credential revocation, authorized file updates, unsupported-service human handoff, and recovery from a stop between any two steps. Grant expiry and quota/run stops must leave pending cycling visible rather than silently marked complete or bypassed.

Use Herdr and provider-native session/permission/cancellation controls, retaining existing Stampede integration guards. The resource decision rejects a new enforcement controller, broker, or isolation layer; recovery design must work within actual native capabilities and report gaps.

**Intended Outcome:** A continuity and recovery contract compatible with the chosen runtime.

**Done-Criteria:** Ownership, persistence, retries, reconciliation, integration, and escalation are defined without relying on conversational memory.

**Verification Step:** Tabletop the interruption scenarios from known checkpoints and demonstrate exactly how duplicate work or false completion is avoided.

## Comments

### Accepted upstream handoff semantics — 2026-11-06

Implement the design mechanics around the accepted handoff contract in [Define the domain contract and smallest useful execution loop](04-domain-and-loop.md): stable work-item identity, separate attempts, progress/change/evidence/next-action handoff, successor revalidation, duplicate-result suppression, and reconciliation of late results. The completion contract is still under discussion; do not infer its acceptance from agreement on continuity.

### Accepted continuation and exhaustion-reset semantics — 2026-11-06

[Set replication, routing, resource, and authority limits](07-replication-and-routing.md) now records accepted separation of engineering attempts from interrupted worker sessions. A quota/process continuation does not spend a repair just for switching and never resets consumed repairs. Unknown/unusable designated backups pause affected work. The two-provider stop requires explicit resume and refreshed availability, retaining history while beginning a new exhaustion-counting period. Preserve these semantics in recovery design; the enforcement architecture remains under revision.

### Continuity decision claimed — 2026-11-06

Claimed for HinchK after domain, operator experience, and resource/authority decisions resolved. Earlier historical comments about pending completion/enforcement are superseded by those resolutions. Focus on persistence, crash recovery, integration cadence, stop handling, and cycling recovery; use Herdr/provider-native controls and existing Stampede foundations. No new enforcement service or runtime implementation is authorized.

### First continuity round — proposals awaiting HinchK — 2026-11-06

Three independent choices were submitted: (1) recover/continue unambiguous work on reopening under still-valid authority, versus asking before every continuation; (2) integrate accepted tasks incrementally into the run branch, versus milestone batches; (3) allow local work and secret-free review PRs while cycling is pending, but hold base merges/final completion, versus a different gate. None is yet accepted by this round.

### Draft continuity contract for source review and scenario checks

Reuse existing project-local state, worktrees, logs, provider session identifiers, and integration receipts. No new database, enforcement controller, broker, or cross-provider conversation replication is proposed. Exact state schema/location will follow the inspected repository conventions. A saved state file is a recovery aid, not proof that the filesystem, remote action, or provider session still matches it.

**Minimum recoverable record.** Track run/work/worker-attempt identity; goal and acceptance references; original grant/stop settings; provider/harness/model and native session identity; worktree/branch and base/result commit identities; ownership/dependencies; engineering repair usage; verification/review/integration receipt references; pending worker questions and mediation decisions; unfinished changes and next action; quota stop state when enabled; and any credential-cycling obligation by non-secret reference. Native transcripts are supplementary, not the only portable handoff. Do not copy secret-bearing context into a successor or indiscriminately mirror a vendor transcript.

**Checkpoint boundaries.** Save at work admission, before consequential external operations, after meaningful verified progress/integration, after mediation, and before handoff/pause when possible. Checkpoints should describe partial work rather than require a clean commit before every pause. Preserve dirty work in its existing worktree; do not reset/delete it to manufacture a clean recovery. Use existing safe state-write primitives; do not create a separate coordination service. An exhausted/crashed worker cannot be relied on to write its own final checkpoint.

**Reconciliation.** On reopening, inventory actual native sessions/processes and Git worktree/branch state, then compare it with saved records. Confirm the previous writer has stopped before replacement writes. A crash after a commit but before a receipt calls for inspecting that commit and completing missing verification/recording, not replaying the change. A repeated receipt does not apply the change twice. If the combined tree or base changed, verify the actual candidate again; earlier green results from a different tree do not establish acceptance. The contract-lawyer resolves ordinary state/evidence disagreements within the existing repair policy; genuinely unknown effects remain pending rather than guessed away.

**Stopping.** Use native interruption/cancellation and existing supervision controls. Stop admitting affected work at its selected boundary, preserve observable unfinished state, and report unresolved processes or remote effects honestly. Do not count a stop request as observed termination. Work-completion stops, timed breaks, hard run limits, credential handoffs, and revocation retain their already-agreed semantics. The detailed distinction between pause requested and safely quiescent must be visible without adding a new enforcement layer.

**Cycling recovery.** Record the obligation before approved exposure, then track each named credential through replacement requested/observed, dependent configuration updated where authorized, replacement verified, old credential revoked/verified, or human action required. Store service identifiers and non-secret receipts, not values. If a service call times out after possibly succeeding, inspect the service's state through a supported authorized read before retrying; where the outcome cannot be established, ask the human rather than issue repeated rotations blindly. A service without safe automation uses the guided manual path. A run stop/expired grant leaves pending cycling visible and does not authorize continued cleanup. The proposed merge/PR gate awaits the user's answer above.

These are proposed semantics for this decision, not implemented persistence or recovery guarantees. Source findings will distinguish existing mechanisms from additions, and the final resolution will retain only accepted policy and justified engineering details.

### Current-source recovery findings — 2026-11-06

Read-only delegated inspection found useful foundations and specific gaps:

- [Attention state](../../../lib/attention.py#L35) persists events, pauses, repairs, inflight decisions, approvals, and finished tickets with locking/atomic replacement. Interrupted decisions currently pause for inspection; autonomous reconciliation would be new behavior.
- [Worktree attachment](../../../lib/worktree.sh#L110) preserves existing work. [Normal teardown](../../../lib/worktree.sh#L187) checkpoints dirty tracked files and separately salvages non-ignored untracked files. Forced pruning and ignored files are exceptions; teardown salvage is not a continuous project checkpoint.
- [Lifecycle snapshots](../../../lib/lifecycle.sh#L545) copy four ledgers and raw transcript tails before closing panes. They omit attention/lease state from that ledger list, are not a demonstrated restore mechanism, and snapshot failure does not prevent teardown. Raw transcript copying must not leak values from the optional exposure mode into routine logs or portable handoffs; use non-secret recovery records and references instead.
- [Integration queue](../../../lib/arbiter.sh#L74) deduplicates queued ticket/SHA pairs and supersedes earlier queued SHAs for a ticket, but is not a completed-action deduplicator.
- [Ref/queue handling](../../../lib/arbiter.sh#L125) and [receipt writing](../../../lib/arbiter.sh#L433) are separate operations. A ref can advance before its queue/receipt record is updated. Recovery must inspect the actual integrated history/tree and missing records before retrying, not assume the queued action has never happened.
- [Combined-tree verification](../../../lib/arbiter.sh#L359) already tests the candidate built on the current integration tip, checks for tree drift, and uses expected-ref advancement. Preserve these checks and their explicit conflict/failure outcomes.
- [Lease state and reconciliation](../../../lib/partition.sh#L393) are durable but roster-based: a seat disappearing can release a lease without proving its process stopped. A missing seat is not sufficient evidence to start a conflicting writer.
- [Attention pause/resume](../../../lib/attention.py#L98), [headless termination](../../../lib/headless.sh#L195), and [pane teardown](../../../lib/lifecycle.sh#L700) do not collectively prove that every descendant/remote effect has quiesced. Distinguish dispatch paused, interruption requested, and observed stopped in the recovery record.

No live recovery, provider sessions, credentials, or cancellation tests were run. These findings inform the proposal and the later disposable validation plan. The three human choices remain pending; this decision stays claimed.

### Recovery, milestone integration, and cycling gate accepted — 2026-11-06

HinchK selected **Recover and continue within valid authority**. On reopening, reconcile saved state against Git and actual provider sessions, then continue unambiguous authorized work without a fresh question for each task. The contract-lawyer handles ordinary discrepancies. Expired authority, uncertain side effects, and security/stability concerns retain their agreed pause/escalation behavior; reopening does not renew a grant.

For integration, HinchK chose **milestone boundaries by default**, with an offer to reduce the batch to task-level integration when the user encounters repeated friction. This replaces the proposed incremental default. The swarm may recognize repeated conflicts, mediation, or rework and recommend the change, but must not silently switch cadence or change the meaning of the agreed milestone. Preserve the existing review and combined-code checks at either cadence; base-branch merging remains a separate opt-in.

HinchK selected **Allow review; hold merge and completion** while credential cycling is pending. Local work and secret-free review PRs may continue under valid authority, but base-branch merges and final run completion wait for the required cycling pass to be verified. Mark delivery progress separately from unresolved cycling; do not hide the pending obligation merely because engineering checks passed.

The source/design check below will reconcile milestone batching with current dependency/lease behavior before recording the complete resolution. No runtime changes or live recovery tests are authorized by these answers.

### Resolution — 2026-11-06

HinchK accepted automatic recovery/continuation under valid authority and allowing review while holding base merges/final completion for pending credential cycling. HinchK chose milestone-boundary integration as the default, with an offer to switch to task-level batches when repeated friction warrants it. This resolution supersedes the incremental-integration recommendation and earlier pending-status comments.

**Authoritative state and checkpoints.** Use Git/worktrees for actual code and commit identity, and existing project-local Stampede state for work lifecycle, ownership, grants/stops, repair usage, native session references, evidence/receipts, and mediation. Extend the current lock/atomic-write conventions with the minimal run/checkpoint references needed; introduce no new database or enforcement service. A checkpoint records run/work/attempt identity, dependency/base/result SHAs, native provider/harness/model/session, unfinished changes, next action, verification and integration evidence, current questions/decisions, and non-secret cycling obligations. Provider conversations supplement that record; they are not the sole source of continuity. Never copy secret-bearing transcript tails into routine recovery logs.

Checkpoint at admission, before consequential external operations, after verified progress/mediation/integration, and before handoff or pause when possible. Preserve dirty tracked and untracked work in its worktree without force-resetting or pruning it to make recovery appear clean. The record may truthfully describe incomplete work. Recovery cannot depend on an exhausted or crashed model emitting one last summary. Existing teardown salvage is a fallback, not proof that all state has a continuous checkpoint.

**Reopening and ownership.** On explicit reopening, compare saved records with actual Git refs/worktrees, native sessions/processes, lease state, and available action receipts. If the same goal, permissions, and original time window remain valid, continue unambiguous work automatically. Do not renew grants or clear explicit user/quota stops by reopening. A surviving worker is reattached rather than duplicated. A replacement may write only after predecessor quiescence and ownership are established; a missing roster entry or deleted PID file alone is not that evidence. Preserve the work identity and engineering repair count through model/session changes. A replacement mediator reloads the recorded decisions instead of inventing a new contract.

**Milestone integration and dependencies.** Default to milestone batches. Completed subtasks retain their worker-branch commits/checkpoints and review evidence until the batch integrates; this is not shared-branch integration or final milestone acceptance. For the smallest pilot adaptation, group a dependent subtask chain into one milestone dispatch/integration unit and process that chain serially on its owned work branch/worktree. Pin each predecessor checkpoint so later subtasks can build on verified progress without falsely labelling it integrated. Independent work may proceed in disjoint owned partitions, with all required heads identified before assembling the milestone candidate. Retain ownership through integration; do not release overlapping claims merely because a subtask finished. This grouping/dependency-readiness behavior is a required adaptation to current source, not a shipped capability.

At the boundary, assemble the batch in the existing candidate/worktree flow against the current shared run-branch tip. Preserve the reviewer and combined-tree test requirements; publish the candidate only when its exact tree passes and the expected old ref still matches. Record included task/head identities and outcomes. If the base moves or the candidate changes, reconcile and verify the actual new candidate before advancing; never reuse green evidence for a different tree. Base-branch promotion remains a separate opt-in and must honor the cycling/production boundaries.

The contract-lawyer records repeated integration conflicts, mediation, or rework and offers task-level integration when smaller batches would help. The user chooses whether to switch; no hidden automatic cadence change or invented friction threshold. Save the chosen cadence and apply it at a coherent checkpoint so already integrated work is not replayed. Either cadence retains the same evidence and ownership standards.

**Crash reconciliation and stopping.** Distinguish an operation requested, observed completed, and durably receipted. A crash after ref advancement but before queue/receipt updates requires examining Git history/tree and operation identity before repairing records; do not apply the change twice. A missing receipt is not proof that the action failed. If evidence cannot establish the outcome, pause affected work and mediate; seek human input for genuinely missing context or security/stability implications. A completed result without checks remains unaccepted.

Use native interruption/cancellation and existing supervision controls at selected stops. Stop new affected dispatch, preserve observable state, and distinguish interruption requested from observed stopped. Do not extend a hard deadline to finish a checkpoint or claim remote effects were undone. If a provider cannot establish a stopped writer, preserve the unresolved status and withhold conflicting successor writes. The already-agreed quota reset, grant validity, local versus run-wide pause, and separate improvement-allowance rules remain unchanged.

**Credential cycling and completion.** Record the obligation before approved disclosure. Track each named credential by non-secret reference through replacement requested/observed, authorized dependent configuration updated, replacement verified, and old credential revocation verified, or human action required. Use the service's supported safe order; where overlapping credentials/automation are unsupported, guide the human instead of assuming universal rotation capability. After an interrupted call, query supported service state before retrying; if the outcome cannot be determined, keep it pending and request the necessary human action. Preserve obligation/receipts across provider switches, quota stops, grant expiry, and restart without recording values. Pending cleanup does not extend authority or override stops.

While cycling is pending, local work and secret-free review PRs may continue under valid authority. Base-branch merges and final run completion are held until the required pass is verified. Display engineering progress and cleanup status separately. The allowed review PR must not trigger a production change or silently auto-merge around this gate.

**Scenario verification (design walkthrough, not live tests).**

| Scenario | Required outcome |
| --- | --- |
| All agents disappear | Reload non-secret project state, inspect actual Git/session status, and recover only what remains authorized and unambiguous. |
| Worker commits then crashes before reporting | Preserve/find the commit, reconcile its work identity, perform missing checks, and record it once. |
| Integration ref advances before receipt is written | Inspect the exact included commits/tree; repair missing records only with supporting evidence; do not merge twice. |
| Quota expires mid-edit | Preserve dirty work and the current engineering attempt; use the agreed backup policy and native stop checks before successor writes. |
| A checkpoint names an old base | Reconcile against current refs and verify the resulting candidate; the old checkpoint is not current acceptance evidence. |
| Dependent task in an unfinished milestone | Continue from a pinned verified predecessor in the owned batch; do not require premature shared integration or allow overlapping writers. |
| Friction repeats | Record causes and offer smaller batches; wait for the user's cadence choice without stopping unrelated authorized work. |
| Rotation call succeeds but its response is lost | Inspect supported service state; do not blindly create/revoke more credentials or clear the obligation. |
| Cycling remains pending at a stop | Preserve and surface it; allow only still-authorized work, hold base merge/final completion, and obtain authorized continuation or human action. |

**Source and limitations.** The source findings above identify reusable state, worktree, lease, and integration mechanisms, including their known gaps. A follow-up delegated source check was unavailable due to its usage limit; the primary agent directly inspected `Attention._ticket_settled`/`next_ready_ticket`, lease acquisition, and `_arb_integrate` to verify the milestone dependency issue. No runtime code, live recovery, provider execution, secret values, or rotation actions were exercised. Native capability validation remains an implementation gate, not evidence supplied by this planning decision.

**Next decision.** [Define how harness improvements are proposed, evaluated, and adopted](08-harness-evolution.md) is next in map order. It must use these checkpoint, integration-cadence, evidence, and cleanup rules without reintroducing a separate enforcement layer.
