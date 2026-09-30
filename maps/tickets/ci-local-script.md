---
id: DOG-18
title: "scripts/ci-local.sh: local CI-parity wrapper (PM flags likely redundant — see PM Note)"
type: wayfinder:task
status: resolved
commit: 4025f4b
assignee: arch
owns: scripts/ci-local.sh,CLAUDE.md
parent: maps/public-readiness.md
blocked_by: []
github_issue: 68
github_url: "https://github.com/HinchK/stampede/issues/68"
synced_at: "2026-09-30T17:16:14Z"
---

# DOG-18 — scripts/ci-local.sh: local CI-parity wrapper (Wave DX-1)

## PM Note (read before implementing)

I (pm-hinchk-stampede) am staging this ticket at the human driver's
explicit request, but I don't think it should be built as literally
scoped. Flagging this up front rather than silently softening the ticket,
per "draft tickets for both, let arch decide."

`.github/workflows/ci.yml` already documents itself as running exactly
one thing: `make check`. The workflow's own comment says so verbatim
("Runs the repo's own aggregate gate, `make check`..."). Everything else
in that workflow (installing jq/coreutils, pinning shellcheck to
v0.11.0, setting a `stampede-ci` git identity) is CI-runner
*provisioning*, not CI *logic* — a contributor's dev machine already has
these tools, under whatever versions it already has, and pinning
shellcheck locally to match CI's exact pin is a separate, narrower
concern from "run the CI job locally." A `scripts/ci-local.sh` that just
runs `make check` would be a zero-value wrapper around a command that
already IS the single canonical entry point (see `CLAUDE.md`'s own
`## Commands` section, first line under Aggregate entry points). Adding
a same-behavior wrapper is the premature-abstraction failure mode this
project's own working conventions warn against.

**Recommendation**: implement only the part with real, non-duplicate
value — a `--strict` or `--pin-check` mode (name TBD) that additionally
verifies the *local* shellcheck binary matches the CI-pinned version
(`v0.11.0`, per DOG-14 / `.github/workflows/ci.yml`'s `SC_VERSION`) and
warns if it doesn't, since that's the one place local and CI *can*
silently diverge (a contributor's stock `shellcheck` vs. the CI pin) and
`make check` alone can't catch it. If arch or the human driver disagrees
and wants a literal `ci-local.sh` wrapper anyway, that's a fine call to
override on — just make sure it doesn't get positioned as a *new* gate
alongside `make check` (one aggregate gate, not two).

## 1. Intended Outcome (as requested)

A script that reproduces `.github/workflows/ci.yml`'s `check` job
locally, exiting non-zero on any failure, so a contributor can verify
CI-equivalence before pushing.

## 2. Plan

Whichever shape lands (see PM Note): if the shellcheck-pin-parity
variant, `scripts/ci-local.sh` runs `make check` and additionally
compares the local `shellcheck --version` against `SC_VERSION` in
`.github/workflows/ci.yml`, warning (not failing, unless `--strict`) on
mismatch. Document the actual chosen behavior in `CLAUDE.md` next to the
`make check` line so a future session doesn't reach for both out of
habit.

## 3. Explicit Done-Criteria

- Does not introduce a second gate that can disagree with `make check`
  about pass/fail — if it wraps `make check`, `make check`'s own exit
  code is authoritative and unmodified.
- 0 shellcheck warnings.
- `CLAUDE.md` documents whatever this ticket actually ships, including if
  the resolution is "not built, `make check` already covers it."

## 4. Verification Step

```bash
scripts/ci-local.sh; echo "rc=$?"
make check   # must agree with ci-local.sh's verdict
shellcheck scripts/ci-local.sh
```
