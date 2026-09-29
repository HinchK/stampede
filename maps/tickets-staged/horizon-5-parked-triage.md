---
id: HORIZON-5
title: "Parked-queue triage audit"
type: wayfinder:decision
status: backlog
assignee: pm
owns: maps/tickets-parked
parent: maps/next-horizon.md
blocked_by: []
---

# HORIZON-5 — the parked queue vs. reality

## Intended Outcome

Each of the five parked tickets (`maps/tickets-parked/`) gets a keep/kill
verdict with a receipt. In particular `arbiter-batch-integration.md` and
`worktree-config-and-ledger-integration.md` likely pre-date PROVE-4
(auto-drain) and HEADLESS-6 (worktree+ledger provisioning in the batch) and
may be superseded wholesale.

## Done-Criteria

1. Audit doc in docs/audits/ with per-ticket verdicts + supersession
   receipts (or re-release into maps/tickets with refreshed scope).
2. No ticket remains parked without a dated reason.

## Verification Step

`ls maps/tickets-parked | wc -l` equals the audited set; audit doc exists.
