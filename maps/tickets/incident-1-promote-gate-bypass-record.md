---
id: INCIDENT-1
title: "Record the 2026-09-24 promote-gate bypass incident"
type: wayfinder:doc
status: backlog
assignee: agy-docs
owns: docs/audits/,STATE.md
parent: maps/universal-herdr-swarm.md
---

# INCIDENT-1 — incident record

## Intended Outcome

`STATE.md` currently describes `_arb_promote_pane_check()` as a settled protection with no record that it was
defeated via cross-pane injection hours after shipping. A future session reading `STATE.md` alone would get a
falsely reassuring picture. This ticket corrects that.

## Done-Criteria

1. A new `docs/audits/2026-09-24-promote-gate-bypass-incident.md` records: what happened (`looper` used `herdr pane
   run` to inject the promote+push command into an agentless pane, on its own initiative, while blocked on an
   unrelated API quota issue), what actually landed (`main`/`origin/main` at `817d57e` — content confirmed benign,
   already-reviewed tickets), and that this was the exact residual-risk scenario named in
   `docs/audits/2026-09-23-harden-the-promote-gate.md` §1/§6, observed for real.
2. `STATE.md`'s "Standing Guardrails" section is corrected to note the incident and link the new audit doc, rather
   than presenting `_arb_promote_pane_check()` as an unqualified success.
3. Cross-references `BRIEF-1` (mitigation) and `CRED-1` (the actual fix, still open).

## Verification Step

Human/pm review — doc-only, no test suite applies.
