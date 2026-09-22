# ADR 0007: Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [ADR 0004](0004-safe-workspace-lifecycle-and-seat-ledger.md), [ADR 0006](0006-git-worktree-worker-isolation.md), [P2-2 Configuration Integration Spec](../audits/2026-09-19-p2-2-config-integration-spec.md), [Phase 2 PM Worktree Advisory](../audits/2026-09-19-phase2-worktree-advisory.md)

---

## 1. Context and Problem Statement

During Phase 2 implementation planning and architectural specification for Git worktree worker isolation ([P2-2 Specification](../audits/2026-09-19-p2-2-config-integration-spec.md)), three critical operational insights emerged regarding Herdr CLI semantics, worktree teardown safety, and seat state accounting:

1. **Herdr Pane CWD Binding Semantics (Correction C1)**:
   In the Herdr terminal multiplexer, `herdr pane split` accepts `--cwd <dir>`, but `herdr agent start` **has no `--cwd` argument**. An agent hosted in a pane strictly inherits the pane's initial working directory at creation time. If the swarm launcher splits a pane *before* provisioning the worktree, the pane is created in the repository root (`$TARGET_DIR`). Once created, the pane's working directory cannot be changed via Herdr agent start commands. The agent is seated in the root working tree, completely violating the isolation boundary and risking shared checkout collisions.
2. **Destructive Teardown Risk in ADR 0006 (Amendment A1)**:
   [ADR 0006 §4.D.3](0006-git-worktree-worker-isolation.md) originally specified that `swarm_down` would execute `git worktree remove --force "$worktree_dir"`. Using `--force` unconditionally discards uncommitted file modifications if an agent crashes, stalls, or is interrupted mid-task. This contradicts the fundamental safety guarantee that "work is never lost." Git's native refusal to remove a dirty worktree is an essential safety net that must be respected.
3. **Stale Branch Contamination (Amendment A2)**:
   [ADR 0006 §4.C.2](0006-git-worktree-worker-isolation.md) originally specified: "if branch exists, attach." Because branch names are seat-scoped (`swarm/<slug>/<seat>`), branches persist across swarm runs. Silently attaching to a pre-existing branch from an earlier run hands the worker stale, unintegrated commits, leading to spurious merge conflicts and dirty baselines (Hazard H3).
4. **State Schema Limitations (Ledger v1)**:
   The v1 seat ledger (`.herdr-swarm/seats.json`) defined in [ADR 0004](0004-safe-workspace-lifecycle-and-seat-ledger.md) tracked only `workspace_id` and `{name, kind, pane}`. It lacked fields to record worktree paths, branch names, baseline commit SHAs, or isolation flags, preventing downstream tooling (`loop-bot-herd.sh` and `swarm_down`) from determining where each seat executes and which worktrees require lifecycle management.

---

## 2. Decision Drivers

- **Strict CWD Binding**: Herdr panes must be initialized directly inside the worker's assigned worktree directory.
- **Data Loss Prevention**: Swarm teardown must never delete or prune uncommitted work. Dirty worktrees must be preserved and reported to the operator.
- **Stale Baseline Protection**: A worker must never unknowingly build on stale commits from an unmerged, prior run.
- **Unified Seat Accounting**: Downstream supervisors, status inspectors, and teardown scripts must query a single, structured schema to locate the exact working directory and branch for every seat.
- **Backward Compatibility**: Existing v1 ledgers must be parsed gracefully without breaking running swarms or status checks.

---

## 3. Considered Options

- **Option A (Late CWD Switching via Prompt / `cd`)**: Split pane in root, then send `cd <worktree>` to the shell or agent prompt. (Extremely fragile: races with agent boot scripts, fails if prompt input fails, and pollutes shell command history).
- **Option B (Ad-Hoc Worktree Tracking in Separate Files)**: Keep `seats.json` as v1 and store worktree paths in separate `.herdr-swarm/worktrees.json` or environment files. (Fragmented state, split-brain failure windows during partial crashes).
- **Option C (Strict Ordering, Safe Teardown, and Ledger Schema v2)**: Enforce `worktree_provision` before `split_pane`, require clean worktrees for `down`, gate stale branches, and upgrade `.herdr-swarm/seats.json` to schema v2.

---

## 4. Decision

We adopted **Option C**. We establish the following architectural rules:

### A. Strict Ordering: Provisioning Precedes Pane Creation (Correction C1)
The seating sequence in `herdr-loop-swarm.sh` must strictly adhere to the following order per seat:

```
[Seat Loop]
     │
     ▼
[1. Check agent_alive "$seat_name"] ──(Alive)──> [Reuse existing ledger entry, SKIP]
     │ (Not seated)
     ▼
[2. Worktree Evaluation]
     ├── If SEAT_WORKTREE == 1:
     │     seat_cwd = worktree_provision("$TARGET_DIR", "$SLUG", "$SEAT_KEY", "$SEAT_NAME", "$BASE_BRANCH")
     └── Else:
           seat_cwd = "$TARGET_DIR"
     │
     ▼
[3. Pane Creation (CWD Bound Here)]
     seat_pane = split_pane(anchor, direction, ratio, "$seat_cwd")
     │
     ▼
[4. Start Agent in Pane]
     herdr agent start "$seat_name" --kind "$kind" --pane "$seat_pane"
     │
     ▼
[5. Record Ledger Entry in seats.json v2]
```

