# Swarm State Checkpoint: Universal Herdr Swarm (`herd-swarm`)

**Updated:** 2026-09-19  
**Active Phase:** Milestone 1 — Foundations & Core Correctness  
**Orchestrator Pane:** `looper` (AGY)  

---

## 1. Decisions Made

1. **Architecture & Scope**:
   - `herdr-loop-swarm.sh` is transitioning into a project-agnostic, universal swarm orchestrator (`herd-swarm up|watch|down|status`).
   - Hardcoded kultivait assumptions are converted into dynamic profile inputs (`.herdr-swarm/profile.env`).
   - Single source of truth is established in `swarm.config.toml` (parsed via `python3 -c tomllib`).
   - Per-project agent namespacing (`arch·<slug>`, `looper·<slug>`, `pm·<slug>`) prevents cross-project agent conflicts in Herdr.
   - All brief deliveries use the file path + nonce channel (no raw prompt strings).

2. **Milestone Progression**:
   - **Milestone 1 (M1)**: Foundations & Correctness (V1–V3 blockers: git baseline, herdr semantics, workspace focus, agent namespacing, bats harness).
   - **Milestone 2 (M2)**: Config, Profiling & Brief Templating (V4–V6: profile lib, TOML registry, brief templating, loop-bot supervisor).
   - **Milestone 3 (M3)**: Swarm Lifecycle & Observability (V7–V10: preflight check, telemetry wiring, seat verification, down/status commands, ops-tab additions, README rewrite).

3. **Invariants & Safety**:
   - Hard Invariant: `looper` orchestrates and verifies; implementation code is written exclusively by `arch`.
   - All worker dispatches strictly conform to the **3-line prompt preamble**.
   - Remote git operations require explicit human driver approval.

---

## 2. Master Task Catalog (Standard 3-Line Preambles)

### Milestone 1: Foundations & Correctness

#### Ticket T-014: `chore: init git repo and establish clean baseline`
1. **Intended Outcome**: Initialize a git repository for `loop-bot-herd-agy` with standard `.gitignore` and create the baseline commit.
2. **Explicit Done-Criteria**: `git rev-parse --is-inside-work-tree` returns 0; `.gitignore` ignores `.herdr-swarm/`, `__pycache__/`, `*.pyc`, and `.DS_Store`; all existing script files and briefs are committed on branch `main` with message `chore: initial repository baseline (#T-014)`.
3. **Verification Step**: Run `git status --porcelain` and verify working tree is clean with exit code 0.

#### Ticket T-001: `research: document herdr workspace-focus and agent-name semantics`
1. **Intended Outcome**: Research and document whether `herdr workspace focus <ID>` routes subsequent pane/agent operations and test valid per-project agent naming syntax.
2. **Explicit Done-Criteria**: Comprehensive findings documented in `docs/findings/herdr-semantics.md` answering: (1) Does `workspace focus` route subsequent pane/agent commands? (2) Are agent names strictly global or workspace-scoped? (3) Which separator characters (`·`, `-`, `_`) are accepted by `herdr agent start <NAME>`.
3. **Verification Step**: Run `test -f docs/findings/herdr-semantics.md && grep -q "workspace focus" docs/findings/herdr-semantics.md && grep -q "agent naming" docs/findings/herdr-semantics.md`.

#### Ticket T-013: `test: bats test harness and HERDR_FAKE mock shim`
1. **Intended Outcome**: Create a bats test suite with a mock `herdr` CLI (`HERDR_FAKE`) to validate launcher logic, profile detection, and TOML parsing completely offline.
2. **Explicit Done-Criteria**: Test suite runs in CI/offline without a live herdr daemon; `shellcheck` runs on all bash scripts and passes with 0 warnings.
3. **Verification Step**: Run `bats tests/` and `shellcheck herdr-loop-swarm.sh lib/*.sh` and confirm all tests pass cleanly.

