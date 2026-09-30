---
id: CRED-1
title: "Research: is credential separation for agent seats actually achievable on this GitHub plan?"
type: wayfinder:research
status: superseded
outcome: superseded
commit: cd70a74
assignee: agy-gh
owns: docs/findings/
parent: maps/universal-herdr-swarm.md
resolution:
  commit: cd70a74
  findings_file: docs/findings/credential-separation-design.md
github_issue: 70
github_url: "https://github.com/HinchK/stampede/issues/70"
synced_at: "2026-09-30T17:16:14Z"
---

**Superseded 2026-09-29:** driver rejected the multi-account credential-separation approach as excessive onboarding friction for a project whose whole point is frictionless multi-agent orchestration. See GRANT-1 for the adopted lower-friction alternative. Research below kept for the record — the GitHub API findings (public repo -> branch protection available for free) remain accurate and useful if this is ever revisited.

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

## Notes

Resolved by research (`worker-gh`, role `agy-gh-hinchk-stampede`), matching HEADLESS-2 precedent — no code changes, no suite gate.

## Resolution

Resolved by research in commit `cd70a74` with the publication of [`docs/findings/credential-separation-design.md`](file:///Users/hinchk/Fun/stampede/docs/findings/credential-separation-design.md):

1. **Four Credential Mechanisms Evaluated**:
   - **Fine-grained PATs**: `Contents: Read and write` scope is repository-wide. No ref/branch pattern filter exists in token configuration. Cannot restrict branch pushes without server-side rules.
   - **GitHub App Installation Tokens**: Scoped to repositories with `contents: write`; token issuance endpoint (`POST /app/installations/.../access_tokens`) has no branch parameter. Cannot restrict branch pushes without server-side rules.
   - **Machine-User Account**: On personal GitHub accounts, collaborators have standard Read/Write repository access. Custom repository roles are restricted to GitHub Enterprise Cloud organizations. Cannot restrict branch pushes without server-side rules.
   - **SSH Deploy Keys**: Deploy keys operate repository-wide with a binary "Allow write access" toggle (equivalent to collaborator write). Zero branch awareness.
   - **Conclusion**: No credential mechanism in isolation can restrict push access to a specific branch. Push permissions are repository-scoped; branch restrictions are enforced strictly at the repository branch protection / ruleset layer.

2. **Plan & Visibility Reality Check**:
   - On 2026-09-23, `HinchK/stampede` returned HTTP 403 on branch protection queries because the repository was private on GitHub Free.
   - Empirically verified on 2026-09-27 (`gh repo view`): `HinchK/stampede` is currently **PUBLIC**.
   - As a result, `gh api repos/HinchK/stampede/branches/main/protection` now returns HTTP 404 ("Branch not protected") and `.../rulesets` returns HTTP 200 (`[]`). Branch protection and rulesets are **available immediately at $0/month** on the current visibility.
   - If the repository remains PUBLIC, structural credential separation is achievable today. If it reverts to PRIVATE, it requires upgrading to GitHub Pro ($4/mo).

3. **Concrete Architecture for Structural Separation**:
   - Requires two interlocking layers:
     - **Server-Side Gate**: Branch Protection Rule or Repository Ruleset on `main` with push access restricted exclusively to the human driver (`HinchK`).
     - **Agent Identity**: Dedicated machine-user account (`stampede-agent`) added as repository collaborator with write access, issuing a PAT for agent seats.
   - Result: Pushes to `main` by agent seats fail at the Git transport level (`remote: error: GH006: Protected branch update failed for refs/heads/main`), while pushes to `worktree/*` succeed. Direct human promotion via local terminal continues to succeed.

4. **Next Steps**:
   - Implementation scoped out of this ticket to follow-up, pending human driver confirmation on visibility policy (maintain public vs upgrade to Pro for private).

