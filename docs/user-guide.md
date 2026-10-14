# Stampede user guide

Stampede builds a small frontier-model team around a Git repository. Herdr
owns the terminal panes and session. Stampede owns ticket dispatch, the
exact-commit test gate, and the integration queue. You choose the models and
run the arbiter yourself.

## Set up a repository

Install Herdr, Git, `jq`, a Python with `tomllib`, `timeout(1)`, GitHub CLI,
and the harnesses you want to use. AGY is required for the looper in this
release. Claude and OpenCode are recommended for the initial PM and architect
seats; setup can assign installed frontier harnesses to those roles instead.
Local model detection is deferred.
The target Git repository needs an initial commit so isolated seats can branch
from `HEAD`.

```bash
/path/to/stampede/bin/stampede setup /path/to/your/repo
```

Setup checks the installed harnesses and current AGY/OpenCode model lists,
then recommends a low-cost AGY Flash looper, Claude Sonnet PM, AGY Flash
GitHub and docs seats, two OpenCode GLM-5.3 architects, and a cheap helper.
You can change each provider and model, the PM and architect counts, and the
attention mode. `medium` is the default. The generated configuration is
`<repo>/swarm.config.toml`. Setup asks where to save `yeehaw.sh`; it does not
start agents or run the arbiter. Running setup again keeps an existing complete
setup; editing it makes `.bak` copies before replacement.

The launcher reads the repository's configuration. Standing briefs are
rendered from Stampede's installed templates, so the target repository does
not need its own `briefs/` directory. All model seats in a new setup use
isolated worktrees; only the human moves the base branch.

## Launch

Use the path chosen during setup:

```bash
/path/to/yeehaw.sh start --brainstorm --topic "a focused product question"
/path/to/yeehaw.sh start --wayfinder --topic "a milestone"
/path/to/yeehaw.sh start --seat-only
```

The first launch builds the Herdr layout, seats the chosen model agents,
starts the supervisor, and opens model-free worklog, troubleshooting, and
handoff panes in Ops. The looper pane displays the durable worklog. Each
needed looper decision uses one fresh, bounded AGY call; the CLI's token
usage is recorded in `.herdr-swarm/looper-usage.jsonl`. A repeated launch
reuses managed panes and live seats.
`--seat-only` keeps automatic issue intake idle; a later brainstorm or
wayfinder launch enables it.

The launch checks the project's test command. If Stampede cannot identify a
runnable suite, supply one when prompted; a gate cannot be trusted without
it. Run `stampede status <repo>` to see the configured roster, attention mode,
live Herdr agents, and recent activity.

## Choose how much attention Stampede uses

```bash
stampede attention /path/to/your/repo
stampede attention /path/to/your/repo quiet
stampede attention /path/to/your/repo medium
stampede attention /path/to/your/repo loud
stampede attention /path/to/your/repo resume TICKET
```

| Event | Quiet | Medium (default) | Loud, always stopped |
| --- | --- | --- | --- |
| GREEN gate | Log and notify; you run arbiter | One short AGY summary; you run arbiter | Pause that ticket for your review |
| New `loop:ready` issue | Queue it | AGY chooses a ready architect; Stampede checks the seat and lease before dispatch | Pause that ticket |
| RED gate | Pause and alert | One AGY diagnosis and at most one repair to the same isolated worker | Pause and alert |
| Blocked question | Pause and alert | Pause and alert | Pause and alert |

A pause affects one ticket; independent safe work can continue. A second RED
pauses the ticket in medium. In quiet, the existing supervisor's `drain-on`
command explicitly enables deterministic ticket intake without AGY turns;
this is **ticket dispatch**, not arbiter drain. Ticket state and decisions
stay in `.herdr-swarm/attention.json`, `worklog.log`,
`troubleshooting.log`, and `handoff.log`.

For quiet ticket intake, run `REPO_DIR=/path/to/your/repo bash
/path/to/stampede/loop-bot-herd.sh drain-on`; run `drain-off` with the same
prefix to stop intake. These commands only control new issue dispatch. The
arbiter remains manual.

## Inspect and run the arbiter manually

Workers report `ARCH DONE #<ticket> <commit-sha>`. The supervisor re-runs the
project suite on that exact commit. GREEN candidates enter the integration
queue; startup and the ordinary supervisor loop leave them there. The
project-bound command below reads the target's profile and refuses to run
without a runnable test command.

```bash
stampede arbiter /path/to/your/repo init-ref       # once, after first launch
stampede status /path/to/your/repo
stampede arbiter /path/to/your/repo drain          # only after inspecting GREEN evidence
stampede status /path/to/your/repo
stampede arbiter /path/to/your/repo promote --confirm  # only after human review
```

`drain` re-tests the combined result and advances an integration ref. It does
not move the base branch. `promote --confirm` is the deliberate human step
that moves it. Run these from a plain shell, not an agent pane. The explicit
headless batch mode retains its own in-batch drain behavior when you choose
that separate command.

## Leave, return, or stop

- **Leave for now:** press `ctrl+b q` in Herdr to detach. The server keeps
  panes and agents running; close the terminal after detaching.
- **Return:** run `herdr`, then `stampede status /path/to/your/repo`.
  Running the quick launcher again reuses the existing managed seats.
- **Stop deliberately:** inspect pending work, then run
  `stampede down /path/to/your/repo`. It confirms, snapshots ledgers and
  available transcript tails, closes Stampede-managed panes, and preserves
  unrelated operator panes. Isolated worker worktrees follow the existing
  checkpoint and salvage rules.

After a Herdr server restart, eligible native agent conversations resume only
if current Herdr integrations supplied session references. Check them with
`herdr integration status`. The transient looper always starts fresh from
durable state on its next event. A teardown snapshot records evidence; it is
not a live conversation restore.

For the older `stampede init` flow and its historical seat layout, see the
[legacy user guide](legacy-user-guide.md).
