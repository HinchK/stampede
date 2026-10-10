# Architecture Decision Records (ADRs)

This directory maintains the Architecture Decision Records (ADRs) for the Universal Herdr Swarm (`herd-swarm`). 

ADRs capture significant architectural and design choices, along with the context, alternatives evaluated, rationale, and consequences of each decision.

## Index of Records

| ADR | Title | Status | Date | Primary Assets / Tickets |
|---|---|---|---|---|
| [0001](0001-fail-closed-profile-and-test-gating.md) | Fail-Closed Profile Detection and Test Gating Policy | Accepted | 2026-09-19 | `lib/profile.sh`, `lib/common.sh`, [T-002](../../maps/tickets/profile-detection-and-fail-closed-target-policy.md), [T-002-fix](../../maps/tickets/profile-validation-and-safe-slug-emitter.md) |
| [0002](0002-exact-sha-supervisor-deduplication.md) | Exact-SHA Supervisor Protocol and Re-Verdict Deduplication | Accepted | 2026-09-19 | `loop-bot-herd.sh`, `briefs/arch.in.md`, [T-007a-fix](../../maps/tickets/supervisor-reverdict-dedupe-protocol.md), [T-007b](../../maps/tickets/supervisor-genericization-and-profile-binding.md) |
| [0003](0003-dynamic-seating-and-nonce-brief-delivery.md) | Dynamic Seating from TOML Registry and Nonce Brief Delivery Protocol | Accepted | 2026-09-19 | `swarm.config.toml`, `lib/config.sh`, `lib/briefs.sh`, [T-INT-2](../../maps/tickets/integrate-config-and-briefs-into-launcher.md), [T-005](../../maps/tickets/herdr-workspace-routing-and-agent-namespacing.md) |
| [0004](0004-safe-workspace-lifecycle-and-seat-ledger.md) | Safe Workspace Lifecycle, Physical CWD Resolution, and Seat Ledger | Accepted | 2026-09-19 | `lib/lifecycle.sh`, `.herdr-swarm/seats.json`, [T-011-fix](../../maps/tickets/lifecycle-safe-teardown-and-targeting.md) |
| [0005](0005-preflight-matrix-and-seat-verification.md) | Preflight Dependency Matrix and Post-Seating Readiness Verification Gate | Accepted | 2026-09-19 | `lib/preflight.sh`, `lib/lifecycle.sh`, [T-008](../../maps/tickets/preflight-dependency-and-daemon-verification.md), [T-010](../../maps/tickets/seat-verification-protocol.md) |
| [0006](0006-git-worktree-worker-isolation.md) | Git Worktree Worker Isolation and Lifecycle Management | Accepted | 2026-09-19 | `lib/lifecycle.sh`, `docs/worktree-swarm.md`, [T-016-docs](../../maps/tickets/worktree-isolation-architecture.md) |
| [0007](0007-split-pane-cwd-order-and-ledger-v2.md) | Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2 | Accepted | 2026-09-19 | `herdr-loop-swarm.sh`, `.herdr-swarm/seats.json`, [P2-2 Spec](../audits/2026-09-19-p2-2-config-integration-spec.md) |
| [0008](0008-supervisor-worktree-suite-gating-and-drift.md) | Supervisor Worktree Suite Gating, Provenance, and Drift Detection | Accepted | 2026-09-19 | `loop-bot-herd.sh`, `lib/worktree.sh`, [P2-3 Spec](../audits/2026-09-19-p2-3-supervisor-gating-spec.md), [T-P2-3](../../maps/tickets/supervisor-worktree-suite-gating.md) |
| [0009](0009-arbiter-branch-integration-and-cas-merge.md) | Arbiter Branch Integration, Compare-and-Swap Ref Updates, and Human Promotion Gates | Accepted (Amended) | 2026-09-19 (Amended 2026-09-23) | `lib/arbiter.sh`, [P2-4 Spec](../audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md), [T-P2-4](../../maps/tickets/arbiter-and-branch-reconciliation.md), [GATE-1](../../maps/tickets/gate-1-promote-pane-check.md), [GATE-2](../../maps/tickets/gate-2-adr-amend-0009.md) |
| [0010](0010-worktree-teardown-lifecycle-and-salvage.md) | Worktree Teardown Lifecycle, Untracked File Salvage, and Stale Branch Re-attachment Gating | Accepted | 2026-09-19 | `lib/worktree.sh`, `lib/lifecycle.sh`, [Milestone Audit](../audits/2026-09-19-phase2-worktree-milestone-audit.md), [T-P2-H](../../maps/tickets/worktree-lifecycle-teardown-and-salvage.md) |
| [0011](0011-multi-worker-floor-topologies-and-concurrency.md) | Multi-Worker Floor Topologies, Worktree Namespacing, and Heterogeneous Concurrency | Accepted | 2026-09-19 | `lib/layout_engine.sh`, `swarm.config.toml`, [Fan-Out Roadmap](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md), [T-P3-1](../../maps/tickets/multi-worker-config-and-roster-expansion.md) |
| [0012](0012-task-partitioning-and-disjoint-dispatches.md) | Task Partitioning, File Disjointness, and Durable Ledger Leases | Accepted | 2026-09-19 | `lib/partition.sh`, `.herdr-swarm/leases.json`, [P3-2 Spec](../audits/2026-09-19-p3-2-task-partition-check-spec.md), [T-P3-2](../../maps/tickets/task-intake-partition-checking.md) |
| [0013](0013-asynchronous-supervisor-gate-jobs.md) | Asynchronous Supervisor Suite Gating, Durable Job Records, and Concurrency Bounding | Accepted | 2026-09-19 | `loop-bot-herd.sh`, `.herdr-swarm/gates/`, [Fan-Out Roadmap §1.3](../audits/2026-09-19-phase3-concurrent-fanout-roadmap.md), [T-P3-3](../../maps/tickets/async-supervisor-harvesting.md) |
| [0014](0014-arbiter-drain-automation.md) | Arbiter Drain Automation and Non-Blocking Supervisor Integration | Accepted | 2026-09-23 | `lib/arbiter.sh`, `loop-bot-herd.sh`, [PROVE-4](../../maps/tickets/prove-auto-wire-arbiter-drain.md), [PROVE-5](../../maps/tickets/prove-drain-adr.md) |
| [0015](0015-headless-batch-drain-mode.md) | Headless Batch Drain Mode and Unattended Safety Invariants | Accepted | 2026-09-24 | `lib/headless.sh`, `lib/cli/stampede-headless.sh`, [HEADLESS-2](../findings/headless-mode-design.md), [HEADLESS-7](../../maps/tickets/headless-7-adr.md) |
| [0016](0016-headless-batch-review-boundary.md) | The Headless Batch Review Boundary — an Accepted Limit | Accepted | 2026-10-05 | `lib/cli/stampede-headless.sh`, [HORIZON-2 live proof](../findings/headless-live-proof.md), [HORIZON-3](../../maps/tickets-staged/horizon-3-headless-review-rounds.md) |
| [0017](0017-herdr-native-coordination-primitives.md) | Herdr-Native Coordination Primitives — Wait, Explain, Notify | Accepted | 2026-10-07 | `lib/briefs.sh`, `lib/quota.sh`, `lib/cli/stampede-doctor.sh`, [Epic: Herdr-Native & Seat Utilization](../../maps/herdr-native-and-seat-utilization.md), [HERDR-1](../../maps/tickets/herdr-1-herdr-surface-audit.md) |
| [0018](0018-single-reviewer-accepted-limit-with-quota-failover.md) | Single-Reviewer Accepted Limit with Non-AGY Quota Failover | Accepted | 2026-10-08 | `loop-bot-herd.sh`, `swarm.config.toml`, [REV-07](../../maps/tickets/rev-07-multi-reviewer-quorum-decision.md), [REV-FAILOVER-1](../../maps/tickets/rev-failover-1-non-agy-reviewer-failover.md), [FALLBACK-1](../../maps/tickets/fallback-1-standby-orchestrator-seat.md) |

## Related Documentation

- Swarm Orchestration Retrospective: [swarm-orchestration-retrospective.md](../findings/swarm-orchestration-retrospective.md)
- Phase 2 Worktree Architecture Blueprint: [worktree-swarm.md](../worktree-swarm.md)
- System Vocabulary and Conceptual Invariants: [CONTEXT.md](../../CONTEXT.md)
- Wayfinder Master Architecture Map: [universal-herdr-swarm.md](../../maps/universal-herdr-swarm.md)
- Herdr Semantics & Empirical Findings: [herdr-semantics.md](../findings/herdr-semantics.md)
- Telemetry Event Schema: [telemetry-schema.md](../findings/telemetry-schema.md)
