---
id: REV-4
title: "Review telemetry events, rich status review dashboard, and end-to-end verification"
type: wayfinder:task
status: resolved
assignee: arch-1
owns: lib/lifecycle.sh,lib/telemetry.py,lib/cli/stampede-status.sh,tests/test_review_loop.sh,tests/test_telemetry.sh,tests/test_cli_status.sh
parent: maps/autonomous-reviewer-loop.md
blocked_by: [REV-3]
---

# REV-4 — Review telemetry, rich status aggregation, and end-to-end verification (Wave 4)

## 1. Intended Outcome

1. **Fast-Follow Contract Alignment (`lib/lifecycle.sh:199`)**:
   - Change `printf 'ALERT_INVALID %s no-review-state\n' "$ticket" >&2` to stdout (`printf 'ALERT_INVALID %s no-review-state\n' "$ticket"`) so all machine directives consistently flow through stdout per the documented contract.
   - Add assertion in `tests/test_review_loop.sh` asserting the file-absent branch emits `ALERT_INVALID` on stdout and returns exit code 1.
2. **Review Domain Events in `lib/telemetry.py`**:
   - `review.dispatched {ticket, sha, round}`
   - `review.verdict {ticket, sha, verdict: "PASS"|"BLOCK", round, findings_count}`
   - `review.critique {ticket, sha, round, recipient}`
3. **Rich Status Review Dashboard (`lib/cli/stampede-status.sh`)**:
   - Include review loop metrics in `stampede status --rich`: total reviews, pass count, block count, re-review iterations.
   - Surface review metrics in `--json` output (`.reviews` object) and ANSI formatted table.
4. **End-to-End Verification**:
   - Unit tests in `tests/test_telemetry.sh` and `tests/test_cli_status.sh`.
   - `make check` 100% green across all 16 suites.

## 2. Problem

Trust tax telemetry (PUB-10) and the rich status dashboard (PUB-11) track gate runs and arbiter integrations, but currently have zero visibility into reviewer cycles or critique costs. Operators need measured numbers on how often cross-provider reviews catch flaws and how many cycles are consumed. Additionally, line 199 in `lib/lifecycle.sh` violates the stdout directive contract by printing to stderr, which would silently lose the invalid-state alert when consumed by callers.

## 3. Plan

- `lib/lifecycle.sh`: Fix line 199 to emit to stdout.
- `tests/test_review_loop.sh`: Assert missing-state-file path outputs `ALERT_INVALID` on stdout with rc 1.
- `lib/telemetry.py`: Define review event types and emission helpers.
- `lib/cli/stampede-status.sh`: Aggregate review telemetry from `.herdr-swarm/traces/` into status report.
- `tests/test_telemetry.sh`: Test review event envelope and parsing.
- `tests/test_cli_status.sh`: Assert review metrics render in table and `--json`.

## 4. Explicit Done-Criteria

- Line 199 in `lib/lifecycle.sh` emits `ALERT_INVALID` to stdout and is verified by test.
- Review events log cleanly into traces with valid schema and string ticket ids.
- `bin/stampede status --rich --json` exposes `.reviews` rollup.
- `make check` 100% green with 0 shellcheck warnings across all touched files.

## 5. Verification Step

```bash
bash tests/test_review_loop.sh
bin/stampede status --rich --json | jq -e '.reviews'
make check
```

## 6. Resolution (2026-09-22, `950e264`)

- **`lib/lifecycle.sh`**: Resolved PM finding from REV-3 by ensuring `review_loop_on_review_verdict()` prints `ALERT_INVALID <ticket> no-review-state` to stdout (removed `>&2`) so all machine directives consistently flow through stdout per line 15 contract.
- **`lib/telemetry.py`**: Added review domain badges: `REVIEW:✓` / `REVIEW:✗` from explicit `payload.verdict` (`PASS|BLOCK`), plain `REVIEW` for dispatched/critique events. Checked before generic branches.
- **`lib/cli/stampede-status.sh`**: Added `.reviews` rollup to `stampede status --rich --json` aggregating `total`, `passes`, `blocks`, `rerounds`, `findings_total`, and per-ticket detail. Rendered review line in ANSI human table (conditionally displayed only when review events exist).
- **`tests/`**:
  - `tests/test_review_loop.sh`: Added test 6b asserting missing-state-file path outputs `ALERT_INVALID` on stdout with rc 1 and no state file created (+3 assertions, 43 total).
  - `tests/test_telemetry.sh`: Added assertions for review domain events, payload pass-through, and badge rendering (+6 assertions, 13 total).
  - `tests/test_cli_status.sh`: Added fixture test simulating review lifecycle and verifying `.reviews` JSON structure and human summary table (+5 assertions, 32 total).
- **Verification**: `bin/stampede status --rich --json | jq -e '.reviews'` succeeds; `make check` 16/16 suites green, 412 assertions passed, 0 failed; 0 shellcheck warnings across 22 shell files.

