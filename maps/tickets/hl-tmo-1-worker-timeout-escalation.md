---
id: HL-TMO-1
title: "Worker wall-clock timeout is SIGTERM-only without -k escalation"
type: wayfinder:task
status: backlog
assignee: arch
owns: lib/headless.sh,tests/test_async_gate.sh
parent: maps/harden-headless-mode.md
---

# HL-TMO-1 — Worker wall-clock timeout SIGKILL escalation

**Severity:** LOW (probe-demonstrated vulnerability; uncooperative child can evade wall-clock bounds).  
**Found by:** `arch-2-hinchk-stampede` during `#PROVE-HEADLESS-1` (Receipt Finding F8).  
**Dispatch Constraint:** Owns `lib/headless.sh`; cannot dispatch concurrently with `HL-RED-1`.

## Root Cause

In `lib/headless.sh:136-138`, the headless worker spawn runs under `"$TIMEOUT_BIN" "$tmo" opencode …`. However, `timeout` sends only `SIGTERM` by default and does not specify `--kill-after` / `-k`. If a worker subprocess traps or ignores `SIGTERM`, GNU `timeout` waits indefinitely until the process terminates on its own, defeating the hard wall-clock guarantee.

Receipt quote (Finding F8):
> "The worker wall clock is TERM-only. `"$TIMEOUT_BIN" "$tmo" opencode …` (lib/headless.sh:136-138) never escalates past SIGTERM; GNU `timeout` without `--kill-after` waits forever on a child that ignores it (probe 2 above). The DOG-15-style comment says 'hard wall-clock bound'; make it true with `-k <grace>` (or `timeout -s KILL`), keeping the rc=124 semantics.
> ```
> TERM-accepting stub, 3s wall clock:   status: exited rc=124          ✓ killed at the bound
> TERM-IGNORING stub, 3s wall clock:    status after 6s: running (pid 31552)   ✗ evaded
>                                       status after 32s: exited rc=124 (its own sleep 30 ending)
> ```"

## Done-Criteria

1. In `lib/headless.sh`, add kill escalation grace (e.g. `-k 5s` or portable fallback) to the worker timeout wrapper so that uncooperative child processes are forcefully terminated via `SIGKILL` if they fail to exit on `SIGTERM`, preserving exit code 124.
2. Add unit test coverage in `tests/test_headless.sh` or `tests/test_async_gate.sh` validating hard eviction of a SIGTERM-ignoring process.
3. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_headless.sh
```
