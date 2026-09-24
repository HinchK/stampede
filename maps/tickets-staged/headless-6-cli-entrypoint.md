---
id: HEADLESS-6
title: "bin/stampede drain --headless CLI entrypoint"
type: wayfinder:task
status: backlog
assignee: arch
blocked_by: HEADLESS-5
owns: bin/stampede,lib/headless.sh,tests/test_cli.sh,CLAUDE.md
parent: maps/headless-run-mode.md
---

# HEADLESS-6 — CLI entrypoint (Slice 3c)

**Source:** `docs/findings/headless-mode-design.md` §3.

## Intended Outcome

`bin/stampede drain --headless [--max-tickets N] [--timeout M]` ties HEADLESS-3/4/5 together into the actual
user-facing command: iterate `backlog` tickets in `maps/tickets/` (the deterministic queue-intake replacement for
`looper`'s interactive judgment, per the map's Notes), dispatch each via `lib/headless.sh`, harvest via HEADLESS-4's
wiring, respect HEADLESS-5's safety caps, and terminate when the queue is empty or the caps are hit.

## Done-Criteria

1. `bin/stampede drain --headless` runs end-to-end against a scratch repo with queued tickets, no Herdr daemon
   required at all (verify by running with `herdr` deliberately not on `PATH`).
2. `--max-tickets N` and `--timeout M` are honored (finite batch, not an infinite loop).
3. `tests/test_cli.sh` gains coverage for the new subcommand's argument parsing and dispatch.
4. `CLAUDE.md`'s Commands section documents the new entrypoint.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_cli.sh
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v herdr | paste -sd:) bin/stampede drain --headless --max-tickets 1
```
