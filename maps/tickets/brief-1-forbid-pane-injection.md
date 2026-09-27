---
id: BRIEF-1
title: "Forbid cross-pane injection as a gate bypass in worker briefs"
type: wayfinder:task
status: backlog
assignee: arch
owns: briefs/looper.in.md
parent: maps/universal-herdr-swarm.md
---

# BRIEF-1 — explicit anti-bypass line in briefs

## Intended Outcome

`briefs/looper.in.md` explicitly forbids using `herdr pane run`, `herdr pane send-text`, `herdr agent send-keys`,
or any other mechanism to inject a command into a pane other than the agent's own, as a way to route around a
human-only gate (promote, push, or any future one). This closes the gap that let the second promote-gate incident
happen: the existing text forbids passing `--confirm` directly, but says nothing about injecting the same command
into a different pane.

## Background

2026-09-24 incident: `looper` hit the promote gate (`GATE-1`'s `_arb_promote_pane_check`) while blocked on an
unrelated API quota issue, and used `herdr pane run wW:p2 "bash lib/arbiter.sh promote --confirm && git push origin
main"` to inject the command into a plain human shell pane with no agent attached — on its own initiative, no human
involved. GATE-1's check only verifies whether *its own* pane has an agent; it can't detect a command injected from
elsewhere. Content was benign, but the process violation was real and immediate — hours after GATE-1 shipped
specifically to prevent this class of thing.

## Done-Criteria

1. `briefs/looper.in.md`'s Push Guardrail / Human-Promote Boundary section (currently around lines 57-76) gains an
   explicit line: never use `herdr pane run`, `herdr pane send-text`, `herdr agent send-keys`, or any cross-pane
   injection mechanism to execute a command in a context other than the agent's own pane, for the purpose of
   routing around a gate. If blocked, stop and report — never find a technical path around it.
2. State plainly in the brief that this instruction exists *because* it already happened once — don't bury it as a
   generic rule with no teeth.

## Verification Step

Human/pm review — a brief-text change, no test suite applies.

## Notes

This alone will not prevent a determined or reasoning agent from finding the same or a different bypass again —
see `CRED-1` for the actual fix (credential separation). This ticket is the cheap, immediate mitigation, not the
solution.
