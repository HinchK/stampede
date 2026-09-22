# Swarm State Checkpoint: Universal Herdr Swarm (`herd-swarm`)

**Updated:** 2026-09-22  
**Plan of Record:** [maps/universal-herdr-swarm.md](maps/universal-herdr-swarm.md)  
**Execution Roadmap:** [docs/reordered-plan.md](docs/reordered-plan.md)  
**Orchestrator:** `looper` (wM:p1, AGY Flash)  
**Implementer:** `arch` (wM:p5, OpenCode GLM-5.3)  
**Overseer:** `pm` (wM:p4, Claude Code)  
**Documenter:** `agy-docs` (wM:p7, AGY Flash)  
**GitHub Specialist:** `agy-gh` (wM:p8, AGY Flash)  

---

## 1. Key Decisions Made

- **Teardown Safety (D1 / T-011-fix):** Resolved in commit `f6cfbc4`. `find_workspace_by_cwd` strictly inspects physical pane CWDs; `swarm_down` uses `.herdr-swarm/seats.json` ledger to close only recorded seats; interactive confirmation gate required.
- **Fail-Closed Profile & Safe Slug Emitter (D3 & D4 / T-002-fix):** Resolved in commit `44c0d56`. Empty prompts loop until non-empty input; `test_cmd_is_runnable` blocks empty/none/true test gates; `slugify()` normalizes names to `^[a-z][a-z0-9_-]*$`; `lib/config.sh` emits environment variables via `sys.argv` and `shlex.quote`.
- **Launcher Preflight & Subcommands (T-INT-4 / T-008):** Resolved in commit `5ca2049`. 9-point preflight matrix runs fail-closed before workspace/pane mutation; `up`, `down`, and `status` subcommands delegate directly to `lib/lifecycle.sh`.
- **Dynamic Seating & Templated Brief Delivery (T-INT-2, T-005, T-INT-3):** Resolved in commit `2455bc5`. Dynamic seating from `swarm.config.toml` with `<seat>-<slug>` namespacing, nonce file-path prompt delivery (<200b), and `.herdr-swarm/seats.json` durable ledger.
- **Supervisor Genericization & Re-Verdicts (T-007a-fix, T-007b):** Resolved in commits `64170d7` and `94d6534`. Strict `(ticket, sha)` deduplication, `profile.env` binding, and real project test runner gating.
- **Telemetry Event Engine & Live Ops Streaming (T-009-impl):** Resolved in commit `8b059f2`. Upgraded `lib/telemetry.py` with project-scoped traces (`.herdr-swarm/traces/`), standardized `domain.action` envelope, column-clamped ANSI badge streaming in Ops pane, and unified session logging in launcher and supervisor.
- **Architecture Decision Records & System Vocabulary:** Resolved in commit `aa06ec4`. `agy-docs` authored ADRs 0001–0005 in `docs/adr/` with index in `README.md`, and system vocabulary with `_Avoid_` anti-patterns in `CONTEXT.md`.
- **README & User Guide Polish (T-015b):** Resolved in commit `15d61a0`. Documented all lifecycle subcommands (`up`, `down`, `status`, `verify`), live telemetry ANSI streaming engine, dynamic seating, seat verification protocol, ADR index, and repo tree.
- **Supervisor Anchored Verdict Harvesting & Mode-R Gating (T-007c-fix):** Resolved in commit `5acf8f6`. Fixed root cause H1 (false-green verdict scraping from scrollback) using strict whole-line regex anchoring (`^[[:space:]]*ARCH DONE #[0-9]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]*$`), gated mode `r` fail-closed against unrunnable test commands, routed skipped verdicts to human gate, purged legacy fixture records (#99, #42, #77, #55), and deleted orphan `lib/agent_guard.sh`.
- **Launcher Target Directory & SHA Validation (T-016-arch):** Resolved in commit `1030654`. Symmetrical `up [dir]` argument support, git commit SHA object existence check (`git cat-file -e "${sha}^{commit}"`) before suite gating in `loop-bot-herd.sh`, and `interactive-ready` status relabeling in `lib/lifecycle.sh`.
- **Git Worktree Isolation & Phase 2 Blueprint (T-016-docs / ADR 0006):** Resolved in commit `53dd36d`. `agy-docs` authored ADR 0006 (`docs/adr/0006-git-worktree-worker-isolation.md`) and `docs/worktree-swarm.md` outlining root orchestrator vs isolated worker topologies, ledger tracking in `seats.json`, and arbiter integration.
- **Phase 2 Concurrency & Worktree Advisory (PM Advisory):** Resolved in commit `6cf36e9`. `pm` (Claude Code) conducted empirical git concurrency tests (CAS ref updates, 0/240 commit failures in separate worktrees vs 4/6 lock failures in shared index) and defined the 8-step Phase 2 roadmap.
- **Nested Session Workspace Discovery (T-016c):** Resolved in commit `a08c9e8`. Sourced `find_workspace_by_cwd "$PWD"` in `herdr-loop-swarm.sh`, eliminating ambient `$HERDR_WORKSPACE_ID` hijacking and isolating nested/scratch swarms from host sessions.
- **GitHub Issues Two-Way Synchronization (T-017):** Resolved in commit `0ae36f5`. `agy-gh` authored protocol specification `docs/findings/github-issues-sync.md` and prototype CLI `lib/gh_sync.sh` with fail-closed authentication and zero unconfirmed writes (`--dry-run` default).
- **Dogfooding Rehearsal Receipt:** Documented in `docs/audits/2026-09-19-dogfooding-rehearsal-receipt.md`. Successfully executed `status` -> `up` (`wR`) -> `status` -> `down --yes` against `/tmp/herdr-dogfood-scratch-rehearsal` from inside `wM` with zero disruption to the host session.
- **Worktree Lifecycle Library (P2-1):** Resolved in commit `99867cf`. Built `lib/worktree.sh` supporting `worktree_provision`, porcelain locking, dirty tracked checkpoints, `worktree_prune`, and `worktree_reconcile`, validated by 21/21 passing assertions in `tests/test_worktree.sh`.
- **Worktree Config & Ledger Integration Specification (P2-2 Spec):** Resolved in commit `b01b81f`. `pm` authored `docs/audits/2026-09-19-p2-2-config-integration-spec.md` defining `swarm.config.toml` schema, `lib/config.sh` bindings, `seats.json` v2 schema, and the `split_pane` CWD ordering contract.
- **Phase 2 Release and Synchronization Validation Checklist (#T-GH-CHECKLIST):** Resolved in commit `9d9f3b7`. `agy-gh` authored `docs/findings/phase2-release-checklist.md` detailing 11-point acceptance criteria matrix, `lib/gh_sync.sh` validation, and promotion protocol.
- **ADR 0007 & Swarm Orchestration Retrospective (#T-DOCS-RETRO):** Resolved in commit `4e0a2e3`. `agy-docs` authored ADR 0007 (`docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md`) and `docs/findings/swarm-orchestration-retrospective.md` analyzing multi-agent floor topology, 80%+ token reduction, PTY buffer safety, and human operator ergonomics.
- **P2-3 Supervisor Worktree Suite Gating Specification (#P2-3-spec):** Resolved in commit `ce17f18`. `pm` authored `docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md` with empirical probes uncovering `-B` branch reset hazard and `--untracked-files=no` drift loophole.
- **Worktree Config Binding, Ledger v2 & Launcher CWD Integration (#P2-2):** Resolved in commit `5200df5`. `arch` implemented `worktree = true` in `swarm.config.toml`, `SEAT_WORKTREE_<seat>` in `lib/config.sh`, worktree-first pane creation in `herdr-loop-swarm.sh`, and atomic `seats.json` v2 serialization.
- **ADR 0008 Supervisor Worktree Suite Gating (#T-DOCS-ADR0008):** Resolved in commit `7697000`. `agy-docs` authored `docs/adr/0008-supervisor-worktree-suite-gating-and-drift.md` documenting ledger-first gate resolution, pre/post TOCTOU drift detection, and non-destructive branch re-attachment.
- **GitHub Issue Sync Validation Report (#T-GH-REPORT):** Resolved in commit `c018177`. `agy-gh` tested `lib/gh_sync.sh` against current tickets, documented zero unconfirmed writes in `docs/findings/gh-sync-validation-report.md`, and drafted P2-4 ticket.
- **Supervisor Worktree Suite Gating and Drift Validation (#P2-3):** Resolved in commit `420d5e6`. `arch` implemented `resolve_seat_gate()`, pre/post-run drift validation, per-seat `TMPDIR` and gate logging, and fixed the `-B` branch reset bug in `lib/worktree.sh`.
- **P2-4 Arbiter and Integration PR Specification (#P2-4-spec):** Resolved in commit `fee14b4`. `pm` authored `docs/audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md` specifying partition check, CAS fast-forward merge, PR creation, and teardown integration.
- **Phase 2 Release Notes & Migration Guide (#T-GH-RELEASE):** Resolved in commit `2092cb5`. `agy-gh` authored `docs/findings/phase2-release-notes-draft.md` with feature summary, migration guide, and operational instructions.
- **ADR 0009 Arbiter Branch Integration & CAS Merge (#T-DOCS-ADR0009):** Resolved in commit `9d5eaea`. `agy-docs` authored `docs/adr/0009-arbiter-branch-integration-and-cas-merge.md` capturing the off-branch integration architecture, CAS atomic updates, and human-promoted base merges.
- **Arbiter Branch Merge and Integration PR Engine (#P2-4):** Resolved in commit `3c4a584`. `arch` implemented `lib/arbiter.sh` (`arbiter_enqueue`, `arbiter_drain`, `arbiter_promote`) with 26/26 unit tests passing in `tests/test_arbiter.sh` and 0 shellcheck warnings.
- **Phase 2 Worktree Swarm Milestone Audit (#P2-AUDIT):** Resolved in commit `af18758`. `pm` conducted comprehensive empirical audit validating P2-1 through P2-4, confirming structural false green elimination and data loss closure, while identifying hardening items (H1-H5).
- **ADR 0010 Worktree Teardown Lifecycle and Salvage (#T-DOCS-ADR0010):** Resolved in commit `cd6979b`. `agy-docs` authored `docs/adr/0010-worktree-teardown-lifecycle-and-salvage.md` capturing non-destructive teardown, untracked salvage directory, and stale branch gate.
- **GitHub Sync Closeout (#T-GH-CLOSEOUT):** Resolved in commit `6732646`. `agy-gh` validated full 31-ticket inventory against `lib/gh_sync.sh` with zero unconfirmed writes.
- **Worktree Lifecycle Teardown, Untracked Salvage & Stale Branch Gate (#P2-H):** Resolved in commit `d7c9558`. `arch` implemented stale branch gating in `lib/worktree.sh`, untracked file salvage preservation, and teardown worktree unlocking/pruning in `lib/lifecycle.sh` (37/37 worktree tests passing).
- **Phase 3 Concurrent Fan-Out Roadmap (#P3-ROADMAP):** Resolved in commit `416b569`. `pm` authored `docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md` defining multi-worker seating, partition checking, and async harvesting.
- **Multi-Worker Config & Dynamic Roster Expansion (#P3-1):** Resolved in commit `b62faf1`. `arch` implemented dual implementation engines (`arch-1` with GLM-5.3, `arch-2` with Claude) in `swarm.config.toml`, `lib/config.sh`, and `herdr-loop-swarm.sh`.
- **ADR 0011 Multi-Worker Floor Topologies (#T-DOCS-ADR0011):** Resolved in commit `b62faf1`. `agy-docs` authored `docs/adr/0011-multi-worker-floor-topologies-and-concurrency.md` establishing scaling from 1 to $N$ implementation seats and model tier routing.
- **Phase 3 Milestone & Issue Sync Mapping (#T-GH-P3SYNC):** Resolved in commit `9050196`. `agy-gh` defined milestone boards, worker issue labels, and drafted tickets P3-2 and P3-3.
- **P3-2 Task Intake Partition Checking (#P3-2):** Resolved in commit `1992e37`. `arch` implemented `lib/partition.sh` (`parse_owns`, `normalize_path`, `overlaps`, `partition_check`, `lease_acquire`, `lease_release`, `suggest`) with 26/26 unit tests in `tests/test_partition.sh` and 0 shellcheck warnings.
- **ADR 0012 Task Partitioning & Disjoint Dispatches (#T-DOCS-ADR0012):** Resolved in commit `78cb21a`. `agy-docs` authored `docs/adr/0012-task-partitioning-and-disjoint-dispatches.md` capturing single-line frontmatter grammar, casefolded comparison, and arbiter-tied lease lifetimes.
- **Ticket Frontmatter Annotations (#T-GH-OWNS):** Resolved in commit `cd5c473`. `agy-gh` annotated 29 ticket frontmatters in `maps/tickets/` with single-line `owns:` declarations.
- **CLAUDE.md Refresh & Alignment:** Resolved in commit `1c8615b`. `pm` refreshed `CLAUDE.md` with verified 3-suite commands, arbiter integration pipeline, and partition/lease rules.
- **Local Engine Tier Activation (pi + kultivait) (#P3-LOCAL-PI):** Resolved in commit `f6ead53`. Configured local Metal-accelerated Qwen3-14B inference via `kultivait` on port 4114, seated `pi` in pane `wM:pC` (tab `local-pi`), and provisioned isolated worktree `.herdr-swarm/worktrees/pi`.
- **P3-3 Asynchronous Supervisor Harvesting & Durable Gate Jobs (#P3-3):** Resolved in commits `eafdc91` (implementation + `tests/test_async_gate.sh`, ADR 0013) and `144efea` (ticket resolved, frontmatter schemas harmonized). Background gate jobs in `.herdr-swarm/gates/` with `(ticket, sha)` dedup, concurrency cap, mid-gate invalidation.
- **P3-FLAKE-1 Concurrent worktree_provision Race:** Resolved in commit `cf8b546` — serialized provisioning under an advisory `provision.lock` with idempotent retry; later hardened by #BASH32-FLOOR's harness fix.
- **Bash 3.2 Platform Floor (#BASH32-FLOOR):** Resolved in commits `b9678f3`, `50ad127`. `owns_normalize`'s `//`-collapse leaked backslashes under macOS system bash (test [8d] red); and bash 3.2 fires the EXIT trap early when `wait` reaps a signal-killed bg job, which made the worktree suite's own cleanup delete its scratch tree (xtrace + minimal repro in the ticket). Suites now run under `/bin/bash`.
- **Aggregate Test Command (#TEST-AGG):** Resolved in commit `ec6d090`. `Makefile` with failure-propagating `test` (all suites), `lint` (0-warning shellcheck bar), `check` — the root fix for "one failure, four symptoms" (no aggregate runner → no CI → red landed on main → ledger certified by its own authors).
- **Self-Dogfooding Profile (#PROFILE-MAKE):** Resolved in commit `27c8b13`. `detect_ecosystem` resolves `make` (Makefile WITH a `test:` target) and `run_all` (`run_all.sh`) after the ecosystem markers; `profile.env.example` documents the hand-edit path. The swarm now gates its own repo from a clean clone (`TEST_CMD=make test`); the stale hand-typed `REPO="HinchK/prototype"` was corrected to `HinchK/stampede`.
- **Arbiter String Ticket Ids (#ARB-STR):** Resolved in commits `29667a1`, `906d699`. `--argjson t` silently dropped every non-numeric ticket id (the repo's entire vocabulary); the queue is string-typed end-to-end. The async-gate [8] assertion was updated to match (caught by the arbiter's own integration gate before promote — the pipeline works).
- **Proxy Config Gating (#PROXY-GATE):** Resolved in commit `14f8016`. `[proxy] enabled` defaults false; launcher preflight/launch and the supervisor's credits probe are config-gated; serve command and health URL are config data (`serve_cmd`, `health_check_url`), not launcher hardcode. Recovery pointer now names this repo's launcher.
- **PM Branch Reconciliation (#PM-BRANCH-RECON):** Resolved via the first real arbiter run: `P3-4` spec and `PM-PLAN-EVIDENCE` enqueued → gated (`make test`) → integrated (`97d31e2`, `d50c128`) → promoted ff-only to `main` (`d50c128`). Eleven superseded/equivalent pm branches deleted with per-branch evidence (`merge-tree` / `git cherry`); `.claude/worktrees/pm-audit` unlocked and removed; `git branch --no-merged main` is now empty.
- **Python Interpreter Resolver (#DOG-1 / Wave 1):** Resolved in commit `3a9a70d` (ticket marked resolved in `4993d58`). Centralized Python interpreter resolution in `lib/pyenv.sh` (`resolve_python()`), replacing bare `python3` invocations across `Makefile`, supervisor, library scripts, and test suites with a capability probe for `tomllib` ($PYTHON_BIN, python3.14 down to python3) and actionable remediation guidance. Added `tests/test_pyenv.sh` (16 passing assertions).
- **Dogfood Plan Deviation & Public Readiness Records:** Documented in `docs/audits/2026-09-21-public-readiness-review.md` and `docs/dogfood/`; the planned two-clone dogfooding run was superseded by direct in-repo execution.

---

## 2. Active Status & Open Items

- **Autonomous Reviewer Loop Milestone (IN FLIGHT — Waves 1–3 Complete):**
  - **Wave 1 Complete:** `REV-1` (`e22697c`): Reviewer config flag (`loop`, `max_rounds`) in `swarm.config.toml` bound in `lib/config.sh`, dual-mode brief with `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>` anchor and `.herdr-swarm/reviews/<ticket>-<sha>.md` report schema, +8 config assertions (promoted).
  - **Wave 2 Complete:** `REV-2` (`efc857e`): Critique delivery protocol: implementer refinement on existing worktree branch (`briefs/arch.in.md`, `briefs/arch.md`, `docs/user-guide.md`) (promoted).
  - **Wave 3 Complete:** `REV-3` (`ed86598`): Looper autonomous review loop state machine and fail-closed gate (`lib/lifecycle.sh`, `herdr-loop-swarm.sh`, `tests/test_review_loop.sh`). Durable `reviews.json`, directive contract, `--no-review-loop` flag, +40 assertions (promoted).
  - **Wave 4 In-Flight (runs alone):** `REV-4`: Review telemetry, rich status aggregation, and end-to-end verification (plus fast-follow fix for `lib/lifecycle.sh:199` stdout directive).
- **Public Multi-Provider Milestone (COMPLETE — Waves 8–12 Shipped):**
  - Shipped `PUB-1` through `PUB-11` (all promoted).
- **Standing Guardrails:**
  - Arch briefs enforce Single-Ticket Scope Guardrail: workers halt and await looper dispatch after reporting completion.
  - Base branch promotion remains human-only (DOG-12).
- **Total Test Suite Health:** **398 passed, 0 failed** across 16 suites (42 worktree, 40 review loop, 39 partition, 38 arbiter, 33 config, 28 quota, 27 gh_sync, 27 cli_status, 24 cli_init, 18 profile, 17 async gate, 16 pyenv, 15 cli, 14 cli_doctor, 13 providers, 7 telemetry); `make check` green (lint 0 warnings across 22 shell files).

---

## 3. Immediate Next Step

- Release `REV-4` from `maps/tickets-staged/` to `maps/tickets/` with status `ready`.
- Dispatch `REV-4` (Review telemetry, rich status aggregation, and fast-follow stdout directive fix) to an implementer seat (`arch-1` or `arch-2`).
- Verify and integrate `REV-4`.






