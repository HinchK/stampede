---
id: HEADLESS-6
title: "bin/stampede headless CLI entrypoint"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/cli/stampede-headless.sh,bin/stampede,tests/test_cli.sh,CLAUDE.md
parent: maps/headless-run-mode.md
github_issue: 79
github_url: "https://github.com/HinchK/stampede/issues/79"
synced_at: "2026-09-30T17:16:14Z"
---

# HEADLESS-6 — CLI entrypoint (Slice 3c)

**Source:** `docs/findings/headless-mode-design.md` §3.

## Intended Outcome

`bin/stampede headless [--max-tickets N] [--timeout M]` ties HEADLESS-3/4/5 together into the actual user-facing
command: iterate `backlog` tickets in `maps/tickets/` (the deterministic queue-intake replacement for `looper`'s
interactive judgment, per the map's Notes), dispatch each via `lib/headless.sh`, harvest via HEADLESS-4's wiring,
respect HEADLESS-5's safety caps, and terminate when the queue is empty or the caps are hit.

**Naming, corrected during PM guidance (2026-09-24):** the original design doc proposed `stampede drain
--headless`. That collides with the already-established meaning of "drain" in this repo — `arbiter_drain` /
`lib/arbiter.sh drain` advances `swarm/<slug>/integration` from the queue, a completely different operation from
processing the ticket backlog unattended. `bin/stampede`'s own convention-dispatch pattern
(`lib/cli/stampede-<cmd>.sh` defining `stampede_cmd_<cmd>`, per its own header comment) makes a dedicated `headless`
subcommand the natural fit, not a flag on a name that already means something else.

## Done-Criteria

1. New file `lib/cli/stampede-headless.sh` defining `stampede_cmd_headless`, dispatched via `bin/stampede`'s
   existing convention (see `bin/stampede`'s own header comment — new commands land as new files, the dispatcher
   doesn't need to know the full list).
2. `bin/stampede headless` runs end-to-end against a scratch repo with queued tickets, no Herdr daemon required at
   all (verify by running with `herdr` deliberately not on `PATH`).
3. `--max-tickets N` and `--timeout M` are honored (finite batch, not an infinite loop).
4. `tests/test_cli.sh` gains coverage for the new subcommand's argument parsing and dispatch.
5. `CLAUDE.md`'s Commands section documents the new entrypoint.
6. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_cli.sh
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v herdr | paste -sd:) bin/stampede headless --max-tickets 1
```

## Resolution

- **Commit**: `155f3e4` (integrated into `swarm/stampede/integration`)
- **Review Verdict**: PASS (Round 1/2) by `reviewer-hinchk-stampede` (`.herdr-swarm/reviews/HEADLESS-6-155f3e459698f617411836b0cd8f1a13e7d1b3a7.md`)
- **Tests**: `tests/test_cli.sh` (31/31 passed), `make check` all 19 suites green.

