---
id: HL-WT-1
title: "worktree_provision ignores _wt_add_with_retry rc, causing phantom worktree and green no-op"
type: wayfinder:defect
status: resolved
assignee: arch
owns: lib/worktree.sh,tests/test_worktree.sh,lib/headless.sh
parent: maps/harden-headless-mode.md
---

# HL-WT-1 — worktree_provision rc propagation and phantom worktree guard

**Severity:** MED (silent no-op, masks failure as success; not data loss).  
**Found by:** `arch-2-hinchk-stampede` during `#PROVE-HEADLESS-1` (Receipt Finding F3).

## Root Cause

In `lib/worktree.sh:151`, `_wt_add_with_retry` returns 1 and prints the real failure on stderr, but `worktree_provision` ignores its exit status and prints the success shape (`<wt_path>\n<branch>`) anyway.

Inside the headless call site `if ! prov=$(worktree_provision …)` (`lib/cli/stampede-headless.sh:115`), `set -e` is suspended by the `if !` condition, so the failure propagates nowhere.

Receipt quote (Finding F3):
> `worktree_provision` ignores `_wt_add_with_retry`'s rc (`lib/worktree.sh:151`) and prints the success shape anyway. Inside the headless call site `if ! prov=$(worktree_provision …)` (`lib/cli/stampede-headless.sh:115`) `set -e` is suspended, so the failure propagates nowhere. Repro: leave a locked, missing worktree entry + its branch from a prior run (e.g. state dir deleted between runs), re-run `headless`:
> ```
> headless: dispatching #T10 → … (worktree: …/worktrees/arch_1)
> lib/headless.sh: line 70: cd: …/worktrees/arch_1: No such file or directory
> headless: worktree dir not found:            ← empty path in the message (cd failed inside $())
> headless: #T10 spawn failed — parking  … batch done — 0 dispatched, 0 dead-letter record(s)  exit 0
> ```
> A fully green-looking no-op. Also note the CLI form *does* fail loudly (`bash lib/worktree.sh provision …` exits 1) — but only by accident of top-level `set -e`.

## Done-Criteria

1. `worktree_provision` in `lib/worktree.sh` checks the return code of `_wt_add_with_retry` and returns 1 when adding/locking fails, never printing a phantom path or returning 0 on failure.
2. In `lib/headless.sh`, `headless_spawn` guards `wt=$(cd "$wt" && pwd)` so that if `cd` fails, the error message names the missing path clearly rather than logging an empty path.
3. Add hermetic test coverage in `tests/test_worktree.sh` validating that a failed `worktree_provision` returns non-zero even when executed inside a command substitution under `if ! prov=$(...)` (`set -e` suspended).
4. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_worktree.sh
bash tests/test_headless.sh
```

## Resolution

- **Author:** `arch-1-hinchk-stampede` (commit `3dc233364beb588a91d33321242affffea9dd3cd`)
- **Review:** `reviewer-hinchk-stampede` Round 1/2 PASS (`.herdr-swarm/reviews/HL-WT-1-3dc233364beb588a91d33321242affffea9dd3cd.md`)
- **Integrated:** `b95b3836504edd37e2846d82451c0116f0d35f03` onto `swarm/stampede/integration`
- **Summary:** Propagated `_wt_add_with_retry` failure rc in `lib/worktree.sh` so phantom paths are never emitted when provisioning fails, guarded `cd "$wt"` in `lib/headless.sh` to name missing worktree paths clearly, and added case 16 reproducing the exact stale-entry incident in `tests/test_worktree.sh` (46/46 passed).

