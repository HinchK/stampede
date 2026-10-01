---
id: HORIZON-2
title: "Prove stampede headless on a real ticket (live dogfood)"
type: wayfinder:task
status: backlog
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
