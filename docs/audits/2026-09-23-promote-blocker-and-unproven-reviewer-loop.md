# PM Audit: Promote Blocker, Unpushed `main`, and the Unproven Reviewer Loop

**Date:** 2026-09-23
**Author:** `pm` (Claude Code)
**Scope:** Empirical audit of repo state following the Autonomous Reviewer Loop milestone (REV-1–5) and DX-1
(DOG-17/DOG-18), triggered by a driver request to review recent work and recommend next steps.

All findings below are grounded in command output run against this checkout; commands are quoted so they can be
re-run.

---

## 1. Summary judgment

The work itself is solid: 16 test suites are green on `main` (428 assertions), 18 are green on
`swarm/stampede/integration` (479 assertions, independently re-summed in an isolated detached worktree — this matches
`STATE.md`'s claimed figure exactly). CI is real, cross-platform, and has never gone red on a commit it has actually
seen. The Public Multi-Provider and Autonomous Reviewer Loop milestones both closed cleanly against that bar, and the
9/21 public-readiness Tier 1 and Tier 2 items (`LICENSE`, `.github/workflows/ci.yml`, `CONTRIBUTING.md`,
`SECURITY.md`, `PYTHON_BIN` resolver, `seats.pi.enabled = false`, the "Zero Trust" README lede) are all done.

But three things mean `STATE.md`'s "Immediate Next Step" cannot be executed as written, and one thing means the
newest shipped milestone hasn't actually been proven yet. None of these are regressions in the code — they're gaps
between "ticket resolved" and "verified in production," which is exactly the failure mode this project's whole
design exists to catch. Reported here rather than fixed silently, per "claims need receipts."

---

## 2. Finding: the documented promote will fail as written

`STATE.md` §3 says the immediate next step is to promote DOG-17/18 from `swarm/stampede/integration` to `main` via
`bin/stampede promote` / `lib/arbiter.sh promote --confirm` (`merge --ff-only`). That will fail:

```
$ git log --oneline main..swarm/stampede/integration
4025f4b feat: ci-local CI-parity wrapper with shellcheck pin check (#DOG-18)
f78b0a1 feat: single-command repo state summary script (#DOG-17)

$ git log --oneline swarm/stampede/integration..main
deadb3c docs: update STATE.md for DOG-17 and DOG-18 completion
c4ec368 docs(DOG-18): mark ci-local.sh resolved with receipts
858b7c4 docs(DOG-17): mark repo-state.sh resolved with receipts

$ git merge-base --is-ancestor main swarm/stampede/integration; echo $?
1
```

`main` has the DOG-17/18 ticket-resolution docs commits; `integration` has the DOG-17/18 code. Neither is an
ancestor of the other, so a fast-forward merge in either direction fails. This is the same shape of problem
`d7f875f` ("reconcile main base branch into integration") fixed once already. The fix is the same move: merge `main`
into `integration`, re-run `make test` on the combined tree, then promote. This is an arbiter/human action, not
something the `pm` seat should do directly — it touches `swarm/stampede/integration`, which is outside `pm`'s write
boundary.

## 3. Finding: local `main` is 5 commits ahead of `origin/main` — nothing pushed

```
$ git rev-parse main
deadb3c381c9a06dcd7ea97a697ad6c011a0cd5b
$ git rev-parse origin/main
b7c2b8d37df8029f3471deb445967c86f1a0bb92
$ git log --oneline origin/main..main
deadb3c docs: update STATE.md for DOG-17 and DOG-18 completion
c4ec368 docs(DOG-18): mark ci-local.sh resolved with receipts
858b7c4 docs(DOG-17): mark repo-state.sh resolved with receipts
c7f2d05 docs(wayfinder): release DOG-17 and DOG-18 into maps/tickets/
6855cac docs(wayfinder): stage DOG-17/DOG-18 (repo-state.sh, ci-local.sh)
```

`gh run list --branch main` confirms CI has not run on any of these five commits — its most recent entry is the
REV-5 closeout commit (`b7c2b8d`, which is `origin/main`'s current tip). The DOG-17/18 ticket-resolution state and
the STATE.md update exist only on this machine. Per `CONTEXT.md`'s Git Remote Safety invariant, pushing requires
explicit human driver approval — flagged here, not pushed.

## 4. Finding: suite health, independently re-verified

`STATE.md` claims "479 passed, 0 failed across 18 suites" on integration. Per this repo's own convention ("verify
test results from evidence, not a summary line"), re-verified by summing the per-suite grep output rather than
trusting the aggregate line:

```
$ cd $(mktemp-equivalent) && git worktree add --detach <tmp> swarm/stampede/integration
$ make test 2>&1 | grep -E '^[0-9]+ passed|All suites green'
38 33 17 15 14 24 32 33 27 39 18 13 16 28 34 43 13 42   (18 numbers)
All suites green (18)
$ # sum: 479
$ git worktree remove <tmp>   # clean, no --force
```

Sum = 479. Matches `STATE.md` exactly. `main` (16 suites, missing `test_repo_state.sh` and `test_ci_local.sh` until
promote lands) sums to 428, also 0 failed. Both figures are real.

## 5. Finding: partition/lease machinery is now live (corrects the 9/21 audit)

The 2026-09-21 public-readiness review found `partition_check` / `lease_acquire` had "no caller at all." That's no
longer true:

```
$ grep -n 'partition_check\|lease_acquire' loop-bot-herd.sh
loop-bot-herd.sh:687:  partition_check "$tf" "$REPO_DIR" || prc=$?
loop-bot-herd.sh:694:  if ! lease_acquire "$tname" "$worker" "" "-"; then
```

Both are called from the supervisor's dispatch path. Good — record the correction so the next audit doesn't
re-flag it as missing.

## 6. Finding: `arbiter_drain` is still operator-only (confirms the 9/21 audit)

```
$ grep -rn 'arbiter_drain' herdr-loop-swarm.sh loop-bot-herd.sh lib/lifecycle.sh
(no matches)
```

`arbiter_drain` is only reachable via `bash lib/arbiter.sh drain` (its own CLI dispatcher) and the test suites. This
appears to be by design per ADR 0009 (human-gated integration), but it means the pipeline needs two separate manual
steps today — drain, then promote — not one. Worth an explicit decision: is that the intended steady state, or
should drain auto-run after enqueue, leaving only promote as the human gate?

## 7. Finding: the Reviewer Loop has never been exercised on a real ticket

Five waves (REV-1 through REV-5) shipped a full autonomous review loop: config flag, dual-mode brief, verdict
protocol, state machine, telemetry, and supervisor wiring — 43 + 33 + ... assertions across the suites, all green.
But:

```
$ ls .herdr-swarm/reviews/
ls: .herdr-swarm/reviews/: No such file or directory

$ cat .herdr-swarm/session-verdicts.jsonl
{"ticket": "DOG-17", ..., "verdict": "ARCH DONE #DOG-17 f78b0a1..."}
{"ticket": "DOG-18", ..., "verdict": "ARCH DONE #DOG-18 4025f4b..." (skipped)}
{"ticket": "DOG-18", ..., "verdict": "ARCH DONE #DOG-18 4025f4b..." (green)}
```

Zero `REVIEW VERDICT` lines. Zero files in `.herdr-swarm/reviews/`. The directory that the whole milestone exists to
populate does not exist yet outside the test fixtures. This is exactly the gap the original `docs/reordered-plan.md`
warned about for the ops-tab reviewer proposal: "deferred — re-propose after M3 with evidence that the reviewer
catches something." Five waves later, that evidence still doesn't exist. It doesn't need another wave of
engineering — it needs one ticket run through `loop` mode with a real `PASS`/`BLOCK` harvested.

## 8. Doc drift (fixed in this same commit, within `pm`'s write boundary)

- `maps/universal-herdr-swarm.md` (the linked "Plan of Record") was three milestones stale — Active Frontier still
  listed the already-resolved P3-FLAKE-1, and "Not yet specified" still listed quota probing, which shipped as
  PUB-9 weeks ago. Backfilled in this commit.

## 9. Doc drift (out of `pm`'s write boundary — reported, not edited)

- `CLAUDE.md`'s Commands section says "all eight suites"; `.github/workflows/ci.yml`'s header comment says "all six
  suites." `main` has 16 suites today (18 once DX-1 promotes). Needs an arch-seat edit.
- `AGENTS.md` (untracked, Codex-facing mirror of `CLAUDE.md`, generated ~2026-09-22) will silently drift from
  `CLAUDE.md` the next time this doc changes, since nothing regenerates it. Not a ticket deliverable; flagging for
  the human driver to decide whether it's wanted.
- `CONTEXT.md` still only documents Phase 1 vocabulary (Fail-Closed, Nonce Delivery, Seat Ledger, Slug Namespacing,
  Suite Gate, Wayfinder Map, Supervisor Gate). Arbiter/CAS integration, worktree isolation, partition/lease, and the
  Reviewer Loop have no entries. Lower priority than the items above; noted for a future documentation pass.

---

## 10. Recommended sequence

1. **Reconcile `main` into `integration`, re-gate, promote DOG-17/18.** Arbiter/human action; blocks everything else
   that touches `main`.
2. **Push `main` to `origin`** once reconciled, so CI actually sees the current tip. Human-authorized per
   `CONTEXT.md`'s Git Remote Safety rule.
3. **Dispatch one real ticket through the Reviewer Loop** and confirm a genuine verdict lands in
   `.herdr-swarm/reviews/`. Do this before scoping any new milestone that assumes the loop works.
4. **Decide `arbiter_drain`'s steady state**: stays operator-only, or gets an automatic caller. Either is defensible;
   pick one and document it in ADR 0009 or a follow-up ADR.
5. **Arch-seat pass** on the CLAUDE.md/ci.yml suite-count drift (§9) — cheap, mechanical.

Only after 1–3 land does it make sense to scope new feature work. Candidates surfacing from this audit, roughly in
order of how directly they build on what's already shipped:

- Headless mode (no panes, no focus calls) — the capability that would make "autonomous" true rather than
  aspirational (9/21 review, Tier 3 #12).
- Trust-tax instrumentation — measure the five proxies named in the 9/21 review and publish real numbers instead of
  the retrospective's modeled 80% token-reduction claim.
- Auto-wire `arbiter_drain` into dispatch, closing the two-manual-step gap in §6.

This is a driver decision, not a `pm` unilateral call — flagged for direction rather than picked.
