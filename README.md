# Stampede

Stampede sets up a small, cost-fitted frontier model team around a Git
repository. Herdr keeps the terminal workspace and agents running. Stampede
handles ticket dispatch, independent tests on exact commits, and an integration
queue that only a human advances.

## First run

The target must be a Git repository with an initial commit. Install Herdr,
Git, GitHub CLI, `jq`, Python with `tomllib`, and the harnesses you want to
use. AGY is required for the looper in this release.

```bash
/path/to/stampede/bin/stampede setup /path/to/repo
/path/you/chose/yeehaw.sh start --brainstorm --topic "your topic"
/path/to/stampede/bin/stampede status /path/to/repo
```

Setup checks installed harnesses and available model lists, recommends a
model for each role, then lets you choose. It writes project-local
`swarm.config.toml` and asks where to save `yeehaw.sh`. Setup does not launch
agents or run the arbiter. Local models are deferred to a future release.

| Role | Starting recommendation | Default count |
| --- | --- | ---: |
| Looper | AGY Flash Low, one bounded decision at a time | 1 |
| Project manager | Claude Sonnet | 1, scalable |
| GitHub runner | AGY Flash Low | 1 |
| Documentation | AGY Flash Low | 1 |
| Coding architect | OpenCode GLM-5.3 | 2, scalable |
| Helper | AGY Flash Low | 1 |

Every standing model seat uses an isolated Git worktree. The looper pane and
Ops worklog, troubleshooting, and handoff panes run without persistent model
sessions. One fresh AGY call handles each needed looper decision; its usage
is recorded in `.herdr-swarm/looper-usage.jsonl`.

## Attention and human gates

`medium` is the default attention level: Stampede can assign a ready issue,
summarize a GREEN verdict, and request one same-worker repair after RED. The
`quiet` and `loud` settings let you reduce autonomous work or stop at each
decision. Blocked questions always pause their ticket. Change the setting
with `stampede attention /path/to/repo quiet|medium|loud`.

Workers never approve their own output. The supervisor runs the project's
test command on the exact worker commit. A GREEN verdict enters the
integration queue. **Startup does not drain the arbiter.** From a plain human
shell, inspect the evidence and run:

```bash
stampede arbiter /path/to/repo init-ref          # once, after first launch
stampede status /path/to/repo
stampede arbiter /path/to/repo drain             # re-test the combined tree
stampede arbiter /path/to/repo promote --confirm # only after human review
```

`drain` advances a separate integration ref. Only the explicit promotion
step moves the base branch.

## Leave and return

In Herdr, press `ctrl+b q` to detach while the session keeps running. Reopen
Herdr and run `stampede status /path/to/repo` to return. Reusing the launcher
reattaches to managed panes. To end the swarm deliberately, inspect pending
work and run `stampede down /path/to/repo`.

The [user guide](docs/user-guide.md) covers setup, attention behavior,
arbiter commands, and state handling. The [legacy README](LEGACY.md) and
[legacy user guide](docs/legacy-user-guide.md) preserve the previous layout
and `stampede init` flow.
