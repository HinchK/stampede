---
id: DOG-12
title: "The human-promote invariant is absent from the brief the looper actually reads"
type: wayfinder:defect
status: in-progress
assignee: arch
owns: briefs/looper.in.md,lib/arbiter.sh,tests/test_arbiter.sh
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

## 6. Notes

Runs alone and **before wave 2**. Wave 2 releases five tickets at once; without
this, each green verdict is a candidate for another unsupervised promotion.
