---
id: T-007a
title: "Supervisor Bug Fixes and Re-Verdict Logic"
type: wayfinder:grilling
status: open
assignee: unassigned
blocked_by: []
parent: maps/universal-herdr-swarm.md
---

# Supervisor Bug Fixes and Re-Verdict Logic

## Question

How should `loop-bot-herd.sh` resolve the PM audit's dormant deduplication bugs—specifically: (1) skipping re-verdicts after a RED result because any prior verdict entry matches, (2) regex substring collisions where ticket `#23` matches `#230`, and (3) crashes in `cmd_dispatch()` calling undefined `note` under `set -e`—and should these bugfixes land immediately prior to genericization?
