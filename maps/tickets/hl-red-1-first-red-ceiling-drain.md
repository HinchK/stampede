---
id: HL-RED-1
title: "First-RED ticket exits 0 and kills critique turn, leaving ceiling unreachable and batch undrained"
type: wayfinder:defect
status: resolved
assignee: arch
owns: lib/headless.sh,lib/cli/stampede-headless.sh,tests/test_async_gate.sh
parent: maps/harden-headless-mode.md
---

# HL-RED-1 — First-RED critique termination, unreachable ceiling, and headless batch undrained gap

**Severity:** MED-HIGH (contract-vs-behavior gap; misleading exit 0 on failed ticket; self-wedging un-drained queue).  
**Found by:** `arch-2-hinchk-stampede` during `#PROVE-HEADLESS-1` (Receipt Findings F5 & F6).

## Root Cause

Two inter-locking defects in `lib/cli/stampede-headless.sh` and `lib/headless.sh`:

1. **First-RED kills critique turn (F6)**: The per-ticket wait loop in `stampede-headless.sh` treats *any* session-verdict record as concluding the ticket — including `RED`. It immediately calls `headless_kill` on the seat, which terminates the critique turn that `worker_feedback` had just spawned. Because attempt 2 is killed before it can run, the `max_verdict_attempts = 2` ceiling (`HEADLESS-5`) can never fire in-batch. Furthermore, the batch exits 0 despite leaving an un-integrated, RED ticket in the ledger.
2. **Missing in-batch drain and lease release (F5)**: Headless mode enqueues green tickets into `integration.jsonl` with status `queued`, but never invokes `arbiter_auto_drain` or `lease_release_integrated` (both reside in `loop-bot-herd.sh once`, which the batch never calls). As a result, leases stay held permanently across tickets; a no-owns ticket parks all subsequent tickets, requiring manual operator recovery.

Receipt quotes:
> **Finding F6**: "A first-RED ticket ends the batch exit 0, and the ceiling is unreachable in-batch (defect vs documented contract). The per-ticket wait treats *any* session record as 'concluded' — including RED — then `headless_kill`s the just-spawned critique turn. With `max_verdict_attempts = 2`, attempt 2 can never happen inside one run (the re-verdict worker is killed), and across runs the held lease parks the ticket (F5). Net: the designed 'RED ×N → DEAD_LETTER' transition is unreachable in practice; the only producing path is worker-death-without-verdict (attempt 1). Exit 0 with a RED, un-integrated ticket in the log is at best misleading for CI."
> 
> **Finding F5**: "The batch never drains and never releases leases (design gap, same smell PROVE-4 fixed for the supervisor loop). Greens sit `queued` in `integration.jsonl`; leases stay held; a no-owns ticket therefore holds the whole repo forever. In attempt 5, one green ticket parked the other two permanently — a second batch run would park all three."

## Done-Criteria

1. In `lib/cli/stampede-headless.sh`, treat `RED` as non-concluded while attempts remain below `max_verdict_attempts`, allowing the critique turn spawned by `worker_feedback` to run until either a re-verdict succeeds or the ceiling triggers `DEAD_LETTER`.
2. Ensure `bin/stampede headless` exits non-zero whenever any ticket in the batch concludes in `RED` or `DEAD_LETTER`.
3. Auto-drain integrated records (`arbiter_auto_drain` / `arbiter_drain`) and release leases (`lease_release_integrated`) within the headless batch lifecycle so completed tickets free their partition claims for subsequent tickets and batch runs.
4. Comprehensive test coverage in `tests/test_async_gate.sh` and `tests/test_cli.sh` proving multi-attempt critique progression to ceiling, non-zero batch exit on unresolved failure, and automatic drain/lease release.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_async_gate.sh
bash tests/test_cli.sh
```
