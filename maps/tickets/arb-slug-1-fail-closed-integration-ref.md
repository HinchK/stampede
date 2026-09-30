---
id: ARB-SLUG-1
title: "Arbiter silently creates a phantom integration branch instead of failing closed on slug mismatch"
type: wayfinder:defect
status: resolved
assignee: arch
owns: lib/arbiter.sh,tests/test_arbiter.sh
parent: maps/universal-herdr-swarm.md
github_issue: 66
github_url: "https://github.com/HinchK/stampede/issues/66"
synced_at: "2026-09-30T17:16:14Z"
---

# ARB-SLUG-1 -- fail-closed integration ref resolution

**Severity:** MED-HIGH -- no data loss occurred (git objects are immutable, the divergent branch was recoverable),
but this created a real fork of the integration ref that briefly made false "integrated" claims land on main. This
is exactly the class of silent-fake-green failure mode this project's whole design exists to prevent, now found
inside the arbiter itself.
**Found by:** looper, while investigating why SUPER-1's reported integration didn't match the real
swarm/stampede/integration ref (2026-09-29). Root cause fully diagnosed, not yet fixed.

## Root Cause

Two disagreeing sources of truth for the project slug:
- profile.env sets REPO="HinchK/stampede", which slugifies to "hinchk-stampede".
- swarm.config.toml sets [swarm] name = "stampede".
- lib/arbiter.sh sources neither directly and falls back to `basename $PWD` ("stampede") when PROJECT_SLUG isn't
  set in its environment.
- The watch daemon (loop-bot-herd.sh watch) picked up PROJECT_SLUG="hinchk-stampede" from profile.env for one
  auto-drain pass.
- With that slug, `git show-ref --verify refs/heads/swarm/hinchk-stampede/integration` failed (that ref never
  existed -- the real one is swarm/stampede/integration).
- Instead of failing closed, lib/arbiter.sh's fallback ran `i0=$(git rev-parse "$ARB_BASE")` (main's tip) and
  created a brand-new integration branch rooted there, then drained onto it -- producing a divergent fork that
  never touched the real integration ref.

## Done-Criteria

1. `lib/arbiter.sh` resolves PROJECT_SLUG from one canonical source, consistent with whatever loop-bot-herd.sh
   uses -- investigate which of profile.env / swarm.config.toml should be canonical (swarm.config.toml is
   documented elsewhere as "the single source of seat truth," which is a reasonable default unless investigation
   finds a reason otherwise) and align both scripts to it.
2. Independent of (1), as defense in depth: if `git show-ref --verify refs/heads/swarm/<slug>/integration` fails
   to find the expected ref, arbiter_drain / arbiter_enqueue_and_drain refuse loudly with a clear error rather than
   creating a new branch rooted at main. Creating the canonical integration branch is a one-time, explicit
   initialization action, never an implicit fallback inside drain.
3. New test coverage: a slug mismatch between the two config sources is caught and refused, not silently
   papered over by branch creation.
4. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_arbiter.sh   # new fail-closed assertion for missing/mismatched integration ref
```

## Notes

The divergent branch this incident created (rooted at commit f0194dc) should be left alone as a historical
artifact once this ticket lands -- don't delete or rewrite it, it's harmless now that the real integration ref is
correct and this ticket prevents recurrence.

## Resolution

- **Implementation**:
  - `lib/arbiter.sh`: Canonical slug resolution chain (`PROJECT_SLUG` > `SWARM_CONFIG_NAME` > `basename`).
  - `loop-bot-herd.sh`: `arbiter_auto_drain` passes canonical `SWARM_CONFIG_NAME` (`stampede`) from `swarm.config.toml`.
  - `lib/arbiter.sh`: `arbiter_drain` fails closed if `refs/heads/swarm/<slug>/integration` is missing (loud error, prints diagnostics, releases lock, returns 1). Deleted implicit create-if-missing fallback in `_arb_integrate`.
  - `lib/arbiter.sh`: Added `arbiter_init_ref` (CLI `arbiter.sh init-ref [BASE]`) for explicit, one-time integration branch initialization.
- **Suite Gate**: `tests/test_arbiter.sh` Section 10 (+11 tests, 88/88 passing) covering missing ref refusal, no-fork guarantee, explicit init-ref, and precedence chain; `make check` all 19 suites green, 0 shellcheck warnings.
- **Review**: Autonomous Reviewer Loop PASS verdict by `reviewer-hinchk-stampede` (Round 1/2) in `.herdr-swarm/reviews/ARB-SLUG-1-cb418921e51ced67792fe6ee2a648638f77749cb.md`.
- **Integrated**: Auto-drained and integrated on `swarm/stampede/integration` at `3bb01bd` on top of `SUPER-1` (`611cc4e`) and `GRANT-1` (`c7d8367`). Verified ancestor. Lease released cleanly.
