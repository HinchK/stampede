---
id: CI-FIX-1
title: "test_ci_local [2a] hides shellcheck by PATH — fails on ubuntu CI, main red for 5 runs"
type: wayfinder:task
status: backlog
assignee: arch
owns: tests/test_ci_local.sh
parent: maps/universal-herdr-swarm.md
---

# CI-FIX-1 -- make the "shellcheck absent" fixtures hermetic

## Intended Outcome

`make check` passes on `ubuntu-latest`, so CI on `main` goes green again. Today every
push to `main` since at least 2026-10-06 fails the `make check (ubuntu-latest)` job.

## Background (receipts)

PM audit 2026-10-07. `gh run view 37708838497 --log-failed` shows
`✗ [2a] shellcheck absent: warns, exits 0 after green gate` then
`16 passed, 1 failed` / `FAILED: tests/test_ci_local.sh`. Local `make test` is green
(19 suites) only because macOS shellcheck lives in Homebrew, outside the
`PATH="$BIN_NOSC:/usr/bin:/bin"` the fixture uses to simulate absence
(`tests/test_ci_local.sh:83`). On ubuntu runners shellcheck is `/usr/bin/shellcheck`,
so the "absent" fixture finds it. Case 2b (same PATH) is the same latent defect.
The local suite cannot catch this class: green here is not evidence for CI.

## Done-Criteria

1. The "shellcheck absent" fixtures (2a, 2b) simulate absence without depending on
   where the host installs shellcheck (e.g. a PATH of only a scratch bin dir holding
   the symlinks the fixture needs — `bash`, `git`, `make`, coreutils — and no
   shellcheck; do not whitelist `/usr/bin`).
2. Suite passes on this machine AND on a host with shellcheck in `/usr/bin`
   (prove the second with a scratch PATH containing a fake `/usr/bin`-style shellcheck,
   or by a green CI run).
3. No production code (`scripts/ci-local.sh`) change unless the fix proves it is
   itself wrong; if so, say so in the hand-off.

## Verification Step

`make check` green locally, then push the integration ref and confirm
`gh run list -L 1` shows `completed success` for the promoted commit.

## Notes

Standing lesson: any fixture that simulates "tool absent" via a PATH allowlist must
exclude system dirs that the tool can legitimately live in.
