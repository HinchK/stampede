---
id: SYNC-2
title: "gh_sync.sh doesn't recognize superseded as closed-equivalent, forcing a ticket-file workaround"
type: wayfinder:defect
status: resolved
assignee: arch
owns: lib/gh_sync.sh
parent: maps/close-the-gaps.md
---

# SYNC-2 -- gh_sync.sh status vocabulary gap

**Severity:** LOW -- self-corrected same session, no data loss, but the workaround used (hand-patching a
ticket's status field to satisfy a script's narrow vocabulary) is exactly the anti-pattern this project's
conventions exist to prevent, even when the intent is benign.
**Found by:** agy-gh, while running `SYNC-1`'s `lib/gh_sync.sh --apply` 2026-09-30.

## Root Cause

`lib/gh_sync.sh` line 344's `local_is_closed` check only recognizes `t_st in ("resolved", "closed", "done")`.
`CRED-1`'s actual status, `superseded`, isn't in that set, so `gh_sync.sh --dry-run` planned to reopen the
already-closed GitHub issue #70. To avoid that, `CRED-1`'s ticket file was hand-patched from `status: superseded`
to `status: closed` / `outcome: superseded` before running `--apply`, then reverted afterward once noticed by
the reviewer during `PART-1`'s review.

## Done-Criteria

1. `lib/gh_sync.sh`'s closed-recognition set includes `superseded` (and audit for any other status values used
   across `maps/tickets/` that should also count as closed-equivalent -- `grep -rh "^status:" maps/tickets/ |
   sort -u`).
2. No ticket file should ever need its `status:` field temporarily altered to satisfy `gh_sync.sh`'s
   classification -- the canonical status stays canonical; the sync script adapts to it.
3. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_gh_sync.sh
bash lib/gh_sync.sh --dry-run
```

## Resolution

- **Implementation**: In commit `a3bc78d`, `arch-1-hinchk-stampede` updated `local_is_closed` in `lib/gh_sync.sh:348` to include `"superseded"`, treating it as closed-equivalent across both arms (closed remote remains `IN_SYNC` without reopening; open remote plans `UPDATE_REMOTE` close).
- **Status Audit**: Audited all ticket status values across `maps/tickets/` (`backlog`, `closed`, `done`, `resolved`, `superseded`) — confirmed only `backlog` is open-class.
- **Suite Gate**: `tests/test_gh_sync.sh` expanded (+3 tests, 30/30 passing) including fixture assertions proving superseded tickets remain untouched in frontmatter without requiring hand-patching; `make check` all 19 suites green, 0 shellcheck warnings.
- **Review**: Autonomous Reviewer Loop Round 1/2 issued `PASS` in `.herdr-swarm/reviews/SYNC-2-a3bc78d933b134c1e3102592906d9e5f8b333b9f.md`.
- **Integration**: Integrated onto `swarm/stampede/integration` at `0276187` via arbiter auto-drain. Lease released cleanly.
