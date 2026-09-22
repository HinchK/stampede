---
id: DOG-16
title: "Wire partition checking and path lease acquisition into supervisor dispatch"
type: wayfinder:task
status: resolved
commit: 280ae5f
assignee: arch-2
owns: loop-bot-herd.sh,lib/partition.sh,tests/test_partition.sh
parent: maps/public-readiness.md
github_issue: 63
github_url: "https://github.com/HinchK/stampede/issues/63"
synced_at: "2026-09-22T06:30:47Z"
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

## 6. Resolution (2026-09-21, `280ae5f`)

- `loop-bot-herd.sh` sources `lib/partition.sh` (orchestrator-only, same governance rule as the arbiter) and its dispatch path now runs `partition_check` → `lease_acquire` inside `cmd_dispatch` before any prompt: rc 0 leases and proceeds, rc 2 acquires an exclusive whole-repo lease or blocks, rc 1 blocks fail-closed with the holding lease and overlap paths logged. The ticket id comes from the brief's frontmatter (`id:`/`owns:`) or an explicit third argument; plain non-ticket briefs pass ungated.
- Release side: `lease_release_integrated` runs in every supervisor pass (`cmd_once`) and frees a lease only when `integration.jsonl` names the ticket `integrated`/`promoted`. Green/queued never releases (ADR 0012 §5, premature-release anti-pattern). Re-dispatch of a leased ticket is blocked like any overlap — re-briefing requires a deliberate `lease release`.
- Regression: `tests/test_partition.sh` sources the real supervisor and asserts the lifecycle end-to-end (17a–17h): acquire-on-dispatch, collision blocked with holder named, `cmd_dispatch` exit 1, re-dispatch blocked, exclusive fallback once idle, integrated-released/queued-held, promoted-released, unresolvable named ticket fail-closed, lease-free plain briefs. Suite grew 29 → 39 assertions.
- Receipts: `make check` — lint clean (14 shell files, 0 shellcheck warnings) and all 8 suites green (215 assertions, 0 failed), including `shellcheck loop-bot-herd.sh lib/partition.sh` clean.
