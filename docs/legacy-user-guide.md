# Stampede User Guide

Zero to your first **verified green verdict**. This guide assumes nothing
except a stock macOS or Linux machine and **one** agent CLI. You never
need more than one — but everything here works with several different
providers seated side by side.

> Looking for the architecture and the reasoning? That's the
> [README](../README.md). This page is the journey.

---

## What you are about to run

Stampede seats agent CLIs (Claude Code, OpenCode, AGY, a local engine —
any mix) in terminal panes and supervises them against a repository you
choose. Workers claim tickets, implement in isolated git worktrees, and
emit a one-line completion verdict. An independent supervisor re-runs
**your real test suite** on the exact commit before believing them, and
an arbiter re-tests combined results before anything integrates. Only
you move `main`.

```
you ──► seats workers ──► workers claim tickets in worktrees
        supervisor re-runs your suite on the exact commit (Suite Gate)
        arbiter merges green shas, re-tests the combination
you ◄── promote (the only hand on main)
```

Time budget: about 15 minutes from clone to first verdict.

## 1. Prerequisites

| Need | Check | If missing |
|---|---|---|
| bash ≥ 3.2 | `bash --version` | stock on macOS/Linux |
| git, jq | `git --version && jq --version` | `brew install git jq` or your package manager |
| Python ≥ 3.11 | `python3 -c 'import tomllib'` | `brew install python@3.12` |
| timeout(1) | `timeout 1 true` | `brew install coreutils` (macOS) |
| [Herdr](https://herdr.dev) | `herdr workspace list` | `curl -fsSL https://herdr.dev/install.sh \| sh` |
| GitHub CLI, logged in | `gh auth status` | `brew install gh && gh auth login` |
| **one** agent CLI | see below | install any one |

Agent CLIs — any **one** is enough:

- **Claude Code** — `npm install -g @anthropic-ai/claude-code`
- **OpenCode** — `curl -fsSL https://opencode.ai/install | bash`
- **AGY** — see its vendor docs

Which seats you can run depends on which CLIs you have; the next step
tells you exactly.

## 2. Clone and prove the tool itself is green

```bash
git clone https://github.com/HinchK/stampede "$HOME/stampede" && cd "$HOME/stampede"
make check
```

Every suite green, zero lint warnings. A supervisor you can't verify has
no business verifying anything else.

## 3. Doctor: what can run on this machine

```bash
bin/stampede doctor
```

One row per seat in `swarm.config.toml`: `OK` (provider found), `MISSING`
(with an install pointer), or `SKIP` (seat disabled in config — never
your problem). Then the standing dependency matrix: herdr daemon, jq,
git, tomllib-capable Python, timeout(1), gh auth.

Exit code is scriptable: `0` when every **enabled** seat's provider is
usable, `1` otherwise. Fix the reds before seating — the launcher will
fail closed on the same problems, but doctor's table is faster to read.

## 4. Configure your seats

Seats are declared in
[`swarm.config.toml`](../swarm.config.toml). Each seat: a CLI `kind`, a
`brief` (its standing instructions), a pane position, and optionally
`worktree = true` for isolated implementation seats.

Minimal working setup for a single Claude Code install:

```toml
[seats.looper]
name = "looper"
role = "Orchestrator"
default_kind = "claude"
brief = "briefs/looper.md"
tab = "herd"
position = "bottom-full"

[seats.arch_1]
name = "arch-1"
role = "Implementation Engine"
default_kind = "claude"
brief = "briefs/arch.md"
tab = "herd"
position = "top-right"
worktree = true
```

With two providers, give different seats different kinds — e.g.
`arch_1` on `opencode`, `pm` on `claude`. Short on patience for
hand-editing? `stampede init` generates this file from the providers
actually installed (`stampede init --non-interactive --preset minimal`).

## 5. First run, on the demo repo

Do your first loop against
[`examples/demo-repo`](../examples/demo-repo) — one tiny library, one
real test suite, three disjoint tickets. Its
[README](../examples/demo-repo/README.md) is the script: copy it out,
`git init`, add a placeholder remote (nothing is ever pushed), then:

```bash
"$HOME/stampede/bin/stampede" up /tmp/demo -m s   # seat only, no dispatch
"$HOME/stampede/bin/stampede" verify /tmp/demo    # every seat brief-ready
```

## 6. Dispatch your first ticket

From `/tmp/demo`, prompt a worker seat with the ticket path (one short
line — briefs travel as file paths in this system, never pasted walls of
text):

```
Work ticket maps/tickets/demo-1-calc-pow.md in this repo, on a branch.
```

The worker implements, commits, and prints its verdict line:

```
ARCH DONE #DEMO-1 <commit-sha>
```

## 7. Read the verdict — trust this, not the chat

The supervisor harvests that line, verifies the sha exists, and re-runs
`make test` itself on the worker's tree:

```bash
cat /tmp/demo/.herdr-swarm/session-verdicts.jsonl
```

- **GREEN** — the suite passed at that sha. Only this retires a ticket.
- **RED** — it failed. The ticket stays open; the worker fixes and
  re-emits `ARCH DONE #<ticket> <new-sha>`. A new sha is a new verdict.
- **SKIPPED/unverifiable** — escalated to you, never reported as done.

A worker saying "tests pass" is not data. The JSONL line is data.

## 8. Integrate (and the one human-only step)

```bash
"$HOME/stampede/lib/arbiter.sh" drain      # merges gated shas, re-tests combined result
"$HOME/stampede/lib/arbiter.sh" promote    # fast-forwards main — asks for --confirm
```

`drain` never resolves conflicts (they bounce back to the worker) and
never writes your base branch. `promote` is yours: it refuses to run
without `--confirm`, because the human is the only hand on `main`.

## 9. Cross-provider review (optional lane)

With two or more providers installed, you can seat a **reviewer** on a
*different* provider than your implementer — different vendors' models
have different blind spots biases, so a second pair of eyes from another
provider catches what the first rationalizes past. It is one config flip:

```toml
[seats.reviewer]
name = "reviewer"
role = "Review Specialist"
default_kind = "agy"          # any kind DIFFERENT from your implementer
brief = "briefs/reviewer.md"
tab = "ops"
position = "top-right"
```

Your implementer seats might be `kinds = ["opencode", "claude"]`; seating
the reviewer on `agy` (or any other kind) is the whole trick. Then
`stampede up <dir> -m s` seats it like any other seat.

What the reviewer does: audits the **gated sha** — the exact commit the
supervisor's Suite Gate already tested — before you promote. Tests
first, then the diff, findings cited `file:line` with remediations. It
finishes with an advisory anchor line:

```
REVIEW DONE #<ticket> <sha>
```

What it never does — and this is the important part:

- **It never merges.** Promote stays yours, `--confirm` and all.
- **It never gates.** Review is advisory input to *your* promote
  decision. The Suite Gate remains the only thing that retires a ticket;
  a `REVIEW DONE` line retires nothing, and a reviewer PASS is not a
  test result. If review and gate disagree, believe the gate.
- It works read-only (`git show`/`git diff` on the gated sha — never
  `git checkout` in the shared root). Need a reviewer with its own tree?
  Add `worktree = true` to its seat.

Read the review before you run `arbiter.sh promote --confirm`; treat a
BLOCK as "ask the implementer seat to fix and re-verdict first".

### The multi-turn critique loop (`[reviewer] loop = true`)

Flipping `[reviewer] loop = true` (with `max_rounds`, default 2) turns
the single-shot review into a bounded refinement loop. One round:

1. The reviewer audits the implementer's gated sha and writes durable
   findings to `.herdr-swarm/reviews/<ticket>-<sha>.md`, then emits
   `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>`.
2. A `BLOCK` routes back to the implementer as a critique dispatch:
   `DISPATCH CRITIQUE: #<ticket> round <N>/<MAX> — see <path>`.
3. The implementer reads the findings file, refines **on its existing
   in-flight branch** (never a reset, never a rebase-away, never
   reverting unrelated work — the gated-sha lineage is the evidence
   trail), runs the suite locally, commits
   `fix: address reviewer critique for #<ticket> (round N)`, and
   re-emits `ARCH DONE #<ticket> <new-sha>`.
4. The new sha re-enters the pipeline from the top: supervisor gate,
   then (loop still on) a fresh review round at the new sha.

Each round's findings file is a separate durable artifact — the audit
trail of what was found and what changed because of it. The loop is
bounded: after `max_rounds`, a still-standing BLOCK comes to you as an
honest standoff instead of an infinite polish ping-pong.

Two things the loop still never does: the review never replaces the
Suite Gate (a PASS verdict is not a test result; the gate re-runs at
every new sha regardless), and the reviewer never merges — promote
remains yours. If implementer and reviewer disagree at the budget,
you read the findings files and rule.

## 10. Watch the room

- `bin/stampede status <dir>` — workspace, seats, profile, recent events.
- The Ops pane — live one-line telemetry (dispatches, verdicts, gates).
- `bin/stampede down <dir> --yes` — selective teardown: closes only
  panes the swarm opened, salvages anything dirty, prunes worktrees.

## 11. Headless batch mode (unattended queue drain)

When you have a backlog of pre-scoped tickets with declared `owns:` paths and want to drain them without babysitting terminal panes or keeping a display open, reach for **headless batch mode**:

```bash
bin/stampede headless /path/to/repo [--max-tickets N] [--timeout M]
```

### When to reach for it
- **Unattended / Overnight runs**: Drain an unblocked ticket queue in the background without needing terminal multiplexer (`herdr`) panes or manual prompt dispatch.
- **CI/CD pipelines & remote boxes**: Runs cleanly in headless Linux containers or GitHub Actions runners where no display server, GUI, or interactive multiplexer exists.
- **Strictly disjoint batches**: Safely runs batch jobs knowing the partition manager will refuse and bypass tickets with conflicting or held file leases.

### How it works: a worked example

Suppose `/tmp/demo` has three backlog tickets (`DEMO-1`, `DEMO-2`, `DEMO-3`) in `maps/tickets/`:

```bash
# Drain up to 3 tickets, with a 20-minute batch timeout ceiling
bin/stampede headless /tmp/demo --max-tickets 3 --timeout 1200
```

Under the hood, `stampede headless` executes an automated pipeline per ticket:
1. **Intake & Partition Check**: Scans `maps/tickets/` for `status: backlog` or `status: queued`. Verifies that the ticket's `owns:` declaration does not overlap with any active ticket or existing lease in `.herdr-swarm/leases/`.
2. **Ephemeral Worktree Provisioning**: Creates an isolated worktree at `.herdr-swarm/worktrees/<seat>` rooted on a fresh branch `swarm/<slug>/<seat>`.
3. **Subprocess Dispatch**: Spawns the vendor CLI directly as a background subprocess (no Herdr pane). Delivers the ticket brief via argv pointer (`.herdr-swarm/state/channel/<seat>-brief.md`).
4. **Suite Gate & In-Batch Critique**: Once the worker commits and emits `ARCH DONE #<ticket> <sha>`, the supervisor runs your real test suite. If the test fails (`RED`), headless mode feeds the error back to the worker in an automated critique turn (up to `max_verdict_attempts`, default 2).
5. **CAS Arbiter Drain**: When the suite passes (`GREEN`), the arbiter acquires `.arbiter-drain.lock`, compare-and-swap merges the commit into `swarm/<slug>/integration`, releases the partition lease, and advances to the next ticket.

### Command flags and configuration

| Flag / Option | Default | Description |
|---|---|---|
| `[dir]` | `$PWD` | Target repository path |
| `--max-tickets N` | `5` | Stop after draining $N$ tickets, even if more remain in the queue |
| `--timeout M` | `1800` (30 min) | Whole-batch wall-clock timeout in seconds (POSIX exit code `124` or `3`) |
| `--mode M` | `sequential` | Queue processing strategy |

Environment variable overrides (`emit_env_wins`) take precedence over `swarm.config.toml`:
- `CONFIG_HEADLESS_MAX_ATTEMPTS`: Re-verdict retry ceiling before dead-lettering (default: `2`).
- `CONFIG_HEADLESS_WORKER_TIMEOUT_S`: Per-worker wall-clock timeout in seconds (default: `900`).
- `HL_KILL_GRACE_S`: Grace period between SIGTERM and SIGKILL escalation (default: `5`).

### Exit codes (fail-closed CI contract)

The command exits with deterministic status codes so automated pipelines can halt or alert immediately:
- **`0`**: Success. All eligible tickets were drained green, or the backlog was already empty.
- **`1`**: Dead-letter / failure. At least one ticket failed tests beyond the retry budget, crashed, or hit an unresolvable error.
- **`3` / `124`**: Batch timeout. The whole-batch `--timeout` expired before completion.

### Dead-letter handling & diagnostics

When a worker crashes, tests remain red past the retry budget, or a ticket cannot be verified, `stampede headless` **never swallows the error**:
1. The ticket's partition lease is released so other tasks are not starved.
2. A structured incident record is appended to `.herdr-swarm/dead-letter.jsonl`:
   ```json
   {"ticket":"DEMO-1","seat":"arch-1","reason":"worker exited rc=1 without a verdict — worker log: /tmp/demo/.herdr-swarm/logs/arch-1.log","timestamp":1727730000}
   ```
3. A human-readable alert is written to `.herdr-swarm/headless-notices.log` and printed to stderr.
4. The exact failure reason and path to the raw vendor output log (`.herdr-swarm/logs/<seat>.log`) are displayed, allowing immediate root-cause inspection.

### Target repository requirements

Before running headless batch mode against a target repository, ensure three operational prerequisites are met:

1. **Model Pinning in Vendor Config**:
   Workers running in headless mode must not inherit stale global defaults. In `.opencode/opencode.json` (or your provider's config), explicitly pin a valid model:
   ```json
   {
     "$schema": "https://opencode.ai/config.json",
     "model": "zai-coding-plan/glm-5.2"
   }
   ```
2. **Sandbox External Directory Permissions**:
   Because workers run inside isolated worktrees (`.herdr-swarm/worktrees/<seat>`), but read ticket briefs and write channels in the root repository (`maps/tickets/`), sandbox permissions must allow external directory access:
   ```json
   {
     "permission": {
       "bash": "allow",
       "edit": "allow",
       "write": "allow",
       "external_directory": "allow"
     }
   }
   ```
   *(Note: OpenCode ≥ 1.18 requires `"allow"` \| `"ask"` \| `"deny"`; older wildcard strings like `"*"` cause config syntax errors).*
3. **Ignore the Swarm State Directory**:
   Add `.herdr-swarm/` to the target repository's `.gitignore`. The supervisor's suite gate checks for untracked files (`gate_tree_matches`); if runtime state files are untracked, every verdict will be rejected as tree drift (`stale`).

## Troubleshooting (every failure is fail-closed on purpose)

| Symptom | Cause | Fix |
|---|---|---|
| `preflight: herdr binary not on PATH` | Herdr missing | `curl -fsSL https://herdr.dev/install.sh \| sh` |
| `no tomllib-capable interpreter` | Python < 3.11 | `brew install python@3.12` or `export PYTHON_BIN=...` |
| `no runnable timeout(1)` | macOS coreutils | `brew install coreutils` or `export TIMEOUT_BIN=...` |
| doctor row `MISSING` | that seat's CLI absent | install per the row's pointer, or disable the seat |
| launcher aborts before seating | profile fail-closed (no remote / no test runner) | add remote or set `REPO`/`TEST_CMD` in `<target>/.herdr-swarm/profile.env` |
| `verify` times out | agent still booting | re-run with a bigger timeout: `verify <dir> 60000` |
| nothing integrates after a GREEN | arbiter is operator-invoked | run `lib/arbiter.sh drain` |
| `promote` refuses | by design | read the prompt, then `--confirm` if you mean it |
| headless worker dies in ~2s (`ProviderModelNotFoundError`) | target repo lacks model pin | set `"model"` in target repo `.opencode/opencode.json` |
| headless worker fails (`auto-rejecting external_directory`) | sandbox rejects reading root `maps/tickets/` | set `"permission": {"external_directory": "allow"}` in `.opencode/opencode.json` |
| headless tickets rejected as `stale` tree drift | `.herdr-swarm/` untracked | add `.herdr-swarm/` to target repo `.gitignore` |

## Where to go next

- [README](../README.md) — architecture, the zero-trust thesis, ADR index
- [`examples/demo-repo`](../examples/demo-repo/README.md) — the walkthrough
- [CONTRIBUTING](../CONTRIBUTING.md) — the four git safety rules, commit style
- [CONTEXT.md](../CONTEXT.md) — the system's vocabulary and its _Avoid_ lines
