---
id: PUB-4
title: "examples/demo-repo: real test suite + one-verdict walkthrough"
type: wayfinder:task
status: ready
assignee: arch
owns: examples/demo-repo/
parent: maps/public-multi-provider.md
blocked_by: PUB-1
---

# PUB-4 — Demo repo: prove the loop in five minutes (Wave 9)

## 1. Intended Outcome

`examples/demo-repo/` is a tiny real repository — genuine `make test` with
real assertions, three pre-written disjoint tickets — plus a README
walkthrough that produces **one supervisor-gated green verdict end to end**
(seat-only up → hand-dispatch one ticket → watch the gate → drain arbiter
→ human promote), using whatever single provider the user configured.

## 2. Problem

The product's whole value is the verified-verdict loop, and there is no
artefact a stranger can run that *shows* it. A demo is also the honest way
to time-box M1 (time-to-first-green-verdict < 15 min).

## 3. Plan

- Zero-dependency implementation (a small bash library + its tests) so
  `make test` runs on stock macOS/Linux bash; the suite must contain real
  assertions that genuinely fail on a planted bug (the demo's RED path is
  part of the lesson).
- Three tickets under `examples/demo-repo/maps/tickets/` with disjoint
  single-line `owns:` (the partition grammar).
- `examples/demo-repo/README.md` walkthrough keyed to the user guide's
  steps 5–8; every command copy-pasteable with `<target>` = the demo dir.
- Profile check: `lib/profile.sh ensure` resolves `TEST_CMD=make test` on
  the demo (it is a `make`-ecosystem repo by construction).

## 4. Explicit Done-Criteria

- `make -C examples/demo-repo test` green on a fresh clone; planting the
  documented bug turns it red.
- Demo tickets pass `partition_check` disjointness.
- Walkthrough never uses a synthetic gate (`true`/`none` forbidden — the
  demo must not green-light the lie the product exists to catch).

## 5. Verification Step

```bash
make -C examples/demo-repo test
bash lib/profile.sh ensure examples/demo-repo 0; echo "rc=$? (want 0)"
make check
```
