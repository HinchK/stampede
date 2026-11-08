# Prior Art for Herdr and Stampede Orchestration

Date: 2026-11-07. Research for **Herdr harness and Stampede orchestration prior art**. Synthesizes verified primary sources across terminal substrates, multi-agent coding harnesses, agent-to-agent protocols, merge queues, human-automation taxonomies, and fault-tolerant supervision architectures, cross-referenced against Stampede's existing landscape audits (`open-source-landscape.md` and `gas-city-herdr-adapter.md`).

---

## 1. Terminal Multiplexers & Persistent Substrates

Herdr's foundational bet—that the terminal is the universal ABI every coding agent already speaks—sits on four decades of multiplexer and remote-shell evolution. Each predecessor isolated a specific boundary that Herdr either inherits or still needs to harden:

- **`tmux` (Control Mode & Format Trees):** Beyond basic detach/reattach (`server` ↔ `client` over a Unix socket), `tmux` pioneered **Control Mode (`tmux -C` / `-CC`)**, a machine-readable, newline-delimited protocol over stdin/stdout that emits asynchronous `%output`, `%layout-change`, and `%exit` notifications alongside structured format strings (`#{pane_id}`, `#{pane_current_command}`). Originally built for iTerm2 native window rendering, it proved a multiplexer can serve humans visually and control planes programmatically over the same server.
  - *Steal / Avoid:* Herdr's `herdr api` socket subscription (deferred in ADR 0017) is the exact equivalent of `tmux -C`. Adopt Gas City's rule when wiring it: treat socket events as **wake hints to re-poll authoritative state, never as authoritative state transitions themselves**. [tmux Control Mode Wiki](https://github.com/tmux/tmux/wiki/Control-Mode)
- **Zellij (WASM Plugin Sandbox & Layout Resurrection):** Zellij (`zellij-org/zellij`, ~35.7k stars, active) compiles its own UI chrome and third-party extensions to WebAssembly/WASI communicating over typed pipes with explicit capability permissions, and serializes session layouts (`kdl` manifests) to disk for post-reboot resurrection.
  - *Steal / Avoid:* Herdr (`herdrdev/herdr`, ~43.1k stars) ships a plugin manifest (`plugins.mdx`). Packaging Stampede's `up / status / down / doctor` lifecycle as a declarative Herdr plugin—rather than an external shell script invoking `pane split` imperatively—solves distribution and startup ordering in one stroke. [Zellij Plugin Documentation](https://zellij.dev/documentation/plugins) · [Herdr Plugins Docs](https://github.com/herdrdev/herdr/blob/2563803/docs/next/website/src/content/docs/plugins.mdx)
- **`abduco` + `dvtm` (Decoupling Persistence from Windowing):** Marc André Tanner split `tmux` along the Unix philosophy line: `abduco` handles *only* process session persistence and detach/reattach (like `dtach`), while `dvtm` handles *only* tiling window management.
  - *Steal / Avoid:* Validates Stampede's headless batch mode (`bin/stampede headless`, ADR 0015). Worker lifecycle and result capture (`wt` / `.herdr-swarm`) must never depend on TUI focus or viewport geometry—the root cause of the `pane split --current` focus bug documented in `herdr-semantics.md`. [abduco Repository](https://github.com/martanne/abduco) · [dvtm Repository](https://github.com/martanne/dvtm)
- **Mosh (State Synchronization Protocol — SSP):** Mosh (`mobile-shell/mosh`, USENIX ATC 2012) replaced SSH's unceasing byte stream with UDP **state synchronization** of the terminal screen object: only the diff between the last acknowledged state and the latest frame is transmitted.
  - *Steal / Avoid:* Instead of scraping raw scrollback streams or polling full transcripts, orchestrator status probes (`wt peek`, `agent read`) should diff structured terminal state snapshots (`visible` vs `recent-unwrapped`) keyed by sequence/generation numbers. [Mosh USENIX Paper](https://mosh.org/mosh-paper.pdf)

---

## 2. Multi-Agent Coding Harnesses & Worktree Orchestrators

The `git worktree` + terminal-session pattern has converged across dozens of tools. Comparing them against Stampede's three core invariants (independent exact-SHA test execution, combined-tree CAS integration, and human-only `main` promotion) exposes where peers cut corners:

- **Gas Town & Gas City (`gastownhall/gastown` ~18.3k stars; `gastownhall/gascity` ~1.4k stars, active):** The closest architectural relative. Gas Town pairs a "Mayor" coordinator, ephemeral "polecat" workers in git-worktree "hooks", a Dolt-backed issue graph (**Beads**, `gastownhall/beads`, ~27.8k stars), and a "Refinery" merge queue. **Gas City** extracts this infrastructure into a Go SDK with a native **Herdr runtime backend** (`internal/runtime/herdr/`, ~3,800 LOC).
  - *How it works & diverges:* In Gas Town's live path (`mol-refinery-patrol.formula.toml`), the Refinery gate is **an LLM agent** that runs tests, attempts conflict resolution, and pushes to `main` itself (a deterministic Go batch/bisect engine exists in `internal/refinery/batch.go` but has no non-test caller at `649b832`). However, Gas City's Herdr adapter has already survived three breaking Herdr CLI drifts (0.7.4/0.7.5, 0.8.0, 0.9.1) and documents hard-won defenses: one-tab-per-agent (zero `pane split` calls), persisted pane-ID bindings verified via `pane process-info`, shell-ready polling before `agent start`, and an opt-in `make test-herdr-live` test suite.
  - *Steal / Avoid:* **Steal** Gas City's Herdr adapter hardening (persisted pane-ID routing, `pane process-info` readiness checks, `test-herdr-live` CI tier) and Beads' dependency-aware `ready` filter (`blocked_by` / `depends_on`). **Avoid** delegating the merge gate or conflict resolution to an LLM ("Refinery agent"). [gastown Repo](https://github.com/gastownhall/gastown) · [gascity Herdr Provider Doc](https://github.com/gastownhall/gascity/blob/3bc4148/docs/reference/herdr-provider.md) · [beads Repo](https://github.com/gastownhall/beads)
- **`no-mistakes` (`kunchenguid/no-mistakes`, ~8.8k stars, active):** A local Git proxy remote sitting in front of `origin`. Pushing a branch spins up a disposable worktree, runs `review → test → docs → lint`, and forwards the push only when green.
  - *Steal / Avoid:* **Steal** `test.base_attribution` (`internal/pipeline/steps/test_base_attribution.go`): when a worker commit fails the test suite (`RED`), re-run the suite at the merge-base SHA to classify the failure as `introduced` vs `pre-existing` before burning a worker repair cycle. **Avoid** its fallback of asking an LLM agent to run tests when `commands.test` is unset. [no-mistakes Repo](https://github.com/kunchenguid/no-mistakes)
- **OpenRig (`mvschwarz/openrig`, ~6.4k stars, active):** YAML-declared agent rigs (`rig.yaml`) over a Hono/SQLite daemon on `tmux`, using Herdr by default as a multi-pane viewer (`rig terminal open --provider herdr`).
  - *Steal / Avoid:* **Steal** `rig seat set-typing-guard <seat> --enabled true`, which holds automated prompt delivery when a human is actively typing in a shared seat (like `pm`), and its explicit invariant that scope approval *"is NEVER the source of proven-green."* **Avoid** shared-checkout seats (`cwd: "."` in its starter rig). [OpenRig Repo](https://github.com/mvschwarz/openrig)
- **`claude-squad` (`smtg-ai/claude-squad`, ~8.6k stars, AGPL-3.0):** Go TUI pairing one `tmux` session + one `git worktree` per agent (Claude Code, Codex, OpenCode, Gemini CLI, Aider) with a central diff preview and pause/resume loop.
  - *Steal / Avoid:* Clean keyboard-driven diff inspection per seat before queuing; lacks automated test gating or combined-tree verification. [claude-squad Repo](https://github.com/smtg-ai/claude-squad)
- **Crystal / Nimbalyst (`stravu/crystal`, ~3.1k stars, superseded by commercial Nimbalyst) & Vibe Kanban (`BloopAI/vibe-kanban`, ~28.3k stars, sunsetting to community maintenance):** GUI/web wrappers provisioning worktrees per task card with inline diff viewers and rebase/squash buttons; **Cline Kanban (`cline/kanban`, ~1.4k stars)** adds dependency-linked cards and symlinks gitignored directories (`node_modules`) into new worktrees.
  - *Steal / Avoid:* **Steal** warm worktree provisioning—use copy-on-write caches (as in **`worktrunk`**, `max-sixty/worktrunk`, ~9.1k stars) rather than `node_modules` symlinks so one worker's package install cannot mutate another worker's test gate. [stravu/crystal Repo](https://github.com/stravu/crystal) · [BloopAI/vibe-kanban Repo](https://github.com/BloopAI/vibe-kanban) · [cline/kanban Repo](https://github.com/cline/kanban) · [worktrunk Repo](https://github.com/max-sixty/worktrunk)
- **Conductor (`conductor.build`, commercial macOS app + cloud microVMs) & Agent Orchestrator (`OrchestratorInc/agent-orchestrator`, ~13.0k stars):** Desktop control planes isolating agents in worktrees or Firecracker microVMs. Agent Orchestrator derives kanban card state (`Working`, `Needs you`, `In review`, `Ready to merge`) strictly from observable Git/PR/CI facts rather than self-reported labels, and automatically routes failed CI logs back to the owning worker.
  - *Steal / Avoid:* Fact-derived state reconciliation (matching Stampede's `STATUS-INDET-1` philosophy). [Conductor Site](https://www.conductor.build) · [Agent Orchestrator Repo](https://github.com/OrchestratorInc/agent-orchestrator)
- **`claude-flow` / Ruflo (`ruvnet/ruflo`, ~74.2k stars), Overstory (`jayminwest/overstory`, ~1.3k stars, archived), and `mcp_agent_mail` (`Dicklesworthstone/mcp_agent_mail`, ~2.2k stars):**
  - Overstory's post-mortem archival note explicitly warns that in multi-agent swarms *"compounding error rates, cost amplification, debugging complexity, and merge conflicts are the normal case."* It introduced `FILE_SCOPE` drift detection with a worker-declared `expansion_reason:` field.
  - `mcp_agent_mail` pairs an MCP mailbox server with an optional **pre-commit Git hook** in worker checkouts that blocks commits touching paths leased by another agent. (Note: `mcp_agent_mail` carries a non-standard OpenAI/Anthropic license rider—treat as a clean-room concept only, never copy code.)
  - *Steal / Avoid:* Wire Stampede's existing `partition_drift_check` (`lib/partition.sh`) into the supervisor post-GREEN gate *and* install a clean-room pre-commit hook in each worker worktree that warns/blocks on undeclared `owns:` paths unless an `expansion_reason:` is provided. [Overstory Repo](https://github.com/jayminwest/overstory) · [mcp_agent_mail Repo](https://github.com/Dicklesworthstone/mcp_agent_mail) · [Ruflo Repo](https://github.com/ruvnet/ruflo)
- **First-Party Runtime Primitives (Claude Code Subagents & Agent Teams, OpenAI Symphony):**
  - Claude Code supports `isolation: worktree` on subagents and experimental **Agent Teams** (`TeammateIdle` / `TaskCompleted` quality-gate hooks that reject completion when exiting code `2`).
  - OpenAI's **Symphony** (`openai/symphony`, ~27.6k stars) specifies an Elixir reconciliation daemon (`SPEC.md`) that polls an issue tracker, runs per-issue workspaces governed by a repo-owned `WORKFLOW.md`, and automatically terminates active agent runs the moment an issue's tracker state becomes ineligible.
  - *Steal / Avoid:* Use harness-native turn-end hooks (`TaskCompleted` / `.agents/hooks.json`) to enforce result-file formatting before the worker even yields, and adopt Symphony's reconciliation state machine for cancelling zombie workers when tickets close or re-scope. [Claude Code Subagents Docs](https://code.claude.com/docs/en/sub-agents) · [Claude Code Agent Teams Docs](https://code.claude.com/docs/en/agent-teams) · [OpenAI Symphony Spec](https://github.com/openai/symphony/blob/be10a1b/SPEC.md)

---

## 3. Agent-to-Agent Orchestration Protocols & Lifecycle Semantics

Herdr's `wt` (walkietalkie) CLI (`delegate → status → peek → wait --any → result → answer → cancel → release`) maps cleanly onto formal multi-agent and durable-workflow primitives—with one novel epistemic distinction:

| `wt` / Herdr Primitive | Formal Prior Art Equivalent | Key Mechanism & Lesson |
| :--- | :--- | :--- |
| `wt delegate` / `release` | **OpenAI Agents SDK** (`handoff()` vs Agents-as-Tools) | Distinguishes transferring control of the conversation thread (`handoff` with `input_filter`) from scoped RPC invocation where the parent retains orchestration authority (`wt delegate`). [OpenAI Agents SDK Handoffs](https://openai.github.io/openai-agents-python/handoffs/) |
| `wt status: blocked` + `wt answer` | **Google / Linux Foundation A2A Protocol** (`input-required`) & **LangGraph** (`interrupt()` / `Command(resume=...)`) | In A2A (`a2aproject/A2A`, ~26.1k stars), a task transitions to `TASK_STATE_INPUT_REQUIRED` when blocked on clarification; the caller resumes the exact `taskId` with a message. In LangGraph, `interrupt()` checkpoints graph state and halts execution until `Command(resume=value)` supplies the answer. [A2A Protocol Spec](https://github.com/a2aproject/A2A) · [LangGraph Interrupts](https://langchain-ai.github.io/langgraph/concepts/human_in_the_loop/) |
| `wt wait --any` (settled-on-delivery) | **POSIX `epoll` (edge- vs level-triggered)** / **Go `select`** / **Actor Selective Receive** | Counting a completed delegation as outstanding *until delivered to the caller* prevents the classic lost-wakeup race between spawning a worker and entering `wait`. |
| **Result File vs. Salvaged Transcript (`salvaged`)** | **Mostly novel in agent frameworks** (closest: CI exit-code vs stdout log archival) | AutoGen (`microsoft/autogen`), CrewAI, and LangGraph treat the final LLM message in a chat transcript *as* the return value, blurring partial reasoning with committed output. Herdr's rule—orchestrators read only the explicit result file, and a scraped terminal on crash is quarantined as `salvaged` ("evidence of work, not a result")—is a major epistemic upgrade. [AutoGen Repo](https://github.com/microsoft/autogen) |

---

## 4. Merge Queues & Tested-Integration Prior Art

Stampede's arbiter (`drain` onto an integration ref → run full test suite on combined tree → CAS ref update → human `promote --confirm`) is a direct local implementation of **Graydon Hoare's "Not Rocket Science" rule** (*automatically maintain a repository of code that always passes all tests*):

- **`bors` / `bors-ng` (Batching & Binary Bisection):** Tested approved PRs against `main` in a staging branch (`staging.tmp`). To amortize expensive test suites, `bors-ng` merged batches of green PRs (`main + A + B + C + D`) and tested once; if the combined tree failed due to semantic merge skew, it recursively **bisected** the batch in $O(\log N)$ runs to isolate and eject the offending PR while landing the rest. (Note: `bors-ng` archived in 2024 after GitHub productized native Merge Queues; `rust-lang/bors` continues for Rust.)
  - *Steal / Avoid:* Stampede already has a parked spec for arbiter batching (`docs/audits/2026-09-19-p3-4-arbiter-batching-spec.md`). When unparked, pair `bors-ng`'s binary bisection with Gas Town's MIT-licensed `internal/refinery/batch.go` test cases. [bors-ng Repository](https://github.com/bors-ng/bors-ng) · [rust-lang/bors Repository](https://github.com/rust-lang/bors)
- **Zuul (Projective Gating & Speculative Execution):** Built for OpenStack (`zuul-ci.org`), Zuul eliminates serial queue latency by constructing cumulative speculative git states (`main + A`, `main + A + B`, `main + A + B + C`) and testing them concurrently across worktrees. If `B` fails, Zuul drops `B`, cancels `main + A + B + C`, and immediately restarts `main + A + C`.
  - *Steal / Avoid:* Because Stampede runs tests locally, full Zuul speculation across $N$ worktrees can saturate local CPU/memory and trigger cross-worker test flakiness. Prefer **bounded batching (`bors`-style)** on a single local machine, or reserve speculative trees for cloud/container runners (`dagger/container-use`). [Zuul Project Gating Docs](https://zuul-ci.org/docs/zuul/latest/project-gating.html)
- **Emergency Base-Health Precondition (`multiclaude` / `no-mistakes`):** Before draining the queue or blaming a worker for a `RED` verdict, verify that the target base branch itself passes `TEST_CMD`. If `main` (or the integration ref) is already broken, halt queue drains immediately rather than falsely rejecting every queued worker branch.

---

## 5. Autonomy Tiers & Human-Automation Boundaries

Stampede's `quiet / medium / loud` attention levels and explicit human `promote --confirm` boundary map directly onto classic human-factors engineering:

- **Sheridan & Verplank (1978) — 10 Levels of Automation (LOA):** Established in *Human and computer control of undersea teleoperators* (MIT Man-Machine Systems Lab), their 10-point continuum places the critical architectural boundary between **Level 5** (*computer executes suggestion if the human approves* — Stampede's `promote --confirm`), **Level 6** (*computer allows the human a restricted time window to veto before automatic execution*), and **Level 7** (*computer executes automatically, then necessarily informs the human* — Stampede's `quiet` tier for routine ticket dispatch and repair loops). [Sheridan & Verplank 1978 MIT Report](https://dspace.mit.edu/handle/1721.1/149334)
- **Parasuraman, Sheridan, & Wickens (2000) — 4-Stage Model of Automation:** Demonstrated in *IEEE Transactions on Systems, Man, and Cybernetics* (30(3), 286–297) that automation should **not** be set to a single uniform level across the whole system, but tuned independently across four cognitive stages:
  1. *Information Acquisition* (Telemetry, git status, test runs → **Level 9–10** in Stampede)
  2. *Information Analysis* (Exact-SHA verdict deduplication, base attribution, diff summary → **Level 8–9**)
  3. *Decision Selection* (Looper ticket routing and repair assignment → **Level 5–7**, governed by `quiet/medium/loud`)
  4. *Action Implementation* (Moving `main` or external side effects → **Level 5** hard human gate)
  - *Steal / Avoid:* Keep Information Acquisition and Analysis at maximum automation (zero human toil to discover state), let `quiet/medium/loud` modulate *only* Stage 3 (Decision Selection), and keep Stage 4 irreversible actions (`promote` to `main`, external deploys) locked at Level 5. [Parasuraman et al. 2000 DOI](https://doi.org/10.1109/3468.844354)
- **Harness Permission Modes & Environment Gates:** Claude Code's permission tiers (`plan` → `acceptEdits` → `dontAsk` / `bypassPermissions`) and GitHub Actions' **Environment Protection Rules** (mandatory human reviewers + wait timers before a job can access production secrets or refs) provide the implementation pattern: bind worktree seats to broad local write permissions, but restrict base-branch ref mutations at the OS/git-hook level so an autonomous seat physically cannot fast-forward `main`. [Claude Code Permissions Docs](https://code.claude.com/docs/en/permissions)

---

## 6. Supervision, Fault Tolerance & the "Idle Orchestrator" Problem

The two fragilities identified in Herdr/Stampede—*"nothing wakes an idle orchestrator on its own"* and best-effort natural-language contracts—are classic distributed-systems problems with battle-tested solutions:

- **Erlang/OTP Supervision Trees & Actor Mailboxes:**
  - *Why the idle-orchestrator problem happens:* In an Actor system (Hewitt 1973; Armstrong 2003), every process owns a kernel-managed **mailbox**. When a process blocks on `receive`, the scheduler suspends it and wakes it deterministically the instant a message lands in its mailbox—whether the sender sent it before or after `receive` was called. Terminal TUIs have **no inbox separate from stdin**: if a worker "pings" an orchestrator by injecting keystrokes while the orchestrator is mid-turn or typing, it corrupts the prompt; if it writes to `.wt/` without injecting a prompt, the idle orchestrator sits at its TUI prompt forever.
  - *How OTP solves it:* Separate the **durable mailbox** (`.wt/` or `.herdr-swarm/` state files) from the **wakeup edge** (a deterministic supervisor/dispatcher loop that watches both the mailbox and the orchestrator's `idle` state, delivering the next queued envelope *only* when the target seat transitions to `idle` and has no human typing guard active).
  - *Supervision & Restart Intensity:* OTP supervisors pair restart strategies (`one_for_one`, `rest_for_one`, `one_for_all`) with child restart types (`permanent`, `transient`, `temporary`) and a **restart intensity breaker (`MaxR` restarts within `MaxT` seconds)** before escalating up the tree. Stampede's workers are `transient` (restart on abnormal crash/stall, not on clean `DONE`), while the Looper is `permanent` under a circuit breaker. [Erlang/OTP Supervisor Design Principles](https://www.erlang.org/doc/system/sup_princ.html)
- **Temporal (Durable Execution & Event-Sourced Replay):** Temporal (`temporalio/temporal`) guarantees workflow completion across process crashes by recording an append-only **Event History** (`ActivityTaskScheduled`, `ActivityTaskCompleted`, `TimerFired`). Workers emit deterministic *Commands*, and on restart replay the event log without re-executing completed external side effects.
  - *Steal / Avoid:* Stampede's `(ticket, sha)` verdict deduplication (ADR 0002) and `.herdr-swarm/seats.json` ledger are already half of an event-sourced log. Making the supervisor transition log explicitly replayable (`DISPATCHED → WORKER_COMMITTED → GATE_RUNNING → VERDICT_RECORDED → QUEUED → DRAINED`) ensures a supervisor restart mid-test-run resumes cleanly without double-testing or losing verdicts. [Temporal Durable Execution Docs](https://docs.temporal.io/evaluate/understanding-temporal)
- **Hearsay-II Blackboard Architecture (Erman, Hayes-Roth, Lesser, & Reddy, 1980):** Hearsay-II coordinated heterogeneous, unreliable specialist modules ("Knowledge Sources") by forbidding direct peer-to-peer chatter. Instead, all specialists read from and wrote structured hypotheses to a shared, multi-level **Blackboard**, while a central **Scheduler/Monitor** triggered the next specialist whenever a precondition matched.
  - *Steal / Avoid:* Stampede's `.herdr-swarm/` + `maps/tickets/` directory *is* a Hearsay-II blackboard, and `loop-bot-herd.sh` is the blackboard monitor. Keep workers decoupled from each other; resist adding free-form peer-to-peer agent chat meshes, which recreate Overstory's compounding error cascades. [Hearsay-II ACM Computing Surveys 1980](https://doi.org/10.1145/356810.356816)

---

## 7. Comparison Matrix: System × Mechanism Coverage

| System | Terminal Substrate | Worktree Isolation | Structured Delegation (`wt`-style) | Salvage vs Result Distinction | Non-Agent Exact-SHA Gate | Combined-Tree Merge Queue | Path Leases (`owns:`) | Human-Only Base Promote |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Herdr + Stampede** | **Native (Herdr)** | **Yes** | **Yes (`wt`)** | **Yes (`salvaged`)** | **Yes (Fail-closed)** | **Yes (CAS Drain)** | **Yes (Dispatch)** | **Yes (`promote`)** |
| **Gas Town / Gas City** | Herdr & tmux | Yes (Hooks) | Yes (`gt sling`) | Partial | No (LLM Refinery; Go unwired) | Partial (LLM / unwired Go) | No | No (Auto-push default) |
| **OpenRig** | tmux (+Herdr view) | No (Shared cwd) | Yes (SQLite queue) | Partial (Batons) | No (Agent gate roles) | No (Ancestry read only) | No (`depends_on`) | N/A |
| **`no-mistakes`** | N/A (Git proxy) | Gate-only | No | No | Partial (Falls back to LLM) | No (Single branch) | No | Yes (Opens PR) |
| **`claude-squad`** | tmux | Yes | No (Human TUI) | No | No | No | No | Yes (Manual merge) |
| **Agent Orchestrator** | Desktop daemon | Yes | Yes | No | Partial (Hosted CI) | No | No | Unverified |
| **OpenAI Symphony** | App-server / CLI | Dir-per-issue | Tracker-driven | No | No (Agent-supplied proof) | No | No | Partial (`Human Review`) |
| **Overstory** *(archived)* | Subprocess / TUI | Yes | Yes (SQLite mail) | No | No | Partial (FIFO + AI merge) | Advisory (`FILE_SCOPE`) | Unverified |
| **Zuul / `bors-ng`** | N/A (CI bots) | Ephemeral CI | N/A | CI logs vs status | **Yes (Deterministic CI)** | **Yes (Speculative / Batch)** | No | Automatic on green |

---

## 8. Top 10 Things to Steal (Ranked by Impact / Effort for Herdr & Stampede)

1. **Mailbox-to-Idle Wakeup Dispatcher (Erlang/OTP + OpenRig Typing Guard)**
   - *Target:* Herdr `wt` daemon / `loop-bot-herd.sh` + `lib/briefs.sh`
   - *Implication:* Solve *"nothing wakes an idle orchestrator"* without racing human keystrokes. Maintain a durable inbox queue per seat; when an item arrives in `.wt/` or `.herdr-swarm/`, a background watcher waits until `herdr agent get <seat>` reports `status == "idle"` **and** no human typing guard is active before injecting a single compact wake pointer.
2. **Base-Branch Failure Attribution on `RED` (`no-mistakes` `test_base_attribution.go` + `multiclaude`)**
   - *Target:* `loop-bot-herd.sh` supervisor gate & `lib/arbiter.sh`
   - *Implication:* When a worker commit fails `TEST_CMD`, run `TEST_CMD` once against the commit's merge-base (or cache the base SHA's green/red status). Tag the verdict `RED:introduced` vs `RED:pre-existing`, and refuse to drain the arbiter if the base branch itself is red. Saves wasted worker repair turns on broken trunks.
3. **Commit-Time `owns:` Pre-Commit Guard + Post-GREEN Drift Enforcement (`mcp_agent_mail` + Overstory)**
   - *Target:* `lib/worktree.sh`, `lib/partition.sh`, `loop-bot-herd.sh`
   - *Implication:* Wire the already-written `partition_drift_check` into the supervisor immediately after a `GREEN` verdict (authoritative check), and install a clean-room `.git/hooks/pre-commit` inside each worker worktree at provision time that checks `git diff --cached --name-only` against the ticket's leased `owns:` globs, allowing overrides only when the commit message carries `expansion_reason: <why>`.
4. **Gas City's Herdr Adapter Defenses (Persisted Pane-ID Binding & `pane process-info` Readiness)**
   - *Target:* `herdr-loop-swarm.sh`, `lib/lifecycle.sh`, `lib/standby.sh`
   - *Implication:* Stop firing `herdr agent start` immediately after `pane split` without checking shell readiness, and stop discarding `agent prompt` exit codes at the six `>/dev/null 2>&1 || true` call sites identified in `gas-city-herdr-adapter.md`. Poll `pane process-info` (or wait for shell prompt) before starting the agent, cap generated seat names at 32 chars, and add an opt-in `make test-herdr-live` test target.
5. **Harness-Native Turn-End Hooks to Enforce Result Contracts (Claude Code `TaskCompleted` / FailproofAI)**
   - *Target:* `.agents/hooks.json`, worker worktree provisioning
   - *Implication:* Replace "best-effort natural-language standing briefs" for completion anchors (`ARCH DONE #<ticket> <sha>`) and `wt` result files with a turn-end hook (`Stop` / `TaskCompleted`) in the worker's harness config that verifies the result file or commit anchor exists and exits `2` (blocking turn completion and prompting the agent to write its result) if missing.
6. **Dependency-Aware `ready` Ticket Filter (Beads `bd ready` / Claude Code Task List)**
   - *Target:* `lib/headless.sh`, `loop-bot-herd.sh` dispatch
   - *Implication:* Parse `depends_on:` / `blocked_by:` in `maps/tickets/*.md` frontmatter and filter out tickets with unresolved dependencies before presenting candidates to the Looper or headless dispatcher. Five lines of shell/Python, zero new database dependencies.
7. **Tracker-Driven Zombie Run Cancellation (OpenAI Symphony `SPEC.md` §8.5)**
   - *Target:* `lib/headless.sh`, `loop-bot-herd.sh`
   - *Implication:* On each supervisor pass, reconcile active seats against ticket state. If a human closes, parks, or re-scopes a ticket while a worker is actively grinding on it, automatically cancel the worker turn and release its path lease instead of letting it burn quota to a stale `ARCH DONE`.
8. **Copy-on-Write Warm Worktree Provisioning (`worktrunk` / `cline/kanban`)**
   - *Target:* `lib/worktree.sh`, `swarm.config.toml`
   - *Implication:* Add an optional `post_provision` hook or APFS/Btrfs copy-on-write clone step (`cp -cR` on macOS) for heavy build caches (`target/`, `.venv/`, `node_modules/`) so exact-SHA supervisor gates and fresh worker worktrees don't pay cold dependency-install latency while preserving strict filesystem isolation between seats.
9. **Parasuraman 4-Stage Autonomy Mapping for `quiet / medium / loud` (Sheridan & Verplank 1978; Parasuraman et al. 2000)**
   - *Target:* `swarm.config.toml`, `docs/user-guide.md`
   - *Implication:* Explicitly separate Stage 1–2 (sensing/analysis: always Level 9–10 automated), Stage 3 (ticket dispatch and repair retries: modulated by `quiet/medium/loud` between Level 5 and Level 7), and Stage 4 (`promote` to `main`: pinned at Level 5 human approval, or optional Level 6 timed-veto window in headless batch mode).
10. **Opt-In OTLP Telemetry Exporter Keyed by `run.id` (Gas Town `otel-data-model.md`)**
    - *Target:* `lib/telemetry.py`
    - *Implication:* Keep `.herdr-swarm/traces/*.jsonl` as the zero-dependency local record, but add an env-gated OTLP exporter mapping each seat dispatch to a trace `run.id` with attributes for `seat`, `ticket`, `sha`, `verdict`, and `trust_tax_ms` so standard observability dashboards can chart swarm efficiency alongside `trust-tax-telemetry-measurements.md`.

---

## 9. What Nobody Does Yet (Herdr & Stampede's Differentiation)

Across the 68+ repositories surveyed in `open-source-landscape.md` and the foundational literature above, **three combinations remain unoccupied in the open-source ecosystem**:

1. **Zero-Trust Triple Gate on Local Multi-Vendor Worktrees:** No other surveyed system combines (a) fail-closed non-agent test execution on the exact worker SHA, (b) combined-tree re-verification on a separate integration ref via compare-and-swap, and (c) a strict refusal to let an LLM resolve merge conflicts or fast-forward `main`. Closest peers (`gastown`, `multiclaude`, `overstory`, `Aperant`) all hand the final merge or conflict-resolution decision back to an LLM agent.
2. **Epistemic Quarantine of Crashed Agent Work (`salvaged` Evidence vs. `result`):** Mainstream agent protocols (AutoGen, LangGraph, CrewAI, A2A) treat partial transcript state on failure as either an opaque error or a regular message. Herdr's explicit `salvaged` state—scraping the terminal witness while machine-labeling it *"evidence of what the worker did, not a result it wrote for you"*—is a genuinely novel primitive that prevents downstream orchestrators from hallucinating success out of a mid-thought crash.
3. **Dispatch-Time Path Leases Paired with Independent Post-Hoc Verification:** Tools that isolate via `git worktree` almost universally adopt `multiclaude`'s *"let them collide and resolve at merge time"* posture, while tools with file reservations (`mcp_agent_mail`) rely on voluntary agent compliance without an independent merge gate. Enforcing disjoint `owns:` path leases at dispatch *before* work begins, verifying drift post-GREEN, and gating convergence through a deterministic arbiter is uniquely Stampede's territory.
