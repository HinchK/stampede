# External Repo Review — `loop-bot-herd-agy`

**Reviewer:** Claude Opus 5 (outside-the-swarm read)
**Date:** 2026-09-19
**HEAD:** `1992e37` (`feat: task intake partition checking and lease protocol (#P3-2)`)
**Scope:** What this repo is, how it runs, what is genuinely novel in it, and what it needs next.
**Status:** EXTERNAL review, authored outside the swarm. Not a swarm-produced audit — do not
ingest as authoritative swarm context. Untracked at time of writing.
**Method:** read the tree; ran all three test suites; ran `shellcheck -S warning`; exercised
`lib/profile.sh` detection directly; checked branch/worktree state. Findings below are
empirical, not a README paraphrase.

---

## 1. What it is

A **shell-based orchestration layer that runs a herd of heterogeneous coding agents against
a git repository, and refuses to believe them.**

It is not a framework or a library. It is ~5,200 lines of bash + one 238-line Python
telemetry renderer that drive [Herdr](https://github.com/) (a terminal multiplexer with an
agent-control API) as the execution substrate. Herdr owns panes and agent lifecycles; this
repo owns *policy* — who sits where, what each seat is told, which trees get tested, and
what is allowed to count as "done".

Seats are declared in `swarm.config.toml` and deliberately span vendors:

| Seat | Engine | Job |
|---|---|---|
| `pm` | Claude Code | strategy, specs, audits |
| `arch-1` | OpenCode / GLM-5.3 | implementation (isolated worktree) |
| `arch-2` | Claude Sonnet | implementation (isolated worktree) |
| `looper` | AGY / Gemini Pro | orchestration only — forbidden from writing code |
| `agy-docs` | Gemini Flash | ADRs, docs |
| `agy-gh` | Gemini Flash | GitHub issues/PRs |
| `reviewer` | Gemini Flash | security/quality (disabled) |

The interesting design commitment is the **role split**: `looper` coordinates and verifies
but never edits files; implementation is confined to `arch-*` seats in private worktrees;
the human is the only one who may merge to `main`.

## 2. How it runs

```bash
./herdr-loop-swarm.sh [up] [dir] -m <w|b|r|a|s> [-n MAP] [-t TOPIC]
./herdr-loop-swarm.sh status [dir]
./herdr-loop-swarm.sh verify [dir] [timeout_ms]
./herdr-loop-swarm.sh down  [dir] [-y] [--keep-ws]
```

`--help` matches the documented flags — no CLI/README drift. Modes: `w` chart a milestone,
`b` brainstorm to tickets, `r` drain an existing map, `a` autonomous queue, `s` seat only.

Startup sequence (`herdr-loop-swarm.sh`, 617 lines):

1. **Preflight** (`lib/preflight.sh`) — daemon liveness, `jq`/`git`/`gh`/`python3+tomllib`,
   GitHub auth, agent runtimes. Fail-closed before any pane is touched.
2. **Profile** (`lib/profile.sh`) — detect ecosystem, GitHub remote, and `TEST_CMD`;
   refuse `""`, `none`, `true`.
3. **Workspace resolution** (`lib/lifecycle.sh`) — `find_workspace_by_cwd` matches on
   *physical pane CWD*, never on ambient `$HERDR_WORKSPACE_ID`. This is what keeps a nested
   swarm from hijacking the host session.
4. **Worktree provisioning** (`lib/worktree.sh`) — `worktree = true` seats get
   `.herdr-swarm/worktrees/<seat>` on branch `swarm/<slug>/<seat>`.
5. **Seating + nonce briefs** (`lib/briefs.sh`) — templates render to disk, and the agent
   receives a <200-byte *file pointer*, not the 3–10 KB brief. This exists because pasting
   briefs into a PTY truncated them.
6. **Readiness gate** — `herdr agent wait --until idle --until done`; in mode `a`, aborts if
   `arch`/`pm` never settle, so tasks are never dispatched into a dead pane.
