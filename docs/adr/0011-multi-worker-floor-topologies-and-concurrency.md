# ADR 0011: Multi-Worker Floor Topologies, Worktree Namespacing, and Heterogeneous Concurrency

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [Phase 3 Fan-Out Roadmap](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md), [Ticket P3-1 (Multi-Worker Config)](../../maps/tickets/multi-worker-config-and-roster-expansion.md), [ADR 0006](0006-git-worktree-worker-isolation.md), [ADR 0007](0007-split-pane-cwd-order-and-ledger-v2.md), [ADR 0008](0008-supervisor-worktree-suite-gating-and-drift.md), [ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0010](0010-worktree-teardown-lifecycle-and-salvage.md)

---

## 1. Context and Problem Statement

Phase 2 established the primitives of Git worktree isolation ([ADR 0006](0006-git-worktree-worker-isolation.md)), CWD binding ordering ([ADR 0007](0007-split-pane-cwd-order-and-ledger-v2.md)), isolated suite gating ([ADR 0008](0008-supervisor-worktree-suite-gating-and-drift.md)), transactional merge arbitration ([ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md)), and safe teardown/salvage ([ADR 0010](0010-worktree-teardown-lifecycle-and-salvage.md)). However, the execution model in Phase 2 remained constrained to a single active implementation seat (`arch`), gating and integrating tickets one at a time.

As empirical benchmarking demonstrated ([Phase 3 Fan-Out Roadmap](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md)), single-worker execution serializes throughput. To achieve autonomous scale, Phase 3 expands the swarm from 1 singleton worker to $N$ concurrent workers (`arch_1`, `arch_2`, etc.) operating simultaneously in isolated git worktrees.

Scaling to concurrent multi-worker execution introduces four architectural challenges:
1. **Herdr Floor Topologies and Geometry Constraints**: Herdr terminal panes must honor an 80×20 character floor (`MIN_COLS=80`, `MIN_ROWS=20` in [`lib/layout_engine.sh`](../../lib/layout_engine.sh)). Packing multiple worker terminals into the primary `herd` tab rapidly crushes panes below minimum dimensions, causing terminal ANSI escape corruption, truncated model inputs, and agent failures.
2. **Worktree Path and Branch Namespacing**: Parallel workers concurrently executing Git operations will conflict if filesystem paths or branch references collide or overlap.
3. **Model Tier Routing & Token Economics**: Deploying frontier reasoning models across all $N$ parallel workers causes catastrophic token burn and rate-limit exhaustion. Conversely, deploying lightweight models on complex architectural tasks leads to hallucinations and structural defects.
4. **Lifecycle Fault Tolerance and Crash Isolation**: A crashed, looping, or failing worker must not contaminate the root checkout, corrupt peer workers' workspaces, or block the swarm's supervisor loops.

---

## 2. Decision Drivers

- **Linear Scalability without Contention**: Scaling from 1 to $N$ workers must produce zero Git index lock contention (`index.lock`) and zero filesystem interference.
- **Terminal Geometry Guarantee**: Terminal dimensions for all active agents must never drop below 80×20, preserving PTY stability and legible visual monitoring.
- **Economic Model Routing**: Dynamic routing of heterogeneous agent engines (`opencode`, `claude`, `agy`) to appropriate task tiers (high-throughput implementation vs. architectural reasoning vs. documentation).
- **Fault Domain Isolation**: Failure, syntax crash, or gate invalidation in one worker seat must be strictly isolated to its worktree, leaving peer seats and root intact.
- **Deterministic Namespacing**: Worktree paths, Git branches, and ledger records must follow strict, slugified namespaces.

---

## 3. Considered Options

- **Option A (Single Tab Multi-Split)**: Subdivide the existing `herd` tab into $N+2$ panes. (Rejected: immediately violates the 80×20 geometry floor; 3+ workers produce unusable terminal strips that break model CLI rendering).
- **Option B (Homogeneous Frontier Fleet in Separate Clones)**: Spin up full repository clones for each worker, all running the identical frontier model. (Rejected: full clones duplicate disk usage and break shared `.git` object cache; identical frontier models multiply operational API costs by $N\times$ with diminishing returns on routine implementation).
- **Option C (Multi-Tab Floor Topology, Shared Object Namespaced Worktrees, and Heterogeneous Model Tiers)**:
  - Isolate workers into a dedicated `workers` tab or automated relocation tabs adhering to the 80×20 floor.
  - Namespace worktrees under `.herdr-swarm/worktrees/<seat>` and branches under `swarm/<slug>/<seat>`.
  - Route model tiers declaratively via `swarm.config.toml` (`opencode` + GLM-5.3 for high-throughput coding, `claude` + Sonnet for complex refactors, `agy` + Flash for docs and ops).
  - Track every seat independently in `.herdr-swarm/seats.json` v2.

