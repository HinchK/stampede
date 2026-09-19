# Phase 2 Worktree Swarm — Milestone Audit (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `36c927a` · **Scope:** P2-1 … P2-4
**Method:** every claim below was re-derived by running the shipped code against scratch repos (git 2.55.0). No worker
self-report was accepted. Evidence key: **[probed]** = executed here; **[inspection]** = read, not run.

## Verdict

**P2-1 → P2-3 are implemented and materially correct. P2-4 is specified but unbuilt. The whole path is still
unexercised on a live herd.**

The headline result is that the structural false green is gone: the same failing test now returns **RED in the worker's
worktree (rc=1)** where the pre-P2-3 root gate returned **green (rc=0)** [probed]. The prior audit's data-loss bug
(`worktree add -B` wiping seat branches) is fixed and verified. Four defects remain, one of which destroys worker files
(H2) and one of which leaves every worktree behind at teardown (H3).

| Ticket | State | Evidence |
|---|---|---|
| P2-1 `lib/worktree.sh` | ✅ shipped | 21/21 tests pass [probed]; branch preservation verified |
| P2-2 config / ledger v2 / launcher cwd | ✅ shipped | config binding, `seats.json` v2 writer, `split_pane` cwd ordering [probed + inspection] |
| P2-3 supervisor gating (`420d5e6`) | ✅ shipped, 2 gaps | A3 proof [probed]; provenance V2/V3 absent |
| P2-4 arbiter | ⚠ **spec only** | `lib/arbiter.sh` does not exist; ticket `status: in_progress` |

---

## P2-1 — Worktree lifecycle library

- **Tests:** `bash tests/test_worktree.sh` → **21 passed, 0 failed** [probed].
- **Branch preservation (the fix):** `-B` is gone (`lib/worktree.sh:58-61`): attach when `refs/heads/<branch>` exists,
  `-b` when it doesn't. Probe: a seat branch 1 commit ahead of `main`, worktree removed, re-provisioned → **still 1 ahead**.
  The previous audit measured 20 → 0 on the same sequence. **Data loss closed.**
- **Root inviolability:** `worktree_prune` refuses when the path resolves to the target root (`:107-111`) [inspection].
- **Checkpointing:** dirty *tracked* work is committed via `git add -u` (never `-A`, per advisory H8) onto a
  `…-checkpoint-<ts>` marker ref before removal [inspection].

**H1 — MED [probed]: ADR 0007 §C's stale-branch gate was never implemented.** `worktree_provision` attaches to any
existing seat branch with no staleness test. Probe: a seat branch carrying an unmerged commit from an earlier run is
adopted silently, `rc=0`, and the only message printed is the unrelated git-ignore warning. Work is safe (that was the
`-B` bug), but a worker silently inherits a stale baseline — the exact H3 hazard ADR 0007 §C accepted a fix for.
Expected: refuse with `stale branch … (N commits not on <base>)` unless `--adopt-branches`.

**H2 — MED [probed]: `worktree_prune` deletes untracked worker files.** Tracked dirt is checkpointed, then step 3 runs
`git worktree remove --force` (`:133`). Untracked files are never staged by `add -u`, so `--force` deletes them.
Probe: an untracked `test_uncommitted_new.py` in the seat worktree → after prune, **file gone**; the committed commit
survived. A brand-new test file a worker wrote but never `git add`ed is the common case. ADR 0007 §B ("without
`--force`") is not satisfied by a checkpoint that cannot see untracked files.
**Fix:** refuse to prune when non-ignored untracked files exist (report and retain), or copy them to
`.herdr-swarm/salvage/<seat>-<ts>/` before removing. Do not widen the checkpoint to `add -A` — H8 exists for a reason.

---

## P2-2 — Config binding, ledger v2, launcher cwd

- `swarm.config.toml`: `worktree_root = ".herdr-swarm/worktrees"`, `[seats.arch] worktree = true` [inspection].
- `lib/config.sh`: emits `SWARM_WORKTREE_ROOT` and `SEAT_WORKTREE_<key>=1|0`, rejects non-boolean values and refuses
  `worktree = true` on root anchors, both as specified (`:126,148-153`) [inspection].
- **Seating order is correct** — the point the spec was written to protect. `worktree_provision` runs at `:424-429`
  **before** `split_pane … "$seat_cwd"` (`:450-452`), so the pane (and therefore the agent, which has no `--cwd`)
  starts inside the worktree [inspection].
- **Ledger v2** written at `:479-516` with `{version: 2, workspace_id, seats:[{name, kind, pane, worktree_dir, branch,
  isolated}]}` [inspection], and consumed by the supervisor (below).
- Re-`up` idempotence: a live isolated seat's worktree is recovered from `git worktree list --porcelain` rather than
  re-provisioned (`:442-446`) [inspection].

**H4 — LOW: ledger v2 omits `target_dir`, `base_branch`, `base_sha`, `branch_created`.** P2-4 needs `base_sha` (the CAS
baseline and the `own_commits` denominator) and `branch_created` (so a future `--purge` deletes only herd-created
branches). Cheapest to add now, while the writer is the only producer.

---

## P2-3 — Supervisor worktree suite gating (`420d5e6`)

Implemented as specified:

- `resolve_seat_gate` (`loop-bot-herd.sh:132-149`) reads `seats.json`, and for an isolated seat requires both that
  `worktree_dir` exists and that its HEAD is on the ledger's `branch`, else returns 1 [probed: resolves `arch-myproj` →
  its worktree; root seat → repo root].
