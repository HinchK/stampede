# Stampede operator walkthrough

Reviewed design artifact for [Choose the runtime boundary and operator experience](../../maps/evolving-harness-swarm/issues/05-runtime-and-experience.md), 2026-11-06. HinchK accepted the summary view and runtime boundary, and selected separate setup and launch. The artifact has been revised to reflect those answers; runtime behavior is not implemented.

Open [the interactive walkthrough](PROTOTYPE-stampede-operator.html) directly in a browser. It is a self-contained simulation with no dependencies, storage, provider calls, or runtime integration. Its buttons represent terminal events, not a proposed web product. All provider availability and results are examples; usage is deliberately unknown.

## Separate setup and launch

Use the existing command vocabulary: `stampede setup` prepares configuration; `stampede up` launches or reattaches. Their enhanced guided behavior described here is planned, not currently implemented. Do not introduce the previously proposed combined `stampede start` flow or silently change bare invocation.

Setup checks providers, helps assemble the team, and saves configuration plus any prepared starter-task brief. It ends without launching delivery workers. Optional kickoff research remains an explicitly requested, bounded activity; it does not authorize implementation. Launch is a separate action that revalidates saved configuration, access, goal, and limits before starting delivery. Returning users can launch/resume from saved setup without repeating the whole interview, or rerun setup to change the team. Exhausted allowances still require a new agreement.

The preparation stages below may establish a starter-task brief before launch; agreement on that brief is not automatic execution.

1. **Check this terminal.** Identify installed tools and Herdr; distinguish installed, ready, unavailable, and unknown. Check eligible model/access paths without exposing credentials. Show remaining usage only if safely obtainable and attributable. Neither a binary nor a subscription name proves model access or quota.
2. **Choose useful work.** Offer a bounded bugfix, containerization, preparation for open source, or a custom sprint. Ask whether the user wants help engineering the goal.
3. **Optional research-assisted kickoff.** Offer a small provisional research team from eligible routes before the final team is known. State its proposed research scope and usage allowance before starting. Use contrasting perspectives to ask informed questions. The human settles the outcome and boundaries; research consensus does not settle them. Exact bootstrap concurrency and budget remain resource-policy decisions.
4. **Recommend the delivery team.** Explain planner, generalist, reviewer, and contract-lawyer recommendations in terms of suitability and available usage. Sonnet-level is the default capability tier, not a mandatory provider. Workers start on demand. Let the user adjust recommendations without assigning every future subtask manually.
5. **Agree one run brief.** Show goal, evidence of success, team/access choices, overall horizon and budget, sprint/milestone/epic stop, break interval, action stops, optional improvement allowance, and supervision mode. The pilot starts with a four-hour total horizon; later break presets cannot extend it. Approval here covers routine autonomous decomposition and execution within these bounds.
6. **Save setup and exit.** Preserve existing settings and the prepared brief. Do not start delivery workers.
7. **Launch separately and summarize.** Recheck the saved brief, access, and limits before starting workers. Show outcome progress and the next stopping boundary, with worker details available on demand. The actual terminal experience stays in Herdr. A successful starter task includes evidence and a demonstrated stop/resume, not just a generated configuration.

## Accepted operator view

Keep one summary pane visible, with drill-down to live worker panes and the decision history. Herdr may still host all required worker panes; whether they are hidden, grouped, or simply unfocused depends on its supported layout controls. Do not assume an unverified hiding capability.

The summary answers: what is being attempted, what has been accepted, what is waiting, what happens next, and when will this run stop? Include quota availability or unknown, per-model token velocity when measurable, time in work/tool waits, and mediation activity. Do not substitute token output for completed work.

The proposed `--yolo` behavior opens an observer panel. It does not forward provider bypass flags. Typing there initiates a request for a human grant with explicit scope and stopping conditions. Until granted, it observes. The demo's grant ends at the delivery boundary; actual grant defaults, broader delegable actions, authentication, revocation, and expiry remain the authority ticket's decisions.