---

## 4. Decision

We adopted **Option C**. We establish the following architectural standards across the configuration registry, layout engine, and swarm launcher:

### A. Multi-Worker Floor Topology & Herdr Geometry Floors
To support $N$ workers without degrading terminal usability:
1. **Tab Separation**:
   - **Root Anchor Tab (`herd`)**: Houses the orchestration anchors (`looper`, `pm`) executing in `$PWD` on the baseline ref.
   - **Worker Floor (`workers` tab / Dedicated Seat Tabs)**: Autonomous implementation seats are placed in a dedicated `workers` tab. If $N \le 2$, a 50/50 split is used. If $N > 2$ or terminal width is restricted, [`lib/layout_engine.sh`](../../lib/layout_engine.sh) automatically moves cramped panes to dedicated tabs (`seat-<slug>-<id>`).
   - **Operations Tab (`ops`)**: Houses real-time telemetry streaming (`telemetry.py`), GitHub operations (`agy-gh`), documentation agents (`agy-docs`), and proxy hosts.
2. **80×20 Geometry Floor Enforcement**:
   [`lib/layout_engine.sh`](../../lib/layout_engine.sh) continuously inspects pane rectangles. Any pane whose geometry drops below `MIN_COLS=80` or `MIN_ROWS=20` is immediately relocated via `herdr pane move --tab <rescue_tab>` before agent launch, preventing PTY text wrapping failures.

```
┌─────────────────────────────────────────────────────────────┐
│ Herdr Swarm Workspace ("swarm-dev")                         │
├─────────────────┬─────────────────────────┬─────────────────┤
│ Tab 1: "herd"   │ Tab 2: "workers"        │ Tab 3: "ops"    │
├─────────────────┼─────────────────────────┼─────────────────┤
│ [looper] (AGY)  │ [arch_1] (.herdr-swarm/ │ [telemetry]     │
│  Root / main    │  worktrees/arch-1)      │  Live JSONL     │
├─────────────────┼─────────────────────────┼─────────────────┤
│ [pm] (Claude)   │ [arch_2] (.herdr-swarm/ │ [agy-docs]      │
│  Root / main    │  worktrees/arch-2)      │ [agy-gh]        │
└─────────────────┴─────────────────────────┴─────────────────┘
```

### B. Worktree Path and Branch Namespacing
To avoid cross-seat collisions and Git lock contention:
1. **Filesystem Isolation**: Each worker $i$ receives a dedicated worktree directory:
   ```
   ${TARGET_DIR}/.herdr-swarm/worktrees/${seat}
   ```
   (e.g. `.herdr-swarm/worktrees/arch-1-preview`, `.herdr-swarm/worktrees/arch-2-preview`).
2. **Branch Namespacing**: Each worker operates on an isolated branch:
   ```
   refs/heads/swarm/${PROJECT_SLUG}/${seat}
   ```
   (e.g. `swarm/preview/arch_1`, `swarm/preview/arch_2`).
3. **Dedicated Git Index**: Because each worktree maintains its own `.git/worktrees/<seat>/index`, concurrent `git add`, `git commit`, and `git checkout` operations across workers execute with zero `index.lock` contention.
4. **CWD Binding Order (ADR 0007 Enforcement)**: `worktree_provision` executes prior to `split_pane`, guaranteeing the terminal pane permanently attaches to the isolated directory.

### C. Heterogeneous Model Tier Routing
To balance throughput, cost, and reasoning depth, seats in [`swarm.config.toml`](../../swarm.config.toml) are mapped to specialized engine tiers:

| Tier | Engine (`default_kind`) | Model (`model`) | Primary Allocation | Economic / Cognitive Profile |
|---|---|---|---|---|
| **High-Throughput Implementation** | `opencode` | `zai/glm-5.3` | `arch_1`, `arch_2` | Fast token velocity, low cost per ticket, high precision on concrete diffs and unit tests. |
| **Architectural Reasoning & Strategy** | `claude` | `claude-3-7-sonnet` | `pm`, complex refactors | Extended context reasoning, map/PRD synthesis, file partition planning. |
| **Autonomous Loop Orchestration** | `agy` | `gemini-2.5-pro` | `looper` | Multimodal tool use, supervisor telemetry parsing, arbitration triggers. |
| **Documentation & CI Operations** | `agy` | `gemini-2.5-flash` | `agy-docs`, `agy-gh` | Structured markdown generation, ADR authoring, GitHub CLI operations, ultra-low cost. |