7. **Telemetry** — `lib/telemetry.py stream` in the Ops anchor pane, reading JSONL from
   `.herdr-swarm/traces/`.

Then the supervisor daemon `loop-bot-herd.sh` (385 lines) polls seat scrollback for
`ARCH DONE #<ticket> <sha>`, resolves which tree that seat owns, runs the real suite, and
records a verdict. `lib/arbiter.sh` merges green branches onto an integration ref and opens
one PR; a human promotes.

**Runtime dependencies are real and local:** `herdr`, `agy`, `opencode`, `claude`, `gh`,
`jq`, `python3` ≥3.11 are all present on this machine. There is no container, no CI, and no
way to run this in an unattended environment today.

## 3. What is actually novel

Set aside the parts that are now industry-standard: worktree-per-agent isolation, a TOML
seat registry, multi-model cost routing, JSONL telemetry. Those are competent, not new.

The differentiated idea is a **layered defense against false-green** — an agent claiming
success that nothing independently confirmed. Each layer exists because a specific failure
was observed, and the code says so:

1. **Verdicts are anchored, not grepped.** Whole-line regex
   `^[[:space:]]*ARCH DONE #[0-9]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]*$` — earlier
   substring matching harvested green verdicts out of *scrollback quotations*.
2. **Dedup on `(ticket, sha)`, not ticket.** Identical trees are never re-gated, but a RED
   ticket re-verdicted at a *new* sha is re-evaluated. Fixes both `#23`≡`#230` collisions
   and permanent lockout after a failure.
3. **`gate_tree_matches` treats untracked files as drift.** The sharpest line in the repo,
   and the comment explains why: an untracked `*_test.py` would be *collected by the test
   runner*, so a dirty tree invalidates the gate even though HEAD matches.
4. **`resolve_seat_gate` will not fall back to root.** If a seat's worktree is missing or on
   the wrong branch it returns 1 rather than test the root checkout — testing the wrong tree
   is exactly how a false green is manufactured.
5. **Pre/post drift re-check around the suite run.** A tree that moved *while the suite ran*
   invalidates the verdict and re-prompts the agent.
6. **CAS integration.** `git update-ref <ref> <candidate> <expected-old>` with retry, so two
   arbiter passes cannot clobber each other; conflicts leave the ref unmoved.
7. **File-ownership leases** (`lib/partition.sh`, P3-2). Tickets declare `owns:` paths; a
   candidate overlapping a live lease is blocked. A ticket *without* `owns:` takes an
   exclusive whole-repo lease — "owns everything," never "owns nothing." Leases are
   mkdir-locked and written atomically (`tmp` + `mv`), bash-3.2/macOS safe.

Every one of these is fail-closed in the direction that costs throughput and buys
correctness. That is an unusual and correct instinct for agent orchestration, where the
default failure mode is a confident agent and a trusting supervisor.

**The second novel thing is the artifact itself.** All 84 commits landed on a single day.
The repo carries **7,391 lines of markdown against 5,189 lines of code** — 12 ADRs, 10
audits/specs, 35 tickets, a vocabulary file with explicit `_Avoid_` anti-patterns. That is
not documentation bloat: it is *load-bearing context*, written by agents for agents, so a
cold seat can pick up the frontier without a human re-explaining the architecture. A repo
whose doc corpus is primarily an input rather than an output is a genuinely interesting
shape, and it's the most original thing here.

---

## 4. What it needs — highest leverage first

### 4.1 One failure, four symptoms: nothing routinely runs the tests

The chain:

> No aggregate test command (no `Makefile`, no `tests/run_all.sh`) → no habit or hook that
> runs all three suites → no CI to run them regardless → HEAD `1992e37` landed on `main`
> with its own acceptance suite **red** → and the ledger that certifies the work is written
> by the same agents that did it.

Verified now, on `main`:

