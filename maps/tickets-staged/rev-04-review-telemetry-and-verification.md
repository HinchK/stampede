---
id: REV-4
title: "Review telemetry events, rich status review dashboard, and end-to-end verification"
type: wayfinder:task
status: staged
assignee: arch
owns: lib/telemetry.py,lib/cli/stampede-status.sh,tests/test_telemetry.sh,tests/test_cli_status.sh
parent: maps/autonomous-reviewer-loop.md
blocked_by: [REV-3]
---

# REV-4 — Review telemetry, rich status aggregation, and end-to-end verification (Wave 4)

## 1. Intended Outcome

1. Add review domain events to `lib/telemetry.py`:
   - `review.dispatched {ticket, sha, round}`
   - `review.verdict {ticket, sha, verdict: "PASS"|"BLOCK", round, findings_count}`
   - `review.critique {ticket, sha, round, recipient}`
2. Update `lib/cli/stampede-status.sh` (`stampede status --rich`):
   - Include review loop metrics: total reviews, pass count, block count, re-review iterations.
   - Surface review status in `--json` and human ANSI tables.
3. Validate end-to-end behavior across all suites in `make check`.

## 2. Problem

Trust tax telemetry (PUB-10) and the rich status dashboard (PUB-11) track gate runs and arbiter integrations, but currently have zero visibility into reviewer cycles or critique costs. Operators need measured numbers on how often cross-provider reviews catch flaws and how many cycles are consumed.

## 3. Plan

- `lib/telemetry.py`: Define review event types and emission helpers.
- `lib/cli/stampede-status.sh`: Aggregate review telemetry from `.herdr-swarm/traces/` into status report.
- `tests/test_telemetry.sh`: Test review event envelope and parsing.
- `tests/test_cli_status.sh`: Assert review metrics render in table and `--json`.

## 4. Explicit Done-Criteria

- Review events log cleanly into traces with valid schema and string ticket ids.
- `bin/stampede status --rich --json` exposes `.reviews` rollup.
- `make check` 100% green with 0 shellcheck warnings.

## 5. Verification Step

```bash
bin/stampede status --rich --json | jq -e '.reviews'
make check
```
