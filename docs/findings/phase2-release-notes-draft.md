# Universal Herdr Swarm — Phase 2 Release Notes & Migration Guide

**Release Version:** `v0.2.0-phase2`  
**Date:** 2026-09-19 · **Author:** `agy-gh` · **Status:** Draft / Accepted Release Candidate  
**Master Roadmap:** [`maps/universal-herdr-swarm.md`](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/universal-herdr-swarm.md)  
**Associated Architecture Decisions:**  
- [ADR 0006: Git Worktree Worker Isolation](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0006-git-worktree-worker-isolation.md)  
- [ADR 0007: Split-Pane CWD Order and Durable Seat Ledger v2](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md)  
- [ADR 0008: Supervisor Worktree Suite Gating and Drift Detection](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0008-supervisor-worktree-suite-gating-and-drift.md)  
- [Phase 2 Architecture Specification (`docs/worktree-swarm.md`)](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/worktree-swarm.md)  
- [GitHub Issues Two-Way Synchronization Protocol (`docs/findings/github-issues-sync.md`)](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/github-issues-sync.md)  
- [Phase 2 Release Verification Checklist (`docs/findings/phase2-release-checklist.md`)](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/phase2-release-checklist.md)

---

## 1. Executive Summary

Milestone 1 established the foundation for project-agnostic autonomous swarms: fail-closed profile detection, dynamic TOML configuration registries, agent slug namespacing, templated brief delivery via nonce exchange, and safe workspace lifecycle management. However, Milestone 1 operated sequentially: all agents ran in the root repository checkout (`$TARGET_DIR`) on a single branch, risking file edit collisions, branch checkout conflicts, and Git index lock contention.

**Phase 2 (`v0.2.0-phase2`)** elevates the swarm into a **concurrent, parallel worker orchestrator**. Using native Git worktree isolation, worker agents (`arch`, sub-agents) develop simultaneously in isolated checkouts without file collisions or lock contention. Completed worktree branches are gated in their specific branch context with Time-of-Check to Time-of-Use (TOCTOU) drift detection, reconciled via a deterministic Compare-and-Swap (CAS) Arbiter merge engine, and synchronized bi-directionally with upstream GitHub Issues.

---

## 2. Phase 2 Feature Set

### A. Native Git Worktree Worker Isolation (ADR 0006)
- **Multi-Tenant Floor Plan:**
  - **Root Workspace (`$TARGET_DIR`):** Reserved exclusively for the master orchestrator (`looper`), strategic overseer (`pm`), and the live telemetry ANSI streaming pane (`lib/telemetry.py`). Checked out on the base branch (`main`).
  - **Worker Worktrees:** Seated coding agents operate within dedicated checkouts under `${TARGET_DIR}/.herdr-swarm/worktrees/<seat>`.
- **Branch Namespacing & Isolation:** Worker branches conform to `swarm/<slug>/<seat>`, ensuring zero branch namespace collisions across multiple repositories or swarms.
- **Live Seat Lock Markers:** Every provisioned worktree is locked via `git worktree lock --reason "seated: <seat>"`, guaranteeing it survives external background `git worktree prune` routines.
- **Uncommitted Work Preservation:** Pruning a worktree automatically checkpoints dirty tracked changes using `git add -u` (never `-A` to prevent capturing untracked build noise) and tags `swarm/<slug>/<seat>-checkpoint-<timestamp>`. Branches survive worktree directory deletion, ensuring operator work is never destroyed.

### B. Durable Seat Ledger v2 Schema (ADR 0007)
The seat ledger (`.herdr-swarm/seats.json`) is upgraded from v1 to schema v2, establishing a single source of truth for runtime directories, branch tracking, and isolation boundaries:

```json
{
  "schema_version": 2,
  "workspace_id": "wM",
  "project_slug": "preview",
  "target_dir": "/Users/hinchk/Fun/loop-bot-herd-agy",
  "seats": [
    {
      "key": "arch",
      "name": "arch-preview",
      "kind": "opencode",
      "pane": "wM:p3",
      "isolated": true,
      "worktree_dir": "/Users/hinchk/Fun/loop-bot-herd-agy/.herdr-swarm/worktrees/arch",
      "branch": "swarm/preview/arch",
      "base_sha": "0cfae5d18e47"
    },
    {
      "key": "looper",
      "name": "looper-preview",
      "kind": "agy",
      "pane": "wM:p1",
      "isolated": false,
      "worktree_dir": "/Users/hinchk/Fun/loop-bot-herd-agy",
      "branch": "main",
      "base_sha": "0cfae5d18e47"
    }
  ]
}
```

