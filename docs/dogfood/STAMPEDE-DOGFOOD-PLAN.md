# Stampede Dogfood Plan — the swarm rewrites its own source

**Purpose:** run this repo's swarm against a *separate clone of this repo*, to
work the public-readiness backlog from
`docs/audits/2026-09-21-public-readiness-review.md`.

**Authored:** 2026-09-21, outside the swarm. Evidence-bearing, not swarm-certified.

Everything here was verified against the tree at `924619d`. Where a claim is a
measurement, the command that produced it is shown.

---

## 1. The topology, and why it is two directories

`herdr-loop-swarm.sh` resolves `SCRIPT_DIR` from `${BASH_SOURCE[0]}`
(`herdr-loop-swarm.sh:9`), while `loop-bot-herd.sh` resolves `REPO_DIR` from
`$PWD` (`loop-bot-herd.sh:29`) and sources its libraries from `$SCRIPT_DIR`
(`loop-bot-herd.sh:47`). Those two are independent — which is exactly what makes
dogfooding safe:

```
SOURCE  /Users/hinchk/Fun/loop-bot-herd-agy      the orchestrator. Pinned. Never edited by agents.
TARGET  ~/Fun/stampede-dogfood                   the clone. Everything the agents touch.
```

The supervisor executes the **source's** `lib/*.sh` while gating the **target's**
tree. So when DOG-1 rewrites `loop-bot-herd.sh` and `Makefile`, it rewrites them
*in the clone*, and the running supervisor is unaffected.

> **Hard rule.** Never point the launcher at the source directory. If
> `TARGET == SOURCE`, the agents rewrite the code the supervisor is mid-execution
> of. The bootstrap script refuses this case; do not work around it.

---

## 2. Precondition: the swarm cannot start until you fix your PATH

This is the one thing that will stop you before you begin, and it is also the
first ticket.

```
$ ./loop-bot-herd.sh status
ModuleNotFoundError: No module named 'tomllib'
RC=1
```

macOS ships `/usr/bin/python3` = 3.9.6; `tomllib` needs 3.11+. Where `/usr/bin`
precedes Homebrew on your PATH, the supervisor cannot start at all — and neither
can `make test`.

```bash
export PATH="/opt/homebrew/bin:$PATH"
python3 -c 'import tomllib; print("ok")'
```

Do this in **every shell** that runs a swarm command, until DOG-1 lands. The
bootstrap script hard-fails if it is not satisfied.

The irony is the point: the first ticket fixes the defect that would otherwise
prevent the swarm from running long enough to fix it.

---

## 3. Bootstrap

> **Commit this directory first.** `docs/dogfood/` and the review it derives from
> are untracked as written. The bootstrap copies tickets from your working tree
> so it runs either way, but until they are committed they exist in exactly one
> place on one machine — which is the failure mode this whole backlog is about.

```bash
bash docs/dogfood/bootstrap-dogfood.sh ~/Fun/stampede-dogfood
```

It will:

1. refuse if target == source, or if `python3` lacks `tomllib`
2. clone from the **local** source — `origin/main` on GitHub is 39 commits
   behind and has none of the Makefile / PROFILE-MAKE / PROXY-GATE work
3. set `origin` to `github.com/HinchK/stampede` — `detect_repo` (`lib/profile.sh`)
   matches `github.com[:/]owner/repo`, so a local-path origin fails closed and
   aborts the launcher
4. seed `.herdr-swarm/profile.env` with `TEST_CMD="make test"`
5. **park** the 5 pre-existing tickets still marked `backlog`/`in_progress`
   (P3-4, P3, T-016-arch, T-016c, P2-2) into `maps/tickets-parked/` — otherwise
   the looper may pull P3-4 instead of DOG-1
6. put DOG-1 in `maps/tickets/` and hold DOG-2..DOG-11 in `maps/tickets-staged/`
7. delete `docs/dogfood/` **from the clone** — otherwise an agent greps `docs/`,
   finds every staged ticket plus this plan, and works ahead of the wave
8. commit, so the root tree is clean
9. run `make check` once to establish a green baseline

**If step 9 is RED, stop.** Every verdict will be RED until the baseline is
green, and you will be debugging the harness instead of the work.

---

## 4. Launch

Two shells, both with the PATH fix.

**Shell A — the floor:**

```bash
cd /Users/hinchk/Fun/loop-bot-herd-agy
./herdr-loop-swarm.sh up ~/Fun/stampede-dogfood -m a
```

