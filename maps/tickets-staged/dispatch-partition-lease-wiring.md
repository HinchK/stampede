---
id: DOG-16
title: "Wire partition checking and path lease acquisition into supervisor dispatch"
type: wayfinder:task
status: ready
assignee: arch
owns: loop-bot-herd.sh,lib/partition.sh,tests/test_partition.sh
parent: maps/public-readiness.md
---

# DOG-16 — Wire partition checking and path lease acquisition into supervisor dispatch

## 1. Intended Outcome

The supervisor's dispatch path (`loop-bot-herd.sh` / `cmd_dispatch()`) calls
`partition_check` and `lease_acquire` before prompting any worker, ensuring that
no two concurrent workers are ever dispatched with overlapping `owns:` paths,
and automatically releases leases when tickets are integrated or reaped.

## 2. Problem

`lib/partition.sh` was implemented in P3-2 and hardened against fresh-clone deadlocks
in DOG-11, but as documented in `maps/public-readiness.md`:
> "Hazard 1: partition_check / lease_acquire have no callers. File-overlap
> protection is NOT live. Ticket disjointness is enforced by the human releasing
> tickets in waves — never by co-dispatching and hoping."

Now that DOG-11 is resolved and verified in CI, `partition_check` gives accurate
verdicts on fresh clones. Wiring it into the supervisor turns file disjointness
from an advisory human discipline into an active, automated fail-closed invariant.

## 3. Scope

1. In `loop-bot-herd.sh`:
   - Source `lib/partition.sh`.
   - In dispatch path (`cmd_dispatch` or `frontier_drain`), run `partition_check "$ticket_file"`:
     - Return code `0` (disjoint): acquire lease via `lease_acquire "$ticket_file" "$worker"` and proceed with dispatch.
     - Return code `2` (no `owns:` declared): dispatch exclusively if no other leases are active; block if any lease is live.
     - Return code `1` (collision): block dispatch and log overlapping paths and holding workers.
   - When a ticket completes and merges (via arbiter or supervisor verdict reap), call `lease_release "$ticket_file"`.
2. Add end-to-end regression assertions in `tests/test_partition.sh` verifying dispatch rejection on overlapping candidate leases.
3. Clean under `shellcheck` with 0 warnings.
4. `make check` 100% green.

## 4. Done-Criteria

1. `partition_check` and `lease_acquire` are invoked directly in `loop-bot-herd.sh` dispatch flow.
2. Concurrent dispatch of conflicting tickets is blocked fail-closed.
3. `tests/test_partition.sh` verifies supervisor lease acquisition and release lifecycle.
4. All 8 test suites pass cleanly (`make check`).

## 5. Verification Step

```bash
make check
shellcheck loop-bot-herd.sh lib/partition.sh
```