### C. Launcher Pre-Split CWD Binding (Correction C1)
In the Herdr terminal multiplexer, `herdr pane split` accepts `--cwd <dir>`, but `herdr agent start` has no CWD parameter. If a pane is split before worktree provisioning, the agent strictly inherits the root directory, defeating isolation.
- Phase 2 enforces strict ordering in `herdr-loop-swarm.sh`: `worktree_provision` runs **before** `split_pane`.
- The target worktree path is passed directly to `split_pane`, guaranteeing the agent shell physically spawns inside the isolated checkout.

### D. Supervisor Worktree Suite Gating & TOCTOU Drift Detection (ADR 0008)
- **Elimination of False-Green Testing:** `loop-bot-herd.sh` queries `.herdr-swarm/seats.json` v2 via `resolve_seat_gate "$seat"`. The test suite runner executes `TEST_CMD` inside `GATE_DIR` (`worktree_dir`), never in the root checkout.
- **Fail-Closed Resolution:** If an isolated seat's worktree directory is missing or detached, the supervisor marks the verdict `suite: "unresolvable"` and alerts the human operator; it **never** falls back to `$REPO_DIR`.
- **3-Point Commit Provenance:** Verifies that the declared commit SHA exists in the Git object store, resides on `GATE_BRANCH` ancestry, and represents at least one commit ahead of the baseline (`own_commits >= 1`).
- **Pre-Condition Drift Check:** Prior to testing, checks that `HEAD == sha` and `git status --porcelain` is completely clean (including untracked files). If dirty, records `suite: "stale"`.
- **Post-Condition Drift Check:** Following test execution, re-verifies that the working copy was not modified while tests ran. If mutated, records `suite: "invalidated"`.
- **Deduplication & Retirement:** Redundant runs of `(ticket, sha)` are skipped; only genuine `suite: "green"` passes retire tickets.

### E. Deterministic Arbiter CAS Merge Engine (P2-4 Spec)
- **Serialized Shell Integration (`lib/arbiter.sh`):** Operates on integration-eligible records from `session-verdicts.jsonl` (isolated, green, provenance-verified).
- **Compare-and-Swap (CAS) Update:** Builds merge commits in a dedicated detached worktree (`.herdr-swarm/worktrees/arbiter-<slug>`) and advances `swarm/<slug>/integration` using `git update-ref <ref> <new> <expected-old>`.
- **Integration Suite Gating:** Re-executes `TEST_CMD` against the combined integration branch before updating references.
- **Human-Gated Promotion:** Final promotion to `main` is handled via operator `--ff-only` merge or synthesized GitHub Pull Requests.
- **Default-Off Safety:** Controlled via `control.json` (`arbiter_on` / `arbiter_off`), remaining disabled by default until explicitly enabled.

### F. GitHub Issues Two-Way Synchronization (`lib/gh_sync.sh`)
- **Zero Unconfirmed Writes:** Defaults to `--dry-run`, presenting a full reconciliation diff without touching remote GitHub Issues or mutating local markdown files.
- **Frontmatter Lineage Anchoring:** Upon `--apply`, links GitHub Issues with local `maps/tickets/*.md`, recording `github_issue`, `github_url`, and `synced_at`.
- **External PR Reconciliation:** Pulls upstream status changes (e.g. PR merged on GitHub with `Closes #42`) and marks local tickets `status: resolved`.

---

## 3. Breaking Changes & Compatibility

### Breaking Changes
1. **Seat Working Directory Context:** Worker seats marked with `worktree = true` run in `.herdr-swarm/worktrees/<seat>`. Scripts or commands assuming `$PWD` is the repository root must be made directory-agnostic or reference root via Git top-level (`git rev-parse --show-toplevel`).
2. **Worktree Removal Replaces Blanket Deletion:** Teardown no longer runs blind `rm -rf` on working copies. Dirty worktrees require explicit operator confirmation or checkpointing.
3. **Supervisor Verdict Anchoring:** Verdicts must match exact regex anchoring `^ARCH DONE #([0-9]+) ([0-9a-f]{7,40})$`. Freeform or un-anchored terminal mentions will not trigger suite evaluation.

### Configuration Syntax (`swarm.config.toml`)
Enable worktree isolation per seat by adding `worktree = true`:

