---
id: CI-FIX-2
title: "test_repo_state [1k] hides gh by PATH allowlist — still red on ubuntu after CI-FIX-1"
type: wayfinder:task
status: resolved
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

## Resolution (2026-10-08)

Resolved in commit `d8b4d985b4b6ecd2ae867e33956784916e1ff613` (`d8b4d98`).

Done per criterion 1: `NOGH_BIN` now holds symlinks to exactly the externals
`repo-state.sh` resolves (`bash git sed awk cat`) and every absence-fixture run uses
`PATH="$NOGH_BIN"` — no system dir whitelisted, so gh is unreachable wherever the host
installed it. New regression case **[1k2]** proves the ubuntu condition inside the
suite: a fake gh in an ambient PATH dir (resolvable via `command -v gh`) still yields
`gh: unavailable (not on PATH)` under the fixture's PATH.

Receipts (criteria 2-3):
- `bash tests/test_repo_state.sh` → `36 passed, 0 failed` (local, Homebrew gh).
- Fake `/usr/bin`-style gh on the ambient PATH (`PATH="<fake>:$PATH" command -v gh`
  resolves it) + full suite → `36 passed, 0 failed` — the ubuntu condition.
- `make check` → `All suites green (20)` (now includes HERDR-4's test_briefs),
  lint 0 warnings.
- Sweep of the other `/usr/bin`-allowlisting suites — none in the defect class;
  all were green on ubuntu run 37730865014 (the run that exposed [1k]):
  - `test_ci_local.sh:50` — carrier PATH for stub make + real shellcheck parity
    (the absence fixtures were already fixed by CI-FIX-1).
  - `test_cli.sh:136` (HB_PATH) — carrier for python/git/jq; hides herdr, which is
    not preinstalled in /usr/bin on runners.
  - `test_cli_init.sh`, `test_cli_doctor.sh`, `test_providers.sh`, `test_quota.sh` —
    prepend scratch stub bins that SHADOW /usr/bin; the only absences relied on are
    provider CLIs / herdr, none of which ubuntu runners preinstall in /usr/bin.
    (Doctor's opencode-absent case is the closest cousin — revisit only if a runner
    ever preinstalls opencode.)
  - `test_pyenv.sh` — /usr/bin python3 is the intended fallback (fail-closed scan
    stops at the first candidate), not a hidden-tool fixture.
