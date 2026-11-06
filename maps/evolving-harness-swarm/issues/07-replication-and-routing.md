---
id: EHS-07
title: "Set replication, routing, resource, and authority limits"
type: wayfinder:grilling
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-01, EHS-02, EHS-04, EHS-11, EHS-12, EHS-13]
---

# Set replication, routing, resource, and authority limits

## Question

When may a run request another worker, switch provider, escalate model capability, or stop, and whose authority and resources does each action consume?

Define replication of a configuration separately from changing the configuration. Apply startup opt-in for capacity/quota management; define user-selected capacity controls, child delegation, subscription exhaustion, designated backups, threshold alerts, and unknown-quota behavior. API and local-model support are deferred to a later iteration. Choose what all providers working in concert means operationally, including conditions where sequential execution is preferable. Determine which permissions children inherit and which actions always require external authorization.

Apply the stopping and credential boundaries accepted in [Define the first engineering workload and what better means](01-workload-and-success.md). Specify precedence among work, time, and action boundaries; whether a stop pauses one task or the swarm; the enforcement boundary for secret values; and how external credential handoff and readiness checks permit resumption without exposing secrets. Keep normal use of existing provider authentication distinct from changing or revealing credentials. Child delegation must preserve these requirements.

Apply the policy settled in [Define traffic-control supervision and human-proxy authority](12-traffic-control-authority.md), as refined by HinchK's decision to use Herdr and each provider's own harness. Specify how existing native permissions, approvals, session controls, and Stampede integration checks support the agreed behavior. Do not add a separate enforcement controller, permission broker, or isolation layer. State capability limitations honestly; operational policy must not be presented as stronger enforcement than the selected tools provide.

**Intended Outcome:** A routing and delegation policy with explicit resource and authority boundaries.

**Done-Criteria:** The user has selected the initial policy and escalation limits; descendants cannot silently create new budget or authority.

**Verification Step:** Walk through recursive delegation, provider exhaustion, repeated failure, and an attempted permission escalation; each has a bounded outcome.

## Comments

### Resource and delegation decision claimed — 2026-11-06

Claimed for HinchK after all five prerequisites resolved. This turn defines pilot policy and a concrete enforcement design; it does not launch workers, inspect account credentials, or authorize paid use. Existing provider research informs capability assumptions; actual available quota and containment remain unverified.

### Pilot policy round — awaiting HinchK — 2026-11-06

These are proposed starting parameters, not accepted limits or measured optima. Four independent questions have been sent:

| Topic | Recommendation submitted |
| --- | --- |
| Active jobs and replication | Four active agent jobs total: at most three delivery/review/research jobs and one reserved coordination/mediation slot. Idle panes do not count. Every new worker is admitted by Stampede against shared limits; no hidden recursive spawning. |
| Billing | Existing subscriptions by default. API billing, credit fallback, and overages require explicit opt-in with a per-run cap. A route switch must not silently change billing class. |
| Interactive reserve and unknown quota | Preserve 20% where trustworthy remaining-quota information exists. Unknown stays unknown; allow one active job per account with bounded attempts and cooldowns. Do not claim this guarantees a reserve. Exhausted routes yield to other approved eligible routes. |
| Routing and failed attempts | Automatic switching among approved routes within limits: Sonnet-level baseline, economical routes for suitable simple work, stronger routes when justified. One initial attempt plus two repair attempts per work item across providers. After exhaustion, record mediation and pause the work; do not reset the allowance by renaming/cloning it. |

The reserve is a scheduling target where observable, not an atomic reservation against other applications using the same subscription. Account-level caps must group multiple models/harnesses that consume the same account allowance. Provider-internal subagents, hidden retries, tool time, and coordination consume resources too; eligibility/accounting design must prevent them bypassing the stated limits. Detailed semantics and examples will be settled after the current answers.

### Enforcement design prerequisite

The prior authority decision requires a concrete human-controlled issuance and storage boundary unavailable to worker/model-issued tools. Current source facts are being checked before recommending the mechanism. In particular, a same-user file, pane label, or instruction to ignore protected files is not isolation. Protected operations must remain outside model authority, including grant writes, scheduler limits, privileged Git actions, and authority-bearing runtime configuration. Tool or network paths that can perform the same action directly must be considered as well as the intended broker path.

