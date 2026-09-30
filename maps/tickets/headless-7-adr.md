---
id: HEADLESS-7
title: "ADR: Headless Batch Drain Mode"
type: wayfinder:doc
status: resolved
assignee: agy-docs
blocked_by: HEADLESS-6
owns: docs/adr/
parent: maps/headless-run-mode.md
github_issue: 80
github_url: "https://github.com/HinchK/stampede/issues/80"
synced_at: "2026-09-30T17:16:14Z"
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

## Resolution

- **ADR Created**: [`docs/adr/0015-headless-batch-drain-mode.md`](file:///Users/hinchk/Fun/stampede/docs/adr/0015-headless-batch-drain-mode.md) (Status: Accepted)
- **Decisions Captured**:
  - Additive destination: `stampede headless` batch drainer permanently preserves interactive `stampede up` mode.
  - Mechanism decision: Option A (direct subprocess supervisor via `lib/headless.sh`) chosen over Option B (detached Herdr session) due to absence of Herdr daemon and display in CI environments.
  - Three unattended safety hazards and closures (HEADLESS-5): re-verdict ceilings (`[headless] max_verdict_attempts`), process timeouts (`resolve_timeout`) + stale pidfile reap (`headless_reap`), and dead-letter records (`.herdr-swarm/dead-letter.jsonl`) with non-zero CI exit codes.
  - User-facing CLI entrypoint (`bin/stampede headless` from HEADLESS-6): convention dispatch, deterministic queue intake, partition leases, worktree isolation (`worktree_provision`), supervisor function sourcing, and reviewer loop disabled in batch (`CONFIG_REVIEW_LOOP=0`).
- **Indexes Updated**: `docs/adr/README.md` and `README.md`.
