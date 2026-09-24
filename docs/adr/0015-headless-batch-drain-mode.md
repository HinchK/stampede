# ADR 0015: Headless Batch Drain Mode and Unattended Safety Invariants

- **Status**: Accepted
- **Date**: 2026-09-24
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [ADR 0003: Dynamic Seating and Nonce Brief Delivery](0003-dynamic-seating-and-nonce-brief-delivery.md), [ADR 0006: Git Worktree Worker Isolation](0006-git-worktree-worker-isolation.md), [ADR 0008: Supervisor Worktree Suite Gating and Drift](0008-supervisor-worktree-suite-gating-and-drift.md), [ADR 0009: Arbiter Branch Integration and CAS Merge](0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0012: Task Partitioning and Disjoint Dispatches](0012-task-partitioning-and-disjoint-dispatches.md), [ADR 0013: Asynchronous Supervisor Gate Jobs](0013-asynchronous-supervisor-gate-jobs.md), [ADR 0014: Arbiter Drain Automation](0014-arbiter-drain-automation.md), [HEADLESS-2 Design Research](../findings/headless-mode-design.md), [Wayfinder Map: Headless Run Mode](../../maps/headless-run-mode.md), Tickets HEADLESS-3 through HEADLESS-7

---

## 1. Context and Problem Statement

The Stampede swarm architecture was initially developed as an interactive, multi-agent engineering floor inside a terminal multiplexer ([ADR 0003](0003-dynamic-seating-and-nonce-brief-delivery.md), [ADR 0007](0007-split-pane-cwd-order-and-ledger-v2.md), [ADR 0011](0011-multi-worker-floor-topologies-and-concurrency.md)). In this interactive mode (`stampede up`), a human driver collaborates with seated agents across dedicated tabs (`herd` and `ops`), observing live ANSI telemetry streams and orchestrating dispatches via `looper`.

However, deploying Stampede into automated Continuous Integration (CI) pipelines (e.g., GitHub Actions runners), remote headless servers, or overnight cron jobs introduced a fundamental operational mismatch:
1. **Absence of Display and Herdr Daemon**: Automated CI environments possess no GUI display, no virtual framebuffer, and no running `herdr` daemon. Spawning multiplexer panes or querying window geometries fails immediately.
2. **Interactive PTY Assumptions**: The supervisor's original verdict harvesting and critique injection relied on terminal pane scraping (`herdr agent read`) and synthetic keystroke injection (`herdr agent prompt` / PTY typing). In a headless environment, there are no PTYs to read from or type into.
3. **Operator Absence and Unattended Blast Radius**: In interactive mode, human operators notice infinite loops, frozen CLIs, or failing alerts in real time. Running completely unattended introduces severe hazards: runaway re-verdict cycles burning API tokens, hanging worker processes starving task path leases indefinitely, and swallowed error alerts that fail to fail CI builds.

A mechanism was required to execute batch ticket draining in completely headless environments without requiring a Herdr daemon or display, while preserving the interactive developer experience and upholding all foundational safety invariants.

---

## 2. Decision Drivers

- **Unattended CI / Server Compatibility**: Zero dependency on a running `herdr` daemon, terminal multiplexers, pseudo-terminals (PTYs), or display servers. All operations must run via standard POSIX bash and vendor CLI binaries (`claude`, `opencode`, `agy`).
- **Strict Additive Destination (Permanence of Interactive Mode)**: Headless mode must be strictly additive. Interactive pane-based mode (`stampede up`) remains the primary human-in-the-loop development environment and is left 100% unchanged. Headless mode exists specifically for unattended batch execution.
- **Foundational Invariant Reuse Without Mutation**: The core safety machinery—Fail-Closed Suite Gating ([ADR 0001](0001-fail-closed-profile-and-test-gating.md), [ADR 0008](0008-supervisor-worktree-suite-gating-and-drift.md)), Task Partition Leases ([ADR 0012](0012-task-partitioning-and-disjoint-dispatches.md)), Detached Arbiter Integration ([ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0014](0014-arbiter-drain-automation.md)), and Sovereign Human Promotion to Base Branch ([ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md))—must be reused as-is, not rebuilt or bypassed.
- **Unattended Blast Radius Hardening**: Machine-enforced guards must eliminate the three unattended failure modes identified in [HEADLESS-2](../findings/headless-mode-design.md): runaway re-verdict loops, hanging process lease starvation, and swallowed alerts.
- **Deterministic Queue Automation**: Replace `looper`'s interactive human-like dispatch judgment with a deterministic, bounded backlog intake engine over `maps/tickets/`.

