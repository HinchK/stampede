---
id: HORIZON-2
title: "Prove stampede headless on a real ticket (live dogfood)"
type: wayfinder:task
status: resolved
assignee: arch
owns: docs/findings/headless-live-proof.md
parent: maps/next-horizon.md
blocked_by: [HORIZON-1]
---

# HORIZON-2 — one real ticket through the batch, receipts or it didn't happen

## Intended Outcome

`bin/stampede headless <dir> --max-tickets 1` completes one REAL backlog ticket
on this repository (real vendor CLI, real gate, real arbiter enqueue), and the
run is captured in `docs/findings/headless-live-proof.md`: the command, the
elapsed time, the session-verdict record, the integration queue entry, and
what broke that the hermetic stubs couldn't see.

## Problem

Every headless proof to date is stubbed (test_cli §9/§10). The reviewer loop
earned its live proof (PROVE-3) before we trusted it; the batch has not had
one. Hermetic suites cannot catch: vendor CLI auth in a bare subprocess,
profile quirks of this repo's own Makefile gate, ledger/provision
interactions with a real branch state.

## Done-Criteria

1. One real ticket dispatched, gated green (or its failure honestly recorded
   and dead-lettered — a real RED with receipts also proves the safety caps).
2. Findings doc with the receipts above + any follow-up defects filed.
3. `make check` still green.

## Verification Step

The findings doc quotes the batch's own summary line and the session-verdict
JSON for the ticket it processed.

## Pre-flight safety (added 2026-09-30, before release)

1. Seat collision: the scratch-repo proof named its worker arch-1-<slug>. On this live repo that could literally
   be arch-1-hinchk-stampede, a live interactive seat -- confirm headless worker naming can't collide with a live
   seat name, and that headless doesn't write into the same .herdr-swarm/seats.json a live interactive seat uses.
2. Ticket selection: dispatch with --max-tickets 1, and make the target ticket the ONLY backlog-status ticket in
   maps/tickets/ at run time -- check whether headless filters by assignee; if it doesn't, any other released
   ticket (e.g. HORIZON-4, QUOTA-1, DECISION-1) is fair game for accidental headless pickup.
3. No double dispatch: whoever runs this must confirm looper is not also about to interactively dispatch the same
   ticket through the normal herdr path.

## Corrected execution plan (added 2026-10-05, supersedes any instinct to release this ticket itself)

HORIZON-2 is dispatched INTERACTIVELY to a concrete arch seat, exactly like any other ticket -- never released
into maps/tickets/ as a backlog item. The seat that receives it does the following as its own work:

1. Confirm both prerequisites are live on main (not just integration) before running anything:
   - HL-LEDGER-1's fix (namespaced headless worker names) is an ancestor of main.
   - HL-CONFIG-1's .opencode/opencode.json is an ancestor of main.
   If either isn't on main yet, stop and report -- do not proceed on pre-fix code.
2. Write ONE small, separate, real target ticket directly into maps/tickets/ with status: backlog -- small,
   mechanical, provable by the suite gate alone (a doc fix, a one-line script change, something with an obvious
   low-risk done-criteria), owns: disjoint from anything live or from HORIZON-2's own owns
   (docs/findings/headless-live-proof.md). This is the actual headless proof target, not HORIZON-2 itself.
3. Confirm maps/tickets/ contains ONLY that one target ticket at status:backlog/queued at run time -- re-check,
   don't assume, since other tickets could have landed since this plan was written.
4. Snapshot .herdr-swarm/seats.json and .herdr-swarm/leases.json BEFORE running.
5. Run `bin/stampede headless <repo-root> --max-tickets 1` for real from the root checkout (post-promote main),
   with herdr confirmed off PATH.
6. Snapshot seats.json and leases.json AFTER running. Diff both snapshots -- this diff is the actual receipt
   that HL-LEDGER-1 holds live, not just in its own test suite. Any live interactive seat's pane/worktree_dir/
   branch must be byte-identical before and after.
7. Write docs/findings/headless-live-proof.md: the command, elapsed time, session-verdict JSON, integration
   queue entry, the seats.json/leases.json diff, and anything that broke that the hermetic suites couldn't see.
8. The target ticket itself lands on the integration branch WITHOUT a reviewer pass (headless mode's own
   documented boundary, HORIZON-3 is deciding whether that should change) -- note this explicitly in the
   findings doc, don't present it as reviewed.
9. Clean up: if the target ticket's own resolution needs anything beyond what headless itself did (doc updates,
   etc.), handle that as normal afterward.

## Resolution

- **Author:** `arch-2-hinchk-stampede` (commit `b9cdc39ee000b1cb14c38c3ca14bf722c043fd50`)
- **Review:** `reviewer-hinchk-stampede` Round 1/2 PASS (`.herdr-swarm/reviews/HORIZON-2-b9cdc39ee000b1cb14c38c3ca14bf722c043fd50.md`)
- **Integrated:** `b9cdc39` onto `swarm/stampede/integration` via `arbiter_enqueue_and_drain`
- **Summary:** Executed live headless proof run against root repository on `main` with `herdr` off PATH. Run 1 caught a stale nested worktree holding slug-global branch `swarm/hinchk-stampede/arch_1`, validating `HL-WT-1` loud refusal. Run 2 dispatched real target ticket `HL-TGT-1` and honestly dead-lettered with real log pointer (`HL-DOCS-1` receipt), diagnosing model prefix drift in `.opencode/opencode.json` (`zai/glm-5.3` vs `zai-coding-plan/glm-5.3`) and fixing it on branch. Validated live ledger preservation (`HL-LEDGER-1` receipt): all 7 interactive seats byte-identical before and after. Comprehensive receipts recorded in `docs/findings/headless-live-proof.md`.


