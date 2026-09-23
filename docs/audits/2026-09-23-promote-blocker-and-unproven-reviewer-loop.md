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
$ git worktree add --detach "$CLAUDE_JOB_DIR/tmp/integ" swarm/stampede/integration
$ cd "$CLAUDE_JOB_DIR/tmp/integ" && make test 2>&1 | grep -E '^[0-9]+ passed|All suites green'
38 33 17 15 14 24 32 33 27 39 18 13 16 28 34 43 13 42   (18 per-suite counts)
All suites green (18)
$ cd - && git worktree remove "$CLAUDE_JOB_DIR/tmp/integ"   # clean, no --force
```

Sum of the 18 per-suite counts = **479**. Matches `STATE.md` exactly. The same grep-and-sum against `main` (16
suites — missing `test_repo_state.sh` and `test_ci_local.sh` until promote lands) gives 38+33+15+14+24+32+33+27+39+
18+13+16+28+43+13+42 = **428**, also 0 failed. Both figures are real, re-derived independently rather than trusted
from the "All suites green" summary line.

## 5. Finding: partition/lease machinery is live, confirming DOG-16 (already recorded)

The 2026-09-21 public-readiness review found `partition_check` / `lease_acquire` had "no caller at all." That gap
was closed the same day: DOG-16 ("Wire partition checking and lease acquisition into supervisor dispatch",
`280ae5f`, recorded in `maps/public-readiness.md`) wired `cmd_dispatch` to resolve the ticket and acquire through
`lease_acquire`'s locked section before any prompt. Re-confirmed live here, independent of that record:

```
$ grep -n 'partition_check\|lease_acquire' loop-bot-herd.sh
loop-bot-herd.sh:687:  partition_check "$tf" "$REPO_DIR" || prc=$?
loop-bot-herd.sh:694:  if ! lease_acquire "$tname" "$worker" "" "-"; then
```

Both are called from the supervisor's dispatch path. This is a confirmation, not a new correction — noted here only
because it's easy to mis-cite the 9/21 finding as still current if you don't check `public-readiness.md` first.

## 6. Finding: `arbiter_drain` is still operator-only (confirms the 9/21 audit)

```
$ grep -rn 'arbiter_drain' herdr-loop-swarm.sh loop-bot-herd.sh lib/lifecycle.sh
(no matches)
```

`arbiter_drain` is only reachable via `bash lib/arbiter.sh drain` (its own CLI dispatcher) and the test suites. This
appears to be by design per ADR 0009 (human-gated integration), but it means the pipeline needs two separate manual
steps today — drain, then promote — not one. Worth an explicit decision: is that the intended steady state, or
should drain auto-run after enqueue, leaving only promote as the human gate?

## 7. Finding: the Reviewer Loop has never been exercised — because it's still switched off

Five waves (REV-1 through REV-5, 43+33+... assertions across the suites, all green) shipped a full autonomous
review loop: config flag, dual-mode brief, verdict protocol, state machine, telemetry, and supervisor wiring. But:

```
$ ls .herdr-swarm/reviews/
ls: .herdr-swarm/reviews/: No such file or directory

$ cat .herdr-swarm/session-verdicts.jsonl
{"ticket": "DOG-17", ..., "verdict": "ARCH DONE #DOG-17 f78b0a1..."}
{"ticket": "DOG-18", ..., "verdict": "ARCH DONE #DOG-18 4025f4b..." (skipped)}
{"ticket": "DOG-18", ..., "verdict": "ARCH DONE #DOG-18 4025f4b..." (green)}
```

Zero `REVIEW VERDICT` lines. Zero files in `.herdr-swarm/reviews/`. The root cause is mechanical, not architectural:

```
$ sed -n '/\[reviewer\]/,/^\[/p' swarm.config.toml
[reviewer]
loop = false          # keeps the reviewer advisory: nothing harvested
max_rounds = 2

