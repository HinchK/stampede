---
id: SEEDED-1
title: "Seeded-regression pairs: suites must fail when the defect is planted"
type: wayfinder:task
status: resolved
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

## Resolution (2026-10-08)

Resolved in commit `614773278a21e6a9d090f6c811827d616964f364` (`6147732`).

Delivered across all criteria:
1. **Reusable Seed Helper**: Created `tests/helpers/seed.sh` providing `with_seeded_defect <fn> <sed-expr> <assertion-body>`, which sed-mutates the `declare -f` representation of a function, verifies the mutation matched, runs the assertion body expecting failure, and cleanly restores the original function. Added to `LINT_TESTS_SH` in `Makefile`.
2. **CAS Seeded Pair**: Added Section 11 in `tests/test_arbiter.sh`: healthy half verifies concurrent ref move during gate triggers CAS retry; seeded half sed-patches `_arb_integrate` to omit `<expected-old>` from `git update-ref`, proving the retry assertion fails when CAS protection is lost.
3. **Verdict Dedupe Seeded Pair**: Added Section 18 in `tests/test_async_gate.sh`: healthy half verifies re-verdict at new SHA is re-gated green after prior RED; seeded half sed-patches `harvest_verdicts` to drop SHA matching, proving re-verdict rows fail to land when SHA deduplication is broken.
4. **Documentation**: Documented the seeded-regression pair discipline in `CONTRIBUTING.md` naming the two seed pairs as the bar for future orchestrator state machines.
5. **Verification**: `bash tests/test_arbiter.sh && bash tests/test_async_gate.sh` green; `make check` all 21 suites green; 0 ShellCheck warnings.
