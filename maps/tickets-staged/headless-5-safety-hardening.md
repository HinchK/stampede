---
id: HEADLESS-5
title: "Unattended safety hardening: re-verdict ceiling, timeouts, dead-letter logging"
type: wayfinder:task
status: backlog
assignee: arch
blocked_by: HEADLESS-4
owns: loop-bot-herd.sh,lib/headless.sh,swarm.config.toml,tests/test_headless.sh
parent: maps/headless-run-mode.md
---

# HEADLESS-5 — safety hardening (Slice 4)

**Source:** `docs/findings/headless-mode-design.md` §5 — the three hazards named there, blocked on HEADLESS-4's
harvesting loop existing to hook into.

## Intended Outcome

The three hazards the design doc identified as specific to unattended operation are closed:

1. **Runaway re-verdict/cost loops**: a per-ticket re-verdict ceiling, **configurable via `[headless]
   max_verdict_attempts` in `swarm.config.toml`** (default 2) — not a hardcoded shell constant, matching the
   precedent `[reviewer].max_rounds` already set for exactly this kind of bounded-retry knob. On reaching it, the
   ticket transitions to `DEAD_LETTER` and its lease releases — it does not retry forever.
2. **Hanging processes / lease starvation**: every headless subprocess runs under a hard wall-clock timeout
   (`timeout <N>s ...`, reusing the `resolve_timeout` pattern already in this repo per `CLAUDE.md`'s CI notes). A
   subprocess that dies without releasing its lease is evicted via PID-liveness check (`kill -0`), the same pattern
   PROVE-7 built for `arbiter.lock` — reuse that function, don't duplicate it.
3. **Silent swallowed alerts**: any `DEAD_LETTER` or `ALERT_BLOCKED` outcome during a headless run appends a
   structured record to `.herdr-swarm/dead-letter.jsonl`, and the headless runner exits non-zero if the batch ends
   with anything in that state — so a CI pipeline actually notices.

## Done-Criteria

1. `[headless] max_verdict_attempts` read from `swarm.config.toml` (default 2 when the section/key is absent, same
   optional-with-default pattern `[reviewer]` uses), enforced; `DEAD_LETTER` status implemented and releases its
   lease.
2. Every `headless_spawn`-started subprocess is timeout-wrapped; a killed-for-timeout subprocess's stale
   PID/lease is evicted on the next pass, not left dangling.
3. `.herdr-swarm/dead-letter.jsonl` gets a record for every `DEAD_LETTER`/`ALERT_BLOCKED` outcome; the headless
   entrypoint's exit code is non-zero if the dead-letter log has any entry from this run.
4. `tests/test_headless.sh` gains: a stub worker that never emits a verdict (proves the timeout fires and the lease
   frees), a stub that always fails tests (proves `DEAD_LETTER` after `MAX_VERDICT_ATTEMPTS`), and an assertion on
   the non-zero exit code.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_headless.sh
```