```toml
[swarm]
name = "my-project"
worktree_root = ".herdr-swarm/worktrees" # Optional: default path

[seats.arch]
name = "arch"
role = "Lead Architect & Implementation Engine"
default_kind = "opencode"
model = "zai/glm-5.3"
brief = "briefs/arch.md"
tab = "herd"
position = "top-right"
worktree = true   # <--- Phase 2 Worktree Isolation Toggle

[seats.looper]
name = "looper"
role = "Loop Orchestrator"
default_kind = "agy"
model = "gemini-2.5-pro"
brief = "briefs/looper.md"
tab = "herd"
position = "bottom-full"
worktree = false  # <--- Root workspace seat (default)
```

### Backward Compatibility Guarantees (v1 Seats)
- **Omitted `worktree` Flag:** Any seat omitting `worktree = true` defaults to `worktree = false` and continues running in `$TARGET_DIR` on `main`.
- **v1 Ledger Compatibility:** `lib/lifecycle.sh` and `loop-bot-herd.sh` parse v1 `seats.json` ledgers gracefully, treating all seats as root seats (`isolated = false`, `worktree_dir = TARGET_DIR`).
- **Milestone 1 Swarms:** Repositories without worktree configuration run exactly as they did in Milestone 1.

---

## 4. Operational Verification Command Recipes

### Recipe 1: Verify Worktree Lifecycle Suite
Runs the 21-point automated worktree lifecycle test suite in an isolated scratch repository:
```bash
bash tests/test_worktree.sh
# Expected: "21 passed, 0 failed"
```

### Recipe 2: Inspect Seating Topology & Worktree Plan
Preview the runtime seating layout and worktree allocation without launching agents:
```bash
bash lib/config.sh plan
# Expected: Markdown table displaying 'Worktree: yes' for arch and 'no' for others.
```

### Recipe 3: Execute Preflight 9-Point Matrix
Run the fail-closed preflight dependency and environment verification:
```bash
./lib/preflight.sh
# Expected: All 9 checks pass with exit code 0.
```

### Recipe 4: Verify Live Swarm Seating & Nonce Delivery
Verify that all seated agents are running, idle, and have received rendered briefs:
```bash
./herdr-loop-swarm.sh verify [TARGET_DIR]
# Expected: Verification table shows all seats 'idle' and briefs acknowledged.
```

### Recipe 5: Execute Supervisor Suite Gate Check
Evaluate worktree-scoped suite gating and TOCTOU drift detection:
```bash
./loop-bot-herd.sh once
# Expected: Harvests verdicts, runs test in GATE_DIR, emits suite.verdict telemetry event.
```

### Recipe 6: Dry-Run GitHub Issues Synchronization
Inspect pending ticket creations and status reconciliation against GitHub without writes:
```bash
# Full repository dry-run:
bash lib/gh_sync.sh --dry-run maps/tickets

# Filtered to specific tickets:
bash lib/gh_sync.sh --dry-run maps/tickets --ticket "P2-1,P2-2,P2-3,P2-4"
# Expected: Lists planned [CREATE] / [LINK] / [UPDATE] actions; confirms 0 writes executed.
```

### Recipe 7: Execute Safe Swarm Teardown
Cleanly shut down panes and prune worktrees while checkpointing uncommitted work:
```bash
./herdr-loop-swarm.sh down [TARGET_DIR] -y
# Expected: Retires only swarm panes; checkpoints dirty worktrees; leaves main intact.
```

---

## 5. Migration Guide: Upgrading a Swarm to Phase 2

Follow these steps to upgrade an existing Milestone 1 swarm repository to Phase 2:

1. **Pull Release Tag:**
   Ensure repository codebase includes `v0.2.0-phase2`.
2. **Update `.gitignore`:**
   Verify that `.herdr-swarm/` is ignored so worktrees and session ledgers do not pollute git status:
   ```bash
   grep -q ".herdr-swarm/" .gitignore || echo ".herdr-swarm/" >> .gitignore
   ```
3. **Configure Worktrees in `swarm.config.toml`:**
   Add `worktree = true` under `[seats.arch]` or any parallel worker seat.
4. **Validate Topology:**
   Run `bash lib/config.sh plan` and ensure worktree assignments reflect your configuration.
5. **Run Preflight Matrix:**
   Execute `./lib/preflight.sh` to confirm Git, Herdr, and GitHub CLI prerequisites.
6. **Launch Phase 2 Swarm:**
   ```bash
   ./herdr-loop-swarm.sh up [TARGET_DIR]
   ```
7. **Perform Issue Synchronization:**
   ```bash
   bash lib/gh_sync.sh --apply maps/tickets
   ```
