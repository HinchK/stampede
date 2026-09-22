# ADR 0012: Task Partitioning, File Disjointness, and Durable Ledger Leases

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [P3-2 Spec (Task Intake File Partition Checking)](../audits/2026-09-19-p3-2-task-partition-check-spec.md), [Ticket P3-2](../../maps/tickets/task-intake-partition-checking.md), [Phase 3 Fan-Out Roadmap](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md), [ADR 0006](0006-git-worktree-worker-isolation.md), [ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0011](0011-multi-worker-floor-topologies-and-concurrency.md)

---

## 1. Context and Problem Statement

Phase 3 introduces concurrent multi-worker execution ([ADR 0011](0011-multi-worker-floor-topologies-and-concurrency.md)), enabling multiple implementation seats (`arch-1`, `arch-2`) to implement tickets in parallel in isolated Git worktrees. In Phase 2, the Arbiter engine ([ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md)) established atomic Compare-and-Swap (CAS) ref updates and conflict rejection.

However, relying solely on merge-time conflict detection at the Arbiter stage introduces severe inefficiencies in a concurrent swarm:
1. **Wasted Agent Cycles & Token Burn**: If two workers concurrently spend 10–15 minutes modifying overlapping files, one worker's merge will succeed while the other will be rejected as a merge conflict. The rejected worker must rebase, reconcile conflicts, and re-run its test suites, wasting API tokens and execution time.
2. **Integration Queue Stalls**: Concurrent updates on overlapping files invalidate candidate merges, forcing the Arbiter queue to serialize, bisect, or stall.
3. **YAML Frontmatter Parser Vulnerability**: Existing lightweight tooling (such as [`lib/gh_sync.sh`](../../lib/gh_sync.sh)) parses ticket frontmatter line-by-line via simple string splitting (`line.split(":", 1)`). If multi-line YAML block sequences (`owns:\n  - file1\n  - file2`) were introduced, the parser would record `owns` as an empty string and drop all subsequent path lines, leading to silent partitioning failure.
4. **Host Filesystem Case Sensitivity Mismatches**: On macOS systems (APFS / HFS+), filesystems are case-insensitive by default. Naive case-sensitive string equality checks (e.g. `lib/Common.sh` vs `lib/common.sh`) would conclude paths are disjoint, resulting in silent filesystem collisions.
5. **Premature Lease Release on Verdict**: Releasing file locks when a worker emits a green verdict rather than when the Arbiter successfully merges the branch creates a critical race condition: a second worker could dispatch against a base commit that does not yet contain the first worker's changes, manufacturing base drift conflicts.

To solve these problems, task conflict checking must move from **merge-time cure to intake-time prevention**.

---

## 2. Decision Drivers

- **Zero-Conflict Concurrency Invariant**: Autonomous workers dispatched in parallel must be guaranteed to operate on disjoint subsets of the repository filesystem.
- **Fail-Closed Dispatch Gate**: Any ambiguity, invalid path specification, or overlap between a candidate task and active tasks must block concurrent dispatch.
- **Parser Resilience**: Frontmatter grammar must be robust against line-by-line POSIX shell and Python parsing without requiring complex YAML parsers.
- **Platform Filesystem Safety**: Path comparison must account for case-insensitive filesystems (macOS APFS default) to avoid silent collisions.
- **Durable Lease Lifecycle**: Task leases must persist across process restarts and remain active until code is merged into the integration ref, preventing stale base forking.
- **Smooth Backward Compatibility**: Existing tickets lacking explicit ownership declarations must not halt the swarm, but must fail closed into safe serialized execution.

---

## 3. Considered Options

- **Option A (Pure Merge-Time Rejection via Arbiter)**: Dispatch tasks freely without intake checks; let the Arbiter reject conflicting branches during merge. (Rejected: wastes substantial agent tokens and execution time; causes cascade rebases and integration bottlenecks).
- **Option B (Dynamic Filesystem Inotify/FSEvents Monitoring)**: Monitor actual file access during worker execution and abort the second worker dynamically. (Rejected: highly non-deterministic, platform-dependent, and aborts work halfway through execution).
- **Option C (Frontmatter `owns:` Declaration, Casefolded Over-Approximate Matching, and Durable Arbiter-Tied Leases)**:
  - Require a single-line comma-separated `owns:` frontmatter field in tickets.
  - Enforce casefolded, normalized, over-approximate path matching at dispatch time via `lib/partition.sh`.
  - Maintain durable atomic leases in `.herdr-swarm/leases.json`, released only upon Arbiter integration.
  - Fail-closed fallback: un-annotated tickets acquire exclusive whole-repo leases, running sequentially.

---

## 4. Decision

We adopted **Option C**. We establish the following architectural standards across task intake, ticket definitions, and swarm scheduling:

