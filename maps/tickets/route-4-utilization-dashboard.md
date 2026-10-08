---
id: ROUTE-4
title: "Seat-utilization activity panel in stampede status --rich"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/cli/stampede-status.sh, tests/test_cli_status.sh
parent: maps/herdr-native-and-seat-utilization.md
---

# ROUTE-4 -- make seat utilization a number, not a retrospective surprise

## Intended Outcome

`stampede status --rich` gains a **Seat Activity** panel: per seat, dispatch count
over a trailing window (from `.herdr-swarm/traces/` telemetry events) and commit share
over the same window (from `git shortlog -s -n --since=<window>` mapped to seats),
rendered beside the existing session dashboard.

## Background

Epic charter 2026-10-07. The retrospective's agy-gh-underuse finding was discovered by
hand-transcript analysis a week late. The epic's routing rebalance (ROUTE-1..3) is
unfalsifiable without a standing read-out; this ticket is the epic's measurement leg
and its own success metric.

## Done-Criteria

1. Panel sources: dispatch counts from trace events (event kinds the telemetry schema
   already emits — `dispatch`/worker-feedback class; degrade to "n/a" when traces are
   absent, never fabricate zeros), commit share from git shortlog over
   `--since` window (default 7 days; overridable via `--window <days>` flag on the
   status subcommand).
2. Seat↔author mapping reads the seat roster from the target's `.herdr-swarm/seats.json`
   plus co-author/trailer conventions this repo already uses; unmapped authors
   aggregate under `other` (honest bucket, no guessing).
3. Read-only: no writes to any swarm state; works on a quiet herd (all zeros is a
   valid, displayable answer).
4. Herdr-absent safety unchanged (`status` must not require a live Herdr session).
5. Tests extend `tests/test_cli_status.sh` with a scratch repo + seeded traces/commits:
   counts correct, `other` bucket, `--window` honored, traces-absent degradation.

## Verification Step

`make check` green. Receipt: run against this repo's real `.herdr-swarm/` and paste
the panel — the retrospective's claims (agy-gh idle, looper-heavy bookkeeping share)
should be visible in the numbers.

## Notes

This is the epic's gauge, not a behavior change: no alerts, no thresholds, no
auto-anything. If the panel exposes telemetry gaps (missing event kinds for dispatch
counting), record the gap in the ticket rather than widening the schema silently.

## Resolution (2026-10-07)

Resolved in commit `6a19bd10199259f4581269dbaa035f29867d97a4` (`6a19bd1`).
Implemented `Seat Activity` panel in `stampede status --rich` (`lib/cli/stampede-status.sh`), aggregating dispatch counts from `lease.acquired` traces, calculating commit shares via git integration records and trailer parsing over `--window <days>` (default 7), honest `other` author aggregation, and graceful `n/a` degradation when traces are absent. Covered by 99 unit assertions in `tests/test_cli_status.sh`. Integrated at `c2752ec`.
