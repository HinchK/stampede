---
id: ELIG-2
title: "Supervisor dispatch guard and attention ask the ticket eligibility module"
type: wayfinder:task
status: backlog
assignee: arch
blocked_by: ELIG-1
owns: loop-bot-herd.sh, lib/attention.py, tests/test_attention.py, tests/test_attention.sh, tests/test_manual_arbiter.sh
parent: maps/ticket-eligibility.md
---

# ELIG-2: supervisor guard + attention onto Ticket Eligibility (slice 2 of 3)

> **Staged.** Release with a `mv` into `maps/tickets/` only after ELIG-1 is on `main`. Re-pin `assignee:` to the idle-longest arch seat at release.

## Intended Outcome

The interactive and bounded-looper dispatch paths stop applying their own eligibility rules and ask the ELIG-1 module instead. Tickets synthesized from GitHub issues carry full frontmatter, so frontmatter-only parsing reads them correctly. After this slice, `assignee: human` stops automated pickup on every dispatch path.

## Background

- `dispatch_partition_guard` (`loop-bot-herd.sh:1238`), `_dispatch_resolve_ticket` (`:1215`) and `_gate_green_continue` (`:412`) read status and blockers with whole-file `sed` (`:412`, `:1247`, `:1250`).
- `attention.local_ticket_path` (`attention.py:198`) maps id → `maps/tickets/<id>.md`. No ticket's filename equals its id (143 of 143), so local tickets are unreadable in bounded-looper mode.
- `attention.py:214` treats any non-blocked, non-paused, non-terminal status as dispatchable, including `in_progress`.
- `attention.py:618-622` writes `.herdr-swarm/tickets/<id>.md` with only `id`/`owns` frontmatter. The issue's real fields end up in the body, and `blocked_by` "works" only because of a whole-file `sed`.

## Done-Criteria

1. **Supervisor guard.** The dispatch guard and ticket resolution in `loop-bot-herd.sh` call the module's **eligible** (mode `interactive`, or `bounded-looper` when `CONFIG_BOUNDED_LOOPER`) and **record**. No `sed` status/id/blocked_by reads remain in `loop-bot-herd.sh`. The `ticket_blockers_open` shim from ELIG-1 is removed if this was its last caller.
2. **Attention.** `attention.py` imports the module directly. `local_ticket_path`/`local_ticket_status` are deleted, and local terminal-status handling uses the module's categories (`attention.py:41` goes away).
3. **GitHub-issue tickets.** The synthesized tickets carry full frontmatter:
   - `id`
   - `status`: from labels (`loop:ready`→`ready`, `loop:blocked`→`blocked`; open with no loop label→`backlog`)
   - `blocked_by` and `owns`: from the issue body's frontmatter-style lines
   - `assignee`: `human` if the issue has any GitHub assignee, otherwise `arch`

   Today's rule that assigned issues aren't picked (`loop-bot-herd.sh:1172`, `attention.py:192,401`) still holds, now through the assignee rule.
4. **Tests.** `tests/test_attention.py` covers a local ticket whose filename ≠ id (readable), an `in_progress` ticket (not dispatchable), and a GitHub issue with an assignee (synthesized as `assignee: human`, not dispatched). Superseded ticket-reading assertions are deleted.
5. **Gate.** `make check` is green with 0 shellcheck warnings.

## Verification Step

```bash
/bin/bash tests/test_attention.sh && /bin/bash tests/test_manual_arbiter.sh && make check
grep -nE "sed -nE 's/\^(status|id|blocked_by):" loop-bot-herd.sh   # expect no output
grep -n "local_ticket_path\|local_ticket_status" lib/attention.py   # expect no output
```
