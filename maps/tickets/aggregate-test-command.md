---
id: TEST-AGG
title: "Aggregate test command: a Makefile whose `test` target runs every suite and propagates failures"
type: wayfinder:task
status: resolved
commit: ec6d090
assignee: pi
owns: Makefile
parent: maps/universal-herdr-swarm.md
github_issue: 18
github_url: "https://github.com/HinchK/stampede/issues/18"
synced_at: "2026-09-22T03:16:07Z"
---

# TEST-AGG: one command, all suites, failures propagate

**Problem (one failure, four symptoms):** with no aggregate test command,
nothing ran all three suites, there was no CI at all, and a red suite landed
on `main` — while the ledger certifying the work was written by the agents
that did it. The repo that invented the fail-closed Suite Gate had no gate of
its own.

**Fix:** `Makefile` with:

- `make test` — every `tests/test_*.sh` under `/bin/bash` (macOS system
  bash 3.2 is the platform floor, not the dev shell's bash 5 — #BASH32-FLOOR),
  auto-including suites added later, `set -e` so any failure fails the target
  with the offending suite named.
- `make lint` — the 0-warning shellcheck bar plus `bash -n` and
  `py_compile`.
- `make check` — lint + test; what CI and the Suite Gate should run.

**Verification Step**

    make test                    # 4 suites, exit 0
    make lint                    # exit 0, 0 warnings
    # propagation probe: a suite that exits 1 must fail `make test` (verified
    # with a synthetic tests/test_zzz_synthetic_broken.sh — make exit 2)
