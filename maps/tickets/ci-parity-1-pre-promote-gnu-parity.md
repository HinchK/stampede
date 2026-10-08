---
id: CI-PARITY-1
title: "Catch macOS-green/ubuntu-red before promote: lint tests/*.sh and a GNU-userland parity mode"
type: wayfinder:task
status: resolved
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

## Resolution (2026-10-08)

Done, all four criteria:

1. **Lint widened, two tiers, 0-warning bar held.** `LINT_SH` now covers
   `scripts/*.sh` and `lib/*/*.sh` at the existing strict bar (0 findings at ANY
   severity — 27 files), and a new `LINT_TESTS_SH` covers `tests/*.sh` at the
   stated repo bar (`--severity=warning` — 21 files); the split and the info
   baseline (SC2015 ok/bad one-liners, SC2016 single-quoted eval bodies, SC2329
   indirect stubs) are documented in the Makefile itself. Warnings surfaced and
   dispositioned: one real fix (`rc=0` init before the EXIT trap in
   tests/test_headless.sh — SC2154); the rest are eval-string consumption /
   eval-assigned config vars, silenced with individually-justified file-level
   directives matching the sibling-suite convention in test_ci_local,
   test_headless, test_repo_state, test_config, test_pyenv, test_cli_init
   (SC2034/SC2154). Those five files are outside this ticket's `owns:` —
   lint-only one-directive touches, conflict-checked against open tickets.
2. **`--gnu-sim` ladder**: runtime probe `docker` then `podman`
   (daemon-alive `info` check); runtime present → `make check` runs INSIDE
   `<rt> run --rm -v <root>:/work -w /work ${CI_GNU_SIM_IMAGE:-ubuntu:24.04}`
   and that rc is the gate (local make skipped); runtime absent → explicit
   "GNU parity unproven — no container runtime found (tried: docker, podman)"
   warning, local gate authoritative, exit 0 on green; `--gnu-sim --strict`
   exits 1 after a green local gate. Composable flag parsing (loop over args,
   ≤2 flags) — fixed a self-inflicted no-args regression (`"${@:-}"` phantom
   arg) caught by the existing suite before it ever committed.
3. **Tests**: 11 new assertions 5a–5k (exact container argv incl. mount/workdir/
   image, local-make skipped, rc propagation, image override, absent-runtime
   degrade + local gate runs, strict-unproven, podman fallback, strict-proven,
   help). Runtime stubs fail `info` by default, so absence is hermetic even on
   hosts with live docker in /usr/bin (the CI-FIX-1 lesson applied to itself).
   No new dependency is mandatory: `make check` never invokes a runtime.
4. **Promote-time proposal**: in `/tmp/arch-out.md` (arbiter-side
   ubuntu-CI-result check, warn-by-default/refuse-with-grant) — proposed, not
   wired, per the ticket.

Demo receipt (scratch copy, `sed -i ''` defect): local `make check` GREEN
(BSD), `ci-local.sh` default exit 0 (divergence invisible locally),
`--gnu-sim` exit 2 — GNU sed rejects the BSD idiom, caught pre-promote.

Receipts: `make lint` → `Lint clean (48 shell files: 27 strict, 21
warnings-bar)`; `make check` → `All suites green (21)` (test_standby.sh
arrived with the main merge; CLAUDE.md count line refreshed);
tests/test_ci_local.sh → 28 passed, 0 failed.
