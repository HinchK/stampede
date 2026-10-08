---
id: CI-FIX-2
title: "test_repo_state [1k] hides gh by PATH allowlist — still red on ubuntu after CI-FIX-1"
type: wayfinder:task
status: backlog
assignee: arch
owns: tests/test_repo_state.sh
parent: maps/universal-herdr-swarm.md
---

# CI-FIX-2 -- make the "gh absent" fixture hermetic (same class as CI-FIX-1)

## Intended Outcome

`make check` passes on `ubuntu-latest`; CI on `main` goes green for the first time
since 2026-10-06.

## Background (receipts)

PM audit 2026-10-08. `gh run view 37730865014 --log-failed` (run for `4c03a07`, which
contains CI-FIX-1): `test_ci_local` now passes (17/0) but
`✗ [1k] ci degrades to gh: unavailable (missing binary)` /
`✖ FAILED: tests/test_repo_state.sh`. `tests/test_repo_state.sh:31` builds
`NOGH_PATH="$NOGH_BIN:/usr/bin:/bin"`; ubuntu runners ship `gh` at `/usr/bin/gh`, so
the "absent" fixture finds it. Identical root cause to CI-FIX-1.

## Done-Criteria

1. `[1k]` (and any case using `NOGH_PATH`) simulates absence without allowlisting a
   system dir that can contain `gh`; the scratch bin links only what the script needs.
2. Prove on a host with `gh` in `/usr/bin` (fake `gh` on an ambient-PATH stub, as
   CI-FIX-1 did) or by green CI.
3. Sweep the other suites using `PATH="…:/usr/bin:/bin"` (`test_cli_init`,
   `test_cli_doctor`, `test_cli`, `test_providers`, `test_pyenv`): for each, state in the
   hand-off whether the tool it claims to hide can live in `/usr/bin` on ubuntu. Fix any
   that can; leave the rest (python in `/usr/bin` is intended) with a one-line receipt.
   `owns` widens only to a suite proven to have the defect.

## Verification Step

`make check` green locally; after promote, `gh run list -L 1` shows
`completed success`. Do not call CI fixed on the local run alone.
