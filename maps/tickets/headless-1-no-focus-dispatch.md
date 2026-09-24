---
id: HEADLESS-1
title: "Dispatch calls don't pass --no-focus, stealing the human's pane focus on every herd prompt"
type: wayfinder:defect
status: backlog
assignee: arch
owns: loop-bot-herd.sh,herdr-loop-swarm.sh,briefs/looper.in.md
parent: maps/universal-herdr-swarm.md
---

# HEADLESS-1 — stop stealing focus on dispatch

## Intended Outcome

Every place this repo's own code (or its briefs, which instruct `looper`) calls `herdr agent prompt` for
background dispatch passes `--no-focus`, so routine ticket dispatch stops switching the human's visible pane away
from whatever they're actually looking at. The `herdr` CLI already supports this — nothing to build, just an audit
and a flag.

## Background

Confirmed this session: `pm`'s own `herdr agent prompt looper-hinchk-stampede "..." --wait --timeout 120000` calls
(used repeatedly to dispatch the `Prove and Reconcile` and `TRUST-1` epics) never passed `--no-focus`, meaning
every single dispatch likely switched the human's visible tab to `looper`'s pane. The herdr skill's own guidance is
explicit: "Use `--no-focus` for background work unless the user asked to switch context." This is the cheap half of
"headless mode" — no architecture change, just an audit.

## Done-Criteria

1. `grep -rn "herdr agent prompt" .` across `loop-bot-herd.sh`, `herdr-loop-swarm.sh`, and any brief that
   instructs an agent to prompt another agent (`briefs/looper.in.md` etc.) — every call for *routine* background
   dispatch gets `--no-focus`.
2. Calls that legitimately want to switch the human's attention (e.g. a blocked/approval-needed state) are left
   alone and the ticket says which ones and why.
3. `make test` green.

## Verification Step

```bash
grep -rn "herdr agent prompt" . --include="*.sh" --include="*.md" | grep -v "no-focus\|test"
# should only list calls with a documented reason to keep focus
```

## Notes

This ticket is scoped narrowly on purpose — it's the well-understood, low-risk half of "headless mode." The bigger
question (a true unattended `--headless` run mode with no panes at all) is HEADLESS-2, a research ticket, because
the destination for that isn't settled yet.
