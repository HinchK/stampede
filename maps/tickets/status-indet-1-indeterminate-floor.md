---
id: STATUS-INDET-1
title: "INDETERMINATE floor for stampede status"
type: wayfinder:task
status: backlog
assignee: arch
owns: lib/cli/stampede-status.sh
parent: maps/pick-up-where-we-left-off.md
---

# STATUS-INDET-1 — derive status facts at read time; never collapse unknowns into labels

## Intended Outcome

`stampede status` (rich mode) reports seat facts **derived at read time** from live sources
(seats.json, pane queries, git refs); when a source is unreadable, stale, or ambiguous, the
affected field prints `INDETERMINATE (basis: <reason>)` instead of inferring health from recorded
labels. Derived, never authored (OpenRig comparison §7 #4, adopted via BORROW-1).

## Background (receipts)

- OpenRig's execution view: "no field is copied from a label a human wrote about state"; an
  unreachable source renders the literal `INDETERMINATE`, never idle/done/false
  (`openrig:packages/daemon/src/domain/execution-view.ts:L6-L22`, per
  `.herdr-swarm/research/2026-10-08-openrig-comparison-review.md` §5.5).
- Our `lib/cli/stampede-status.sh` panels largely report recorded labels (seats.json entries,
  review states) — a stale ledger prints confident facts about a seat whose pane is gone. The
  ROUTE-4 seat-activity panel already derives commit shares from git records at read time; the
  same discipline extends to seat presence.

## Done-Criteria

1. Seat presence panel: unreadable or missing `seats.json` → `seats: INDETERMINATE (basis:
   seats.json unreadable: <err>)`, not an empty/healthy-looking panel.
2. Per-seat rows: a ledger entry whose pane query fails or returns a cwd mismatch renders
   `INDETERMINATE (basis: ...)` rather than the last recorded state.
3. No path in the status panels turns an unreadable source into a confident claim (grep-level
   audit in the ticket receipt).
4. Tests in `tests/test_cli_status.sh`: unreadable seats.json, missing pane, healthy path
   unchanged.
5. `make check` green (all suites), 0 ShellCheck warnings.

## Verification Step

```bash
bash tests/test_cli_status.sh && make check
```
