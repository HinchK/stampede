---
id: ELIG-1
title: "Ticket eligibility module: lib/tickets.py + fixture suite; partition and headless onto it"
type: wayfinder:task
status: backlog
assignee: arch-1-stampede
owns: lib/tickets.py, lib/partition.sh, lib/cli/stampede-headless.sh, tests/test_tickets.sh, tests/test_partition.sh, tests/test_headless.sh
parent: maps/ticket-eligibility.md
---

# ELIG-1: deepen Ticket Eligibility into one module (slice 1 of 3)

## Intended Outcome

One module, `lib/tickets.py` with a small bash-callable CLI (the `lib/config.sh` / `lib/pyenv.sh` precedent), owns the following:

- frontmatter parsing (frontmatter only; `id:` canonical)
- id → file lookup
- the status vocabulary and its four categories
- blocker resolution
- `owns:` and `assignee:`

Its interface answers exactly three questions:

1. **record**: the parsed frontmatter for a ticket id.
2. **eligible**: for a ticket, a dispatch mode and a role or seat, eligible or not plus a one-line reason.
3. **claims**: the `owns:` paths held by claimed, unknown and missing-status tickets, plus terminal tickets whose work is queued for the arbiter but not yet integrated.

`lib/partition.sh` and `lib/cli/stampede-headless.sh` stop reading ticket files themselves. Partition keeps only overlap maths and leases. Spec: `CONTEXT.md` §16 and [ADR 0020](../../docs/adr/0020-ticket-eligibility-and-status-categories.md).

## Background

These are the 2026-11-08 architecture review findings, spot-checked:

- **Four parsers.**
  - Whole-file `sed` in `stampede-headless.sh:158,201`, `partition.sh:221-222,335,350` and `loop-bot-herd.sh:412,1247`.
  - Frontmatter-only bash in `owns_parse_ticket` (`partition.sh:70`).
  - Python in `attention.py:201`.
  - A regex dict in `gh_sync.sh:268`.
- **Conflicting rules.**
  - Headless dispatches `backlog|queued` (`stampede-headless.sh:159`).
  - Partition treats `queued` as active (`partition.sh:195,208`) but skips tickets with no status (`:223`).
- **Duplicated terminal set.** It appears at `partition.sh:196,351`, `attention.py:41` and `gh_sync.sh:350`.
- **`assignee:` is filtered nowhere.** It appears on 142 of 143 tickets. Only `gh_sync.sh:285` reads it.

## Done-Criteria

1. **The module.** `lib/tickets.py` implements the following, with **record / eligible / claims** as its only bash-facing interface; blocker resolution, lookup and the status table stay internal.
   - **Status categories**
     - intake: `backlog`, `queued`, `ready`
     - claimed: `in_progress`, `review` and any other in-flight status found in code
     - parked: `blocked`, `paused`
     - terminal: `resolved`, `closed`, `done`, `superseded`, `integrated`, `promoted`
   - **Mode intake table**, inside the module and not in config: `headless` = `backlog|queued`, plus `interactive` and `bounded-looper` entries.
   - **Fail-closed status.** A missing or unknown status is ineligible (reason `no status` / `unknown status: X`) and counts as a claim.
   - **Terminal claims (ADR 0020 decision 4).** A terminal ticket is a claim only while `integration.jsonl` has an entry for its id that is not `integrated`/`promoted`. A ticket absent from the ledger, or a missing ledger, means no claim. This replaces PART-1's "an existing ledger that doesn't name the ticket keeps it active" rule (`partition.sh:196-208`). `superseded` never claims.
   - **Assignee rules.**
     - `human` is never eligible.
     - Roles are aliased onto `lib/roles.py`: `arch`→`architect`, `agy-docs`→`docs`, `agy-gh`→`gh`.
     - A seat is accepted as a seat key (`arch_1`), an agent base name (`arch-1`) or a namespaced agent name (`arch-1-stampede`).
     - Anything else is ineligible with reason `unknown assignee`.
   - **Identity.** Lookup goes id → file by scanning `id:` lines. Filename fallback is allowed only when no file declares that id.
   - **Blockers.** A ticket is ineligible while any `blocked_by:` id is not terminal.
2. **Partition.** `lib/partition.sh` asks the module for **claims**, and its private ticket readers (`_partition_ticket_active`, `_partition_active_conflicts`, `_partition_ticket_file`, `ticket_blockers_open`, the frontmatter half of `owns_parse_ticket`) are deleted or reduced to calls into the module. Overlap maths, `owns_normalize` and leases are unchanged. Keep `ticket_blockers_open` as a thin shim only if `loop-bot-herd.sh:1250` still calls it; ELIG-2 removes that caller.
3. **Headless.** The picker in `lib/cli/stampede-headless.sh` asks **eligible** (mode `headless`, the candidate seat's role) instead of its own `sed` status/id reads. A ticket that isn't eligible is parked with the module's reason, so the `parked — …` output carries the reason.
4. **Tests.** `tests/test_tickets.sh` is a fixture table: a scratch directory of ticket files, each mapped to expected `eligible` + reason and `claims`. It must include one row for each of these:
   - id ≠ filename
   - no status
   - unknown status
   - `queued` (eligible in headless, not a claim)
   - `in_progress` (a claim, not eligible)
   - `assignee: human`
   - `assignee: arch` against an architect seat and against a docs seat
   - `assignee: arch-2-stampede` against `arch_1` and against `arch_2`
   - `assignee: research`
   - an open blocker
   - a terminal blocker
   - `resolved` + ledger entry `queued` (claim)
   - `resolved` + ledger entry `integrated` (no claim)
   - `resolved` + ledger with no entry for it (no claim; the PART-1 regression row)
   - `resolved` with no ledger file (no claim)

   The ticket-reading assertions this replaces are deleted from `tests/test_partition.sh` and `tests/test_headless.sh`, not kept alongside. Overlap and lease tests stay.
5. **Behaviour changes are visible.** The commit message lists the four behaviour changes from ADR 0020 §"Decisions that change behaviour" (1–4) that this slice introduces.
6. **Gate.** `make check` is green with 0 shellcheck warnings, and the module passes `py_compile` under `"$(bash lib/pyenv.sh)"`.

## Dispatch note

Under the current PART-1 rule, `bash lib/partition.sh check` returns BLOCKED for this ticket: 13 resolved tickets that never passed through the arbiter claim `lib/partition.sh`, `lib/cli/stampede-headless.sh`, `tests/test_partition.sh` and `tests/test_headless.sh`. This ticket is what fixes that rule, so dispatching it takes a **one-time human override** (ADR 0020, Consequences). Do not dispatch around the BLOCKED verdict without that explicit human go-ahead. After this lands, the same check should return clear: paste it in the resolution.

## Verification Step

```bash
/bin/bash tests/test_tickets.sh && /bin/bash tests/test_partition.sh && /bin/bash tests/test_headless.sh && make check
# no private ticket reads left in the migrated callers:
grep -nE "sed -nE 's/\^(status|id|blocked_by):" lib/partition.sh lib/cli/stampede-headless.sh   # expect no output
```
