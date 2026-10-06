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
| **HORIZON-2** (staged, current — corrected plan 2026-10-05) | arch | — (promote backlog is 0; both prereqs verified on main above) | The live proof run per its own execution plan: single mechanical target ticket, seats/leases snapshots diffed, findings doc; lands on integration without reviewer pass (the documented boundary) |
| **HORIZON-3** (staged, current) | arch | HORIZON-2 | Review rounds in batch mode — implement or write the accepted-limit ADR |
| **REL-1** (new, below) | human | HORIZON-3 | Publish 0.5.0: date the CHANGELOG entry, `make version-check`, human tag + push |

No other open tickets exist: `maps/tickets/` is 96 resolved / 11 closed /
2 done / 1 superseded / 0 backlog; the parked queue is one deliberately-parked
item (`arbiter-batch-integration`, kept per the HORIZON-5 triage).

## Decisions so far

- 2026-10-05 (charting): reference HORIZON-2/3 as-is — their staged text is
  current and carries the corrected, safety-first execution plan; re-chartering
  would fork a plan that is already right.
- 2026-10-05 (charting): HORIZON-2 is dispatched INTERACTIVELY to a concrete
  arch seat (per its own plan) — never released into the backlog queue where
  another headless run could pick it up.
- 2026-10-05 (charting): REL-1 sequences behind HORIZON-3 so the release
  notes can state the review boundary truthfully either way.
