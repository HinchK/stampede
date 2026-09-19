---
id: T-007a
title: "Supervisor Bug Fixes and Re-Verdict Logic"
type: wayfinder:grilling
status: closed
assignee: looper
resolution_file: loop-bot-herd.sh
parent: maps/universal-herdr-swarm.md
---

# Supervisor Bug Fixes and Re-Verdict Logic

## Question

How should `loop-bot-herd.sh` resolve the PM audit's dormant deduplication bugs—specifically: (1) skipping re-verdicts after a RED result because any prior verdict matches, (2) regex substring collisions where ticket `#23` matches `#230`, and (3) crashes in `cmd_dispatch()` calling undefined `note` under `set -e`—and should these bugfixes land immediately prior to genericization?

## Resolution

Resolved directly in `loop-bot-herd.sh`:
1. **Deduplication Rewrite:** Replaced grep substring matching with structured `jq` queries over `$SESSION_LOG`. Tickets with `suite == "green"` or `suite == "skipped"` are permanently skipped; if previous test runs failed with `RED`, subsequent distinct verdict lines for the same ticket (e.g. after a fix commit) are allowed to run the suite gate again without getting dropped.
2. **Numeric Substring Disambiguation:** `jq --argjson t "$ticket"` performs strict numerical equality, preventing `#23` from matching `#230`.
3. **Missing Helper Definitions:** Defined `note()` and `step()` logging helpers in `loop-bot-herd.sh`, eliminating exit code 127 in `cmd_dispatch()`.
