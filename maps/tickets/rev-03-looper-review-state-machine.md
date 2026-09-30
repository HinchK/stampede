---
id: REV-3
title: "Looper autonomous review loop state machine and fail-closed gate"
type: wayfinder:task
status: resolved
assignee: arch-1
owns: lib/lifecycle.sh,herdr-loop-swarm.sh,tests/test_review_loop.sh
parent: maps/autonomous-reviewer-loop.md
blocked_by: [REV-1, REV-2]
github_issue: 104
github_url: "https://github.com/HinchK/stampede/issues/104"
synced_at: "2026-09-30T17:16:14Z"
---

# REV-3 — Looper autonomous review loop state machine and fail-closed gate (Wave 3)

## 1. Intended Outcome

1. Implement the autonomous review loop state machine in `looper` / orchestration layer:
   - When `arch` emits `ARCH DONE #<ticket> <sha>` and the Suite Gate (`make test`) passes:
     - If `CONFIG_REVIEW_LOOP == 0`: immediately proceed to Arbiter enqueue (existing behavior).
     - If `CONFIG_REVIEW_LOOP == 1`: transition ticket to `awaiting_review` and dispatch `reviewer` on `<sha>`.
   - When `reviewer` reports:
     - On `PASS`: enqueue `<sha>` to Arbiter.
     - On `BLOCK` and `round < CONFIG_REVIEW_MAX_ROUNDS`: transition to `critique_dispatched`, prompt `arch` with critique path, increment round count.
     - On `BLOCK` and `round >= CONFIG_REVIEW_MAX_ROUNDS`: transition to `review_blocked`, halt integration, alert human driver. Do NOT enqueue to Arbiter.
2. Support dynamic CLI flag: `stampede up --no-review-loop` or `stampede status` indicating review loop state.

## 2. Problem

Without orchestrator state tracking, the review process requires manual human coordination to read reviewer outputs and re-dispatch workers. The state machine automates the handshake between `arch`, `supervisor`, and `reviewer`.

## 3. Plan

- `lib/lifecycle.sh` / `herdr-loop-swarm.sh`: Add review round tracking and dispatch transition logic.
- Fail-closed guardrail: ensure exhausted review blocks never touch the arbiter integration queue.
- `tests/test_review_loop.sh`: Hermetic state machine unit tests simulating pass, single-round fix, and multi-round block scenarios.

## 4. Explicit Done-Criteria

- Full state transition logic verified across all outcome branches (direct pass, 1-round fix pass, 2-round fail-closed block).
- Arbiter enqueue is blocked upon exhausted review failure.
- 0 shellcheck warnings.

## 5. Verification Step

```bash
bash tests/test_review_loop.sh
make check
```

## 6. Resolution (2026-09-22, `ed86598`)

- **`lib/lifecycle.sh`**: Implemented review loop state machine with durable storage in `.herdr-swarm/reviews.json` (atomic writes, fail-closed on corrupt state). Defined directive contract: `ENQUEUE`, `DISPATCH_REVIEWER`, `DISPATCH_CRITIQUE`, `ALERT_BLOCKED`, `ALERT_INVALID`. Pure state transitions: `review_loop_on_gate_green` and `review_loop_on_review_verdict` without shell-out side effects. Bounded round tracking with fail-closed block when rounds reach `CONFIG_REVIEW_MAX_ROUNDS`. Added `review_loop_status` reporting active reviews and override status in `swarm_status`.
- **`herdr-loop-swarm.sh`**: Added `--no-review-loop` CLI flag creating durable runtime override marker `.herdr-swarm/review-loop.override` (survives daemon inspection, cleared on subsequent `up` without flag).
- **`tests/test_review_loop.sh`**: Added 40 hermetic assertions validating all transition paths (direct pass, 1-round fix, max-rounds fail-closed block, override precedence, corrupt/invalid input handling, status formatting, launcher options).
- **Verification**: `tests/test_review_loop.sh` 40/40 passed; `make check` 16/16 suites green, 398 assertions passed, 0 failed; 0 shellcheck warnings across 22 shell files.

