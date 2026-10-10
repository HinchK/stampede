---
id: SNAP-1
title: "Snapshot before down: capture conversation and verdict state at teardown"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/lifecycle.sh
parent: maps/pick-up-where-we-left-off.md
---

# SNAP-1 — `swarm down` writes a timestamped snapshot before closing panes

## Intended Outcome

`swarm_down` captures a snapshot — per-seat transcript tails, `seats.json`, verdict/integration
ledgers, `reviews.json` — into `.herdr-swarm/snapshots/<UTC-ts>/` **before** closing panes, so
teardown stops destroying conversation state. Audit logs already survive; conversation threads
today do not (OpenRig comparison §7 #5, adopted via BORROW-1).

## Background (receipts)

- OpenRig's `rig down --snapshot` / `rig up <name>` captures and restores state with per-node
  outcomes, including honest `awaiting-decision` when a conversation cannot resume
  (`openrig:README.md:L336`, per
  `.herdr-swarm/research/2026-10-08-openrig-comparison-review.md` §5.1).
- Our teardown (`lib/lifecycle.sh` `swarm_down`) preserves `.herdr-swarm/` ledgers by design but
  issues no capture of pane scrollback; after `down`, the seats' in-flight reasoning is gone.
- Scope guard: this ticket is **capture only** — restore/resume is explicitly out of scope (it
  would need its own research pass; see the map's fog section).

## Done-Criteria

1. `swarm_down` writes `.herdr-swarm/snapshots/<UTC-timestamp>/` containing: per-seat transcript
   tails (bounded, e.g. last N lines via the existing seat-output seam), `seats.json`, session
   verdicts, `integration.jsonl`, `reviews.json`.
2. Snapshot failure is non-fatal but loud: stderr warning + the HERDR-5 notification seam (when
   inside Herdr) — teardown still proceeds only after the existing confirmation gate.
3. `-y`/`--keep-ws` flags unaffected; snapshot happens in all teardown paths that close panes.
4. Tests in `tests/test_worktree.sh` (the suite that exercises `swarm_down`): snapshot dir
   created with expected members on teardown; missing sources degrade to absent files with a
   warning, never a failed teardown.
5. `make check` green (all suites), 0 ShellCheck warnings.

## Verification Step

```bash
bash tests/test_worktree.sh && make check
```

## Resolution (2026-10-08)

Resolved in commit `e4c015e95795817960751f2013556633c662e659` (`e4c015e`).

Delivered across all criteria:
1. **Capture before close**: `_swarm_snapshot` (lib/lifecycle.sh:459) writes `.herdr-swarm/snapshots/<UTC-ts>/` with verbatim copies of `seats.json`, `session-verdicts.jsonl`, `integration.jsonl`, `reviews.json` plus `transcripts/<seat>.log` — per-seat tails via the supervisor's seat-output seam (`herdr agent read`, the same surface loop-bot-herd.sh:696 harvests), bounded to the last `${SWARM_SNAPSHOT_TAIL_LINES:-400}` lines. Roster sourced by the same ledger-first / live-registry-fallback decision as the pane retirement plan. Called from `swarm_down` after the confirmation gate and BEFORE the pane-close loop — so it runs in every teardown path that closes panes, `--keep-workspace` included.
2. **Non-fatal but loud**: any snapshot failure prints a stderr warning (`swarm_down: snapshot: …`), fires the HERDR-5 seam (`herdr notification show … || true`, same mechanism as `_standby_notify`) on total failure, and teardown proceeds; the confirmation gate is untouched.
3. **Degradation**: absent ledgers copy nothing and warn (`reviews.json absent — not captured`); an unreadable seat yields no transcript file plus a warning — never a failed teardown.
4. **Tests**: `tests/test_worktree.sh` §9b (21 assertions, stubbed `herdr`, ambient `HERDR_PANE_ID`/`HERDR_WORKSPACE_ID` scrubbed — an ambient workspace id would resolve the REAL workspace through the stub and stale-mark the ledger): rc-0 teardown with snapshot; all four members copied verbatim; a 5001-line scrollback bounded to exactly 400 lines keeping the newest marker and dropping the oldest; the stub's `pane close` proves the snapshot existed BEFORE each close; absent `reviews.json` degrades with a warning; a blocker file (snapshots path unusable) fails loudly without aborting — panes still close; `--keep-workspace` snapshots too and skips `workspace close`. Suite 70/70.
5. **Verification**: `bash tests/test_worktree.sh` 70/70; `make check` green (21 suites); `make lint` 0 warnings.
