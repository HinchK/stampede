---
id: T-010
title: "Seat Verification Protocol and Brief Acknowledgment Gate"
type: wayfinder:prototype
status: done
assignee: arch
prototype_asset: lib/lifecycle.sh,herdr-loop-swarm.sh
owns: lib/lifecycle.sh,herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
github_issue: 44
github_url: "https://github.com/HinchK/stampede/issues/44"
synced_at: "2026-09-22T03:50:13Z"
---

# Seat Verification Protocol and Brief Acknowledgment Gate (T-010)

## Question

How should `lib/lifecycle.sh` and `herdr-loop-swarm.sh` implement a robust post-seating verification gate (`swarm_verify_seats`) that confirms every seated agent in `.herdr-swarm/seats.json` is alive, responsive, and has finished ingesting its standing brief (`idle` or `done`) before dispatching kickoff execution?

## Preamble

1. **Intended Outcome**: Add `swarm_verify_seats` to `lib/lifecycle.sh` and integrate it into `herdr-loop-swarm.sh` immediately after seating and seat-ledger generation, ensuring all seated agents acknowledge their briefs and reach interactive readiness (`idle` or `done`) before kickoff prompts are dispatched.
2. **Explicit Done-Criteria**:
   - `lib/lifecycle.sh` defines `swarm_verify_seats [target_dir] [timeout_ms]`:
     - Reads `${target_dir}/.herdr-swarm/seats.json` (falling back to live workspace agents if ledger is missing/stale).
     - For each seat, checks existence via `herdr agent get "$name"`.
     - Waits up to `timeout_ms` (default 30000ms) for the agent to settle using `herdr agent wait "$name" --until "idle" --until "done" --timeout "$timeout_ms"`.
     - Prints clear per-seat status (`✓ <name> (<kind> in <pane>): ready` or `✖ <name>: <failure>`).
     - Returns 0 if all seats are ready, non-zero if any seat failed or timed out.
   - `herdr-loop-swarm.sh` calls `swarm_verify_seats "$PWD"` after generating `.herdr-swarm/seats.json` and before `Kickoff Execution`.
   - If `swarm_verify_seats` fails:
     - In interactive/seat-only mode (`s`), prints warning.
     - In autonomous queue mode (`a`), fails closed with exit code 1 if critical seats (`arch`, `pm`) are not ready.
   - `herdr-loop-swarm.sh` supports a `verify [dir]` subcommand calling `swarm_verify_seats "${dir:-$PWD}"`.
   - Shellcheck on `lib/lifecycle.sh` and `herdr-loop-swarm.sh` passes cleanly with 0 warnings.
3. **Verification Step**:
   - Run `shellcheck lib/lifecycle.sh herdr-loop-swarm.sh && echo "PASS: shellcheck"`
   - Run `./herdr-loop-swarm.sh verify >/dev/null && echo "PASS: verify subcommand"`
   - Test `swarm_verify_seats` against the live swarm in `wM` and verify all 5 agents pass readiness check.
