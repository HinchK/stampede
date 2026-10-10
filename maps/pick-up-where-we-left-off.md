# Wayfinder Map: Pick Up Where We Left Off

**Charted:** 2026-10-08 (arch-1-hinchk-stampede, driver milestone-charter dispatch) · **Adopts the unclaimed
backlog of** `maps/dispatch-safety-and-review-policy.md` (REV-JQ-1, TEST-PATH-1, INTEG-REC-1, REV-07 — re-parented
here, ids and history stable) · **Intakes** the two fresh 2026-10-08 inputs that no ticket yet reflects: the
looper-temp handoff (`.herdr-swarm/research/looper-temp-handoff.md`) and the OpenRig comparison review
(`.herdr-swarm/research/2026-10-08-openrig-comparison-review.md`).

## Destination (Complete)

**Milestone Complete (2026-10-08).** The swarm has resumed on a fully-reconciled, fully-verified footing: all staged
implementation defects are fixed and integrated, the two decisions owed to the human (review quorum, OpenRig borrows)
are made and recorded with durable receipts, and all five staged backlog tickets (REV-FAILOVER-1, SEEDED-1, HASH-1,
STATUS-INDET-1, SNAP-1) are resolved, verified, and integrated.

## Where we actually left off (verified 2026-10-08, receipts)

- **Reconciled and green.** `main` == `origin/main` == `swarm/stampede/integration` at `6ad1234`; working tree
  clean; all 21 suites green (`make check`), 0 ShellCheck warnings (`STATE.md` §12).
- **No held state.** `.herdr-swarm/leases.json` is empty; every entry in `.herdr-swarm/reviews.json` is
  `review_passed` or `docs_fast_path` — the REVIEW-SHA-1 canonicalization held (no `review_blocked` stragglers).
- **Dead letter is historical.** One record (HL-TGT-1, 2026-09-19 session), already scoped out of batch exits by
  HL-DL-1's baseline counting.
- **Standby orchestrator is live.** FALLBACK-1 shipped (`lib/standby.sh`, `[seats.looper_standby]` in
  `swarm.config.toml`, 38 assertions) and survived CI portability (CI-FIX-3).
- **Both handoff defects are accounted for.** The sha-mismatch defect → REVIEW-SHA-1 (resolved, `843f085`). The
  `jq: invalid JSON text passed to --argjson` warning observed live in the supervisor log (~2026-10-08 08:48Z) →
  REV-JQ-1, still open, site confirmed at `loop-bot-herd.sh:567`.
