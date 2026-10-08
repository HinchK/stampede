---
id: FALLBACK-1
title: "Standby orchestrator seat: quota-triggered, single-command takeover and stand-down"
type: wayfinder:task
status: backlog
assignee: arch
owns: swarm.config.toml, briefs/looper-standby.in.md, lib/standby.sh, tests/test_standby.sh
parent: maps/dispatch-safety-and-review-policy.md
---

# FALLBACK-1 -- turn the 2026-10-08 improvised stand-in into a supported seat

## Intended Outcome

When the agy account quota walls the herd, the driver (or the supervisor's alert) can
bring up a non-agy orchestrator with ONE command, it runs under a restricted brief, and
a clean handshake returns control to the real `looper` -- never two orchestrators
dispatching at once.

## Background (receipts, PM audit 2026-10-08)

Experiment: PM started `looper-temp-hinchk-stampede` (opencode,
`zai-coding-plan/glm-5.3-flash`, pane `wY:pK`) while looper/agy-docs/reviewer were
walled. It harvested CI-FIX-2, dispatched QUOTA-5 (back in 10m55s), wrote an accurate
handoff, broke no rules (no stash, no promote, no agy dispatch). It cost ~25 min of one
cheap seat. It worked only because the PM improvised: split pane, `agent start`, hand-
written scoped prompt, hand-set timers, hand-closed handoff. Existing PUB-6 fallback
chains (`kinds = [...]`) cover absent/unhealthy providers, not an exhausted quota.

## Done-Criteria

1. A `[seats.looper_standby]` table, `enabled = false` by default, kind opencode, model
   from config (default `zai-coding-plan/glm-5.3-flash` -- note this differs from the
   `zai/glm-5.3` pin spelling; use whichever `opencode models` accepts), agent name
   `looper-standby-<slug>` (names are global in Herdr). Not auto-seated by `up`.
2. `briefs/looper-standby.in.md`: mechanics only -- harvest `ARCH DONE`, partition
   check + lease, dispatch to arch seats, `wait-output` on anchors, handoff file at
   `.herdr-swarm/research/looper-standby-handoff.md`. Hard rules baked in: no agy
   dispatch while the wall is up, no promote, no stash, no `main` writes, no edits to
   forbidden paths, no verdict judgement beyond reporting (the temp looper called a
   blocked review "integrated").
3. `lib/standby.sh up|down|status`: `up` splits a pane by explicit ID (never
   `--current`), `cwd` = repo root, starts the seat, delivers the brief by file path;
   `down` runs the handshake, never closes a pane without confirmation.
4. Single-orchestrator guarantee: a lock/lease on the orchestrator role. Standby cannot
   acquire it while the real looper holds it, and takeover requires the real looper to
   be walled (gate says exhausted, per QUOTA-5) or the driver to force it explicitly.
   Real looper resuming must observe the lock and wait for the handoff.
5. Alert: on first detected exhaustion the supervisor emits `herdr notification show`
   (HERDR-5 mechanism) naming the standby command. Advisory only -- it never
   auto-starts the seat.
6. Tests: seat disabled by default, `up` refuses without exhaustion unless forced, lock
   prevents double orchestration, brief render contains every hard rule.

## Out of scope / Input to REV-07

The experiment's real weak point was REVIEW: every review stays on the agy reviewer, so
the stand-in could dispatch but not integrate. A fallback reviewer on another provider
is a policy decision (trust, rubric parity, quorum) and belongs to
`maps/tickets/rev-07-multi-reviewer-quorum-decision.md`; this ticket does not build it.
PM recommendation for that session: decide it first, FALLBACK-1 is half a fix without it.

## Verification Step

`make check` green. Live drill (human-gated, like HORIZON-2): force-exhaustion fixture,
`standby up`, confirm lock and brief, `standby down`, confirm the real looper resumes
cleanly. Record receipts in the hand-off.
