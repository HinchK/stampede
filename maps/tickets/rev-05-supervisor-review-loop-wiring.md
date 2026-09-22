---
id: REV-5
title: "Supervisor review loop wiring, verdict harvesting, and telemetry"
type: wayfinder:task
status: resolved
assignee: arch
owns: loop-bot-herd.sh,tests/test_async_gate.sh
parent: maps/autonomous-reviewer-loop.md
blocked_by: [REV-3, REV-4]
resolution:
  commit: debd73e
  promoted_at: 2026-09-22
  verification: "make check green (16 suites, 428 passed, 0 failed; tests/test_async_gate.sh 33/33; shellcheck 0 warnings); PM sign-off"
---

# REV-5 — Supervisor review loop wiring, verdict harvesting, and telemetry (Wave 5)

## 1. Intended Outcome

1. **Source and Terminal Safety in `loop-bot-herd.sh`**:
   - Source `"$SCRIPT_DIR/lib/lifecycle.sh"` so supervisor has access to review loop state machine functions (`review_loop_on_gate_green`, `review_loop_on_review_verdict`, etc.).
   - Guard `tput` calls around line 105 (`DIM=$(tput dim 2>/dev/null || true)`, `RESET=$(tput sgr0 2>/dev/null || true)`, etc.) to prevent `set -e` failure in non-interactive/dumb terminals.
2. **String Ticket ID Harvesting in `loop-bot-herd.sh`**:
   - Update `ARCH DONE` regex in `harvest_verdicts` to harvest alphanumeric ticket IDs (e.g. `([A-Za-z0-9_.-]+)` or `([0-9]+|[A-Za-z0-9_-]+)`) matching the string ticket schema throughout the pipeline (`#ARB-STR`).
3. **Review Loop Directives Execution on Suite Green (`gate_reap`)**:
   - When a suite gate passes (`rc_val == 0`):
     - If `$iso == true`: call `review_loop_on_gate_green "$ticket" "$seat" "$sha" "$STATE_DIR"`.
     - Execute directives printed on stdout:
       - `ENQUEUE <ticket> <seat> <sha>`: call `arbiter_enqueue "$ticket" "$seat" "$sha"` (reproduces existing behavior when `CONFIG_REVIEW_LOOP=0`).
       - `DISPATCH_REVIEWER <seat> <ticket> <sha> <round> <max>`:
         - Resolve reviewer seat name (`${SEAT_NAME_reviewer:-reviewer}`).
         - Prompt reviewer seat via `herdr agent prompt`: `"DISPATCH: Review #<ticket> @ <sha> (round <round>/<max>). Follow your seat brief."`
         - Log `review.dispatched` telemetry via `telemetry.py` with `{ticket, sha, round}`.
4. **Reviewer Verdict Harvesting in `harvest_verdicts`**:
   - In `harvest_verdicts`, scan the reviewer seat (`${SEAT_NAME_reviewer:-reviewer}`) output for `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>` anchors:
     - Regex: `^REVIEW VERDICT #[A-Za-z0-9_.-]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]+(PASS|BLOCK)`
     - Call `review_loop_on_review_verdict "$ticket" "$sha" "$verdict" "$STATE_DIR"`.
     - Log `review.verdict` telemetry via `telemetry.py` with `{ticket, sha, verdict, round, findings_count}`.
     - Act on returned machine directives:
       - `ENQUEUE <ticket> <seat> <sha>`: call `arbiter_enqueue "$ticket" "$seat" "$sha"`.
       - `DISPATCH_CRITIQUE <seat> <ticket> <round> <max> <path>`:
         - Prompt implementer seat (`$seat`): `"DISPATCH CRITIQUE: #<ticket> round <round>/<max> — see <path>"`.
         - Log `review.critique` telemetry via `telemetry.py` with `{ticket, sha, round, recipient: seat}`.
       - `ALERT_BLOCKED <ticket> <sha> <round> <max>`:
         - Prompt looper / alert driver: `"LOOP-BOT: review for #<ticket> @ <sha> BLOCKED after <max> rounds — human review required."`. Do NOT enqueue.
       - `ALERT_INVALID <ticket> <reason>`:
         - Prompt looper / alert driver with invalid state warning.
5. **Hermetic Unit Tests in `tests/test_async_gate.sh`**:
   - Validate supervisor integration with review loop:
     - `CONFIG_REVIEW_LOOP=0`: green gate immediately enqueues (existing tests pass).
     - `CONFIG_REVIEW_LOOP=1`: green gate dispatches reviewer, harvests `REVIEW VERDICT PASS` to enqueue, or `REVIEW VERDICT BLOCK` to critique dispatch.
     - Terminal `tput` safe invocation under non-interactive env.

## 2. Problem

`REV-3` and `REV-4` implemented the review loop state machine and rich status aggregation, but the supervisor daemon (`loop-bot-herd.sh`) was outside their declared owns. The supervisor still directly enqueues to Arbiter on gate green and ignores reviewer emissions. Wiring the supervisor closes the loop so the swarm operates autonomously.

## 3. Plan

- `loop-bot-herd.sh`: Source `lib/lifecycle.sh`, guard `tput`, wire `gate_reap` green path to `review_loop_on_gate_green`, harvest reviewer verdicts in `harvest_verdicts`, execute directive actions, and log telemetry events.
- `tests/test_async_gate.sh`: Add assertions covering review loop dispatch, verdict harvesting, and telemetry logging in the supervisor.

## 4. Explicit Done-Criteria

- `loop-bot-herd.sh` executes directives (`ENQUEUE`, `DISPATCH_REVIEWER`, `DISPATCH_CRITIQUE`, `ALERT_BLOCKED`, `ALERT_INVALID`) cleanly.
- `tests/test_async_gate.sh` passes all existing and new assertions.
- 0 shellcheck warnings.
- `make check` 100% green across all 16 suites.

## 5. Verification Step

```bash
bash tests/test_async_gate.sh
make check
```
