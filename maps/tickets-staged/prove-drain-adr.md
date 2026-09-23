---
id: PROVE-5
title: "Record the arbiter_drain auto-wire decision in a new ADR"
type: wayfinder:doc
status: backlog
assignee: agy-docs
blocked_by: PROVE-4
owns: docs/adr/,README.md
parent: maps/prove-and-reconcile.md
---

# PROVE-5 — Drain automation ADR (Wave 1)

**Source:** grilled and settled with the driver 2026-09-23; see `maps/prove-and-reconcile.md` Decisions so far.

## Intended Outcome

A new ADR (next number after 0013) records that `arbiter_drain` auto-runs after a successful enqueue, why that's
safe (it only advances the integration ref, never `main`), and that ADR 0009's sovereign-human-promotion invariant
is unchanged. Written against what PROVE-4 actually built, not a hypothetical — this ticket is blocked by PROVE-4.

## Done-Criteria

1. New file `docs/adr/00NN-arbiter-drain-automation.md` (next sequential number).
2. States the decision, the alternatives considered (stay operator-only), and why auto-wiring doesn't conflict with
   ADR 0009 (drain vs. promote are different refs with different trust requirements).
3. Cross-references ADR 0009 and PROVE-4's actual implementation (file/line).
4. `README.md`'s ADR index is updated to list it.

## Verification Step

```bash
ls docs/adr/ | tail -1   # new ADR present, sequential
grep -c "00NN" README.md   # indexed
```
