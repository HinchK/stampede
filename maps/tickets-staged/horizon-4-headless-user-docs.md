---
id: HORIZON-4
title: "User-facing documentation for the headless batch"
type: wayfinder:task
status: backlog
assignee: agy-docs
owns: docs/user-guide.md,README.md,CHANGELOG.md
parent: maps/next-horizon.md
blocked_by: [HORIZON-1]
---

# HORIZON-4 — teach the world stampede headless

## Intended Outcome

The public surface describes the batch mode truthfully: a user-guide section
(when to reach for it, the flags, the exit codes, the dead-letter file), a
README mention beside the existing run modes, and a CHANGELOG entry whose
version matches VERSION (PUB-5 discipline).

## Done-Criteria

1. docs/user-guide.md section with a worked example.
2. README run-mode table/paragraph updated.
3. CHANGELOG top entry names the version in VERSION (`make version-check`).
4. `make check` green.

## Verification Step

`grep -rn "stampede headless" README.md docs/user-guide.md` finds both;
`make version-check` passes.
