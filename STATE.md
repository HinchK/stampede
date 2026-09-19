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

---

## 2. Active Status & Open Items

- **Milestones M1 & M2 Complete:**
  - M1 (Safe entrypoint): Teardown safety (D1), Profile fail-closed (D3/D4), Launcher profile integration (T-INT-1), Re-verdict dedupe (D2), README truth (T-015a).
  - M2 (Generalize): TOML config integration (T-INT-2), Namespacing (T-005), Brief nonce delivery (T-INT-3), Supervisor genericization (T-007b), Preflight verification (T-008).
- **M3 (Lifecycle & Observability) Progress:**
  - T-INT-4 (`up`/`down`/`status` subcommands): Complete (`5ca2049`).
  - T-010 (Seat verification & brief acknowledgment gate): Complete (`33a07b3`).
  - T-009-impl (Telemetry event engine & live Ops streaming): Complete (`8b059f2`).
  - Next Up:
    1. `T-015b`: Complete README & user guide polish (capturing modular architecture, lifecycle subcommands, seat verification, and live telemetry).
    2. End-to-end swarm rehearsal & live dogfood verification.

---

## 3. Immediate Next Step

- Draft ticket `maps/tickets/readme-and-user-guide-polish.md` for `T-015b`.
- Dispatch `agy-docs` and `arch` to refine `README.md` and user documentation.
- Execute full dry-run / live rehearsal of `herdr-loop-swarm.sh`.
