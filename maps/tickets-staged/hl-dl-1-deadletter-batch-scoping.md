---
id: HL-DL-1
title: "Per-batch scoping for headless dead-letter count"
type: wayfinder:defect
status: backlog
assignee: arch
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
