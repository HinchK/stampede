---
id: REV-1
title: "Reviewer config flag and harvested verdict protocol (REVIEW VERDICT)"
type: wayfinder:task
status: ready
assignee: arch
owns: lib/config.sh,swarm.config.toml,briefs/reviewer.in.md,briefs/reviewer.md,tests/test_config.sh
parent: maps/autonomous-reviewer-loop.md
blocked_by: []
---

# REV-1 — Reviewer config flag and harvested verdict protocol (Wave 1)

## 1. Intended Outcome

1. Add `loop` and `max_rounds` configuration options to `[reviewer]` in `swarm.config.toml`, bound cleanly into shell variables in `lib/config.sh` (`CONFIG_REVIEW_LOOP`, `CONFIG_REVIEW_MAX_ROUNDS`).
2. Update `briefs/reviewer.in.md` (and re-render `briefs/reviewer.md`) so that when the review loop is active, the reviewer outputs:
   - A durable structured markdown report to `.herdr-swarm/reviews/<ticket>-<sha>.md` containing findings categorized as `[BLOCK]` or `[CONCERNS]` with citations (`file:line`), description, and remediation.
   - A standardized harvested terminal anchor on its own line:
     `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>`
3. Maintain backward compatibility: when `loop = false`, reviewer remains in advisory mode with `REVIEW DONE #<ticket> <sha>` as before.

## 2. Problem

PUB-8 established the reviewer brief as strictly advisory (`REVIEW DONE`), explicitly unharvested. To enable autonomous critique loops, the orchestrator needs an unambiguous, programmatically harvestable verdict (`PASS` vs `BLOCK`), a durable findings file on disk for the implementer to read, and a configuration switch to enable/disable this loop across herdr runs.

## 3. Plan

- `swarm.config.toml`: Add `loop = false` and `max_rounds = 2` under `[reviewer]`.
- `lib/config.sh`: Parse `loop` (boolean) and `max_rounds` (integer defaulting to 2) using `config_dump_env`.
- `briefs/reviewer.in.md`: Define the output contract: write report to `.herdr-swarm/reviews/<ticket>-<sha>.md` and emit `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>`.
- `briefs/reviewer.md`: Re-render using `lib/briefs.sh render reviewer <slug>`.
- `tests/test_config.sh`: Add assertions for `CONFIG_REVIEW_LOOP` and `CONFIG_REVIEW_MAX_ROUNDS`.

## 4. Explicit Done-Criteria

- `lib/config.sh` binds `CONFIG_REVIEW_LOOP` (0 or 1) and `CONFIG_REVIEW_MAX_ROUNDS` (positive integer).
- Brief templates render cleanly without unexpanded placeholders.
- 0 shellcheck warnings across modified shell files; tests in `test_config.sh` pass.

## 5. Verification Step

```bash
make check
bin/stampede doctor
```
