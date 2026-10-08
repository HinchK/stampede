---
id: SNAP-1
title: "Snapshot before down: capture conversation and verdict state at teardown"
type: wayfinder:task
status: backlog
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