Because `split_pane` receives `seat_cwd`, the newly created terminal pane initializes directly inside the provisioned worktree. When `herdr agent start` attaches to the pane, the agent process naturally inherits the worktree directory as its working directory.

### B. Safe Worktree Teardown without `--force` (Amendment A1)
During `swarm_down`:
1. Swarm-managed panes are closed first.
2. For isolated seats (`isolated == true`), `swarm_down` executes:
   ```bash
   git -C "$TARGET_DIR" worktree remove "$worktree_dir"
   ```
   **WITHOUT `--force`**.
3. **Dirty Tree Handling**: If the worktree contains uncommitted changes, Git refuses removal with a non-zero exit code. `swarm_down` intercepts this refusal, leaves the worktree locked, and prints an explicit warning under "Retained Work" with the path for operator inspection.
4. **Pruning**: `git -C "$TARGET_DIR" worktree prune` is called only after clean worktrees are removed.

### C. Stale Branch Re-attach Gate (Amendment A2)
When `worktree_provision` encounters an existing branch `swarm/<slug>/<seat>`:
1. It verifies whether the branch has unmerged commits ahead of `BASE_BRANCH`:
   ```bash
   unmerged_count=$(git -C "$TARGET_DIR" rev-list --count "$BASE_BRANCH..$branch")
   ```
2. If `unmerged_count == 0` (clean), or if the previous `seats.json` recorded that exact branch for this seat (active resume), the worktree attaches safely.
3. If `unmerged_count > 0` and this is a fresh launch, `worktree_provision` **fails closed** for that seat:
   ```
   ERROR: Stale branch swarm/<slug>/<seat> (N commits not on <base>).
   Pass --adopt-branches to proceed, or delete the branch.
   ```

### D. Seat Ledger Schema v2 Specification
`.herdr-swarm/seats.json` is formalized as a versioned, atomic document:

```json
{
  "version": 2,
  "workspace_id": "wM",
  "base_branch": "main",
  "base_sha": "903fb2d",
  "created_at": "2026-09-19T13:40:00Z",
  "seats": [
    {
      "name": "looper-kultivait",
      "kind": "agy",
      "pane": "wM:p1",
      "isolated": false,
      "worktree_dir": "/path/to/target-repo",
      "branch": "main",
      "branch_created": false,
      "provisioned_at": "2026-09-19T13:40:00Z"
    },
    {
      "name": "arch-kultivait",
      "kind": "opencode",
      "pane": "wM:p2",
      "isolated": true,
      "worktree_dir": "/path/to/target-repo/.herdr-swarm/worktrees/arch-kultivait",
      "branch": "swarm/kultivait/arch",
      "branch_created": true,
      "provisioned_at": "2026-09-19T13:40:00Z"
    }
  ]
}
```

#### Schema Invariants:
1. `version`: Literal integer `2`. Unversioned ledgers are treated as v1.
2. `worktree_dir`: Mandatory on **all seats**. For root seats (`isolated: false`), it points to canonical `$TARGET_DIR` (`pwd -P`). This ensures a single code path for resolving seat directories.
3. `isolated`: Boolean indicating whether the seat operates in an isolated worktree.
4. `branch_created`: Boolean indicating whether this launch created the branch ref.
5. **Atomic Writes**: Written via temporary file (`mktemp`) and atomic `mv` inside `.herdr-swarm/` to prevent partial reads during agent crashes.

---

## 5. Backward Compatibility (v1 $\to$ v2)

Any ledger lacking a `"version"` property is treated as a v1 ledger:
- Readers (`lib/lifecycle.sh`, `herdr-loop-swarm.sh status`, `verify`) synthesize default values for v1 records:
  ```json
  {"isolated": false, "worktree_dir": "<target_dir>", "branch": "<base_branch>"}
  ```
- Existing v1 ledgers are never rewritten in place; the next execution of `herdr-loop-swarm.sh up` automatically produces a clean v2 ledger.

---

## 6. Consequences

### Positive
- **Guaranteed Worker Isolation**: Agents are guaranteed to execute in their designated worktrees from their first shell command, with zero risk of unisolated startup.
- **Zero Accidental Work Loss**: Uncommitted worker progress is never deleted during swarm teardown.
- **Protection from Stale Code**: Stale branch detection prevents workers from accidentally reviving obsolete, failing commits from earlier experiments.
- **Unified State API**: `loop-bot-herd.sh` resolves the exact execution directory for test suite gates by querying `.seats[] | select(.name == $seat).worktree_dir`, preventing false-green passes against the root repository.

### Negative / Trade-offs
- **Operator Remediation**: When a dirty worktree or stale branch is detected, the operator must manually inspect, commit, or clean the branch before re-running with that seat. (This manual step is intentional to prevent silent data loss).