- **Fail-closed, never root-gated:** with the worktree deleted, resolve returns **1 → `unresolvable`** and no suite runs
  [probed]. This is the single most important safety property, since the fallback would have been a false green.
- **Execution directory + TOCTOU:** the suite runs in `GATE_DIR` with a per-seat `TMPDIR` and a kept log (`:223`);
  `gate_tree_matches` requires `HEAD == sha` **and** an empty `status --porcelain` (untracked included) before the run
  (`stale`) and again after it (`invalidated`) (`:212, :229`) [inspection].
- **Dedupe:** drift records (`stale`/`invalidated`/`unresolvable`) are excluded from `(ticket, sha)` dedupe (`:187`), so
  a re-verdict at the same sha from a clean tree is still gated [inspection].

**A3 proof [probed]:** a commit that breaks a check only in the worker's worktree →
`gate in WORKTREE rc=1 (RED)` vs `same gate in ROOT rc=0 (green)`. Pre-P2-3 behaviour would have filed that ticket green.

**H3 — MED [probed]: nothing ever prunes worktrees, and `down` doesn't know about them.** `lib/lifecycle.sh` contains no
worktree logic, and `worktree_prune`/`worktree_reconcile` have **no callers** — `herdr-loop-swarm.sh:27` sources the
library only for `worktree_provision`. So `down` closes panes and leaves every worktree on disk, **locked**
(`worktree lock` is the live-seat marker). The locks then block later `git worktree remove`, and `git worktree prune`
skips locked entries by design. Each `up`/`down` cycle accrues another locked tree. This is the P2-2 spec §3.4 table
and ADR 0006 §4.D, neither implemented.