| suite | result |
|---|---|
| `tests/test_arbiter.sh` | 26 passed, 0 failed |
| `tests/test_worktree.sh` | 37 passed, 0 failed |
| `tests/test_partition.sh` | **25 passed, 1 failed** (exit 1) |

The failure is real and localizes to `lib/partition.sh:29`:

```bash
while [[ "$e" == *//* ]]; do e="${e//\/\//\/}"; done
```

The backslashes in the *replacement* text survive into the result, so collapsing `//` emits
a literal backslash. Verified directly, on both bash 3.2.57 (macOS `/bin/bash`) and 5.3:

```
$ owns_normalize " ./lib//x.sh "   →   lib\/x.sh      (expected: lib/x.sh)
```

Test `[8d]` catches it exactly. **Do not apply the obvious fix.** The natural quoted form

```bash
e="${e//"//"/"/"}"        # ← DANGEROUS HERE
```

does not collapse `//` under bash 3.2 at all, which means the `while [[ "$e" == *//* ]]`
guard never clears and the function **spins forever** on macOS system bash — verified by
hanging a 120-second probe. Since `lib/partition.sh` explicitly claims "bash 3.2 / macOS
safe," use a form checked on 3.2. Both of these were verified correct there:

```bash
s=/; while [[ "$e" == *//* ]]; do e="${e//\/\//$s}"; done   # indirect replacement
# or drop the loop entirely:  e=$(printf '%s' "$e" | tr -s '/')
```

(Not applied — this is a report. But whoever fixes it should run `tests/test_partition.sh`
under `/bin/bash`, not just `bash`.)

This matters beyond one test: `owns_normalize` is the front door to the lease protocol. A
mis-normalized path silently changes what two workers are judged to overlap on.

**Root fix, cheap, do this first:** add a `Makefile` with a `test:` target that runs
`tests/*.sh` and propagates non-zero. It pays two ways immediately — a human can verify the
repo in one command, and a GitHub Actions job becomes three lines — and it becomes the
manifest a new `detect_ecosystem` branch can key off, which is what finally lets the swarm
profile its own repo (see 4.2; the Makefile alone does **not** do this).

### 4.2 The swarm cannot dogfood its own Suite Gate from a clean clone

Confirmed empirically:

```
$ bash lib/profile.sh detect-ecosystem .        → generic
$ bash lib/profile.sh detect-test <fresh dir>   → none  (rc=1)
```

`detect_ecosystem` keys off `pyproject.toml` / `Cargo.toml` / `package.json` / `go.mod`. A
pure-bash repo with a `tests/` directory is `generic`, and `generic` deliberately returns 1
rather than fake-green. That is the right policy — but it means the repo that *invented* the
fail-closed test gate is, on a fresh clone, the one repo its own autonomous mode refuses to
run. The only thing standing in for a suite today is a hand-typed `TEST_CMD` in a gitignored
`.herdr-swarm/profile.env`, which travels with no one.

Two fixes, both small: (a) the `Makefile` above, plus a `make`/`just`/`tests/run_all.sh`
branch in `detect_ecosystem`; (b) commit a `profile.env.example`.

### 4.3 STATE.md has drifted from the tree it describes

STATE.md is the swarm's own continuity mechanism, which makes drift in it expensive — a
cold seat reads it as truth. Two concrete instances at HEAD:

- §2 lists **P3-2 as "Active Frontier. Implementing `lib/partition.sh`"** — but
  `lib/partition.sh` (447 lines) and its suite are already committed at HEAD, and the suite
  is red. The ledger describes work as in-flight that has in fact landed *broken*.
- §3 says **"Dispatch `pm` to author P3-3 specification"** — but
  `docs/audits/2026-09-19-p3-3-async-supervisor-harvesting-spec.md` already exists, on the
  unmerged `pm-p3-3-spec` branch (`5a7d547`).

To be fair to the ledger: the "Phase 2: 63/63 tests passing" claim is *accurate* for its
scope — arbiter 26 + worktree 37 = 63. The problem is not exaggeration, it is staleness plus
the structural issue that nothing outside the swarm checks it. A `make test` result line
pasted into STATE.md as part of the retire step would close most of this.

