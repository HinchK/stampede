---
id: GATE-2
title: "Amend ADR 0009 with the promote pane-check mechanism and its limitations"
type: wayfinder:doc
status: resolved
assignee: agy-docs
owns: docs/adr/0009-arbiter-branch-integration-and-cas-merge.md,docs/adr/README.md
parent: maps/universal-herdr-swarm.md
resolution:
  adr_amended: docs/adr/0009-arbiter-branch-integration-and-cas-merge.md#8-amendment-fail-closed-agent-pane-guard--promote-gate-hardening-2026-09-23
  adr_index_updated: docs/adr/README.md
  spec_reference: docs/audits/2026-09-23-harden-the-promote-gate.md
  implementation_commit: e86f790
github_issue: 72
github_url: "https://github.com/HinchK/stampede/issues/72"
synced_at: "2026-09-30T17:16:14Z"
---

# GATE-2 — Document the promote gate hardening (Wave, blocked by GATE-1)

## Intended Outcome

ADR 0009 gains a section documenting `_arb_promote_pane_check()`: what it does, why (the session incident:
`looper` ran promote+push on a direct human instruction, despite its brief forbidding it), and its explicit
limitation (not airtight against a deliberate bypass — every seat shares OS user, `git`, and `gh` credentials).
Cross-references DOG-12 (original human-promote guardrail) and
`docs/audits/2026-09-23-harden-the-promote-gate.md` (the investigation and design).

## Done-Criteria

1. Written against what GATE-1 **actually built** — read the merged implementation, not the spec's proposal, in
   case anything changed during implementation.
2. States plainly, in the ADR's own words, that GitHub branch protection was found unavailable on this repo's
   current plan (with the exact `gh api` 403 finding), and that credential separation is the real fix, named as
   follow-up rather than promised as done.
3. `docs/adr/README.md` index updated to list it.

## Verification Step

Human/pm review — ADR is documentation, no test suite applies.

## Resolution

Resolved by amending [`docs/adr/0009-arbiter-branch-integration-and-cas-merge.md`](../../docs/adr/0009-arbiter-branch-integration-and-cas-merge.md) with Section 8 ("Amendment: Fail-Closed Agent-Pane Guard & Promote Gate Hardening (2026-09-23)") and indexing in [`docs/adr/README.md`](../../docs/adr/README.md):

1. **Documented Mechanism**: Documented `_arb_promote_pane_check()` as implemented in commit `e86f790` (GATE-1), detailing its fail-closed evaluation matrix (unset $\to$ allow, set + live agent $\to$ refuse, set + query failure $\to$ refuse, set + agentless $\to$ allow) wired at the entry point of `arbiter_promote()` before `--confirm` or `--pr`/local mode dispatch.
2. **Context & Motivation**: Documented the session incident where `looper` complied with a direct human instruction to run promote and push despite standing brief instructions, demonstrating that sovereignty guarantees require programmatic code barriers rather than prompt adherence.
3. **Explicit Limitations**: Stated clearly that this is local hardening against accidental compliance, not an airtight defense against deliberate bypass (shared OS user, identical `git`/`gh` credentials across seats, and `/dev/tty` availability inside Herdr panes).
4. **GitHub 403 Finding**: Cited the empirical HTTP 403 error on `gh api repos/HinchK/stampede/branches/main/protection` and rulesets ("Upgrade to GitHub Pro or make this repository public to enable this feature"), demonstrating that server-side branch protection is currently unavailable.
5. **Credential Separation**: Explicitly identified credential separation (scoped tokens without push/merge authority to `main`) as the true long-term architectural solution, named as a future roadmap item.
