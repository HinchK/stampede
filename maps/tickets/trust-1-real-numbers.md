---
id: TRUST-1
title: "Publish real trust-tax numbers from telemetry, replacing the modelled 80% claim"
type: wayfinder:task
status: backlog
assignee: agy-docs
owns: docs/findings/,docs/findings/swarm-orchestration-retrospective.md
parent: maps/universal-herdr-swarm.md
---

# TRUST-1 — Real trust-tax measurement (from the 9/21 public-readiness review)

## Intended Outcome

`docs/findings/swarm-orchestration-retrospective.md` §3.2 ("The Trust Tax") currently states only that total token
spend goes up, with no measured numbers — DOG-4 already correctly relabeled the 80% figure elsewhere in the doc as
modelled, not empirical, but no *real* measurement has replaced it. PUB-10 already built the telemetry schema
(`docs/findings/telemetry-schema.md`, `lib/telemetry.py`) with measured, never-modelled fields. Real trace data now
exists from actual dispatches (`.herdr-swarm/traces/swarm-20260919-114508.jsonl`), including the just-completed
`Prove and Reconcile` epic (DOG-17, DOG-18, PROVE-2, PROVE-4, PROVE-6, PROVE-7). This ticket mines that data into
a real, published number for each of the five proxies the 9/21 review named, and updates the retrospective to cite
them (or explicitly state what remains unmeasured, and why).

## The five proxies (from the 9/21 public-readiness review)

1. Brief bytes delivered (nonce delivery protocol — how compact the actual dispatch payload is).
2. Suite-gate runs per retired ticket.
3. Re-verdict count per ticket (how often RED → re-verdict happened).
4. Dispatches per integration (how many tickets land per arbiter integration cycle).
5. Wall-clock per ticket — **use lease.acquired → suite.verdict gaps for tickets dispatched and completed in one
   continuous session** (e.g. PROVE-2: ~7.5 min, PROVE-4: ~7 min, PROVE-6: ~4 min from the current trace) rather
   than raw acquired-to-verdict deltas for tickets that spanned idle gaps between sessions (DOG-17/18 show
   multi-hour gaps that are session idle time, not active gate duration — don't report those as "wall-clock per
   ticket" without that caveat, or the number will be misleading in the opposite direction of the 80% claim this
   ticket exists to fix).

## Explicitly out of scope (don't attempt to fix)

Per-seat token/cost accounting remains structurally unmeasurable — Herdr drives vendor CLIs over a PTY that
reports no usage data (already documented in the retrospective §3.2). Don't try to work around this; state it
plainly as a known limitation alongside whatever *is* measured.

## Done-Criteria

1. A new report (or an expanded §3.2) presents real numbers for proxies 1-4 fully, and proxy 5 with the
   continuous-session caveat above.
2. The retrospective's Trust Tax section links to it and no longer reads as if only the modelled 80% figure exists.
3. Numbers are computed from `.herdr-swarm/traces/*.jsonl`, cited with the exact events/timestamps used — reviewable
   the same way this ticket's own PROVE-2/4/6 estimates were (re-derivable by anyone re-reading the trace file).
4. `make test` unaffected (docs-only change) — still green.

## Verification Step

```bash
grep -c "lease.acquired\|suite.verdict" .herdr-swarm/traces/*.jsonl   # events exist to derive the numbers from
```

## Notes

This is analysis + writing, not code — a natural fit for `agy-docs`, not `arch`. If the existing trace file's
event coverage turns out too sparse for a fully confident number on any one proxy, say so explicitly rather than
filling the gap with an estimate — that would just recreate the exact problem (an unlabelled modelled number) this
ticket exists to close out.
