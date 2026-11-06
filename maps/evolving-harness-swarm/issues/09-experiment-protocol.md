---
id: EHS-09
title: "Choose the pilot configurations and freeze the experiment protocol"
type: wayfinder:grilling
status: closed
assignee: null
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-01, EHS-02, EHS-03, EHS-06, EHS-08]
---

# Choose the pilot configurations and freeze the experiment protocol

## Question

Which comparison can fairly test whether this Stampede design improves the chosen workload, and what must be recorded before results are observed?

Consider a strong single-agent baseline with a good harness, a swarm with fixed harnesses, and a swarm with evolving harnesses. Decide how to isolate orchestration from model choice and adaptation. Select tasks/projects, splits, repeated-run strategy, model/version pinning, resource limits, stopping rules, success thresholds, and human involvement. Include context resets, integration, later defects, adaptation overhead, and subscription accounting (API support is deferred). Define reporting for uncertainty, losses, and task-specific tradeoffs.

Specify the evidence and data handling needed to reproduce the comparison without exposing credentials or private project material. This ticket writes the protocol; it does not run it.

Carry forward the effort-first adoption criterion and required per-model token velocity over time from [Define the first engineering workload and what better means](01-workload-and-success.md). Define which token categories are counted (including input, output, and cache accounting where available), the time denominator and sampling windows, model/version attribution, provider-reported versus estimated data, and behavior when measurements are unavailable. Distinguish generation throughput from end-to-end run throughput and relate both to accepted outcomes, human effort, retries, and adaptation overhead. Address differences in token accounting across models before comparing rates. Do not treat higher token consumption as proof of efficiency.

**Intended Outcome:** A predeclared, reproducible experiment protocol with honest success and failure criteria.

If assisted kickoff or the human proxy is enabled, record their research, deliberation, token use, and decision outcomes. Distinguish actual human interventions from proxy answers; include time spent correcting mistaken proxy assumptions. Declare whether these components are shared by comparison arms or deliberately varied so their contribution is not misattributed to model choice or swarm size.

Include contract-lawyer overhead and effectiveness: timestamped friction/failure events requiring mediation, decisions, time to resolution, repeated or reopened failures, and human escalations. Separate recorded agent decisions from actual human interventions; include later rework caused by mistaken mediation. Define event classification and deduplication before comparing runs.

Carry forward the startup opt-in capacity/quota policy from [Set replication, routing, resource, and authority limits](07-replication-and-routing.md). Record whether the user enabled it, provider/account quota observability, threshold notifications, human choices, handoffs due to unknown quota versus confirmed exhaustion, and the two-provider stop. A benchmark requiring capacity controls must explicitly opt into them in its run brief; it must not silently turn them into product defaults. Restrict initial pilot arms to eligible subscriptions; API and local models are later work.

Freeze the numerical adoption criteria and test partitions required by [Define how harness improvements are proposed, evaluated, and adopted](08-harness-evolution.md): quality floors, measurable benefit, repeat counts, motivating cases versus held-out/regression tasks, evaluator independence, overhead attribution, and task-family-specific scope. Do not treat token velocity alone as an improvement or allow a candidate to alter its own grading rules.

**Done-Criteria:** HinchK has selected workloads, configurations, resource bounds, measurements, and decision criteria; unresolved confounders are explicit.

**Verification Step:** Review whether a negative result is possible and reportable, whether baselines are fairly equipped, and whether an independent reader could reproduce the intended comparison.

## Comments

### 2026-11-06 — Closed out of scope

HinchK directed the map to bypass the comparative experiment and continue toward a simpler Herdr-based Stampede. Prior selections and research remain historical context, not an adopted requirement for the revised handoff. Evidence for safe harness-improvement adoption remains an open design question.

### 2026-11-06 — Claimed; simplicity and Herdr reuse

HinchK reaffirmed keeping this simple and using Herdr's strengths. Its [quick-start](https://herdr.dev/tui/docs/quick-start/) documents project workspaces, terminal panes, automatic agent detection with sidebar status, and a background session that keeps agents running when the client detaches. Reuse those facilities in every comparison arm. Detaching is not pausing or interrupting a worker, and a displayed agent state is not an acceptance verdict.

Keep the initial experiment to frozen briefs/checks, isolated Git starting points, and a small nonsecret run record plus results table. No new terminal manager, evaluation service, or telemetry platform is needed for the protocol. Native status can inform timing, but it does not establish per-model token counts or quota availability; record unavailable measurements honestly.

Pending human decisions: staged comparison size, first representative starter-task family, and the practical benefit threshold. Recommendations are not yet an adopted protocol. No experiment or live Herdr session has been launched.

