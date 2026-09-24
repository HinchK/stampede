---
id: HEADLESS-4
title: "Wire headless verdict harvesting into the supervisor"
type: wayfinder:task
status: resolved
commit: 85b27585a25d2b0e57f02bf76aeb7cb756b80c0f
assignee: arch
owns: loop-bot-herd.sh,tests/test_async_gate.sh
parent: maps/headless-run-mode.md
resolution:
  commit: 85b27585a25d2b0e57f02bf76aeb7cb756b80c0f
  status: resolved
  integrated_at: 85b2758
  integration_ref: swarm/stampede/integration
  reviewer_verdict: PASS
  review_file: .herdr-swarm/reviews/HEADLESS-4-85b27585a25d2b0e57f02bf76aeb7cb756b80c0f.md
  channel_report: .herdr-swarm/channel/arch-1-hinchk-stampede-1790234776-31332.md
---

# HEADLESS-4 — harvest wiring (Slice 3b)

**Source:** `docs/findings/headless-mode-design.md` §2 Approach A. Blocked on HEADLESS-3's harness existing —
read what it actually built, not the spec, before wiring.

## Intended Outcome

`loop-bot-herd.sh` gains a `--headless` mode where `harvest_verdicts` reads from `.herdr-swarm/logs/<worker>.log`
(via `lib/headless.sh`'s `headless_status`) instead of `herdr agent read`, using the **exact same** anchored-regex
verdict parsing already in place (`^[[:space:]]*ARCH DONE #...` / `REVIEW VERDICT #...`) — don't reimplement the
regex, import/reuse it.

## Done-Criteria

1. `harvest_verdicts` branches on a `HEADLESS_MODE` flag: pane-scraping (existing, unchanged, default) vs.
   log-scraping (new, via `lib/headless.sh`).
2. Partition/lease acquisition and the Suite Gate are called identically in both modes — this ticket only changes
   *where verdicts are read from*, nothing about what happens once one is found.
3. Re-verdict / RED handling: since there's no PTY to inject feedback into, a rejected verdict triggers a fresh
   `headless_spawn` with a critique brief (mirroring `REV-2`'s critique-delivery protocol) rather than
   `herdr agent prompt`.
4. `tests/test_async_gate.sh` gains headless-mode coverage using the stub vendor CLI from HEADLESS-3's tests.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_async_gate.sh
```
