# Swarm State Checkpoint: Universal Herdr Swarm (`herd-swarm`)

**Updated:** 2026-09-19  
**Plan of Record:** [maps/universal-herdr-swarm.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/universal-herdr-swarm.md)  
**Execution Roadmap:** [docs/reordered-plan.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/reordered-plan.md)  
**Orchestrator:** `looper` (wM:p1, AGY Flash)  
**Implementer:** `arch` (wM:p5, OpenCode GLM-5.3)  
**Overseer:** `pm` (wM:p4, Claude Code)  

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

---

## 2. Active Status & Open Items

- **Milestones M1, M2, M3 Complete & Audited:**
  - Full end-to-end receipt attached; all M3 recommendations satisfied.
- **Phase 2 Implementation Frontier (Parallel Worktree Swarm Fan-Out):**
  - **P2-1 (Worktree Lifecycle Library `lib/worktree.sh`):** Provisioning, locking, pruning, and dirty checkpointing.
  - **P2-2 (Config & Ledger Integration):** Per-seat `worktree = true` in `swarm.config.toml` and `"worktree_dir"` in `.herdr-swarm/seats.json`.
  - **P2-3 (Supervisor Worktree Suite Gating):** Running suite verification inside the worker's worktree.
  - **P2-4 (Arbiter Branch Merge):** Safe compare-and-swap integration of verified worker branches.

---

## 3. Immediate Next Step

- Draft ticket `maps/tickets/worktree-lifecycle-library.md` for P2-1.
- Dispatch `arch` to build `lib/worktree.sh` and `agy-docs` to update user guides.
