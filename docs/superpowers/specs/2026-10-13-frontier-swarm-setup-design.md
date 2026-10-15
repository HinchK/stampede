# Stampede: guided frontier swarm setup and bounded looper

**Status:** Approved direction, 2026-10-13. The human asked us to proceed with the recommended decisions through completion.

## Intent

Stampede should help one person start and manage a small, well-fitted swarm of frontier coding agents in an existing repository. Setup should feel like choosing a team, not configuring a supervisor framework. Each role gets a model suited to its work and expected cost. A human can see what is happening, pause a ticket, detach safely, and run integration commands deliberately.

The immediate motivation is measured looper usage. In AgentsView's Stampede project view, four AGY looper/wayfinder sessions consumed at least 2.23 million output tokens and an estimated $136.79 over the inspected 30-day window. A Claude PM session was the largest single cost at $174. These figures justify bounding coordination turns and measuring the result; they do not prove that all those tokens were waste or that a different model alone will save a given amount.

## Goals and boundaries

- First-run command: `stampede setup /path/to/repo`. It detects available frontier harness CLIs, recommends a provider/model for each role, lets the human choose, and produces a valid project configuration without overwriting an existing one silently.
- Default roster: one AGY looper, one Claude PM, one AGY GitHub/CI agent, one AGY documentation agent, two coding architects, and one cheap frontier helper for small parallel tasks. PM and architect counts are adjustable; other roles start at one. A reviewer may remain an advanced optional seat. The helper starts with bounded research, summarization, and other non-code tasks; any code change must enter an isolated worker worktree and the same gate as architect work.
- A visible Herdr looper pane exists, but each looper wake runs one fresh, bounded AGY turn using a short durable checkpoint. No conversation continuation is used for routine coordination.
- Attention modes are human-configurable. `medium` is the setup default; `quiet` and `loud` can be selected at setup or changed during a session.
- Setup offers a `yeehaw.sh` quick launch script and asks where to save it. Startup never runs the arbiter.
- Setup clearly teaches detach, reattach, deliberate teardown, and the manual arbiter commands.
- Worklog, troubleshooting, and handoff views are ordinary non-agent Herdr panes or tabs backed by durable files.
- Preserve the existing exact-SHA worker gate, isolated worktrees, review boundary, and human-only base-branch promotion. Change the existing codebase incrementally.

Local models and Ollama detection are deferred to a later release. Do not present them during this setup. Do not claim accurate billing from CLI token counts or a static model catalog. Windows support and a new Herdr plugin are outside this first cut.

## First-run experience

1. `stampede setup <repo>` resolves the physical target, checks that it is a Git repository, inspects existing Stampede configuration/state, and reports any changes it would make. An existing configuration is shown and may be kept or edited; replacement requires an explicit choice and a backup. Setup does not launch agents or mutate the target's application files.
2. Probe each supported harness executable and the minimum capability needed to launch it. Display detected and unavailable harnesses separately. Where a harness can list available models safely, query it; otherwise allow a human-entered model ID and validate it at seating. Failed probes do not silently choose another paid provider.
3. Present role-by-role recommendations with a short reason and relative cost tier. Proposed starting choices are AGY Flash-tier for looper, GitHub, and docs; Claude Sonnet for PM with Opus selectable for harder oversight; OpenCode with GLM-5.3 for each architect; and the cheapest available frontier option suitable for the helper. These are **builder-maintained recommendations**, not user-approved fixed model IDs or price promises. The exact offered IDs must match the harnesses available at setup time. Every role's model can be changed independently. Supported provider/harness choices may vary by role; the looper uses AGY in this release, as the human specified, and setup should state that constraint. Fallbacks require an explicit configured model and cost tier so a cheap role cannot silently jump to an expensive model.
4. Choose PM and architect counts, attention mode (`medium` preselected), and the quick-launch destination. The default role counts above are shown first. The generated configuration uses the current `swarm.config.toml` format where practical; project runtime files live under `.herdr-swarm/` and are kept out of normal Git staging by a local exclude rule if necessary. Brief templates come from the Stampede installation and are rendered for the target, so a new target repo need not already contain `briefs/`.
5. Show a concise summary before writing: role, harness, exact model ID, count, target paths, and launch behavior. Write atomically, validate with the real parser, and retain a backup on replacement. A second run is idempotent and offers edits rather than duplicating panes or scripts.
6. Print the launch command, the chosen `yeehaw.sh` path, attention-mode command, manual arbiter commands, and the session lifecycle explanation from below.

