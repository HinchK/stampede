# P3-3 Spec — Asynchronous Supervisor Multi-Worker Harvesting (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `1872747` · **Target:** `loop-bot-herd.sh`
**Implements:** Phase 3 roadmap §1.3 · **Depends on:** P3-1 roster expansion (landed, `b62faf1`), P3-2 leases (spec'd),
P2-3 gating, P2-4 arbiter. **Evidence:** measured against the shipped code; numbers are observed.

## 0. The problem, measured

`harvest_verdicts` walks `EXPECTED_SEATS` sequentially (`loop-bot-herd.sh:166`) and runs the suite **inline**
(`:223`). The roster is already config-driven (`:62-66` expands `SEAT_KEYS`), so P3-1's `arch-1 … arch-N` land in that
loop automatically — which is exactly what makes the blocking bite:

- One gate blocks every later seat in the pass. With `SUITE_TIMEOUT_S=300` and N seats, a pass can stall **N × 300 s**.
- Measured on the arbiter, which has the same shape: three tickets × a 2 s suite drained in **6 s** — strictly serial.
- A worker that finishes during someone else's gate waits for the next poll (`POLL_S=30`) *plus* the remaining gates.

Phase 3's throughput ceiling is this loop, not the workers.

**Platform constraint:** system bash here is **3.2.57**, and the scripts use `#!/usr/bin/env bash`, so they may run
under 3.2. `wait -n`, associative arrays and `declare -A` are unavailable. Completion must be detected by **polling
result files**, not by shell job control.

## 1. Architecture: from "loop that blocks" to "scheduler that polls"

A poll pass becomes three fast, non-blocking phases. Nothing in a pass ever waits on a suite run.

```
cmd_once:
  A. SCAN     every seat: read pane → anchored verdicts → precheck → maybe SPAWN a gate job
  B. REAP     every finished job: post-check → verdict record → telemetry → arbiter_enqueue
  C. SETTLE   arbiter drain (backgrounded), lease reconciliation, back-pressure report
```

### A. Scan (per seat, bounded work)

For each seat in the roster, in order: `herdr agent read` → anchored `ARCH DONE #<n> <sha>` lines → for each candidate:

1. dedupe against `session-verdicts.jsonl` and against **running jobs** for the same `(ticket, sha)`;
2. `resolve_seat_gate` (P2-3) → `GATE_DIR`/`GATE_BRANCH`, or record `unresolvable` and move on;
3. `gate_tree_matches` pre-check → or record `stale` and move on;
4. if `running_jobs < gate_concurrency`: **spawn** (below). Otherwise leave the verdict unharvested; the next pass
   reconsiders it. Nothing is lost, because the pane line and the ledger are the source of truth, not in-memory state.

Scan never runs a suite, so its cost is one `herdr agent read` per seat plus jq — flat in N.

### B. Gate jobs (the core change)

```bash
gate_spawn() {  # SEAT TICKET SHA GATE_DIR
  local jid="${2}-${3:0:7}" jdir="${STATE_DIR}/gates"
  mkdir -p "$jdir" "${STATE_DIR}/gate-tmp/$1"
  (
    cd "$4" || exit 127
    TMPDIR="${STATE_DIR}/gate-tmp/$1" timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD" \
      >"$jdir/$jid.log" 2>&1
    printf '%s' "$?" > "$jdir/$jid.rc.tmp" && mv "$jdir/$jid.rc.tmp" "$jdir/$jid.rc"
  ) &
  # one record per job, pid included; written AFTER the fork so the pid is known,
  # and atomically so a reaper never sees a half-written job file
  jq -cn --arg s "$1" --arg t "$2" --arg sha "$3" --arg d "$4" \
         --arg st "$(date -u +%FT%TZ)" --argjson pid "$!" \
    '{seat:$s, ticket:$t, sha:$sha, dir:$d, start_time:$st, pid:$pid}' \
    > "$jdir/$jid.job.tmp" && mv "$jdir/$jid.job.tmp" "$jdir/$jid.job"
}
```

Job record at `.herdr-swarm/gates/<seat>-<sha7>.job`:

```json
{"seat":"arch_1-repo","ticket":"P3-3","sha":"4e5f6a7…","dir":"/abs/.herdr-swarm/worktrees/arch_1",
 "start_time":"2026-09-19T14:05:00Z","pid":48213}
```

- **`rc` is written atomically** (`tmp` + `mv`) and is the *only* completion signal. A half-written rc is impossible,
  so a reaper never reads a partial exit code.
- **One job per `(ticket, sha)`**, keyed by the job id. A duplicate verdict line cannot spawn a second run.
- **Logs are kept per job** (`<jid>.log`) and the path goes into the verdict record — the audit trail that Phase 2's
  H6 asked for, now mandatory because N concurrent gates make "which run produced this?" ambiguous.
- **`gate_concurrency`** (config, default 2) bounds CPU, ports and DB contention. Workers may outpace it; gates queue.
- **Fairness:** candidates are spawned oldest-verdict-first across seats, so a fast-cycling worker cannot starve a slow one.

### C. Reap (no `wait`, no blocking)

For each `<jid>.rc` present:

1. read `rc`; re-run `gate_tree_matches` → **`invalidated`** if the tree moved during the run (P2-3's post-check,
   unchanged and still essential — it is what makes a background gate trustworthy);
2. `rc == 0` → `green`; else → `RED`;
3. write the verdict record **including `worktree_dir`, `branch`, `gate_cwd`, `exit_code`, `duration_s`, `log`**;
4. telemetry `suite.verdict`; on green, `arbiter_enqueue <ticket> <seat> <sha>`;
5. delete `.job` and `.rc` (keep `.log`).

**Crash recovery.** On startup, for every `.job` without an `.rc`: if the job record's `pid` is dead, the run died with the
supervisor — delete the job and re-harvest the verdict next pass. **Never infer green from a missing rc.** A job whose
pid is alive is adopted as-is (it is a detached child of the previous supervisor; its `rc` write still lands).

**Timeout hygiene.** `timeout` returns 124 on expiry, which is simply a non-zero `rc` ⇒ `RED` with a log showing the
truncation. A hung suite therefore cannot wedge the loop; it occupies one gate slot for at most `SUITE_TIMEOUT_S`.

## 2. Integration with leases and the arbiter

### 2.1 Leases (P3-2)

The supervisor is the natural **releaser** (the dispatcher acquires). In phase C, under the P3-2 locked writer:

| Event | Lease action |
|---|---|
| `integration.jsonl` records `integrated` (or `promoted`) for a ticket | **release** its lease |
| verdict `green` but not yet integrated | **hold** — this is the case that matters; releasing at green would let the next worker branch from a base missing those commits |
| seat absent from `seats.json` (retired/crashed) | release, **reported as stale**, never silently |
| ticket `blocked` by the arbiter twice | hold, and surface to the human — the files are still contended |

Lease release is what unblocks the looper's next dispatch, so it belongs in the same pass that observes integration.

### 2.2 Arbiter

- `arbiter_enqueue` is called at reap time (cheap, append-only) — never inside the gate.
- `arbiter_drain` **gates inside its own lock** and is therefore slow; it must not run inline in the poll pass.
  Spawn it as a **single background job** (`arbiter.job`, same job-record + atomic `rc` convention). `arbiter_lock` already makes a second
  drain a no-op, so the worst case is a wasted process, not corruption.
- **Back-pressure:** phase C reports `queue_depth` (queued records) and `integration_lag` (`rev-list --count
  <base>..<integration ref>`). When `queue_depth > max_workers`, the supervisor emits `fanout.backpressure` and the
  looper stops dispatching new tickets until it drains. Unbounded queue growth is what turns a clean partition into a
  merge-conflict pile.
- Head-of-line: the roadmap's fix to `arbiter_drain`'s `break`-on-conflict (P3-4) is assumed but not required here;
  without it, a conflicting record just delays its queue-mates by one pass.

## 3. Configuration

```toml
[fanout]
gate_concurrency = 2      # concurrent suite runs (0 = inline/legacy behaviour)
max_workers      = 2      # used for back-pressure comparison
poll_secs        = 15     # scan/reap cadence; safe to lower now that passes are non-blocking
```

`gate_concurrency = 0` must reproduce today's inline behaviour exactly, so the change can be rolled back by config.

## 4. Acceptance

| # | Case | Expected |
|---|---|---|
| 1 | two seats verdict at once, seat A's suite sleeps 20 s, seat B's is instant | B's verdict is recorded within one poll interval; it does **not** wait for A |
| 2 | `gate_concurrency = 1`, three verdicts | exactly one gate process at a time; all three eventually recorded |
| 3 | `gate_concurrency = 0` | byte-identical behaviour to `1872747` (inline gate) |
| 4 | kill the supervisor mid-gate, restart | job with dead pid discarded, verdict re-harvested, **no green invented** |
| 5 | worker commits during its gate | `invalidated` (post-check survives backgrounding) |
| 6 | same verdict line seen in three passes | one job, one record |
| 7 | suite exceeds `SUITE_TIMEOUT_S` | `RED`, rc 124, truncated log, slot released |
| 8 | green verdict | `arbiter_enqueue` called once; lease **not** released until `integrated` appears |
| 9 | ticket integrates | lease released in the next pass; looper may dispatch an overlapping ticket |
| 10 | `queue_depth > max_workers` | `fanout.backpressure` emitted; no new dispatch |
| 11 | bash 3.2 | no `wait -n`, no `declare -A`; `shellcheck` clean |
| 12 | N=4 seats, 60 s suites | a full pass (scan+reap) completes in < 5 s; gates run in the background |

Case 4 is the one that protects the herd's integrity: a missing `rc` must never read as success.

## 5. Risks

- **Fork-bomb by misconfiguration:** `gate_concurrency` must be clamped (say 1–8) and validated at config load; N
  workers × unbounded gates would thrash the machine.
- **Disk:** per-job logs accumulate. Reap keeps logs but should prune those older than a configurable window
  (default 7 days) so `.herdr-swarm/gates/` does not grow without bound.
- **Interleaved output:** background gates must never write to the supervisor's stdout — all output goes to the job log,
  or the Ops pane becomes unreadable at N>1.
- **Clock/ordering:** records are appended by several reap steps in one pass; consumers must sort by `ts` and not assume
  file order (already true, worth stating).
- **P3-FLAKE-1** (`maps/tickets/concurrent-provision-race-mitigation.md`) should land first: N-way seating is what this
  spec assumes, and that race is in the seating path.

## 6. Out of scope

Arbiter batching and bisect (P3-4), speculative parallel gating, scoped/test-impact selection, and the dispatch side of
leases (P3-2 owns acquisition; this spec only releases).
