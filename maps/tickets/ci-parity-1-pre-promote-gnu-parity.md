---
id: CI-PARITY-1
title: "Catch macOS-green/ubuntu-red before promote: lint tests/*.sh and a GNU-userland parity mode"
type: wayfinder:task
status: backlog
assignee: arch
owns: Makefile, scripts/ci-local.sh, tests/test_ci_local.sh
parent: maps/dispatch-safety-and-review-policy.md
---

# CI-PARITY-1 -- stop promoting commits that only a different OS can reject

## Intended Outcome

A flavor-specific test bug (macOS-only `sed -i ''`, `/usr/bin` PATH allowlists) fails on
the dev machine or at the gate, never on `main` after a promote.

## Background (receipts, PM audit 2026-10-08)

Three consecutive promotes turned `main` red on ubuntu while macOS was green:
CI-FIX-1 (shellcheck PATH), CI-FIX-2 (`gh` PATH), CI-FIX-3 (`sed -i ''`, run
`37772778703`). Each was found only by remote CI after the promote. CI-FIX-3's hand-off
proposed the process fix but did not charter it.

## Done-Criteria

1. `make lint` shellchecks `tests/*.sh` (today `LINT_SH` omits them). Any warnings this
   surfaces are fixed or individually justified in the hand-off; the 0-warning bar holds.
   Scope guard: if the sweep exceeds a handful of fixes, split the cleanup out and land
   the widening with a documented baseline instead of blocking.
2. `scripts/ci-local.sh --gnu-sim` (name flexible) runs `make check` under GNU
   userland where available (container or equivalent) and degrades to an explicit
   "parity unproven" warning, exit 0, when no container runtime exists (`--strict`
   fails), matching the existing pin-parity ladder in `tests/test_ci_local.sh`.
3. Tests for the new mode's ladder (runtime present / absent / strict). No new
   dependency becomes mandatory for `make check`.
4. Hand-off proposes, but does not wire, a promote-time check (e.g. arbiter refusing or
   warning when the integration ref has no remote ubuntu CI result). Wiring is a
   separate decision because it touches the promote gate.

## Verification Step

`make check` green on both CI runners after promote; show `--gnu-sim` catching a
re-introduced `sed -i ''` in a scratch copy (fails before the fix, passes after).
