---
id: PROFILE-MAKE
title: "Self-dogfood: detect make / run_all.sh aggregate runners so the swarm can gate its own repo from a clean clone"
type: wayfinder:task
status: resolved
commit: 27c8b13
assignee: pi
owns: lib/profile.sh,tests/test_profile.sh,profile.env.example
parent: maps/universal-herdr-swarm.md
---

# PROFILE-MAKE: the gate repo couldn't gate itself

**Problem:** `detect_ecosystem .` on this repo returned `generic` →
`detect_test_cmd` returned 1 — the repo that invented the fail-closed test
gate was the one repo its own autonomous mode refused to run. The only
stand-in was a hand-typed `TEST_CMD` in a gitignored `profile.env` (which
had also drifted: `REPO="HinchK/prototype"` vs remote `HinchK/stampede`).

**Fix:**

- `detect_ecosystem` gains two branches after the ecosystem markers (which
  keep precedence): a `Makefile` **with a `test:` target** → `make`
  (a Makefile without one stays generic — no synthetic gate); `run_all.sh`
  → `run_all`.
- `detect_test_cmd` maps them to `make test`, `./run_all.sh` (executable) or
  `bash run_all.sh`. All still subject to `test_cmd_is_runnable` (no "",
  none, true).
- `profile.env.example` documents every key for the hand-edit path.
- `tests/test_profile.sh` (17 assertions) pins: make/run_all detection,
  no-test-target fail-closed, marker precedence, empty-repo fail-closed,
  runnable gate, and clean-clone self-dogfood of this repo's own Makefile.

**Verification Step**

    /bin/bash tests/test_profile.sh        # 17/17
    bash lib/profile.sh detect-test .      # make test
    bash lib/profile.sh is-runnable "make test"   # runnable
