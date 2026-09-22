---
id: DOG-15
title: "tests/test_arbiter.sh fails on macos-latest in CI but passes everywhere locally"
type: wayfinder:defect
status: in_progress
assignee: arch-2
owns: tests/test_arbiter.sh,lib/arbiter.sh
parent: maps/public-readiness.md
github_issue: 11
github_url: "https://github.com/HinchK/stampede/issues/11"
synced_at: "2026-09-21T22:28:00Z"
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

## 2b. SCOPE WIDENED — there are now TWO CI-only suite failures

After the shellcheck pin and the hardcoded-path fix landed on PR #9 (`c0dbadd`),
the legs fail in *different* suites:

| leg | result |
|---|---|
| ubuntu | shellcheck pinned v0.11.0, **Lint clean**, `test_arbiter.sh` **passes**, then `✗ [12c] exclusive lease shape` in `tests/test_partition.sh` |
| macOS | `test_arbiter.sh` still fails as before — integration ref never created |

Two consequences. The arbiter failure is **macOS-only**, not universal — ubuntu
gets past it. And `tests/test_partition.sh` never ran in CI before, because
`make test` exits on the first failure and `test_arbiter.sh` sorts ahead of it;
fixing the hardcoded path simply let it run for the first time and it failed.
Assume more failures are queued behind these two.

Case 12c is `lease_acquire T-SER arch-9-x "swarm/x/arch-9" "-"` — the no-owns
path that should take an exclusive whole-repo lease — asserting
`exclusive == true` and `owns` empty.

## 3. What has already been ruled out

Do not re-test these:

- **Not git identity.** `.github/workflows/ci.yml` configures
  `user.name`/`user.email` globally before `make check`.
- **Not environment leakage from the dev shell.** Reproduced attempt under a
  sanitized environment — `env -i`, fresh `HOME`, isolated `GIT_CONFIG_GLOBAL`,
  CI's identity, `/bin/bash` — gives **34 passed, 0 failed**.
- **Not a regression from this backlog's arbiter work.** The same suite is green
  locally on the exact PR branch commit.
- **Not the git version.** The macOS runner reports `git 2.55.0`. Both suites
  pass locally under Apple git 2.54.0 **and** Homebrew git 2.55.0 — 34 passed.
- **Not the bash version.** macOS `/bin/bash` is 3.2.57, ubuntu's is 5.x. The
  partition suite passes locally under 3.2.57 **and** 5.3.20 — 26 passed.
- **Not shellcheck.** Pinned to v0.11.0 on both legs; ubuntu logs
  `shellcheck pinned to v0.11.0` and `Lint clean (14 shell files)`.

Every locally-reproducible hypothesis is exhausted. **Diagnose in CI** — that is
now the only remaining path, and it is what section 5 already prescribes.

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
