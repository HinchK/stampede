---
id: PROVE-6
title: "Fix stale suite-count claims in CLAUDE.md and ci.yml"
type: wayfinder:doc
status: resolved
commit: b02609d
assignee: arch
owns: CLAUDE.md,.github/workflows/ci.yml
parent: maps/prove-and-reconcile.md
github_issue: 87
github_url: "https://github.com/HinchK/stampede/issues/87"
synced_at: "2026-09-30T17:16:14Z"
---

# PROVE-6 — Suite-count drift (Wave 1)

**Source:** `docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md` §9.

## Intended Outcome

`CLAUDE.md`'s Commands section and `ci.yml`'s header comment state the real, current suite count instead of a
stale one.

## Background

`CLAUDE.md` says "all eight suites." `.github/workflows/ci.yml`'s header comment says "all six suites." `main` has
16 suites today; 18 once PROVE-1 promotes DOG-17/18. Both have been wrong for multiple waves — this is cheap,
mechanical drift, not a design question.

## Done-Criteria

1. `CLAUDE.md`'s Commands section lists the actual suite count and names every suite file (or states the count
   accurately if listing all by name is deemed too brittle going forward — flag which choice was made and why).
2. `ci.yml`'s header comment states the actual count.
3. Both reflect the count as of whenever this ticket is worked — re-verify with `ls tests/*.sh | wc -l` at that
   time rather than hardcoding "18" from this ticket's writing.

## Verification Step

```bash
ls tests/*.sh | wc -l
grep -n "suite" CLAUDE.md .github/workflows/ci.yml   # both match the count above
```
