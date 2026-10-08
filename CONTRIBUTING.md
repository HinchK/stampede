# Contributing to Stampede

Stampede is a Bash + Python orchestrator. There is no build step and no package
manifest — the deliverables are the shell scripts at the repo root and the
libraries in `lib/`. That makes the contribution loop short: install a handful
of tools, run one command, and you have the same verdict the supervisor would
give you.

## Prerequisites

You do **not** need Herdr or any agent CLI to contribute. The test suites
are hermetic: each builds an ephemeral scratch repository under `/tmp`, stubs
`herdr`, `agy` and `opencode`, and cleans up after itself. No secrets, no
network, no model calls.

What you do need:

| Tool | Why |
| --- | --- |
| `git` | Everything. |
| `jq` | The supervisor parses verdicts with it; several suites exercise that path. |
| `shellcheck` | The lint gate. |
| Python **>= 3.11** | `tomllib` — the seat registry parser. |

**Python >= 3.11 is a hard floor, and it is the one prerequisite that bites.**
`swarm.config.toml` is parsed with the standard-library `tomllib` module, which
landed in Python 3.11, while macOS still ships `/usr/bin/python3` as 3.9. A bare
`python3` is therefore not a safe assumption, and `lib/pyenv.sh` exists to
resolve a capable interpreter rather than guess:

```bash
bash lib/pyenv.sh            # prints the interpreter it resolved
```

If it cannot find one it fails loudly with a remedy. Either install a newer
interpreter (`brew install python@3.12`) or point the resolver at one you
already have:

```bash
export PYTHON_BIN=/path/to/python3.11+
```

An explicit `PYTHON_BIN` is honoured strictly — if it cannot import `tomllib`,
the resolver errors instead of silently falling back. That is deliberate.

`gh` is not needed for `make check`. It is used by `lib/gh_sync.sh` (ticket ↔
GitHub issue reconciliation), and the preflight matrix checks both `gh` and
`gh auth status` fail-closed before any workspace mutation — so you need it
authenticated to actually run a swarm, not to contribute a change.

## The one command

```bash
make check
```

That is the gate. It is `make lint` followed by `make test`, failures propagate,
and it is the same command the supervisor's Suite Gate runs against your commit
before any verdict is recorded (`Makefile`; `lib/profile.sh` resolves `TEST_CMD`
to `make test` for this repo). Run it before you open a pull request — a green
local gate and a green verdict are the same event.

Two halves, if you need to narrow down a failure:

```bash
make lint    # shellcheck + bash -n + py_compile
make test    # every suite under tests/
```

**0 shellcheck warnings is the bar.** Not "no errors" — zero warnings, across
`herdr-loop-swarm.sh`, `loop-bot-herd.sh` and every `lib/*.sh`. If a warning is
genuinely wrong for the case at hand, silence it with a narrowly scoped
`# shellcheck disable=SCxxxx` directive and a comment saying why, rather than
widening the bar.

Individual suites, run directly:

```bash
/bin/bash tests/test_worktree.sh     # provisioning, salvage, teardown
/bin/bash tests/test_arbiter.sh      # CAS integration, conflict, promote
/bin/bash tests/test_partition.sh    # owns parsing, overlap, leases
/bin/bash tests/test_async_gate.sh   # background gate jobs, reaping
/bin/bash tests/test_briefs.sh       # brief delivery single-submission (HERDR-4)
/bin/bash tests/test_profile.sh      # ecosystem / test-cmd detection
/bin/bash tests/test_pyenv.sh        # interpreter resolution
```

No suite has a per-test filter. To exercise a single function, source the
library in a scratch repo yourself — that is what the suites do.

**Seeded-regression pairs (SEEDED-1).** A state-machine test only counts if it
also *fails when the defect is planted* — passes-healthy is necessary, never
sufficient. `tests/helpers/seed.sh` provides `with_seeded_defect <fn> <sed-expr>
<assertion-body>`: it redefines the function under test with the defect sedded
into its own `declare -f` text, asserts the body fails, and restores the
original. The bar for new supervisor/arbiter state-machine coverage is a pair —
green-without-seed plus red-with-seed — on the model of the two shipped pairs:
verdict dedupe dropping the sha (`tests/test_async_gate.sh` §18) and the CAS
ref advance dropping `expected-old` (`tests/test_arbiter.sh` §11). Plant the
bug where a silent pass-through would be costliest.

## Platform floor: bash 3.2

**macOS system bash (3.2) is the platform floor.** Suites run under
`/bin/bash`, not the dev shell's bash 5, because that is what a stock macOS
machine has. Write to 3.2:

- no associative arrays (`declare -A`)
- no `${var,,}` / `${var^^}` case conversion
- no `mapfile` / `readarray`
- no negative array indices
- `[[ ... ]]` and `local` are fine

Running a suite under bash 5 and calling it green proves nothing about the
floor. Invoke `/bin/bash` explicitly, as `make test` does.

## Commits

Conventional commits, referencing the ticket:

```
feat: resolve interpreter via shared pyenv helper (#DOG-3)
fix: anchor arbiter resolution to orchestrator root (#DOG-13)
docs: add CONTRIBUTING and SECURITY (#DOG-6)
```

Tickets live as one Markdown file per ticket in `maps/tickets/`. Documents are
part of the work here: architectural decisions become ADRs in `docs/adr/`,
`CONTEXT.md` defines the project vocabulary (read it before naming anything
new), and `STATE.md` is the resumable checkpoint.

Claims need receipts. A finding quotes the command output that proves it, and a
ticket carries an explicit Verification Step. Probe git semantics in a scratch
repository rather than asserting them.

## Git safety rules

These four are not style preferences. Each one is a failure this project has
already paid for, and the orchestrator runs many agents across many worktrees
over one object store, which is exactly where they bite.

1. **Never `git stash`.** The stash stack is shared across every worktree of a
   repository. A `stash pop` in one worktree can restore — or destroy — work
   stashed from another. Use a WIP commit instead; it is per-branch and cannot
   be clobbered by a sibling.

2. **Never `git worktree remove --force`.** Git's refusal to remove a worktree
   with a dirty tree is the safety net, not an obstacle. If the removal is
   blocked, something uncommitted is in there. Look at it first.

3. **Never move a branch that is checked out somewhere else.** `git update-ref`
   and `git branch -f` succeed silently against a branch another worktree has
   checked out, and that checkout is then left staging a reversal of the move.
   Move a branch only from inside the worktree that has it checked out — for
   example, a fast-forward merge to a base branch runs in the root worktree.

4. **Never push or merge to a base branch without explicit human approval.**
   `main` moves only by human action. Automated work lands on a task branch and
   is integrated by compare-and-swap onto an integration ref; a human performs
   the final `merge --ff-only` or opens a pull request. Do not force-push a
   shared branch.

## Pull requests

- One ticket per pull request where you can manage it; say which ticket in the
  description.
- Paste the real `make check` output. A summary line asserting green is not
  evidence — the counts are.
- Say what you did not do. Scope left out on purpose is useful information;
  scope left out silently is a bug in the review.

## Security

Do not open a public issue or pull request for a vulnerability. See
[SECURITY.md](SECURITY.md).