The contract-lawyer normally resolves disputed requirements, checks, and handoffs without interrupting the user. Its record must identify the work and attempts, event time, friction/failure, supporting context, decision and rationale, follow-up, and eventual result. The demo uses ordered event numbers instead of pretending to measure elapsed time. A human escalation should state the problem, what was tried, the recommended decision, and the security/stability implication or missing context.

## Reviewed walkthroughs

| Case | Intended experience |
| --- | --- |
| Setup only | Discover → agree configuration/brief → save → exit without delivery workers. |
| First run | Discover → optional research/interview → agree brief → save setup → separate launch → accept demonstrated result → pause. |
| Disputed check | Lawyer mediates, orders an equivalent check, records why, and waits for evidence. No human interruption for ordinary friction. |
| Context or security concern | Lawyer asks one concrete human question; the affected work remains unaccepted. Exact run-wide versus local pause policy remains open. |
| Credential needed | Stop for an outside login or named local environment setup; no values enter conversations. Readiness check reveals no secrets, then resume explicitly. |
| Proxy takeover | Observer → human types → grant requested → explicit scoped grant → supervision → expiry. |
| Timed break and model switch | Pause without declaring completion; revalidate checkpoint; keep work identity and record a new attempt; duplicate results count once. |
| Delivery followed by improvement | Delivery stops at its selected boundary. Only the separate allowance permits improvement work; the overall limit stops both. Proposed improvements are not automatically adopted. |

The sketch uses one starter work item. It does not simulate concurrent integration, process cancellation, sleeping through a deadline, durable recovery, action interception, or permission enforcement. A button labelled “Accept delivery result” represents independently supplied acceptance evidence; the HTML does not verify source code. Those mechanisms must be designed and tested later.

## Runtime boundary grounded in current source

Source inspection on 2026-11-06; no live behavior was exercised.

| Existing foundation | Proposed treatment |
| --- | --- |
| [Single public command](../../bin/stampede#L63) and command-module dispatch | Retain separate setup and lifecycle commands; enhance guided preparation without automatic launch. |
| [Provider probing](../../lib/setup.py#L338) | Extend eligibility and usage reporting. Current setup recognizes AGY/Claude/OpenCode and requires AGY; provider-neutral recommendations are new work. |
| [Configuration preservation](../../lib/setup.py#L207) | Retain non-seat settings and custom configuration when changing the team. Replace seat-count-first setup with goal/team guidance. |
| [Herdr launch orchestration](../../herdr-loop-swarm.sh#L538) | Herdr provides terminal workspaces, panes, and agents. Stampede selects placement, configuration, work, and provider/model routing. |
| [Persisted attention](../../lib/attention.py#L529) | Retain state/readiness foundations; redesign ordinary blocked-event escalation around mediation. Existing GREEN handling still returns a manual-arbiter outcome. |
| [Bounded Resume Map](../../herdr-loop-swarm.sh#L813) | Existing source supports an active map. Extend and verify it for the new checkpoint/timed-break contract; do not treat it as proof of that contract. |
| [Trace-derived status](../../lib/cli/stampede-status.sh#L17) | Retain source attribution and honest unknowns; add goal, stop policy, mediation, and supervision state. |
| [Integration and promotion guards](../../lib/arbiter.sh#L387) | Retain combined-tree verification and guarded ref advancement. Existing promotion grants do not imply broader proxy authority. |

Accepted ownership: **Herdr operates terminal sessions; Stampede owns the durable work contract, scheduling, evidence, integration, limits, and operator summary.** Model agents advise and mediate within that contract; deterministic controls enforce it. This retains the existing foundations while replacing the fixed-seat setup and ordinary interruption behavior. HinchK accepted this retain/replace boundary; this planning decision is not authorization to implement it.

## Human verdict

HinchK chose **Keep setup and launch separate**, **Summary with worker drill-down**, and **Use this boundary and reuse plan**. The revised artifact preserves separate preparation and execution, with saved configuration reused after readiness checks. Detailed proxy grants and continuity mechanics remain downstream decisions.

This HTML is a design record, not production code. The ticket records the prototype branch and commit so the reviewed artifact remains recoverable independently of local preview copies.
