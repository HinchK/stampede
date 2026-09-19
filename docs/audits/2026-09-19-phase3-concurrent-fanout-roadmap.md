# Phase 3 Roadmap — Autonomous Concurrent Multi-Ticket Fan-Out (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `ffd3312` · **Builds on:** P2-1 … P2-4
**Evidence:** measured against the shipped libraries in scratch repos (git 2.55.0). Numbers below are observed, not estimated.

## 0. Where Phase 2 leaves us

| Component | State | Verified here |
|---|---|---|
| P2-1 `lib/worktree.sh` | shipped | `tests/test_worktree.sh` → **21/21** |
| P2-2 config flag, ledger v2, launcher cwd ordering | shipped | seat cwd bound at `split_pane`; ledger v2 written |
| P2-3 worktree suite gating (`420d5e6`) | shipped | gate runs in the worker's tree; unresolvable ≠ root-gated |
| P2-4 `lib/arbiter.sh` (`3c4a584`) | shipped | `tests/test_arbiter.sh` → **26/26**; end-to-end drain verified below |

**Arbiter end-to-end, measured.** Three workers on disjoint files, each one green commit, a stand-in 2-second suite:
all **3 integrated**, integration tip 5 commits ahead of `main`, drain wall time **6 s**. A fourth and fifth worker
touching the same file: `104:integrated 105:conflict`, no corruption, no lost update.

Phase 2 gives us one worker at a time doing this safely. Phase 3 is about N at once, and every number below says the
same thing: **the workers are not the bottleneck — the single serialized gate is.**

### Open prerequisites (from `2026-09-19-phase2-worktree-milestone-audit.md`, all still open at `ffd3312`)

| ID | Defect | Why it blocks Phase 3 |
|---|---|---|
| H2 | `worktree_prune` deletes untracked files (`remove --force` after an `add -u` checkpoint that cannot see them) | loss probability scales linearly with worker count and cycles |
| H3 | nothing calls `worktree_prune`/`worktree_reconcile`; `down` leaves worktrees **locked** on disk | N workers × cycles = N locked trees per cycle; locks block later removal |
| H1 | ADR 0007 §C stale-branch gate unimplemented | with N seats, silently adopted stale baselines multiply conflicts |
| H5 | no provenance checks (`grep -c is-ancestor` = 0) | with N workers a mis-attributed sha is far likelier |
| H4 | ledger lacks `base_sha` / `branch_created` | H5's `own_commits` and safe `--purge` both need them |

**Gate: P3 does not start until H2 and H3 are fixed.** They are cheap, and Phase 3 multiplies both.

---

## 1. Architecture

### 1.1 Multi-worker dispatch (`arch-1 … arch-N`)

Seats become **replicable templates** rather than singletons. `swarm.config.toml`:

```toml
[seats.arch]
worktree = true
replicas = 3            # new: 1 = today's behaviour, unchanged
[fanout]
enabled = false         # Phase 3 opt-in
max_workers = 3         # concurrent implementation workers
gate_concurrency = 2    # concurrent suite gates (see §1.3)
```

`lib/config.sh` expands a replicated seat into `SEAT_KEYS` entries `arch_1 … arch_N`, each emitting the existing
`SEAT_NAME_*`/`SEAT_WORKTREE_*` variables, with names `arch-1-<slug>` (already Herdr-legal under `slugify`). Everything
downstream — provisioning, ledger v2, `resolve_seat_gate`, the arbiter — is keyed by seat name and needs **no change**.
That is the payoff of P2-2's design: fan-out is a config expansion, not a new code path.

Workers live in a dedicated `workers` tab (the 80×20 geometry floor already relocates cramped panes); `looper`, `pm`
and telemetry stay in the root anchor.

### 1.2 Partition checking at dispatch

Port `partition_check` from `loop-bot-herd-claude/herdr-loop-claude-pm.sh` into `lib/partition.sh` and run it
**before** any worker is dispatched, not at merge time.

