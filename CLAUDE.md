# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Bash + Python orchestrator that seats a herd of LLM agents (`looper`, `arch`, `pm`, `agy-docs`, `agy-gh`) in
[Herdr](https://herdr.dev) terminal panes and supervises their work against **any** target repository. There is no build
step and no package manifest: the deliverables are `herdr-loop-swarm.sh` (launcher), `loop-bot-herd.sh` (supervisor
daemon), and the `lib/*.sh` libraries they source.

The code that runs here drives *other* repositories. `TARGET_DIR`/`$PWD` is the repo being worked on, which is usually
not this one.

## Commands

```bash
# Aggregate entry points (the Suite Gate resolves to `make test` here — #PROFILE-MAKE)
make check                              # lint + every suite, failure-propagating
make test                              # all suites under /bin/bash (bash 3.2 is the platform floor)
make lint                              # shellcheck 0-warning bar + bash -n + py_compile
# CI parity (DOG-18): `make check` IS the gate — reach for it first; ci-local only adds the pin-parity signal
scripts/ci-local.sh [--strict]          # runs make check (rc authoritative) + warns when local shellcheck != CI's pinned SC_VERSION (--strict: exit 1 on unproven parity)
# Suites — 21 as of this writing (CI-PARITY-1); re-verify with `ls tests/*.sh | wc -l`
# (each builds an ephemeral scratch git repo under /tmp and cleans up after itself.
#  Per-suite assertion counts are deliberately omitted — they drift fastest; the
#  suite's own summary line prints the live count.)
/bin/bash tests/test_arbiter.sh       # CAS integration, conflict abort, promote, string ticket ids
/bin/bash tests/test_async_gate.sh    # background gate jobs, reaping, invalidation, review-loop wiring
/bin/bash tests/test_briefs.sh        # brief delivery single-submission, --wait adoption, failure surfacing
/bin/bash tests/test_ci_local.sh      # ci-local make delegation + shellcheck pin-parity ladder
/bin/bash tests/test_cli.sh           # bin/stampede entrypoint dispatch and pass-through
/bin/bash tests/test_cli_doctor.sh    # `stampede doctor` end-to-end
/bin/bash tests/test_cli_init.sh      # `stampede init` acceptance
/bin/bash tests/test_cli_status.sh    # `stampede status --rich` session trust dashboard
/bin/bash tests/test_config.sh        # swarm.config.toml binding, enabled=false suppression, PROXY_* emission
/bin/bash tests/test_gh_sync.sh       # hermetic lib/gh_sync.sh suite, stubbed gh, zero network
/bin/bash tests/test_partition.sh     # owns parsing, overlap, leases
/bin/bash tests/test_profile.sh       # ecosystem/test-cmd detection incl. make/run_all
/bin/bash tests/test_providers.sh     # lib/providers.sh registry and fallbacks
/bin/bash tests/test_pyenv.sh         # tomllib interpreter resolver, PYTHON_BIN honouring
/bin/bash tests/test_quota.sh         # lib/quota.sh + `stampede quota` probing
/bin/bash tests/test_repo_state.sh    # scripts/repo-state.sh sections + gh degrade ladder
/bin/bash tests/test_review_loop.sh   # autonomous reviewer-loop state machine
/bin/bash tests/test_telemetry.sh     # telemetry envelope + round-trip
/bin/bash tests/test_worktree.sh      # provisioning, salvage, teardown

# Lint gate — tickets treat 0 warnings as the bar
shellcheck herdr-loop-swarm.sh loop-bot-herd.sh lib/*.sh
bash -n herdr-loop-swarm.sh              # syntax-only check
"$(bash lib/pyenv.sh)" -m py_compile lib/telemetry.py   # tomllib-capable interpreter (DOG-1)

# Launcher (safe, read-only subcommands first)
./herdr-loop-swarm.sh status [dir]                 # workspace, seats, profile, recent traces
./herdr-loop-swarm.sh verify [dir] [timeout_ms]    # every seat alive and brief-ready
./herdr-loop-swarm.sh up [dir] -m s                # seat-only: no task dispatch
./herdr-loop-swarm.sh down [dir] [-y] [--keep-ws]  # selective teardown (destructive)

# One-call repo state (read-only) — prefer this over ad-hoc git log/gh probe sequences (DOG-17)
scripts/repo-state.sh [dir]                        # branch, last 10 commits, merged-to-main branches, best-effort CI, dirty tree

# Unattended batch (HEADLESS-6) — backlog tickets in/out, no Herdr panes; reviewer loop off in batch mode
bin/stampede headless [dir] [--max-tickets N] [--timeout M]   # dispatch→gate→enqueue per ticket; dead-letter + non-zero exit on failures

# Supervisor daemon
./loop-bot-herd.sh status          # control flags, verdict count, channel files
./loop-bot-herd.sh once            # one pass: health, verdict harvest, suite gate
./loop-bot-herd.sh watch           # poll loop
./loop-bot-herd.sh gate-on|gate-off|pause|resume|drain-on|drain-off

# Individual library entry points (each is also a CLI)
bash lib/preflight.sh              # 9-point dependency matrix
bash lib/config.sh dump <slug>     # TOML → shell exports
bash lib/profile.sh ensure <dir> 0          # fail-closed profile resolution (exits 1 when unresolvable)
bash lib/profile.sh is-runnable "<test cmd>" # rejects "", none, true
bash lib/worktree.sh provision <seat> <slug> [base] [dir]   # WORKTREE_ADOPT_BRANCHES=1 to adopt a stale branch
bash lib/arbiter.sh enqueue <ticket> <seat> <sha> | drain | promote [--pr] | pr-body <file>
bash lib/partition.sh check <ticket.md> [repo] | lease acquire|release|list|reconcile | suggest <base> <branch> [repo]
bash lib/gh_sync.sh --dry-run            # ticket ↔ GitHub issue reconciliation (--apply to write)
python3 lib/telemetry.py log <session> <event> <agent> <ticket> '<json>' --trace-dir <dir>
python3 lib/telemetry.py stream <session> <trace-dir>
```

No suite has a per-test filter. To exercise one function, source the lib in a scratch repo yourself (that is what the
suites do) rather than narrowing the file.

## Architecture

**Config → environment → launcher.** `swarm.config.toml` is the single source of seat truth. `lib/config.sh` parses it
with Python `tomllib` and emits `shlex.quote`d `export SEAT_*_<key>` lines that the launcher `eval`s. Slug and paths
travel as `sys.argv`, never interpolated into Python source. Adding or removing a seat should be a TOML edit only —
never hardcode a seat name in shell.

**Profile is fail-closed.** `lib/profile.sh` detects `REPO`, `TEST_CMD`, `ECOSYSTEM`, `DOCS_DIR` from the target repo
and caches them in `<target>/.herdr-swarm/profile.env`. With no GitHub remote or no detectable test runner it returns
non-zero and the launcher aborts *before* any workspace mutation. `test_cmd_is_runnable` rejects `""`, `none` and
`true`: a synthetic gate would green-light everything, which is the failure mode the whole design exists to prevent.

**Seating order matters.** `herdr agent start` has **no `--cwd`**; an agent inherits the cwd of the pane it starts in,
and a pane's cwd is fixed at `herdr pane split --cwd`. So for an isolated seat the order is
`worktree_provision` → `split_pane` (with the worktree as cwd) → `agent start` → ledger entry. Herdr commands route by
explicit workspace-prefixed IDs (`wM:p5`); `pane split --current` resolves to the human's foreground pane and can land
in the wrong workspace — never use it in scripts.

**Two kinds of seat.** Root anchors (`looper`, `pm`, telemetry) live in the target repo root on its base branch.
Isolated seats (`worktree = true` in TOML — today `arch_1` and `arch_2`) get `.herdr-swarm/worktrees/<seat>` on
`swarm/<slug>/<seat>`, sharing the one object store. More concurrent workers means another `[seats.arch_N]` table, not
new shell. Agent names are global across Herdr workspaces, so every seat is namespaced `<seat>-<slug>` via `slugify()`
in `lib/common.sh` (`^[a-z][a-z0-9_-]*$`).

**Seat ledger.** `<target>/.herdr-swarm/seats.json` records each seat's pane, `worktree_dir`, `branch` and `isolated`
flag. It is what makes teardown selective: `swarm_down` closes only recorded panes, resolves the workspace by strict
physical-cwd match (never by `$HERDR_WORKSPACE_ID` alone, never by basename label), and asks before closing anything.

**Completion protocol.** Workers emit one anchored line, `ARCH DONE #<ticket> <sha>`. The supervisor harvests it,
verifies the sha exists, runs `TEST_CMD` itself, and records the outcome in `.herdr-swarm/session-verdicts.jsonl`,
deduping on `(ticket, sha)` so a RED ticket can be re-verdicted at a new sha. Only a green gate retires a ticket; a
skipped or unverifiable verdict escalates to the human and must not be reported to `looper` as done. Never accept an
agent's own claim that tests passed.

**Integration pipeline.** A green verdict is enqueued to `lib/arbiter.sh` (`.herdr-swarm/integration.jsonl`). `drain`
holds one lock, merges the **gated sha** (not the branch tip) onto `swarm/<slug>/integration` in its own detached
worktree, runs the suite on the *combined* result, and only then advances the ref with a compare-and-swap
(`update-ref <ref> <new> <expected-old>`). A plain `update-ref` silently loses concurrent updates; CAS rejects the
losers loudly. Conflicts are aborted and handed back to the worker — the arbiter never resolves them, never rebases a
seat branch, and never writes the base branch. `main` moves only by human `promote`: `merge --ff-only` **run inside the
root worktree**, or a PR. Moving a checked-out branch from outside its worktree leaves that checkout staging a reversal.

**Partition and leases.** `lib/partition.sh` reads a comma-separated `owns:` line from a ticket's frontmatter (the
frontmatter parser is line-based, so a YAML list would silently vanish) and refuses to co-dispatch tickets whose paths
overlap. A lease in `.herdr-swarm/leases.json` is held until the ticket **integrates**, not until its verdict is green —
releasing at green would let the next worker branch from a base missing that work.

**Libraries land before their callers.** Several libs ship and are unit-tested a milestone before anything calls them
(`partition.sh` today; `arbiter.sh` until recently). Before assuming a behaviour is live, grep for a caller in
`herdr-loop-swarm.sh` / `loop-bot-herd.sh` — a passing suite does not mean the herd uses it.

**Briefs travel as file paths.** `briefs/*.in.md` are templates rendered with project variables into
`.herdr-swarm/briefs/` and delivered as a short path plus a nonce reply file. Piping brief text into
`herdr agent prompt` saturates the PTY and silently truncates instructions.

**Telemetry.** `lib/telemetry.py` writes JSONL events to `.herdr-swarm/traces/` and streams them as one-line ANSI
badges in the Ops anchor pane.

## Working conventions

- **Documents are part of the work.** Decisions become ADRs in `docs/adr/`; plans live in `maps/universal-herdr-swarm.md`
  with one file per ticket in `maps/tickets/` (frontmatter `id`/`status`/`github_issue` drives `lib/gh_sync.sh`, and
  `owns:` drives partition checking — one comma-separated line, never a YAML list);
  `STATE.md` is the resumable checkpoint; `CONTEXT.md` defines the vocabulary and its `_Avoid_` lines; PM reviews land in
  `docs/audits/`. Read `CONTEXT.md` before naming anything new.
- **Claims need receipts.** Tickets carry an explicit Verification Step, and findings quote the command output that
  proves them. Probe git semantics in a scratch repo rather than asserting them.
- **Git safety rules this repo has paid for:** never `git stash` (the stash stack is shared across worktrees — use a WIP
  commit); never `git worktree remove --force` (git's refusal on a dirty tree is the safety net); never move a branch
  that is checked out somewhere (`update-ref` succeeds silently and leaves that checkout staging a reversal); never
  push or merge to a base branch without explicit human approval.
- Changes land as conventional commits referencing the ticket, e.g. `feat: … (#P2-1)`.

## Foreign agent configs

An OpenAI Codex config (`~/.codex/config.toml`) and a Gemini CLI config (`~/.gemini/settings.json`) exist on this
machine. To pull their MCP servers, slash commands, subagents or instructions into Claude Code, reply `/import` to scan
and list what's importable, then `/import --yes=<digest>` with the digest that scan prints. If `/import` isn't available
on this surface, run `claude import` from a terminal.
