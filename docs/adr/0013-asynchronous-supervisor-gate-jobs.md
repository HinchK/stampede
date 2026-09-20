# ADR 0013: Asynchronous Supervisor Suite Gating, Durable Job Records, and Concurrency Bounding

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [Phase 3 Fan-Out Roadmap §1.3](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md), [Ticket P3-3 (Async Supervisor Harvesting)](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/async-supervisor-harvesting.md), [ADR 0002](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0002-exact-sha-supervisor-deduplication.md), [ADR 0008](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0008-supervisor-worktree-suite-gating-and-drift.md), [ADR 0009](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0011](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0011-multi-worker-floor-topologies-and-concurrency.md), [ADR 0012](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0012-task-partitioning-and-disjoint-dispatches.md)

---

## 1. Context and Problem Statement

In Phase 1 and Phase 2, the supervisor daemon ([`loop-bot-herd.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/loop-bot-herd.sh)) harvested completion verdicts by sequentially iterating over `EXPECTED_SEATS` and executing the project test suite (`TEST_CMD`) synchronously inline within the poll loop (`loop-bot-herd.sh:223`).

In a single-worker environment, synchronous test execution was acceptable. However, Phase 3 scales the swarm to $N$ concurrent implementation seats (`arch-1`, `arch-2`, etc. per [ADR 0011](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0011-multi-worker-floor-topologies-and-concurrency.md)). In a multi-worker topology, inline synchronous suite gating introduces a severe head-of-line blocking bottleneck:
1. **Harvest Loop Starvation**: When worker `arch-1` emits an `ARCH DONE #<ticket> <sha>` verdict with a long-running test suite (e.g. 60–300s under `SUITE_TIMEOUT_S=300`), the supervisor blocks on that single test run. During this time, the supervisor cannot read terminal panes from other seats, evaluate other completed tickets, update telemetry, release task leases, or trigger Arbiter promotions. With $N$ active seats, a sequential poll pass can stall for $N \times 300$ seconds.
2. **Resource Thrashing Risk**: Spawning unconstrained background test suites simultaneously across all workers risks CPU starvation, disk I/O bottlenecks, memory pressure, and port/database collisions (Advisory Finding H5).
3. **TOCTOU Drift Vulnerability in Background Execution**: If a test suite runs asynchronously in the background of an isolated worktree, the worker agent might continue modifying files, creating new commits, or generating untracked test fixtures while the runner is active, invalidating the test result.
4. **Crash State Loss**: If the supervisor process terminates or restarts mid-gate, ephemeral in-memory background jobs are lost. The system must never falsely assume unverified jobs succeeded or leave orphaned gate processes running indefinitely.

To achieve scalable multi-worker fan-out, the supervisor suite gate must be transformed into a **non-blocking, concurrency-bounded background execution engine with durable job records**.

---

## 2. Decision Drivers

- **Non-Blocking Supervisor Poll Loop**: A long-running test suite in one worker's worktree must never block the supervisor from harvesting verdicts, checking drift, or managing queues for other seats.
- **Resource Concurrency Bounding**: Concurrent suite executions must be capped to prevent CPU thrashing and test runner collisions.
- **Strict Verification Integrity (TOCTOU Drift Safety)**: Asynchronous background gate execution must guarantee that the code tree evaluated by the runner matches the exact commit SHA and remains pristine throughout the entire execution.
- **Cold Restart Crash Safety**: Supervisor restarts must recover running and completed jobs deterministically without losing state or producing false greens.
- **Seamless Arbiter Integration**: A green test verdict from an asynchronous gate must immediately enqueue the ticket for Compare-and-Swap (CAS) integration into the Arbiter queue.

---

## 3. Considered Options

- **Option A (Inline Synchronous Gating with Reduced Timeouts)**: Keep synchronous gating in the poll loop but shorten `SUITE_TIMEOUT_S`. (Rejected: tests on realistic codebases require realistic timeouts; any timeout truncation causes false RED verdicts on legitimate long suites).
- **Option B (Fully Unbounded Background Spawning)**: Spawn a background subshell `TEST_CMD &` immediately upon every verdict without concurrency limits. (Rejected: launches $N$ concurrent suites simultaneously, saturating system cores, exhaustively locking test databases, and causing flakiness).
- **Option C (Durable Asynchronous Job Records with Concurrency Bounding and Non-Blocking Reaping)**:
  - Spawns background gate jobs with exit code files (`rc`) and dedicated `TMPDIR` paths.
  - Persists durable job metadata files in `.herdr-swarm/gates/<seat>-<sha7>.job`.
  - Caps active test runs to `gate_concurrency` (default 2), queueing excess verdicts oldest-first.
  - Reaps completed jobs in a non-blocking poll loop, re-verifies post-condition tree drift, writes session records, and triggers `arbiter_enqueue`.
  - Re-queues uncompleted jobs on supervisor restart (fail-closed).

---

## 4. Decision

We adopted **Option C**. We establish the following architectural standards across [`loop-bot-herd.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/loop-bot-herd.sh) and the supervisor daemon:

### A. Durable Gate Job Records (`.herdr-swarm/gates/<seat>-<sha7>.job`)
When a seat emits an eligible `ARCH DONE #<ticket> <sha>` verdict and passes initial reality checks:
1. The supervisor assigns the gate execution to the background rather than executing inline.
2. It assigns unique file paths for logging, temporary storage, and exit code capture:
   - Gate Log: `.herdr-swarm/gate-logs/<seat>-<sha>.log`
   - Exit Code File: `.herdr-swarm/gates/<seat>-<sha7>.rc`
   - Dedicated TMPDIR: `.herdr-swarm/gate-tmp/<seat>/`
3. It spawns the test command asynchronously in a subshell:
   ```bash
   (
     cd "$GATE_DIR" && \
     TMPDIR="${STATE_DIR}/gate-tmp/${seat}" \
     timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD"
   ) >"$gate_log" 2>&1
   echo $? > "$rc_file" &
   gate_pid=$!
   ```
4. It immediately writes an atomic, durable JSON job metadata file:
   `.herdr-swarm/gates/<seat>-<sha7>.job`:
   ```json
   {
     "version": 1,
     "pid": 12345,
     "ticket": 42,
     "sha": "a1b2c3d",
     "seat": "arch-1",
     "gate_dir": "/path/to/.herdr-swarm/worktrees/arch-1",
     "started_at": 1774130000,
     "log_file": "/path/to/.herdr-swarm/gate-logs/arch-1-a1b2c3d.log",
     "rc_file": "/path/to/.herdr-swarm/gates/arch-1-a1b2c3d.rc",
     "verdict_line": "ARCH DONE #42 a1b2c3d"
   }
   ```
5. The poll loop proceeds immediately to the next seat without waiting.

### B. Concurrency Bounding (`gate_concurrency`) and Starvation Prevention
To prevent resource saturation:
1. The supervisor reads `gate_concurrency` from `swarm.config.toml` (under `[fanout]`, default: 2).
2. Before spawning a new gate job, the supervisor counts active jobs (where PID is alive and `.rc` file has not yet appeared).
3. If `active_jobs >= gate_concurrency`:
   - New eligible verdicts are queued in memory / pending state.
   - Jobs are scheduled **oldest-verdict-first** based on verdict timestamp. A fast-cycling worker producing frequent commits cannot monopolize gate execution slots at the expense of other workers.

### C. Non-Blocking Poll Cycle, Reaping, and Arbiter Enqueueing
On each iteration of `harvest_verdicts` (running every few seconds):

```
┌────────────────────────────────────────────────────────────────────────┐
│ Supervisor Poll Cycle                                                  │
├────────────────────────────────────────────────────────────────────────┤
│ 1. Scan Terminals (Fast, Non-Blocking)                                 │
│    Read panes → Extract ARCH DONE #<ticket> <sha>                      │
│    Verify SHA in git object store & resolve GATE_DIR (ADR 0008)         │
│                                                                        │
│ 2. Check Capacity & Spawn                                              │
│    If (ticket, sha) not running and active_jobs < gate_concurrency:    │
│      Pre-check gate_tree_matches "$GATE_DIR" "$sha"                    │
│      Spawn background gate & write .herdr-swarm/gates/<seat>-<sha>.job │
│                                                                        │
│ 3. Reap Finished Jobs                                                  │
│    For each .job where .rc exists:                                     │
│      Read gate_rc from .rc file                                        │
│      Post-check gate_tree_matches (TOCTOU verification)                │
│      If tree dirty/drifted: verdict = INVALIDATED                      │
│      Else if gate_rc == 0:  verdict = GREEN → arbiter_enqueue          │
│      Else:                  verdict = RED                              │
│      Record in session.log & telemetry                                 │
│      Remove .job and .rc files                                         │
└────────────────────────────────────────────────────────────────────────┘
```

1. **Reap Trigger**: The presence of `<seat>-<sha7>.rc` signals that the background process has completed.
2. **Post-Condition TOCTOU Drift Verification**:
   Before accepting any result, the supervisor executes `gate_tree_matches "$GATE_DIR" "$sha"`. If `git status --porcelain` shows untracked or modified files, or if `HEAD != sha`, the run is marked `invalidated` regardless of the test suite return code.
3. **Arbiter Enqueueing**:
   If the run is GREEN and pristine, the supervisor writes the verdict to `session.log`, emits telemetry, and immediately invokes:
   ```bash
   arbiter_enqueue "$ticket" "$sha" "$seat"
   ```
   This hands off the candidate branch directly to the transactional Compare-and-Swap Arbiter ([ADR 0009](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0009-arbiter-branch-integration-and-cas-merge.md)).
4. **Cleanup**: The `.job` and `.rc` files are safely removed upon conclusive recording.

### D. Crash Safety and Cold Restart Recovery
The supervisor daemon can crash, receive `SIGKILL`, or be restarted while gate jobs are running in the background. The durable `.job` records guarantee safe recovery:

On supervisor startup:
1. The supervisor inspects `.herdr-swarm/gates/*.job`.
2. For each found job file:
   - **Case 1: Process Still Alive**: `kill -0 "$pid" 2>/dev/null` succeeds. The supervisor resumes tracking the existing background job without restarting it.
   - **Case 2: Process Finished while Dead**: `pid` is gone, but `.rc` exists. The supervisor reaps the exit code, validates tree drift, logs the verdict, and cleans up.
   - **Case 3: Process Killed Mid-Run**: `pid` is gone, but `.rc` is missing. The test execution was interrupted. The supervisor deletes the stale `.job` file and logs a warning. The verdict will be cleanly re-evaluated on the next poll pass. **It is never assumed green.**

### E. Process and Filesystem Isolation (`TMPDIR`)
Running parallel test runners on a single machine can lead to temporary file collisions (e.g. shared `/tmp/test.db` or `/tmp/cache`).
- Every background gate runs with an explicit per-seat temporary directory:
  ```bash
  TMPDIR="${STATE_DIR}/gate-tmp/${seat}"
  ```
- This guarantees full filesystem isolation between concurrent test runner processes.

---

## 5. Invariants & Safety Guarantees

1. **Non-Blocking Poll Invariant**: The supervisor main loop must never invoke blocking commands (`wait`, synchronous `sh -c "$TEST_CMD"`) that can stall the poll cycle.
2. **Concurrency Ceiling Invariant**: The number of concurrently active gate jobs must never exceed `gate_concurrency`.
3. **Durable Job State Invariant**: No background gate process may be spawned without immediately writing its corresponding `.herdr-swarm/gates/<seat>-<sha7>.job` metadata file.
4. **Fail-Closed Crash Invariant**: A background job whose process died without producing an `.rc` file must be treated as aborted and re-queued; it must never be recorded as green.
5. **TOCTOU Drift Invariant**: A background gate run whose working tree changed during execution is strictly marked `invalidated`, even if the test command exited with code 0.

---

## 6. Consequences

### Positive
- **Zero Head-of-Line Blocking**: Long test suites on one worker do not impede verdict harvesting, task intake, or status reporting for other workers.
- **Linear Concurrency Scaling**: Multiple workers can execute tests in parallel up to the configured concurrency cap.
- **Resource Protection**: `gate_concurrency` prevents CPU starvation, port collisions, and memory thrashing.
- **High Crash Resilience**: Durable `.job` files allow seamless recovery across supervisor restarts.
- **Tight Arbiter Coupling**: Green verdicts transition immediately to the Arbiter queue without manual operator intervention.

### Negative / Trade-offs
- **Process Management Complexity**: The supervisor must manage background PIDs, signal checking, `.rc` exit code files, and job cleanup.
- **Disk I/O Overhead**: Fast polling of `.job` and `.rc` files adds minor filesystem stat overhead, though negligible on modern NVMe drives.
- **Queueing Latency under High Contention**: When more workers finish simultaneously than `gate_concurrency` allows, later workers experience queueing delays before their suite runs begin.

---

## 7. References

- [Phase 3 Fan-Out Roadmap §1.3: Asynchronous Supervisor Harvesting](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md)
- [Ticket P3-3: Asynchronous Supervisor Harvesting and Durable Gate Jobs](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/async-supervisor-harvesting.md)
- [ADR 0002: Exact-SHA Supervisor Protocol and Re-Verdict Deduplication](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0002-exact-sha-supervisor-deduplication.md)
- [ADR 0008: Supervisor Worktree Suite Gating, Provenance, and Drift Detection](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0008-supervisor-worktree-suite-gating-and-drift.md)
- [ADR 0009: Arbiter Branch Integration, Compare-and-Swap Ref Updates, and Human Promotion Gates](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0009-arbiter-branch-integration-and-cas-merge.md)
- [ADR 0011: Multi-Worker Floor Topologies, Worktree Namespacing, and Heterogeneous Concurrency](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0011-multi-worker-floor-topologies-and-concurrency.md)
- [ADR 0012: Task Partitioning, File Disjointness, and Durable Ledger Leases](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0012-task-partitioning-and-disjoint-dispatches.md)
