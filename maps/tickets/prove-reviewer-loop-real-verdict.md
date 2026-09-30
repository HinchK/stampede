---
id: PROVE-3
title: "Prove the Reviewer Loop on a real ticket"
type: wayfinder:task
status: resolved
resolution:
  ticket: PROVE-4
  target_sha: 16dd48121c78780f36440a3181bf2b2ba54db3c6
  verdict: PASS
  review_file: .herdr-swarm/reviews/PROVE-4-16dd48121c78780f36440a3181bf2b2ba54db3c6.md
  reviews_store: .herdr-swarm/reviews.json
assignee: looper
blocked_by: PROVE-1,PROVE-2
parent: maps/prove-and-reconcile.md
github_issue: 89
github_url: "https://github.com/HinchK/stampede/issues/89"
synced_at: "2026-09-30T17:16:14Z"
---

# PROVE-3 — Prove the Reviewer Loop (Wave 1)

**Source:** `docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md` §7, §10 step 3.

## Intended Outcome

At least one real ticket runs through `loop` mode and produces a genuine, harvested verdict — closing the gap
between "REV-1..5 shipped and unit-tested" and "the reviewer has actually caught or passed something."

## Background

```
$ ls .herdr-swarm/reviews/
ls: .herdr-swarm/reviews/: No such file or directory
```

Five waves of engineering, 479 green assertions, and zero `REVIEW VERDICT` lines outside the test fixtures. This
ticket is the fix — not more engineering, one real dispatch.

**Blocked by PROVE-1 and PROVE-2**: no supervisor process is currently running, and PROVE-2's config flip only
takes effect once it's on `main` (the launcher/supervisor run from the root checkout, not an arch worktree branch).

## Done-Criteria

1. One ticket is dispatched with `loop = true` in effect.
2. A `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>` anchor is emitted and harvested.
3. A report file exists at `.herdr-swarm/reviews/<ticket>-<sha>.md`.
4. `.herdr-swarm/session-verdicts.jsonl` (or the reviews' own store) shows the harvested verdict.

## Verification Step

```bash
ls .herdr-swarm/reviews/            # at least one file
cat .herdr-swarm/reviews/*.md       # a real PASS or BLOCK, with findings
```

## Notes

A doc-only ticket as the guinea pig would only exercise the `PASS`/harvest path, not `BLOCK` → refine (REV-2/REV-3).
Prefer a ticket with at least a plausible finding over the safest possible one — a clean `PASS` alone on trivial
work isn't proof the loop actually reviews anything.
