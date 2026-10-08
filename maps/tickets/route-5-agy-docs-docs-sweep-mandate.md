---
id: ROUTE-5
title: "agy-docs brief gains a post-integration docs-sweep mandate (companion to ROUTE-1)"
type: wayfinder:task
status: resolved
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

## Resolution (2026-10-07)

Done: Core Responsibilities item 2 "Post-Integration Sweep (on dispatcher request)" —
request shape `sweep #<TICKET> <sha>`; GREEN-verdict precondition read from
`.herdr-swarm/session-verdicts.jsonl` on the exact `(ticket, sha)` pair, skip (and
skip-report via the anchor + `— SKIPPED: gate verdict not green`) when not green;
on green updates ticket status, parent-map roll-up line, and `STATE.md` within the
root-seat permitted paths. Reply anchor is `DOCS DONE <ticket> <sha>` — bare ticket
id, no `#` (the request carries the `#`, the anchor does not; stated explicitly in
the brief so ROUTE-2 cannot disagree by one character). ADR/context/guide duties
renumbered only; guardrails and forbidden-path boundary unchanged;
`briefs/looper.in.md` untouched.

Receipts:
- `bash lib/briefs.sh render <repo> hinchk-stampede` → all briefs rendered; rendered
  worker-docs.md contains the new section with `{{DOCS_NAME}}`/`{{LOOPER_NAME}}`/
  `{{SLUG}}`/`{{REPO}}` substituted, zero leftover `{{`.
- `make check` → `All suites green (19)`, lint 0 warnings.
- `git status` after render → only `briefs/worker-docs.in.md` modified.