Configuration permits expanding implementation workers via explicit seats or replica templates (`replicas = N` in `swarm.config.toml`), which [`lib/config.sh`](../../lib/config.sh) expands into `SEAT_KEYS="arch_1 arch_2 ..."`.

### D. Independent Lifecycle Isolation and Fault Tolerance
1. **Crash Isolation**:
   - If worker `arch_1` crashes, loops indefinitely, or produces a RED suite verdict, worker `arch_2` continues uninhibited.
   - A crashed worker never pollutes `main` because its changes remain confined to `swarm/<slug>/arch_1`.
2. **Asynchronous Suite Gating & Harvesting**:
   - As specified in the [Phase 3 Fan-Out Roadmap](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md), suite gating jobs execute in the background with durable job records (`.herdr-swarm/gates/<seat>-<sha7>.job`).
   - A slow or stalled test suite on one worker does not block the supervisor from harvesting verdicts or dispatching tasks to other seats.
3. **Safe Teardown & Salvage**:
   - On shutdown (`swarm_down`), each worker worktree is processed per [ADR 0010](0010-worktree-teardown-lifecycle-and-salvage.md): untracked files are archived to `.herdr-swarm/salvage/<seat>-<timestamp>/`, tracked changes are preserved on checkpoint branches, and administrative locks are released.

---

## 5. Invariants & Safety Guarantees

1. **Geometry Floor Invariant**: No agent terminal pane may remain below 80 columns or 20 rows; violating panes must be relocated to dedicated tabs prior to agent startup.
2. **Worktree Isolation Invariant**: No two active implementation workers may share the same working directory or branch.
3. **Index Lock Invariant**: Implementation workers must never invoke Git commands within the root workspace `$PWD`, ensuring zero `index.lock` interference with the orchestrator or arbiter.
4. **Provision-Before-Split Invariant**: Every worker worktree must be fully created on disk before invoking `herdr pane split --cwd <dir>`.
5. **Fail-Closed Failure Domain**: A worker failure (crash, gate rejection, parse failure) must never terminate the supervisor daemon or halt peer workers.

---

## 6. Consequences

### Positive
- **Concurrent Throughput**: Multiple independent tickets can be implemented, tested, and gated concurrently, multiplying development velocity.
- **Zero Lock Contention**: Parallel git operations execute smoothly without index conflicts.
- **Optimized Token Economics**: Routing high-volume implementation to cost-effective models (GLM-5.3) preserves API budgets while reserving frontier models (Claude 3.7 Sonnet) for architectural synthesis.
- **Robust Visual Monitoring**: The multi-tab floor topology ensures operators can cleanly observe agent progress without terminal line wrap corruption.

### Negative / Trade-offs
- **Increased Memory and Disk Footprint**: Running $N$ concurrent workers allocates $N$ worktree directories and $N$ active language agent processes.
- **CPU / Port Contention During Concurrent Test Gating**: Running multiple test suites simultaneously can cause port collisions or CPU thrashing; bounded by `gate_concurrency` (default 2).
- **Partitioning Requirement**: To prevent merge conflicts at the Arbiter stage, tickets must be partitioned with disjoint file ownership sets (`owns:` metadata).

---

## 7. References

- [Phase 3 Fan-Out Roadmap: Autonomous Concurrent Multi-Ticket Fan-Out](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md)
- [Ticket P3-1: Multi-Worker Config & Dynamic Roster Expansion](../../maps/tickets/multi-worker-config-and-roster-expansion.md)
- [ADR 0006: Git Worktree Worker Isolation and Lifecycle Management](0006-git-worktree-worker-isolation.md)
- [ADR 0007: Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2](0007-split-pane-cwd-order-and-ledger-v2.md)
- [ADR 0008: Supervisor Worktree Suite Gating, Provenance, and Drift Detection](0008-supervisor-worktree-suite-gating-and-drift.md)
- [ADR 0009: Arbiter Branch Integration, Compare-and-Swap Ref Updates, and Human Promotion Gates](0009-arbiter-branch-integration-and-cas-merge.md)
- [ADR 0010: Worktree Teardown Lifecycle, Untracked File Salvage, and Stale Branch Re-attachment Gating](0010-worktree-teardown-lifecycle-and-salvage.md)
- [Swarm Orchestration Retrospective](../findings/swarm-orchestration-retrospective.md)