The design must distinguish a provider session's legitimate use of existing authentication from model-directed access to secret values, and cannot claim that mounting credentials into an arbitrary worker meets the credential boundary. It must also define what happens when a provider's native tool runner, nested agents, cancellation, or quota/overage settings cannot be constrained or verified. Compatibility with all installed tools does not establish eligibility for unattended execution.

Do not resolve this ticket solely on the four numeric/policy answers. A concrete isolation/trust model, grant propagation, usage admission, retry attribution, and the provider-exhaustion/recursive-spawn/permission-escalation walkthroughs must also be completed before resolution. No existing tool or account has been declared eligible for these guarantees.

### Source findings for the pilot policy — 2026-11-06

Read-only inspection supports retaining useful foundations but does not establish the proposed global limits:

- [Configured fan-out](../../../lib/config.sh#L153) emits a default worker value of two; inspection found no consumer enforcing it as a global agent cap in the runtime shell/Python paths. Verification-job concurrency is a different limit.
- [Dispatch ownership](../../../loop-bot-herd.sh#L1162) uses disjoint-path/exclusive leases for resolved tickets and refuses unresolved named tickets, but a brief without ticket identity can bypass partition leasing. All admitted work needs an explicit identity in the new contract.
- [Quota handling](../../../lib/quota.sh#L157) reacts to exhaustion and allows unknown/error quota. It is not a general percentage reserve or shared account allocator.
- [Provider fallback](../../../herdr-loop-swarm.sh#L542) handles launch/registration failure and drops an incompatible primary model ID. It does not establish equivalent-model selection or quality-driven escalation.
- [Headless bounds](../../../lib/headless.sh#L83) provide a default 600-second timeout and duplicate-name/PID prevention; they do not prove cancellation of detached or remote work. The [launch path](../../../lib/headless.sh#L145) supplies no demonstrated central nested-agent accounting, shared token/spend allocation, or OS isolation.
- [Repair handling](../../../lib/attention.py#L551) pauses after a second RED; the proposed three-attempt policy and contract-lawyer path are changes, not current behavior.
- [Same-user promotion guard](../../../lib/arbiter.sh#L465) explicitly is not airtight; the existing grant file cannot be treated as a worker-inaccessible authorization store.

No accounts, credentials, live quota, paid calls, cancellation behavior, or OS containment were tested. Numeric pilot choices remain pending and cannot be represented as enforced runtime guarantees.

### Billing and adaptive routing accepted; capacity and quota policy open — 2026-11-06

HinchK selected **Subscriptions first; paid use opt-in**. The pilot defaults to existing eligible subscription access. API use, credit fallback, and overages are disabled unless explicitly enabled with a per-run spending cap. Route changes must not silently change billing class. This is an accepted design policy, not permission to spend in this planning session or evidence that existing account settings enforce it.

HinchK selected **Adaptive routing with three-attempt limit**. Approved routes may be switched within existing limits, preserving the Sonnet-level baseline, appropriate economical routes, and stronger models when justified. The allowance is one initial attempt plus at most two repair attempts per work item, shared across providers. After exhaustion, the lawyer records why the work is stuck and pauses it; independent authorized work may continue. Renaming or cloning the same work does not reset the allowance. Fine-grained accounting of interrupted, failed-to-launch, and provider-limited attempts remains part of the pending implementation-design semantics.

HinchK chose **Adjust how capacity is shared** and **Choose a different reserve or unknown-quota policy** without specifying the replacements. The four-job cap, permanently reserved coordination slot, 20% reserve, and single-job unknown-quota fallback are therefore not adopted. No unlimited-capacity or zero-reserve policy should be inferred either.

Two clarification questions are pending: the desired total/per-provider concurrency and sharing across delivery/planning/review/mediation; and the desired per-provider reserve and concurrency/backoff policy when remaining quota is unavailable. The concrete enforcement design remains unresolved as recorded above. The ticket stays claimed.

### Capacity and quota direction from HinchK — 2026-11-06

This answer supersedes the earlier proposed four-job cap, reserved coordination slot, 20% reserve, conservative unknown-quota concurrency, and initial-pilot paid-API opt-in.

**Startup opt-in.** Do not impose capacity- or quota-management actions unless the user requests them at startup. No default concurrency cap, permanently reserved coordination slot, or retained percentage is adopted. The user may exhaust their subscriptions. Interpret the monitoring/alert/automatic-handoff policy below as the startup-enabled quota-management feature, not an always-on policy hidden behind optional cap settings. Existing goal, credential, authority, run-stop, and accepted work-item repair boundaries are separate from optional capacity/quota management.

**Warning levels.** When quota management is enabled and trustworthy remaining-quota data exists, alert the user in all panels below **20%, 15%, 10%, and 5%**. These are warning thresholds, not reserves or automatic stop thresholds. Each alert offers (1) wrap up and wait until reset or (2) create a handoff, fork a successor attempt, and transfer work to another model. Panel alerts must be visible notifications, not injected agent instructions or commands. The handling of an unanswered warning is the remaining interaction question; the recommendation is to keep working until a chosen action, exhaustion, or another stop applies.

**Backup behavior.** On exhaustion, attempt takeover by an available backup provider. If remaining quota is unavailable, divert work to the designated backup model rather than treating unknown quota as unlimited or inventing a percentage. Unknown quota and confirmed exhaustion must remain distinct: unknown does not itself count as an exhausted provider. Backup selection must identify the actual provider/account; another model sharing the exhausted subscription is not fresh capacity.

**Two-provider stop.** Once two distinct providers are exhausted, stop the swarm and alert the user, even if another provider might otherwise be available. Multiple exhausted models on the same provider must not inflate this count. Reset/resume semantics and accounting across accounts/windows still need precise design; this direction does not authorize automatic restart. If no usable designated backup exists, report that condition and preserve the handoff rather than silently choosing a paid route or cycling indefinitely.

**Handoff semantics.** Use the already accepted stable work identity, separate attempt record, checkpoint, evidence, and next action. Forking a successor must not keep the old attempt writing concurrently, duplicate accepted work, reset the repair allowance, or expand authority. At exhaustion, the successor may need to recover from durable state because the old model may have no quota left to write a fresh handoff. Missing telemetry cannot produce invented threshold alerts or reset times.

**Initial scope.** API and local-model support belong to a later iteration. The pilot uses eligible subscription routes only; the earlier paid-API opt-in recommendation is superseded. No automatic API, purchased-credit, or overage fallback is part of the initial pilot. Research about those access paths remains evidence for later work, not authorization to enable them now.

**Still open.** Warning behavior when the human does not respond, handling of unknown quota on the backup itself, exhaustion/reset accounting, interrupted-attempt attribution, descendant control, and the concrete grant isolation/enforcement mechanism must be completed before this ticket resolves. No capacity/quota runtime behavior is implemented by these notes.

### Unanswered warnings resolved — 2026-11-06

HinchK selected **Continue; hand off on exhaustion**. When startup-enabled quota management emits a 20/15/10/5% warning and the human does not answer, continue useful authorized work. The warning is not a pause or permission to change the run's other boundaries. At exhaustion, automatically attempt takeover by the designated available backup. Two distinct exhausted providers still stop the whole run and alert the human.

This resolves the warning-interaction question in the prior comment. The two offered actions remain available to the human at each threshold: wrap up and wait until reset, or prepare a handoff/fork to another model. An unanswered notification is not consent to either early action. Missing quota information still follows the previously specified backup route, without fabricating a remaining percentage or treating unknown as confirmed exhaustion.

### Policy walkthrough and remaining eligibility choice — 2026-11-06

| Event | Settled policy consequence |
| --- | --- |
| User did not enable quota/capacity management at startup | No imposed cap, reserve, threshold monitoring/management, or quota-driven automatic routing under this feature. Existing work/authority/stopping rules still apply. |
| Remaining quota falls below a warning level; no response | Notify all panels and continue, subject to existing boundaries. |
| Human chooses wrap-up/wait | Checkpoint and stop taking new work on the affected route; do not pretend remaining capacity guarantees a final model response. Reset/resume mechanics still need definition. |
| Human chooses early transfer | Preserve the work/checkpoint and transfer to an eligible backup without duplicate execution or a reset of repair authority. |
| Primary is exhausted | Attempt automatic takeover from durable state using the designated available backup. |
| Primary quota cannot be read | Use the designated backup; report unknown separately from exhaustion. |
| Two distinct providers exhausted | Stop the run and alert; do not silently cycle to a third provider or paid access. |

A further policy choice has been submitted: start unattended pilots with routes whose secret/permission/stop boundaries can be verified, leaving other routes ineligible until integrated, or wait until all selected providers meet those requirements. This is a rollout/eligibility preference, not a claim that any current provider route has passed verification. It does not reopen the user's right to exhaust subscriptions or impose optional capacity limits by another name.

After that choice, the concrete isolation/grant mechanism and remaining handoff/accounting edge cases still need a complete design. This ticket remains claimed; no providers were exercised or configured.

### Staged eligibility accepted — 2026-11-06

HinchK selected **Start with verified eligible routes**. The first unattended pilot may use a subset of providers that pass the required secret, permission, and stopping checks. Other routes remain unavailable for unattended work until their integration qualifies; the pilot need not wait for every selected provider. This is not proof that any current route qualifies.

### Encryption and remaining transition semantics — proposed for design — 2026-11-06

HinchK suggested encrypted secrets; [Establish enforceable isolation for subscription-backed routes](13-subscription-route-enforcement.md) is investigating credential-store compatibility and protection against model-directed access to decrypted material. No live credential handling is authorized.

The following transition details are proposed to complete the accepted quota policy, pending consolidation with the enforcement findings:

- Timestamp quota observations with provider/account, affected limit window, and provenance; do not synthesize percentages. Warn once per crossed threshold per observed window and make the latest state visible across panels. A reading that skips multiple levels should present one current alert showing the levels crossed, rather than a burst of duplicate prompts.
- An unknown-quota primary routes to its designated backup. If the backup also lacks usable quota information and no designated eligible alternative can be selected without revisiting a route, pause affected work and report the telemetry gap. Do not mislabel unknown providers as exhausted or bounce indefinitely between them.
- Count distinct confirmed-exhausted providers in the current run for the two-provider stop, with reset-window observations retained as evidence. After that stop, resume only after an explicit user action, refreshed availability, and revalidated authority; elapsed time alone must not renew a grant.
- A quota interruption transfers the same logical work, preserving its already-consumed repair allowance. Provider session/attempt records still change, but a transport or quota interruption is distinguished from a failed engineering repair. Neither kind of interruption permits unbounded repeated dispatch to an unusable route.
- Before a successor can write, quiesce the original attempt and reconcile its durable state; if termination cannot be established, block replacement writes. Handoff generation cannot depend on an exhausted model answering one last prompt.

These are proposed mechanics supporting the user's chosen behavior, not newly accepted limits. They do not reintroduce a default concurrency cap, reserve, or paid fallback.

### User-maintained secret files; encryption deferred — 2026-11-06

HinchK clarified that encrypted storage is not current work. Keep secrets in secure files maintained by the human; Stampede and model-directed tools must not read, copy, edit, reveal, or transfer their contents. Pass only non-secret references/names and readiness results. Existing provider clients may authenticate internally using their existing login, as already agreed; this is not permission for an agent to inspect credential files or environment values. New/changed credentials remain an outside-session human task.

The encryption suggestion is superseded for the initial pilot. No new vault, encryption implementation, keyring migration, or automatic secret-file maintenance is required. The enforcement research now targets secret-file exclusion and user ownership alongside protected grants; it must not confuse a request to avoid reads with proof that current runtime tools enforce it.

### Optional scoped secret exposure and credential cycling accepted — 2026-11-06

HinchK added an optional user-agreed exposure mode, then explicitly selected **Approved agent/provider access only** and **Automate supported rotations; guide the rest**.

**Default and exception.** Default behavior remains user-maintained secure files with no model-directed access to secret values. An explicit per-run agreement may instead allow the named credentials to be read/used by the selected agents/providers. The grant must identify credentials by non-secret references, recipients, permitted use, and the required cycling pass. General proxy authority, quota fallback, or a request for setup is not this agreement. This is a scoped exception to prior unconditional secret-handoff wording; other credentials remain protected. A new backup provider must already be within the approved recipients or require a further human decision before secret access.

**Exposure boundaries.** Even in this mode, values stay out of Git commits, public output, and routine logs. Checkpoints, mediation records, and handoffs use references rather than copying secrets. Enabling access to selected credentials does not authorize arbitrary host access, reading unrelated credentials, widening grants, deployment, or expanded spending. Cycling invalidates old credentials but cannot erase copies already disclosed to an approved provider.

**Cycling obligation.** Stampede manages the pass through supported, explicitly authorized service integrations: provision/rotate a replacement, verify that the replacement works, and revoke the old credential where the service supports that sequence. Guide the human through unsupported services. The run remains visibly **credential cycling pending** until the required pass is verified, including after interruption, quota exhaustion, or restart. Do not claim successful cleanup because an agent says rotation is done. Service-specific capabilities and permitted target-file updates must be established before automation; no universal rotation support is assumed.

**Scope reconciliation.** Encrypted-storage implementation and credential-store migration remain deferred. Optional authorized cycling is now in scope for the design; blanket automatic maintenance of user secret files is not. Deferring model-provider API access does not prohibit explicitly authorized service-management integrations used for cycling. No credential has been exposed, inspected, changed, or revoked in this planning conversation.

**Remaining lifecycle details.** The continuity decision must cover replacement creation, dependent configuration updates, verification/revocation receipts, retries, service limitations, and interruptions between steps without logging values or exceeding grant expiry. Pending cycling does not extend a grant or override a stop; unsupported or interrupted cleanup stays visible and requires an authorized continuation or human handoff. The resource decision still requires the concrete enforcement design and remaining quota/attempt edge cases before resolution.

### Consolidated enforcement and handoff proposal — awaiting HinchK — 2026-11-06

This proposal builds on [Establish enforceable isolation for subscription-backed routes](13-subscription-route-enforcement.md). It fills the remaining resource/authority mechanics without reopening startup opt-in capacity/quota management, subscription-only access, the two-provider stop, or scoped secret exposure. The architecture and continuation semantics below require human acceptance before this ticket resolves.

**Protected controller.** Reuse Stampede's scheduling/integration foundations behind one deterministic controller, running under a dedicated OS identity whose executable, policy, grant store, and administrative interface are outside worker-readable/writable paths. The user's outside session can issue/revoke scoped grants through an operator-only interface. Worker-facing requests cannot issue grants or invoke that administrative interface. This is a proposed runtime trust boundary, not a file naming convention or a new encryption/credential-storage project. The host OS, controller, pinned provider harness, and reviewed adapter are trusted; model output and project/worker code are not. A compromised administrator/OS is outside the guarantee. Setup must verify this separation before claiming eligibility; it must not silently install privileged services or treat a pane label as proof of identity.

**Requests and protected effects.** Bind each worker to run/work/attempt identity and its permitted work area. Workers request launches and consequential actions through the controller. It checks live authority immediately before admitting an operation: repository, action, target ref/commit, recipients where relevant, deadline, revocation, and optional user-selected capacity/quota rules. Request/receipt identity prevents duplicate delivery from repeating an effect. Pushes, PR changes, and opted-in base merges use narrowly defined operations, never arbitrary worker-supplied shell. Existing combined-tree checks and expected-ref advancement remain required. Block equivalent bypass through worker credentials, direct network actions, Git hooks, host-control sockets, other panes, or editable policy. An inability to enforce the boundary makes a route ineligible for unattended use.

**Authenticated providers and model tools.** Keep existing subscription authentication in the pinned provider client; do not migrate credentials or adopt model APIs. Herdr hosts the sessions. Apply a locked tool policy across file tools, shell, network, plugins/hooks, and native subagents, rather than assuming a shell restriction covers everything. Default secret files stay inaccessible to model tools; non-secret readiness is sufficient. Scoped exposure grants permit only the named credentials to approved recipients and do not permit reading unrelated secrets or control state. Create the durable cycling obligation before first disclosure so a crash cannot erase the obligation. Exact cycling state/receipt recovery belongs to the continuity decision; no service integration is presumed supported.

**Replication and inheritance.** A worker may request another worker with a bounded work purpose and existing harness recipe. The controller admits it under the same run and checks independent useful work, dependencies, ownership, and authority. A child receives the intersection of the requested scope and its parent's delegable scope, never broader permission, a later deadline, or a fresh repair allowance for the same work. Replica creation does not mutate the recipe; proposed recipe changes belong to the improvement policy. There is no default worker count, recursion-depth cap, reserved slot, or quota reserve. When the user enables capacity limits, every admitted child counts against those limits. Native nested workers must expose equivalent admission, scope propagation, stop, and accounting controls; otherwise disable that path for unattended execution. This is authority/ownership enforcement, not a hidden capacity cap.

**Quota handoff and engineering repairs.** Preserve the accepted one initial engineering attempt plus two repairs for the same logical work. A provider change forced solely by quota, an interrupted process, or a failed launch creates a new execution-attempt record continuing the current engineering attempt; it neither consumes a repair merely for switching nor restores a repair already consumed. A completed result that fails acceptance uses its engineering attempt; changing model or renaming the work cannot erase that failure. Record the interruption reason and link predecessor/successor. Quiesce the predecessor and reconcile durable state before successor writes; if termination cannot be established, wait rather than start competing writers. Do not depend on an exhausted model generating a final handoff message.

**Missing quota and reset.** Only when startup quota management is enabled: unknown primary quota uses the designated eligible backup. If that backup is also unusable or unknown and no designated unvisited eligible route remains, pause affected work and report the gap. Do not fabricate exhaustion or loop between routes. Confirmed exhaustion excludes that route until a non-secret refreshed observation establishes availability; do not repeatedly launch to probe an unchanged failure. Two distinct providers exhausted in the current run trigger the agreed whole-run stop, even if a third is available. Keep that stop latched until explicit user resume, refreshed readiness, and valid authority; never auto-renew a grant after reset. On authorized resume, start a new exhaustion-counting epoch while retaining history so previously resolved exhaustion is not counted forever. Details of provider-account/window evidence belong in the adapter contract.

**Notifications.** For measured quota, notify all panels when crossing 20/15/10/5% remaining, offering the two agreed choices. Deduplicate within the provider/account window, and if one reading skips levels, issue one current alert recording the crossed levels. Re-arm after verified window reset. No response means continue until exhaustion or another stop; alert delivery never grants authority. Unknown remaining balance never generates a fabricated percentage.

**Scenario consequences of this proposal.**

| Case | Proposed required outcome |
| --- | --- |
| Child requests another child | Controller checks work identity, ownership, scope, and any enabled limits. No fresh authority or repair budget appears. |
| Optional capacity/quota controls are off | Authority, ownership, billing-class, and existing work/run stops still apply; no cap, reserve, quota polling, or quota-driven transfer is imposed by this feature. |
| Primary is exhausted after one failed engineering attempt | Backup continues the current authorized repair using preserved state; it does not regain the initial attempt. |
| Primary and backup quota are unknown | No invented exhaustion count; pause affected work when no designated usable route remains. |
| Second distinct provider exhausts | Whole-run stop and alert; no third-provider dispatch until explicitly resumed under valid authority. |
| Worker requests broader grant or edits grant files | Administrative interface/storage deny access; log a non-secret denied request, without minting permission. |
| Grant expires during a queued merge | Recheck before the effect; refuse new action and reconcile anything already started. A merge triggering unapproved production deployment remains unavailable. |
| Secret-bearing worker switches provider | Check recipient scope first; transfer references, not secret-bearing context. Any new disclosure requires the relevant exposure grant and preserved cycling obligation. |

These are design requirements, not live verification. The decision remains claimed pending acceptance of the controller/inheritance boundary and continuation/reset rules. Detailed interrupted-cycling recovery, persistence transactions, and integration recovery remain owned by [Define durable progress, recovery, and integration](06-continuity-and-integration.md); improvement promotion remains with its existing ticket.

### Continuation/reset accepted; enforcement revision requested — 2026-11-06

HinchK selected **Use these continuation and reset rules**. Quota/process interruptions may continue the same engineering attempt on a backup, creating a separate worker-attempt record without consuming a repair merely for switching or restoring repairs already used. If all designated backups have unknown/unusable quota, pause affected work. After the two-provider exhaustion stop, explicit user resume and refreshed availability are required; retain exhaustion history but start a fresh counting period after that authorized resume. Existing grant validity and run-stop boundaries still apply.

HinchK selected **Adjust the enforcement model** without specifying the replacement. The proposed protected-controller architecture, worker-action request mechanism, inheritance model, and host isolation mechanism are therefore not adopted as a complete design. A clarification is pending on the desired behavior. This answer does not itself revoke previously accepted scoped authority, secret-access rules, or unattended-route eligibility requirements, nor does it authorize implementation. Keep this ticket claimed.

### Resolution — 2026-11-06

HinchK's final enforcement direction is: **“keep it simple to herdr and each provider's harness. don't create a seatbelt on a seatbelt.”** This supersedes the protected-controller, dedicated OS identity, administrative socket, custom permission-broker, and added isolation proposals above. The continuation/reset rules were accepted separately and remain in effect.

**Runtime and authority.** Herdr manages sessions/panes and workers; each provider harness supplies its native tool permissions, approvals, credential use, and process controls. Stampede coordinates goals, work identity, handoffs, routing, records, and already-agreed stopping policies, while retaining its existing integration/review/promotion checks. Do not create a second permission system or require every worker launch and Git action to pass through a new broker. Record the human's run agreement using existing configuration/session records and configure supported native controls accordingly. Native human approvals are not replaced by agent assertions or cross-pane evasion. The agreed scopes, expiry, revocation, base-merge opt-in, and lawyer/traffic-control division remain operating rules; no universal tamper-proof same-user authorization guarantee is claimed.

**Replication and routing.** Use Herdr/provider-supported worker and subagent facilities with explicit work/attempt identity and ownership. Replication reuses a harness recipe; changing that recipe is separate improvement work. Descendants must follow the same run agreement and applicable native permissions; a request for a child is not new scope or fresh authority. Do not build custom recursive permission machinery or impose a default worker/depth cap. Spawn for useful independent work; serialize dependent/conflicting work using existing ownership/integration mechanisms. Model selection remains adaptive among approved eligible subscription routes, with Sonnet-level defaults and appropriate cheaper/stronger routes. Keep actual account/provider identity distinct from model or harness names.

**Optional capacity/quota management.** Enable these actions only if the user requests them at startup. There is no default concurrency ceiling, reserved coordination slot, or retained quota percentage. When enabled, show all-panel warnings below 20/15/10/5%, offering wrap-up/wait or handoff/fork. Unanswered warnings do not pause work. Exhaustion automatically attempts the designated eligible backup; unknown quota also routes to the designated backup without inventing a percentage. If no designated usable backup remains, pause affected work. Two distinct exhausted providers stop the whole run and alert the user. Resume requires explicit human action, refreshed availability, and valid authority; preserve history and begin a new exhaustion-counting period. A different model on the same exhausted subscription is not fresh capacity. Notification deduplication and window tracking are adapter details, not new reserve policies.

**Attempts and continuation.** Preserve one initial engineering attempt plus two repairs per work item across routes. Quota/process interruption may create a successor worker attempt continuing the same engineering attempt: no repair is spent merely for switching, and previously spent repairs are not restored. Record reasons and predecessor/successor identity. Reconcile/checkpoint unfinished work and establish predecessor quiescence through available native controls before allowing conflicting successor writes. If that cannot be established, report the unresolved state rather than claim cancellation. Do not depend on an exhausted model writing a final handoff. Once engineering repairs are exhausted, record mediation and pause the work while independent authorized work may continue.

**Secrets and eligibility.** Keep user-maintained secret files outside agent access by default using supported native harness settings; no encryption/vault/migration project. Optional explicit per-run exposure allows named credentials only to approved agents/providers, with values excluded from Git, public output, and routine logs. Required cycling is automated only through supported authorized service integrations, with replacement verification and old-credential revocation where supported; guide the human otherwise. Keep cycling pending across interruptions until verified. It does not extend authority. Begin unattended pilots with verified eligible native routes. If a chosen harness cannot meet the selected secret/permission/stop mode, report that limitation and leave that route unavailable for that unattended mode rather than invent another enforcement layer or claim a guarantee.

**Scope and evidence.** Initial model access is subscription-only. Model-provider APIs and local models are later work; service-management integrations explicitly approved for cycling are distinct. These are design decisions derived from HinchK's answers, not authorization to inspect credentials, launch agents, spend, publish, or rotate anything now. The research report remains a source of capability facts; its separate-controller recommendation was not adopted. Native capabilities and their limitations must be verified for the actual pilot versions/platform before live readiness claims.

**Scenario check.** A child cannot acquire new project scope merely by spawning; configured native controls and the shared run agreement apply. Quota interruption hands over work without resetting repairs. Unknown primary and unknown backups produce a reported pause, not fabricated exhaustion or repeated cycling. Two exhausted providers stop the run. Agent-written approval text does not count as a human grant. A route lacking required native protection is not declared eligible. Exposed credentials leave a durable cycling obligation even when the run stops. These are policy walkthroughs, not executed tests.

**Downstream.** [Define durable progress, recovery, and integration](06-continuity-and-integration.md) and [Define how harness improvements are proposed, evaluated, and adopted](08-harness-evolution.md) are now unblocked. The continuity decision comes first in map order and owns checkpoint persistence, native cancellation/reconciliation, and interrupted credential-cycling recovery. Neither downstream workstream should reintroduce the rejected enforcement layer or default capacity/quota controls.
