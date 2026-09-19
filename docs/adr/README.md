# Architecture Decision Records (ADRs)

This directory maintains the Architecture Decision Records (ADRs) for the Universal Herdr Swarm (`herd-swarm`). 

ADRs capture significant architectural and design choices, along with the context, alternatives evaluated, rationale, and consequences of each decision.

## Index of Records

| ADR | Title | Status | Date | Primary Assets / Tickets |
|---|---|---|---|---|
| [0001](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0001-fail-closed-profile-and-test-gating.md) | Fail-Closed Profile Detection and Test Gating Policy | Accepted | 2026-09-19 | `lib/profile.sh`, `lib/common.sh`, [T-002](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/profile-detection-and-fail-closed-target-policy.md), [T-002-fix](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/profile-validation-and-safe-slug-emitter.md) |
| [0002](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0002-exact-sha-supervisor-deduplication.md) | Exact-SHA Supervisor Protocol and Re-Verdict Deduplication | Accepted | 2026-09-19 | `loop-bot-herd.sh`, `briefs/arch.in.md`, [T-007a-fix](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-reverdict-dedupe-protocol.md), [T-007b](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-genericization-and-profile-binding.md) |
| [0003](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md) | Dynamic Seating from TOML Registry and Nonce Brief Delivery Protocol | Accepted | 2026-09-19 | `swarm.config.toml`, `lib/config.sh`, `lib/briefs.sh`, [T-INT-2](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/integrate-config-and-briefs-into-launcher.md), [T-005](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/herdr-workspace-routing-and-agent-namespacing.md) |
| [0004](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0004-safe-workspace-lifecycle-and-seat-ledger.md) | Safe Workspace Lifecycle, Physical CWD Resolution, and Seat Ledger | Accepted | 2026-09-19 | `lib/lifecycle.sh`, `.herdr-swarm/seats.json`, [T-011-fix](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/lifecycle-safe-teardown-and-targeting.md) |
| [0005](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0005-preflight-matrix-and-seat-verification.md) | Preflight Dependency Matrix and Post-Seating Readiness Verification Gate | Accepted | 2026-09-19 | `lib/preflight.sh`, `lib/lifecycle.sh`, [T-008](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/preflight-dependency-and-daemon-verification.md), [T-010](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/seat-verification-protocol.md) |
| [0006](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0006-git-worktree-worker-isolation.md) | Git Worktree Worker Isolation and Lifecycle Management | Accepted | 2026-09-19 | `lib/lifecycle.sh`, `docs/worktree-swarm.md`, [T-016-docs](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/worktree-isolation-architecture.md) |
| [0007](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md) | Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2 | Accepted | 2026-09-19 | `herdr-loop-swarm.sh`, `.herdr-swarm/seats.json`, [P2-2 Spec](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-2-config-integration-spec.md) |
| [0008](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0008-supervisor-worktree-suite-gating-and-drift.md) | Supervisor Worktree Suite Gating, Provenance, and Drift Detection | Accepted | 2026-09-19 | `loop-bot-herd.sh`, `lib/worktree.sh`, [P2-3 Spec](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md), [T-P2-3](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-worktree-suite-gating.md) |

## Related Documentation

- Swarm Orchestration Retrospective: [swarm-orchestration-retrospective.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/swarm-orchestration-retrospective.md)
- Phase 2 Worktree Architecture Blueprint: [worktree-swarm.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/worktree-swarm.md)
- System Vocabulary and Conceptual Invariants: [CONTEXT.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/CONTEXT.md)
- Wayfinder Master Architecture Map: [universal-herdr-swarm.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/universal-herdr-swarm.md)
- Herdr Semantics & Empirical Findings: [herdr-semantics.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/herdr-semantics.md)
- Telemetry Event Schema: [telemetry-schema.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/telemetry-schema.md)
