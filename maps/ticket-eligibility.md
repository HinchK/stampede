# Wayfinder Map: Ticket Eligibility

**Destination**: one module decides whether a ticket may be dispatched (`CONTEXT.md` §16, [ADR 0020](../docs/adr/0020-ticket-eligibility-and-status-categories.md)). Every dispatch path asks it, and no path keeps its own rule.

**Origin**: 2026-11-08 architecture review, candidate #1 (Strong), followed by a two-round grilling with HinchK. Every recommendation was accepted.

## Tickets

| Ticket | Slice | Location | Depends on |
|---|---|---|---|
| [ELIG-1](tickets/elig-1-ticket-eligibility-module.md) | Module, fixture suite, partition + headless onto it | released | — |
| [ELIG-2](tickets-staged/elig-2-supervisor-and-attention-onto-eligibility.md) | Supervisor dispatch guard + attention (GitHub-issue frontmatter) | staged | ELIG-1 on `main` |
| [ELIG-3](tickets-staged/elig-3-gh-sync-onto-ticket-parser.md) | gh_sync on the shared parser | staged | ELIG-1 on `main` |

ELIG-2 and ELIG-3 have disjoint `owns:`, so they can run in parallel once ELIG-1 is promoted.

## Notes

- **Staging**: ELIG-2 and ELIG-3 sit in `maps/tickets-staged/` because releasing a ticket makes it dispatchable immediately. The interactive guard does not honour `assignee:` until ELIG-2 lands. Release each one with a `mv` into `maps/tickets/` only after ELIG-1 is on `main`, not just on `swarm/stampede/integration`.
- **ELIG-1 dispatch needs a one-time human override.** `partition check` is BLOCKED by 13 resolved tickets under the PART-1 rule that ELIG-1 replaces (ADR 0020 decision 4, approved 2026-11-08). Nobody, agent or looper, dispatches around that verdict without the human go-ahead.
- **Seat**: ELIG-1 is pinned to `arch-1-stampede`, the idle-longest seat by `state_change_seq` at the time of writing. Re-pin before release if that has changed.
- **Out of scope**: choosing the seat (arch-1 vs arch-2 balancing); the verdict-ledger and gate-measurement candidates from the same review.
