# Wayfinder Map: Autonomous Reviewer Loop PRD

## Destination

An autonomous, config-gated cross-provider reviewer loop where `looper` dispatches `reviewer` on every suite-green verdict, mediates up to 2 rounds of structured critique/refinement with `arch`, and only enqueues to Arbiter upon a `PASS` (failing closed to the human operator on exhausted rounds).

## Notes

- **Domain**: Multi-agent review loop, cross-model critique, bash orchestration, git plumbing, fail-closed CI gating.
- **Provider Diversity Invariant**: Reviewer and implementer never share a provider kind (e.g. Claude implements, OpenCode/GLM-5.3 reviews, or vice versa).
- **Suite Gate Invariant**: Deterministic test suite execution (`make test`) remains the absolute prerequisite gate — code MUST pass tests before review can start, and critique fix commits MUST pass tests before re-review.
- **Human Promotion Invariant**: Arbiter promotion remains human-only (DOG-12).
- **Fail-Closed Policy**: If the review loop exhausts its maximum rounds (default 2) with a persistent `BLOCK`, the ticket halts integration and alerts the human driver; unapproved code never silently lands on the integration ref.
- **Tracker**: Local Markdown Tracker (`maps/tickets/` for active frontier, `maps/tickets-staged/` for staged waves).

## Decisions so far

<!-- the index: one line per closed ticket, enough to judge relevance, then zoom the link for the detail the ticket holds -->
- [REV-1: Reviewer config flag and harvested verdict protocol](tickets/rev-01-reviewer-config-and-verdict-protocol.md): `[reviewer]` loop/max_rounds in `swarm.config.toml` bound in `lib/config.sh`; dual-mode brief with `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>` anchor and durable `.herdr-swarm/reviews/<ticket>-<sha>.md` report schema (`e22697c`).
- [REV-2: Critique delivery protocol: implementer refinement on existing worktree branch](tickets/rev-02-critique-delivery-protocol.md): `briefs/arch.in.md` Section 4 `DISPATCH CRITIQUE: #<ticket> round <N>/<MAX> — see <path>` protocol; in-flight branch refinement with `ARCH DONE #<ticket> <sha2>` re-verdict; user guide §9 multi-turn loop documentation (`efc857e`).
- [REV-3: Looper autonomous review loop state machine and fail-closed gate](tickets/rev-03-looper-review-state-machine.md): Review loop state machine in `lib/lifecycle.sh` with durable `.herdr-swarm/reviews.json`, directive contract (`ENQUEUE`/`DISPATCH_*`/`ALERT_*`), fail-closed budget bounds, `--no-review-loop` CLI flag and status visibility (`ed86598`).

## Not yet specified

<!-- Fog of war: in-scope questions to specify as the frontier advances -->
- **Reviewer Auto-Approve Heuristics**: Policy on whether documentation-only or test-only commits can skip review loop or fast-path to PASS.
- **Multi-Reviewer Quorum**: Scaling review from single-seat review to multi-seat cross-provider consensus (e.g., both Claude and Gemini must PASS).
- **Interactive TUI Review Diff Inspection**: Visualizing reviewer critique comments directly inline within an Ops or Herdr terminal view.

## Out of scope

- **Review Replacing the Test Suite**: The Suite Gate (`make test`) is non-negotiable. Reviewer critique is semantic and complementary; it never substitutes for deterministic test verification.
- **Autonomous Direct-to-Main Merges**: Reviewer never merges to `main` or runs `arbiter promote --confirm`.

## Waves and Dependencies

- [x] **Wave 1 — Reviewer Config & Verdict Protocol.** REV-1 (`e22697c`): `[reviewer] loop = true/false` config binding, and formal `REVIEW VERDICT` anchor + `.herdr-swarm/reviews/<ticket>-<sha>.md` report schema.
- [x] **Wave 2 — Critique Brief & Implementer Refinement Protocol.** REV-2 (`efc857e`): Implementer brief update for critique dispatches (`round 2/2`) on existing worktree branches.
- [x] **Wave 3 — Looper Review Loop State Machine.** REV-3 (`ed86598`): 2-round autonomous loop state machine in orchestrator with fail-closed human escalation.
- [ ] **Wave 4 — Review Telemetry, Rich Status & Full Verification.** REV-4: Telemetry event logging, rich status dashboard aggregation, and hermetic multi-round test suite.

Dependency edges:
REV-2 ← REV-1 · REV-3 ← REV-1,REV-2 · REV-4 ← REV-3.

