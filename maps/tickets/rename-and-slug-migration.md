---
id: DOG-10
title: "Rename: loop-bot-herd-agy becomes stampede (slug + branch namespace migration)"
type: wayfinder:task
status: closed
assignee: human
resolution_commit: a552d34
owns: .herdr-swarm/,swarm.config.toml,herdr-loop-swarm.sh,loop-bot-herd.sh
parent: maps/public-readiness.md
github_issue: 64
github_url: "https://github.com/HinchK/stampede/issues/64"
synced_at: "2026-09-22T06:30:55Z"
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

1. [x] `./herdr-loop-swarm.sh down <dir> --yes` — floor down: panes closed,
   worktrees pruned, ledger cleared. Salvage lands in
   `.herdr-swarm/salvage/` if anything was dirty. *(human)*
2. [x] `mv ~/Fun/loop-bot-herd-agy ~/Fun/stampede` (or re-clone as `stampede`).
   *(human)*
3. [x] Update slug source if it derives from the directory name (see
   `slugify()` in `lib/common.sh` and the `[swarm]` table in
   `swarm.config.toml`); otherwise set it explicitly. *Finding: the slug
   derives from `REPO` in `profile.env` (git remote → `HinchK/stampede` →
   `hinchk-stampede`), not the dirname; `[swarm] name` was a dangling ref and
   is now `stampede` (`a552d34`).*
4. [x] Delete-or-keep decision per old `swarm/loop-bot-herd-agy/*` branch —
   they are namespaced under the old slug and will not be re-adopted.
   *Both branches fully merged into `main`; GitHub already had none
   (`ls-remote` empty). Deleted locally (`d50c128` integration, `144efea` pi)
   after `worktree repair` + clean `worktree remove` of their path-orphaned
   registrations. Dangling `local-source` remote removed from the dogfood
   clone.*
5. [x] `./herdr-loop-swarm.sh up ~/Fun/stampede -m s` — re-seat fresh.
   *6 seats interactive-ready in `wT`. First-run trust prompts in the new cwd
   ("trust this folder" — claude, agy) blocked the initial seating; answered
   per pane, and `agent start --timeout` raised (default 30s is too short for
   first-run boots with MCP).*
6. [x] `grep -rn 'loop-bot-herd-agy' . --exclude-dir=.herdr-swarm` → fix stragglers.
   *Living files fixed (`a552d34`): Makefile header, `swarm.config.toml`
   name + Location comments, launcher Location, README tree, CONTEXT example.
   Historical receipts (`docs/findings`, `docs/audits`, `docs/adr`, `maps/`)
   intentionally retain the old name — they quote real output from the era —
   so the verification grep is scoped to living files (human decision).*

## 5. Verification Step

```bash
./herdr-loop-swarm.sh verify ~/Fun/stampede
grep -rn 'loop-bot-herd-agy' . --exclude-dir=.git --exclude-dir=.herdr-swarm \
  --exclude-dir=maps --exclude-dir=findings --exclude-dir=audits \
  --exclude-dir=adr --exclude-dir=dogfood ; echo "rc=$? (want 1)"
make check
```

Receipts (2026-09-21):

- `verify` → `✓ All seats verified ready` (pm, arch-1, arch-2, looper,
  agy-docs, agy-gh — all `interactive-ready` in `wT`).
- Scoped grep → `rc=1` at `~/Fun/stampede`.
- `make lint` → clean (14 files). Suites: worktree 42, arbiter 38, partition
  29, profile 18, pyenv 16 — all green. `test_async_gate` 16/17: `[1b] scan
  blocked` fails identically at pre-rename baseline `d0fb40f` under load
  average ~12 (measured 1791ms/1977ms/2080ms vs 1500ms budget) — timing
  flake, environmental, not caused by the rename.
