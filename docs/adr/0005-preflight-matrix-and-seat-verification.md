# ADR 0005: Preflight Dependency Matrix and Post-Seating Readiness Verification Gate

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`
- **Consulted**: [T-008](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/preflight-dependency-and-daemon-verification.md), [T-010](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/seat-verification-protocol.md), [T-INT-4](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/launcher-preflight-and-subcommands.md)

---

## 1. Context and Problem Statement

A multi-agent swarm operates as an orchestrated distributed system within a terminal multiplexer. In early versions, starting the swarm suffered from two distinct failure modes at opposite ends of the startup sequence:

1. **Blind Startup Failures**: Swarm initialization began creating workspaces, tabs, and panes before validating whether required system dependencies were present. If `jq`, `tomllib`, or `gh` authentication was missing, the script failed midway, leaving orphaned panes, unseated agent shells, and corrupted state.
2. **Kickoff Race Conditions (Post-Seating Desynchronization)**: Spawning an agent process in a pane (`herdr agent start`) is asynchronous. In early versions, kickoff task prompts were dispatched immediately after seating. Because agent runtimes take 3–15 seconds to initialize their models and read their standing briefs, early prompts collided with agent boot routines, resulting in dropped prompts, uninitialized agent roles, or ungrounded responses.

---

## 2. Decision Drivers

- **Zero Orphaned Panes**: Workspace and pane creation must never commence unless all dependencies and credentials are fully verified.
- **Fail-Closed Gatekeeping**: If a critical dependency is missing, the launcher must abort immediately with human-actionable remediation instructions.
- **Boot Synchronization**: Kickoff work dispatches must be blocked until every seated agent has completed booting, loaded its runtime, and acknowledged or settled its standing brief.
- **Observability and Portability**: Verification routines must support human-readable text output, silent exit codes for scripting, and JSON output for automated telemetry.

---

## 3. Considered Options

- **Option A (Inline Ad-Hoc Checks)**: Add scattered `which` checks throughout `herdr-loop-swarm.sh`. (Fragile, lacks structured remediation, and duplicates logic).
- **Option B (Fixed Sleep Delays)**: Insert arbitrary `sleep 10` delays after seating to let agents boot. (Flaky across different machines, models, and network conditions; either wastes time or fails on slow boots).
- **Option C (Two-Stage Verification Gates: Preflight Matrix & Seat Readiness Verification)**: Implement a standalone preflight validation matrix (`lib/preflight.sh`) executed before workspace creation, combined with an active post-seating readiness gate (`swarm_verify_seats` in `lib/lifecycle.sh`) that waits for agents to reach `idle` or `done` states.

---

## 4. Decision

We adopted **Option C**. We established a rigorous two-stage gating architecture:

```
[Start] ──> [Stage 1: Preflight Matrix] ──(Fail: Halt with Remediation)
                     │
                 (Pass: 0)
                     ▼
           [Workspace & Seating]
                     │
                     ▼
            [Stage 2: Seat Verification Gate] ──(Fail: Autonomous Mode Abort)
                     │
                 (Pass: 0)
                     ▼
            [Kickoff Execution]
```

### A. Stage 1: The 9-Point Preflight Dependency Matrix (`lib/preflight.sh`)
Before any workspace creation or pane mutation occurs, `preflight_run` executes a 9-point verification matrix:

1. **Herdr Daemon Liveness**: Verifies the daemon is responsive via `herdr workspace list` (with up to 3 retries and 1s exponential backoff).
2. **`jq` Utility**: Confirms `jq` is installed for JSON parsing and ledger manipulation.
3. **`git` Utility**: Confirms Git is installed.
4. **`python3` & `tomllib`**: Verifies Python 3 is installed and has native `tomllib` support (Python 3.11+) for parsing `swarm.config.toml`.
5. **GitHub CLI (`gh`)**: Confirms `gh` is installed.
6. **GitHub Authentication (`gh auth status`)**: Validates active GitHub authentication to ensure remote operations and issues can be accessed.
7. **Git Repository Worktree**: Verifies the target directory is an initialized Git repository (`git rev-parse --is-inside-work-tree`).
8. **Agent CLI Runtimes**: Inspects availability of configured agent CLIs (`agy`, `claude`, `opencode`).
9. **Test Suite Command**: Validates that the detected test command is runnable via `test_cmd_is_runnable`.

If any mandatory check fails, the preflight engine formats human-actionable remediation hints (e.g. `brew install jq`, `gh auth login`, `pyenv install 3.11`) and halts with exit code 1.

### B. Stage 2: Post-Seating Readiness Verification Gate (`swarm_verify_seats`)
Immediately after panes are allocated, agents started, briefs delivered via nonces, and `.herdr-swarm/seats.json` written, [`lib/lifecycle.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/lifecycle.sh) executes `swarm_verify_seats`:

1. **Ledger Resolution**: Reads the seated agents roster from `.herdr-swarm/seats.json` (falling back to the live workspace registry if necessary).
2. **Agent Liveness Probe**: Confirms the agent exists in Herdr (`herdr agent get "$name"`).
3. **State Settlement**: Blocks until the agent reaches an interactive settled state:
   ```bash
   herdr agent wait "$name" --until "idle" --until "done" --timeout "$timeout_ms"
   ```
4. **Visual & Machine Reporting**: Prints per-seat status:
   - Success: `✓ <name> (<kind> in <pane>): ready`
   - Failure: `✖ <name>: <error/timeout>`
5. **Fail-Closed Autonomous Policy**:
   - In interactive mode, prints warnings if seats are unready.
   - In autonomous queue mode (`a`), if core implementation seats (`arch`, `pm`) fail to settle within `timeout_ms` (default 30,000ms), the launcher **fails closed** and aborts execution immediately with exit code 1.

The launcher also exposes this capability as an independent CLI subcommand:
```bash
./herdr-loop-swarm.sh verify [dir]
```

---

## 5. Consequences

### Positive
- **Zero Incomplete Swarm States**: No workspaces or panes are ever created on an unready system.
- **Elimination of Boot Race Conditions**: Agents are guaranteed to be booted, listening, and aware of their briefs before kickoff instructions arrive.
- **Deterministic Autonomous Reliability**: Automated pipelines fail fast with actionable diagnostics rather than hanging silently on unseated agents.
- **Clear Developer UX**: Color-coded CLI badges provide immediate visual feedback on dependency status and seat readiness.

### Negative / Trade-offs
- **Startup Latency**: The verification steps introduce a slight delay (~1–2 seconds for preflight; 5–20 seconds for agents to load LLM contexts and signal `idle`). This latency is an intentional tradeoff for guaranteed correctness.
