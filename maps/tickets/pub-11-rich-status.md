---
id: PUB-11
title: "stampede status --rich: session trust dashboard from traces"
type: wayfinder:task
status: resolved
assignee: arch-2
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

## 6. Resolution (2026-09-22, `cf5f7b1`)

- `lib/cli/stampede-status.sh`: one JSON object is the single source of truth; the human ANSI table renders FROM it, so `--json` and the table cannot disagree. Tickets by verdict = latest record per ticket in session-verdicts.jsonl (green/red/skipped/other); gate durations come only from trace `suite.verdict` events carrying the flat-key `gate.duration_ms` (PUB-10 absence semantics: never averaged over missing); integrations count by arbiter queue status; re-verdict ratio = (records − distinct tickets) / records from the verdicts history; per-seat rows carry the seat's configured kind chain, rolled up per primary provider via the PUB-2 registry (degrading to `-` without an interpreter). Torn JSONL lines drop via `fromjson?`; fresh clones get a friendly empty state naming `docs/user-guide.md` with exit 0; `--json` names every source path (null when absent).
- Routing seam (disclosed, one case arm in `bin/stampede`): `status --rich|--json|-h` routes to the module when present; plain `status [dir]` still delegates to the launcher verbatim (PUB-1 pass-through unchanged). The ticket's verification step cannot reach the module without it — flagged in the commit for review against this ticket's owns list.
- `tests/test_cli_status.sh`: 27 hermetic assertions — fixture-seeded scratch `.herdr-swarm`, JSON/table shapes, latest-record-wins, re-verdict ratio 0.4 computed from history, duration absence semantics, provider rollup, source naming, ANSI-free piped output, torn-line resilience, a file-mtime snapshot proving read-only behaviour (no `.herdr-swarm/` change across runs), empty state, and delegation-seam fallback.
- Receipts: `bin/stampede status --rich --json | jq -e '.tickets'` passes against both a fresh clone and the live target repo (16 enqueued / 14 promoted / 1 conflict / 1 red rendered from the real arbiter queue); `shellcheck lib/cli/stampede-status.sh bin/stampede` 0 warnings; `make check` fully green — all 15 suites, 348 assertions, 0 failed, lint clean across 22 shell files.
