# Headless live proof — HORIZON-2

**Date:** 2026-10-05 · **Runner:** arch-2 seat, interactively dispatched (HORIZON-2 never released to
`maps/tickets/` as a backlog item, per the corrected execution plan)
**Target:** THIS repository, root checkout on `main` @ `4d90e46`, with 7 live interactive seats seated
and the real vendor CLI (opencode) — no stubs anywhere.

## Outcome in one line

The live proof ran for real and **failed honestly twice, in ways hermetic suites structurally cannot
see** — which is exactly what this ticket existed to find. The dead-letter path carried the failure with
full diagnostics, HL-LEDGER-1's namespacing held byte-identical under a live swarm, and both defects now
have one-line fixes on the seat branch. Per this ticket's Done-Criteria ("a real RED with receipts also
proves the safety caps"), the failure path **is** the proof; the green path is one promote away.

## Pre-flight (plan steps 1–4, all verified — not assumed)

- HL-LEDGER-1 (`19135fe`) ancestor of `main` ✓ and `origin/main` ✓
- HL-CONFIG-1 (`.opencode/opencode.json`, `2cf79c0`) ancestor of `main` ✓
- Root checkout: `main` @ `4d90e46`, clean tree, contains both ✓
- No supervisor process running; no risk of double dispatch (looper interactive-only)
- `maps/tickets/` at run time: exactly ONE backlog ticket — `hl-tgt-1-drain-claim-freshness.md`
  (written for this proof: a one-paragraph staleness fix in `docs/dogfood/public-readiness.md`,
  `owns:` disjoint from everything live)
- Integration queue: zero queued records; leases: only HORIZON-2 itself
- Snapshots of `seats.json` + `leases.json` taken before both runs
- `herdr` confirmed off PATH (staged symlink bin dir; `command -v herdr` fails in the run env; git,
  jq, python3 (tomllib), timeout, make, opencode all present)

## Run 1 — blocked by stale nested worktree residue (live finding #1)

```
$ bin/stampede headless /Users/hinchk/Fun/stampede --max-tickets 1     [herdr off PATH]
headless: worktree provision failed for arch_1 — refusing to run on the root checkout
exit 1, 1 second
```

HL-WT-1's rc propagation worked live: refusal was loud, no phantom path, no 0-dispatched green exit.
The underlying git error (surfaced by manual repro):

```
fatal: 'swarm/hinchk-stampede/arch_1' is already used by worktree at
  '.herdr-swarm/worktrees/arch-1-hinchk-stampede/.herdr-swarm/worktrees/arch_1'
```

A **nested stale worktree** — a previous headless run had been executed with arch-1's WORKTREE as the
target dir, provisioning `…/arch-1-hinchk-stampede/.herdr-swarm/worktrees/arch_1` on branch
`swarm/hinchk-stampede/arch_1` (locked, clean, 0 unmerged commits, no process). The branch is a global
ref: any headless run for slug+seat collides with it from any directory. Removed per the git safety
rules (unlock → plain `worktree remove`, no force; `branch -d`, not `-D`; both verified safe first).
**Lesson for the design doc:** headless worktree/branch names are slug-global — running headless from
inside a seat worktree nests state and strands refs.

## Run 2 — real dispatch, real worker, honest dead-letter (live finding #2)

```
2026-10-05 17:39:04 → 17:39:13 (9s)
$ env PATH=<herdr-free> bash bin/stampede headless /Users/hinchk/Fun/stampede --max-tickets 1
headless: /Users/hinchk/Fun/stampede — 1 dispatchable ticket(s), cap 1, budget 1800s, worker headless-arch-1-hinchk-stampede (opencode)
headless: dispatching #HL-TGT-1 → headless-arch-1-hinchk-stampede (brief: …/maps/tickets/hl-tgt-1-drain-claim-freshness.md, worktree: …/worktrees/arch_1)
headless: #HL-TGT-1 UNCONCLUDED (last state: none)
headless: #HL-TGT-1 did not conclude — dead-lettering: worker exited rc=1 without a verdict — worker log: /Users/hinchk/Fun/stampede/.herdr-swarm/logs/headless-arch-1-hinchk-stampede.log
headless: batch done — 1 dispatched, 1 dead-letter record(s) this session
headless: DEAD LETTERS present — see /Users/hinchk/Fun/stampede/.herdr-swarm/dead-letter.jsonl
exit 1
```

