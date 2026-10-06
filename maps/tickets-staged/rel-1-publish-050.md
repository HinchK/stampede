---
id: REL-1
title: "Publish 0.5.0 — date the changelog, tag, push"
type: wayfinder:task
status: backlog
assignee: human
owns: CHANGELOG.md,VERSION
parent: maps/headless-live.md
blocked_by: [HORIZON-3]
---

# REL-1 — ship the release the changelog already describes

## Intended Outcome

The `[0.5.0] — in development` entry at the top of CHANGELOG.md becomes a
dated `[0.5.0] — 2026-10-XX` release, the repo is tagged `v0.5.0`, and the
tag + main are pushed — the PUB-5 discipline (version-check green, publishing
starts with the paperwork) executed for real.

## Done-Criteria

1. CHANGELOG top entry dated; if HORIZON-2/3 added capabilities or decisions
   after the entry was drafted, they are named in it (the live-proof findings
   doc and the review-boundary ADR-or-feature).
2. `make version-check` green (VERSION=0.5.0 == top changelog entry).
3. `make check` green at the tag.
4. Human creates the annotated tag and pushes tag + main (push is human-only;
   a session grant covers promote, never the release push without an explicit
   go).

## Verification Step

`git tag --points-at HEAD` shows v0.5.0; `make version-check` passes;
`origin/main` carries the release commit.
