# Wayfinder Map: Pick Up Where We Left Off

**Charted:** 2026-10-08 (arch-1-hinchk-stampede, driver milestone-charter dispatch) · **Adopts the unclaimed
backlog of** `maps/dispatch-safety-and-review-policy.md` (REV-JQ-1, TEST-PATH-1, INTEG-REC-1, REV-07 — re-parented
here, ids and history stable) · **Intakes** the two fresh 2026-10-08 inputs that no ticket yet reflects: the
looper-temp handoff (`.herdr-swarm/research/looper-temp-handoff.md`) and the OpenRig comparison review
(`.herdr-swarm/research/2026-10-08-openrig-comparison-review.md`).

## Destination

The swarm resumes on a fully-reconciled, fully-verified footing: the three staged implementation defects are fixed
and integrated, the two decisions owed to the human (review quorum, OpenRig borrows) are made with real options on
the table, and nothing left open on 2026-10-08 remains unstated — every item is ticketed, decided, or explicitly
parked.

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

## Tickets

| Ticket | Seat | Status | Blocked by | Synopsis |
|---|---|---|---|---|
| **REV-JQ-1** | arch (unclaimed) | backlog | — | Harden review verdict telemetry against empty/malformed findings counts (`loop-bot-herd.sh:567`, observed live) |
| **INTEG-REC-1** | arch (unclaimed) | backlog | — | Arbiter integration emits durable session-verdict record (unblocks post-integration docs sweeps) |
| **TEST-PATH-1** | arch (unclaimed) | backlog | — | Hermeticize `tests/test_profile.sh:78` PATH — 4th instance of the CI-FIX runner-shadow class |
| **REV-07** | human | backlog | — | Decide multi-reviewer quorum (or accepted-limit ADR); consume OpenRig cross-vendor finding; review is the quota SPOF |
| **BORROW-1** | human | backlog | — | Triage OpenRig §7 borrows — adopt / decline / fog each, with receipts |

## Not yet specified

- Inline TUI review-diff inspection — carried fog from `maps/autonomous-reviewer-loop.md`; still needs its own
  research pass on what Herdr's pane model can render.
- The deeper OpenRig borrows pending BORROW-1's verdicts: seeded-regression test pairs, a stub seat runtime,
  evidence-hashed verdicts, an `INDETERMINATE` floor for `stampede status`, snapshot-before-`down`, webhook
  notification adapter for headless/CI.

## Out of scope

- P3-4 arbiter batch integration (`maps/tickets-parked/arbiter-batch-integration.md`) — stays parked until the
  driver unparks it.
- Extending quota probing beyond `agy` (carried exclusion from `maps/dispatch-safety-and-review-policy.md`).
- Anything that moves `main` or `origin/main` without the human.