---

## 3. Considered Options

### Option A: Direct Subprocess Supervisor (`stampede headless`) — ACCEPTED
Spawn vendor CLI binaries as direct background subprocesses inside isolated Git worktrees. Manage execution, PID tracking, process trees, and signal propagation via a lightweight library harness (`lib/headless.sh`). Harvest completion signals from durable process logs and communicate through file-based brief pointers.

- *Rationale*: Clean, robust POSIX abstraction. Completely decouples batch execution from display servers and multiplexer daemons. Directly supports lightweight CI runner containers.

### Option B: Detached Virtual Herdr Session (tmux / headless daemon) — REJECTED
Run the existing Herdr daemon and multiplexer inside a detached session or virtual display wrapper (e.g., `xvfb` or headless tmux session).

- *Rejection*: In standard CI trigger environments (such as GitHub Actions or minimal Docker containers), the `herdr` daemon binary is not installed or available. Attempting to simulate an interactive terminal multiplexer in headless batch containers introduces massive fragility, high resource overhead, and unpredictable pseudo-terminal buffering issues without delivering any architectural advantage.

### Option C: CLI Flag on Existing Arbiter Drain (`stampede drain --headless`) — REJECTED
Add a `--headless` flag to the existing `drain` command.

- *Rejection*: Under [ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md) and [ADR 0014](0014-arbiter-drain-automation.md), `drain` (`arbiter_drain`) has a well-established, inviolable meaning: advancing the integration staging ref (`swarm/<slug>/integration`) by merging queued, gated commits. Draining the ticket backlog in `maps/tickets/` is a completely different domain operation. Conflating them under the same subcommand violates domain clarity.

### Option D: Full Replacement of Interactive Herd — REJECTED
Deprecate the interactive pane-based floor in favor of purely headless background processes.

- *Rejection*: Stampede's interactive topology, live ANSI telemetry streaming, and human-in-the-loop steering are central to interactive software engineering. Headless mode serves automated batch execution; it does not replace daytime developer workflows.

---

## 4. Decision

We adopted **Option A**, implemented across tickets HEADLESS-3 through HEADLESS-6 and codified in this ADR (HEADLESS-7).

```
+-----------------------------------------------------------------------------------+
|                        `stampede headless` Architecture                           |
|                                                                                   |
|  Deterministic Queue Intake (maps/tickets/*.md: status backlog | queued)          |
|                                   |                                               |
|                    +--------------v--------------+                                |
|                    |   lib/partition.sh Checks   |---- (overlap) ---> [Parked]    |
|                    +--------------+--------------+                                |
|                                   | (clear)                                       |
|                    +--------------v--------------+                                |
|                    |   Lease Acquire (PID/Seat)  |                                |
|                    +--------------+--------------+                                |
|                                   |                                               |
|                    +--------------v--------------+                                |
|                    |     worktree_provision      |                                |
|                    |   (.herdr-swarm/worktrees)  |                                |
|                    +--------------+--------------+                                |
|                                   |                                               |
|                    +--------------v--------------+                                |
|                    |  lib/headless.sh (spawn)    |                                |
|                    |  timeout 600s <vendor-cli>  |                                |
|                    +--------------+--------------+                                |
|                                   |                                               |
|               +-------------------v-------------------+                           |
|               |  Supervisor Harvesting & Suite Gate   |                           |
|               |  (loop-bot-herd.sh: HEADLESS_MODE=1)  |                           |
|               +-------------------+-------------------+                           |
|                                   |                                               |
|        +--------------------------+--------------------------+                    |
|        | (green)                                             | (RED / drift)      |
|  +-----v------------------+                    +-------------v-------------+      |
|  | arbiter_enqueue_and_   |                    | Re-verdict Ceiling Check  |      |
|  | drain (ADR 0014)       |                    | (attempts >= max_attempts)|      |
|  +------------------------+                    +-------------+-------------+      |
|                                                              |                    |
|                                            +-----------------+-----------------+  |
|                                            | (< max)         | (>= max)        |  |
|                                    +-------v-------+  +------v-------+         |  |
|                                    | Critique Turn |  | DEAD_LETTER  |         |  |
|                                    | Spawned       |  | (Hazard 1/3) |         |  |
|                                    +---------------+  +--------------+         |  |
+-----------------------------------------------------------------------------------+
```

