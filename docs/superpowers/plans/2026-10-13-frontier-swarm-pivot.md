# Frontier Swarm Pivot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Status:** Implemented and verified with `make check` (25 suites). The planned task commits were consolidated into one branch change.

**Goal:** Make Stampede's first run build a cost-fitted frontier roster and keep coordination bounded, observable, and under human control.

**Architecture:** Add a project-local setup command and configuration, then make launcher and supervisor consume that configuration. Keep Herdr as the pane/session owner and Stampede as the gate/queue owner. Retain the existing worker gate and isolated worktrees while making arbiter drain an explicit human command.

**Tech Stack:** Bash 3.2, Python `tomllib`, Herdr CLI, AGY CLI, existing shell test harness.

**Spec:** `docs/superpowers/specs/2026-10-13-frontier-swarm-setup-design.md`

## Global Constraints

- AGY is the looper harness; local models are deferred.
- Default attention mode is `medium`; `quiet` and `loud` are selectable.
- No automatic arbiter drain or promotion from setup or interactive startup.
- Existing exact-SHA gate, isolated worktrees, and human-only promotion remain authoritative.
- Target repositories need not contain Stampede briefs.
- Bash 3.2 is the runtime floor; add no dependency.

## Review Focus

- A target path with spaces must appear safely in generated configuration and launcher (Task 1 test).
- An existing configuration or quick launcher must survive unless replacement was explicit, with backup (Task 1 test).
- A model choice must reach the actual Herdr start command, including Claude and AGY (Task 2 test).
- A duplicate verdict event must produce one looper receipt and no repeat model call (Task 3 test).
- An untrusted looper response must never execute shell or drain an arbiter (Task 3 test).

---

### Task 1: Guided project setup

**Files:** Create `lib/cli/stampede-setup.sh`, `tests/test_setup.sh`; modify `lib/config.sh`, `lib/briefs.sh`, `README.md`, `docs/user-guide.md`.

**Interfaces:** `stampede setup <repo> [--non-interactive] [--force] [--launcher path] [--attention quiet|medium|loud]` writes `<repo>/swarm.config.toml`, a chosen `yeehaw.sh`, and project-local state. The setup command probes only `agy`, `claude`, `opencode`, accepts model/provider choices, and validates the TOML through `config_dump_env`.

- [x] Write `tests/test_setup.sh` with temporary Git targets, fake provider binaries, choice prompts, repeat/backup checks, path-with-spaces checks, and setup output assertions.
- [x] Run `bash tests/test_setup.sh`; confirm the missing command fails.
- [x] Implement setup, project config selection, brief rendering from installed templates, and launcher writing; keep existing `stampede init` compatible.
- [x] Run `bash tests/test_setup.sh` and `make lint`; require pass.
- [x] Commit the task's code, tests, and user documentation.

### Task 2: Seated roster and visible state

**Files:** Modify `herdr-loop-swarm.sh`, `lib/briefs.sh`, `lib/lifecycle.sh`; create or extend `tests/test_setup.sh` and launcher lifecycle tests.

**Interfaces:** Launcher reads project configuration when present, uses the selected model for every provider, seats looper as a named non-agent pane, and provides durable Ops worklog/troubleshooting/handoff panes. Project status reports role, provider, model, and attention mode.

- [x] Add a failing stubbed Herdr launch test for the complete default roster, AGY/Claude/OpenCode model arguments, no model process in log panes, and idempotent reattach.
- [x] Run the focused test; confirm the missing behavior fails.
- [x] Implement project config binding, looper shell pane, model arguments, log panes, status display, and safe detach/return/teardown guidance.
- [x] Run focused tests and `make lint`; require pass.
- [x] Commit the task's code and tests.

### Task 3: Attention policy and bounded AGY turns

**Files:** Create `lib/attention.py`, `lib/cli/stampede-attention.sh`, `tests/test_attention.sh`; modify `loop-bot-herd.sh`, `herdr-loop-swarm.sh`.

**Interfaces:** `stampede attention <repo> [quiet|medium|loud]` reads/changes the durable mode. `attention_event <kind> <ticket> <evidence>` deduplicates authoritative events, writes a bounded checkpoint and receipt, and runs one AGY `--print` turn in medium mode. It accepts only a small validated action vocabulary and never executes a model-supplied command string. RED/blocked pause the affected ticket under documented mode rules.

- [x] Add failing tests for all nine mode/event cases, duplicate event, AGY timeout, malformed proposal, one retry ceiling, and ticket-local pause.
- [x] Run `bash tests/test_attention.sh`; confirm the failure reflects missing policy.
- [x] Implement the policy, deterministic readiness checks, fresh AGY invocation, and supervisor event wiring. Preserve existing headless batch behavior where explicitly requested.
- [x] Run focused tests and `make lint`; require pass.
- [x] Commit the task's code and tests.

### Task 4: Manual arbiter and verification

**Files:** Modify `loop-bot-herd.sh`, `lib/arbiter.sh`, `tests/test_arbiter.sh`, `tests/test_async_gate.sh`, `docs/user-guide.md`, `README.md`.

**Interfaces:** Interactive supervisor enqueues a gated verdict and reports `bash <install>/lib/arbiter.sh drain`; it never calls drain automatically. `arbiter enqueue` only enqueues. Explicit `drain` remains the serialized integration path and `promote --confirm` remains human-only.

- [x] Change tests first to require queued-after-green and queued-after-CLI-enqueue, with explicit drain integration.
- [x] Run focused arbiter and supervisor tests; confirm the old auto-drain behavior fails.
- [x] Remove default drain triggers; retain an explicit automation entry point only where the existing headless command explicitly opts in.
- [x] Run `make check`, inspect the final diff, and perform a fresh whole-branch review. Fix findings and rerun the affected gates.
- [x] Commit the final task and report remaining limits with measured evidence.
