---
id: HORIZON-4
title: "User-facing documentation for the headless batch"
type: wayfinder:task
status: resolved
assignee: agy-docs
owns: docs/user-guide.md,README.md,CHANGELOG.md
parent: maps/next-horizon.md
blocked_by: [HORIZON-1]
resolution:
  user_guide: docs/user-guide.md#11-headless-batch-mode-unattended-queue-drain
  readme: README.md#two-run-modes
  changelog: CHANGELOG.md#050--in-development-multi-provider-ux-review-loop-and-headless-batch-drain
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

## Resolution

- **User Guide Section**: Added Section 11 to [`docs/user-guide.md`](../../docs/user-guide.md) with a full worked example (`bin/stampede headless /tmp/demo --max-tickets 3 --timeout 1200`), flags, exit code contract (`0`, `1`, `3`/`124`), dead-letter diagnostics (`.herdr-swarm/dead-letter.jsonl`), and target repository prerequisites (model pinning, external directory permissions, gitignore state directory).
- **README Run Modes**: Added "Two Run Modes" comparative table to [`README.md`](../../README.md) comparing interactive floor mode vs headless batch mode, expanded the `stampede headless` CLI section, and updated the ADR tree to include ADR 0015.
- **CHANGELOG [0.5.0]**: Expanded [`CHANGELOG.md`](../../CHANGELOG.md) top entry to document all capabilities shipped during this session (headless batch mode, headless safety/hardening, autonomous review loop, session-scoped promote grant, auto-drain pipeline, partition/ref integrity, and tooling).
- **Verification**: `grep -rn "stampede headless" README.md docs/user-guide.md` and `make version-check` pass.

