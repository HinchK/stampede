---
id: DOG-11
title: "Fresh-clone partition deadlock: gitignored integration evidence marks every resolved ticket an active lease-holder"
type: wayfinder:defect
status: in_progress
assignee: arch-2
owns: lib/partition.sh,tests/test_partition.sh
parent: maps/public-readiness.md
github_issue: 25
github_url: "https://github.com/HinchK/stampede/issues/25"
synced_at: "2026-09-22T03:16:07Z"
---

# DOG-11 — Partition check deadlocks a fresh clone (WAVE 4)

## 1. Intended Outcome

`partition_check` gives correct answers in a fresh clone, so it can be wired
into the dispatch path (a standing fog item this ticket unblocks).

## 2. Problem

`.herdr-swarm/` is gitignored, so a fresh clone has no `integration.jsonl`.
Without integration evidence, `partition_check` counts **resolved** tickets as
active lease-holders — all ~47 of them — and blocks every dispatch. The
failure was found during bootstrap, before the loop ran (first dogfood
finding).

## 3. Scope

- Inactive determination must not depend on gitignored state. A ticket whose
  frontmatter says `resolved`/`done`/`closed` is inactive **unless** live
  contrary evidence exists (in-progress lease, recent un-merge), never the
  other way around. Missing evidence is not activity.
- Fail-open applies to resolved tickets ONLY: `in_progress` and `backlog`/
  `ready` tickets keep today's strict behaviour unchanged.
- Emit a one-line warning when integration evidence is absent, so a genuinely
  wiped `.herdr-swarm/` is visible rather than silently forgiven.
- Reproduction pinned as a test: scratch repo, resolved tickets, no
  `.herdr-swarm/` → candidate with disjoint `owns:` dispatches (rc=2 path),
  and a no-owns candidate is not buried by phantom leases from resolved
  tickets.

## 4. Done-Criteria

1. Fresh-clone repro (no `.herdr-swarm/`) no longer blocks disjoint
   dispatches.
2. All 26 existing partition assertions still pass; new assertions for the
   above.
3. `make check` green; 0 shellcheck warnings.

## 5. Verification Step

```bash
make test
bash tests/test_partition.sh
```