`-m a` is auto-queue. It gates fail-closed on an unrunnable `TEST_CMD`
(`herdr-loop-swarm.sh:355-360`) and on unverified `arch`/`pm` seats
(`herdr-loop-swarm.sh:545`).

**Shell B — the supervisor:**

```bash
cd ~/Fun/stampede-dogfood
/Users/hinchk/Fun/loop-bot-herd-agy/loop-bot-herd.sh watch
```

`cd` into the target, invoke the source by absolute path. That gives
`REPO_DIR` = target and `SCRIPT_DIR` = source, which is the split section 1
describes. Running it any other way breaks the isolation.

Sanity check before you walk away:

```bash
./herdr-loop-swarm.sh status ~/Fun/stampede-dogfood
```

---

## 5. The wave protocol — this is the part that is manual

Two mechanisms you would expect to sequence this work **do not run**:

| Mechanism | State | Consequence |
|---|---|---|
| `partition_check` / `lease_acquire` | shipped, tested, **no callers** | file-overlap protection is not enforced |
| `blocked_by` frontmatter | parsed by **nothing** | the dependency DAG is advisory prose |

Both verified:

```
$ grep -n 'partition_check\|lease_acquire' herdr-loop-swarm.sh loop-bot-herd.sh
(no output)
```

So **you are the scheduler.**

### Gate by file presence, not by status

There is no inert ticket status. `lib/partition.sh:187-199` recognises exactly
three cases — `in_progress` is active, `backlog`/`ready` are dispatchable,
`resolved`/`done`/`closed` are inactive once integrated. **Everything else,
including `blocked`, hits the `*` fail-closed branch and counts as active**,
holding a phantom lease on its own files:

```
$ bash lib/partition.sh check maps/tickets/license.md .
BLOCKED by active ticket DOG-2 (status=blocked)
  license ∩ license
```

That is the ticket blocking *itself*. So unreleased tickets live **outside**
`maps/tickets/`. The bootstrap puts them in `maps/tickets-staged/`, and releasing
a wave is a move:

```bash
cd ~/Fun/stampede-dogfood
git mv maps/tickets-staged/{license,ci-workflow,token-claim-relabel,readme-zero-trust-lede,contributing-and-security}.md \
       maps/tickets/
git commit -qm "chore: release wave 2"
```

Commit it. A dirty root tree makes `arbiter promote` refuse.

Do not open the next wave until the current one has integrated.

| Wave | Tickets | Concurrency | Why |
|---|---|---|---|
| 1 | DOG-1 | **alone** | owns `loop-bot-herd.sh`, `Makefile`, `lib/config.sh` — and unblocks everything |
| 2 | DOG-2, DOG-3, DOG-4, DOG-5, DOG-6 | parallel | `owns:` lines are disjoint by inspection |
| 3 | DOG-7 | **alone** | shares `loop-bot-herd.sh` + `lib/config.sh` with DOG-1 |
| 4 | DOG-8, DOG-11 | parallel | DOG-8 shares `lib/gh_sync.sh` with DOG-7; DOG-11 owns only `lib/partition.sh` + its suite |
| 5 | DOG-9 | **alone** | touches nearly every `.md`; must follow DOG-5 |
| 6 | DOG-10 | **human** | floor down + manual ref move; never unattended |

Wave 2 has five tickets but only two `arch` seats plus `agy-docs`. That is fine —
the looper pulls what it can. Do not add seats to go faster; concurrency is
bounded by `[fanout] max_workers = 2` in `swarm.config.toml` for a reason.

---

## 6. Integration is operator-invoked

Green verdicts enqueue **automatically** — `loop-bot-herd.sh:261` calls
`arbiter_enqueue` on a green gate from an isolated seat. Nothing after that is
automatic:

```
$ grep -rn 'arbiter_drain\|arbiter_promote' --include='*.sh' . | grep -v tests/ | grep -v lib/arbiter.sh
(no output)
```

So after each wave:

```bash
cd ~/Fun/stampede-dogfood
bash /Users/hinchk/Fun/loop-bot-herd-agy/lib/arbiter.sh drain
bash /Users/hinchk/Fun/loop-bot-herd-agy/lib/arbiter.sh promote
```

`drain` merges each gated sha onto `swarm/<slug>/integration` in its own detached
worktree, re-runs the suite on the **combined** tree, and advances the ref by
compare-and-swap. `promote` fast-forwards `main` — run it from the root worktree.