#### Ticket T-004: `fix: workspace context and focus routing`
1. **Intended Outcome**: Ensure `herdr-loop-swarm.sh` creates/attaches workspaces keyed on absolute directory path ($PWD) and explicitly executes `herdr workspace focus $WS_ID` before pane/agent allocation.
2. **Explicit Done-Criteria**: Launching swarm in separate project directories creates distinct workspaces without pane cross-placement or label collisions; workspace focus is guaranteed before pane split.
3. **Verification Step**: Run `herdr workspace list` across two distinct test directories and verify each workspace contains only its designated panes.

#### Ticket T-005: `feat: per-project agent namespacing`
1. **Intended Outcome**: Namespace agent identities based on project slug (e.g., `arch·<slug>`, `pm·<slug>`, `looper·<slug>`) across launcher, supervisor, and briefs.
2. **Explicit Done-Criteria**: Multiple swarms in different project directories can be seated simultaneously without name collision errors; launcher, supervisor `EXPECTED_SEATS`, and status queries use the namespaced name.
3. **Verification Step**: Run `herdr agent list` with two running project instances and verify both sets of namespaced seats exist concurrently.

---

### Milestone 2: Config, Profiling & Brief Templating

#### Ticket T-002: `feat: profile detection library`
1. **Intended Outcome**: Implement `lib/profile.sh` to reliably auto-detect project ecosystem, test command, GitHub canonical repository slug, and documentation directory without hardcoded kultivait fallbacks.
2. **Explicit Done-Criteria**: `lib/profile.sh` defines `detect_profile()` which fails closed when no GitHub remote exists (prompts user or reads `.herdr-swarm/profile.env`); outputs variables `REPO`, `TEST_CMD`, `ECOSYSTEM`, `DOCS_DIR`; passes bats test suite across Python, Rust, Node, and Go fixtures.
3. **Verification Step**: Run `grep -rq "Standard-Pentest/kultivait" lib/profile.sh && exit 1 || bats tests/test_profile.bats`.

#### Ticket T-003: `feat: TOML seat and swarm configuration registry`
1. **Intended Outcome**: Implement a TOML parser utility (`lib/config.sh` backed by `python3 -c tomllib`) to dynamically parse `swarm.config.toml` into shell key-value pairs.
2. **Explicit Done-Criteria**: Eliminates all hardcoded seat arrays and model mappings in shell scripts; dynamically registers seats, kinds, models, tabs, and briefs from `swarm.config.toml`; supports `--plan` dry-run preview.
3. **Verification Step**: Run `python3 -c "import tomllib; tomllib.load(open('swarm.config.toml', 'rb'))" && ./lib/config.sh --dump-env | grep -q "SEATS="`.

#### Ticket T-006: `feat: templated briefs with file+nonce delivery`
1. **Intended Outcome**: Convert static briefs in `briefs/` into templates (`briefs/*.in.md`) that substitute variables (`{{REPO}}`, `{{TEST_CMD}}`, `{{DOCS_DIR}}`, `{{ARCH_NAME}}`) into `.herdr-swarm/briefs/` at startup, delivered via file path + nonce channel.
2. **Explicit Done-Criteria**: All hardcoded kultivait assumptions are eliminated or gated behind profile flags; briefs are never passed inline via massive shell prompt strings; workers receive brief path via nonce channel.
3. **Verification Step**: Run `diff -u briefs/looper.in.md .herdr-swarm/briefs/looper.md` on a test profile and verify `{{TEST_CMD}}` is substituted with the project's actual runner.

#### Ticket T-007: `fix: loop-bot supervisor genericization`
1. **Intended Outcome**: Parameterize `loop-bot-herd.sh` to supervise arbitrary projects using project-specific `STATE_DIR`, suite gates using detected `TEST_CMD`, and dynamic seat lists from config.
2. **Explicit Done-Criteria**: `loop-bot-herd.sh` operates without hardcoded kultivait paths; suite gate executes arbitrary test runners (`cargo test`, `npm test`, `go test`); logs verdicts to `.herdr-swarm/verdicts.jsonl`.
3. **Verification Step**: Execute `./loop-bot-herd.sh status` and `./loop-bot-herd.sh check-suite` in a fixture directory and verify proper test gate execution.

---

### Milestone 3: Swarm Lifecycle & Observability

