---
id: HORIZON-1
title: "Integrate BRIEF-1, promote integration to main, push"
type: wayfinder:task
status: backlog
assignee: human
owns: STATE.md
parent: maps/next-horizon.md
blocked_by: []
---

# HORIZON-1 — integrate and promote the incident follow-up

## Intended Outcome

The BRIEF-1 brief-text change (commit on the arch branch, gated green) is
integrated onto `swarm/stampede/integration`, promoted to `main` by the human
driver, and pushed to `origin/main` — so the anti-bypass briefs render for
every future seat, and the batch (HORIZON-2) runs with them live.

## Done-Criteria

1. `lib/arbiter.sh drain` advanced past `32dc565` cleanly (no conflict).
2. Human runs `bash lib/arbiter.sh promote --confirm` from the root checkout
   on `main`, then pushes — the standing PROVE-1 pattern.
3. STATE.md records the promote receipts.

## Verification Step

`git log --oneline origin/main -3` names the BRIEF-1 commit; `./herdr-loop-swarm.sh status` clean.

## Notes

Everything before the promote is machinery that already ran; the human act is
the point (and the mechanism itself now checks that, GATE-1).
