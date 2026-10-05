---
id: HL-CONFIG-1
title: "Project-level .opencode/opencode.json: valid model pin + external_directory permission"
type: wayfinder:task
status: resolved
assignee: arch
owns: .opencode/
parent: maps/next-horizon.md
---

# HL-CONFIG-1 -- unblock HORIZON-2's F1/F4 preconditions

## Intended Outcome

A project-level `.opencode/opencode.json` exists in this repo so a spawned `opencode` worker (interactive or
headless) no longer falls back to the stale global `~/.config/opencode/opencode.json`, which pins a
provider-model string (`zai-coding-plan/glm-4.6`) that no longer exists on the provider endpoint (F1) and lacks
`external_directory` permission needed to read briefs that live outside the worker's worktree cwd (F4). Driver
approved creating this 2026-10-01.

## Background

Confirmed via `swarm.config.toml`'s `[seats.arch_2]`: the currently-working model string live interactive seats
actually use is `model = "zai/glm-5.3"` -- use this exact string, not the stale global default. Verify it's still
correct at implementation time (re-check `swarm.config.toml` and/or a live seat's actual active model) rather
than trusting this ticket's copy of it, in case it's drifted since this was written.

## Done-Criteria

1. `.opencode/opencode.json` created with:
   - A valid, currently-correct model pin matching what `swarm.config.toml`'s arch seats actually use.
   - `"permission": { "external_directory": "allow" }`.
2. Does not touch `~/.config/opencode/opencode.json` (the global default) -- project-level config only, scoped to
   this repo.
3. Verify a spawned opencode worker (interactive, not headless -- this file affects both) picks up this config
   over the global default and does not regress anything about how arch-1/arch-2 currently operate.
4. `make check` green, 0 shellcheck warnings (if any shell touches this -- likely none, this is config-only).

## Verification Step

Spawn or inspect a worker and confirm its effective model/permission config reflects this file, not the global
default. Human/pm review given this affects live interactive seat defaults, not just headless.

## Notes

This is a prerequisite for `HORIZON-2` (prove `stampede headless` live on this repo), not `HORIZON-2` itself --
`HORIZON-2` stays staged until this lands AND queue-isolation is handled at actual run time (confirmed: headless
has zero assignee filtering, picks up any `status: backlog` ticket in `maps/tickets/`).

## Resolution

- **Author:** `arch-1-hinchk-stampede` (commit `2cf79c017f2238988f09433fc1057406c5037fb1`)
- **Review:** `reviewer-hinchk-stampede` Round 1/2 PASS (`.herdr-swarm/reviews/HL-CONFIG-1-2cf79c017f2238988f09433fc1057406c5037fb1.md`)
- **Integrated:** `ec5baa2` onto `swarm/stampede/integration` via `arbiter_enqueue_and_drain`
- **Summary:** Created repository-level `.opencode/opencode.json` pinning `"model": "zai/glm-5.3"` (matching `swarm.config.toml` arch seats) and granting `"permission": { "external_directory": "allow" }`. Resolves HORIZON-2 preconditions F1 (stale global model fallback) and F4 (brief access outside worker worktrees) without touching global `~/.config/opencode/opencode.json`. Verified via `opencode debug config` inside worktree that project config takes precedence while retaining global MCP servers and provider configurations; `make check` green (19 suites).

