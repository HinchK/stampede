# Wayfinder Map: Universal Herdr Swarm Launcher (`herd-swarm`)

## Destination

A hardened, project-agnostic multi-agent swarm orchestrator (`up · watch · down · status`) that provisions a dedicated, verified Herdr workspace with project-scoped seats (`arch`, `pm`, `looper`, `docs`, `gh`, `reviewer`), dynamic TOML configuration, and fail-closed test gating in any repository.

## Notes

- Domain: Herdr terminal workspace management, multi-agent coordination (AGY, Claude Code, OpenCode GLM-5.3), bash scripting, TOML parsing.
- Core Invariant: `looper` orchestrates and verifies; implementation is delegated to `arch`.
- Safety Rules: Fail-closed on missing GitHub remotes or test commands; zero unconfirmed git pushes; no `--current` pane splits; agent names must match `^[a-z][a-z0-9_-]*$`.
- Issue tracker: Local Markdown Tracker (`maps/tickets/`).

## Decisions so far

- [Foundations: Git Baseline Initialization](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/git-baseline-initialization.md): Initialized standalone Git repository on `main` with comprehensive `.gitignore` and baseline commit `95044cc`.
- [Herdr Semantics: Workspace Routing and Agent Namespacing](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/herdr-workspace-routing-and-agent-namespacing.md): Confirmed pane commands route via workspace-prefixed pane IDs (never `--current`), agent names are server-global requiring `seat-<slug>` format, and separator must be `-` or `_` (`·` is rejected).
- [Telemetry Event Schema and Live Ops Streaming](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/telemetry-event-schema-and-live-ops-streaming.md): Defined standard JSONL event contract (domain.action envelope), resolved 5 launcher/supervisor/guard disconnections, and specified a 1-line ANSI streaming engine in telemetry.py for the Ops pane.
- [Profile Detection and Fail-Closed Target Policy](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/profile-detection-and-fail-closed-target-policy.md): Built and validated prototype in lib/profile.sh establishing multi-manifest detection, fail-closed remotes (no kultivait default), and fail-closed test validation (no fake-green "true" fallback).
- [Supervisor Bug Fixes and Re-Verdict Logic](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-bug-fixes-and-re-verdict-logic.md): Rewrote loop-bot-herd.sh dedupe logic with jq exact matching to support re-verdicts after RED, fixed substring collisions (#23 vs #230), and defined missing note/step helpers.
- [TOML Configuration Schema and Shell Binding](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/toml-configuration-schema-and-shell-binding.md): Implemented lib/config.sh using python3 tomllib to parse swarm.config.toml into shell bindings, dynamic seat arrays, namespaced agent names, and dry-run markdown plans.
- [Brief Templating Syntax and Nonce File Protocol](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/brief-templating-syntax-and-nonce-file-protocol.md): Authored briefs/*.in.md templates and lib/briefs.sh renderer to dynamically inject {{REPO}}, {{TEST_CMD}}, and namespaced seats into .herdr-swarm/briefs/, delivered via compact file-path prompts.
- [Workspace Lifecycle and Clean Teardown Protocol](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/workspace-lifecycle-and-clean-teardown-protocol.md): Implemented lib/lifecycle.sh with workspace auto-discovery, safe per-pane agent teardown, audit log retention, and rich terminal status inspection.
- [Preflight Dependency and Daemon Verification](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/preflight-dependency-and-daemon-verification.md): Implemented lib/preflight.sh with 9-point validation matrix (daemon, core CLIs, python tomllib, gh auth, agent CLIs, git repo) and actionable human remediation hints.
- [Lifecycle Safe Teardown and Target Disambiguation](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/lifecycle-safe-teardown-and-targeting.md): Hardened lib/lifecycle.sh with physical pane CWD matching, confirmation gate, and seats.json selective pane retirement to eliminate destructive teardown hazards (D1).
- [Profile Validation and Safe Slug Emitter](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/profile-validation-and-safe-slug-emitter.md): Hardened lib/profile.sh test validation (blocking auto-mode on empty/none/true test commands), introduced shared lib/common.sh slugify(), and updated lib/config.sh to safely emit environment bindings via sys.argv and shlex.quote (D3 & D4).
- [Integrate Profile Detection into Swarm Launcher](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/integrate-profile-into-launcher.md): Sourced lib/profile.sh and lib/lifecycle.sh in herdr-loop-swarm.sh, deleted hardcoded kultivait and TEST_CMD="true" defaults, gated auto-queue mode against non-runnable test commands, and bound workspace lookup to physical CWD (T-INT-1).
- [Supervisor Re-Verdict Deduplication Protocol](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-reverdict-dedupe-protocol.md): Updated loop-bot-herd.sh and briefs/arch.in.md with explicit commit sha protocol (ARCH DONE #<n> <sha>) and (ticket, sha) deduplication, enabling suite re-evaluation on new commits after RED failures (T-007a-fix / D2).
- [README Truth: Align Documentation with Shipped Architecture](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/readme-truth-and-capabilities.md): Aligned README.md with shipped architecture, striking fictional components and documenting modular libraries, fail-closed profiling, and lifecycle guarantees (T-015a).




## Not yet specified

- **Phase 2 Parallel Worktree Swarm Fan-out:** Merging the Claude-PM worktree isolation variant with the Universal Swarm so workers operate in disposable git worktrees for concurrent execution.
- **Cross-LLM Quota and Credit Probing:** Live API credit/rate-limit detection across Anthropic, Google Gemini, and Z.AI backends to gracefully pause or reroute workers before rate limits fail tasks.
- **GitHub Issues Two-Way Synchronization:** Automatic synchronization between local markdown decision tickets and GitHub Issues once an upstream remote is attached.

## Out of scope

- Windows or PowerShell compatibility (POSIX bash 3.2+ and macOS/Linux only).
- Modifying the upstream `herdr` daemon Go codebase or daemon protocol.
- Autonomous auto-push of code, branches, or release tags to remote Git origins without explicit human driver authorization.