### A. User-Facing Entrypoint (`bin/stampede headless`)

Dispatched by convention via `lib/cli/stampede-headless.sh`, the headless entrypoint coordinates the unattended batch pipeline:

```bash
stampede headless [dir] [--max-tickets N] [--timeout M]
```

- **Arguments and Bounded Defaults**:
  - `dir`: Target repository root (defaults to `$PWD`).
  - `--max-tickets N`: Dispatches at most $N$ tickets per session (default: `5`). Enforces finite batch execution, preventing runaway queue consumption.
  - `--timeout M`: Global wall-clock timeout for the entire batch in seconds (default: `1800` / 30 minutes).
- **Fail-Closed Profiling**: Calls `ensure_profile "$dir"` (`lib/profile.sh`) before any dispatch. If toolchain detection fails or tests are unrunnable, the batch aborts immediately.
- **Supervisor Function Sourcing**: Sets `HEADLESS_MODE=1` and sources `loop-bot-herd.sh status` to inherit seat bindings, telemetry sessions, and gate functions directly without duplicating logic.
- **Reviewer Loop Policy in Batch Mode**: The interactive reviewer loop is explicitly disabled (`CONFIG_REVIEW_LOOP=0`). Green verdicts route directly to `arbiter_enqueue_and_drain` (pre-REV-5 path). Quality is guaranteed by the Suite Gate and re-verdict ceilings; multi-round critique reviews are reserved for interactive mode or dedicated review sweeps.
- **Worktree Isolation and Arbiter Integration**: Every headless worker operates in an isolated worktree provisioned via `worktree_provision "$seat_key"` (`lib/worktree.sh`) and tracked in `.herdr-swarm/seats.json` (v2 schema). This ensures `resolve_seat_gate()` detects the seat as isolated, enabling automatic enqueue to `swarm/<slug>/integration` upon a green verdict. Running workers on the root checkout is strictly refused.
- **Deterministic Queue Intake**: Iterates through `maps/tickets/*.md` sorted in lexical filename order, selecting tickets with frontmatter `status: backlog` or `status: queued`.
- **Partition and Lease Protection**: Evaluates `partition_check` (`lib/partition.sh`). Status 0 (clear) and status 2 (exclusive-clear) proceed to `lease_acquire`; status 1 (partition collision) parks the ticket without dispatching.

### B. Subprocess Harness Architecture (`lib/headless.sh`)

`lib/headless.sh` provides non-interactive subprocess management for vendor CLIs (`claude`, `opencode`, `agy`):

1. **Non-Interactive Invocation**: Invokes vendor CLIs directly with prompts passed via command-line arguments (`claude -p "$prompt"`, `opencode run "$prompt"`, `agy -p "$prompt"`). Completely bypasses pseudo-terminals and synthetic enter keys.
2. **Compact File Pointers**: Preserves the prompt delivery invariant from [ADR 0003](0003-dynamic-seating-and-nonce-brief-delivery.md): prompts contain only short file pointers (`BRIEF (file): ... REPLY CHANNEL: ...`), preventing argument-length overflows.
3. **Double-Spawn Prevention and Stale PID Eviction**: Checks `.herdr-swarm/pids/<worker>.pid`. If a process is alive (`kill -0 "$old"`), double spawn is refused. If the PID is dead, the stale pidfile is evicted automatically.
4. **Signal Forwarding and Process Tree Cleanup**:
   - The vendor CLI runs as a direct child of a wrapper subshell. Traps for `TERM`, `INT`, and `HUP` invoke `_hl_signal()`, which forwards the signal to the child CLI and reaps it before exiting at `128+SIG`.
   - `headless_kill` issues `pkill -P "$pid"` before signalling the wrapper, ensuring vendor child processes are terminated immediately and never orphaned in worktrees.
   - Concluded runs append `[_exit_ rc=N]` to the log. `headless_status` inspects the trailing 5 lines to distinguish clean exit (`exited rc=N`) from abrupt termination or signal death (`dead`).