**If nothing appears to integrate, this is why.** It is not a malfunction.

---

## 7. Watching it

```bash
cd ~/Fun/stampede-dogfood
tail -f .herdr-swarm/session-verdicts.jsonl              # every verdict, deduped on (ticket, sha)
ls .herdr-swarm/gates/                                   # in-flight background gate jobs
python3 /Users/hinchk/Fun/loop-bot-herd-agy/lib/telemetry.py stream <session> .herdr-swarm/traces
git log --oneline swarm/loop-bot-herd-agy/integration    # what has actually integrated
```

A verdict is the only evidence a ticket is done. An agent saying it passed is not
a verdict — that distinction is the entire thesis of the repo you are testing.

---

## 8. When it goes wrong

**Every verdict is RED.** Check the baseline first:
`cd ~/Fun/stampede-dogfood && make check`. If that is red, the gate is broken,
not the work — almost always the PATH/interpreter issue from section 2.

**A verdict says `invalidated`.** The tree moved while the suite ran. Working as
designed (`gate_tree_matches` treats untracked files as drift, because an
untracked `*_test.py` would be collected by the runner). The worker is
re-prompted automatically.

**A seat will not settle.** `./herdr-loop-swarm.sh verify ~/Fun/stampede-dogfood 60000`.
In auto-queue mode the launcher already fails closed if `arch`/`pm` never settle.

**The same suite fails twice on one ticket.** Stop. The looper's brief says to
surface the diagnostic rather than loop retries. Read the gate log in
`.herdr-swarm/gate-logs/`.

**You need to stop everything.**

```bash
cd /Users/hinchk/Fun/loop-bot-herd-agy
./herdr-loop-swarm.sh down ~/Fun/stampede-dogfood -y
```

Teardown is selective — it closes only panes recorded in `seats.json`, checkpoints
dirty tracked files, and salvages untracked ones. Worker branches survive.

**You want to throw it all away.** The clone is disposable. `rm -rf` it and
re-run the bootstrap. Nothing in the source repo changed.

---

## 9. What "done" looks like

After wave 5, in the target:

```bash
cd ~/Fun/stampede-dogfood
make check                                          # 5 suites green
test -f LICENSE && test -f .github/workflows/ci.yml
grep -rn 'file:///Users' . --include='*.md' | wc -l # 0
grep -rn kultivait --include='*.sh' --include='*.toml' . # comments only
bash /Users/hinchk/Fun/loop-bot-herd-agy/lib/config.sh dump stampede | grep SEAT_KEYS  # no "pi"
sed -n '1,20p' README.md                            # Zero Trust lede, no "Autonomous"
```

Then DOG-10 by hand, then push — with your own approval, as the briefs require.

---

## 10. What this run is actually testing

The backlog is the stated goal. The second, less obvious one: **this is the first
time the swarm has been pointed at a repository that is not trivial and not its
own root checkout.**

### It already paid for itself, during bootstrap

Writing this plan surfaced a latent defect nobody had hit, because nobody had run
the tooling against a fresh clone before:

`partition_check` treats `resolved`/`done`/`closed` tickets as active unless it
can prove they integrated — and the proof lives in
`.herdr-swarm/integration.jsonl`, which is **gitignored**. In any clone that file
is absent, so all **38** historical tickets read as active lease-holders and every
new ticket is blocked:

```
$ ls .herdr-swarm/integration.jsonl        → No such file or directory
$ bash lib/partition.sh check maps/tickets/license.md .
BLOCKED by active ticket TEST-AGG (status=resolved)
  makefile ∩ makefile
... rc=1
```

Harmless today — nothing calls `partition_check`. But `STATE.md` §3 lists wiring
it into the dispatch path as the next task, and doing so would deadlock any
clone, including CI. Filed as **DOG-11**, which should land before that wiring.

Worth recording in `STATE.md` as you go:

- Did any ticket's `owns:` turn out wrong — did two workers collide on a file the
  frontmatter did not declare? That is direct evidence for wiring
  `partition_check` into the dispatch path.
- How many suite-gate runs per retired ticket? How many re-verdicts? Those are
  two of the five trust-tax proxies the review proposes instrumenting, and this
  run can produce them by hand from `session-verdicts.jsonl`.
- Did the arbiter ever conflict, and did handing it back to the worker actually
  resolve it?

A dogfood run that produces no findings about the harness has not been observed
closely enough.
