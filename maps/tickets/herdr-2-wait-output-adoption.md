---
id: HERDR-2
title: "Adopt herdr pane wait-output for single-target waits (seat-verify, quota probe)"
type: wayfinder:task
status: backlog
assignee: arch
owns: herdr-loop-swarm.sh, lib/quota.sh, tests/test_quota.sh, tests/test_cli.sh
parent: maps/herdr-native-and-seat-utilization.md
blocked_by: [HERDR-1]
---

# HERDR-2 -- block, don't poll, on single-target output waits

## Intended Outcome

Call sites whose purpose is "wait until this pane shows X" block on
`herdr pane wait-output <pane_id> --regex <pattern> --timeout <ms>` instead of
poll-read-recheck loops, with a capability probe (`herdr pane wait-output --help`)
that fails soft to today's behavior.

## Background

ADR 0017 Decision 1. Two seams are in scope (the audit may add none without a new
ticket):

1. **Seat-verify wait** (`herdr-loop-swarm.sh`, post-seating verification and the
   auto-queue critical-seat check): today a 2s `agent wait --until ...` poll per
   critical seat. Where the wait is really "seat shows brief-ack output", a
   `wait-output` on the seat pane tightens the signal.
2. **Quota probe block** (`lib/quota.sh` `quota_probe_kind`): the probe reads
   `agent read` once (fine); but any *supervisor/looper* usage that loops the probe
   while a quota banner is pending should block on
   `--regex 'Individual quota reached.*Resets in'` with the existing timeout budget.

Explicitly **out of scope**: the supervisor multi-anchor harvest scan
(`harvest_verdicts`) stays `agent read` + anchored grep (ADR 0017 keep verdict).

## Done-Criteria

1. A shared probe helper (e.g. in `lib/common.sh` or a sibling) detects wait-output
   support once per process and logs one degradation line when absent.
2. Each in-scope seam uses wait-output when probed available, preserving exact current
   semantics when not (same timeouts, same "unknown never fabricated" contract).
3. Standing-brief instruction added is NOT this ticket (briefs are ROUTE-2's owns).
4. Tests: unit coverage of the probe + fallback branching with a stubbed `herdr`
   (existing suites stub herdr the same way); at least one assertion per seam that the
   wait-output path parses `--timeout`/regex args correctly and the fallback path is
   byte-equivalent to current behavior.

## Verification Step

`make check` green. Receipt in the ticket close-out: the probe+fallback branch table
and the stubbed-herdr test names that exercise each branch.

## Notes

Do not widen `--lines` assumptions here unless HERDR-1's alternate-screen assessment
says a seam reads anchored lines beyond 80 rows — then fix that seam with an explicit
`--lines` and cite the audit row.
