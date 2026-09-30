---
id: PART-1
title: "Partition ownership check treats superseded tickets as still active, false-blocking disjoint dispatch"
type: wayfinder:defect
status: backlog
assignee: arch
owns: lib/partition.sh,tests/test_partition.sh
parent: maps/close-the-gaps.md
github_issue: 82
github_url: "https://github.com/HinchK/stampede/issues/82"
synced_at: "2026-09-30T17:14:49Z"
---

# PART-1 -- superseded status not recognized by ownership check

**Severity:** LOW-MED -- no data loss or false-green risk (opposite direction of ARB-SLUG-1: this fails closed too
*aggressively*, blocking legitimate dispatch rather than letting something unsafe through), but it silently
blocks real work with no clear error, which is its own tax on throughput.
**Found by:** looper, while dispatching the Close the Gaps epic (2026-09-30), investigating why
`PROVE-HEADLESS-1` (owns `docs/findings/`) was reported as conflicting with another ticket despite the map
declaring all three tickets disjoint. Root cause fully diagnosed and verified fixed in a scratch edit, not yet
landed by the correct seat.

## Root Cause

`lib/partition.sh`'s `_partition_ticket_active()` (around line 188) only explicitly matches `in_progress`,
`backlog|ready`, and `resolved|done|closed`:

```bash
case "$status" in
  in_progress) return 0 ;;
  backlog|ready) return 1 ;;
  resolved|done|closed)
    # No evidence file -> it cannot testify against the ticket -> inactive.
    ...
  *) return 0 ;;   # fail-closed default
esac
```

`CRED-1`'s status is `superseded` (it was dropped in favor of `GRANT-1`, per the driver's explicit decision
2026-09-29 -- see the commit superseding it). `superseded` isn't in the matched list, so it falls through to the
`*)` fail-closed default and is treated as still active, meaning `CRED-1`'s `owns: docs/findings/` still holds an
exclusive claim -- which collides with `PROVE-HEADLESS-1`'s own `owns: docs/findings/` and blocks it.

## Done-Criteria

1. `_partition_ticket_active()` treats `superseded` as inactive, same as `backlog|ready` (a superseded ticket was
   never executed and never will be -- it cannot hold a real ownership claim). Minimal fix already drafted and
   verified by looper:
   ```diff
   -    backlog|ready) return 1 ;;
   +    backlog|ready|superseded) return 1 ;;
   ```
2. New test coverage in `tests/test_partition.sh` for a `superseded` ticket not blocking a disjoint dispatch on
   the same owned path (looper's scratch version passed 40/0 after adding this -- re-derive rather than trust that
   number, but it's a strong signal the shape of the fix is right).
3. Audit whether any other status value used in ticket frontmatter across `maps/tickets/` (`grep -rh "^status:"
   maps/tickets/ | sort -u`) would hit the same fail-closed default unintentionally -- fix or explicitly
   document any that should.
4. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_partition.sh
bash lib/partition.sh check maps/tickets/prove-headless-1-real-batch-run.md
```

## Notes

This blocks `PROVE-HEADLESS-1`'s actual dispatch (a real lease conflict, not just advisory `blocked_by` prose) --
`PROVE-HEADLESS-1` is staged pending this ticket, not dispatched yet. `CONTEXT-1` and `SYNC-1` are unaffected and
dispatch immediately.

Per this project's write-boundary convention, this ticket exists because looper (root anchor) correctly diagnosed
and verified the fix in a scratch edit but must not land it directly -- `lib/*.sh` and `tests/*.sh` are outside a
root anchor's permitted paths. The scratch edit was discarded; `arch` re-derives and lands it properly, same
precedent as `ARB-SLUG-1`.
