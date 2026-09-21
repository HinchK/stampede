---
id: DOG-12
title: "The human-promote invariant is absent from the brief the looper actually reads"
type: wayfinder:defect
status: resolved
commit: 3d679ef
assignee: arch
owns: briefs/looper.in.md,briefs/worker-docs.in.md,briefs/worker-gh.in.md,briefs/overseer-pm.in.md,lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/public-readiness.md
github_issue: 2
github_url: "https://github.com/HinchK/stampede/issues/2"
synced_at: "2026-09-21T21:03:40Z"
---

# DOG-12 — Promote guardrail (WAVE 1.5, RUNS ALONE)

> Observed live during the DOG-1 dogfood run, not theorised.

## 1. Intended Outcome

An orchestrator cannot advance `main` without a human, and the rule is stated in
the document the orchestrator actually reads.

## 2. What happened

During DOG-1 the looper ran, unprompted and unsupervised:

```
bash lib/arbiter.sh enqueue 1 arch-1-hinchk-stampede 3a9a70d
bash lib/arbiter.sh drain
bash lib/arbiter.sh promote          # <-- main moved, 4e1fbab -> 3a9a70d
```

`main` advanced with no human in the loop.

**The looper did not violate its instructions.** It was never given them. Counted
in the rendered brief at `.herdr-swarm/briefs/looper-<slug>.md`:

| In the looper brief | Occurrences |
|---|---|
| `push` (both about *remote* pushes) | 2 |
| `arbiter` | **0** |
| "`main` moves only by human promote" | **0** |

The invariant is written in `CLAUDE.md`, in `CONTEXT.md` §"Git Remote Safety",
and in ADR 0009 — three documents the looper never reads. It is absent from the
one it is handed.

**The contrast is the actual finding.** The remote-push guardrail *is* in the
brief, and it held perfectly: `origin/main` stayed at `924619d` with 3 commits
unpushed. Nothing reached GitHub. Guardrails written into briefs are obeyed;
guardrails living only in ADRs are not. Every invariant this project intends to
hold must be restated in the brief of the agent capable of breaking it.

## 3. Scope

1. **`briefs/looper.in.md`** — add the arbiter to the execution loop and state
   the boundary explicitly:
   - green verdicts reach the arbiter automatically; the looper does not enqueue
   - `arbiter drain` is permitted (it advances only the integration ref)
   - **`arbiter promote` is forbidden** — `main` moves only by the human driver
   - the existing Push Guardrail extends to *any* mutation of a base branch,
     local or remote
2. **`lib/arbiter.sh`** — defense in depth, because a brief is a request and not
   an enforcement: `arbiter_promote` refuses unless the caller passes explicit
   confirmation (`--confirm`, or `PROMOTE_CONFIRM=1`). The refusal message must
   name the human action required.
3. **`tests/test_arbiter.sh`** — assert promote refuses without confirmation and
   still succeeds with it.

Do **not** weaken `drain`. Advancing the integration ref is the arbiter's job and
is already CAS-protected; only `main` is human-gated.

## 4. Done-Criteria

1. `briefs/looper.in.md` contains the words `arbiter` and an explicit statement
   that `promote` is human-only.
2. `bash lib/arbiter.sh promote` with no confirmation exits non-zero, does not
   move `main`, and prints the required human action.
3. `PROMOTE_CONFIRM=1 bash lib/arbiter.sh promote` behaves exactly as today.
4. New assertions in `tests/test_arbiter.sh` for both, and the existing 30 still
   pass.
5. `make check` green; `shellcheck` 0 warnings.

## 5. Verification Step

```bash
grep -c arbiter briefs/looper.in.md                 # want >= 1
grep -ci 'human'  briefs/looper.in.md               # want >= 1

before=$(git rev-parse main)
bash lib/arbiter.sh promote; echo "want non-zero: $?"
[ "$before" = "$(git rev-parse main)" ] && echo "main unmoved: correct"

/bin/bash tests/test_arbiter.sh                     # 30 existing + new
make check
```

