---
id: PUB-11
title: "stampede status --rich: session trust dashboard from traces"
type: wayfinder:task
status: ready
assignee: arch
owns: lib/cli/stampede-status.sh,tests/test_cli_status.sh
parent: maps/public-multi-provider.md
blocked_by: PUB-10
---

# PUB-11 — Rich status: the session at a glance (Wave 12, runs alone)

## 1. Intended Outcome

`stampede status --rich` reads `.herdr-swarm/traces/`,
`session-verdicts.jsonl`, and the arbiter queue, and prints a read-only
session summary: tickets by verdict (green/red/skipped), gate runs and
durations, integrations enqueued/promoted, per-seat (and per-provider)
activity, and the re-verdict ratio — the trust tax and the trust dividend
on one screen.

## 2. Problem

State lives in five places (ledger, verdicts JSONL, gates dir, arbiter
queue, traces). The Ops pane streams events live, but there is no way to
ask "what has this session actually accomplished, and what did
verification cost?" — the exact question a multi-provider user asks when
deciding which vendor to keep paying.

## 3. Plan

- `lib/cli/stampede-status.sh`: pure aggregation over the PUB-10 schema
  fields plus existing JSONL; no new emit points, no writes, no network.
- Output: one ANSI table for humans; `--json` for scripting.
- Missing artifacts (fresh clone, no session yet) → friendly empty state
  with pointers to the user guide, exit `0` (empty is not an error).
- `tests/test_cli_status.sh`: seed a scratch `.herdr-swarm/` with fixture
  traces/verdicts/queue, assert deterministic table and JSON shapes.

## 4. Explicit Done-Criteria

- Every number on screen is traceable to a trace/verdict record (M3) —
  the table names its sources in `--json` mode.
- Re-verdict ratio computed from verdicts JSONL `(ticket, sha)` history,
  not from memory.
- 0 shellcheck warnings; read-only (asserted: no `.herdr-swarm/` file
  mtimes change across a run in tests).

## 5. Verification Step

```bash
bin/stampede status --rich --json | jq -e '.tickets'
make check
```