- **One research note landed unticketed.** The OpenRig comparison (external, primary-source, self-labelled "do not
  ingest as authoritative swarm context") enumerates 7 borrow candidates (its §7) and 5 declines (its §8); the
  cross-vendor review finding (#6) feeds directly into REV-07's pending decision.

## Notes

- **Disjoint owns → co-dispatchable.** REV-JQ-1 owns `loop-bot-herd.sh`; INTEG-REC-1 owns `lib/arbiter.sh` +
  `tests/test_arbiter.sh`; TEST-PATH-1 owns `tests/test_profile.sh`. Pairwise disjoint — arch-1 and arch-2 can carry
  two of them concurrently under partition leases; the third follows.
- **Why these three first.** REV-JQ-1 and INTEG-REC-1 were both *observed live* in the last session (telemetry
  warning; stalled docs sweeps for REVIEW-SHA-1 and CI-FIX-2). TEST-PATH-1 is prophylactic — the runner tool-shadow
  class has already struck three times (CI-FIX-1, CI-FIX-2, CI-FIX-3) and this is the fourth known instance of the
  same hazard (`PATH=/usr/bin:/bin` at `tests/test_profile.sh:78`).
- **REV-07 is now the keystone decision.** FALLBACK-1 shipped, so the standby story reads: dispatch and harvest
  survive an agy quota wall, **review does not** — the exact SPOF the PM audit flagged. The ticket's own note
  ("recommend deciding before FALLBACK-1 is dispatched") has been overtaken; the decision is overdue, and its
  grilling should consume OpenRig §7 #6 (cross-vendor critique seat): same conversation, and it names the second
  reviewer vendor a quorum would need.
- **BORROW-1 is a funnel, not a shopping list.** The borrows arrive from an external note; staging them as
  implementation tickets before the driver has triaged them would invert who decides. One decision ticket routes
  all seven to adopt / decline / fog.
- **Core invariants unchanged:** promote/push stay human-only; no cross-pane injection; never trust a self-reported
  green without independent verification.

## Decisions so far

- 2026-10-08 (charting): backlog tickets are **re-parented**, not re-staged — ticket ids, frontmatter history, and
  gh-sync parity stay stable; `maps/dispatch-safety-and-review-policy.md` closes.
- 2026-10-08 (charting): OpenRig borrows are **not** auto-staged as implementation tickets — the research note is
  external and unaudited by the swarm; BORROW-1 funnels each to adopt/decline/fog with the driver.
- 2026-10-08 (charting): P3-4 (arbiter batch integration) **stays parked** — real design, wrong milestone; unparking
  is the driver's call, not a resumption default.
- 2026-10-08 (charting): dispatch order recommendation — REV-JQ-1 + INTEG-REC-1 first (both live-observed; disjoint
  owns; two arch seats), TEST-PATH-1 next, REV-07 + BORROW-1 whenever the human sits for decisions.
- 2026-10-08 (driver resolution, REV-07): single-reviewer PASS is an **accepted limit** — quorum not built;
  the review quota SPOF is closed by **failover** instead. Recorded as
  [ADR 0018](../docs/adr/0018-single-reviewer-accepted-limit-with-quota-failover.md); the OpenRig §7 #6
  cross-vendor critique idea is realized as the failover path, staged as REV-FAILOVER-1.
- 2026-10-08 (driver resolution, BORROW-1): triage — **adopt** #1 seeded-regression pairs (SEEDED-1), #3
  evidence hashes (HASH-1), #4 `INDETERMINATE` floor (STATUS-INDET-1), #5 snapshot-before-`down` (SNAP-1,
  capture only); **fold** #6 cross-vendor review into REV-FAILOVER-1; **fog** #2 stub seat runtime and #7
  webhook adapter (unblocking conditions in fog below); **affirm all §8 declines** (daemon+SQLite,
  agent-managed topology, shared checkout, permissive defaults, verdicts-as-verification) — reasoning in the
  BORROW-1 resolution receipt.
- 2026-10-08 (execution): REV-JQ-1 resolved (`2fe4963`, arch-1) — telemetry hardening with seeded-regression
  receipt; INTEG-REC-1 resolved (`eb805dd`, arch-2) and TEST-PATH-1 resolved (`89b9ef4`, arch-2). All three
  verdict anchors emitted; supervisor harvest/integration pending at chart-update time — statuses cite the
  implementation shas, not yet base promotion.
- 2026-10-08 (execution): REV-FAILOVER-1 resolved (`35360d9`, arch-1) — non-AGY reviewer failover on quota exhaustion
  via config binding, supervisor failover dispatch with contract pointer, and reviews.json attribution; verified via 12
  new §17 tests in `test_async_gate.sh` and 5 new 6r tests in `test_config.sh`.
- 2026-10-08 (execution): SEEDED-1 resolved (`6147732`, arch-1) — seeded-regression pairs proving test teeth
  for verdict dedupe (`test_async_gate.sh` §18) and CAS ref advance (`test_arbiter.sh` §11) via `tests/helpers/seed.sh`
  (`with_seeded_defect`), documented in `CONTRIBUTING.md`.
- 2026-10-08 (execution): STATUS-INDET-1 resolved (`7b91419`), SNAP-1 resolved (`9582ec6`), and HASH-1 resolved (`d9c71c3`).
  All five staged backlog tickets are resolved and integrated; milestone is complete.

## Tickets

| Ticket | Seat | Status | Blocked by | Synopsis |
|---|---|---|---|---|
| **REV-JQ-1** | arch-1-hinchk-stampede | **resolved** (`2fe4963`, integration pending) | — | Harden review verdict telemetry against empty/malformed findings counts (`loop-bot-herd.sh`, observed live) |
| **INTEG-REC-1** | arch-2-hinchk-stampede | **resolved** (`eb805dd`, integration pending) | — | Arbiter integration emits durable session-verdict record (unblocks post-integration docs sweeps) |
| **TEST-PATH-1** | arch-2-hinchk-stampede | **resolved** (`89b9ef4`, integration pending) | — | Hermeticize `tests/test_profile.sh` PATH — 4th instance of the CI-FIX runner-shadow class |
| **REV-07** | human (settled), arch-1 (recorded) | **resolved** (ADR 0018) | — | Single-reviewer accepted limit; quota SPOF closed by failover, not quorum |
| **BORROW-1** | human (settled), arch-1 (recorded) | **resolved** (triage receipt) | — | OpenRig §7 triage: 4 adopts, 1 fold, 2 fog, §8 declines affirmed |
| **REV-FAILOVER-1** | arch-1-hinchk-stampede | **resolved** (`35360d9`) | — | Non-AGY reviewer failover on quota exhaustion (ADR 0018's staged mechanism) |
| **SEEDED-1** | arch-1-hinchk-stampede | **resolved** (`6147732`) | — | Seeded-regression pairs for verdict dedupe + CAS paths — suites must fail when the defect is planted |
| **HASH-1** | arch-2-hinchk-stampede | **resolved** (`d9c71c3`) | — | Evidence hashes (`sha256` gate log + host/pid) on session verdict records |
| **STATUS-INDET-1** | arch-2-hinchk-stampede | **resolved** (`7b91419`) | — | `INDETERMINATE` floor for `stampede status` — derived at read time, never collapsed by labels |
| **SNAP-1** | arch-2-hinchk-stampede | **resolved** (`9582ec6`) | — | Snapshot transcript tails + ledgers before `swarm down` closes panes (capture only) |

Note: All tickets in this milestone are resolved and integrated; milestone complete.

## Not yet specified

- Inline TUI review-diff inspection — carried fog from `maps/autonomous-reviewer-loop.md`; still needs its own
  research pass on what Herdr's pane model can render.
- **Stub seat runtime** (OpenRig §7 #2, fogged by BORROW-1): needs a research pass on the seat-type surface —
  config binding for a `worker = stub` kind, brief-delivery path, headless-harness interplay — before a ticket
  is specifiable. Unblocks zero-model-cost pipeline suites.
- **Notification webhook adapter** (OpenRig §7 #7, fogged by BORROW-1): only justified when headless/CI runs
  without panes become routine; revisit when a second real headless deployment exists.
- **Snapshot restore/resume** (beyond SNAP-1's capture-only scope): resurrecting conversation state after
  `down` needs its own design pass; SNAP-1 is deliberately the cheap half.

## Out of scope

- P3-4 arbiter batch integration (`maps/tickets-parked/arbiter-batch-integration.md`) — stays parked until the
  driver unparks it.
- Extending quota probing beyond `agy` (carried exclusion from `maps/dispatch-safety-and-review-policy.md`).
- Anything that moves `main` or `origin/main` without the human.