Receipt must show `main` unmoved after the unconfirmed promote attempt.

## 6. Second finding — the same root cause, one layer down

Folded in after increment 1. While watching for an unauthorised promote, two
commits landed on `main` that were **not** promotes:

```
87431c3  agy-docs  docs: update STATE.md for DOG-1 completion
254ccee  agy-gh    chore(tickets): link DOG-12 to GitHub issue #2
```

Both single-parent, neither reachable from the integration ref. They are root
anchors committing straight to the base branch. From `.herdr-swarm/seats.json`:

| seat | isolated | branch |
|---|---|---|
| `pm` | 0 | `main` |
| `looper` | 0 | `main` |
| `agy-docs` | 0 | `main` |
| `agy-gh` | 0 | `main` |
| `arch-1` / `arch-2` / `pi` | 1 | `swarm/<slug>/<seat>` |

**Four of seven seats write directly to `main`** — no worktree, no suite gate,
no arbiter, no human. There is exactly one gate log on disk
(`arch-1-…-3a9a70d.log`); neither commit above was verified by anything.

This is the same root cause as §2 at a different layer: the architecture's
guarantees apply to the seats it isolates, and every other seat is governed only
by the prose in its brief. Three consequences:

1. `STATE.md` — the continuity ledger a cold seat reads as truth, and the file
   the 2026-09-19 review flagged for drift — is now written by an agent with no
   verification of any kind.
2. Nothing confines a docs seat to docs. `agy-docs` is scoped by its brief, not
   by a path check — and §2 established that the brief is the only thing these
   agents actually obey.
3. The claim "nothing lands unverified" is true of `arch` seats and false of the
   other four.

### Added scope

4. **`briefs/worker-docs.in.md`, `briefs/worker-gh.in.md`,
   `briefs/overseer-pm.in.md`** — state the write boundary in each, since the
   brief is the enforcement surface that works:
   - these seats commit to the base branch directly and are therefore **never**
     suite-gated; say so plainly, so the agent knows its own blast radius
   - permitted paths: `docs/`, `maps/`, `STATE.md`, `CONTEXT.md`, `README.md`
   - forbidden without going through an `arch` seat: `lib/`, `tests/`,
     `briefs/`, `*.sh`, `Makefile`, `swarm.config.toml`
   - a docs seat that believes it needs a forbidden path must stop and report

**Out of scope here, deliberately.** The README's accuracy is DOG-5's
(`owns: README.md`) and the ADR is DOG-9's (`owns: docs/`). Do not edit either
from this ticket. Record in the receipt that **DOG-5's lede needs a scope
clause** — "Workers never merge" is true only of isolated seats, and shipping it
unqualified would be the same class of overclaim this backlog exists to remove.

### Added done-criteria

6. Each of the three briefs names its permitted and forbidden paths and states
   that the seat is not suite-gated.
7. `grep -c 'not suite-gated\|never suite-gated' briefs/worker-docs.in.md` ≥ 1.
8. The receipt carries the DOG-5 cross-reference from the paragraph above.

## 7. Notes

Runs alone and **before wave 2**. Wave 2 releases five tickets at once; without
this, each green verdict is a candidate for another unsupervised promotion.

Increment 1 (`a7be67a`) shipped §3 items 1–3. This fold-in adds item 4; land it
on the same branch and re-emit `ARCH DONE #2 <new-sha>`. The supervisor dedupes
on `(ticket, sha)`, so a new sha on the same ticket is re-gated by design.

Minor, worth fixing while in here: increment 1 set `status: in-progress` in the
frontmatter, but `lib/partition.sh:188` recognises `in_progress` with an
underscore. The hyphenated form is an *unknown* status and lands in the `*`
fail-closed branch — treated as active for the wrong reason. Use `in_progress`.
