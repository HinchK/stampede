---
id: HEADLESS-7
title: "ADR: Headless Batch Drain Mode"
type: wayfinder:doc
status: backlog
assignee: agy-docs
blocked_by: HEADLESS-6
owns: docs/adr/
parent: maps/headless-run-mode.md
---

# HEADLESS-7 — ADR (Wave, blocked by HEADLESS-6)

## Intended Outcome

A new ADR (next sequential number after 0014) documents headless batch drain mode: the additive-not-replacement
destination decision, why direct subprocess management (Option A) was chosen over a detached Herdr session
(Option B) — the CI trigger case has no Herdr daemon available at all — and the three unattended-specific safety
mechanisms HEADLESS-5 built. Written against what HEADLESS-3 through HEADLESS-6 **actually built**, not the
original research doc's proposal.

## Done-Criteria

1. New file `docs/adr/00NN-headless-batch-drain-mode.md`.
2. States the destination decision and the mechanism decision, both with the reasoning that settled them.
3. Documents the three safety hazards and their closures, cross-referencing HEADLESS-5.
4. `docs/adr/README.md` index updated.

## Verification Step

Human/pm review — no test suite applies to a research/doc ticket.