The quick launcher takes `start --brainstorm --topic "..."`, `start --wayfinder --topic "..."`, or `start --seat-only`, translating to existing launcher modes. It has a fixed target-repository path, uses the installed Stampede entry point, quotes the topic safely, reports a missing installation, and never invokes an arbiter command. It is not created over an existing file without explicit replacement.

## Runtime and Herdr ownership

Herdr owns workspace/tab/pane topology, live agent identification, waits, notifications, detach, and reattach. Stampede owns ticket state, dispatch policy, authorization, gate evidence, and durable logs. Setup checks relevant Herdr integration status, especially for AGY, Claude, and OpenCode. Herdr native agent resume after a server restart is used only when the required integration reports support; a restart may otherwise return a shell. Detach preserves the running processes because the server keeps running.

The looper pane is a named shell/status surface. A deterministic supervisor receives worker anchors and Herdr state changes, writes event receipts, and decides whether the current attention policy calls for a looper turn. A one-shot AGY process is launched for that event in the looper pane or a tightly associated command, using the configured model, a bounded timeout, a single event description, and paths to the concise checkpoint and needed evidence. The implementation may use the installed AGY CLI's print/structured-output mode. It must not rely on an indefinite interactive AGY session or `--continue`. Herdr's `agent start` remains appropriate for persistent worker/PM seats; the looper's transient process is governed by its exit/result rather than assuming a persistent Herdr agent identity.

The checkpoint is regenerated from authoritative Stampede ledgers, not from the previous model's transcript. It contains the active ticket IDs and states, available seats, pending manual arbiter items, unresolved human decisions, and a bounded recent event list with file paths to full evidence. The model returns a small structured proposal and summary. Stampede validates every proposed action against ticket state, leases, seat readiness, write boundaries, and allowed command types before executing it. Model output is never run as arbitrary shell. The turn receipt and any human-facing summary are appended to durable files. If the turn fails or times out, the ticket remains safe and the human sees a specific error.

For one worker, use Herdr `agent wait` or `pane wait-output` as appropriate. The present timed supervisor scan can remain for multi-anchor harvesting in the first implementation; duplicate events must be suppressed before a looper prompt. Herdr socket event subscriptions are an optional later optimization if measured polling overhead or latency warrants a long-lived event client. They are not required to deliver bounded AGY turns.

## Attention policy

An attention mode controls model wakeups, human alerts, and ticket pauses. It is saved per project and changeable by a human during a session. A change governs subsequent events. A ticket already paused remains paused until explicitly resumed. Every mode preserves test gates and manual arbiter actions.

| Event | Quiet | Medium (default) | Loud, always stopped |
| --- | --- | --- | --- |
| Worker produces a valid GREEN verdict | Record it and show an arbiter-ready human notice; no looper turn. | One bounded looper turn summarizes the receipt and next step; the human still runs the arbiter. | Pause that ticket and notify the human before further work on it. |
| New unblocked ticket is available | Queue it; deterministic dispatch happens only if the human enabled that rule. | One bounded looper turn chooses a suitable available seat and records the assignment. | Pause that ticket until the human approves or chooses its seat. |
| Worker is blocked or gate is RED | Pause the affected ticket and alert the human; independent safe tickets may continue. | One bounded looper turn routes a diagnosis or states why human input is needed, with a strict retry ceiling. | Pause the affected ticket immediately and require a human decision. |

