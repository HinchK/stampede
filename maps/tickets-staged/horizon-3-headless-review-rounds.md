---
id: HORIZON-3
title: "Headless reviewer rounds in batch mode — feature or accepted limit"
type: wayfinder:decision
status: backlog
assignee: arch
owns: docs/adr
parent: maps/next-horizon.md
blocked_by: [HORIZON-2]
---

# HORIZON-3 — decide the batch's review boundary

## Intended Outcome

Either (a) the batch runs reviewer rounds: greens route through
`awaiting_review`, the reviewer is spawned headlessly with its own
worktree/ledger entry, PASS→enqueue / BLOCK→critique-turn all in subprocess
mode; or (b) an ADR records the accepted limit — batch quality = suite gate
+ HEADLESS-5 ceilings, review stays an interactive-herd feature — with the
reasoning. Today it is a code comment in lib/cli/stampede-headless.sh; a
boundary this load-bearing belongs in a decision record, whichever way it
goes.

## Done-Criteria

1. ADR written for (a) or (b), indexed in docs/adr/README.md.
2. If (a): CONFIG_REVIEW_LOOP honored per config in batch mode, reviewer
   provisioning in the CLI, coverage in test_cli's e2e.
3. `make check` green.

## Verification Step

The ADR exists and the code comment cites it.
