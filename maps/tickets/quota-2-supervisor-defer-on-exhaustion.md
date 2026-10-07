---
id: QUOTA-2
title: "Supervisor defers reviewer dispatch on account-wide agy quota exhaustion, retries on clear"
type: wayfinder:task
status: resolved
assignee: arch-1-hinchk-stampede
owns: loop-bot-herd.sh,lib/quota.sh,tests/test_async_gate.sh
parent: maps/universal-herdr-swarm.md
---

# QUOTA-2 -- pause reviewer dispatch on agy quota exhaustion, retry through

## Intended Outcome

`loop-bot-herd.sh`'s `DISPATCH_REVIEWER` directive (in `_review_directives`) checks `quota_probe_kind agy`
before calling `worker_feedback` on the reviewer seat. If the probe reports the account is exhausted, the
dispatch is **deferred, not dropped** -- the supervisor retries it on a later poll cycle once the probe clears.

## Background

Chartered via /wayfinder grilling, 2026-10-06 (no map needed -- scope settled tight enough for one ticket).
Motivated by a real incident this session: `looper` (agy/Gemini via Antigravity CLI) hit an account-level
quota wall mid-session and sat blocked for ~90 minutes; the human had to manually detect and wait it out.
`QUOTA-1` (shipped this session) built the read-only `quota_probe_kind agy` signal specifically as groundwork
for this follow-up, which it explicitly deferred: "If loop-bot-herd.sh should eventually pause dispatch on a
seat with known-exhausted quota, that's a separate, future ticket informed by actually having this probe
available first."

Settled via grilling (all deliberate, not guessed):
- **Scope: `agy` only.** The four `agy`-kind seats (`looper`, `reviewer`, `agy-docs`, `agy-gh`) share one
  account; `opencode`/`claude` have no known quota signal yet and are out of scope for this ticket.
  Account-wide scope is the point: it's one shared account, not four independent quota pools.
- **Account-wide pause, not per-seat.** `quota_probe_kind agy` reporting exhaustion on any pane is evidence
  the whole account is exhausted (same account, same limit) -- there is no per-seat quota to isolate.
- **Supervisor-only for this ticket.** `loop-bot-herd.sh`'s automated `DISPATCH_REVIEWER` dispatch is real,
  testable shell code. `looper`'s own interactive dispatch to `reviewer`/`agy-docs`/`agy-gh` via
  `herdr agent prompt` is an LLM agent following its brief, not code the suite gate can verify -- that's a
  separate, later ticket if this pattern proves out, not bundled here.
- **Proactive, not reactive.** Check the probe before the dispatch attempt, not after a failed one -- `QUOTA-1`'s
  probe is a cheap pane-output scan, so checking first avoids wasting a dispatch (and burning more quota) on
  an already-exhausted account.
- **Defer-and-retry, not skip-and-drop.** `review_loop_on_gate_green` fires once, at gate-green harvest, and
  emits `DISPATCH_REVIEWER` as a one-shot directive -- there is currently no mechanism to re-trigger a skipped
  dispatch later. This ticket must add one (a pending-dispatch marker the poll loop rechecks each cycle until
  quota clears), not just skip the call.

## Done-Criteria

1. In `_review_directives`'s `DISPATCH_REVIEWER` case: before calling `worker_feedback` on the reviewer seat,
   call `quota_probe_kind agy` (against the reviewer's own recent pane output, same signature `QUOTA-1`
   established). If exhausted, do NOT call `worker_feedback` -- instead record a pending-dispatch marker
   (ticket, sha, round, max) that survives across poll cycles.
2. Each `loop-bot-herd.sh` poll cycle (`once`/`watch`), before anything else that would dispatch to an `agy`
   seat, checks for any pending deferred dispatches and re-attempts them if the probe now clears. A cleared
   probe retries ALL pending dispatches for the account, not just one.
3. While paused: no NEW `DISPATCH_REVIEWER` call is attempted either -- same account-wide gate applies to
   fresh gate-green harvests during the pause window, not just the one that got deferred first.
4. Telemetry/logging: a deferred dispatch and its eventual retry are both visible (log line at minimum;
   `lib/telemetry.py` event if that's cheap to add, don't force it if it's not).
5. Test coverage in `tests/test_async_gate.sh` (or wherever the existing review-loop dispatch tests live --
   check first) proving: (a) a dispatch is deferred when the probe reports exhaustion, not attempted; (b) the
   deferred dispatch is NOT lost -- it fires once the probe clears on a later cycle; (c) a second ticket's
   gate-green during the pause window also defers, not just the first.
6. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_async_gate.sh
```

## Notes

This does not touch `looper`'s own interactive dispatch behavior, and does not extend probing to `opencode`/
`claude` -- both are explicitly out of scope for this ticket per the grilling above. If this pattern proves
out in practice, extending it to looper's own brief-level dispatch is a natural follow-up, informed by having
this land first.

## Resolution

Resolved at commit `87c1cb21576eb2d27aeeaa0a8630ffd94519b198`.
- In `_review_directives`'s `DISPATCH_REVIEWER` case in `loop-bot-herd.sh`, proactive check probes `quota_probe_kind agy` against reviewer seat (`_agy_quota_exhausted`). If positive exhaustion (`ok:<seconds>s`), defers dispatch with a durable record in `.herdr-swarm/quota-deferred.jsonl`, emits `review.deferred` telemetry, and alerts. Normal/unknown responses proceed unhindered.
- Unified reviewer dispatch implementation factored into `_dispatch_reviewer`.
- `cmd_once` runs `_quota_retry_deferred` first each cycle, retrying all deferred dispatches once quota clears and draining the marker.
- The pause gate checks the probe directly, so fresh gate-greens during an exhaustion window also defer into the marker.
- Comprehensive test coverage in `tests/test_async_gate.sh` (§16, 10 assertions, 66/66 passing).
- Autonomous review PASS verdict by `reviewer-hinchk-stampede` (Round 1/2) in `.herdr-swarm/reviews/QUOTA-2-87c1cb21576eb2d27aeeaa0a8630ffd94519b198.md`.
- Integrated onto `swarm/stampede/integration` via `arbiter_enqueue_and_drain` at `87c1cb2`. Lease released cleanly.
