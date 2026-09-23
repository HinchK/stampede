---
id: PROVE-1
title: "Reconcile main into integration, promote and push DOG-17/18"
type: wayfinder:task
status: backlog
assignee: human
owns: STATE.md
parent: maps/prove-and-reconcile.md
---

# PROVE-1 — Reconcile, promote, push (Wave 1)

**Source:** `docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md` §2, §3, §10 step 0.

## Intended Outcome

`main` and `swarm/stampede/integration` stop being diverged, DOG-17/18 (`scripts/repo-state.sh`,
`scripts/ci-local.sh`) are promoted to `main`, and `main` is pushed to `origin` so CI actually sees the current tip.

## Background

```
$ git log --oneline main..swarm/stampede/integration
4025f4b feat: ci-local CI-parity wrapper with shellcheck pin check (#DOG-18)
f78b0a1 feat: single-command repo state summary script (#DOG-17)

$ git log --oneline swarm/stampede/integration..main
deadb3c docs: update STATE.md for DOG-17 and DOG-18 completion
c4ec368 docs(DOG-18): mark ci-local.sh resolved with receipts
858b7c4 docs(DOG-17): mark repo-state.sh resolved with receipts

$ git merge-base --is-ancestor main swarm/stampede/integration; echo $?
1
```

Local `main` is also 5 commits ahead of `origin/main` — nothing has been pushed yet; CI has not seen the current tip.

**Step 0, before anything else:** fold branch `worktree-pm-audit-2026-09-23` (this map, this ticket, and
`docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md`) into `main`. It's based off `origin/main`,
not local `main`'s tip — if it lands after the reconcile below instead of before, `main` diverges from
`integration` again immediately.

**Precedent:** the equivalent-shaped fix last time (`d7f875f`, "reconcile main base branch into integration") was
committed by the human driver directly, not an agent seat.

## Done-Criteria

1. `worktree-pm-audit-2026-09-23` is folded into `main`.
2. `main` is merged into `swarm/stampede/integration` (same shape as `d7f875f`), and `make test` passes on the
   combined tree (18 suites, per `STATE.md`'s figure — re-verify the count, don't trust it).
3. `swarm/stampede/integration` promotes to `main` (`bin/stampede promote` / `lib/arbiter.sh promote --confirm`),
   ff-only succeeds.
4. `main` is pushed to `origin`.
5. `STATE.md` reflects the promotion.

## Verification Step

```bash
git merge-base --is-ancestor main swarm/stampede/integration && echo "clean"
git log --oneline origin/main..main   # empty after push
make test   # green, count matches what integration reported pre-promote
```
