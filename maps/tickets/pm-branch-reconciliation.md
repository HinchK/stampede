---
id: PM-BRANCH-RECON
title: "Reconcile eleven unmerged pm branches: integrate live content through the arbiter, delete the rest with evidence"
type: wayfinder:task
status: resolved
commit: pending
assignee: pi
owns: maps/tickets/pm-branch-reconciliation.md
parent: maps/universal-herdr-swarm.md
---

# PM-BRANCH-RECON

Eleven unmerged (mostly one-commit) `pm` branches plus a locked worktree held
content the ledger treated as authoritative but that was reachable only from
side branches — the arbiter existed for exactly this and was unused on `pm`
output.

## Classification (evidence: `git merge-tree --write-tree refs/heads/main <branch>` + `git cherry`)

**Integrated via arbiter (queue → drain, gated by `make test` → promote):**

| branch | ticket | content |
|---|---|---|
| `pm-p3-4-spec` | P3-4 | P3-4 arbiter batching spec + ticket (new) |
| `pm-reordered-plan` | PM-PLAN-EVIDENCE | `docs/reordered-plan.md` (new; referenced by STATE.md) |

**Deleted — merge would change 0 files** (content already on `main` via
other commits; `git branch -D` used only after this check):

`pm-m3-audit`, `pm-p2-2-spec`, `pm-p2-3-spec`, `pm-p3-2-spec`,
`pm-p3-roadmap`, `pm-phase2-advisory`, `pm-phase2-milestone-audit`,
`worktree-pm-audit`.

**Deleted — superseded (merge conflicts / regresses newer content on main):**

- `pm-p2-4-spec`: its spec doc is on main; merging conflicts on CLAUDE.md
  against the newer refreshed version.
- `pm-p3-3-spec`: v1 of the async-harvesting spec + early P3-FLAKE-1 ticket;
  both superseded by the merged v2 spec and the implemented fix (`cf8b546`).

**Worktree:** `.claude/worktrees/pm-audit` (held `pm-p3-4-spec`, clean
tree) unlocked and removed after promote; arbiter worktree pruned.

## Verification Step

    git branch --no-merged main        # empty (no unmerged pm branches)
    git log --oneline --grep="integrate #"   # arbiter merge commits promoted
    git worktree list                  # no pm-audit worktree
