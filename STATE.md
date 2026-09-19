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
- **Done Means Integrated:** Writing a library in isolation is not sufficient to claim completion. Integration tickets (T-INT-1, T-INT-2, T-INT-3, T-INT-4) require wiring into `herdr-loop-swarm.sh` and deleting obsolete hardcoded fallback paths.

---

## 2. Active Status & Open Items

- **In Progress:** `T-INT-1` (Integrate Profile Detection into Swarm Launcher). `arch` is currently integrating `lib/profile.sh` and `lib/lifecycle.sh` into `herdr-loop-swarm.sh`, deleting `Standard-Pentest/kultivait` and `TEST_CMD="true"` defaults, and enforcing fail-closed execution.
- **Next Up (Critical Path per `docs/reordered-plan.md`):**
  1. `T-007a-fix (D2)`: Supervisor re-verdict deduplication protocol (`ARCH DONE #<n> <sha>` + `(ticket, sha)` dedupe).
  2. `T-INT-2`: Integrate TOML config registry & dynamic seat arrays (`lib/config.sh`).
  3. `T-INT-3`: Integrate brief templating & nonce file delivery (`lib/briefs.sh`).
  4. `T-INT-4`: Wire preflight verification and lifecycle commands (`up`, `down`, `status`).

---

## 3. Immediate Next Step

- Monitor `arch` to finish T-INT-1 implementation.
- Run independent verification checks (`grep -n 'Standard-Pentest\|TEST_CMD="true"' herdr-loop-swarm.sh`, fail-closed scratch execution).
- Update ticket `maps/tickets/integrate-profile-into-launcher.md` and commit.
