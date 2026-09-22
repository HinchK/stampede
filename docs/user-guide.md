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

## 10. Watch the room

- `bin/stampede status <dir>` — workspace, seats, profile, recent events.
- The Ops pane — live one-line telemetry (dispatches, verdicts, gates).
- `bin/stampede down <dir> --yes` — selective teardown: closes only
  panes the swarm opened, salvages anything dirty, prunes worktrees.

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

## Where to go next

- [README](../README.md) — architecture, the zero-trust thesis, ADR index
- [`examples/demo-repo`](../examples/demo-repo/README.md) — the walkthrough
- [CONTRIBUTING](../CONTRIBUTING.md) — the four git safety rules, commit style
- [CONTEXT.md](../CONTEXT.md) — the system's vocabulary and its _Avoid_ lines
