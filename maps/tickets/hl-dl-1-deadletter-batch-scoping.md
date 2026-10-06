---
id: HL-DL-1
title: "Per-batch scoping for headless dead-letter count"
type: wayfinder:defect
status: resolved
assignee: arch-2-hinchk-stampede
owns: lib/headless.sh,lib/cli/stampede-headless.sh,tests/test_headless.sh
parent: maps/headless-live.md
blocked_by: [HORIZON-3]
---

# HL-DL-1 — per-batch scoping for headless dead-letter count

## Intended Outcome

Per-batch scoping for headless dead-letter counting (`headless_deadletter_count`),
ensuring historical dead-letter entries recorded under the project's stable telemetry
session ID do not cause subsequent all-green headless batch runs on the same repository
to exit 1.

## Problem Context

Discovered during HORIZON-2 live proof on the live stampede repository
([`docs/findings/headless-live-proof.md`](docs/findings/headless-live-proof.md)):
`dead-letter.jsonl` counting (`headless_deadletter_count` in `lib/headless.sh`,
invoked in `lib/cli/stampede-headless.sh`) filters records by the telemetry session ID
(`$SESSION_ID`). In persistent repositories, `$SESSION_ID` is stable across multiple
invocations (`swarm-20260919-114508`). When a repository has any historical dead-letter
record in `.herdr-swarm/dead-letter.jsonl`, subsequent runs of `bin/stampede headless`
count those historical records and exit with return code 1, even if every ticket in
the current batch succeeded and concluded green.
Scratch test repositories with fresh state directories never encountered this, but
any long-lived repository does.

## Done-Criteria

1. `headless_deadletter_count` or the batch dead-letter checking mechanism scopes
   evaluations strictly to the active batch run (e.g., via a unique run/batch session id,
   a per-run since-marker / timestamp / line offset, or run-specific metadata).
2. Existing dead letters from prior runs in `dead-letter.jsonl` do not cause a later,
   all-green headless batch to exit 1.
3. If the current batch itself encounters a dead letter, `bin/stampede headless` and
   `headless deadletter-check` still detect it and exit 1 (preserving Hazard 3 unattended
   safety invariant).
4. Unit and CLI tests in `tests/test_headless.sh` and `tests/test_cli.sh` verify both:
   - Prior-run dead letters are ignored by new batches.
   - Current-batch dead letters trigger non-zero exit and reporting.
5. `make check` passes cleanly (all suites green, 0 shellcheck warnings).

## Verification Step

Run `tests/test_headless.sh` and `tests/test_cli.sh` (or `make check`) verifying
that historical dead-letter records do not fail subsequent green batches while new
dead-letter records fail as expected.

## Resolution

Resolved at commit `c1f8f1b15af6fdb26cbfb8c2fbe2fd5e730c8f30`.
- `headless_deadletter_count` in `lib/headless.sh` upgraded with an optional `SINCE_INDEX` parameter (default 0), slicing the append-only JSONL file past the baseline count.
- `stampede headless` in `lib/cli/stampede-headless.sh` records baseline record count before dispatch and evaluates exit status against it, preserving Hazard 3 while ignoring historical records.
- Comprehensive bidirectional tests in `tests/test_headless.sh` (8j-8j4) and `tests/test_cli.sh` ([15]).
- Autonomous review PASS verdict by `reviewer-hinchk-stampede` (Round 1/2) in `.herdr-swarm/reviews/HL-DL-1-c1f8f1b15af6fdb26cbfb8c2fbe2fd5e730c8f30.md`.
- Integrated onto `swarm/stampede/integration` via `arbiter_enqueue_and_drain` and merged to `main`. Lease released cleanly.
