# P3-4 Spec — Arbiter Batch Integration and Non-Blocking Drain Pipeline (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `144efea` · **Target:** `lib/arbiter.sh`, `tests/test_arbiter.sh`
**Implements:** `docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md` §1.4 (lever **P3-a**) · **Depends on:**
P2-4 arbiter (landed), P3-3 async harvesting (landed, `eafdc91`)
**Evidence:** probes against git 2.55.0; every number below was observed, not estimated.

## 0. Why

Measured on the shipped arbiter: three queued greens with a 2 s suite drain in **6 s** — strictly serial, one full
suite per ticket. At a realistic 60 s suite and 6 workers that is **~6 minutes per round**, during which the
integration tip drifts further from every worker's base, which is what manufactures conflicts. The ref-write
serialization is correct and stays; what must shrink is **suite runs per ticket**.

**Design validation probe** (5 branches: 3 disjoint, 1 conflicting, 1 suite-breaking):

| Step | Result |
|---|---|
| assemble batch by merging each queued green in turn | included `w1 w2 w3 w5`, **deferred only** `w4` (conflict) |
| single gate over the assembled batch | `rc=1` (the suite-breaker is inside) |
| re-assemble without the culprit, gate again | **`rc=0`**, `f1.txt f2.txt f3.txt` all present |
| bisect cost, k=4 | 1 gate if green; `1+⌈log₂4⌉ = 3` gates to isolate, vs **4** serial |

The middle two rows are the thing worth proving: **one bad ticket does not invalidate its batch-mates.**

---

## 1. Lever P3-a — batch integration

### 1.1 Configuration

```toml
[fanout]
batch_max          = 4     # max queued greens per candidate; 1 = today's per-ticket behaviour
batch_bisect       = true  # false = on RED, defer the whole batch to size-1 retries
max_consecutive_red = 2    # circuit breaker (§3)
```

`batch_max = 1` must reproduce current behaviour exactly, so the lever is revertible by config.

### 1.2 Assembly (inside the existing `arbiter_lock`, in the detached arbiter worktree)

```
I0 = current integration tip (or ARB_BASE when the ref is absent)
checkout --detach I0
members = []
for rec in queued records, oldest ts first, while |members| < batch_max:
    if merge-base --is-ancestor <candidate> rec.sha : merge is a fast-forward
    git merge --no-ff --no-edit rec.sha
        success        → members += rec
        conflict       → git merge --abort; mark rec `conflict` (files listed); CONTINUE to next rec
candidate = HEAD
```

- **Assembly order is `ts` ascending**, so a batch is reproducible from the queue alone — required for the crash
  recovery in §1.5 and for meaningful bisect logs.
- A conflicting record is **deferred, not fatal**: the probe confirms the rest of the batch still assembles. The
  conflicting worker is prompted exactly as today (merge integration, resolve, re-verdict).
- `members == []` after the sweep ⇒ nothing to gate; release and return.
- `|members| == 1` ⇒ identical to the current path (one merge, one gate, one CAS).

### 1.3 Gate and advance

1. Run `TEST_CMD` once in the arbiter worktree on `candidate`, with the same clean-tree precondition and per-run log
   that P2-3/P3-3 established.
2. **Green** → single CAS: `git update-ref "$ARB_REF" <candidate> <I0>`. All members become `integrated`, each carrying
   `batch_id` and `merge_sha`. One ref write for k tickets.
3. **RED** → §1.4. The ref is **not** advanced; nothing durable has changed.
4. **CAS rejected** (tip moved under us) → discard the candidate, re-derive `I0`, and rebuild the batch (bounded to 3
   attempts, then `blocked`). The batch was built on `I0`, so it is not salvageable against a different tip.

### 1.4 Bisect on RED

Binary search over `members`, preserving `ts` order; each probe re-assembles a **prefix subset** from `I0` in the
arbiter worktree and gates it:

```
lo=0, hi=k
while hi - lo > 1:
    mid = (lo+hi)/2
    assemble members[0..mid) from I0; gate
    green → lo = mid          # culprit is in the upper half
    red   → hi = mid          # culprit is within the lower half
culprit = members[lo]
```

- **Cost:** `1 + ⌈log₂ k⌉` gates on RED (3 for k=4, measured), against `k` gates for today's serial drain. Batching is
  therefore never worse than serial beyond `k=2`, and strictly better on the green path (1 gate for k tickets).
- **Culprit confirmation (flaky-suite guard):** gate the culprit **alone** against `I0`. If that run is *green*, the
  batch failure was order-dependent or flaky: record `flaky_suspect`, do **not** mark the culprit
  `integration_red`, and fall back to `batch_max = 1` for the next `max_consecutive_red` batches. Bisect assumes a
  deterministic suite; this is the check that keeps a flaky suite from blaming an innocent ticket.
- **Culprit handling:** `integration_red` with the bisect log paths; the owning seat is prompted to fix and re-verdict.
- **Innocents:** re-assembled without the culprit and gated once more; green ⇒ they integrate in the same pass (probe:
  `rc=0`, all three files present). They are **never** marked red and never lose their green verdict.
- `batch_bisect = false` ⇒ skip the search, return every member to `queued`, and process them at `batch_max = 1`.

### 1.5 Crash safety

Nothing durable exists until the CAS: the candidate lives in the detached arbiter worktree, and queue records stay
`queued` until they succeed. A supervisor killed mid-batch leaves the tip untouched; the next drain re-derives the same
batch from the queue in the same `ts` order. The arbiter worktree is re-`checkout --detach`ed at the start of every
assembly, so leftover state from a dead run is discarded rather than inherited.

