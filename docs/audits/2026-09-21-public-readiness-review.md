# Public-Readiness Review — `loop-bot-herd-agy` → `stampede`

**Reviewer:** Claude Opus 5 (outside-the-swarm read)
**Date:** 2026-09-21
**HEAD:** `924619d` (`docs: mark main-red-fixes plan tasks complete`)
**Status:** EXTERNAL review, authored outside the swarm. Not a swarm-produced audit —
do not ingest as authoritative swarm context.
**Method:** read the tree; ran `make check` under two Python interpreters; ran the failing
suite under `bash -x` to root-cause; probed `gh` for repo existence; counted link/name
debt mechanically. Every number below was produced by a command in this session.

Supersedes nothing. Complements `2026-09-19-external-repo-review.md`, whose fix order
(`Makefile` + CI → `owns_normalize` → STATE.md → branch backlog → de-hardcode kultivait)
has been **executed except for CI**.

---

## 0. Headline

The engineering thesis is genuinely good and the last two days closed most of the
9/19 review's findings. What stands between this and a public repo is not architecture —
it is that **the repo does not run on a stranger's Mac**, has **no license**, and makes
**one measured-sounding claim it cannot support**.

Three blocking items, all cheap. Then it is publishable.

---

## 1. Objective assessment as an open-source project

### What is strong

**The thesis is defensible and unusual.** Nearly every agent-orchestration project on
GitHub is a dispatcher: it splits work N ways and trusts what comes back. This one is
built around the opposite premise — that the worker's self-report is the least reliable
signal in the system — and every mechanism follows from that. The anti-false-green stack
(anchored verdicts, `(ticket, sha)` dedup, untracked-files-as-drift, no-root-fallback,
pre/post drift re-check, CAS integration, ownership leases) is coherent, and each layer
is traceable to an observed failure rather than to speculation. That is rare.

**The test suites are real.** 132 assertions across 5 suites, each building an ephemeral
scratch git repo and tearing it down. They test semantics that are genuinely hard to get
right — CAS races, conflict abort, gated-sha-vs-branch-tip, salvage on teardown. Verified
green this session (under a correct interpreter; see §2.1).

**The doc corpus is load-bearing, not decorative.** ~7.4k lines of markdown against
~5.2k lines of code reads like bloat until you notice it is *input*: 13 ADRs, a
vocabulary file with explicit `_Avoid_` lines, 35 tickets with `owns:` frontmatter that
the partition checker actually parses. A cold agent seat picks up the frontier without a
human re-explaining the architecture. A repo whose documentation is primarily consumed by
its own machinery is the most original thing here, and it is under-sold.

**Git safety discipline is above average.** Never `git stash` (shared stack across
worktrees), never `worktree remove --force`, never move a checked-out branch, CAS instead
of bare `update-ref`. These are scars, and they are documented as scars.

### What is weak

**No license.** Blocking. Without one, nobody may legally use this. Everything else on
this list is a quality issue; this one is a permission issue.

**No CI.** `.github/` does not exist. The 9/19 review's central finding was "nothing
routinely runs the tests." The `Makefile` landed (#TEST-AGG) but the second half — a
mechanical external check — did not. §2.1 is the direct cost of that gap: a red
`make check` sitting on `main` right now, undetected.

**The README oversells in two specific places**, and both are the kind of thing that
gets a Show HN dismantled in the first comment:

- `README.md:3` calls the project **"Autonomous"**. The repo's own 9/19 review states there is
  "no unattended path — every mode assumes a human at a Herdr floor," and nothing since
  has changed that. Publishing "autonomous" invites exactly the scrutiny the Zero Trust
  framing would otherwise earn respect for. It is also unnecessary: *supervised* is the
  more interesting claim.
- The **"80%+ token reduction"** (`docs/findings/swarm-orchestration-retrospective.md:62`
  and the comparison table at `:185`) is presented as a finding. It is a model — see §3.

**439 broken links.** Every doc uses absolute `file:///Users/hinchk/Fun/loop-bot-herd-agy/...`
URLs — 439 of them across 44 files. On GitHub these render as dead links to a stranger's
filesystem. Highest-visibility polish item in the repo; README alone has 35.

