---
id: P2-2
title: "Worktree Config Binding, Ledger v2, and Launcher CWD Integration"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: swarm.config.toml,lib/config.sh,herdr-loop-swarm.sh
owns: swarm.config.toml,lib/config.sh,herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
---

# Worktree Config Binding, Ledger v2, and Launcher CWD Integration (P2-2)

## Question

How should `swarm.config.toml`, `lib/config.sh`, and `herdr-loop-swarm.sh` integrate the worktree lifecycle library (`lib/worktree.sh`), allowing per-seat worktree isolation (`worktree = true`), recording worktree directories and branches in `.herdr-swarm/seats.json` v2, and provisioning worktree directories prior to `split_pane` so panes spawn directly inside isolated worker checkouts?

## Preamble

1. **Intended Outcome**: `arch` implements P2-2 following PM's specification in [docs/audits/2026-09-19-p2-2-config-integration-spec.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-2-config-integration-spec.md).
2. **Explicit Done-Criteria**:
   - `swarm.config.toml`:
     - Add `worktree = true` for `[seats.arch]`. `pm`, `looper`, `docs`, `gh` omit or set `worktree = false`.
   - `lib/config.sh`:
     - Emits `SEAT_WORKTREE_<seat>=1|0` for each seat.
     - Adds `Worktree` column to `config_plan_markdown()`.
   - `herdr-loop-swarm.sh`:
     - Sources `lib/worktree.sh`.
     - In dynamic seating loop, if `SEAT_WORKTREE_<seat> == 1`:
       - Provisions worktree via `worktree_provision "$seat_name" "$PROJECT_SLUG" "HEAD" "$PWD"`.
       - Passes `wt_path` to `split_pane` so the pane is physically rooted in the worktree directory.
       - Starts the agent in that pane and records `name|kind|pane|wt_path|wt_branch` in `SEAT_LEDGER`.
     - Updates `.herdr-swarm/seats.json` serializer to output v2 ledger:
       `{ "workspace_id": "...", "version": 2, "seats": [ { "name": "...", "kind": "...", "pane": "...", "worktree_dir": "...", "branch": "..." } ] }`.
   - Quality checks:
     - `shellcheck lib/config.sh herdr-loop-swarm.sh` passes cleanly with 0 warnings.
3. **Verification Step**:
   - Run `bash lib/config.sh plan` and verify Worktree column displays `yes` for arch and `no` for others.
   - Run `shellcheck lib/config.sh herdr-loop-swarm.sh`.
   - Commit changes and emit `ARCH DONE #21 <commit_sha>`.
