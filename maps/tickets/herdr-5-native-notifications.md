---
id: HERDR-5
title: "Supervisor human-visible alerts also emit herdr notification show"
type: wayfinder:task
status: resolved
assignee: arch
owns: loop-bot-herd.sh, tests/test_async_gate.sh
parent: maps/herdr-native-and-seat-utilization.md
blocked_by: [HERDR-1]
---

# HERDR-5 -- notify, don't hope

## Intended Outcome

The supervisor's human-visible alert points — agy quota deferral (`QUOTA-2` marker),
review-loop `ALERT_BLOCKED`, headless dead letters, RED-gate escalation — additionally
emit `herdr notification show` when running inside Herdr (`HERDR_ENV=1` and probe
passes), so the driver learns of a stall from the OS, not from the Ops pane's
scrollback.

## Background

ADR 0017 Decision 3. Retrospective: a quota stall took ~90 minutes to reach the human;
a native notification exists (`herdr notification show`) and was never used. The trace
stream remains the durable record — the notification is additive, never a replacement.

## Done-Criteria

1. One tiny emit helper (alert sites call it; lives beside the existing warn/note
   helpers in `loop-bot-herd.sh`): probe `herdr notification --help` once, HERDR_ENV
   gate, fire-and-forget with `|| true` (a notification failure must never fail a
   supervisor pass), message prefixed `[stampede:<slug>]`.
2. Wired at minimum into: quota-defer alert (QUOTA-2 seam), `ALERT_BLOCKED`
   (`_review_directives`), headless dead-letter path, RED verdict alert.
3. Degradation silent-but-logged: outside Herdr or probe-absent → one debug line,
   zero behavior change.
4. Tests extend `tests/test_async_gate.sh` (the alert seams' home suite) with stubbed
   `herdr`: notification emitted on alert inside HERDR_ENV=1; not emitted when
   probe fails or HERDR_ENV unset; alert path exit codes unchanged.

## Verification Step

`make check` green. Live receipt: trigger one real notification (e.g. dry-run a
quota-defer alert) and confirm it appears as an OS notification on the driver's
machine.

## Notes

Keep the message under one terminal line: ticket/seat/reason + pointer to the durable
record (`.herdr-swarm/...` path or trace id).

## Resolution (2026-10-07)

Resolved in commit `cb26aaf686aed1b6e00f2581a670768179cb7f1c` (`cb26aaf`).
Added `_supervisor_notify` helper in `loop-bot-herd.sh` wrapping `herdr notification show` with HERDR_ENV and `--help` probe checks, fire-and-forget execution, and `[stampede:<slug>]` prefix. Wired into quota deferral, ALERT_BLOCKED, headless dead letter, and RED verdict alerts. Verified in `tests/test_async_gate.sh` with 56 passing assertions. Integrated at `cb26aaf`.