---

## 2. Eliminating the head-of-line break

`lib/arbiter.sh` today:

```bash
if ! _arb_integrate "$ticket" "$seat" "$sha" "$i0"; then
  break   # record was resolved (conflict/red/retry); stop this pass
fi
```

One conflicting or RED record ends the entire pass, so every queued ticket behind it waits a full poll interval —
even though the arbiter holds the lock and could have integrated them immediately.

**Fix:** skip and continue. With batching, a resolved record is simply excluded from the next assembly.

**Progress guarantee (why the `break` was load-bearing).** Continuing is only safe if every iteration removes at least
one record from the `queued` set; otherwise the `while :` spins forever. Requirements:

1. Every terminal path must **write a non-`queued` status** for the record it resolved (`conflict`, `integration_red`,
   `superseded`, `blocked`).
2. The loop asserts progress: if a pass completes with the same `queued` id-set as it started with, write
   `status: "stalled"` for the head record, emit `arbiter.stalled`, and break. A spin is a bug, but it must not become
   a hang.
3. A per-pass cap (`batch_max × 4` iterations) bounds any pathological case.

---

## 3. Back-pressure and circuit breakers

Metrics, emitted each drain as `arbiter.metrics` telemetry and shown in `status`:

| Metric | Definition | Threshold action |
|---|---|---|
| `queue_depth` | records with `status: queued` | `> max_workers` ⇒ `fanout.backpressure`; looper stops dispatching new tickets |
| `integration_lag` | `rev-list --count <base>..<ARB_REF>` | reported; a growing lag with a flat `queue_depth` means promotion is overdue |
| `conflict_rate` | conflicts ÷ resolved over the last 20 records | `> 0.3` ⇒ warn: the partition (P3-2 `owns`) is not holding |
| `consecutive_red` | batch gates RED in a row | `≥ max_consecutive_red` ⇒ **breaker opens** |
| `oldest_queued_age` | now − oldest queued `ts` | `> 30 min` ⇒ escalate to human |

**Breaker open** ⇒ batching drops to `batch_max = 1` (slower, unambiguous attribution), the looper stops dispatching,
and the human is told which tickets are implicated. It closes after one green integration at size 1. The breaker never
advances a ref and never discards a record; it only slows the pipeline down and asks for a human.

---

## 4. Acceptance

`tests/test_arbiter.sh`, scratch repos, no herdr required.

| # | Case | Expected |
|---|---|---|
| 1 | `batch_max = 1` | byte-identical behaviour to `144efea` (one merge, one gate, one CAS per ticket) |
| 2 | 4 disjoint greens, `batch_max = 4` | **one** gate run, one CAS, 4 records `integrated` sharing a `batch_id` |
| 3 | 6 queued, `batch_max = 4` | first batch takes 4, second pass takes 2; no record skipped or duplicated |
| 4 | one member conflicts at assembly | it alone is `conflict`; the other 3 assemble, gate and integrate in the same pass |
| 5 | one member breaks the suite | bisect isolates it; culprit `integration_red`; **innocents integrate** (probe-backed) |
| 6 | bisect gate count, k=4 | ≤ `1+⌈log₂4⌉ = 3` gates after the initial batch gate fails |
| 7 | culprit passes when gated alone | `flaky_suspect` recorded; no ticket marked red; `batch_max` drops to 1 |
| 8 | conflict record no longer breaks the pass | remaining queued records are processed in the **same** pass (head-of-line fix) |
| 9 | integration tip moved during the batch | CAS rejected, batch rebuilt on the new tip, nothing lost; ≤ 3 attempts then `blocked` |
| 10 | supervisor killed mid-batch | tip unchanged; next drain re-derives the identical batch from the queue |
| 11 | `queue_depth > max_workers` | `fanout.backpressure` emitted; dispatch halted |
| 12 | `consecutive_red ≥ max_consecutive_red` | breaker opens; `batch_max` forced to 1; human escalation |
| 13 | a queued record is superseded mid-pass | the superseded sha is excluded from the batch; only the newest integrates |
| 14 | empty queue / all records non-`queued` | drain returns 0, no gate, no ref write |
| 15 | pass makes no progress | `stalled` recorded, `arbiter.stalled` emitted, loop exits (no spin, no hang) |
| 16 | batch gate times out | non-zero rc ⇒ RED path; slot released; no partial ref advance |

Cases 5, 8 and 15 are the ones that must be in the receipt: they are the defect, the fix, and the hazard the fix introduces.

## 5. Edge cases and risks

- **Non-deterministic suites** break bisect's core assumption. Case 7's confirmation step is the mitigation; without it the arbiter would blame innocent tickets and the herd would lose trust in RED.
- **Two tickets from the same seat** in one batch is legal (the seat branch advances monotonically) — assembly order by `ts` keeps it deterministic.
- **Base branch moved** (human merged to `main`) during a batch: the candidate is still built on `I0`; the merge into `main` happens at human `promote`, unchanged by this ticket.
- **Batch size vs blast radius:** a larger `batch_max` means fewer gates but a wider suspect set on RED. Start at 4; raise only with `conflict_rate` and `consecutive_red` measured.
- **Log volume:** each bisect probe keeps a gate log. Reuse P3-3's retention window.
- **What this does not fix:** integration still costs at least one full suite run per pass, and the arbiter still holds its lock throughout. Speculative parallel gating (P3-b) and scoped gating (P3-c) remain future levers.

## 6. Out of scope

Speculative parallel gating (P3-b), test-impact selection (P3-c), promotion policy changes, and the dispatch side of
back-pressure (the looper consumes the signal; emitting it is this ticket).