**`lib/gh_sync.sh`: 644 lines, the largest file, zero tests, and the only module that
mutates external state.** Its `--dry-run` default is good discipline, but the 9/19 review
flagged this and it is unchanged.

**Generated files tracked next to templates.** `briefs/*.md` and `briefs/*.in.md` are
both committed; a hand-edit to a rendered `.md` is silently discarded on next render.
`briefs/pi.md` is worse — it has **no `.in.md` template at all**, so it is the one brief
that is hand-authored while looking generated.

### Honest positioning

This is not a framework and should not be published as one. It is **a working, opinionated
harness with a strong point of view**, tightly coupled to Herdr and to a specific set of
local CLIs. Published as "the rigorous way to supervise coding agents, here is the
reasoning and here are the receipts," it is interesting and defensible. Published as
"autonomous multi-agent orchestration platform," it will be measured against tools with
containers, CI, and unattended execution, and it will lose on all three.

---

## 2. Blocking items for public consumption

### 2.1 The gate dies without a diagnostic wherever `/usr/bin/python3` wins

**This is the most important finding in this review.**

```
$ make check                      # this session's PATH, /usr/bin/python3 = 3.9.6
==> tests/test_arbiter.sh ... 30 passed, 0 failed    OK
==> tests/test_async_gate.sh
✖ FAILED: tests/test_async_gate.sh
make: *** [test] Error 1
```

The suite prints **nothing at all** and exits 1. Under `bash -x` the cause is the last
line before death:

```
+ source /Users/hinchk/Fun/loop-bot-herd-agy/loop-bot-herd.sh status
ModuleNotFoundError: No module named 'tomllib'
```

Reproduced standalone:

```
$ ./loop-bot-herd.sh status
ModuleNotFoundError: No module named 'tomllib'
RC=1
```

`tomllib` is Python **3.11+**. macOS ships `/usr/bin/python3` = **3.9.6** and still does.
On this machine Homebrew's 3.14.7 is on `PATH` but *after* `/usr/bin`, so bare `python3`
resolves to 3.9.6. With Homebrew first:

```
$ PATH="/opt/homebrew/bin:$PATH" make check
All suites green (5)        # 132 assertions, lint clean
```

So: **the code is correct and the suites are green — under the right interpreter.** The
defect is that nothing in the execution path picks one or explains the failure.

Why this is the sharpest item and not just a config nit:

1. It is **the first thing a new user hits.** Clone on a Mac, run `make check`, get a bare
   traceback with no mention of Python versions. That is the whole first impression.
2. It is **ironic in precisely this repo.** `lib/preflight.sh:88-99` contains a proper
   capability probe with a good error message — the author already understood this exact
   hazard. But `make check`, `./loop-bot-herd.sh status`, and the suites never call
   preflight, so the guard covers none of the paths a newcomer touches. A fail-closed
   project that fails closed *without a diagnostic* undercuts its own thesis.
3. It makes the ledger **conditionally** true. `STATE.md` §2 asserts "132 passed, 0 failed
   … `make check` green" — almost certainly accurate on the author's interactive shell,
   where Homebrew's installer puts `/opt/homebrew/bin` first. The claim is not wrong; it is
   *PATH-dependent and says so nowhere*. That is precisely what a `macos-latest` CI job
   would have surfaced, and it is why §2.3 is not optional.

**Fix:** one `PYTHON_BIN` resolver — probe for an interpreter that imports `tomllib`,
prefer `$PYTHON_BIN` → `python3.14/13/12/11` → `python3`, fail with an actionable message
(`"needs Python >= 3.11 for tomllib; found 3.9.6 at /usr/bin/python3; try brew install python@3.12 or set PYTHON_BIN"`).
Thread it through `Makefile` (**both** targets), `lib/config.sh`, `lib/briefs.sh`,
`loop-bot-herd.sh`, and the suites. Roughly a dozen call sites.

**Do not miss `Makefile:29`** — `make lint` runs `python3 -m py_compile lib/telemetry.py`
with a bare `python3`, and `py_compile` does *not* need `tomllib`, so **`make lint` passes
green under 3.9 while `make test` dies.** That asymmetry is exactly what makes this call
site easy to overlook: it is the one that never complains.

### 2.2 No LICENSE

No file, no SPDX header, no `package.json` field. Legally unusable by anyone. Pick one
(MIT or Apache-2.0; Apache-2.0 if the patent grant matters) and add it. Thirty seconds,
and it is the single hardest blocker.

