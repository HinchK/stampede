---
id: DOG-10
title: "HUMAN-GATED: rename project to stampede, including the slug migration"
type: wayfinder:task
status: blocked
assignee: looper
owns: swarm.config.toml
parent: maps/public-readiness.md
---

# DOG-10 — Rename to `stampede` (WAVE 6 — HUMAN-GATED)

> `status: blocked` is deliberate. Do **not** pull this in auto-queue mode. It
> requires a swarm teardown and a manual ref move. Surface it to the human driver
> and stop.

## 1. Intended Outcome

The project is called `stampede` everywhere a human reads it, with the live
integration ref migrated rather than orphaned.

## 2. Why this is not a sed job

`[swarm] name` feeds `slugify()`, which produces:

- the **integration ref** `swarm/<slug>/integration` — the arbiter's CAS
  baseline, compared by `update-ref <ref> <new> <expected-old>`
- worktree paths `.herdr-swarm/worktrees/<seat>`
- seat branch names `swarm/<slug>/<seat>`
- the agent names baked into the live `.herdr-swarm/seats.json`

Change that one TOML value while a floor is up and the CAS baseline is orphaned:
the next `drain` compares against a ref that no longer exists, and any live seat
branch is stranded.

Measured in the source repo: **473** occurrences of `loop-bot-herd-agy`.

## 3. The name map — four separate decisions

| Thing | Today | Recommendation |
|---|---|---|
| GitHub repo | `HinchK/stampede` | keep — already correct |
| Human-facing name, docs, README | `Herdr Loop Swarm` | `Stampede` |
| `[swarm] name` (drives `slugify()`) | `loop-bot-herd-agy` | `stampede`, **as a migration** |
| Script filenames | `herdr-loop-swarm.sh`, `loop-bot-herd.sh` | `stampede.sh`, `stampede-supervisor.sh` — breaks every documented command; same pass or not at all |
| State dir `.herdr-swarm/` | — | **keep** — churn with no benefit, and it is gitignored |

## 4. Procedure (human driver, floor down)

```bash
./herdr-loop-swarm.sh down . -y            # 1. tear the floor down
bash lib/arbiter.sh drain                  # 2. drain the queue empty
bash lib/arbiter.sh promote                # 3. promote, confirm queue empty

git update-ref refs/heads/swarm/stampede/integration \
               refs/heads/swarm/loop-bot-herd-agy/integration   # 4. move CAS baseline
git branch -D swarm/loop-bot-herd-agy/integration               # 5. only after 4 verifies

# 6. bulk rename, then:
make check
```

## 5. Done-Criteria

1. Floor down and arbiter queue empty **before** any rename.
2. Integration ref moved; old ref deleted only after the new one verifies.
3. `grep -rc loop-bot-herd-agy` returns 0 outside `docs/adr/` and `docs/audits/`.
4. `make check` green after the rename.
5. `git branch --no-merged main` empty.

## 6. Verification Step

```bash
git rev-parse refs/heads/swarm/stampede/integration
bash lib/arbiter.sh drain           # must report an empty queue
grep -rn 'loop-bot-herd-agy' --include='*.sh' --include='*.toml' --include='*.md' . \
  | grep -v '^./docs/adr\|^./docs/audits'
make check
```