### 2026-11-06 — Human selections and request for a visible run

HinchK selected:

- A staged six-run pilot: two runs each for a well-equipped single agent, a fixed-harness swarm, and that swarm with improvement enabled. Each run has a four-hour maximum and stops earlier on completion.
- A small multi-file Stampede bugfix milestone with reproducible failing checks, within the setup → real starter task → stop/resume experience.
- A provisional win requires all agreed acceptance checks, no new serious regression, and at least 25% less active human effort than the relevant baseline. Count setup, review, recovery, corrections, and improvement overhead. Slower elapsed completion is acceptable within the deadline; small or inconsistent results are inconclusive. Report token consumption and per-model velocity separately.

HinchK subsequently requested seeing the pilot run. This explicitly authorizes moving toward visible execution beyond the earlier planning-only scope; it does not make the proposed runtime or unfinished comparison protocol implemented. Model configurations, the exact bugfix and independent checks, improvement allowance/partitions, and attribution rules still need to be frozen before comparative results count.

Launch preflight: this Codex desktop process is outside a Herdr-managed pane (`HERDR_ENV` is not `1`). The Herdr binary is installed, but no live session was inspected or controlled. Continue the visible run from an agent actually running inside Herdr; do not simulate that context by setting its environment flag. Today's repository includes a separate demo walkthrough at `examples/demo-repo/README.md`; that demo is not the agreed Stampede bugfix experiment. No pilot has started.

### 2026-11-06 — Provider selection correction

HinchK explicitly excludes Codex from every pilot panel. AGY with Flash and ZCode are the primary everyday routes; Claude models are occasional support. The earlier instruction to start Codex inside Herdr is withdrawn. Use an eligible selected native harness for the coordinating panel as well as workers; Codex is not a launch prerequisite.

Use these selected routes when freezing the single-agent baseline and both swarm configurations. Record the actual underlying model and harness versions, and count occasional Claude assistance explicitly; do not quietly add it to only one arm and attribute the difference solely to orchestration or improvement. Earlier Sonnet-level default suggestions do not override this user's pilot selection. Roles and exact models remain to be verified and frozen; this correction does not claim that ZCode/AGY native integration or the proposed pilot is already runnable.

### 2026-11-06 — Codex agent added for the live handoff

HinchK reports adding a Codex agent after the launch-context blocker. The new agent can receive the live pilot handoff; AGY Flash and ZCode remain the requested everyday workers, with occasional Claude support. Do not interpret adding this agent as replacing that provider selection. If Codex contributes to a measured run, record its role and effort explicitly. This desktop chat still reports no Herdr-managed context; the new agent must verify its own context and discover actual panes before controlling them.

### 2026-11-06 — Failed live handoff diagnosis

The pasted follow-up Codex session reported empty `HERDR_ENV`, workspace, tab, and pane IDs. It ran in the `research/swarm-evaluation-methods` checkout at `b5f4439`, whereas the canonical local checkout is `main` at `350271b` as observed here. It prepared `/tmp/stampede-herdr-feasibility.10hCqJ/RUN.md` and an independent check, but did not launch an agent or run the pilot. These are preparation artifacts, not evidence of a visible run. The OpenCode catalog preflight defect is a plausible proposed bugfix, not a task already named by this protocol; the prior session's statement that the protocol named it was incorrect. The source checkout also has unrelated edits, so a run must use an isolated copy of the intended current starting commit and freeze the exact task/checks first.

Recovery: use an agent in an actual Herdr pane; verify its injected context before any session control. Reuse the prepared check only if the user-selected pilot task remains this defect, and refresh the source snapshot to the intended commit. Keep the first run explicitly unscored until the comparison rules are frozen.

### 2026-11-06 — Current-capability preflight and Herdr handoff

This is a repository preflight, **not a pilot run**. The process doing this check is outside Herdr (`HERDR_ENV` is absent), so it did not register an agent, inspect panes, or launch a trial. AGY Flash and ZCode remain the primary pilot workers; the separately added Codex agent is for live handoff, and any contribution it makes to a measured run must be recorded.

