---
id: STATUS-INDET-1
title: "INDETERMINATE floor for stampede status"
type: wayfinder:task
status: resolved
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

## Resolution (2026-10-08)

Resolved in commit `c65bae8b5501e2302f82f0ec0846e87e2fe29026` (`c65bae8`).

Delivered across all criteria:
1. **Ledger floor**: `_status_presence_json` (lib/cli/stampede-status.sh:62) renders panel-level `seats: INDETERMINATE (basis: seats.json unreadable: missing | read error | invalid json | no seats array)` — missing, present-but-unreadable, corrupt, and wrong-shape ledgers each carry their basis; the panel never renders empty-as-healthy. The aggregator itself failing degrades to `basis: presence aggregation failed` (fail-closed).
2. **Per-seat floor**: presence is derived at read time — one `herdr pane list` query (the same surface lib/lifecycle.sh trusts) × the ledger's pane ids and expected dirs (worktree for isolated seats, physical repo root otherwise). Only positive confirmation renders `present`; a failed query (`pane query failed: herdr not on PATH | herdr pane list exited rc=N | pane list output not JSON`), a dead pane (`dead pane: <pane> not in pane list`), or cwd drift (`cwd mismatch: pane in <cwd>, seat expects <dir>`) renders `INDETERMINATE (basis: ...)`. Both renderers print from one JSON object (`.presence`), so `--json` and the human table cannot disagree.
3. **Grep-level audit** of read paths in the module: (a) `_status_read_jsonl`/`_status_read_traces` — missing artifacts are the designed friendly-empty state (PUB-11, test-pinned) and torn lines drop via `fromjson?` (PUB-10 absence semantics); an exists-but-unreadable verdicts/queue file still degrades to empty counts — pre-existing semantics outside this ticket's seat scope, flagged here as the known limitation; (b) `_status_activity_json`'s roster read degrades to no-roster on a corrupt ledger — the adjacent presence panel now carries that ledger's INDETERMINATE basis, so the dashboard as a whole never presents a confident claim on an unreadable ledger; (c) the presence path itself is floored end-to-end per criteria 1-2.
4. **Tests**: `tests/test_cli_status.sh` gains 14 assertions — healthy (anchor seats present via root cwd; isolated seat present via worktree cwd; a pane sitting in the repo ROOT still mismatches an isolated seat), cwd mismatch (exact basis string), dead pane (exact basis), query failure rc=1 (every row INDETERMINATE), herdr not on PATH (in-process probe with a hermetically herdr-free minimal bin — removing the stub would expose a developer host's real herdr, TEST-PATH-1's defect class), missing and corrupt seats.json (JSON + human line, exact basis). All prior healthy-path assertions untouched and green (59/59). The suite stubs `herdr` on PATH for every invocation, so no run ever queries the host's real herdr.
5. **Verification**: `bash tests/test_cli_status.sh` 59/59; `make check` green (21 suites); `make lint` 0 warnings.
