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
