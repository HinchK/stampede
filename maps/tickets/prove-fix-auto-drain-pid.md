---
id: PROVE-7
title: "arbiter_auto_drain records the wrong PID via $$ inside a backgrounded subshell"
type: wayfinder:defect
status: resolved
commit: c3f3c865d70fbd3250c3cc50e0b62e8782f5c677
assignee: arch
owns: loop-bot-herd.sh,lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/prove-and-reconcile.md
resolution:
  commit: c3f3c865d70fbd3250c3cc50e0b62e8782f5c677
  integrated_at: c3f3c86
  integration_ref: swarm/stampede/integration
  reviewer_verdict: PASS
  review_file: .herdr-swarm/reviews/PROVE-7-c3f3c865d70fbd3250c3cc50e0b62e8782f5c677.md
---

# PROVE-7 — auto-drain PID/lock staleness defect

**Severity:** MED — no data corruption or main-branch risk, but a real stall: a crashed background auto-drain
leaves `arbiter.lock` looking permanently held, blocking both future auto-drains AND manual
`lib/arbiter.sh drain --confirm` recovery.
**Found by:** PROVE-3 (the Autonomous Reviewer Loop's first real run), reviewing PROVE-4 at
`16dd48121c78780f36440a3181bf2b2ba54db3c6`. Confirmed by `pm` via direct code read and an empirical repro of
bash `$$` semantics inside a backgrounded block.

## Root Cause

`loop-bot-herd.sh`'s `arbiter_auto_drain()` (PROVE-4) backgrounds `arbiter_drain` inside `{ ...; } &`
(`loop-bot-herd.sh:762-765`). `arbiter_lock()` (`lib/arbiter.sh:94`) writes `$$` into the lock's `pid` file —
correct for every prior synchronous caller, but `$$` does not update inside a backgrounded block in bash (only
`$BASHPID` does, unavailable before bash 4.0, past this repo's bash 3.2 floor). So the lock records the long-lived
supervisor's PID, not the actual drain job's. Repro:

```
$ bash -c 'p=$$; ( echo child=$$; echo bashpid=$BASHPID; echo parent=$p ) & wait'
child=15628
bashpid=15630
parent=15628
```

Separately, `arbiter_auto_drain`'s own pre-check (`loop-bot-herd.sh:756`, `[[ -d "${STATE_DIR}/arbiter.lock" ]]`)
never checks liveness at all — it doesn't even attempt the `kill -0` staleness check that `arbiter_lock()` already
has, so it can't self-heal even in isolation.

## Done-Criteria

1. The background drain runs as a genuinely separate process (e.g.
   `bash "$SCRIPT_DIR/lib/arbiter.sh" drain >> "${STATE_DIR}/gate-logs/arbiter-drain.log" 2>&1 &`, tracked via `$!`),
   so `arbiter_lock`'s own `$$` correctly reflects the drain job's actual PID.
2. A killed background drain leaves a lock that both `arbiter_auto_drain`'s pre-check and a manual `arbiter_lock()`
   call correctly recognize as stale and evict.
3. `tests/test_arbiter.sh` gains a stress assertion: spawn a drain, kill it, confirm a subsequent drain (auto or
   manual) is not permanently blocked.
4. `make test` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_arbiter.sh   # new kill-and-recover assertion passes
```

## Notes

Full original review: `.herdr-swarm/reviews/PROVE-4-16dd48121c78780f36440a3181bf2b2ba54db3c6.md`
