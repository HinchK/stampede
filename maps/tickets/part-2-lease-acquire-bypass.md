---
id: PART-2
title: "lease_acquire() doesn't re-run the ownership/active-ticket check that check performs"
type: wayfinder:defect
status: resolved
assignee: arch
owns: lib/partition.sh,tests/test_partition.sh
parent: maps/close-the-gaps.md
---

# PART-2 -- lease acquire bypasses the check verdict

**Severity:** MED -- allowed a real dispatch (`PROVE-HEADLESS-1`) to proceed after `bash lib/partition.sh check`
had already reported BLOCKED, on the strength of a narrower command that doesn't enforce the same rule. No harm
resulted this time (the underlying ownership conflict was itself a false positive, see `PART-1`), but the gap is
real and would let a *genuine* conflict through too.
**Found by:** looper, self-reported 2026-09-30 during forensic review of how `PROVE-HEADLESS-1` reached
`arch-2-hinchk-stampede` before `PART-1` was promoted to `main`.

## Root Cause

`bash lib/partition.sh check <ticket>` runs `_partition_ticket_active()` against every ticket in `maps/tickets/`
to check for an overlapping `owns:` claim. `lease acquire <ticket> <worker> <branch> <paths>` does not call this
-- it only checks `.herdr-swarm/leases.json` for currently-held *live* leases. A ticket can therefore fail
`check` (BLOCKED by another ticket's ownership claim) and still succeed at `lease acquire`, because the two
commands enforce different, non-overlapping rules. Whatever drives real dispatch decisions must not be able to
call `lease acquire` in isolation and treat a clean exit as equivalent to a passing `check`.

## Done-Criteria

1. `lease_acquire()` internally re-runs (or requires having already run) the same ownership/active-ticket check
   `check` performs, and refuses with a clear error if it would conflict -- not just a `leases.json` scan.
2. New test coverage: a ticket that `check` reports BLOCKED cannot successfully `lease acquire` even when
   `leases.json` shows no live conflict.
3. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_partition.sh
```

## Notes

Standing-rule correction alongside this: `check`'s verdict is authoritative. If it reports BLOCKED, that is the
answer -- do not look for a narrower command whose scope happens not to enforce the same rule and treat its
success as permission. This applies regardless of whether the underlying conflict turns out to be a false
positive (as `PART-1`'s was) -- the check must be trusted or fixed, never routed around.

## Resolution

- **Implementation**:
  - `lib/partition.sh`: Factored active-ticket ownership conflict logic into `_partition_active_conflicts()` so both `partition_check` and `lease_acquire` enforce the identical rule.
  - `lease_acquire` runs the conflict check before taking the lease lock and before modifying `leases.json`, refusing with a clear error without creating any lease or lock residue.
  - Excluded the ticket being acquired (`skip_id`) so leasing one's own in-progress ticket remains valid as the normal dispatch flow.
- **Suite Gate**: `tests/test_partition.sh` Section 18 (+6 tests, 47/47 passing) covering explicit/implicit blocked acquire refusal, no lease written, and unblocking upon ticket transition to superseded; `make check` all 19 suites green, 0 shellcheck warnings.
- **Review**: Autonomous Reviewer Loop PASS verdict by `reviewer-hinchk-stampede` (Round 1/2) in `.herdr-swarm/reviews/PART-2-a2af844260633750c11a877b8c68233c85d97652.md`.
- **Integrated**: Integrated onto `swarm/stampede/integration` at `9905b54` on top of `PART-1` (`c4603eb`). Lease released cleanly.

