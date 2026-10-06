# ADR 0016: The Headless Batch Review Boundary — an Accepted Limit

- **Status**: Accepted
- **Date**: 2026-10-05
- **Deciders**: driver (settled), `arch` (recorded)
- **Consulted**: [ADR 0015: Headless Batch Drain Mode](0015-headless-batch-drain-mode.md), [ADR 0009: Arbiter Branch Integration and Human Promotion Gates](0009-arbiter-branch-integration-and-cas-merge.md), [HORIZON-2 live proof](../findings/headless-live-proof.md), [Wayfinder Map: Prove It Live & Ship 0.5.0](../../maps/headless-live.md), Tickets HORIZON-2/HORIZON-3

---

## 1. Context and Problem Statement

Every integration path in this project goes through the autonomous reviewer
loop before a green verdict enqueues for the arbiter: interactive seats
(`loop-bot-herd.sh`'s review seam, REV-1..5), and — since the incident-class
hardening work (PART-1/PART-2, HL-WT-1, HL-CFG-1, HL-LEDGER-1) — every path
that reaches `swarm/<slug>/integration`.

`stampede headless` (ADR 0015) is the one exception, and until this record it
was documented only by a bare code comment in `lib/cli/stampede-headless.sh`:
the batch runs with `CONFIG_REVIEW_LOOP=0`, and greens route straight to the
arbiter queue — suite gate + HEADLESS-5's mechanical ceilings, no reviewer
pass. HORIZON-3 asked whether that boundary should become a feature
(headless reviewer rounds) or an accepted limit with a written decision. The
driver settled it: **accepted limit**.

## 2. Decision

Batch-mode quality assurance is **the suite gate plus HEADLESS-5's mechanical
safety ceilings, not a reviewer pass**:

- Every dispatched ticket runs the project's real `TEST_CMD` on its gated
  tree before anything enqueues (ADR 0008 semantics, unchanged).
- No verdict → dead-letter record + lease release + non-zero batch exit.
- Repeated conclusive failure → `max_verdict_attempts` ceiling → DEAD_LETTER,
  never an infinite critique loop.
- Wall-clock overrun → TERM, then SIGKILL escalation after the kill grace
  (HL-TMO-1) — a worker cannot evade its bound.

Review — adversarial reading by a second model with findings, BLOCK verdicts,
and critique rounds — remains an **interactive-herd-only feature**.
`stampede headless` never spawns a reviewer and never routes batch greens
through `reviews.json`.

## 3. Reasoning

1. **The design point is unattended speed.** Headless mode exists to drain a
   queue of tickets with zero panes, zero operator, and minimal wall clock
   (ADR 0015). A reviewer round per ticket means: provision a reviewer
   worktree, write its ledger entry, spawn a second vendor subprocess, await
   its verdict, and handle BLOCK with another critique turn — roughly
   doubling per-ticket complexity and runtime, in the one mode whose entire
   value is doing more with less ceremony.
2. **No demonstrated gap.** The HORIZON-2 live proof
   ([findings](../findings/headless-live-proof.md)) produced no instance of a
   suite-gate-green-but-actually-broken ticket that review would have caught.
   The live target ticket never even reached a verdict — it dead-lettered
   honestly (`worker exited rc=1 without a verdict`) on an unrelated config
   defect (a stale provider-model id, since fixed), and the mechanical
   ceilings carried that failure exactly as designed. We are not paying
   double complexity against a hazard with no observed instance.
3. **Scope of work is already restricted.** Headless runs are reserved by
   design for small, mechanical, suite-gate-provable tickets — HORIZON-2's
   own target-ticket criteria (a doc fix, a one-line change, "provable by
   the suite gate alone"). The reviewer loop exists for nuanced judgment
   work: subtle defects, convention violations, spec-vs-implementation drift.
   Routing that class of work through the batch would be a dispatch-policy
   failure regardless of whether a reviewer sat at the end of it.
4. **The consistency cost is real and now written down.** Every other
   integration path reviews first; this is the one exception. Keeping an
   exception as a bare code comment is how it silently becomes folklore —
   this record is the fix for that, not for the boundary itself.

## 4. Consequences

- Batch greens integrate without review by design; anyone auditing
  `integration.jsonl` should read this ADR, not assume an omission.
- Interactive seats are unaffected: review rounds, telemetry, and the
  `reviews.json` state machine continue exactly as REV-1..5 built them.
- A ticket discovered post-hoc as batch-landed and under-reviewed is a
  dispatch-policy bug (wrong class of work sent to the batch), remedied by
  interactive review of that ticket — not by re-architecting the batch.
- `lib/cli/stampede-headless.sh`'s code comment now cites this ADR; if the
  two ever disagree, the code is wrong or this ADR is being amended.

## 5. Revisit trigger

This decision reopens if a **real incident** surfaces where a
headless-landed, suite-gate-green ticket carried a defect a reviewer pass
would have caught. That is grounds to flip Option (a) of HORIZON-3 and build
headless reviewer rounds. Absent that incident, the limit stands.
