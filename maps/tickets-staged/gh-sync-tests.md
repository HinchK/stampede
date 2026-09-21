---
id: DOG-8
title: "Test coverage for lib/gh_sync.sh — largest file, zero tests, mutates external state"
type: wayfinder:prototype
status: backlog
assignee: arch
owns: tests/test_gh_sync.sh,lib/gh_sync.sh,Makefile
parent: maps/public-readiness.md
---

# DOG-8 — gh_sync test coverage (WAVE 4)

## 1. Intended Outcome

`lib/gh_sync.sh` has an acceptance suite matching the treatment
`partition`/`arbiter`/`worktree` received, picked up automatically by `make test`.

## 2. Problem

At 644 lines it is the largest single file in the repo, has **zero tests**, and
is the **only module that can mutate state outside the repo** (GitHub issues).
Its `--dry-run` default is good discipline; nothing enforces that the default
holds after an edit. The 2026-09-19 review flagged this and it is unchanged.

## 3. Scope

`tests/test_gh_sync.sh`, following the house pattern exactly: ephemeral scratch
git repo, stubbed `gh` on PATH, `set -euo pipefail`, trap cleanup, PASS/FAIL
counters, exit 0 = all pass, runs under `/bin/bash` (3.2 floor).

Cover at minimum:

1. **`--dry-run` is the default** — a no-argument invocation performs zero
   writes. This is the single most important assertion in the file.
2. `--apply` is required before any `gh` write is attempted.
3. Frontmatter parsing: `id`, `status`, `github_issue` round-trip.
4. The `owns:` line is **one comma-separated line** — a YAML list must be
   rejected or ignored, never silently half-parsed.
5. Malformed `OWNER/REPO` is rejected fail-closed (`lib/gh_sync.sh:195`).
6. Unauthenticated `gh` fails closed rather than proceeding.
7. A ticket already carrying `github_issue` is not duplicated.

The stub `gh` records invocations to a file, so the suite asserts on what would
have been called and never on network results.

## 4. Done-Criteria

1. `tests/test_gh_sync.sh` exists, exits 0, reports its own pass/fail counts.
2. At least 12 assertions; the dry-run-default case is among them.
3. Picked up by `make test` with no Makefile edit — it globs `tests/test_*.sh`.
   Confirm this, and only touch the `Makefile` if it turns out false.
4. Zero network calls: passes with no `GH_TOKEN` and `gh` stubbed.
5. `shellcheck tests/test_gh_sync.sh` clean.
6. `make check` green.

## 5. Verification Step

```bash
/bin/bash tests/test_gh_sync.sh ; echo "rc=$?"
env -u GH_TOKEN /bin/bash tests/test_gh_sync.sh   # must still pass
shellcheck tests/test_gh_sync.sh
make check
```

Receipt must state the assertion count and confirm the dry-run-default case fails
when `--dry-run` is deliberately removed — prove the test bites.

## 6. Notes

Shares `lib/gh_sync.sh` with DOG-7; runs after DOG-7 integrates.
