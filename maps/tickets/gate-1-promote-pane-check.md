---
id: GATE-1
title: "Harden arbiter_promote against agent execution with a fail-closed pane-identity check"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/universal-herdr-swarm.md
github_issue: 71
github_url: "https://github.com/HinchK/stampede/issues/71"
synced_at: "2026-09-30T17:16:14Z"
---

# GATE-1 — Promote gate hardening (implementation)

**Source:** `docs/audits/2026-09-23-harden-the-promote-gate.md` (full investigation, findings, and design — read it
first, this ticket is the done-criteria extract).

## Intended Outcome

`arbiter_promote()` refuses to run when invoked from a pane Herdr recognizes as agent-occupied, and fails closed
(refuses) whenever pane identity can't be positively resolved — closing the gap demonstrated this session, where
an agent (`looper`) ran the promote and push itself on a direct human instruction, despite its own brief saying
that's forbidden.

## Done-Criteria

1. `_arb_promote_pane_check()` added to `lib/arbiter.sh`, implementing the exact logic in the spec §3:
   - `$HERDR_PANE_ID` unset → allow.
   - `$HERDR_PANE_ID` set, `herdr agent list` query fails → refuse.
   - `$HERDR_PANE_ID` set, resolves to a live agent in that pane → refuse, naming the pane.
   - `$HERDR_PANE_ID` set, Herdr-managed but no agent attached → allow.
2. Called at the top of `arbiter_promote()`, before the `--confirm` check, gating **both** the local ff-only path
   and the `--pr` path (opening a PR still pushes the integration branch — also forbidden for agents per the
   brief's Push Guardrail).
3. **No environment variable bypass of any kind added** — see spec §4. Test coverage for the refusal path works by
   redefining `_arb_promote_pane_check` after sourcing `lib/arbiter.sh` in the test, not by an env toggle the CLI
   itself would honor.
4. Existing promote tests (`--confirm`/`PROMOTE_CONFIRM=1` paths) still pass unmodified — they run hermetically
   with no `$HERDR_PANE_ID` set, so they hit the "unset → allow" branch same as before.
5. New test assertions: (a) promote refuses when the pane check is stubbed to simulate an agent-occupied pane, with
   a clear refusal message; (b) promote refuses when the herdr-list query is stubbed to fail; (c) promote still
   succeeds when the pane check is unstubbed (equivalent to no Herdr context).
6. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_arbiter.sh   # new pane-check assertions pass alongside existing promote assertions
```

## Notes

Do not attempt GitHub branch protection, PR-based promote-by-default, or any form of credential separation as part
of this ticket — all three are explicitly out of scope (spec §5), blocked on driver decisions this ticket doesn't
make. This is a local hardening only, and the spec is explicit that it is not airtight against a deliberate bypass
— don't oversell it in the implementation or its test names.

## Resolution

- **Implemented By**: `arch-1-hinchk-stampede` in commit `e86f79069fce1f3cca472fb034e33eb8c8079740`.
- **Implementation**:
  - Implemented `_arb_promote_pane_check()` in `lib/arbiter.sh:312-327` handling unset pane IDs (allowed), query failures (refused fail-closed), live agent in pane (refused with pane name and plain shell remedy), and agentless managed panes (allowed).
  - Wired at top of `arbiter_promote()` before `--confirm` and mode dispatch, protecting both local fast-forward and `--pr` branches.
  - Added hermetic unit tests in `tests/test_arbiter.sh:233-298` (§7d) with 66/66 assertions passing; unsets ambient `$HERDR_PANE_ID` at top of suite.
- **Review**: Autonomous reviewer round 1 passed with PASS verdict (`.herdr-swarm/reviews/GATE-1-e86f79069fce1f3cca472fb034e33eb8c8079740.md`).
- **Integration**: Integrated onto `swarm/stampede/integration` at `e86f790` via arbiter drain.

