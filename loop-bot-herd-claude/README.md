# herdr-loop-swarm

A parallel, self-healing evolution of the kultivait herd. The current herd
(`herdr-kultivait-session.sh`) is **sequential** — looper dispatches arch one
ticket at a time on a single `main` checkout. This fans a task list into **N
workers in parallel**, each in its own git worktree, watches them via herdr's
own agent signals, verifies every task independently, and integrates through
**one arbiter** that opens a single PR.

## Why (each feature is an observed failure of the sequential herd)

| # | Improvement | The failure it fixes |
|---|---|---|
| 1 | Parallel workers | arch does one ticket at a time; #221's children are independent |
| 2 | git worktree per task | everything on one `main` checkout → local main drifted 17 commits |
| 3 | file-ownership partition | no safe way to run two tasks at once without collisions |
| 4 | watchdog (agent_status + state_change_seq) | agy delegations stalled twice; a loose agent orphaned |
| 5 | durable `.swarm/` ledger | usage limits killed sessions at the finish line; state re-discovered |
| 6 | independent verify gate (non-zero test count) | workers self-report green; false-green slipped through |
| 7 | cost-routed workers + arbiter | everything hit one model; no integration step |

## Safety

- **Dry-run by default.** Nothing is seated and no worktrees change until `--live`.
- **Never pushes the base branch.** The arbiter opens a PR; a human merges.
- All state lives in `<repo>/.swarm/` — delete it to reset.

## Use

```bash
# 1. sanity-check your task partition (no two tasks may own the same file)
./herdr-loop-swarm.sh partition-check --tasks tasks.example.txt

# 2. dry-run against a real repo: seats nothing, but builds .swarm/, the ledger,
#    routes each task to an agent kind, and walks the whole loop once
./herdr-loop-swarm.sh run --repo ~/seeds/_KULT_/kultivait --tasks tasks.example.txt

# 3. for real (seats herdr agents in worktrees, verifies, opens one PR)
./herdr-loop-swarm.sh run --repo ~/seeds/_KULT_/kultivait --tasks tasks.example.txt --live --max 3

# inspect / resume / stop
./herdr-loop-swarm.sh status --repo ~/seeds/_KULT_/kultivait
./herdr-loop-swarm.sh resume --repo ~/seeds/_KULT_/kultivait --live   # cold-restart from the ledger
./herdr-loop-swarm.sh stop   --repo ~/seeds/_KULT_/kultivait
```

## Task file

`id | tier | owns (space-separated paths) | prompt`, one per line. `tier` routes
to an agent kind: `code`→opencode (GLM), `docs`/`mechanical`→agy (cheap/fast),
`hard`→claude. Override any mapping with `KIND_CODE=…`, `KIND_DOCS=…`, etc.

## Knobs (env)

`SWARM_MAX` (3), `BASE_BRANCH` (main), `TICK_SECS` (20), `STALL_SECS` (600),
`MAX_RELAUNCH` (1), `TEST_CMD` (auto: pytest / npm test), and the `KIND_*` routes.

## Status: iteration 1

Working: partition invariant, durable ledger + resume, cost routing, dry-run
walk, worktree seating, watchdog logic, arbiter hand-off. Not yet: dependency
ordering between tasks (arbiter merge order is naive), a blocked-task async
answer channel, and richer verify (typecheck/lint, not just the suite). Iterate.
