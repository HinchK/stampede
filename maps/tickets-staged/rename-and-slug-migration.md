---
id: DOG-10
title: "Rename: loop-bot-herd-agy becomes stampede (slug + branch namespace migration)"
type: wayfinder:task
status: ready
assignee: human
owns: .herdr-swarm/,swarm.config.toml,herdr-loop-swarm.sh,loop-bot-herd.sh
parent: maps/public-readiness.md
---

# DOG-10 — Rename + slug migration (WAVE 6 — HUMAN ONLY)

## 1. Intended Outcome

The working directory, swarm slug, and derived identifiers all say
`stampede`, with no dangling refs to the old name.

## 2. Problem

The repo directory is still `loop-bot-herd-agy` while the project, remote,
README, and LICENSE all say `stampede`. The slug is baked into agent names
(`<seat>-<slug>`), worktree branches (`swarm/<slug>/...`), and the seat
ledger. A rename while the swarm is seated leaves panes pointing at pruned
worktrees and branches that no longer match the ledger.

## 3. Why human-only

The rename moves the floor under every running seat, including the one that
would execute it. The ref moves by hand. **Never dispatched unattended.**

## 4. Checklist (execute in order)

1. `./herdr-loop-swarm.sh down <dir> --yes` — floor down: panes closed,
   worktrees pruned, ledger cleared. Salvage lands in
   `.herdr-swarm/salvage/` if anything was dirty.
2. `mv ~/Fun/loop-bot-herd-agy ~/Fun/stampede` (or re-clone as `stampede`).
3. Update slug source if it derives from the directory name (see
   `slugify()` in `lib/common.sh` and the `[swarm]` table in
   `swarm.config.toml`); otherwise set it explicitly.
4. Delete-or-keep decision per old `swarm/loop-bot-herd-agy/*` branch —
   they are namespaced under the old slug and will not be re-adopted.
5. `./herdr-loop-swarm.sh up ~/Fun/stampede -m s` — re-seat fresh.
6. `grep -rn 'loop-bot-herd-agy' . --exclude-dir=.herdr-swarm` → fix stragglers.

## 5. Verification Step

```bash
./herdr-loop-swarm.sh verify ~/Fun/stampede
grep -rn 'loop-bot-herd-agy' . --exclude-dir=.herdr-swarm ; echo "rc=$? (want 1)"
make check
```
