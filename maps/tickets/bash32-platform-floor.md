---
id: BASH32-FLOOR
title: "Platform floor is macOS system bash 3.2: partition // collapse leaks backslashes; test harness fires EXIT trap early on kill+wait"
type: wayfinder:defect
status: resolved
commit: b9678f3,50ad127
assignee: pi
owns: lib/partition.sh,tests/test_partition.sh,tests/test_worktree.sh
parent: maps/universal-herdr-swarm.md
github_issue: 22
github_url: "https://github.com/HinchK/stampede/issues/22"
synced_at: "2026-09-22T03:16:07Z"
---

# BASH32-FLOOR: bash 3.2 platform-floor reds

Two defects surfaced only under `/bin/bash` (macOS system bash 3.2), which is
the platform floor this repo commits to ("bash 3.2 / macOS safe"):

## 1. `owns_normalize` `//`-collapse leaks backslashes

`lib/partition.sh` collapsed `//` via `e="${e//\/\//\/}"`. In bash 3.2 the
replacement `\/` is a *literal backslash-slash*, so:

    owns_normalize " ./lib//x.sh "  →  lib\/x.sh      (bash 3.2)
                                    →  lib/x.sh       (bash 5)

This is the front door to the lease protocol (frontmatter `owns:` parsing),
so every downstream overlap decision sees corrupted entries. The obvious
quoted fix `${e//"//"/"/"}` is worse: it does not collapse under 3.2, so the
`while [[ $e == *//* ]]` guard never clears and it spins forever (verified by
probe). Fix routes the replacement through a variable
(`local _slash=/; e="${e//\/\//$_slash}"`) so no backslash is parsed in the
replacement on any bash.

## 2. `test_worktree.sh` 5c: EXIT trap fires early on `wait` of a killed job

Under bash 3.2, `wait <pid>` reaping a **signal-killed** background job runs
the shell's EXIT trap immediately, mid-script. The suite's own
`trap cleanup EXIT` (`rm -rf "$TEST_DIR"`) therefore deleted the scratch tree
between 5c's `mkdir` and its pid write:

    + wait <DEAD_PID>
    ++ cleanup            ← EXIT trap, early
    ++ rm -rf /private/tmp/test-wt-.../   ← scratch tree gone
    + printf ... > .../provision.lock/pid  → ENOENT

Minimal repro (3.2 only; bash 5 survives):

    cleanup() { echo RAN; rm -rf "$D"; }
    trap cleanup EXIT
    sleep 5 & P=$!; kill "$P"; wait "$P" 2>/dev/null || true

Fix: the stale-lock holder expires **naturally** (short sleep, `kill -0`
poll) — 5b's naturally-expiring `sleep 1` holder already proved that path is
safe on 3.2. The test never kills+waits a signaled job.

## Verification Step

    /bin/bash tests/test_partition.sh   # 26/26
    bash      tests/test_partition.sh   # 26/26
    /bin/bash tests/test_worktree.sh    # 42/42
    bash      tests/test_worktree.sh    # 42/42
