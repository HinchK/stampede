---
id: DOG-8
title: "gh_sync has no test suite"
type: wayfinder:task
status: resolved
commit: 30be2ac
assignee: arch-1
owns: tests/test_gh_sync.sh,lib/gh_sync.sh,Makefile
parent: maps/public-readiness.md
github_issue: 26
github_url: "https://github.com/HinchK/stampede/issues/26"
synced_at: "2026-09-22T03:16:07Z"
---

# DOG-8 — Test the tracker integration (WAVE 4)

## 1. Intended Outcome

`lib/gh_sync.sh` — the only library with zero suite coverage — is guarded by a
hermetic test suite wired into the aggregate gate, so the ticket↔issue
reconciliation it performs can never silently regress.

## 2. Problem

Every other `lib/*.sh` has a suite under `tests/` and rides `make test`. The
GitHub sync has only a one-off manual validation report
(`docs/findings/gh-sync-validation-report.md`). Its whole design point is
**zero unconfirmed writes** to the issue tracker; nothing mechanical proves
that property still holds after the next edit.

## 3. Scope

- `tests/test_gh_sync.sh`, hermetic: stub `gh` on `PATH` (record invocations,
  emit fixture JSON); never touch the network or a real repo.
- Cover at minimum:
  1. `--dry-run` is the default and performs zero `gh` writes.
  2. Drift detection both directions: resolved ticket ↔ open issue, and
     open ticket ↔ closed issue.
  3. Ticket without `github_issue:` proposes creation with expected title/
     labels (`swarm:ticket`, `type:<t>`).
  4. Fail-closed auth: `gh auth status` failing blocks all writes with
     remediation text.
  5. Missing `maps/tickets/` dir exits non-zero (already the contract —
     pin it).
- Wire into the `Makefile` suite aggregate so `make check` covers it.

## 4. Done-Criteria

1. All five behaviours above have passing assertions.
2. `make check` green; suite cleans up its scratch dir.
3. 0 shellcheck warnings (pinned-version bar).

## 5. Verification Step

```bash
make test
bash tests/test_gh_sync.sh   # standalone rerun passes
```
