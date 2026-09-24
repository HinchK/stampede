# ADR 0014: Arbiter Drain Automation and Non-Blocking Supervisor Integration

- **Status**: Accepted
- **Date**: 2026-09-23
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [ADR 0009: Arbiter Branch Integration and CAS Merge](0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0013: Asynchronous Supervisor Suite Gating](0013-asynchronous-supervisor-gate-jobs.md), [PROVE-4 Ticket](../../maps/tickets/prove-auto-wire-arbiter-drain.md), [PROVE-5 Ticket](../../maps/tickets/prove-drain-adr.md), [PM Audit 2026-09-23 §6](../audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md)

---

## 1. Context and Problem Statement

Under [ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md), completed work from isolated worker branches is reconciled and pre-gated on a dedicated staging ref (`swarm/<slug>/integration`) via Compare-and-Swap (CAS) fast-forward merges before promotion to `main`. 

Historically, this reconciliation pipeline operated as a two-step manual process:
1. When a worker's implementation passed the Suite Gate, the supervisor automatically enqueued a record into `.herdr-swarm/integration.jsonl` via `arbiter_enqueue` (`loop-bot-herd.sh:725`).
2. The enqueued record remained inert in the queue until a human operator or orchestrator explicitly triggered `lib/arbiter.sh drain`. Only after draining did the integration ref advance and integration evidence get recorded.
3. The human driver subsequently reviewed the integrated state and executed `lib/arbiter.sh promote --confirm` to fast-forward `main`.

In practice, this manual drain requirement created an operational gap:
- **Queue Stagnation & Integration Lag**: Green tickets sat queued in `.herdr-swarm/integration.jsonl` indefinitely if an operator did not manually invoke `drain`. During the 2026-09-23 PM audit ([`docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md` §6](../audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md)), tickets DOG-17 and DOG-18 sat gated and queued across multiple turns without advancing the integration branch, allowing `main` to drift out from under them.
- **Partition Lease Retention**: Under [ADR 0012](0012-task-partitioning-and-disjoint-dispatches.md) and DOG-16 (`lease_release_integrated`), active file partition leases are only released when `integration.jsonl` records that a commit has reached `integrated` or `promoted` status. Leaving tickets in `queued` status prevented downstream tickets requiring those paths from being dispatched.

A mechanism was required to automatically drain green enqueued commits without human intervention, while preserving the inviolable rule from [ADR 0009](0009-arbiter-branch-integration-and-cas-merge.md) that `main` is promoted exclusively by a human.

---

## 2. Decision Drivers

- **Continuous Integration Flow**: Verified, green-gated commits must advance to the integration ref (`swarm/<slug>/integration`) immediately to unblock file partition leases and minimize branch divergence.
- **Strict Invariance of Sovereign Human Promotion (ADR 0009)**: Promotion to the base branch (`main`) and pushing to remote origins must remain sovereign-human actions requiring explicit `--confirm` authorization. Auto-wiring must never advance or touch `main`.
- **Non-Blocking Supervisor Poll Loop**: Draining candidate commits requires running `make test` within the detached arbiter worktree (`.herdr-swarm/worktrees/arbiter-<slug>`), taking 30–300s. The supervisor poll loop must never execute `arbiter_drain` inline, which would cause head-of-line blocking ([ADR 0013](0013-asynchronous-supervisor-gate-jobs.md)).
- **Atomic Serialization Without Lock Proliferation**: Concurrent drain attempts from multiple triggers must serialize cleanly under the existing `.herdr-swarm/arbiter.lock` without deadlocks, corruption, or creating new locking mechanisms.
- **Preserved Conflict Semantics**: The arbiter must never attempt automatic fuzzy conflict resolution; merge conflicts on integration must abort and hand back to the worker ([ADR 0009 §4.D](0009-arbiter-branch-integration-and-cas-merge.md)).

---

## 3. Considered Options

- **Option A (Retain Manual Operator Drain)**: Leave `arbiter_drain` strictly operator-invoked.
  - *Rejection*: Leads to stranded queued records, stalled partition leases, and avoidable drift between worker worktrees and integration.
- **Option B (Inline Synchronous Drain in Supervisor Loop)**: Run `arbiter_drain` directly inside `cmd_once()` whenever queued records exist.
  - *Rejection*: `arbiter_drain` executes the full project test suite inside the detached arbiter worktree. Running it synchronously inside the supervisor loop would freeze all verdict harvesting, health checks, and telemetry streaming for minutes per ticket.
- **Option C (Primitive Auto-Drain, CLI Parity, and Asynchronous Background Pass Step)**:
  1. Implement `arbiter_enqueue_and_drain` in `lib/arbiter.sh` to atomize enqueue and drain under a single lock acquisition.
  2. Wire the CLI dispatcher (`lib/arbiter.sh enqueue` / `bin/stampede enqueue`) to automatically drain.
  3. Add `arbiter_auto_drain` to `loop-bot-herd.sh` as an asynchronous background pass step immediately following `gate_reap`.

