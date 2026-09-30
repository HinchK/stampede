---
id: HEADLESS-3
title: "Headless subprocess harness: spawn, track, and log a worker without a Herdr pane"
type: wayfinder:task
status: resolved
commit: b157772d6d6fd26171f6af36b81640eee6eb413d
assignee: arch
owns: lib/headless.sh,tests/test_headless.sh
parent: maps/headless-run-mode.md
resolution:
  commit: b157772d6d6fd26171f6af36b81640eee6eb413d
  status: resolved
  integrated_at: b157772
  integration_ref: swarm/stampede/integration
  reviewer_verdict: PASS
  review_file: .herdr-swarm/reviews/HEADLESS-3-b157772d6d6fd26171f6af36b81640eee6eb413d.md
  channel_report: .herdr-swarm/channel/arch-1-hinchk-stampede-headless-3-round2.md
github_issue: 76
github_url: "https://github.com/HinchK/stampede/issues/76"
synced_at: "2026-09-30T17:16:14Z"
---

# HEADLESS-3 — subprocess harness (Slice 3a)

**Source:** `docs/findings/headless-mode-design.md` §2 Approach A.

## Intended Outcome

A new `lib/headless.sh` can spawn a single worker's vendor CLI as a direct background subprocess (no Herdr pane),
track its PID, redirect its output to a durable log, and deliver its brief via the existing compact-pointer
protocol — CLI-flag or stdin, per vendor, not PTY prompt injection. This ticket builds and unit-tests the harness
in isolation; it does not wire it into `loop-bot-herd.sh` yet (that's HEADLESS-4).

## Done-Criteria

1. `headless_spawn WORKER BRIEF_FILE WORKTREE_DIR` starts the worker's vendor CLI as a background subprocess,
   records its PID at `.herdr-swarm/pids/<worker>.pid`, and redirects stdout/stderr to
   `.herdr-swarm/logs/<worker>.log`.
2. Brief delivery reuses the nonce/channel protocol from `loop-bot-herd.sh:734-738` (`REPLY CHANNEL: write your
   complete response to $out`), delivered via the vendor CLI's non-interactive entrypoint (e.g. `claude -p`,
   `opencode run`), not PTY injection — no `sleep 1` / synthetic `enter` keystrokes anywhere in this file.
3. `headless_status WORKER` reports running/exited/dead (PID liveness via `kill -0`, matching the pattern already
   used in `lib/arbiter.sh:_arb_promote_pane_check` / `PROVE-7`'s stale-lock eviction — reuse, don't reinvent).
4. `headless_kill WORKER` sends a signal and cleans up the PID file.
5. `tests/test_headless.sh` is hermetic — stubs a fake vendor CLI (a short-lived shell script standing in for
   `claude`/`opencode`), no network, no real Herdr daemon required.
6. `make check` green (new suite added to the aggregate), 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_headless.sh
```

## Notes

Do not touch `loop-bot-herd.sh` in this ticket — harvesting integration is HEADLESS-4, staged and blocked on this
one landing first.
