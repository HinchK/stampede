# Wayfinder Map: Prove It Live & Ship 0.5.0

**Parent epic:** the close-out of the headless arc · **Charted:** 2026-10-05 (arch, MILESTONE CHARTER
"Let's work through the next epic") · **Supersedes the remaining scope of** `maps/next-horizon.md`
(HORIZON-1/4/5 and the incident epic are done — receipts in that map's own status section).

## Why this is the next epic

Every hardening and surface ticket has landed and promoted: the close-the-gaps
epic (PART-1/2, ARB-SLUG-1, SYNC-1/2, HL-WT-1/HL-CFG-1/HL-TMO-1/HL-RED-1),
the harden-headless epic, QUOTA-1, HL-LEDGER-1, HL-CONFIG-1. `main` carries
all of it (verified: `git log main..swarm/stampede/integration | grep -c
'integrate #'` → 0; HL-LEDGER-1 `19135fe` and HL-CONFIG-1 `2cf79c0` both
ancestors of `main`). What has NEVER happened: a real `stampede headless` run
on this repository's own backlog against post-fix code — every proof to date
is hermetic stubs (PROVE-HEADLESS-1 ran pre-hardening). And the release that
CHANGELOG's `[0.5.0] — in development` entry describes is sitting finished
but unpublished.

## Destination

The headless arc is **done done**: proven live on this repo with receipts;
the batch's no-review boundary turned into a feature or an accepted-limit ADR
(never again a code comment); and 0.5.0 shipped (CHANGELOG dated, version
discipline green, tagged and pushed by the human).

## Tickets

| Ticket | Seat | Blocked by | Synopsis |
|---|---|---|---|
| **HORIZON-2** (resolved, commit `b9cdc39`) | arch | — | The live proof run per its own execution plan: single mechanical target ticket, seats/leases snapshots diffed, findings doc; lands on integration without reviewer pass (the documented boundary) |
| **HORIZON-3** (resolved, commit `2dfa8bd`) | arch | — (HORIZON-2 resolved) | Review rounds in batch mode — accepted-limit ADR 0016 codified |
| **HL-DL-1** (resolved, commit `c1f8f1b`) | arch | — (HORIZON-3 resolved) | Per-batch scoping for headless dead-letter count — prevent historical dead letters from failing later green batches |
| **REL-1** (unblocked, human ready) | human | — (HORIZON-3 resolved) | Publish 0.5.0: date the CHANGELOG entry, `make version-check`, human tag + push (ready for human operator) |

No other open tickets exist: all tickets in `maps/tickets/` are resolved; the staged queue carries `REL-1` (unblocked, human operator);
the parked queue is one deliberately-parked item (`arbiter-batch-integration`, kept per the HORIZON-5 triage).

## Decisions so far

- 2026-10-05 (charting): reference HORIZON-2/3 as-is — their staged text is
  current and carries the corrected, safety-first execution plan; re-chartering
  would fork a plan that is already right.
- 2026-10-05 (charting): HORIZON-2 is dispatched INTERACTIVELY to a concrete
  arch seat (per its own plan) — never released into the backlog queue where
  another headless run could pick it up.
- 2026-10-05 (charting): REL-1 sequences behind HORIZON-3 so the release
  notes can state the review boundary truthfully either way.
- 2026-10-05 (live proof): HORIZON-2 resolved; live proof found 2 real defects incl. the stale model id affecting the config you just had approved (fixed to `zai-coding-plan/glm-5.3`), HL-LEDGER-1 confirmed holding live via byte-identical ledger diff; full receipts in [docs/findings/headless-live-proof.md](docs/findings/headless-live-proof.md).
- 2026-10-05 (review boundary): HORIZON-3 resolved; driver settled Option (b) accepted limit — batch quality is enforced by suite gate + HEADLESS-5 mechanical ceilings, never a reviewer pass; review remains interactive-only; stampede headless never spawns a reviewer; full rationale and revisit trigger codified in [docs/adr/0016-headless-batch-review-boundary.md](docs/adr/0016-headless-batch-review-boundary.md).
- 2026-10-05 (dead-letter scoping): HL-DL-1 resolved; dead-letter counting scoped to active batch run via append-only since-index offset, preserving Hazard 3 while unblocking subsequent green runs on repos with historical failures.