### 4.4 Eleven unmerged branches, one locked worktree, no remote but `main`

```
pm-m3-audit, pm-p2-2-spec, pm-p2-3-spec, pm-p2-4-spec, pm-p3-2-spec, pm-p3-3-spec,
pm-p3-roadmap, pm-phase2-advisory, pm-phase2-milestone-audit, pm-reordered-plan,
worktree-pm-audit                    (each 1–2 commits ahead of main)
.claude/worktrees/pm-audit           (locked, on pm-p3-3-spec)
```

Each is a one-commit doc branch that was never integrated. Content that the ledger treats as
authoritative (the P3-3 spec) is reachable only from a side branch. The arbiter exists
precisely to solve this and is not being used on the `pm` seat's output. Either route `pm`
docs through the arbiter or fast-forward and delete these — right now the repo's own
integration story is unpracticed on half its artifacts.

### 4.5 The "universal" launcher still hardcodes its parent project

`lib/profile.sh` is scrupulous about never defaulting to `Standard-Pentest/kultivait`. But:

- `herdr-loop-swarm.sh:566` unconditionally runs `uv run kultivait serve` in the Ops pane
  whenever `:4114` is closed — in *any* target repo, regardless of `[proxy] enabled = false`.
- `loop-bot-herd.sh:288` reads `~/.kultivait/credentials.toml` for its credit watch.
- `loop-bot-herd.sh:106` tells the operator to recover seats via
  `herdr-kultivait-session.sh`, a script not in this repo.

These contradict the stated universality invariant and will surprise the first person who
points the launcher at an unrelated repo. Gate the proxy launch on `[proxy].enabled`.

### 4.6 Smaller items

- **Dead parallel implementation.** `loop-bot-herd-claude/` (335 lines, its own `.swarm/`
  ledger, dry-run-by-default, a different arbiter design) is referenced from *nowhere* in
  the tree. Its README is a better statement of intent than the main README's feature list.
  Decide: harvest the dry-run default and delete it, or wire it in. Leaving a second design
  in-tree invites an agent to "fix" the wrong one.
- **Generated files committed next to templates.** `briefs/*.md` and `briefs/*.in.md` are
  both tracked. A hand-edit to a rendered `.md` is silently discarded on next render. Either
  gitignore the rendered output or mark it generated in a header.
- **`gh_sync.sh` is the largest single file (644 lines) with zero tests** — and it is the
  one module that can mutate *external* state. Its `--dry-run` default is good discipline;
  the argument parsing and issue-matching logic deserves the same test treatment
  `partition`/`arbiter`/`worktree` got.
- **`shellcheck -S warning` is clean** across `lib/`, root scripts, and `tests/` — worth
  saying precisely: clean at warning and above, not audited at `style`.
- **No unattended path.** Every mode assumes a human at a Herdr floor. If the goal is
  autonomy, a headless mode (no panes, no focus calls) is the missing capability; if the
  goal is a human-supervised cockpit, the README should stop calling itself autonomous.

---

## 5. Summary judgment

The engineering instinct here is better than the presentation. The anti-false-green
machinery — anchored verdicts, `(ticket, sha)` dedup, untracked-as-drift, no-root-fallback,
CAS integration, ownership leases — is a coherent and well-reasoned answer to the hardest
real problem in multi-agent coding, and each layer is traceable to an observed failure
rather than to speculation.

What it lacks is the one boring thing all of it depends on: **an external, mechanical check
that the repo's own tests pass.** The swarm is rigorous about everything except itself, and
the cost of that gap is already on `main` — a red acceptance suite, a stale state ledger,
and eleven orphan branches, all shipped in a single day of very fast, mostly-good work.

Fix order: `Makefile` + CI → `owns_normalize` collapse fix (3.2-safe) → reconcile STATE.md → integrate or
delete the branch backlog → de-hardcode `kultivait`.