### A. Disjoint Path Ownership Invariant
For any two tickets $T_i$ and $T_j$ dispatched concurrently to implementation workers:
$$\text{owns}(T_i) \cap \text{owns}(T_j) = \emptyset$$

If a candidate ticket's declared paths overlap with any active ticket or held lease, dispatch is blocked. The ticket remains in `ready` or `backlog` status until the conflicting lease is released.

### B. Frontmatter Schema: Single-Line Comma-Separated `owns:`
To eliminate parser truncation hazards in line-by-line splitters (`lib/gh_sync.sh`), task ownership must be declared on a **single line with comma-separated, repository-relative paths**:

```yaml
---
id: P3-2
title: "Task Intake File Partition Checking"
status: in_progress
owns: lib/partition.sh,tests/test_partition.sh,docs/adr/
---
```

Supported entry types:
1. **Explicit File**: `lib/partition.sh` (matches exactly that file).
2. **Directory Prefix**: `docs/adr/` (trailing slash denotes the directory and all transitive children).
3. **Glob Pattern**: `tests/test_*.sh` (`fnmatch` pattern against repo-relative paths; `*` matches within directory, `**` crosses directories).

*Validation Rules*:
- Leading `./` is stripped; redundant slashes `//` are collapsed.
- Absolute paths (`/etc/passwd`) and directory traversals (`../outside`) are rejected fail-closed at intake.
- An empty `owns:` declaration (`owns: `) is rejected as a malformed ticket.
- Missing `owns` field invokes the fallback protocol (§4.E).

### C. Path Normalization, Casefolding, and Over-Approximate Matching
All path comparisons in `lib/partition.sh` execute under strict normalization and conservative over-approximation:

1. **Casefolding**: All paths are lowercased prior to comparison (`lower()`). This prevents false disjointness on case-insensitive filesystems like macOS APFS (`lib/Foo.sh` and `lib/foo.sh` correctly conflict).
2. **Over-Approximate Intersection Semantics**:
   - **File vs. File**: Paths are identical after normalization and casefolding.
   - **File vs. Directory Prefix**: File path begins with the directory prefix (`lib/` ⊃ `lib/partition.sh`).
   - **Directory vs. Directory**: Either directory is a prefix of the other (`lib/` ⊃ `lib/sub/`).
   - **Glob vs. File/Directory**: Evaluated via `fnmatch` against the working tree.
   - **Glob vs. Glob**: Two globs conflict if their **literal prefixes** (text before the first wildcard) overlap under the directory rule, OR if their expanded filesystem matches intersect. Any undecidable condition resolves to a conflict.

*Rationale for Over-Approximation*: A false conflict merely serializes task dispatch (costing concurrency throughput), whereas a missed conflict causes corrupt branch merges or failed arbiter gates.

```
┌─────────────────────────────────────────────────────────────┐
│ Intake Conflict Check (lib/partition.sh)                    │
├───────────────────────┬──────────────────────┬──────────────┤
│ Candidate Entry       │ Active Lease Entry   │ Result       │
├───────────────────────┼──────────────────────┼──────────────┤
│ lib/partition.sh      │ lib/partition.sh     │ ❌ Conflict   │
│ lib/partition.sh      │ lib/                 │ ❌ Conflict   │
│ lib/Foo.sh            │ lib/foo.sh           │ ❌ Conflict   │
│ lib/*.sh              │ lib/*.py             │ ❌ Conflict   │
│ docs/adr/             │ docs/audits/         │ ✓ Disjoint   │
│ lib/common.sh         │ tests/test_arbiter.sh│ ✓ Disjoint   │
└───────────────────────┴──────────────────────┴──────────────┘
```

### D. Durable Lease Protocol (`.herdr-swarm/leases.json`) and Integration-Tied Release
Active task leases are durably recorded in `.herdr-swarm/leases.json`:

```json
{
  "version": 1,
  "leases": [
    {
      "ticket": "P3-2",
      "seat": "arch-1-repo",
      "owns": ["lib/partition.sh", "tests/test_partition.sh", "docs/adr/"],
      "exclusive": false,
      "acquired_at": "2026-09-19T21:00:00Z",
      "branch": "swarm/repo/arch-1"
    }
  ]
}
```

- **Atomic Acquisition**: Lease checks and acquisitions occur in a single atomic critical section using a POSIX-compatible `mkdir` lock directory and temporary file rename (`mv`).
- **Integration-Tied Release Invariant**:
  A lease is **NOT released when a worker emits a green verdict** or when a ticket status becomes `resolved`.
  A lease is released **strictly when the Arbiter records the ticket as `integrated` or `promoted` in `integration.jsonl`** (or when the ticket is explicitly abandoned or the seat torn down).
  *Rationale*: If a lease were released upon green verdict, a second worker could immediately dispatch touching those files. Because the Arbiter may not yet have integrated the first worker's branch into `main`, the second worker would fork from a stale baseline lacking the first worker's commits, guaranteeing a downstream merge conflict.
