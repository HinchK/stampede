---
id: DOG-13
title: "A guard that ships inside the artifact it guards is unarmed until that artifact lands"
type: wayfinder:defect
status: in_progress
assignee: arch
owns: herdr-loop-swarm.sh,loop-bot-herd.sh,lib/briefs.sh,briefs/looper.in.md
parent: maps/public-readiness.md
github_issue: 3
github_url: "https://github.com/HinchK/stampede/issues/3"
synced_at: "2026-09-21T21:33:19Z"
---

# DOG-13 — Invoke the arbiter from the orchestrator, not the target

> Observed live, immediately after DOG-12 shipped. The fix was green, tested,
> integrated — and inert.

## 1. Intended Outcome

The arbiter that governs a target repository is the one from the pinned
orchestrator, so its guards are in force from the first run rather than from the
moment the target happens to merge them.

## 2. What happened

DOG-12 added a human-only gate to `arbiter_promote` (`--confirm` /
`PROMOTE_CONFIRM=1`), with assertions, and it passed its own suite. Minutes later
an unconfirmed `bash lib/arbiter.sh promote`, run from the target's root
checkout, promoted `main` anyway:

```
$ bash lib/arbiter.sh promote
arbiter: promoted integration to main
rc=0
```

Cause, measured:

```
$ git show 8203f73:lib/arbiter.sh | grep -c PROMOTE_CONFIRM     → 0    # what main had
$ git show main:lib/arbiter.sh   | grep -c PROMOTE_CONFIRM      → 4    # after the promote
```

The root worktree is checked out on the base branch, so `bash lib/arbiter.sh`
resolves to **the target's** copy. While DOG-12 lived only on
`swarm/<slug>/integration`, the copy anyone actually executed was the unguarded
one. The guard could not take effect until the promote it exists to prevent had
already happened.

Re-tested after the fact, the guard works:

```
arbiter: promote REFUSED — promoting advances the base branch and is reserved for the human driver
rc=1
```

So this is not a defect in DOG-12's logic. It is a defect in **where the code is
loaded from**.

## 3. Why this generalises

The project already knows this pattern and applies it correctly elsewhere:
`loop-bot-herd.sh:29,39` separates `REPO_DIR` (the tree under test) from
`SCRIPT_DIR` (the orchestration that judges it), and sources its libraries from
`SCRIPT_DIR`. That separation is exactly why a worker rewriting the supervisor
cannot subvert the supervisor mid-run.

The arbiter is the one governance component that does **not** get that
treatment: it is invoked as a bare relative path from whatever tree happens to
be current. Every future guard added to `lib/arbiter.sh` inherits the same
window — it protects nothing until the target adopts it.

Worse in the general case: when the swarm drives a *foreign* repository, that
repo has no `lib/arbiter.sh` at all. The only reason it resolved here is that
the target is a clone of the orchestrator. Dogfooding hid an absent dependency
behind a coincidence.

## 4. Scope

1. Resolve the arbiter through `$SCRIPT_DIR` wherever the launcher or supervisor
   invokes or references it, never as a bare relative path.
2. `briefs/looper.in.md` — give the looper the absolute orchestrator path to use
   for arbiter commands, and state plainly that the target's own copy (if any)
   is not the governing one.
3. Fail loudly if the resolved arbiter is missing, rather than falling back to
   the target's tree.

Do **not** copy `lib/arbiter.sh` into targets to paper over this; that
re-creates the drift in a new place.

## 5. Done-Criteria

1. No invocation of `arbiter.sh` in `herdr-loop-swarm.sh`, `loop-bot-herd.sh` or
   any rendered brief resolves relative to the target's cwd.
2. In a target with **no** `lib/arbiter.sh`, the arbiter still runs from the
   orchestrator.
3. A target carrying a *modified* `lib/arbiter.sh` with its guard stripped does
   not get used; the orchestrator's guarded copy is.
4. `make check` green; `shellcheck` 0 warnings.

## 6. Verification Step

```bash
grep -rn 'arbiter\.sh' herdr-loop-swarm.sh loop-bot-herd.sh briefs/*.in.md
# every hit must be $SCRIPT_DIR-anchored or an absolute path

tmp=$(mktemp -d) && git init -q "$tmp/t" && (cd "$tmp/t" && git commit -q --allow-empty -m base)
# drive the launcher at $tmp/t and confirm arbiter commands resolve to the orchestrator
rm -rf "$tmp"
```

Receipt must show criterion 3 exercised: a target whose `lib/arbiter.sh` has the
guard removed, and the promote still refused.

## 7. Notes

The same question should be asked of every `lib/*.sh` a brief tells an agent to
run. This ticket fixes the arbiter because that is where the gap was observed;
the audit is the more valuable half.