`loud` pauses the **ticket**, not the whole swarm. Global integrity failures such as corrupt shared state or an unsafe workspace target fail closed across affected operations regardless of attention mode. Quiet never hides blocked/RED events. Human alert delivery can follow existing Herdr notifications and durable logs; an unavailable client does not erase the receipt.

In `medium`, a clear unblocked ticket is dispatched immediately after the looper's proposed seat passes deterministic readiness, lease, and ownership checks. If a test gate is RED, the looper may route one repair request to the same isolated worker within the existing retry ceiling; a second RED or an ambiguous failure pauses the ticket for the human. A worker's `blocked` question pauses the affected ticket and reaches the human without automatic approval or speculative repair. This is the human-delegated recommendation selected on 2026-10-13.

## Arbiter and safety contract

The supervisor may gate and enqueue exact-SHA verdicts. Interactive startup, quick launch, and the default supervisor loop never invoke `arbiter drain` or `arbiter promote`. The looper cannot do either by prompt, shell, or cross-pane injection. At setup completion and when a queued result arrives, Stampede prints a concrete manual sequence: inspect `stampede status` and the gate receipt, run the installed arbiter's `drain` command from a plain human shell when ready, inspect its integration receipt, and run `promote --confirm` only after human review. A future explicit, separately enabled automation command may automate drain; it is not enabled by setup. Base-branch promotion stays human-only unless a separate existing authorization mechanism is deliberately invoked by the human.

Existing isolated worker worktrees, path leases, cold suite verification, review verdicts, and compare-and-swap integration remain authoritative. Herdr native worktree management may be evaluated later, but it does not replace Stampede's lease, gate, or salvage rules in this design.

## Visible state and leaving the session

The Ops area provides named non-model panes or tabs for worklog, troubleshooting, and handoff, each rendering a durable file in `.herdr-swarm/`. A log viewer consumes no model tokens. Herdr's built-in agent list remains the source for live agent presence and blocked/done status. Model choices and current attention mode are shown in `stampede status`.

Setup's final screen and the quick launch help distinguish:

- **Leave the terminal for now:** Herdr `ctrl+b q` detaches the client. Panes and agents keep running; closing only the detached terminal does not tear down the swarm.
- **Return:** run `herdr` to reattach, then `stampede status <repo>` to see ticket and arbiter state. The quick launcher should recognize an already seated project and avoid duplicate seating.
- **Stop work deliberately:** pause ticket dispatch, inspect pending work, then run `stampede down <repo>` after its confirmation. This closes Stampede-managed panes and may retire worker worktrees according to existing salvage rules. A snapshot is evidence, not a replacement for a live process or a guaranteed conversation restore.
- **After a Herdr server restart:** layout returns; eligible agent conversations resume only if Herdr's official integrations supplied native session references. The transient looper starts fresh from its checkpoint on the next wakeup.

## Delivery sequence and acceptance

Implement in the existing repository in small reviewable slices: (1) setup and role/model choices; (2) quick launch and lifecycle guidance; (3) non-model views and status; (4) attention policy and bounded looper; (5) remove interactive startup/supervisor automatic arbiter drain and update its documentation/tests. Preserve legacy configuration reading during migration; never rewrite an existing project automatically.

Acceptance requires a fresh Git repo without Stampede briefs to finish setup and launch; provider/model selections to appear unchanged in the seated processes; each mode's three event cases above to produce the documented prompt/alert/pause behavior; repeated events not to launch repeated AGY turns; looper output never to execute unvalidated shell; detach/reattach not to duplicate seats; deliberate down to preserve unrelated panes and dirty work; and no arbiter drain or promotion during setup or startup. Compare looper turns and output tokens per completed ticket against an observed baseline, alongside blocked/RED and human-intervention rates. Do not claim savings until that comparison is measured.

## Builder calls still open

The builder may choose the exact configuration keys, checkpoint schema, CLI wrappers, log viewer commands, cost-tier labels, and migration mechanics that best fit existing code. Those choices must preserve the visible behavior and safety boundaries above.