- **Source of ownership:** an `owns:` list in each ticket's YAML frontmatter (`maps/tickets/*.md`), which `lib/gh_sync.sh`
  already parses. Paths are repo-relative; directory prefixes allowed.
- **Invariant:** for any two tickets dispatched concurrently, `owns(Ti) ∩ owns(Tj) = ∅`. Prefix overlap counts
  (`src/api/` vs `src/api/routes.py`).
- **Lease:** the ledger records the active `owns` set per worker seat. A ticket whose paths intersect a live lease is
  **not dispatched**; it waits for the frontier. Leases are released when the ticket integrates or the seat retires.
- **Fail-closed:** a ticket with no `owns` field is dispatched **alone** (treated as owning the whole repo). Guessing
  ownership from a prompt would silently re-introduce the conflicts this exists to prevent.
- `partition_check --tasks <file>` stays available as a standalone pre-flight the human can run.

This is prevention, not cure: the arbiter's conflict path (proved working) becomes the exception, not the routine.

### 1.3 Asynchronous supervisor harvesting

Today `harvest_verdicts` walks `EXPECTED_SEATS` sequentially and runs the suite **inline** (`loop-bot-herd.sh:166`,
gate at `:223`). One 5-minute gate blocks every other seat's harvest for 5 minutes — with `SUITE_TIMEOUT_S=300` and
N seats, a poll pass can stall for N×300 s.

**Change:** the gate becomes a **background job with a durable job record**, and the poll loop never blocks.

```
poll pass:
  for each seat (fast, non-blocking):
      read pane → anchored verdict lines → precheck (resolve_seat_gate, tree match, provenance)
      eligible & no job running for (ticket,sha) & running_jobs < gate_concurrency
          → spawn:  ( cd "$GATE_DIR" && TMPDIR=… timeout … sh -c "$TEST_CMD" ) >log 2>&1 ; echo $? > rc
            record .herdr-swarm/gates/<seat>-<sha7>.job {pid, started, gate_dir, sha, ticket}
  for each finished job (rc file present):
      re-run gate_tree_matches (existing TOCTOU post-check) → green|RED|invalidated
      write the verdict record, telemetry, arbiter_enqueue on green, reap the job file
```

- **Concurrency cap:** `gate_concurrency` (default 2) bounds CPU and port/DB contention (advisory H5). Workers may
  exceed it; their gates queue.
- **Crash safety:** job files are the durable state. On restart, a job whose pid is gone and whose `rc` file is missing
  is re-queued, never assumed green.
- **Per-seat TMPDIR** is already implemented and becomes load-bearing at N>1.
- **Starvation:** jobs are started oldest-verdict-first, so a fast-cycling worker cannot monopolise the gate slots.

### 1.4 Arbiter queue concurrency

**Measured ceiling:** `arbiter_drain` holds one lock across the whole loop (`lib/arbiter.sh:150-179`) and gates inside
it. Three tickets × 2 s suite = **6 s wall** — strictly serial. With a realistic 60 s suite and 6 workers, a round of
integration costs **~6 minutes**, during which the integration tip drifts further from every worker's base, which is
exactly what manufactures conflicts.

Serialization of *ref writes* is correct and must stay (CAS proved it: 1 winner, 10 loud rejections). What must change
is **how many suite runs the queue costs**. Three levers, in the order I recommend building them:

| Lever | Mechanism | Cost / risk |
|---|---|---|
| **P3-a: batch integration** (recommended first) | drain merges up to `batch_max` queued greens onto the candidate, then runs **one** gate for the batch. All-green → single CAS. RED → binary-search the batch (log₂k extra gates) and record only the culprit as `integration_red` | k tickets for ~1 gate instead of k. Bisect cost only on failure |
| **P3-b: speculative parallel gating** | gate several candidate merges concurrently in separate detached worktrees; first green wins the CAS, losers re-derive from the new tip | CPU × k; wasted work when the tip moves. Only worth it when the suite is long and conflicts are rare |
| **P3-c: scoped gating** | run the impacted subset (per-ticket `owns` → test selection) for the batch gate, full suite once before `promote` | needs a per-ecosystem mapping; weakest guarantee, so it never replaces the pre-promotion full gate |