$ sed -n '/\[seats\.reviewer\]/,/^$/p' swarm.config.toml
[seats.reviewer]
...
enabled = false
```

`[reviewer].loop` and `[seats.reviewer].enabled` were never flipped after REV-5 shipped, so the reviewer seat isn't
even in the current `.herdr-swarm/seats.json` ledger (confirmed: only `pm`, `arch-1`, `arch-2`, `looper`, `agy-docs`,
`agy-gh` are seated today). `briefs/reviewer.in.md` was already rewritten for this by PUB-8 — the seat is ready to
go, just off. This is exactly the gap the original `docs/reordered-plan.md` warned about for the ops-tab reviewer
proposal: "deferred — re-propose after M3 with evidence that the reviewer catches something." Five waves later, that
evidence still doesn't exist, and it can't until these two flags flip and one ticket actually runs through `loop`
mode.

## 8. Doc drift (fixed in this same commit, within `pm`'s write boundary)

- `maps/universal-herdr-swarm.md`'s **root-map-level** decisions (`P3-FLAKE-1`, `#BASH32-FLOOR`, `#TEST-AGG`,
  `#PROFILE-MAKE`, `#ARB-STR`, `#PROXY-GATE`, `#PM-BRANCH-RECON` — confirmed via each ticket's own
  `parent:` field) were genuinely missing from its Decisions so far, and its Active Frontier still listed the
  already-resolved `P3-FLAKE-1`. Fixed. **Correction to an earlier draft of this audit:** the Public Multi-Provider
  (PUB-1..11), Autonomous Reviewer Loop (REV-1..5), and public-readiness (DOG-1..18, including DOG-17/18) decisions
  are *not* missing — they were already correctly recorded in their own per-milestone sub-maps
  (`maps/public-multi-provider.md`, `maps/autonomous-reviewer-loop.md`, `maps/public-readiness.md`, per each
  ticket's `parent:`). PUB-9 (quota probing) landed 2026-09-22, one day before this audit, not "weeks ago" as an
  earlier draft claimed. The root map now carries one pointer line to each sub-map instead of duplicating their
  content.

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

0. **Fold this audit's own branch (`worktree-pm-audit-2026-09-23`) into `main` first.** It carries this doc plus the
   `maps/universal-herdr-swarm.md` fix, based off `origin/main` — not off local `main`'s current tip. If it lands
   *after* the reconcile below instead of before, `main` diverges from `integration` again immediately.
1. **Reconcile `main` into `integration`, re-gate, promote DOG-17/18.** Precedent: the equivalent-shaped fix last
   time (`d7f875f`) was committed by the human driver directly, not an agent seat — worth continuing that pattern
   rather than assuming an arch/looper ticket. Blocks everything else that touches `main`.
2. **Push `main` to `origin`** once reconciled, so CI actually sees the current tip. Human-authorized per
   `CONTEXT.md`'s Git Remote Safety rule.
3. **Dispatch one real ticket through the Reviewer Loop** and confirm a genuine verdict lands in
   `.herdr-swarm/reviews/`. **Sequencing note:** the supervisor and launcher run from the root checkout on `main`
   (no supervisor process is currently running — `ps aux` confirms — so nothing has read a config change yet), so a
   `swarm.config.toml` flip made on an arch worktree branch only takes effect once it's gone through the same
   reconcile → drain → promote pipeline as item 1. This step is **blocked by** item 1, not parallel to it. A
   doc-only ticket used as the guinea pig would only exercise the `PASS`/harvest path, not `BLOCK` → refine
   (REV-2/REV-3) — worth picking a ticket with at least one plausible finding, or accepting that a clean PASS alone
   isn't proof of the whole loop.
4. **Decide `arbiter_drain`'s steady state**: stays operator-only, or gets an automatic caller. ADR 0009 locks
   *promote*-to-`main` as sovereign-human forever but does not decide *drain* (which only advances the integration
   ref, not `main`) — so this is a genuinely open decision, not something ADR 0009 already settled. Either answer is
   defensible; pick one and record it.
5. **Arch-seat pass** on the CLAUDE.md/ci.yml suite-count drift (§9) — cheap, mechanical.

Only after 1–3 land does it make sense to scope new feature work. Candidates surfacing from this audit, roughly in
order of how directly they build on what's already shipped:

- Headless mode (no panes, no focus calls) — the capability that would make "autonomous" true rather than
  aspirational (9/21 review, Tier 3 #12).
- Trust-tax instrumentation — measure the five proxies named in the 9/21 review and publish real numbers instead of
  the retrospective's modeled 80% token-reduction claim.
- Auto-wire `arbiter_drain` into dispatch, closing the two-manual-step gap in §6.

This is a driver decision, not a `pm` unilateral call — flagged for direction rather than picked.