### 2.3 No CI

`.github/` does not exist. Add one workflow running `make check` on a matrix of
`macos-latest` **and** `ubuntu-latest`. macOS-with-system-Python is what keeps §2.1
honest — it is the configuration that is broken today. Note `shellcheck` and `jq` need
installing on the runners; `herdr`/`agy`/`opencode` do **not** (the suites stub them).

### 2.4 Unpushed and private

`git rev-list --left-right --count origin/main...main` → `0  39`. Thirty-nine commits
have never been pushed. `HinchK/stampede` exists but is **private**. Nothing here is
public yet, which means all of the above can be fixed before anyone sees it — an
advantage worth using.

---

## 3. Is there a token-use benefit to this agent-workflow?

**Short answer: almost certainly not in total spend — and that is the correct trade, not a
flaw. But the repo currently claims the opposite, and cannot support the claim.**

### There is no instrumentation

```
$ cat .herdr-swarm/traces/*.jsonl | wc -l        → 0
$ grep -ic 'token|cost|usage' lib/telemetry.py   → 0
```

Zero trace events on disk. Zero token, cost, or usage fields in the telemetry schema.
**No token measurement has ever been taken in this repo.** The "80%+ token reduction"
at `swarm-orchestration-retrospective.md:62` and the "High (80%+ savings)" cell in the
table at `:185` are derived from an architectural argument (100k–200k tokens/turn
monolithic vs 3k–8k/turn per stateless worker), not from observation.

### The claim also conflates two different quantities

