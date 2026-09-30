---
id: SYNC-1
title: "Backfill GitHub issue sync — dormant since 2026-09-22"
type: wayfinder:task
status: backlog
assignee: agy-gh
owns: maps/tickets/
parent: maps/close-the-gaps.md
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