Also fix the **head-of-line break**: `arbiter_drain` currently `break`s the whole pass when a record resolves as
conflict/RED (`:176-178`), so ready tickets behind it wait a full poll interval. Skip the resolved record and continue
the pass instead.

**Back-pressure:** when `queue_depth > max_workers`, the looper stops dispatching new tickets until the arbiter catches
up. Unbounded queue growth is what turns a conflict-free partition into a merge-conflict pile.

---

## 2. Milestones

| # | Ticket | Deliverable | Done when (measured) |
|---|---|---|---|
| **P3-0** | Hardening gate | H2, H3 (then H1, H4, H5) | untracked file survives a prune cycle; `down` leaves zero worktrees and zero stray locks |
| P3-1 | `lib/partition.sh` + `owns:` frontmatter | dispatch-time partition check and ledger leases | overlapping tickets refuse to co-dispatch; `owns`-less ticket runs alone; unit tests |
| P3-2 | Seat replicas | `replicas = N` → `arch-1..N-<slug>` seated, each in its own worktree | 3 workers seated, `git worktree list` shows 3 + root; ledger lists 3 isolated seats; zero `index.lock` errors during simultaneous commits |
| P3-3 | Async gate jobs | non-blocking harvest, `gate_concurrency`, durable job files | one 60 s gate does not delay another seat's verdict by more than a poll interval; killed supervisor re-queues, never greens |
| P3-4 | Arbiter batching (P3-a) + no head-of-line break | batch merge, single gate, bisect on RED | 6 queued greens integrate in ~1 gate; an injected bad ticket is isolated by bisect; conflict record no longer stalls the pass |
| P3-5 | Back-pressure + fan-out status | dispatch throttle on queue depth; `status` shows workers, leases, queue depth, integration lag | queue depth stays ≤ `max_workers` under sustained load |
| P3-6 | Live dogfood | N=3 on a real map, end to end | 3 tickets dispatched, gated, integrated, one promotion PR; transcript attached |

**Suggested defaults on first run:** `max_workers = 2`, `gate_concurrency = 1`, `batch_max = 4`. Raise only with a
measurement attached.

---

## 3. Risks

- **Cost amplification.** N workers × frontier models, plus speculative gating if P3-b lands. Record tokens per ticket
  in telemetry before raising `max_workers`. Route `docs`/`mechanical` tiers to cheaper models.
- **Semantic conflicts.** Partitioning prevents *file* overlap only. Two workers can still break each other through a
  shared API — the 6 s probe's integration gate is the backstop, and P3-a's bisect is how the culprit is found.
- **Disk.** Each worktree is a full checkout plus its own `node_modules`/`.venv`. Preflight should check free space
  against N × working-tree size before seating.
- **Human legibility.** N worker panes plus ops overflow the floor. Dedicated `workers` tab; `status` becomes the
  primary view, not the panes.
- **Debuggability.** With N concurrent gates, "which tree produced this green?" must be answerable from the record —
  audit finding H6 (gated-tree fields in verdicts and telemetry) becomes a requirement at N>1, not a nicety.

## 4. Decisions needed from the driver

1. **Approve the P3-0 gate** — no fan-out work until H2/H3 are fixed.
2. **Ticket ownership source:** `owns:` frontmatter on map tickets (recommended) vs a separate tasks file.
3. **Integration strategy:** batch-then-bisect (P3-a, recommended) vs speculative parallel gating (P3-b) as the first lever.
4. **Initial `max_workers`** — recommend 2, with the first real measurement deciding whether 3+ pays for itself.
