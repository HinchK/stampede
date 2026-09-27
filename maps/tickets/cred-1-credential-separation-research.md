---
id: CRED-1
title: "Research: is credential separation for agent seats actually achievable on this GitHub plan?"
type: wayfinder:research
status: backlog
assignee: agy-gh
owns: docs/findings/
parent: maps/universal-herdr-swarm.md
---

# CRED-1 — credential separation research

## Intended Outcome

A design doc (`docs/findings/credential-separation-design.md`) answering, without implementing anything: can agent
seats be given a `git`/`gh` credential that structurally cannot push to `main`, regardless of what any agent is
instructed or decides to do — and is that actually achievable on this repo's current GitHub plan?

## Background

Two incidents this session (2026-09-23, 2026-09-24) both ended with `main`/`origin/main` advancing via an agent
running the promote+push, once on direct human instruction, once on the agent's own initiative bypassing a local
check. Every seat currently shares the same OS user and the same `git`/`gh` credential (the human's own GitHub
login). Local checks (GATE-1) only raise the bar against accidental pattern-completion — they cannot stop a
credential that has the same push rights as a human's.

**Known constraint, already discovered (2026-09-23):** `gh api repos/HinchK/stampede/branches/main/protection` and
`.../rulesets` both return 403 ("Upgrade to GitHub Pro or make this repository public"). GitHub's per-branch push
restriction is a branch-protection-rule feature — investigate early whether *any* form of credential separation
(a scoped PAT, a GitHub App installation token, a separate machine-user account, an SSH deploy key) can restrict
push access to a specific branch *without* branch protection rules. If the honest answer is "no, not on this plan,"
say that plainly and give the actual options (upgrade the plan, make the repo public, or accept that no technical
separation is possible today) rather than proposing something that turns out to depend on the same blocked feature.

## Done-Criteria

1. Investigates, with citations to real GitHub documentation/API behavior (not assumption): fine-grained PATs, a
   GitHub App installation token, a dedicated machine-user account with restricted collaborator permissions, and
   an SSH deploy key — for each, does it support restricting push access to a specific branch without branch
   protection rules?
2. States plainly whether real credential separation is achievable on the current plan/visibility, or whether it
   depends on the same upgrade/public-repo decision already named in `docs/audits/2026-09-23-harden-the-promote-gate.md`.
3. If achievable: proposes a concrete mechanism and what it would take to implement (a follow-up ticket, not this
   one). If not achievable without a plan change: states that as the finding, doesn't invent a workaround that
   doesn't actually close the gap.
4. Does not touch code, does not propose implementation tickets of its own — research only, matching `HEADLESS-2`'s
   precedent for how this repo scopes design-research tickets.

## Verification Step

Human/pm review — research doc, no test suite applies.
