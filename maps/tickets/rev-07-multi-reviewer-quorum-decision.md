---
id: REV-07
title: "Multi-reviewer quorum: decide policy, or write the accepted-limit ADR"
type: wayfinder:decision
status: resolved
assignee: human
owns: docs/adr
parent: maps/pick-up-where-we-left-off.md
---

# REV-07 -- does single-reviewer PASS need a second opinion?

## Question

Resolving one of three fog items in `maps/autonomous-reviewer-loop.md`'s "Not yet specified" section (the
original note: "scaling review from single-seat review to multi-seat cross-provider consensus, e.g. both
Claude and Gemini must PASS"). Only one reviewer seat/kind exists today (`[seats.reviewer]`:
`default_kind = "agy"`, `gemini-2.5-flash`) -- building actual quorum means provisioning a second
reviewer-capable seat first, which is a separately-sized future ticket, not bundled into this decision.

This ticket is **policy-design-only**, settled via grilling 2026-10-07: decide, with real reasoning, either
(a) what quorum would actually mean if built -- both-must-PASS? majority? an explicit tie-break rule for
disagreement? -- as a spec a future provisioning ticket could implement; or (b) an accepted-limit decision
(mirroring `ADR 0016`'s shape) that single-reviewer PASS is sufficient for now, with a named revisit trigger.

Needs its own grilling session -- not resolved as part of this epic's charting. Per wayfinder discipline, one
ticket resolved per session; this epic's chartering session resolved zero tickets, it created them.

## Notes

Whichever way this resolves, write it as an ADR (same precedent as `ADR 0016` for the headless review
boundary) -- a decision this load-bearing about review trustworthiness belongs in a durable record, not left
as a fog note indefinitely.

## Input from PM audit 2026-10-08

The quota-outage experiment showed review is the single point of failure: the stand-in orchestrator (see `fallback-1-standby-orchestrator-seat.md`) could dispatch and harvest but nothing could pass review while the agy reviewer was walled. Decide a non-agy fallback reviewer (or accept the limit in an ADR) in this session; recommend deciding it before FALLBACK-1 is dispatched.

## Resolution (2026-10-08)

Settled by the driver; recorded by `arch-1` as
[ADR 0018: Single-Reviewer Accepted Limit with Non-AGY Quota Failover](../../docs/adr/0018-single-reviewer-accepted-limit-with-quota-failover.md).

Option (b) — accepted limit, with the SPOF closed by failover:

1. **Single-reviewer PASS remains the gate; quorum is not built.** The load-bearing verification is
   mechanical re-execution (supervisor gate at the exact SHA, arbiter gate on the combined tree —
   ADR 0002/0008/0009); review is defense-in-depth, and no observed reviewer false-green exists to
   justify doubling per-verdict reviewer cost (ADR 0018 §3.2).
2. **The PM audit's SPOF finding is answered by REV-FAILOVER-1** (staged in this milestone): when the
   agy reviewer is quota-walled, reviewer dispatch fails over to a configured non-AGY reviewer seat —
   one active reviewer at a time, return to primary on clear. The OpenRig §7 #6 cross-vendor critique
   idea is realized as this failover path, not as standing quorum. (The audit's "decide before
   FALLBACK-1 is dispatched" recommendation was overtaken by events — FALLBACK-1 shipped first —
   which made the availability half of this decision more urgent, not less.)
3. **Revisit triggers named** (ADR 0018 §5): a real reviewer false-green incident that a different
   vendor would have blocked, or sustained primary/failover divergence once failover readings exist.

Receipts: ADR 0018 committed and indexed in `docs/adr/README.md`;
`maps/tickets/rev-failover-1-non-agy-reviewer-failover.md` staged; Decisions updated in
`maps/pick-up-where-we-left-off.md`.
