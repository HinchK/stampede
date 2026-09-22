---
id: REV-3
title: "Looper autonomous review loop state machine and fail-closed gate"
type: wayfinder:task
status: staged
assignee: arch
owns: lib/lifecycle.sh,herdr-loop-swarm.sh,tests/test_review_loop.sh
parent: maps/autonomous-reviewer-loop.md
blocked_by: [REV-1, REV-2]
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