- **Stale Lease Reconciliation**: During swarm status checks or startup, any lease held by a seat no longer registered in `seats.json` is logged as stale and safely purged.

### E. Fail-Closed Fallback for Legacy Tickets (Exclusive Serialization)
To support existing repositories and legacy tickets lacking `owns:` metadata without halting the swarm:
- A ticket without `owns:` is treated as owning the **entire repository** (`exclusive: true`).
- An exclusive ticket can only be dispatched when **zero other leases are currently held**.
- While an exclusive lease is active, **no other ticket may be dispatched**.
- The looper logs this event explicitly: `serialized: <ticket> declares no owns; acquiring exclusive lease`.
- Tooling (`lib/partition.sh suggest <ticket>`) analyzes branch diffs to generate suggested `owns:` lines for operator adoption.

### F. Post-Hoc Drift Auditing
To ensure agent declarations remain honest without introducing fragile pre-merge blocks:
1. Upon a green test suite verdict, the supervisor inspects the exact commit diff:
   ```bash
   git -C "$GATE_DIR" diff --name-only "$base_sha".."$sha"
   ```
2. Any modified file outside the declared `owns:` scope triggers an `owns_violation` event in telemetry and the supervisor log.
3. **Non-Blocking Principle**: An `owns_violation` does **not** block Arbiter integration or fail the test suite if tests passed. The Arbiter's atomic tree integration remains the ultimate correctness gate. The violation is surfaced to the operator and recorded in the audit trail to correct ticket frontmatter.

---

## 5. Invariants & Safety Guarantees

1. **Disjoint Ownership Invariant**: No two concurrent tasks may hold intersecting path leases.
2. **Integration-Tied Lease Invariant**: A task lease must remain active until its branch is integrated into the baseline ref or the seat is torn down; a green test verdict alone does not release a lease.
3. **Atomic Acquisition Invariant**: Conflict inspection and lease reservation must occur within a single locked atomic section to prevent dispatch TOCTOU races.
4. **Platform Casefolding Invariant**: All path comparisons must lowercase paths to guarantee safety on case-insensitive filesystems.
5. **Over-Approximate Glob Invariant**: Ambiguous glob intersections must resolve to conflict, choosing conservative serialization over corrupted merges.
6. **Exclusive Un-annotated Invariant**: Any ticket lacking `owns:` must acquire an exclusive lease and execute strictly alone.

---

## 6. Consequences

### Positive
- **Guaranteed Conflict-Free Merges**: Parallel workers are mathematically prevented from modifying overlapping files, eliminating Arbiter merge conflicts.
- **Token and Compute Efficiency**: Eliminates wasted agent loops spent implementing changes that would subsequently fail at merge time.
- **Durable Crash Resilience**: `.herdr-swarm/leases.json` survives daemon and supervisor restarts.
- **Safe Evolutionary Adoption**: Un-annotated tickets run sequentially without failure, allowing teams to incrementally adopt `owns:` annotations.

### Negative / Trade-offs
- **Over-Approximation Penalties**: Conservative glob and prefix rules may occasionally serialize tasks that could theoretically have been merged cleanly.
- **Annotation Overhead**: Ticket authors or loop chartering agents must identify and specify repo-relative target paths in frontmatter.
- **Exclusivity Bottlenecks**: A single un-annotated ticket holding an exclusive lease temporarily reduces swarm concurrency to 1.

---

## 7. References

- [P3-2 Spec: Task Intake File Partition Checking](../audits/2026-09-19-p3-2-task-partition-check-spec.md)
- [Ticket P3-2: Task Intake Partition Checking and Ledger Lease Protocol](../../maps/tickets/task-intake-partition-checking.md)
- [Phase 3 Fan-Out Roadmap](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md)
- [ADR 0006: Git Worktree Worker Isolation and Lifecycle Management](0006-git-worktree-worker-isolation.md)
- [ADR 0007: Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2](0007-split-pane-cwd-order-and-ledger-v2.md)
- [ADR 0008: Supervisor Worktree Suite Gating, Provenance, and Drift Detection](0008-supervisor-worktree-suite-gating-and-drift.md)
- [ADR 0009: Arbiter Branch Integration, Compare-and-Swap Ref Updates, and Human Promotion Gates](0009-arbiter-branch-integration-and-cas-merge.md)
- [ADR 0011: Multi-Worker Floor Topologies, Worktree Namespacing, and Heterogeneous Concurrency](0011-multi-worker-floor-topologies-and-concurrency.md)
