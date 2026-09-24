---
id: GATE-2
title: "Amend ADR 0009 with the promote pane-check mechanism and its limitations"
type: wayfinder:doc
status: backlog
assignee: agy-docs
owns: docs/adr/0009-arbiter-branch-integration-and-cas-merge.md,docs/adr/README.md
parent: maps/universal-herdr-swarm.md
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
