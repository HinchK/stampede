---
id: CONTEXT-1
title: "Expand CONTEXT.md with vocabulary for everything shipped since Phase 1"
type: wayfinder:doc
status: resolved
assignee: agy-docs
owns: CONTEXT.md
parent: maps/close-the-gaps.md
github_issue: 69
github_url: "https://github.com/HinchK/stampede/issues/69"
synced_at: "2026-09-30T17:14:49Z"
---

# CONTEXT-1 — vocabulary expansion

## Intended Outcome

`CONTEXT.md` currently defines 7 terms, all from the earliest phase of this project (Fail-Closed, Nonce Delivery,
Seat Ledger, Slug Namespacing, Suite Gate, Wayfinder Map, Supervisor Gate). Everything shipped since — the arbiter
integration pipeline, worktree isolation, partition/leases, the Autonomous Reviewer Loop, headless batch mode,
session-scoped promote grants, and the fail-closed-ref lesson from `ARB-SLUG-1` — has no vocabulary entry at all,
despite CLAUDE.md itself saying "Read CONTEXT.md before naming anything new."

## Done-Criteria

Add entries (continuing the existing numbered format: **Implementation** + **_Avoid_** lines) for at least:

1. **Arbiter Integration & CAS Merge** — the off-branch integration pipeline, compare-and-swap ref updates, human
   promote gate.
2. **Worktree Isolation** — isolated seats on `swarm/<slug>/<seat>` branches vs. root anchors on `main`.
3. **Partition & Lease** — `owns:` frontmatter, disjoint dispatch, lease lifecycle tied to integration not verdict.
4. **Autonomous Reviewer Loop** — verdict-anchored review rounds, critique-and-refine protocol.
5. **Headless Batch Drain** — the additive unattended mode, direct subprocess management, why it's additive not a
   replacement.
6. **Session-Scoped Promote Grant** — the human-gated, time-bounded authorization mechanism, and why it can't be
   self-granted by an agent.
7. **Fail-Closed Ref Resolution** — the `ARB-SLUG-1` lesson: a missing expected ref must refuse, never silently
   create a new branch from a fallback base.

**Verify every citation yourself** — find the actual current file/line/ADR for each concept rather than assuming
numbers from memory (the ADR sequence has moved since Phase 1; cite whichever ADR actually documents each concept,
and note plainly in the entry if no ADR exists yet for something that probably should have one).

## Verification Step

Human/pm review — vocabulary doc, no test suite applies. Spot-check that at least two citations resolve to real,
current file/line references.

## Resolution

- **Vocabulary Expansion**: Added definitions, implementations, and `_Avoid_` directives to `CONTEXT.md` for all 7 concepts: Arbiter Integration Pipeline, Worktree Isolation, Partition & Lease, Autonomous Reviewer Loop, Headless Batch Drain, Session-Scoped Promote Grant, and Fail-Closed Ref Resolution.
- **Architectural Interaction Matrix**: Rebuilt ASCII diagram to depict the complete pipeline (Suite Gate -> Reviewer Loop Gate -> Arbiter CAS -> Sovereign Human Gate).
- **Invariants & Safety**: Documented Sovereign Human Promotion, Partition Disjointness & Lease Integrity, and Zero Cross-Pane Evasion protocols.
- **Landed**: Committed directly to `main` at `5b64e8b07553562c9b07cf6d3e2fb2e7709e5fd7`. Lease released cleanly.