**H5 — MED [probed]: verdict provenance (spec V2/V3) is absent.** Only V1 (`cat-file -e`, `:194`) is implemented;
`grep -c is-ancestor loop-bot-herd.sh` = **0**. The `HEAD == sha` precondition blocks the naive spoof (citing another
seat's sha fails the tree check), so the residual hole is narrower than in the spec: a seat whose branch is reset to
the base tip can verdict a clean tree with **zero own commits** and be gated green against unchanged code — a ticket
retired with no work. Add V3 (`rev-list --count <base_sha>..<sha>` ≥ 1) and V2 (`merge-base --is-ancestor <sha>
<branch>`); V3 is the one that matters and needs `base_sha` from H4.

**H6 — LOW: records and telemetry omit the gated tree.** Verdict records carry `log` but not `worktree_dir`, `branch`,
`isolated`, `gate_cwd`, `exit_code` or `duration_s`; the `suite.verdict` payload likewise (`:251-254`). Nobody can audit
*which* tree produced a green after the fact — the field that would have made this audit a one-liner instead of a probe.

---

## P2-4 — Arbiter architecture evaluation (design review; nothing shipped)

`lib/arbiter.sh` does not exist; `maps/tickets/…arbiter….md` is `status: in_progress` and restates the PM spec.
Evaluated against the concurrency invariants measured in the advisory:

| Invariant | Spec's answer | Assessment |
|---|---|---|
| Lost updates on a shared ref (probe: 11/12 updates silently lost) | CAS `update-ref <ref> <new> <old>`, retry ≤3, serialized by a `mkdir` lock | ✅ Correct. CAS was measured to reject losers loudly (1 winner, 10 rejections). |
| Never move a checked-out branch (probe: `update-ref` on checked-out `main` left the root staging a reversal) | arbiter writes only `swarm/<slug>/integration`; its own worktree is **detached**; `main` moves only by human `merge --ff-only` **in the root**, or PR | ✅ Correct, and stricter than `docs/worktree-swarm.md` §7 Rule 1, which still says "fast-forward merge or squash into `main`". That doc needs the amendment. |
| Green-per-branch ≠ green-combined | merge candidate is gated **before** the ref advances | ✅ Correct, and the reason not to advance-then-test. |
| Integrate what was tested | integrates the **gated sha**, not the branch tip | ✅ Correct; depends on P2-3's `HEAD == sha` precondition, which is shipped. |
| Data loss | arbiter never writes seat branches, never `--force`, never rebases; branches deleted only by human `--purge` after reaching `main` | ✅ Correct in design — but it **rests on H1/H2/H3**: an un-pruned locked worktree, a silently adopted stale branch, or a `--force` prune that eats untracked files all break the premise that un-integrated work waits safely. |
| Conflict handling | `merge --abort`, worker resolves on its own branch, re-verdict; 2 strikes → `blocked` | ✅ Keeps the gate/provenance chain intact. |

**Readiness call:** the design is sound and I would green-light implementation **after H1–H3 are fixed**, in that order.
Building the arbiter on top of a teardown that abandons locked worktrees and a provisioner that adopts stale branches
would hand it exactly the inputs it assumes cannot happen. H5 (V3) should land with it, since the arbiter is what turns
a green verdict into merged code.

**Sequencing note:** P2-4's ticket is already `in_progress` while its three prerequisites are open. Recommend
re-ordering to: H2 → H3 → H1 (+H4 fields) → P2-4 → H5/H6.

---

## Cross-cutting: documentation drift

- `README.md:81` and ADR 0006 §4.D.3 / §6 still describe teardown as `git worktree remove --force`, superseded by
  ADR 0007 §B. ADR 0006 has no amendment banner pointing at 0007.
- `docs/worktree-swarm.md` §7 Rule 1 still permits the arbiter to fast-forward or squash straight into `main`,
  contradicted by the probe in the P2-4 spec §2.3.
- The README's Phase 2 section presents the advisory's scratch-repo benchmark (0/240, 4/6) as the system's own
  performance. Those numbers measured **git**, not this swarm. Attribute them, or a future reader will cite them as a
  herd benchmark.

## Live-exercise status (unchanged since the M3 audit)

`/Users/hinchk/Fun/loop-bot-herd-agy/.herdr-swarm/` holds `profile.env`, `control.json`, `traces/`, `channel/` — **no
`seats.json`**. With `worktree = true` set on arch, the isolated path has still never run on this herd: no `swarm/*`
branch, no worktree, no verdict has ever passed through `resolve_seat_gate` outside the probes in this audit.
Everything above is verified at unit level against scratch repos. **The end-to-end dogfood remains the gating step
before Phase 2 can be called delivered.**

## Recommendations

1. **H2 (untracked-file loss)** — the only defect that destroys human-visible work. Refuse or salvage; never `--force` past untracked files.
2. **H3 (no pruning, locks accumulate)** — wire `worktree_prune` into `swarm_down` per P2-2 spec §3.4, state-by-state.
3. **H1 (stale-branch gate)** — implement ADR 0007 §C, or amend the ADR to say attach-without-reset is the accepted behaviour. Do not leave the ADR asserting a control that does not exist.
4. **H4 + H5** — add `base_sha`/`branch_created` to the ledger, then V3 `own_commits`.
5. **Dogfood:** `up -m s` in a scratch repo with an isolated arch, one real `ARCH DONE #n <sha>` through the gate, then `down`. Attach the transcript.
6. **Doc pass:** amend ADR 0006, `docs/worktree-swarm.md` §7, `README.md:81`, and attribute the benchmark numbers.
7. **H6** — add the gated-tree fields to verdicts and telemetry.
