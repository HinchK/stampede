---
id: PUB-5
title: "VERSION, CHANGELOG.md, and stampede version"
type: wayfinder:task
status: resolved
assignee: arch
owns: VERSION,CHANGELOG.md,lib/cli/stampede-version.sh
parent: maps/public-multi-provider.md
blocked_by: PUB-1
github_issue: 94
github_url: "https://github.com/HinchK/stampede/issues/94"
synced_at: "2026-09-30T17:16:14Z"
---

# PUB-5 — Version + changelog discipline (Wave 9)

## 1. Intended Outcome

`stampede version` prints the semver from `VERSION` plus `git describe
--tags --always --dirty` when available. `CHANGELOG.md` (Keep a Changelog
format) is seeded with the shipped milestones (M1 sequential swarm, P2
worktree isolation, P3 concurrent fan-out, public-readiness waves), and a
`make version-check` target fails when the changelog's top entry version
disagrees with `VERSION`.

## 2. Problem

A public tool with no version, no tags, and no changelog gives users no
upgrade path and no way to pin or reason about drift — and gives the swarm
no honest answer to "what changed?" between clones.

## 3. Plan

- `VERSION`: `0.x.0` starting the pre-1.0 line (public API not frozen).
- `lib/cli/stampede-version.sh`: reads `VERSION`; appends `git describe`
  when the target is a git repo with tags, else the short sha; degrades
  cleanly outside a repo.
- `CHANGELOG.md`: seeded retrospectively from `STATE.md` milestones —
  facts already receipted in-repo, no new claims.
- `Makefile` target lives here only if PUB-1's convention needs no edit;
  otherwise it rides PUB-1's `bin/`+`Makefile` ownership in Wave 8 —
  coordinate, never co-dispatch.

## 4. Explicit Done-Criteria

- `stampede version` works inside and outside a git repo.
- `make version-check` green; deliberately breaking `VERSION` turns it
  red (asserted in the ticket body, not just claimed).
- Tagging procedure documented as human-only (consistent with the
  remote-safety invariant).

## 5. Verification Step

```bash
bin/stampede version
make version-check
(cd /tmp && /path/to/repo/bin/stampede version)   # no-git degradation
make check
```
