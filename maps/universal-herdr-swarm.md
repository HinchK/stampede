# Wayfinder Map: Universal Herdr Swarm Launcher (`herd-swarm`)

## Destination

A hardened, project-agnostic multi-agent swarm orchestrator (`up · watch · down · status`) that provisions a dedicated, verified Herdr workspace with project-scoped seats (`arch`, `pm`, `looper`, `docs`, `gh`, `reviewer`), dynamic TOML configuration, and fail-closed test gating in any repository.

## Notes

- Domain: Herdr terminal workspace management, multi-agent coordination (AGY, Claude Code, OpenCode GLM-5.3), bash scripting, TOML parsing.
- Core Invariant: `looper` orchestrates and verifies; implementation is delegated to `arch`.
- Safety Rules: Fail-closed on missing GitHub remotes or test commands; zero unconfirmed git pushes; no `--current` pane splits; agent names must match `^[a-z][a-z0-9_-]*$`.
- Issue tracker: Local Markdown Tracker (`maps/tickets/`).

## Decisions so far

- [Foundations: Git Baseline Initialization](tickets/git-baseline-initialization.md): Initialized standalone Git repository on `main` with comprehensive `.gitignore` and baseline commit `95044cc`.
- [Herdr Semantics: Workspace Routing and Agent Namespacing](tickets/herdr-workspace-routing-and-agent-namespacing.md): Confirmed pane commands route via workspace-prefixed pane IDs (never `--current`), agent names are server-global requiring `seat-<slug>` format, and separator must be `-` or `_` (`·` is rejected).
- [Telemetry Event Schema and Live Ops Streaming](tickets/telemetry-event-schema-and-live-ops-streaming.md): Defined standard JSONL event contract (domain.action envelope), resolved 5 launcher/supervisor/guard disconnections, and specified a 1-line ANSI streaming engine in telemetry.py for the Ops pane.
- [Profile Detection and Fail-Closed Target Policy](tickets/profile-detection-and-fail-closed-target-policy.md): Built and validated prototype in lib/profile.sh establishing multi-manifest detection, fail-closed remotes (no kultivait default), and fail-closed test validation (no fake-green "true" fallback).
- [Supervisor Bug Fixes and Re-Verdict Logic](tickets/supervisor-bug-fixes-and-re-verdict-logic.md): Rewrote loop-bot-herd.sh dedupe logic with jq exact matching to support re-verdicts after RED, fixed substring collisions (#23 vs #230), and defined missing note/step helpers.
- [TOML Configuration Schema and Shell Binding](tickets/toml-configuration-schema-and-shell-binding.md): Implemented lib/config.sh using python3 tomllib to parse swarm.config.toml into shell bindings, dynamic seat arrays, namespaced agent names, and dry-run markdown plans.
- [Brief Templating Syntax and Nonce File Protocol](tickets/brief-templating-syntax-and-nonce-file-protocol.md): Authored briefs/*.in.md templates and lib/briefs.sh renderer to dynamically inject {{REPO}}, {{TEST_CMD}}, and namespaced seats into .herdr-swarm/briefs/, delivered via compact file-path prompts.
- [Workspace Lifecycle and Clean Teardown Protocol](tickets/workspace-lifecycle-and-clean-teardown-protocol.md): Implemented lib/lifecycle.sh with workspace auto-discovery, safe per-pane agent teardown, audit log retention, and rich terminal status inspection.
- [Preflight Dependency and Daemon Verification](tickets/preflight-dependency-and-daemon-verification.md): Implemented lib/preflight.sh with 9-point validation matrix (daemon, core CLIs, python tomllib, gh auth, agent CLIs, git repo) and actionable human remediation hints.
- [Lifecycle Safe Teardown and Target Disambiguation](tickets/lifecycle-safe-teardown-and-targeting.md): Hardened lib/lifecycle.sh with physical pane CWD matching, confirmation gate, and seats.json selective pane retirement to eliminate destructive teardown hazards (D1).
- [Profile Validation and Safe Slug Emitter](tickets/profile-validation-and-safe-slug-emitter.md): Hardened lib/profile.sh test validation (blocking auto-mode on empty/none/true test commands), introduced shared lib/common.sh slugify(), and updated lib/config.sh to safely emit environment bindings via sys.argv and shlex.quote (D3 & D4).
- [Integrate Profile Detection into Swarm Launcher](tickets/integrate-profile-into-launcher.md): Sourced lib/profile.sh and lib/lifecycle.sh in herdr-loop-swarm.sh, deleted hardcoded kultivait and TEST_CMD="true" defaults, gated auto-queue mode against non-runnable test commands, and bound workspace lookup to physical CWD (T-INT-1).
- [Supervisor Re-Verdict Deduplication Protocol](tickets/supervisor-reverdict-dedupe-protocol.md): Updated loop-bot-herd.sh and briefs/arch.in.md with explicit commit sha protocol (ARCH DONE #<n> <sha>) and (ticket, sha) deduplication, enabling suite re-evaluation on new commits after RED failures (T-007a-fix / D2).
- [README Truth: Align Documentation with Shipped Architecture](tickets/readme-truth-and-capabilities.md): Aligned README.md with shipped architecture, striking fictional components and documenting modular libraries, fail-closed profiling, and lifecycle guarantees (T-015a).
- [Integrate Config Registry, Namespacing, and Templated Brief Delivery](tickets/integrate-config-and-briefs-into-launcher.md): Integrated lib/config.sh and lib/briefs.sh into herdr-loop-swarm.sh, seating agents dynamically from swarm.config.toml with slug namespacing, delivering briefs via compact file-path nonce protocol, and recording seated panes into .herdr-swarm/seats.json (T-INT-2, T-005, T-INT-3).
- [Supervisor Genericization and Profile Binding](tickets/supervisor-genericization-and-profile-binding.md): Genericized loop-bot-herd.sh to supervise arbitrary repositories, binding REPO and TEST_CMD from profile.env, populating EXPECTED_SEATS from swarm.config.toml, and running the project's real test runner in suite gates (T-007b).
- [Preflight Verification and Lifecycle Subcommands in Swarm Launcher](tickets/launcher-preflight-and-subcommands.md): Integrated lib/preflight.sh 9-point matrix fail-closed prior to any workspace or pane creation, and wired up, down, status CLI subcommands delegating to lib/lifecycle.sh with comprehensive help documentation (T-INT-4, T-008).
- [Seat Verification Protocol and Brief Acknowledgment Gate](tickets/seat-verification-protocol.md): Built swarm_verify_seats in lib/lifecycle.sh with .herdr-swarm/seats.json inspection, readiness/brief acknowledgment waiting, fail-closed autonomous mode execution gates, and the verify subcommand in herdr-loop-swarm.sh (T-010).
- [Telemetry Event Engine and Live Ops Streaming Wiring](tickets/telemetry-event-engine-wiring.md): Standardized JSONL domain.action event envelope in lib/telemetry.py, stored traces in project-scoped .herdr-swarm/traces/, rewired Ops Anchor to live ANSI badge stream, and connected lifecycle and supervisor verdict logging on shared session files (T-009-impl).
- [README and User Guide Polish](tickets/readme-and-user-guide-polish.md): Polished README.md with lifecycle subcommands (up, down, status, verify), live telemetry ANSI streaming, dynamic seating, seat verification protocol, ADR index, and current repository structure (T-015b).
- [Supervisor Anchored Verdict Harvesting and Mode-R Gating](tickets/supervisor-verdict-anchoring-and-mode-r-gating.md): Hardened supervisor verdict parsing with whole-line regex anchoring to eliminate false-green scrollback matches (H1), gated resume mode r fail-closed against non-runnable test suites, routed skipped verdicts to human review gate, purged legacy fixture records, and deleted orphan lib/agent_guard.sh (T-007c-fix).
- [Launcher Target Directory Argument and Commit SHA Verification](tickets-parked/launcher-target-dir-and-sha-validation.md): Added up [dir] positional directory support to launcher, enforced git cat-file commit existence verification on harvested verdict SHAs in loop-bot-herd.sh, and relabeled verify status to interactive-ready (T-016-arch).
- [Git Worktree Worker Isolation and Phase 2 Blueprint](tickets/worktree-isolation-architecture.md): Defined root orchestrator vs isolated worker worktree topology in docs/adr/0006-git-worktree-worker-isolation.md and authored the Phase 2 specification in docs/worktree-swarm.md (T-016-docs).
- [Safe Workspace Discovery across Nested Herdr Sessions](tickets-parked/safe-workspace-targeting-in-launcher.md): Sourced find_workspace_by_cwd in herdr-loop-swarm.sh, preventing nested Herdr session hijacking and guaranteeing isolated workspace creation for external repositories (T-016c).
- [GitHub Issues Two-Way Synchronization Protocol and Tooling](tickets/github-issues-two-way-sync.md): Established bi-directional schema mapping between local YAML-frontmatter markdown tickets and upstream GitHub Issues, documented fail-closed remote policies with zero unconfirmed writes in docs/findings/github-issues-sync.md, and built lib/gh_sync.sh supporting --dry-run reconciliation and frontmatter anchoring (T-017).
- [Dogfooding Rehearsal Receipt](../docs/audits/2026-09-19-dogfooding-rehearsal-receipt.md): Validated complete swarm lifecycle (status -> up -> verify -> down -y) against an ephemeral scratch repository from within wM with zero disruption to the host session.
- [Worktree Lifecycle Library: Provisioning, Locking, Pruning & Reconcile](tickets/worktree-lifecycle-library.md): Implemented lib/worktree.sh supporting worktree_provision, porcelain locking, dirty tracked checkpoints, worktree_prune, and worktree_reconcile, validated by 21/21 assertions in tests/test_worktree.sh (P2-1).
- [Worktree Config and Ledger Integration Specification](../docs/audits/2026-09-19-p2-2-config-integration-spec.md): Defined swarm.config.toml per-seat worktree schema, lib/config.sh bindings, .herdr-swarm/seats.json v2 ledger, and launcher split_pane CWD ordering contract (P2-2).
- [Worktree Config Binding, Ledger v2, and Launcher CWD Integration](tickets-parked/worktree-config-and-ledger-integration.md): Implemented worktree = true in swarm.config.toml, SEAT_WORKTREE_<seat> in lib/config.sh, pre-split worktree provisioning in herdr-loop-swarm.sh, and atomic seats.json v2 serialization (P2-2).
- [ADR 0007 & Swarm Retrospective](../docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md): Authored ADR 0007 and docs/findings/swarm-orchestration-retrospective.md capturing empirical multi-agent topology, 80%+ token reduction, and PTY buffer mechanics (#T-DOCS-RETRO).
- [Phase 2 Release and Synchronization Validation Checklist](../docs/findings/phase2-release-checklist.md): Authored release gating matrix, lib/gh_sync.sh verification, and promotion checklist (#T-GH-CHECKLIST).
- [Supervisor Worktree Suite Gating Specification](../docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md): Defined ledger-first seat directory resolution, commit provenance, and pre/post drift validation with empirical probes uncovering -B branch reset hazard (P2-3).
- [Supervisor Worktree Suite Gating and Drift Validation](tickets/supervisor-worktree-suite-gating.md): Implemented loop-bot-herd.sh execution inside worker worktrees with drift validation and fixed -B branch reset bug in lib/worktree.sh (P2-3).
- [ADR 0008: Supervisor Worktree Suite Gating and Drift](../docs/adr/0008-supervisor-worktree-suite-gating-and-drift.md): Authored ADR 0008 documenting ledger-first gate resolution, pre/post TOCTOU drift detection, and non-destructive branch re-attachment (#T-DOCS-ADR0008).
- [GitHub Issue Sync Validation Report](../docs/findings/gh-sync-validation-report.md): Documented lib/gh_sync.sh verification and zero unconfirmed writes (#T-GH-REPORT).
- [Phase 2 Arbiter and Integration PR Specification](../docs/audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md): PM authored specification for partition check, CAS fast-forward merge, PR synthesis, and teardown integration (P2-4).
- [Phase 2 Arbiter and Branch Reconciliation](tickets/arbiter-and-branch-reconciliation.md): Implemented lib/arbiter.sh providing partition checking, atomic CAS fast-forward merges into swarm/<slug>/integration, and human-promoted PRs (P2-4).
- [ADR 0009: Arbiter Branch Integration and CAS Merge](../docs/adr/0009-arbiter-branch-integration-and-cas-merge.md): Authored ADR 0009 documenting off-branch integration, detached worktree candidate pre-gating, and CAS atomic ref updates (#T-DOCS-ADR0009).
- [Phase 2 Worktree Swarm Milestone Audit](../docs/audits/2026-09-19-phase2-worktree-milestone-audit.md): Comprehensive empirical audit validating P2-1 through P2-4, proving false-green elimination and zero data loss, while defining hardening items H1-H5 (#P2-AUDIT).
- [Phase 2 Worktree Teardown and Untracked Salvage](tickets/worktree-lifecycle-teardown-and-salvage.md): Implemented worktree unlocking and safe pruning in lib/lifecycle.sh, untracked salvage preservation, and stale-branch gating in lib/worktree.sh (P2-H).
- [ADR 0010: Worktree Teardown Lifecycle and Salvage](../docs/adr/0010-worktree-teardown-lifecycle-and-salvage.md): Authored ADR 0010 documenting untracked file salvage, non-destructive teardown, and stale branch gate (#T-DOCS-ADR0010).
- [Phase 3 Concurrent Fan-Out Roadmap](../docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md): Defined multi-worker seat rosters, task intake partition checks, and asynchronous supervisor polling (#P3-ROADMAP).

- [Phase 3: Multi-Worker Config & Roster Expansion](tickets/multi-worker-config-and-roster-expansion.md): Expanded swarm.config.toml and lib/config.sh to provision multiple parallel implementation workers (arch-1, arch-2) with isolated worktrees (P3-1, b62faf1).

- [Phase 3: Task Intake Partition Checking and Ledger Lease Protocol](tickets/task-intake-partition-checking.md): Enforcing disjoint file path ownership (`owns`) at ticket intake and managing durable path leases in .herdr-swarm/leases.json (P3-2, 1992e37).
- [Phase 3: Asynchronous Supervisor Harvesting and Durable Gate Jobs](tickets/async-supervisor-harvesting.md): Decoupled suite gate execution into non-blocking background jobs with durable tracking in .herdr-swarm/gates/, concurrency capping, and arbiter enqueueing (P3-3, eafdc91).

## Active Frontier

- [Phase 3 Defect: Concurrent worktree_provision Race Mitigation](tickets/concurrent-provision-race-mitigation.md): Hardening worktree provisioning against concurrent race conditions with advisory directory locks and idempotent retry logic (P3-FLAKE-1).

## Not yet specified

- **Cross-LLM Quota and Credit Probing:** Live API credit/rate-limit detection across Anthropic, Google Gemini, and Z.AI backends to gracefully pause or reroute workers before rate limits fail tasks.




## Out of scope

- Windows or PowerShell compatibility (POSIX bash 3.2+ and macOS/Linux only).
- Modifying the upstream `herdr` daemon Go codebase or daemon protocol.
- Autonomous auto-push of code, branches, or release tags to remote Git origins without explicit human driver authorization.

