---
id: P3-2
title: "Task Intake Partition Checking and Ledger Lease Protocol"
type: wayfinder:prototype
status: resolved
commit: 1992e37
assignee: arch
prototype_asset: lib/partition.sh,tests/test_partition.sh
owns: lib/partition.sh,tests/test_partition.sh,docs/adr/0012-task-partitioning-and-disjoint-dispatches.md
parent: maps/universal-herdr-swarm.md
---

# Task Intake Partition Checking and Ledger Lease Protocol (P3-2)

## Context & Problem Statement

In Phase 3 multi-worker concurrent execution, multiple workers (`arch-1`, `arch-2`) run in parallel. To prevent merge conflicts before workers are dispatched, the swarm must verify file path disjointness (`owns`) between concurrently running tasks.

Per [Phase 3 Roadmap](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md) §1.2:
- Each ticket specifies an `owns:` list in YAML frontmatter representing repo-relative paths or directory prefixes.
- Invariant: For any two concurrently dispatched tickets $T_i, T_j$, $\text{owns}(T_i) \cap \text{owns}(T_j) = \emptyset$.
- Leases are recorded in `.herdr-swarm/seats.json` or `.herdr-swarm/leases.json` and released upon arbiter merge or seat teardown.
- Fail-closed: Any ticket with no `owns` field is treated as owning the whole repository and is dispatched alone.

## Preamble

1. **Intended Outcome**: `arch` implements `lib/partition.sh` and unit tests in `tests/test_partition.sh` to validate task path partitioning and manage active path leases.
2. **Explicit Done-Criteria**:
   - `lib/partition.sh`:
     - `partition_check <ticket_file> [active_leases_json]`: Returns 0 if candidate ticket does not overlap with any active lease, non-zero otherwise.
     - Detects exact file matches and directory prefix overlaps (e.g. `src/api/` vs `src/api/routes.py`).
     - Rejects tickets missing `owns:` if any other task is active (fail-closed singleton dispatch).
     - `lease_acquire` and `lease_release` functions to track active leases in `.herdr-swarm/leases.json`.
   - Quality checks:
     - `shellcheck lib/partition.sh tests/test_partition.sh` passes cleanly with 0 warnings.
     - `bash tests/test_partition.sh` passes 100%.
3. **Verification Step**:
   - Run `bash tests/test_partition.sh`.
   - Run `shellcheck lib/partition.sh`.
