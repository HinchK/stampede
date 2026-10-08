---
id: SEEDED-1
title: "Seeded-regression pairs: suites must fail when the defect is planted"
type: wayfinder:task
status: backlog
assignee: arch
owns: tests/test_arbiter.sh, tests/test_async_gate.sh
parent: maps/pick-up-where-we-left-off.md
---

# SEEDED-1 — prove the suites' teeth on the two costliest silent-failure paths

## Intended Outcome

For the two paths where a silent pass-through is costliest — supervisor **verdict dedupe**
(`(ticket, sha)` re-verdict logic) and arbiter **CAS ref advance** (`update-ref <ref> <new>
<expected-old>`) — the suites assert not only that healthy code passes, but that *planting the
defect makes the suite red*. A test only counts if it fails when the bug is seeded (the
seeded-regression-pair discipline; OpenRig comparison §7 #1, adopted via BORROW-1).

## Background (receipts)

- OpenRig's scenario bar: a scenario "counts only as a pair" — passes healthy, fails seeded
  (`openrig:ARCHITECTURE.md:L262-L264`, per
  `.herdr-swarm/research/2026-10-08-openrig-comparison-review.md` §5.9) — mutation testing for the
  orchestrator's own state machines.
- Our suites assert healthy paths only. REV-JQ-1's manual seeded-regression receipt (red on the
  pre-fix supervisor, 2026-10-08) demonstrated the technique by hand; this ticket mechanizes it
  for the two paths where a false green would certify bad work onto `integration`.
- Candidate seeds: (1) verdict dedupe that skips re-gating when only the sha changes
   (`loop-bot-herd.sh` harvest lane); (2) CAS that drops the `<expected-old>` argument (plain
   `update-ref`) — the exact concurrency-loser git semantics ADR 0009 exists to reject.

## Done-Criteria

1. A reusable suite helper (e.g. `with_seeded_defect <fn-name> <seed-script> <assertions>`) that
   redefines the function under test with the defect planted (post-source function redefinition —
   the GATE-1 suite pattern), runs the targeted assertions, asserts they **fail**, then restores.
2. Seeded pairs cover: verdict-dedupe bypass seed and CAS stale-expected-old seed, each asserting
   the corresponding suite section goes red under the seed and green without it.
3. The discipline is documented with one short paragraph in `CONTRIBUTING.md` (or `CLAUDE.md`
   working conventions) naming the two seed pairs as the bar for future state-machine suites.
4. `make check` green (all suites), 0 ShellCheck warnings.

## Verification Step

```bash
bash tests/test_arbiter.sh && bash tests/test_async_gate.sh && make check
```
