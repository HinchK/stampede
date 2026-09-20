---
id: P3-1
title: "Multi-Worker Config & Dynamic Roster Expansion"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: swarm.config.toml,lib/config.sh,herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
---

# Multi-Worker Config & Dynamic Roster Expansion (P3-1)

## Context & Problem Statement

With Phase 2's worktree lifecycle, suite gating, and arbiter engine verified (63/63 tests passing), Phase 3 expands the swarm from a single implementation worker (`arch`) to multiple concurrent workers (`arch_1`, `arch_2`, etc.) operating simultaneously in isolated git worktrees.

## Preamble

1. **Intended Outcome**: `arch` implements multi-worker seating in `swarm.config.toml`, `lib/config.sh`, and `herdr-loop-swarm.sh` per [docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md).
2. **Explicit Done-Criteria**:
   - `swarm.config.toml`:
     - Configure multiple implementation seats (`arch_1` with GLM-5.3, `arch_2` with Sonnet or alternative), each with `worktree = true`.
   - `lib/config.sh`:
     - Validate that multiple worktree seats export valid `SEAT_WORKTREE_<seat>=1` flags.
     - `config_plan_preview` renders all workers cleanly with their respective worktree indicators.
   - `herdr-loop-swarm.sh`:
     - Provisions distinct worktree paths (`.herdr-swarm/worktrees/arch-1-<slug>`, `.herdr-swarm/worktrees/arch-2-<slug>`) and separate branches (`swarm/<slug>/arch_1`, `swarm/<slug>/arch_2`).
     - Serializes all worker seats into `.herdr-swarm/seats.json` v2.
   - Quality checks:
     - `shellcheck lib/config.sh herdr-loop-swarm.sh` passes cleanly with 0 warnings.
     - `bash tests/test_worktree.sh` and `bash tests/test_arbiter.sh` continue to pass 100%.
3. **Verification Step**:
   - Run `bash lib/config.sh plan preview`.
   - Run `shellcheck lib/config.sh herdr-loop-swarm.sh`.
   - Commit changes and emit `ARCH DONE #26 <commit_sha>`.
