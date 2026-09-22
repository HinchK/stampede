---
id: DOG-9
title: "Docs link to machine-local absolute paths"
type: wayfinder:task
status: resolved
commit: bb8fda9
assignee: arch-1
owns: docs/,maps/,STATE.md,README.md,CONTEXT.md,CLAUDE.md,CONTRIBUTING.md,SECURITY.md
parent: maps/public-readiness.md
github_issue: 61
github_url: "https://github.com/HinchK/stampede/issues/61"
synced_at: "2026-09-22T03:50:13Z"
---

# DOG-9 — Relative links across the docs (WAVE 5)

## 1. Intended Outcome

Every internal link in the repo's markdown resolves from a fresh clone
anywhere on any machine — no file-scheme URLs, no absolute host paths.

## 2. Problem

Docs written by seats on this machine embed file-scheme URLs pointing into
the author's home directory, e.g. the `STATE.md` header linking the ticket
map under `maps/`. A stranger who clones the repo gets dead links in the
checkpoint document that is supposed to orient them. Also breaks after the
rename (DOG-10) unless links are relative first — which is why this wave
precedes it.

## 3. Scope

- Convert file-scheme URLs and bare home-directory absolute references in
  tracked markdown to repo-relative links.
- Sweep **every** tracked `.md` (this is why the ticket runs alone: it touches
  nearly every markdown file and must follow the README work in DOG-5).
- Non-markdown files are out of scope; so is rewriting prose.

## 4. Done-Criteria

1. A grep for the file URL scheme (`file` + two slashes) across tracked
   `.md` returns nothing (excluding `.herdr-swarm/`).
2. A grep for the macOS home-directory prefix (`/Users` + trailing slash)
   across tracked `.md` returns nothing (same exclusion).
3. Spot-check ten converted links resolve from repo root.
4. `make check` green.

## 5. Verification Step

```bash
# (commands spelled without their literal patterns so this ticket does not
#  trip its own sweep — see issue #61 for the verbatim greps)
grep -rn 'file:' --include='*.md' . | grep -v .herdr-swarm ; echo "rc=$? (want 1)"
grep -rn '/Users' --include='*.md' . | grep -v .herdr-swarm ; echo "rc=$? (want 1)"
```
