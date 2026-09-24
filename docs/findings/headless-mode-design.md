# Headless Mode Design Research

**Ticket**: [HEADLESS-2](file:///Users/hinchk/Fun/stampede/maps/tickets/headless-2-headless-design-research.md)  
**Author**: agy-docs / looper  
**Date**: 2026-09-24  
**Status**: Research Findings (Pending Driver Alignment)  
**Related Documents**: [ADR 0003](file:///Users/hinchk/Fun/stampede/docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md), [ADR 0006](file:///Users/hinchk/Fun/stampede/docs/adr/0006-git-worktree-worker-isolation.md), [ADR 0009](file:///Users/hinchk/Fun/stampede/docs/adr/0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0014](file:///Users/hinchk/Fun/stampede/docs/adr/0014-arbiter-drain-automation.md), [HEADLESS-1](file:///Users/hinchk/Fun/stampede/maps/tickets/headless-1-no-focus-dispatch.md)

---

## 1. Executive Summary & Core Working Assumptions

Stampede today runs as an interactive terminal workspace application: it provisions Herdr split panes across two tabs (`herd` and `ops`), runs vendor AI agent CLIs (Claude Code, OpenCode GLM-5.3, Gemini CLI) inside PTY panes, and supervises progress by reading pane scrollback buffers via `herdr agent read` and sending prompts via `herdr agent prompt`.

This document investigates what a true **`--headless` (pane-less / unattended) run mode** would require across four fundamental architectural dimensions:
1. **Verification & Harvesting Mechanism**
2. **Seat Scoping & Trigger Mechanism**
3. **Brief Delivery Protocol**
4. **Blast Radius & Fail-Closed Safety Guarantees**

### ⚠️ Critical Working Assumption (Unconfirmed with Driver)
> **Working Assumption**: Headless mode is conceived as an **additive, unattended batch execution mode** (`stampede up --headless` or `stampede drain --headless`) designed to drain already-queued tickets in `maps/tickets/` without opening terminal windows or stealing window focus.  
> **It is NOT a wholesale replacement** of the interactive pane-based pairing environment (`stampede up`), which remains the primary human-in-the-loop development posture.
>
> **Status**: **UNCONFIRMED**. Whether headless mode should be an additive non-interactive command, a detached Herdr session mode, or a permanent migration away from terminal panes entirely must be confirmed with the human driver before implementation tickets are scheduled.

---

## 2. Research Question 1: Verification & Harvesting Mechanism

### Current Architecture in Code
Today, completion harvesting and test gating are tightly coupled to terminal pane scraping in [`loop-bot-herd.sh`](file:///Users/hinchk/Fun/stampede/loop-bot-herd.sh):

1. **Harvesting Loop** ([`loop-bot-herd.sh:445-447`](file:///Users/hinchk/Fun/stampede/loop-bot-herd.sh#L445-L447)):
   ```bash
   for seat in "${EXPECTED_SEATS[@]}"; do
     out=$(herdr agent read "$seat" 2>/dev/null || true)
     [[ -n "$out" ]] || continue
     _review_scan_verdicts "$seat" "$out"
     while IFS= read -r line; do
       ...
       ticket=$(sed -nE 's/.*ARCH DONE #([A-Za-z0-9_.-]+).*/\1/p' <<<"$verdict_line" | tail -n1)
       sha=$(sed -nE 's/.*ARCH DONE #[A-Za-z0-9_.-]+[[:space:]]+([0-9a-fA-F]{7,40}).*/\1/p' <<<"$verdict_line" | tail -n1)
     done < <(grep -E '^[[:space:]]*ARCH DONE #[A-Za-z0-9_.-]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]*$' <<<"$out" | tail -n 5)
   ```
2. **Feedback Injection** ([`loop-bot-herd.sh:499, 534, 540`](file:///Users/hinchk/Fun/stampede/loop-bot-herd.sh#L499-L540)):
   When a verdict is rejected as stale, invalidated by tree drift, or fails the suite gate (`RED`), the supervisor writes feedback directly back into the agent's PTY input buffer via `herdr agent prompt "$seat" "LOOP-BOT: ..."` and `herdr agent prompt looper "..."`.

### What Replaces Pane Scraping in Headless Mode?

An inspection of the Herdr CLI (`herdr agent --help`, `herdr pane --help`) reveals that **Herdr has no daemon abstraction for pane-less background agents**. Every `herdr agent` command requires a corresponding GUI terminal pane. Therefore, headless execution must choose between two architectural approaches:

#### Approach A: Direct Subprocess Management (Bypassing Herdr Daemon)
In this model, Stampede manages worker processes directly as standard Unix child processes:
- **Process Model**: Worker seats are spawned via background subprocesses (tracking PIDs in `.herdr-swarm/pids/<seat>.pid`) with stdout and stderr redirected to `.herdr-swarm/logs/<seat>.log`.
- **Verdict Signaling**:
  - Instead of emitting `ARCH DONE #<ticket> <sha>` into terminal scrollback, the worker writes its verdict into a durable response file.
  - Stampede *already has* a structured reply channel primitive defined in [`loop-bot-herd.sh:734-738`](file:///Users/hinchk/Fun/stampede/loop-bot-herd.sh#L734-L738):
    ```bash
    nonce=$(date +%s)-$RANDOM
    out="$CHANNEL_DIR/${worker}-${nonce}.md"
    # "REPLY CHANNEL: write your complete response to $out and reply with only the path."
    ```
  - In headless mode, the completion sentinel is written directly to `$out` or scanned from `.herdr-swarm/logs/<seat>.log` using the exact same whole-line anchored regex (`grep -E '^[[:space:]]*ARCH DONE #[A-Za-z0-9_.-]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]*$'`).
- **Feedback & Re-verdict Loops**:
  - When the Suite Gate fails (`suite: RED`) or tree drift occurs, the supervisor cannot type into an active prompt.
  - Instead, the supervisor treats refinement as a new dispatch turn: it compiles a critique brief citing the gate log (`.herdr-swarm/gate-logs/<job>.log`) and re-invokes the worker subprocess on the same worktree branch (mirroring the critique delivery protocol formalized in `REV-2`).

#### Approach B: Detached Virtual Workspace (Retaining Herdr Daemon)
- Keep the Herdr daemon and pane abstraction, but launch the workspace inside a headless/detached session (e.g. `herdr --session headless-stampede` or an off-screen virtual terminal buffer like `xvfb` or headless tmux).
- **Advantage**: Zero changes required to `loop-bot-herd.sh`, `herdr agent read`, or `_review_scan_verdicts`.
- **Disadvantage**: Heavy dependency on Herdr daemon lifecycle, PTY emulation overhead, and potential fragility if detached session support in Herdr is incomplete.

**Research Assessment**: Approach A (Direct Subprocess Management with channel/log harvesting) is the cleanest, most robust foundation for true headless operation in CI/CD and unattended background batch runs.

---

## 3. Research Question 2: Seat Scoping & Trigger Mechanism

### Which Seats Run in Headless Mode?

The interactive swarm topology seats up to 7 agents across two tabs:
- Herd: `looper` (Orchestrator), `arch-1` (GLM-5.3), `arch-2` (Claude), `overseer-pm` (Claude)
- Ops: `reviewer` (Reviewer Loop), `worker-docs` (Doc Sync), `worker-gh` (GitHub Sync)

In an unattended `--headless` run, the required seat roster narrows significantly:

| Seat / Role | Run in Headless? | Operational Rationale |
|---|---|---|
| **`arch-1` / `arch-2`** (Implementers) | **YES** | Core workers executing ticket specs and committing to isolated worktrees. |
| **`reviewer`** (Reviewer Loop) | **YES** | Autonomous code review and critique generation (`REV-1` through `REV-5`). |
| **Arbiter** (`lib/arbiter.sh`) | **YES** | Background integration daemon merging passing commits into `swarm/<slug>/integration`. |
| **Supervisor** (`loop-bot-herd.sh`) | **YES** | Core daemon managing partition leases, suite gates, and verdict harvesting. |
| **`looper`** (Interactive Orchestrator) | **CONDITIONAL** | In interactive mode, `looper` reasons about user requests and chooses tickets. In headless batch mode, `looper`'s dispatch role is replaced by a deterministic queue intake engine that iterates over `maps/tickets/` with status `backlog` / `queued`. |
| **`pm`** (Overseer / Auditor) | **NO** | Strategic planning and ADR chartering are human/interactive milestones. |
| **`worker-docs` / `worker-gh`** | **NO** | Documentation sweep and remote GitHub issue mutation remain operator-governed tasks. |

### How is Headless Mode Triggered?

Three potential entry points exist in the CLI hierarchy:

1. **Launcher Flag (`stampede up --headless`)**:
   - Extends [`herdr-loop-swarm.sh`](file:///Users/hinchk/Fun/stampede/herdr-loop-swarm.sh) with `--headless`.
   - Bypasses `tab_by_label`, `pane_split`, and GUI layout creation in `lib/layout_engine.sh`.
   - Initializes worktrees (`lib/worktree.sh`), starts the background supervisor (`loop-bot-herd.sh`), and executes queued dispatches.
2. **Dedicated Drain Command (`stampede drain --headless`)**:
   - A purpose-built CLI command: `bin/stampede drain [--max-tickets N] [--timeout M]`.
   - Explicitly signals that the invocation is a finite batch operation (drain queued backlog until empty, then terminate).
3. **CI/CD Integration**:
   - Executes inside GitHub Actions (`.github/workflows/`), where no display server or interactive terminal is available.

---

## 4. Research Question 3: Brief Delivery Protocol

### Current Architecture in Code
The Nonce Brief Delivery Protocol ([ADR 0003](file:///Users/hinchk/Fun/stampede/docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md)) relies on active PTY prompts:
- **Standing Briefs** ([`lib/briefs.sh:118-123`](file:///Users/hinchk/Fun/stampede/lib/briefs.sh#L118-L123)):
  ```bash
  local prompt_msg="STANDING BRIEF: You are seated as '${seat_name}'. Your standing brief is rendered at '${brief_path}'. Read it immediately using your file viewing tools and adopt this posture. Acknowledge when ready."
  herdr agent prompt "$seat_name" "$prompt_msg" >/dev/null 2>&1 || true
  sleep 1
  herdr agent send-keys "$seat_name" enter >/dev/null 2>&1 || true
  ```
- **Task Briefs** ([`loop-bot-herd.sh:736`](file:///Users/hinchk/Fun/stampede/loop-bot-herd.sh#L736)):
  ```bash
  herdr agent prompt "$worker" "BRIEF (file): $brief — read it with your file tools and execute. REPLY CHANNEL: write your complete response to $out and reply with only the path." >/dev/null
  ```

Both calls require an open terminal input line and a synthesized `enter` keystroke.

### Headless Brief Delivery Protocol

In a headless subprocess environment, interactive PTY prompt injection is eliminated. However, the core insight of ADR 0003—**delivering compact file-path pointers (<200 bytes) rather than inlining multi-kilobyte documents**—remains fully applicable and optimal:

1. **CLI Prompt Flag / Stdin Invocation**:
   Vendor CLIs provide non-interactive entrypoints:
   - Claude Code: `claude -p "..."` or `cat prompt.txt | claude`
   - OpenCode: `opencode run "..."`
   - Gemini / AGY CLI: `agy -p "..."` or prompt file argument
   
   Instead of inlining the ticket markdown, the command-line prompt delivers the exact same compact pointer:
   ```bash
   opencode run "STANDING BRIEF: .herdr-swarm/briefs/arch.md. TASK BRIEF: $brief. RESPONSE CHANNEL: $out. Adopt posture, execute task, and emit ARCH DONE #<ticket> <sha>."
   ```
2. **Environment Variable Injection**:
   The worker subprocess can inherit execution pointers directly via environment variables:
   ```bash
   export STAMPEDE_STANDING_BRIEF=".herdr-swarm/briefs/arch.md"
   export STAMPEDE_TASK_BRIEF="$brief"
   export STAMPEDE_RESPONSE_CHANNEL="$out"
   export STAMPEDE_WORKTREE_DIR="$wt_dir"
   ```
   A standardized worker boot wrapper (`scripts/run-worker.sh`) reads these variables, mounts the worktree, and initiates the vendor CLI.

3. **Elimination of PTY Synchronization Bugs**:
   Headless brief delivery is structurally superior to PTY injection: it eliminates `sleep 1`, synthetic `enter` keystrokes, and race conditions where prompts sit unsubmitted in terminal input buffers.

---

## 5. Research Question 4: Blast Radius & Fail-Closed Safety Guarantees

When an autonomous multi-agent system runs unattended without a human observing terminal output in real time, do existing safety invariants hold, or do they implicitly rely on human supervision?

### Audit of Existing Invariants

| Safety Invariant | Enforcing Mechanism | Code Location | Autonomous Robustness |
|---|---|---|---|
| **Suite Gate** (No false greens) | Executes real `TEST_CMD` inside isolated worktree; invalidates on tree drift | [`loop-bot-herd.sh:503-538`](file:///Users/hinchk/Fun/stampede/loop-bot-herd.sh#L503-L538), [`lib/profile.sh:test_cmd_is_runnable`](file:///Users/hinchk/Fun/stampede/lib/profile.sh) | **100% Robust**. Pure machine evaluation; requires zero human visual oversight. |
| **Partition / Lease Gate** (Disjoint paths) | Verifies `owns:` frontmatter and locks `.herdr-swarm/leases.json` before dispatch | [`lib/partition.sh`](file:///Users/hinchk/Fun/stampede/lib/partition.sh), [`loop-bot-herd.sh:676`](file:///Users/hinchk/Fun/stampede/loop-bot-herd.sh#L676) | **100% Robust**. Algorithmic file path overlap check; blocks collision before dispatch. |
| **Reviewer Loop Gate** (Adversarial review) | Durable `reviews.json` state machine with hard `max_rounds` budget cap | [`lib/lifecycle.sh`](file:///Users/hinchk/Fun/stampede/lib/lifecycle.sh), [`tests/test_review_loop.sh`](file:///Users/hinchk/Fun/stampede/tests/test_review_loop.sh) | **100% Robust**. Transitions to `ALERT_BLOCKED` and halts enqueue if critique is not resolved. |
| **Sovereign Human Promote Gate** (Base protection) | `arbiter_drain` merges strictly to `swarm/<slug>/integration`; base branch advance requires human promote | [`lib/arbiter.sh:312-323`](file:///Users/hinchk/Fun/stampede/lib/arbiter.sh#L312-L323), [ADR 0009](file:///Users/hinchk/Fun/stampede/docs/adr/0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0014](file:///Users/hinchk/Fun/stampede/docs/adr/0014-arbiter-drain-automation.md) | **100% Robust**. Machine code actively refuses to move `main` without explicit human invocation (`promote --confirm`). |

### ⚠️ New Blast Radius Hazards in Headless Mode

While core correctness gates are machine-enforced, operating without human eyes introduces **three new operational failure modes**:

#### Hazard 1: Runaway Re-Verdict & Cost Loops
- **In Interactive Mode**: If an agent gets stuck in a loop repeatedly failing tests or producing invalid commits, the operator notices rapid terminal activity and terminates the pane.
- **In Headless Mode**: If a ticket triggers repeated `RED` verdicts, an unconstrained supervisor could continuously prompt re-verdict attempts all night, exhausting API quotas and compute credits.
- **Required Invariant**:
  - A strict **Per-Ticket Re-Verdict Ceiling** (e.g. `MAX_VERDICT_ATTEMPTS=2`). Upon reaching the limit, the ticket enters `DEAD_LETTER` status and the lease is released.
  - A strict **Session Ticket Cap** (e.g. `--max-tickets 5`).
  - A global **Wall-Clock Execution Budget** (e.g. `--timeout 1800s`).

#### Hazard 2: Hanging Processes & Path Lease Starvation
- **In Interactive Mode**: If a CLI hangs waiting for user input or encountering a network timeout, the operator observes the freeze.
- **In Headless Mode**: If a worker subprocess hangs, it holds its file path lease in `.herdr-swarm/leases.json` indefinitely, starving all subsequent tickets that touch those files.
- **Required Invariant**:
  - Subprocess execution must be wrapped in hard process timeouts (e.g. `timeout 600s ...`).
  - Stale lease eviction logic in `lib/partition.sh` must monitor PID liveness (`kill -0 "$pid"`), breaking dead locks automatically (analogous to the stale lock eviction built in `PROVE-7` for `arbiter.lock`).

#### Hazard 3: Silent Swallowed Alerts (Alert Invisibility)
- **In Interactive Mode**: Supervisor alerts (`suite: skipped`, `ALERT_BLOCKED`, `arbiter conflict`) prompt `looper` or print ANSI badges to the Ops pane.
- **In Headless Mode**: With no terminal pane or operator watching, prompt injection fails or writes to unmonitored logs.
- **Required Invariant**:
  - Durable **Dead-Letter Logging**: Any ticket that cannot be verified or encounters an unresolvable conflict must append a structured incident record to `.herdr-swarm/dead-letter.jsonl`.
  - Non-Zero Exit Code: If any ticket in a batch run terminates in `DEAD_LETTER` or `BLOCKED`, the headless runner must exit with a non-zero status code, alerting CI/CD pipelines.

---

## 6. Architectural Alternatives Comparison

| Dimension | Option A: Direct Subprocess Supervisor | Option B: Detached Virtual Herdr Session | Option C: Status Quo Focus Audit (HEADLESS-1, Resolved) |
|---|---|---|---|
| **Underlying Mechanism** | Spawns vendor CLIs directly via background subprocesses | Runs Herdr daemon in detached/virtual tmux/session | Uses existing Herdr panes; premise of prompt focus-theft disproven |
| **Herdr Daemon Dependency** | **None** (Bypasses daemon completely) | **High** (Requires running Herdr daemon) | **High** (Runs inside active Herdr session) |
| **CI / Headless Server Support** | **Full** (Native POSIX bash & CLI tools) | **Partial** (Requires headless terminal support) | **None** (Requires interactive desktop GUI / terminal) |
| **Supervisor Changes** | Medium (Replaces `herdr agent read` with log/channel reader) | Minimal (Reuses existing `herdr agent read`) | None (Empirical audit showed no code fix needed or possible) |
| **Implementation Complexity** | Moderate (Requires process supervisor & timeout harness) | High (Dealing with detached session lifecycle & state) | Resolved (Herdr 0.9.1 `prompt` has no `--no-focus`; panes already split `--no-focus`) |

---

## 7. Recommended Next Steps

This research document produces an architectural foundation for driver evaluation, not immediate code changes. 

### Recommendation: Sequence via a Dedicated Wayfinder Map
Rather than jumping directly to implementation, author a dedicated Wayfinder Map (`maps/headless-run-mode.md`) structuring work into discrete, verifiable slices:

1. **Slice 1: Low-Hanging Focus Fix ([HEADLESS-1](file:///Users/hinchk/Fun/stampede/maps/tickets/headless-1-no-focus-dispatch.md) — Resolved)**:
   - Already resolved and complete (`HEADLESS-1` closed in commit `c8fbad2`).
   - Empirical investigation showed `herdr 0.9.1` `agent prompt` has no `--no-focus` option, live probing demonstrated that prompts do not steal window or OS focus, and `split_pane` in `lib/layout_engine.sh:16` already passes `--no-focus`. No code fix was needed or possible.
2. **Slice 2: Driver Alignment on Headless Destination**:
   - Confirm whether headless mode is:
     - (A) Additive batch queue drainer (`stampede drain --headless`), or
     - (B) Full replacement of pane-based architecture.
3. **Slice 3: Headless Subprocess Harness & Channel Protocol**:
   - Build `lib/headless.sh` supporting subprocess spawning, PID tracking, and log redirection.
   - Adapt `loop-bot-herd.sh` to harvest verdicts from response channels when running in headless mode.
4. **Slice 4: Unattended Safety Hardening**:
   - Implement execution timeouts, per-ticket re-verdict caps, dead-letter logging, and stale lease eviction.
