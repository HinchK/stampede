---
id: ELIG-3
title: "gh_sync reads tickets through the shared ticket parser"
type: wayfinder:task
status: backlog
assignee: arch
blocked_by: ELIG-1
owns: lib/gh_sync.sh, tests/test_gh_sync.sh
parent: maps/ticket-eligibility.md
---

# ELIG-3: gh_sync onto the shared ticket parser (slice 3 of 3)

> **Staged.** Release with a `mv` into `maps/tickets/` only after ELIG-1 is on `main`. It can run in parallel with ELIG-2 because their `owns:` are disjoint. Re-pin `assignee:` at release.

## Intended Outcome

`lib/gh_sync.sh` parses ticket frontmatter through the ELIG-1 module's **record** instead of its own regex dict. gh_sync is a mirror, not a dispatcher, so it never asks **eligible**. Its terminal-status list is replaced by the module's categories.

## Background

- gh_sync parses frontmatter with its own regex dict (`gh_sync.sh:268`).
- It defaults a missing `status` to `in_progress` (`:283`). Under ADR 0020 that is a fifth eligibility rule.
- It keeps its own terminal-status set (`:350`).

## Done-Criteria

1. **Shared parser.** gh_sync's embedded Python reads tickets through the module (**record**, plus the module's terminal category for issue open/close decisions). The private regex parser and terminal set are deleted.
2. **Missing status.** A ticket with no status is no longer defaulted to `in_progress`. gh_sync reports it as `no status` and does not open or close an issue for it on `--apply`. That is the fail-closed reading, per ADR 0020.
3. **No sync drift.** `bash lib/gh_sync.sh --dry-run` against this repo's `maps/tickets/` produces the same plan before and after the change, apart from the missing-status rows. Paste both outputs in the resolution.
4. **Tests.** `tests/test_gh_sync.sh` covers a no-status ticket and a ticket whose id ≠ filename.
5. **Gate.** `make check` is green with 0 shellcheck warnings.

## Verification Step

```bash
/bin/bash tests/test_gh_sync.sh && make check
bash lib/gh_sync.sh --dry-run    # compare against the pre-change plan
```
