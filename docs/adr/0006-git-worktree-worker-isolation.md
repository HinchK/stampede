# ADR 0006: Git Worktree Worker Isolation and Lifecycle Management

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [T-016-docs](../../maps/tickets/worktree-isolation-architecture.md), [Universal Swarm Plan](../../maps/universal-herdr-swarm.md), [ADR 0004](0004-safe-workspace-lifecycle-and-seat-ledger.md), Claude-PM Prototype (`loop-bot-herd-claude/`, external lineage — not part of this repo)

---

## 1. Context and Problem Statement

In Milestone 1 (M1), the Universal Herdr Swarm operates under a **sequential execution model**: all seated agents (`pm`, `arch`, `looper`, `agy-docs`, `agy-gh`) share a single physical working directory (`$PWD`) and a single active branch (typically `main`).

While this sequential architecture simplifies initial setup and test verification, fanning out execution to multiple concurrent workers (e.g. `arch` implementing ticket #101 while `agy-docs` authors documentation for ticket #102, or multiple coding workers executing subtasks in parallel) introduces catastrophic concurrency hazards:

1. **Git Lock Contention**: Concurrent `git add` or `git commit` operations across multiple panes collide on `.git/index.lock`, causing intermittent fatal aborts.
2. **Dirty Working Tree Pollution**: Uncommitted edits from one worker leak into other workers' test runs, resulting in non-deterministic test results and spurious test failures.
3. **Branch Switching Collisions**: Running `git checkout` or `git switch` in a shared working directory while another process holds open file descriptors or uncommitted edits is rejected by Git or corrupts in-flight edits.
4. **Untracked File Drift**: Shared temporary build artifacts, scratch scripts, or test caches cross-contaminate concurrent worker evaluation.

To support Phase 2 parallel swarm execution, workers must operate in **isolated, disposable file spaces** while sharing the underlying Git object history.

---

## 2. Decision Drivers

- **Conflict-Free Concurrency**: Multiple autonomous agents must be capable of editing, committing, and testing code simultaneously without file system or Git lock collisions.
- **Root Repository Stability**: Master orchestration (`looper`), strategic oversight (`pm`), and telemetry streaming must remain anchored in the primary repository checkout (`$PWD`) to maintain persistent human operator orientation.
- **Durable Accounting**: Every allocated worktree path and branch ref must be tracked durably in `.herdr-swarm/seats.json`.
- **Safe, Idempotent Teardown**: Swarm teardown (`swarm_down`) must reliably clean up disposable worktrees without touching the root repository, destroying uncommitted operator work, or dropping completed branch commits.
- **Strict Quality Gating**: No worktree branch may be merged into the primary branch or submitted upstream without passing the independent Suite Gate in its own isolated worktree environment.

---

## 3. Considered Options

- **Option A (Sequential Single Checkout — Status Quo)**: Retain single shared working directory; queue all tasks sequentially. (Safe, but fundamentally limits swarm throughput to one agent at a time).
- **Option B (Full Independent Repository Clones)**: Clone the repository into separate scratch directories (`/tmp/...`) for each worker. (High disk usage, slow initialization, duplicate network/git overhead, and disconnected local branch refs).
- **Option C (Git Worktree Isolation with Seat Ledger Accounting)**: Provision dedicated `git worktree` instances under `.herdr-swarm/worktrees/<seat>` linked to the root repository, tracked durably in `.herdr-swarm/seats.json`, gated independently, and integrated via an arbiter.

---

## 4. Decision

We adopted **Option C**. We establish the **Git Worktree Worker Isolation Architecture** as the foundation for Phase 2 parallel swarm fan-out.

### A. Floor Topology: Root Anchor vs Dedicated Worker Worktrees
The swarm topology divides agents into **Root Anchor Seats** and **Isolated Worker Seats**:

1. **Root Anchor Seats**:
   - `looper` (Master Orchestrator), `pm` (Product Manager), and `telemetry-stream` (Ops anchor pane) execute directly in the primary repository root (`$PWD`).
   - They operate on the active baseline branch (`main` or active feature branch).
2. **Isolated Worker Seats**:
   - Implementation agents (`arch`, parallel worker tasks `w-<id>`) execute in dedicated, disposable Git worktrees located at:
     ```
     ${TARGET_DIR}/.herdr-swarm/worktrees/<seat>
     ```
     (Example: `.herdr-swarm/worktrees/arch-kultivait`)
   - Each worker operates on an isolated local branch:
     ```
     swarm/<slug>/<seat>
     ```
     (Example: `swarm/kultivait/arch`) branched from the baseline branch.

### B. Durable Seat Ledger Schema (`.herdr-swarm/seats.json`)
Per [ADR 0004](0004-safe-workspace-lifecycle-and-seat-ledger.md), `.herdr-swarm/seats.json` tracks active seats. For worktree-isolated seats, the schema is extended to record `"worktree_dir"` and `"branch"`:

```json
{
  "workspace_id": "wM",
  "base_branch": "main",
  "seats": [
    {
      "name": "looper-kultivait",
      "kind": "agy",
      "pane": "wM:p1",
      "worktree_dir": "/path/to/target-repo",
      "branch": "main",
      "isolated": false
    },
    {
      "name": "arch-kultivait",
      "kind": "opencode",
      "pane": "wM:p2",
      "worktree_dir": "/path/to/target-repo/.herdr-swarm/worktrees/arch-kultivait",
      "branch": "swarm/kultivait/arch",
      "isolated": true
    }
  ]
}
```

### C. Seating & Worktree Provisioning Protocol
When provisioning an isolated worker seat:
1. Ensure parent directory `${TARGET_DIR}/.herdr-swarm/worktrees` exists and is ignored by `.gitignore`.
2. Check if branch `swarm/<slug>/<seat>` already exists:
   - If not, create branch and worktree:
     ```bash
     git -C "$TARGET_DIR" worktree add -q -b "swarm/${slug}/${seat}" "$worktree_dir" "$BASE_BRANCH"
     ```
   - If branch exists, attach to existing branch:
     ```bash
     git -C "$TARGET_DIR" worktree add -q "$worktree_dir" "swarm/${slug}/${seat}"
     ```
3. Spawn the Herdr pane with `--cwd "$worktree_dir"`.
4. Deliver brief referencing the worker's assigned worktree and branch.

### D. Safe Lifecycle Teardown (`swarm_down`)
When `swarm_down` executes:
1. **Interactive Confirmation**: Prompts the user before tearing down resources (honoring `-y` / `--yes`).
2. **Selective Pane Closure**: Closes the Herdr pane hosting the worker.
3. **Selective Worktree Pruning**:
   - For every seat where `"isolated": true` and `"worktree_dir"` is registered in `seats.json`:
     ```bash
     git -C "$TARGET_DIR" worktree remove --force "$worktree_dir" 2>/dev/null || true
     ```
   - Invokes `git -C "$TARGET_DIR" worktree prune` to clean dangling metadata.
4. **Root Tree Protection**:
   - Under no circumstances is `worktree remove` executed against the root working tree (`$TARGET_DIR`).
   - Worker branch refs (`swarm/<slug>/<seat>`) are **retained in Git history** until explicitly merged or pruned by the operator, ensuring work is never lost.

### E. Merge & Promotion Workflow
Before any worker's commits are integrated into the baseline branch:
1. **Independent Suite Gate**: The supervisor executes `TEST_CMD` inside that worker's specific `worktree_dir`.
2. **Verification Requirement**: A non-zero test count and exit code 0 (`suite == "green"`) must be recorded in `.herdr-swarm/session-verdicts.jsonl`.
3. **Arbiter Promotion**:
   - The orchestrator or human driver reviews the branch diff (`git diff main...swarm/<slug>/<seat>`).
   - If approved, merges into the base branch (via fast-forward merge, squash merge, or GitHub Pull Request).
   - Autonomous direct git pushes to remote origins remain strictly forbidden without explicit human driver approval.

---

## 5. Invariants & Safety Guarantees

1. **Root Directory Inviolability**: The primary repository root checkout is never checked out to a disposable task branch by automated workers.
2. **Strict Isolation**: No two workers ever share the same worktree directory or the same active branch simultaneously.
3. **Worktree Ledger Enforcement**: `swarm_down` prunes only directories explicitly recorded in `.herdr-swarm/seats.json` under `.herdr-swarm/worktrees/`.
4. **Git Object Database Sharing**: All worktrees share the common `.git` object store, eliminating disk duplication while providing full access to all historical commits and tags.
5. **Fail-Closed Integration**: Unverified branches or branches with `RED` suite gate verdicts are never promoted to the baseline branch.

---

## 6. Edge Cases and Mitigations

| Edge Case | Failure Risk | Mitigation |
|---|---|---|
| **Stale Worktree Lock** | Previous crash leaves `.git/worktrees/<seat>/locked` | Run `git worktree prune` during preflight matrix ([ADR 0005](0005-preflight-matrix-and-seat-verification.md)); remove stale lock files if agent is gone. |
| **Branch Divergence** | Baseline branch moves forward while worker is coding | Worker worktree pulls or rebases against `BASE_BRANCH` before final suite gating and PR submission. |
| **Dirty Worktree on Teardown** | Worker left uncommitted files in worktree | `git worktree remove --force` discards disposable working files; uncommitted state was not validated. Committed changes remain safe on the branch ref. |
| **Dependency Cache Duplication** | Sub-worktrees lack `node_modules` or `.venv` | Symlink shared cache directories from root or rely on global virtual environments/package caches (e.g. `uv`, `pnpm` store, `cargo` cache). |

---

## 7. Consequences

### Positive
- **True Concurrent Parallelism**: Multiple autonomous agents can build, test, and commit code simultaneously without cross-talk or lock contention.
- **Zero Risk to Operator Checkout**: The human driver's working branch and staged files in `$PWD` remain completely untouched.
- **Isolated Suite Testing**: Test suites run against the exact commit and file state produced by that specific worker.
- **Clean Audit Trail**: Every worker's progress is encapsulated in its own branch history prior to integration.

### Negative / Trade-offs
- **Disk Overhead**: Each worktree checks out a physical copy of working tree files (typically 5–50 MB for source files, excluding ignored build artifacts).
- **Environment Bootstrapping**: Language ecosystems that store local build artifacts in-tree (e.g. `node_modules`, virtualenvs) require linking or lightweight initialization when the worktree is created.
- **Arbiter Complexity**: Integrating multiple branches requires an arbitration step to detect and resolve semantic or merge conflicts before landing on the base branch.

---

## 8. References

- [Ticket T-016-docs: Worktree Isolation Architecture](../../maps/tickets/worktree-isolation-architecture.md)
- [ADR 0004: Safe Workspace Lifecycle and Seat Ledger](0004-safe-workspace-lifecycle-and-seat-ledger.md)
- [ADR 0005: Preflight Matrix and Seat Verification](0005-preflight-matrix-and-seat-verification.md)
- [Phase 2 Specification: docs/worktree-swarm.md](../worktree-swarm.md)
- Prototype Reference: `loop-bot-herd-claude/herdr-loop-claude-pm.sh` (external lineage — not part of this repo)