| Available in the current code | Still needed for the selected pilot |
| --- | --- |
| `stampede setup` probes AGY, Claude, and OpenCode, offers models, and writes a project config and launcher. `tests/test_setup.sh` passed in this checkout. | A guided **starter-task selection** and recorded acceptance brief; setup currently stops at configuration and launch guidance. |
| The launcher can seat or reattach a Herdr workspace. Bounded AGY decisions, worktree seats, exact-commit suite gates, and a manually drained integration queue exist. | A disposable live Herdr walkthrough of setup → actual bugfix → stop/reattach/resume → accepted result. Unit tests do not establish that workflow. |
| Current config uses AGY Flash for the looper, OpenCode with a ZAI Coding Plan model for architects, and Claude for the PM. It has two architect seats and quiet attention. | Verify actual subscription eligibility, installed model IDs, harness versions, native Herdr agent support, and effective routes. The current Claude PM must be counted as support or replaced consistently; these config values are not a frozen experimental roster. |
| AGY looper usage receipts and general trace/status surfaces exist; quota probes report `ok`, `unknown`, or `error`. | Active human-minute ledger, per-model token time series and comparability rules, mediation/rework events, quota threshold choices, and honest missing-data flags for **all** arms. No current status display is an acceptance verdict. |
| Brief templates and model settings can be changed using existing files. | Version-specific candidate briefs, independent held-out/regression checks, repeat criteria, overhead accounting, and rollback evidence before the evolving arm can be scored. |

The checkout is dirty (including this untracked planning map, `CONTEXT.md`, and `swarm.config.toml`). Trials must start from separately captured, identical Git snapshots; do not launch an arm directly in this checkout or let one arm see another arm's solution. Preserve the existing worktree and runtime state. For the first **visible feasibility pass**, use Herdr's native panes/status and an isolated disposable copy; record the exact source SHA, harness/model versions, route eligibility, task brief, check hashes, run start/stop, and every human intervention. Treat this pass as instrumentation and workflow validation, outside the six scored runs.

Before scored runs, freeze one small multi-file Stampede bugfix with a failing reproduction and independent acceptance checks, then give every arm the same starting snapshot, task, stop point, and four-hour limit. The already selected order of magnitude is two runs per arm: strong single agent, fixed swarm, and fixed swarm plus bounded improvement. A provisional result requires the agreed checks, no serious regression, and at least 25% less **total active human time** than the relevant baseline; count setup, review, recovery, corrections, and all improvement/evaluation work. Report all six outcomes, including failures/timeouts, elapsed time, tokens and per-model velocity separately; two repeats only support a feasibility signal. Do not claim that a single-agent-versus-swarm difference is solely orchestration if the provider/model pool differs.

**Open launch decisions:** exact bugfix and hidden checks; pinned eligible AGY/ZCode routes and whether Claude support is allowed equally in all arms; order/randomization and reset method; improvement allowance plus motivating/held-out partitions and numeric candidate-adoption rule; independent reviewer; token-window/accounting schema; optional quota-management choice and observable limits. EHS-09 remains claimed. The next Herdr-managed AGY/ZCode coordinator should use this list to freeze the run sheet and perform the disposable feasibility pass before any scored trial.

### 2026-11-06 — Smallest reproducible starter bug and live-context gate

The current process again reports no `HERDR_ENV`; Herdr's agent list and panes were not inspected, and no agent was launched. Local binary/catalog checks found AGY 1.5.2 with `gemini-3.8-flash-low` listed, OpenCode 2.2.5 with `zai-coding-plan/glm-5.3` listed, and Claude Code 2.1.319. A catalog listing verifies neither subscription entitlement nor a working Herdr agent session. The existing config's Claude PM would make Claude a routine participant; use a separately frozen pilot config if Claude is only occasional support.

**Feasibility starter task:** make OpenCode model preflight fail closed when OpenCode is installed, an enabled primary OpenCode seat pins a model, and `opencode models` fails or returns an empty catalog. `providers_check_opencode_models` currently prints `opencode models unavailable — model preflight skipped` and returns success in that case; the launch caller then proceeds toward workspace creation. A disposable stub with `opencode models` exiting 1 and a pinned `zai-coding-plan/not-a-real-model` reproduced exit 0. `tests/test_providers.sh` remains green (49 checks) because it covers unlisted models with a working catalog and an absent binary, but not this unavailable-catalog case. Preserve the existing absent-binary fallback behavior and disabled/non-OpenCode-seat behavior. The likely change surface is `lib/providers.sh` plus `tests/test_providers.sh`; `herdr-loop-swarm.sh` is the single launch caller and should still stop before workspace creation on a nonzero preflight result.

For a **disposable, unscored** Herdr pass, copy one clean source snapshot, add the independent failing check before assigning work, run setup with AGY Flash and ZCode/OpenCode as the primary seats, and have the worker repair this bug. Observe a stop and reattach before final verification, then run the independent check and `make check` on the exact candidate. Keep the actual pane/agent IDs, effective model versions, route and human-effort records in the run sheet. Do not start the six scored comparisons from this preparation pass; the held-out checks, adaptation allowance, accounting, and route eligibility above remain unfrozen.
