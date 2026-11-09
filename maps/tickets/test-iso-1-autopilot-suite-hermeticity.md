---
id: TEST-ISO-1
title: "test_autopilot.sh is not hermetic to ambient HERDR_* context — every agent seat goes RED on make test"
type: wayfinder:defect
status: resolved
assignee: arch
owns: tests/test_autopilot.sh
parent: maps/repo-truth-pass.md
---

# TEST-ISO-1 -- make test must be green from a seated agent pane

## Intended Outcome

`make test` passes from ANY context — a plain human shell, CI, and a herdr-seated agent
pane — with `tests/test_autopilot.sh` scrubbed of ambient herdr state; and the suite gains
an explicit tooth pinning the safety property that caused this: `stampede autopilot on`
**refuses and changes nothing** when invoked from an agent-occupied pane context.

## Background

Found live at charting time (2026-11-08, arch-1-stampede) and reproduced three consecutive
times from the seat pane; green from a plain context (CI parity):

- `tests/test_autopilot.sh:39` runs `stampede_cmd_autopilot "$R" on` for real. From an
  agent pane, `lib/arbiter.sh:538-553` `_arb_promote_pane_check` sees `HERDR_PANE_ID` set
  with a live agent in that pane and refuses; `arbiter_grant_session`
  (`lib/arbiter.sh:591-594`) returns 1; `lib/cli/stampede-autopilot.sh:93-96` returns 1
  ("autopilot: promote grant refused — run this from a plain human shell; nothing was
  changed"). Under the suite's `set -euo pipefail` (`tests/test_autopilot.sh:15`) that
  non-zero return kills the suite silently — no assertion diagnostic, exit 1.
- The refusal itself is **correct product behavior** (GATE-1/GRANT-1: grants are
  human-only; see `docs/audits/2026-09-23-harden-the-promote-gate.md` and
  `docs/adr/` GRANT-1 records). The defect is the suite's assumption of a plain-shell
  environment: `_arb_promote_pane_check` allows only when `HERDR_PANE_ID` is unset.
- Same isolation class as postmortem §4.1 / #164 ("the gate does not run the way workers
  run"). Ironic edge: workers are the ones *required* to run `make test` before every
  verdict. The supervisor's own gate is unaffected — it scrubs `HERDR_*` from the gate
  runner (asserted in test_arbiter: "integration gate sees no REPO_DIR/STATE_DIR/slug/
  HERDR_*/config from its runner") — so CI and Suite-Gate verdicts stay green while every
  local seat verification goes red.
- AUTOPILOT-1 shipped in `[Unreleased]` (after 0.6.0); the herd was down over that window
  (postmortem §11.9), so no agent seat had run the suite until 2026-11-08.

## Done-Criteria

1. The on/off leg of `tests/test_autopilot.sh` (section 1, the `stampede_cmd_autopilot
   "$R" on` call and everything after it that depends on the grant) runs with ambient
   herdr context scrubbed — at minimum `HERDR_PANE_ID` unset, matching how CI, plain
   shells, and the supervisor's gate runner invoke it. Reuse the repo's existing
   scrub convention (see how `gate_exec` isolates `HERDR_*`/`REPO_DIR`/`STATE_DIR` in
   `loop-bot-herd.sh`); do not invent a parallel mechanism.
2. A new assertion pins the safety property: with `HERDR_PANE_ID` set and `herdr`
   resolving to a listing that shows an agent in that pane (stub pattern already proven
   in `tests/test_arbiter.sh`'s "agent-occupied pane: promote refused" case),
   `stampede_cmd_autopilot "$R" on` refuses, returns non-zero, and leaves
   `attention.json`, `control.json`, and `promote-grant.json` untouched.
3. The suite's failure mode is never again silent: the section-1 call's stderr is
   captured and included in the assertion diagnostics (a bare `set -e` death with three
   orphan stderr lines cost real diagnosis time on 2026-11-08).
4. Verified from BOTH context classes before the verdict: `make test` green from a plain
   context AND from a live agent pane (any seated seat can run the latter; the ticket
   executor is one).
5. `make check` green, 0 shellcheck warnings on the modified suite.

## Verification Step

```bash
make check           # plain-context parity
bash tests/test_autopilot.sh   # from a seated agent pane, with HERDR_PANE_ID set — must pass
```

## Resolution
Resolved in commit `4901397`. Autopilot suite hermetic to ambient herdr context. Review PASS in .herdr-swarm/reviews/TEST-ISO-1-4901397.md.
