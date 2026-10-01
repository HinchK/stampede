---
id: DECISION-1
title: "Correct INCIDENT-1's stale CRED-1 reference; record the CRED-1-to-GRANT-1 decision"
type: wayfinder:doc
status: backlog
assignee: agy-docs
owns: docs/audits/,STATE.md,maps/tickets/incident-1-promote-gate-bypass-record.md
parent: maps/next-horizon.md
---

# DECISION-1 -- close the incident class with an accurate record

## Intended Outcome

`maps/next-horizon.md`'s own destination requires the 2026-09-24 incident class to be "closed or consciously
accepted with a written decision." `INCIDENT-1`'s resolution (already landed) cross-references `CRED-1` as "the
actual fix, still open" -- but `CRED-1` (multi-account credential separation) was explicitly dropped mid-session
on the driver's direction ("i do not like this multi-github strategy at all... too concerned with safety in the
detriment of progress") in favor of `GRANT-1` (session-scoped promote grant), which shipped and integrated. No
ADR or decision record exists documenting that substitution -- `git grep -li "CRED-1\|GRANT-1" docs/adr/` returns
nothing. Today, a reader of `INCIDENT-1` alone would still believe the real fix is pending.

## Done-Criteria

1. `INCIDENT-1`'s ticket file gets a short addendum (not a rewrite of its existing resolution) noting `CRED-1`
   was superseded by `GRANT-1` and why, linking the actual session exchange's reasoning (friction/safety
   trade-off) rather than re-deriving it.
2. `STATE.md`'s reference to `CRED-1` as pending is corrected to point at `GRANT-1`'s actual resolution.
3. A short decision record exists (new `docs/audits/2026-09-3x-cred-1-superseded-by-grant-1.md`, or added to an
   existing audit doc if one already covers `GRANT-1`'s shipping -- check first) stating: the problem `CRED-1` was
   researching, why it was dropped (friction cost judged to outweigh the safety gain for this project's threat
   model), and why `GRANT-1` was judged sufficient instead.
4. `maps/next-horizon.md`'s "What is actually unresolved" section item 1 is updated to reflect this closure.

## Verification Step

Human/pm review -- doc-only, no test suite applies. `git grep -i "CRED-1" STATE.md maps/tickets/incident-1-
promote-gate-bypass-record.md` no longer implies an open fix.
