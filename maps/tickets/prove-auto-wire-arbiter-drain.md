---
id: PROVE-4
title: "Auto-wire arbiter_drain after a successful enqueue"
type: wayfinder:task
status: resolved
commit: 16dd481
assignee: arch
owns: loop-bot-herd.sh,lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/prove-and-reconcile.md
---

# PROVE-4 — Auto-wire arbiter_drain (Wave 1)

**Source:** `docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md` §6, §10 step 4; grilled and
settled with the driver 2026-09-23.

## Intended Outcome

`arbiter_drain` runs automatically immediately after a successful `arbiter_enqueue`, instead of sitting until an
operator manually runs `lib/arbiter.sh drain`. Promotion to `main` stays the untouchable human gate — this ticket
never touches that.

## Background

```
$ grep -rn 'arbiter_drain' herdr-loop-swarm.sh loop-bot-herd.sh lib/lifecycle.sh
(no matches)
```

`arbiter_drain` is only reachable today via `bash lib/arbiter.sh drain` (its own CLI dispatcher) and the test
suites. Green verdicts enqueue automatically (`loop-bot-herd.sh:261`) but then sit — arguably part of why DOG-17/18
sat gated-but-undrained long enough for `main` to drift out from under it (see PROVE-1).

**Decision (settled, not open):** ADR 0009 locks *promote*-to-`main` as sovereign-human forever, but never decided
*drain* (which only advances `swarm/stampede/integration`, not `main`). Auto-wiring drain does not touch the
sovereign-human-promotion invariant.

## Done-Criteria

1. A successful `arbiter_enqueue` call triggers `arbiter_drain` in the same pass (or immediately after, via the
   supervisor's loop), still serialized under the existing `.herdr-swarm/arbiter.lock`.
2. `arbiter_drain` still never touches `main` — only `swarm/stampede/integration`.
3. A conflict during auto-drain still aborts and hands back to the worker (no automatic conflict resolution) — this
   invariant from ADR 0009 is unchanged.
4. `tests/test_arbiter.sh` covers the new automatic trigger; suite stays green.

## Verification Step

```bash
bash tests/test_arbiter.sh   # new assertions for auto-drain-after-enqueue pass
# Manual: enqueue a green verdict, confirm swarm/stampede/integration advances
# without a separate `lib/arbiter.sh drain` invocation.
```
