---
id: ROUTE-5
title: "agy-docs brief gains a post-integration docs-sweep mandate (companion to ROUTE-1)"
type: wayfinder:task
status: backlog
assignee: arch
owns: briefs/worker-docs.in.md
parent: maps/herdr-native-and-seat-utilization.md
---

# ROUTE-5 -- put agy-docs to work after every integration

## Intended Outcome

`briefs/worker-docs.in.md` gains a **Post-integration sweep** duty so `looper` can
hand `agy-docs` the routine documentation bookkeeping it currently does itself
(the majority of recent commits are looper doc/map reconcile edits).

## Background

PM audit 2026-10-07. Over the last 7 days `agy-docs` landed two tickets (DECISION-1,
HORIZON-4) while `looper` authored most of the 61 commits as ticket/map/STATE
bookkeeping. The epic charter (ROUTE-1..4) fixes `agy-gh` but leaves `agy-docs`
unaddressed, so the second underused seat stays underused.

## Done-Criteria

1. Brief defines a request shape: "sweep #<TICKET> <sha>" -> update ticket `status`,
   the parent map's roll-up line, and `STATE.md`, within the root-seat permitted paths
   only (`docs/`, `maps/`, `STATE.md`, `CONTEXT.md`, `README.md`).
2. Reply anchor `DOCS DONE <ticket> <sha>` (grammar must match what ROUTE-2 tells
   looper to wait on, character for character).
3. Sweeps are skipped, and reported as skipped, when the ticket's gate verdict is not
   green — docs must never record an unverified ticket as resolved.
4. Existing ADR/doc duties and the forbidden-path boundary are unchanged.
5. `bash lib/briefs.sh render` output contains the new section with variables
   substituted. `briefs/looper.in.md` is NOT edited here (ROUTE-2 owns it).

## Verification Step

Human/pm review of brief text plus `make check` green; diff the two anchor grammars
(ROUTE-2 vs this ticket) by eye.
