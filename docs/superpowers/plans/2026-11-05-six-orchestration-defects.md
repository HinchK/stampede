# Six Orchestration Defects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Repair the six reproduced defects without changing Stampede's supported workflows.

**Architecture:** Keep the supervisor and arbiter, sharing existing checks and role interpretation. Protect queue mutations independently of long-running integration tests. Validate review senders against a durable assignment.

**Tech Stack:** Bash 3.2, Python with tomllib, Git, jq; existing dependencies only.

**Spec:** `docs/superpowers/specs/2026-11-05-six-orchestration-defects-design.md`

## Global Constraints

- Keep Bash 3.2, the existing Python runtime, current CLI commands, JSON state, and manual human promotion.
- All tests use scratch repositories and stubbed model/Herdr interfaces.
- Preserve descriptive role labels, provider/model pins, custom seats, and gate_concurrency = 0.
- Implement in the current dedicated `codex/fix-six-orchestration-defects` checkout; no live swarm or remote Git mutation.

## Review Focus

- Quota failover names the implementer: defer without granting self-review.
- An enqueue supersedes a candidate during its integration test: never mark the new row integrated for the old commit.
- Queue parse/write failures: preserve original bytes and release writer ownership.
- Legacy descriptive/renamed architect plus a custom neighboring seat: select only the architect.
- Duplicate completion or unauthorized review scrollback: no duplicate enqueue or damage to a legitimate pending review.

### Task 1: Queue serialization and JSONL (defects 2 and 4)

**Files:** `lib/arbiter.sh`, `tests/test_arbiter.sh`, new hermetic `tests/test_queue_writes.sh` if fixture isolation is simpler.

**Interfaces:** Preserve `arbiter_enqueue`, `_arb_record`, `_arb_set_status` and CLI entry points. Introduce `_arb_queue_write OP ARGS...` as the one locked writer; internal operations cover append, enqueue, status, promotion and integration finalization. Keep the existing drain lock separate.

- [ ] Add failing tests for line-by-line queue readers after status replacement, deterministic enqueue/rewrite overlap, concurrent duplicate enqueue, supersession during a drain, enqueue while a gate waits, malformed input, and writer cleanup.
- [ ] Run the queue regressions and observe the reproduced failures.
- [ ] Implement short portable writer locking with unique temporary files, compact JSON, original-data preservation, candidate revalidation before CAS, and all promotion writes participating. Preserve the existing `_arb_integrate` CAS expression for seeded-regression compatibility.
- [ ] Run `/bin/bash tests/test_queue_writes.sh` and `/bin/bash tests/test_arbiter.sh`; expect zero failures.
- [ ] Commit the queue repair and regression tests.

### Task 2: Integration tree consistency (defect 3)

**Files:** `lib/common.sh`, `lib/arbiter.sh`, `loop-bot-herd.sh`, `tests/test_arbiter.sh` or a focused `tests/test_integration_drift.sh`.

**Interfaces:** Move `gate_tree_matches DIR SHA` to `lib/common.sh`; all callers require successful Git inspection, matching canonical HEAD, and clean tracked/untracked files. Use `integration_red` plus `gate.reason` for drift.

- [ ] Add failing tests for a passing suite modifying tracked files, creating untracked files, moving HEAD, and a normal clean run; assert ref/queue/verdict effects.
- [ ] Run the focused suite; observe drift being accepted before the repair.
- [ ] Use the shared check before/after the arbiter suite; drift keeps the integration ref unchanged and creates no GREEN receipt.
- [ ] Run the drift and arbiter suites; expect zero failures.
- [ ] Commit the shared check and integration repair.

### Task 3: Role compatibility (defect 5)

**Files:** `lib/roles.py` (extract existing resolver), `lib/setup.py`, `lib/attention.py`, `Makefile`, `tests/test_attention.py`, relevant setup fixtures.

**Interfaces:** `seat_roles(seats: dict) -> dict[str, str]` keeps the existing setup behavior. Both setup and attention consume it; existing setup exports remain available.

- [ ] Add a failing setup-render-to-attention regression using the shipped config, plus descriptive standard-key, renamed, and neighboring custom-seat cases. Preserve role labels and model/provider values.
- [ ] Run `/bin/bash tests/test_attention.sh`; observe empty candidate selection.
- [ ] Extract the existing resolver and use it in both consumers; include the shared module in Python compilation and test import paths.
- [ ] Run `/bin/bash tests/test_attention.sh` and `/bin/bash tests/test_setup.sh`; expect zero failures.
- [ ] Commit role compatibility.

### Task 4: Independent review authorization (defect 1)

**Files:** `lib/lifecycle.sh`, `loop-bot-herd.sh`, `tests/test_review_loop.sh`, `tests/test_async_gate.sh`, reviewer protocol notes.

**Interfaces:** Add `review_loop_assign_reviewer TICKET SHA ROUND REVIEWER [STATE_DIR]`; extend `review_loop_on_review_verdict TICKET SHA VERDICT STATE_DIR REVIEWER` to require the sender. Assignment records current round and SHA before prompting. Reject sender mismatch without mutating the legitimate review.

- [ ] Add failing worker/other-seat PASS tests, missing-assignment tests, independent primary/failover success, self-failover deferral and retry, duplicate anchors, and terminal/critique PASS rejection.
- [ ] Run the state and supervisor suites and observe unauthorized review acceptance.
- [ ] Persist assignment before all primary/failover/deferred dispatches; require the assigned independent sender and pending review for PASS. Pass sender identity through the scanner before marking an anchor seen. Keep canonical-SHA failures fail closed and preserve duplicate BLOCK semantics.
- [ ] Update direct state-machine test callers to establish assignments explicitly; test stale SHA and repeat completions.
- [ ] Run `/bin/bash tests/test_review_loop.sh` and `/bin/bash tests/test_async_gate.sh`; expect zero failures.
- [ ] Commit review authorization and protocol changes.

### Task 5: Shared GREEN continuation (defect 6)

**Files:** `loop-bot-herd.sh`, `tests/test_async_gate.sh`, `docs/user-guide.md`.

**Interfaces:** `_gate_green_continue TICKET SEAT SHA ISOLATED` contains the existing isolated-seat state-machine/directive path; asynchronous and inline gates call it after tree validation.

- [ ] Extend inline tests to assert loop-off enqueue and loop-on review, then PASS enqueue; include docs fast path, duplicate completion, state failure and root-seat preservation.
- [ ] Run the supervisor suite and observe missing inline continuation.
- [ ] Extract and call the helper from both gate modes; document identical review/integration policy.
- [ ] Run `/bin/bash tests/test_async_gate.sh`; expect zero failures.
- [ ] Commit inline parity.

### Task 6: Final verification and independent review

**Files:** relevant current protocol docs and this plan's progress ledger.

**Interfaces:** Existing `make check` remains the final gate.

- [ ] Run `make check`; expect clean lint and every shell/Python suite passing.
- [ ] Have one fresh reviewer inspect the whole change against the approved design and Review Focus. Resolve important findings with failing regressions before fixes.
- [ ] Re-run checks warranted by review changes; record actual checks, limitations and any unresolved findings.
- [ ] Commit remaining current-documentation/plan updates and finish the branch locally, ready for review.