#### Ticket T-008: `feat: preflight dependency verification`
1. **Intended Outcome**: Implement robust preflight validation in `lib/preflight.sh` checking for herdr daemon responsiveness, required CLI binaries (`jq`, `gh`, `python3`), agent CLIs (`agy`, `claude`, `opencode`), and GitHub authentication.
2. **Explicit Done-Criteria**: Detects missing tools or unauthenticated GitHub CLI before creating workspaces or splitting panes; prints human-readable remediation commands; exits cleanly with non-zero status.
3. **Verification Step**: Run `PATH=/usr/bin:/bin ./lib/preflight.sh` and verify it exits non-zero with specific missing tool diagnostics.

#### Ticket T-009: `feat: telemetry and circuit breaker integration`
1. **Intended Outcome**: Wire `agent_guard.sh` and `telemetry.py` into launcher and supervisor execution paths, outputting structured JSONL trace events and streaming live formatted events to the Ops log pane.
2. **Explicit Done-Criteria**: Every dispatch, verdict, and state change writes a structured JSON event to `.herdr-swarm/traces/<session>.jsonl`; Ops tab log pane displays real-time formatted events.
3. **Verification Step**: Inspect `.herdr-swarm/traces/*.jsonl` with `jq .` and verify validity of generated event entries.

#### Ticket T-010: `feat: seat verification and rollback`
1. **Intended Outcome**: Implement post-start verification for all seated agents, ensuring each agent reaches `idle` status and acknowledges its brief within bounded timeout.
2. **Explicit Done-Criteria**: If an agent fails to initialize or stalls, launcher logs the failure, leaves intact seats running, and exits with a structured diagnostic summary instead of hanging.
3. **Verification Step**: Simulate agent start failure (invalid model/command) and verify launcher catches timeout and reports partial herd state.

#### Ticket T-011: `feat: swarm lifecycle commands (down and status)`
1. **Intended Outcome**: Implement `down` and `status` subcommands in the swarm script to gracefully stop agents, close panes/workspaces, and display live swarm health metrics.
2. **Explicit Done-Criteria**: `down` cleanly stops agents and terminates panes without leaving orphaned processes; `status` prints a formatted table of active seats, current frontier task, and test suite health.
3. **Verification Step**: Run `./herdr-loop-swarm.sh down` followed by `herdr agent list` to verify all project-scoped agents are cleaned up.

#### Ticket T-012: `feat: ops tab topology enhancements`
1. **Intended Outcome**: Expand the Ops tab to include `reviewer` (default-on), an active `loop-bot` supervisor pane, and dynamic proxy gating based on profile configuration.
2. **Explicit Done-Criteria**: Ops tab allocates panes for `reviewer`, `loop-bot`, and live log; avoids creating dangling proxy panes if proxy is disabled or already running.
3. **Verification Step**: Run `./herdr-loop-swarm.sh --plan` and verify Ops tab topology contains designated panes according to `swarm.config.toml`.

#### Ticket T-015: `docs: README and user guide synchronization`
1. **Intended Outcome**: Rewrite `README.md` and related docs to accurately document the universal `herd-swarm` lifecycle, configuration schema, templating, and telemetry.
2. **Explicit Done-Criteria**: Removes outdated or un-implemented claims; provides clear quickstart instructions for launching the swarm in any arbitrary Git repository.
3. **Verification Step**: Follow quickstart instructions verbatim on a clean test repository and verify successful swarm initialization.

---

## 3. Open Items & Blockers

- **T-014 (Git Baseline)**: Unblocked; must be executed first so subsequent changes have atomic commits.
- **T-001 (Herdr Semantics)**: Unblocked once git baseline is committed.
- **Agent Panes Status**:
  - `arch`: Idle, finished brainstorming, ready for dispatch.
  - `pm`: In progress running herd audit.
  - `agy-docs`: Idle, briefed on documentation & ADR duties.
  - `agy-gh`: Idle, briefed on GitHub issue tracking.

---

## 4. Next Immediate Action

1. Dispatch **Ticket T-014** to `arch` to initialize git repository and commit baseline.
2. Once T-014 is verified, dispatch **Ticket T-001** to `arch` for herdr semantics research spike.