Dead-letter record (verbatim from `.herdr-swarm/dead-letter.jsonl`):

```json
{"ts":1791247152,"session":"swarm-20260919-114508","ticket":"HL-TGT-1","sha":"4d90e46","reason":"worker exited rc=1 without a verdict — worker log: /Users/hinchk/Fun/stampede/.herdr-swarm/logs/headless-arch-1-hinchk-stampede.log"}
```

No session-verdict record for HL-TGT-1 (correct — the worker never verdicted). Note the batch output
demonstrating two prior fixes live: the **namespaced worker** (`headless-arch-1-hinchk-stampede`,
HL-LEDGER-1) and the **honest dead-letter reason with log pointer** (HL-DOCS-1).

The worker log held the real cause, exactly where the pointer said:

```
Error: { "name": "UnknownError", … "ref": "err_ab8473f8" }  [_exit_ rc=1]
```

and `opencode run --print-logs` from the headless worktree resolved it to:

```
ProviderModelNotFoundError: Model not found: zai/glm-5.3.
Did you mean: glm-5.3, glm-5.3-flash, glm-5.3-flashx?
```

**Live finding #2: the prerequisite config's pinned model id is stale.** HL-CONFIG-1 pinned
`zai/glm-5.3`; the working provider id today is `zai-coding-plan/glm-5.3` (verified live:
`opencode run -m zai-coding-plan/glm-5.3` → `pong`). Provider-prefix drift is invisible to hermetic
suites (stubs don't resolve models) and to interactive seats (herdr-wrapped opencode uses its own
config). Fix committed on this branch: `.opencode/opencode.json` → `"zai-coding-plan/glm-5.3"`. Once
promoted, the green path is unblocked.

## The ledger receipt (plan step 6) — HL-LEDGER-1 holds live

All 7 live interactive seats (pm, arch-1, arch-2, looper, agy-docs, agy-gh, reviewer — real panes
`wW:p4…pH`) are **byte-identical before and after** the batch (semantic diff over
name/pane/worktree_dir/branch/kind/isolated: identical). The only seats.json changes: the appended
`headless-arch-1-hinchk-stampede` entry and a cosmetic pretty-print re-serialization of the file (the
batch's jq rewrite; values untouched). `leases.json` identical — the dead-letter released HL-TGT-1's
lease correctly, and HORIZON-2's own lease was never touched.

```
+ { "name": "headless-arch-1-hinchk-stampede", "kind": "opencode", "pane": "",
+   "worktree_dir": "…/.herdr-swarm/worktrees/arch_1", "branch": "swarm/hinchk-stampede/arch_1",
+   "isolated": true }
```

## Follow-up defect noticed, not fixed (out of this ticket's owns)

`dead-letter.jsonl` counting is scoped to the **stable per-project telemetry session id**
(`swarm-20260919-114508` — unchanged since 2026-09-19). On a repo with any historical dead letter, a
later all-green headless batch would still exit 1, because `headless_deadletter_count` counts every
record ever written under that session. Scratch repos never see this (fresh session per state dir);
this live repo did. Needs its own ticket (per-batch scoping, e.g. session-per-run or a since-marker).

## Reviewer boundary (plan step 8, stated plainly)

Nothing in this proof went through the reviewer loop — the target ticket dead-lettered before any
verdict, and HL-TGT-1's actual fix landed as normal interactive seat work (reviewed through the normal
pipeline, not presented as headless-reviewed). Headless batches skip review by design; HORIZON-3 owns
whether that changes.

## Cleanup (plan step 9)

- Target ticket removed from the root checkout's queue (it was never committed to `main`; recorded on
  this branch with `status: done` and the actual doc fix).
- Nested stale worktree + branch removed (run 1 unblock), receipts above.
- The headless worker's own worktree/branch (`worktrees/arch_1`, `swarm/hinchk-stampede/arch_1`) left
  in place: provisioned state for idempotent reuse by the next batch.
- Model-id fix committed on this branch, awaiting the normal integrate → promote cycle; the green-path
  rerun is a one-command follow-up after promotion.