### C. Supervisor Headless Seams (`loop-bot-herd.sh`)

Under `HEADLESS_MODE=1`, `loop-bot-herd.sh` activates three headless seams while leaving interactive pane mode byte-identical:

1. **Output Harvesting (`_headless_seat_output`)**: Scrapes output directly from `.herdr-swarm/logs/<seat>.log` using the exact same anchored regexes (`ARCH DONE #<ticket> <sha>`) as interactive scrollback scraping.
2. **Critique and Feedback Delivery (`worker_feedback`)**: In pane mode, feedback is typed into the PTY. In headless mode, feedback writes a critique brief (`.herdr-swarm/briefs/<seat>-<ticket>-<sha>-<tag>.md`) and executes a new `headless_spawn` turn on the worker's existing worktree branch (reusing the REV-2 shape).
3. **Durable Operator Notices (`looper_notice`)**: Replaces `herdr agent prompt looper` with timestamped, structured appends to `.herdr-swarm/headless-notices.log`.

---

## 5. Unattended Safety Invariants (HEADLESS-5)

Operating unattended without human oversight introduces three distinct blast radius hazards. Headless mode closes all three mechanically:

| Hazard | Failure Mechanism | Enforced Defense | Code Location |
|---|---|---|---|
| **1. Runaway Re-Verdict Loops** | Repeated test failure or tree drift spawns continuous critique loops, burning API quotas. | Strict **Re-Verdict Ceiling** (`[headless] max_verdict_attempts`, default 2). Bounded by ticket failures. On breach, transitions to `DEAD_LETTER`, logs to `dead-letter.jsonl`, releases lease, and halts critique spawning. | [`lib/config.sh`](../../lib/config.sh), [`lib/headless.sh:headless_attempt_count`](../../lib/headless.sh), [`loop-bot-herd.sh:_headless_deadletter`](../../loop-bot-herd.sh) |
| **2. Hanging Processes & Lease Starvation** | Vendor CLI freezes on network call or infinite loop, holding path lease and blocking queue. | Mandatory **Wall-Clock Timeout** on every spawn via `resolve_timeout` (`worker_timeout_s = 600`). Next-pass stale pidfile eviction via `headless_reap` using `kill -0` idiom. | [`lib/headless.sh:headless_spawn`](../../lib/headless.sh), [`lib/headless.sh:headless_reap`](../../lib/headless.sh) |
| **3. Silent Swallowed Alerts** | Unattended failures or gate aborts produce no visible prompt or exit signal, hiding broken builds in CI. | Structured **Dead-Letter Logging** to `.herdr-swarm/dead-letter.jsonl`. Non-zero exit code (`1` on dead-letters, `3` on batch timeout) from `deadletter-check` and `stampede headless`. | [`lib/headless.sh:dead_letter_record`](../../lib/headless.sh), [`lib/cli/stampede-headless.sh`](../../lib/cli/stampede-headless.sh) |

---

## 6. Consequences

### Positive
- **Complete Headless CI/CD Support**: Stampede can execute unattended batch runs inside GitHub Actions, Docker containers, or remote servers with zero Herdr daemon, X11, or display dependencies.
- **Zero Impact on Interactive Mode**: `stampede up` remains completely intact and unchanged, maintaining full compatibility for daytime interactive engineering.
- **Strict Invariant Continuity**: Reuses the Suite Gate, Task Partitioning, Arbiter CAS integration, and sovereign human base branch promotion without altering their verification contracts.
- **Bounded Compute and Financial Risk**: Per-ticket re-verdict ceilings, per-worker process timeouts, and session ticket caps prevent runaway costs and starvation.
- **Definitive CI Signal**: Non-zero exit codes ensure build pipelines fail fast when dead letters or unhandled timeouts occur.

### Neutral / Trade-offs
- **Reviewer Loop Bypassed in Batch**: To prioritize throughput and deterministic execution, `CONFIG_REVIEW_LOOP=0` bypasses the multi-round adversarial review loop in batch mode, relying on the Suite Gate and ceilings. Autonomous review rounds can be triggered interactively or via follow-up sweeps.
- **Sequential Ticket Processing**: Within a single batch run, tickets are processed sequentially per worker seat rather than fanning out arbitrary parallel subprocesses, preserving machine stability and avoiding resource contention.
