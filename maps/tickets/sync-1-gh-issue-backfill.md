---
id: SYNC-1
title: "Backfill GitHub issue sync — dormant since 2026-09-22"
type: wayfinder:task
status: resolved
assignee: agy-gh
owns: maps/tickets/
parent: maps/close-the-gaps.md
github_issue: 108
github_url: "https://github.com/HinchK/stampede/issues/108"
synced_at: "2026-09-30T17:18:19Z"
---

# SYNC-1 — GitHub issue sync backfill

## Intended Outcome

Every resolved ticket since the last sync (`DOG-10`, `2026-09-22`) gets a real GitHub issue, filed and closed to
match its actual local status — `PUB-*`, `REV-*`, `PROVE-*`, `TRUST-1`, `GATE-*`, `HEADLESS-*`, `BRIEF-1`,
`INCIDENT-1`, `GRANT-1`, `SUPER-1`, `ARB-SLUG-1`, and anything else currently missing. Confirmed via
`gh issue list --state all`: nothing newer than issue #64 (`DOG-10`) exists.

## Done-Criteria

1. Run `bash lib/gh_sync.sh --dry-run` first and review the full proposed diff before writing anything — this
   project's own convention (zero unconfirmed writes by default).
2. Run `bash lib/gh_sync.sh --apply` once the dry-run output looks correct.
3. Verify afterward with `gh issue list --state all --limit 50` that the new tickets now have real, correctly
   closed/open issues, and that each synced ticket's frontmatter gained `github_issue`/`github_url`/`synced_at`.
4. Report the final count: how many issues were created, and confirm none were left open that should be closed (or
   vice versa).

## Verification Step

```bash
gh issue list --state all --limit 50 --json number,title,state,updatedAt
```

## Notes

This ticket's `owns:` is intentionally broad (`maps/tickets/`) since `--apply` writes sync metadata back into
every ticket's frontmatter — an exclusive lease for the duration of this run is correct, not overly cautious.

## Resolution

Backfill completed by `agy-gh-hinchk-stampede` following the two-way sync protocol (`lib/gh_sync.sh`):

1. **Dry-Run Inspection**: Verified initial dry-run plan (`Summary: To Create: 44, To Link: 0, To Update: 0, In Sync: 54, Total: 98`) ensuring zero unconfirmed writes prior to execution.
2. **Issue Creation Pass**: Executed `bash lib/gh_sync.sh --apply --repo HinchK/stampede` creating 44 new remote issues (#66 through #109) and writing `github_issue`, `github_url`, and `synced_at` anchors into every ticket frontmatter.
3. **State Reconciliation Pass**: Executed second apply pass to close 40 remote issues corresponding to locally resolved/closed tickets, while preserving 4 active backlog tickets (`CONTEXT-1` #69, `PART-1` #82, `PROVE-HEADLESS-1` #88, `SYNC-1` #108) in OPEN state.
4. **Final Sync Verification**: Ran `bash lib/gh_sync.sh --dry-run --repo HinchK/stampede` confirming `In Sync: 98, Total: 98` (100% parity across local tickets and remote GitHub issues).
5. **Remote Verification**: Verified via `gh issue list -R HinchK/stampede --state all --limit 50 --json number,title,state,updatedAt`.