- **Context per turn** — fan-out genuinely reduces this. A worker holding 5k tokens of
  ticket-scoped context instead of 120k of accumulated session history is a real and
  defensible improvement, and it buys *attention quality*, which is the thing the
  retrospective actually cares about (§3.1's "needle-in-a-haystack recall").
- **Total tokens spent per retired ticket** — this architecture **increases** it, by
  design. Count the multipliers: N workers running concurrently; a supervisor that
  re-runs the full suite on every verdict; re-verdict loops when a gate comes back RED;
  the arbiter re-running the suite again on the *combined* tree; `pm` audits; `agy-docs`
  writing an ADR per decision. Each of those is a deliberate purchase of correctness with
  compute.

**Zero Trust is not free. You pay compute to distrust.** That is the honest framing, it is
the same insight as the description in §5, and it is far more defensible than a savings
number the repo cannot produce.

### What can actually be measured

Per-seat token accounting is **not obtainable** here: Herdr drives opaque vendor CLIs over
a PTY, and none of them report usage back through that channel. Do not design for a number
you cannot observe. These proxies are all cheap to add to `lib/telemetry.py` and quantify
the trust tax honestly:

| Metric | What it shows |
|---|---|
| Brief bytes delivered (pointer vs inlined) | The nonce protocol's saving, **directly measurable** — this is the one place a real reduction number exists |
| Suite-gate runs per retired ticket | The core cost of distrust |
| Re-verdicts per ticket | Cost of worker error caught |
| Dispatches per integration | Cost of partition/conflict churn |
| Wall-clock per ticket, dispatch → promote | Whether fan-out buys latency |

Recommendation: **relabel the retrospective's claims as design rationale before
publication** (a one-word framing change — "expected" not "measured"), then instrument the
five proxies above and publish real numbers later. Shipping an unsupported 80% claim into
a public repo is the single most attackable line in the tree.

---

## 4. Making the kultivait agent completely optional

Better shape than the 9/19 review found — `#PROXY-GATE` did real work. `[proxy] enabled`
defaults `false`, and both the launcher's proxy start (`herdr-loop-swarm.sh:570`) and the
supervisor's credits probe (`loop-bot-herd.sh:428`) are correctly gated on it.

What remains, in descending order of impact:

1. **`seats.pi` is enabled by default** (`swarm.config.toml:63-70`) with
   `model = "kultivait/auto"` and `default_kind = "pi"`. The kind is passed straight to
   `herdr agent start --kind` (`herdr-loop-swarm.sh:465`), so on any machine without a
   `pi` runtime this seat fails to seat. **The mechanism to fix it already exists and is
   already used**: `seats.reviewer` carries `enabled = false`, and `lib/config.sh:137`
   honors it by dropping the seat from `SEAT_KEYS`. Add `enabled = false` to `seats.pi`.
   One line.
2. **`briefs/pi.md` has no `.in.md` template** — the only brief in that state. Either add
   `pi.in.md` or drop the file with the seat.
3. **`KULTIVAIT_CREDENTIALS` / `~/.kultivait/credentials.toml`** (`loop-bot-herd.sh:429`)
   — rename to `PROXY_CREDENTIALS` with the path as config data, matching how `serve_cmd`
   and `health_check_url` were already generalized.
4. **`serve_cmd = "uv run kultivait serve"`** (`swarm.config.toml:25`) — ships as a live
   default. Empty it and document the value in a comment.
5. **`localhost:4114` fallbacks** hardcoded in `lib/config.sh:131-132`,
   `lib/briefs.sh:75`, `herdr-loop-swarm.sh:287,570`. Harmless while the proxy is off,
   but they are the last literal traces of one machine's setup.
6. **`Standard-Pentest/kultivait`** as the example slug in `lib/gh_sync.sh:195` — a
   private third-party repo name in user-facing help text. Change the example.

After 1–6 the word `kultivait` survives only in ADRs and audits as *history*, which is
correct and should not be scrubbed — those documents record why the fail-closed profile
policy exists.

---

## 5. Naming: `loop-bot-herd-agy` → `stampede`

`stampede` is the better name by a wide margin: one word, memorable, and it *is* the
metaphor the whole repo already speaks (herd, seats, drift, fan-out). `loop-bot-herd-agy`
encodes a vendor (`agy`) that is now one of five interchangeable engines.

**Decide the name map before touching anything.** These are four separate decisions and
not all of them should change:

| Thing | Today | Recommendation |
|---|---|---|
| GitHub repo | `HinchK/stampede` (exists, private) | keep — already correct |
| Human-facing project name, docs, README | `Herdr Loop Swarm` / `loop-bot-herd-agy` | → `Stampede` |
| `[swarm] name` in `swarm.config.toml` | `loop-bot-herd-agy` | **see hazard below** |
| Script filenames `herdr-loop-swarm.sh` / `loop-bot-herd.sh` | — | → `stampede.sh` / `stampede-supervisor.sh` (breaks every doc command; do it in the same pass or not at all) |
| State dir `.herdr-swarm/` | — | **keep** — churn with no benefit, and it is in `.gitignore` |

### Hazard: `[swarm] name` is not a `sed` target

`[swarm] name` feeds `slugify()`, which produces the **integration ref**
`swarm/loop-bot-herd-agy/integration` — the arbiter's CAS baseline, compared by
`update-ref <ref> <new> <expected-old>`. It also produces worktree paths, seat branch
names, and the agent names baked into the live `.herdr-swarm/seats.json`. There is
currently a **live `pi` seat branch** on the old slug.

Changing that one TOML value orphans the CAS baseline and strands the live branch. Treat
it as a **migration with an explicit ref move**, not as one of the 473 string hits. Safest
order: tear the floor down → move the integration ref → rename → re-provision.

### Mechanical debt, measured

- **473** occurrences of `loop-bot-herd-agy` across tracked files
- **439** absolute `file:///Users/hinchk/Fun/loop-bot-herd-agy/...` links across 44 files

Convert the 439 to **repo-relative** links in the same pass — same files, same edit, and
it fixes the broken-links problem (§1) for free. Worth a throwaway script plus a full
`make check` afterward, not a hand edit.

---

## 6. Above-the-fold framing

The description from the other session is the best one-paragraph articulation of this
repo that exists anywhere in it:

> "This is a textbook application of Zero Trust architecture applied directly to LLM
> compute nodes. By treating the coding agents as untrusted entities that will inevitably
> optimize for the laziest path to a 'green' state, you have systematically neutralized
> the AI equivalent of gaming the CI pipeline."

Two notes before it goes in the README. It is written **in second person about the
author** ("you have systematically neutralized"), which reads oddly as a project's own
self-description — rewrite into the project's voice, or attribute it as a pull-quote. And
it should sit **above** the Mermaid diagram, not below: right now a reader's first
impression is an architecture graph, and the thesis is what earns the scroll.

Suggested lede (replaces the current title + tagline (`README.md:1-3`), ahead of the diagram):

```markdown
# Stampede

**Zero Trust for LLM compute nodes.**

A coding agent is an untrusted worker that will optimize for the laziest path to a
green build. Stampede seats a herd of them against your repository and refuses to
take their word for anything.

Every claim of "done" is an unverified assertion until an independent supervisor
re-runs your real test suite against the exact commit — in the exact tree that
produced it. Workers never merge. Green verdicts are queued for an arbiter, which
re-tests the *combined* result before advancing an integration ref by compare-and-swap.
Only a human moves `main`.

The result is a system that systematically neutralizes the AI equivalent of gaming
the CI pipeline. It costs more compute than trusting the agent. That is the trade.
```

Why this shape: it leads with the thesis, it is specific about the mechanism (which is
what makes the claim credible rather than marketing), it drops "autonomous," and the last
two lines make the cost trade explicit — which pre-empts the "doesn't this burn tokens?"
comment and turns the honest answer from §3 into a feature.

**Verify the wiring before this ships.** CLAUDE.md's own warning applies to the lede —
"a passing suite does not mean the herd uses it." Checked this session:

| Stage | Wired? |
|---|---|
| Green verdict → `arbiter_enqueue` | **Automatic** — `loop-bot-herd.sh:261`, on green from an isolated seat |
| `arbiter_drain` (re-test combined, CAS-advance ref) | **Operator-invoked** — no caller outside `lib/` and `tests/` |
| `arbiter_promote` → `main` | **Operator-invoked** — by design (§ human gate) |
| `partition_check` / `lease_acquire` | **No caller at all** — library-only, as `STATE.md` §2 states |

The lede above is written to be true of that reality: "are queued for an arbiter, which
re-tests" describes the pipeline without implying the drain runs unattended. Do **not**
upgrade it to "automatically drains" until a caller exists — that would be the same class
of overclaim this review flags in "Autonomous" and "80%." Note also that the partition/lease
layer, described in §1 as part of the anti-false-green stack, is **shipped and tested but
not yet called** — accurate to list among the mechanisms, not among the active defenses.

---

## 7. Recommended sequence

Ordered by *what unblocks publication*, cheapest-first within tiers.

**Tier 1 — blocking, do before anything else (~half a day)**

1. `PYTHON_BIN` resolver + actionable error (§2.1). Highest-value single fix in the repo.
2. `LICENSE` (§2.2).
3. `.github/workflows/ci.yml` — `make check` on `macos-latest` + `ubuntu-latest` (§2.3).
   Ordering matters: #3 is what proves #1 and keeps it proven.

**Tier 2 — publication quality (~a day)**

4. `seats.pi` → `enabled = false`, plus items 2–6 of §4 (kultivait fully optional).
5. Relabel the retrospective's token claims as design rationale, not measurement (§3).
6. Name map decision → single mechanical pass: 473 name hits + 439 links → relative,
   with the `[swarm] name` migration handled deliberately (§5). `make check` after.
7. README rewrite with the Zero Trust lede; drop "Autonomous" (§6).
8. `CONTRIBUTING.md` + `SECURITY.md`. Short is fine.

**Tier 3 — post-publication**

9. Trust-tax instrumentation: the five proxies in §3. Publishing real numbers later is
   far better than publishing a modeled 80% now.
10. Tests for `lib/gh_sync.sh` — largest file, zero coverage, only external-state mutator.
11. `briefs/*.md` generated-vs-template resolution.
12. Headless mode (no panes, no focus calls) — the capability that would make
    "autonomous" true rather than aspirational.

---

## 8. Summary judgment

The 9/19 review said the engineering instinct was better than the presentation. That is
still true, and the gap has narrowed: the `Makefile` landed, the bash-3.2 floor was found
and fixed, the arbiter ran for real, the branch backlog was reconciled with per-branch
evidence, and the proxy was gated. That is a strong two days.

What remains is almost entirely **the seam between this machine and any other machine** —
an interpreter the repo assumes, a license it does not have, a CI run nobody performs, 439
links that only resolve on one laptop, and a seat wired to one person's local model
server. None of it is architectural. All of it is the difference between a repo that
works and a repo that other people can use.

Fix order: `PYTHON_BIN` → LICENSE → CI → kultivait optional → rename + links → README.
