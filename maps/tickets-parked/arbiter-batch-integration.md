---
id: P3-4
title: "Phase 3: Arbiter Batch Integration and Non-Blocking Drain Pipeline"
type: wayfinder:task
status: backlog
assignee: arch
owns: lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/universal-herdr-swarm.md
---

# Phase 3: Arbiter Batch Integration and Non-Blocking Drain Pipeline (P3-4)

**Specification:** [P3-4 Arbiter Batching Spec](../../docs/audits/2026-09-19-p3-4-arbiter-batching-spec.md)
**Roadmap:** [Phase 3 Concurrent Fan-Out](../../docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md) §1.4 (lever P3-a)

## 1. Intended Outcome

Integration costs **one suite run per batch** instead of one per ticket, and a single conflicting or RED record no
longer stalls every ticket queued behind it.

## 2. Problem

Measured on the shipped arbiter: 3 queued greens × a 2 s suite = **6 s** wall, strictly serial. At a 60 s suite and 6
workers that is ~6 minutes per round, and integration lag is what manufactures the next round of conflicts.
Separately, `arbiter_drain` `break`s the whole pass when a record resolves as conflict/RED, so queued tickets behind it
wait a full poll interval despite the lock already being held.

## 3. Scope

1. **Batch assembly** (`batch_max`, default 4): merge queued greens onto the candidate in `ts` order inside the
   detached arbiter worktree; a conflicting record is deferred and the rest continue.
2. **One gate per batch**, then a single CAS advancing `swarm/<slug>/integration` for all members.
3. **Bisect on RED** (`1+⌈log₂k⌉` gates) to isolate the culprit, with a **culprit-confirmation** run that guards
   against flaky suites blaming innocent tickets; innocents re-assemble and integrate in the same pass.
4. **Head-of-line fix:** skip-and-continue instead of `break`, with an explicit progress assertion so the loop cannot spin.
5. **Metrics and circuit breaker:** `queue_depth`, `integration_lag`, `conflict_rate`, `consecutive_red`,
   `oldest_queued_age`; breaker forces `batch_max = 1` and halts dispatch.

## 4. Done-Criteria

1. `batch_max = 1` reproduces current behaviour exactly (revertible by config).
2. 4 disjoint greens integrate with **one** gate run and one CAS, sharing a `batch_id`.
3. A suite-breaking member is isolated by bisect; its batch-mates still integrate in the same pass.
4. A culprit that passes when gated alone is recorded `flaky_suspect`; no ticket is marked red.
5. A conflict record no longer ends the pass; remaining queued records are processed immediately.
6. A pass that makes no progress records `stalled` and exits rather than spinning.
7. CAS rejection rebuilds the batch on the new tip (≤ 3 attempts, then `blocked`); no lost update.
8. Kill mid-batch ⇒ tip unchanged, next drain re-derives the identical batch.
9. All 16 acceptance cases in the spec pass; `tests/test_arbiter.sh` green.
10. `shellcheck lib/arbiter.sh` clean (0 warnings).

## 5. Verification Step

```bash
bash tests/test_arbiter.sh          # every assertion, including cases 5, 8 and 15
shellcheck lib/arbiter.sh
```

Receipt must include the gate-count evidence for a k=4 batch: 1 gate on the green path, ≤ 4 on the RED path
(initial + bisect), against 4 for today's serial drain.

## 6. Notes

Design was validated on scratch repos before specification: batch assembly deferred only the conflicting branch
(4 of 5 included), the single batch gate caught the suite-breaker, and re-assembly without it integrated all three
innocent branches (`rc=0`). Bisect arithmetic for k=4 is 3 gates.

Does **not** change promotion (`main` still moves only by human `promote`), and does not introduce speculative or
scoped gating — those remain separate levers.