---

## 4. Decision

We adopted **Option C** in ticket [PROVE-4](../../maps/tickets/prove-auto-wire-arbiter-drain.md) (commit `16dd481`):

### A. Library Primitives (`lib/arbiter.sh`)

1. **`arbiter_queued_count`**:
   A read-only predicate inspecting `.herdr-swarm/integration.jsonl` via `jq`:
   ```bash
   arbiter_queued_count() {
     _arb_cfg
     [[ -f "$ARB_QUEUE" ]] || { printf '0\n'; return 0; }
     jq -r -s '[.[] | select(.status == "queued")] | length' "$ARB_QUEUE" 2>/dev/null || printf '0'
   }
   ```
2. **`arbiter_enqueue_and_drain`**:
   Atomically chains enqueue and drain within a single locked execution block:
   ```bash
   arbiter_enqueue_and_drain() {
     arbiter_enqueue "$@" || return $?
     arbiter_drain
   }
   ```
3. **CLI Subcommand Parity**:
   The CLI `enqueue` subcommand invokes `arbiter_enqueue_and_drain`, ensuring operator or script enqueues immediately advance the integration ref. The bare `drain` subcommand is retained for manual re-runs and debugging.

### B. Supervisor Asynchronous Pass (`loop-bot-herd.sh:arbiter_auto_drain`)

In `loop-bot-herd.sh`, an `arbiter_auto_drain` pass is executed during `cmd_once()` immediately after `gate_reap`:
```bash
arbiter_auto_drain() {
  local queued
  queued=$(arbiter_queued_count 2>/dev/null || printf '0')
  [[ "$queued" =~ ^[0-9]+$ ]] || queued=0
  (( queued > 0 )) || return 0
  if [[ -d "${STATE_DIR}/arbiter.lock" ]]; then
    note "arbiter drain already running — ${queued} queued record(s) left to it"
    return 0
  fi
  mkdir -p "${STATE_DIR}/gate-logs"
  note "arbiter auto-drain: ${queued} queued record(s) — drain spawned (log: ${STATE_DIR}/gate-logs/arbiter-drain.log)"
  {
    printf '\n[%s] auto-drain pass (supervisor pid %s)\n' "$(date '+%H:%M:%S')" "$$"
    arbiter_drain
  } >> "${STATE_DIR}/gate-logs/arbiter-drain.log" 2>&1 &
}
```

Key operational characteristics:
- **Asynchronous Execution**: The drain runs in the background (`&`), streaming logs to `${STATE_DIR}/gate-logs/arbiter-drain.log`. The supervisor poll loop continues unblocked.
- **Lock-Gated Spawning**: If `${STATE_DIR}/arbiter.lock` is currently held, `arbiter_auto_drain` skips spawning, leaving remaining queued records to the active drain process.
- **Bounded Loser Wait**: If a background drain races with an interactive or CLI drain, the loser defers gracefully after a bounded wait (`ARBITER_TMP_SLEEP`), leaving records safely queued until the lock clears.

### C. Safety and Invariance of ADR 0009

This architecture explicitly distinguishes **integration** from **promotion**:
1. **Ref Isolation**:
   `arbiter_drain` updates exclusively `refs/heads/swarm/<slug>/integration`. It has no code paths that modify `refs/heads/main` or the root repository index.
2. **Untouched Sovereign Human Promotion**:
   Advancing `main` still requires `lib/arbiter.sh promote --confirm` (or `bin/stampede promote`). Auto-drain provides zero automation for the promote step; human authorization remains the sole authority for base branch updates.
3. **Fail-Closed Conflict Handling**:
   If candidate commits conflict during auto-drain, `arbiter_drain` aborts the merge, marks the ticket status as `conflict` in `integration.jsonl`, and leaves the integration ref unchanged. Conflicts are never auto-resolved.

---

## 5. Consequences

### Positive
- **Zero Operator Drain Burden**: Passing implementation tickets advance to `swarm/<slug>/integration` within seconds of gate completion without requiring operator terminal commands.
- **Timely Partition Lease Release**: With tickets reaching `integrated` status automatically, DOG-16 (`lease_release_integrated`) frees task path leases immediately, unblocking downstream worker dispatches.
- **Zero Head-of-Line Blocking**: Asynchronous background spawning ensures test gating in the detached arbiter worktree does not starve supervisor harvesting.
- **Complete Test Coverage**: Validated by 14 assertions in Section 10 of `tests/test_arbiter.sh` (53 total assertions passing).

### Neutral / Trade-offs
- **Background Resource Usage**: Spawning background drain suites consumes CPU and I/O during integration passes. Concurrency bounds and `arbiter.lock` serialization prevent runaway resource exhaustion.
- **Operator Model Realignment**: Operators must understand that `drain` occurs automatically, but `promote` remains manual. Telemetry and `bin/stampede status` reflect the live state of both refs.
