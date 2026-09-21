---
id: DOG-15
title: "tests/test_arbiter.sh fails on macos-latest in CI but passes everywhere locally"
type: wayfinder:defect
status: backlog
assignee: arch
owns: tests/test_arbiter.sh,lib/arbiter.sh
parent: maps/public-readiness.md
---

# DOG-15 — Arbiter suite fails in CI only

> Found by DOG-3's CI on PR #9. Diagnosis is the deliverable; the fix follows
> from it. Do not guess at a fix and call it done.

## 1. Intended Outcome

`tests/test_arbiter.sh` passes on `macos-latest` in CI, and the reason it did
not is understood and written down — not papered over with a retry, a `sleep`,
or a skip.

## 2. Problem

PR #9, `make check (macos-latest)`:

```
  ✗ drain: #201 integrated (wanted integrated, got queued)
  ✗ drain: #202 integrated (wanted integrated, got integration_red)
fatal: Not a valid object name refs/heads/swarm/ptest/integration
  ✗ #201 gated sha is reachable from integration ref
  ✗ integration tree contains both seats' files (merge or ff chain)
  ✓ main untouched by drain
  ✗ conflicting branch recorded as conflict (wanted conflict, got queued)
✖ FAILED: tests/test_arbiter.sh
```

Read the two failures together — they are the clue. `#201` stays **queued**
(drain never processed it) while `#202` resolves **integration_red** (drain ran
and the combined-tree gate failed). The integration ref is never created, so
every downstream reachability assertion fails as a consequence rather than on
its own merits.

The ubuntu leg does not get this far; it fails earlier at lint (DOG-14).

## 3. What has already been ruled out

Do not re-test these:

- **Not git identity.** `.github/workflows/ci.yml` configures
  `user.name`/`user.email` globally before `make check`.
- **Not environment leakage from the dev shell.** Reproduced attempt under a
  sanitized environment — `env -i`, fresh `HOME`, isolated `GIT_CONFIG_GLOBAL`,
  CI's identity, `/bin/bash` — gives **34 passed, 0 failed**.
- **Not a regression from this backlog's arbiter work.** The same suite is green
  locally on the exact PR branch commit.

## 4. Suggested direction

Candidates, in rough order of likelihood:

1. Something the suite assumes about the ambient repo. `actions/checkout@v4`
   defaults to a **shallow** clone (`fetch-depth: 1`); the suite builds its own
   scratch repo, but check whether any arbiter path consults the *outer* repo.
2. A `git` version difference on the runner image affecting `worktree`, `merge`,
   or `update-ref` CAS semantics.
3. `TMPDIR` / path-length / symlink differences (`/tmp` vs
   `/private/var/folders/...`) on a hosted macOS runner. The suite already
   canonicalises with `pwd -P`; confirm the arbiter's own worktree path does.
4. A pre-existing ordering or timing assumption that only fails on a slower,
   colder filesystem.

## 5. Scope

1. **Diagnose in CI**, since it does not reproduce locally: push a temporary
   debug branch that runs the suite with `set -x` and dumps `git --version`,
   `git worktree list`, and the arbiter's own stderr on failure. Delete that
   branch once the cause is known.
2. Fix the cause. If the defect is in `lib/arbiter.sh`, that is the more serious
   outcome and the ticket should say so plainly — it would mean the integration
   pipeline is environment-sensitive.
3. Add whatever assertion would have caught it, so it cannot regress silently.

**Forbidden fixes:** retry loops, `sleep`, `continue-on-error`, marking the
suite non-blocking, or skipping it on macOS. The whole point of this gate is
that it is mechanical and unconditional.

## 6. Done-Criteria

1. The root cause is stated in one sentence in the receipt, with the evidence
   that establishes it.
2. `make check` green on `macos-latest` **and** `ubuntu-latest` on PR #9.
3. The suite still passes locally, sanitized and unsanitized.
4. No retry, sleep, skip, or `continue-on-error` anywhere in the fix.
5. The temporary debug branch is deleted.

## 7. Verification Step

```bash
/bin/bash tests/test_arbiter.sh ; echo "rc=$?"
env -i HOME=/tmp/fh PATH=/usr/bin:/bin:/opt/homebrew/bin /bin/bash -c 'cd '"$PWD"'; /bin/bash tests/test_arbiter.sh'
gh pr checks 9 -R HinchK/stampede
```
