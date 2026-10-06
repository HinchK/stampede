---
id: HORIZON-3
title: "Headless reviewer rounds in batch mode — feature or accepted limit"
type: wayfinder:decision
status: resolved
assignee: arch-1-hinchk-stampede
owns: docs/adr,lib/cli/stampede-headless.sh
parent: maps/headless-live.md
blocked_by: [HORIZON-2]
---

# HORIZON-3 — decide the batch's review boundary

## Intended Outcome

Driver decision settled: **Option (b) — accepted-limit ADR** recording that
batch quality is enforced by the suite gate and HEADLESS-5 mechanical ceilings,
while the reviewer loop remains an interactive-herd-only feature (`stampede headless`
never spawns a reviewer).

Author `docs/adr/0016-headless-batch-review-boundary.md` (indexed in `docs/adr/README.md`)
and update the existing code comment in `lib/cli/stampede-headless.sh` to cite the ADR.

## Done-Criteria

1. ADR written at `docs/adr/0016-headless-batch-review-boundary.md` citing full reasoning:
   - Headless unattended zero-pane speed priority (reviewer subprocess doubling runtime/complexity).
   - HORIZON-2 live proof findings (no demonstrated gap where review would catch a broken suite-green ticket).
   - Headless scoped to small, mechanical, suite-gate-provable tickets.
   - Consistency cost acknowledged (documented exception vs other tickets).
   - Concrete revisit trigger specified.
2. ADR indexed in `docs/adr/README.md`.
3. Existing code comment in `lib/cli/stampede-headless.sh` updated to cite ADR 0016.
4. `make check` green.

## Verification Step

The ADR exists and the code comment cites it.

## Resolution

Resolved at commit `2dfa8bd3c4d82592552aa51033b70ae145d6fae0`.
- Authored `docs/adr/0016-headless-batch-review-boundary.md` capturing driver Option (b).
- Indexed in `docs/adr/README.md`.
- Updated code comment in `lib/cli/stampede-headless.sh`.
- Autonomous review PASS verdict by `reviewer-hinchk-stampede` (Round 1/2) in `.herdr-swarm/reviews/HORIZON-3-2dfa8bd3c4d82592552aa51033b70ae145d6fae0.md`.
- Integrated onto `swarm/stampede/integration` via `arbiter_enqueue_and_drain` and merged to `main`. Lease released cleanly.
