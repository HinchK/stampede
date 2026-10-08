# ADR 0018: Single-Reviewer Accepted Limit with Non-AGY Quota Failover

- **Status**: Accepted
- **Date**: 2026-10-08
- **Deciders**: driver (settled), `arch-1` (recorded)
- **Consulted**: [ADR 0016: The Headless Batch Review Boundary](0016-headless-batch-review-boundary.md), [ADR 0002: Exact-SHA Supervisor Protocol and Re-Verdict Deduplication](0002-exact-sha-supervisor-deduplication.md), [ADR 0009: Arbiter Branch Integration and Human Promotion Gates](0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0014: Arbiter Drain Automation](0014-arbiter-drain-automation.md), [Wayfinder Map: Pick Up Where We Left Off](../../maps/pick-up-where-we-left-off.md), Ticket [REV-07](../../maps/tickets/rev-07-multi-reviewer-quorum-decision.md) (incl. PM audit 2026-10-08 input), [OpenRig comparison review](../../../.herdr-swarm/research/2026-10-08-openrig-comparison-review.md) §3/§7, Tickets FALLBACK-1 / QUOTA-2 / QUOTA-5

---

## 1. Context and Problem Statement

REV-07 asked whether a single reviewer's PASS is sufficient trust for integration, or whether the
herd needs multi-reviewer quorum (both-must-PASS, majority, or a tie-break rule). The question
carried two live pressures:

1. **The quota SPOF is real and observed.** The 2026-10-08 PM audit (recorded in REV-07's notes)
   showed that during an agy account wall the stand-in orchestrator could dispatch and harvest —
   FALLBACK-1's whole story — but *nothing could pass review*, because the one reviewer seat
   (`[seats.reviewer]`, `default_kind = "agy"`) sits behind the same exhausted account as the rest
   of the agy fleet. QUOTA-2 defers reviewer dispatch until the account clears; defer-and-wait is
   correct for a transient wall, but it makes review the single component with no path around an
   outage.
2. **Quorum is not free and not obviously load-bearing here.** The OpenRig comparison (§3) showed
   the other project's multi-judge review records verdicts from named seats but never re-executes
   anything — "independence" there means different vendors, not an independent mechanism. In this
   repo the load-bearing verification is the supervisor's mechanical suite re-execution at the
   gated SHA and the arbiter's re-run on the combined tree (ADR 0002/0008/0009). Review is
   defense-in-depth: a second, adversarial reading — valuable, but an LLM opinion inside the same
   epistemic class as the worker it reviews.

One reviewer seat exists today. Building quorum means provisioning a second reviewer-capable
seat, doubling per-verdict reviewer cost, and writing tie-break policy — before any observed
incident of a reviewer false-green.

## 2. Decision

Two halves, settled together:

1. **Single-reviewer PASS remains the interactive review gate. Quorum is not built — accepted
   limit, ADR-0016 shape.** One reviewer verdict (PASS with evidence file, or BLOCK with findings
   and critique rounds, REV-1..5 machinery) is sufficient for enqueue. The marginal trust a
   second same-class LLM opinion buys does not justify its steady-state cost against a hazard with
   no observed instance.
2. **The availability SPOF is closed by failover, not by quorum.** When the primary (agy)
   reviewer is quota-walled — the same account-wide signal QUOTA-2/QUOTA-5 already produce — the
   supervisor's reviewer dispatch fails over to a configured **non-AGY reviewer seat** (an
   OpenCode/Claude-family seat). One active reviewer at a time; when the agy account clears,
   dispatch returns to the primary. This is where the OpenRig §7 #6 idea (cross-vendor critique)
   lands: realized as the *failover path*, not as standing quorum — a different-vendor reading is
   obtained exactly when the primary is unavailable, at zero steady-state cost.

Staged as [REV-FAILOVER-1](../../maps/tickets/rev-failover-1-non-agy-reviewer-failover.md).

## 3. Reasoning

1. **The trust anchor is re-execution, not reviewer consensus.** The system's core invariant is
   that no agent's claim of green is accepted without independent mechanical verification
   (supervisor gate at the gated SHA, arbiter gate on the combined tree). Stacking more reviewers
   hardens the advisory layer while leaving the anchor untouched; OpenRig's judgment ledger is the
   cautionary shape — recorded multi-judge verdicts that audit claims without ever re-producing
   them (comparison §3).
2. **No observed single-reviewer failure mode.** Across the review history in
   `.herdr-swarm/reviews.json`, no verdict-PASS ticket later proved defective in a way a second
   reviewer would have caught and the suite gate did not. The observed review failure was
   *availability* (the quota wall), not judgment. We fix the failure we have.
3. **Failover, not quorum, is the cheap form of vendor diversity.** A standing second reviewer
   doubles reviewer dispatches per verdict forever; a failover seat costs nothing while the
   primary is healthy and delivers the cross-vendor reading precisely when the herd would
   otherwise stall. It also completes FALLBACK-1's story — the herd that survives a quota wall
   end to end, review included — with one config-bound seat and no new state machines.
4. **Writing the limit down is part of the decision.** Like ADR 0016, an accepted limit kept as a
   fog note silently becomes folklore. Anyone auditing a single-reviewer PASS in
   `session-verdicts.jsonl` should find this record, not an omission.

## 4. Consequences

- Single-reviewer PASS remains sufficient for enqueue; `reviews.json` continues to record which
  seat delivered each verdict, so the audit trail distinguishes primary from failover readings.
- A failover reviewer must satisfy the same reviewer contract as the primary — verdict anchor
  grammar (`REVIEW VERDICT #<id> <sha> <PASS|BLOCK>`), evidence-file schema
  (`.herdr-swarm/reviews/<ticket>-<sha>.md`), findings format, round budget — so the REV-1..5
  state machine stays reviewer-agnostic (REV-FAILOVER-1's job to enforce in briefs and tests).
- QUOTA-2's deferral marker becomes the failover trigger signal; deferred dispatches must not
  silently wait *and* failover — one resolution per deferred verdict, recorded.
- Quorum infrastructure remains unbuilt; this ADR is the receipt. Provisioning additional
  reviewer-capable seats for *capacity* reasons remains allowed — it is not quorum until verdicts
  from multiple reviewers are required to pass.

## 5. Revisit trigger

This decision reopens if either occurs:

1. A **real incident** in which a single reviewer's PASS covered a defect that the suite gate
   missed and a different-vendor reviewer demonstrably would have blocked — grounds to require
   cross-vendor review on the affected class of work, up to standing quorum.
2. **Sustained disagreement data**: once failover readings exist, if primary and failover
   reviewers routinely diverge on the same sha/class of work, the single-opinion premise is
   empirically broken and quorum policy gets re-chartered.
