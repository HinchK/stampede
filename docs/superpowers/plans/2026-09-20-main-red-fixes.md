# Main-Red Fixes, Dogfood Gate & Branch Reconciliation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in this session. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `main` green under the macOS platform floor (`/bin/bash` 3.2), give the repo its own aggregate test command so the Suite Gate can dogfood itself, reconcile the 11 unmerged `pm` branches through the arbiter, and de-kultivait the universal launcher/supervisor.

**Architecture:** Each fix lands as a small conventional commit referencing a ticket in `maps/tickets/`. The Makefile becomes the single aggregate runner; `lib/profile.sh` learns a `make`/`run_all.sh` ecosystem branch so the fail-closed gate resolves on a clean clone; the arbiter gains string ticket ids (the repo's `id:` vocabulary) and is then used for real on the `pm` output. `STATE.md`/`CLAUDE.md` are rewritten last to reflect the actual end state.

**Tech Stack:** bash 3.2-compatible shell, GNU make, python3 tomllib, jq, git worktrees.

**Spec:** user goal message (6 numbered issues), verified by probe during diagnosis.

## Global Constraints

- Platform floor is macOS system bash 3.2: every suite must pass under `/bin/bash` as well as bash 5.
- Lint gate: `shellcheck herdr-loop-swarm.sh loop-bot-herd.sh lib/*.sh` = 0 warnings; `bash -n` clean; `python3 -m py_compile lib/telemetry.py`.
- Never push, never move a base branch except via `arbiter promote` (ff-only, root checkout, clean tree).
- Frontmatter `owns:` is one comma-separated line, never a YAML list.
- Verified root causes (do not re-litigate):
  - `lib/partition.sh:29` — bash 3.2 treats `\/` in the replacement of `${e//pat/rep}` as literal backslash; use `s=/; e="${e//\/\//$s}"` (the quoted-fix `${e//"//"/"/"}` does NOT collapse under 3.2 → infinite loop).
  - `tests/test_worktree.sh` 5c — bash 3.2 runs the EXIT trap early when `wait` reaps a signal-killed bg job; test's `cleanup` rm'd the scratch tree mid-run. Fix: let the holder expire naturally (poll `kill -0`), never kill+wait.

## Review Focus

- `owns_normalize` edge inputs: `///`, `a//b//c`, `//`, `a//`, ` ./x//y ` — must collapse with no backslashes under 3.2 and 5.
- Makefile failure propagation: a failing suite must fail `make test` (verified against the live red before the fix and a synthetic broken suite after).
- Arbiter queue with string tickets: numeric tickets from existing tests must still enqueue/drain/promote identically.
- `detect_ecosystem` precedence: pyproject/Cargo/package/go markers must win over a stray Makefile.
- Promote preconditions: root on `main`, clean tree, ff-only.

---

### Task 1: Fix partition.sh `//`-collapse under bash 3.2 (ticket BASH32-FLOOR)

**Files:** `lib/partition.sh:29`, `tests/test_partition.sh` (already has failing [8d]), `maps/tickets/bash32-platform-floor.md` (new)

- [x] RED reproduced: `/bin/bash tests/test_partition.sh` → [8d] fails, exit 1 (25/26)
- [ ] Apply `local s=/` fix in `owns_normalize`
- [ ] GREEN: suite 26/26 under `/bin/bash` AND bash 5
- [ ] Ticket file + commit `fix: (#BASH32-FLOOR)`

### Task 2: Fix test_worktree.sh 5c early-EXIT-trap under bash 3.2 (same ticket)

**Files:** `tests/test_worktree.sh` (5c block)

- [x] RED reproduced 4/4 + minimal repro: kill+wait fires EXIT trap early on 3.2
- [ ] Replace kill+wait with natural expiry (short sleep + `kill -0` poll), keep dead-pid semantics
- [ ] GREEN: 42/42 under `/bin/bash` AND bash 5
- [ ] Commit `fix: (#BASH32-FLOOR)`

### Task 3: Aggregate Makefile (issue 2)

**Files:** `Makefile` (new)

- [ ] `test` target: every `tests/test_*.sh` under `/bin/bash`, failure-propagating (set -e loop)
- [ ] `lint` target: shellcheck 0-warning gate + bash -n + py_compile
- [ ] `check` = lint + test; verify propagation with synthetic broken suite
- [ ] Commit `feat: aggregate test/lint/check targets (#TEST-AGG)`

### Task 4: Self-dogfood profile detection (issue 3)

**Files:** `lib/profile.sh` (`detect_ecosystem`, `detect_test_cmd`), `profile.env.example` (new), `tests/test_profile.sh` (new, TDD)

- [ ] TDD: makefile-with-test-target → ecosystem `make` → `make test`; run_all.sh → `bash run_all.sh`; generic still returns 1; marker precedence preserved
- [ ] `profile.env.example` documenting REPO/TEST_CMD/ECOSYSTEM/DOCS_DIR
- [ ] Dogfood: `lib/profile.sh detect-test .` prints `make test` on this repo (clean-clone semantics)
- [ ] Refresh runtime `.herdr-swarm/profile.env` (REPO=HinchK/stampede)
- [ ] Commit `feat: (#PROFILE-MAKE)`

### Task 5: Arbiter string ticket ids (issue 5 enabler)

**Files:** `lib/arbiter.sh` (`arbiter_enqueue`, `_arb_set_status`), `tests/test_arbiter.sh`

- [ ] TDD: enqueue/drain/promote with `"P3-4-spec"`-style id; numeric ids unchanged (26 existing + new green)
- [ ] Commit `feat: (#P3-4-arbiter-strings)`

### Task 6: Branch reconciliation via arbiter (issue 5)

- [ ] Two-dot analysis → integrate list (pm-p3-4-spec, pm-p3-3-spec residual, pm-reordered-plan, worktree-pm-audit, pm-p2-4-spec residual) vs delete list (verified patch-equivalent)
- [ ] Per branch: `arbiter enqueue <id> pm <sha>` → `drain` (gate: `make test`) → `promote` (ff-only, clean root — deletions committed first)
- [ ] Delete fully-applied branches (`-D` only after `git cherry` proves equivalence)
- [ ] Unlock + remove `.claude/worktrees/pm-audit`; reconcile integration worktree

### Task 7: STATE.md + CLAUDE.md truth pass (issue 4)

- [ ] §1/§2/§3 updated: P3-3 resolved, P3-4 spec integrated, real test totals (37+26+26+17+profile), P3-2 red→fixed, next steps
- [ ] CLAUDE.md commands: `make check`, four suites
- [ ] Commit `docs: (#STATE-TRUTH)`

### Task 8: De-hardcode kultivait (issue 6)

**Files:** `herdr-loop-swarm.sh` (~566), `lib/config.sh` (emit `PROXY_HEALTH_URL`), `swarm.config.toml` (`enabled = false` default), `loop-bot-herd.sh` (~117 recovery pointer, ~429 credits_watch gate), commit stray deletions `loop-bot-herd-claude/`

- [ ] Launcher: start proxy only when `PROXY_ENABLED=true`; probe `PROXY_HEALTH_URL`
- [ ] Supervisor: recovery pointer → this repo's `herdr-loop-swarm.sh up`; credits probe only when proxy enabled
- [ ] `chore: remove loop-bot-herd-claude/ legacy variant` + commit `fix: (#PROXY-GATE)`
- [ ] Final `make check` green
