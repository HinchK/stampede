---
id: P3-FLAKE-1
title: "Concurrent worktree_provision Race: Non-Idempotent Retry Leaves Branch Without Worktree"
type: wayfinder:defect
status: resolved
commit: cf8b546
assignee: arch
owns: lib/worktree.sh,tests/test_worktree.sh
parent: maps/universal-herdr-swarm.md
github_issue: 24
github_url: "https://github.com/HinchK/stampede/issues/24"
synced_at: "2026-09-22T03:50:13Z"
---

# Concurrent `worktree_provision` Race: Non-Idempotent Retry (P3-FLAKE-1)

**Severity:** MED — intermittent red on `main`; blocks P3-1 replica seating (N workers are provisioned concurrently).
**Found by:** `pm`, while reviewing P3-2. Reproduced and root-caused with probes (git 2.55.0).

## 1. Symptom

`tests/test_worktree.sh` fails intermittently on two adjacent assertions:

```
✗ 5 concurrent provisions all succeed
✗ 5 parallel worktrees + branches all present
```

Observed rate in the suite as written (N=5): **1 failure in 6 runs (~17%)**, then 5/5 clean reruns. A green rerun is
not evidence of a fix.

## 2. Reproduction (load-dependent)

Concurrency is the variable; N=5 was not enough to reproduce in isolation.

| N concurrent provisions | Rounds | Rounds with ≥1 failure |
|---|---|---|
| 5 | 12 | **0** |
| 12 | 8 | **2** |
| 6, **serialized** (as under §4.1's lock) + external `worktree add/remove` churn in the same repo | 25 | **0** |

Probe: `N` background `worktree_provision par-$i myproj HEAD "$repo"` calls in one fresh repo, stderr captured.
Failure output (round 3, N=12):

```
Preparing worktree (new branch 'swarm/myproj/par-10')
fatal: a branch named 'swarm/myproj/par-10' already exists
worktrees registered: 12 (want 13)
branches: 12 (want 12)
```

The end state is the tell: **the branch exists, the worktree does not.**

## 3. Root cause

`lib/worktree.sh`, new-branch path:

```bash
git -C "$target_dir" worktree add -b "$branch" "$wt_path" "$base_ref" >/dev/null 2>&1 \
  || { sleep 0.3; git -C "$target_dir" worktree add -b "$branch" "$wt_path" "$base_ref" >/dev/null; }
```

1. Under contention on git's `.git/worktrees` admin and ref locks, the first `worktree add -b` **creates the branch**
   and then fails before the worktree is registered (it prints `Preparing worktree (new branch …)` first).
2. The retry runs the **same `-b` command**, which now collides with the branch its own failed attempt created:
   `fatal: a branch named … already exists`.
3. The retry is therefore guaranteed to fail in exactly the case it exists to handle. `worktree_provision` returns
   non-zero, leaving an orphan branch and no worktree.

The retry is not idempotent: it repeats the command instead of re-evaluating state.

## 4. Fix

### 4.1 Primary: serialize provisioning under a `mkdir` lock

Provisioning is a compound, non-atomic sequence (`show-ref` → `worktree add` → `lock`). Two of them interleaving is
what produces the half-finished state in §3. Wrap the whole sequence in the herd's standard advisory lock — the same
pattern `arbiter_lock` uses, which is bash 3.2 / macOS safe (no `flock`):

```bash
_wt_lock()   { mkdir "${target_dir}/.herdr-swarm/provision.lock" 2>/dev/null; }   # atomic create-or-fail
_wt_unlock() { rmdir "${target_dir}/.herdr-swarm/provision.lock" 2>/dev/null; }
```

- Spin with bounded attempts and jittered backoff; stamp the lock dir with the holder's pid so a stale lock (pid dead)
  can be broken deliberately rather than by timeout alone.
- Hold across the **entire** sequence including the `worktree lock` call, and release on every exit path (`trap`), or a
  crashed provision wedges all later seats.
- Cost is small and bounded: provisioning is a checkout, not a suite run, and it happens once per seat per `up`.

**Measured support.** With provisioning **serialized** (what this lock gives) while an *external* process churned
`worktree add --detach` / `remove` in the same repo: **0 failures in 25 rounds (150 provisions)**. Under
**concurrent** provisioning with no lock: 2 of 8 rounds failed at N=12. The contention that matters is between our own
provisions, and serializing them removes it. The external-contention probe did **not** reproduce a failure, so there is
currently no evidence that the lock is insufficient — do not assume it needs more than this.

### 4.2 Secondary: make the retry idempotent (defence in depth)

The lock removes the trigger, but the retry is wrong independently of it: any first-attempt failure (disk, permissions,
an unrelated git process) still leaves a created branch and no worktree, and the retry then collides with that branch.

1. **Re-enter the decision, not the command**: on failure, re-run the `show-ref` branch-existence check and dispatch to
   the attach path (`worktree add "$wt_path" "$branch"`) when the branch now exists. Simplest correct shape is a small
   `_wt_add_with_retry` that re-checks state each attempt.
2. **Bounded retries with jittered backoff** (e.g. 3 attempts, 100–400 ms jitter) rather than one fixed `sleep 0.3`;
   contention scales with worker count, and a fixed delay makes collisions re-collide in lockstep.
3. **Do not swallow the last error.** The final attempt's stderr must reach the caller; today `2>&1 >/dev/null` on the
   first attempt hides the real cause and the diagnosis had to be recovered by probe.
4. **Clean up on give-up:** if all attempts fail and the branch was created by this call and has no worktree and no
   commits beyond base, delete it, so a later run does not meet a stale branch (which the P2-H gate would then refuse).

## 5. Done-criteria

1. A stress assertion at **N=12** (not 5) passes **20 consecutive** runs. N=5 was measured insufficient to expose the race.
2. The lock is provably held: a provision that sleeps inside the critical section blocks a second provision, and the
   second acquires only after the first releases. A killed provision leaves a pid-stamped lock that the next run breaks
   with a warning rather than hanging.
3. Simulated failure of the first `worktree add` (stub on `PATH`) exercises the retry and ends with the worktree
   registered on the expected branch.
4. No orphan branches: after a forced all-attempts-fail run, `git branch --list 'swarm/*'` is unchanged.
5. Full `tests/test_worktree.sh` green 10 consecutive runs.

## 6. Verification

```bash
for i in $(seq 20); do bash tests/test_worktree.sh | tail -1; done   # want 20× "N passed, 0 failed"
```

## 7. Notes

Plain `git worktree add` measured **0/12 failures** under the same concurrency in the Phase 2 advisory, so this is a
defect in the wrapper's retry logic, not in git. Phase 3 seats `arch-1 … arch-N` in one pass, so the exposure grows
with `max_workers`.
