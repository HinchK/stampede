# ADR 0020: One Ticket Eligibility Module and Four Status Categories

- **Status**: Accepted
- **Date**: 2026-11-08
- **Deciders**: HinchK (decided in the ticket-eligibility grilling), Claude (`pm-stampede`, recorded)
- **Consulted**: 2026-11-08 architecture review (candidate #1), `CONTEXT.md` §16 *Ticket Eligibility*, [ADR 0001](0001-fail-closed-profile-and-test-gating.md), [ADR 0012](0012-task-partitioning-and-disjoint-dispatches.md), [ADR 0015](0015-headless-batch-drain-mode.md), map [`maps/ticket-eligibility.md`](../../maps/ticket-eligibility.md)

---

Whether a ticket may be dispatched is decided by one module, `lib/tickets.py`, behind a bash interface (the `config.sh` precedent). Headless, the supervisor dispatch guard, attention and partition ask it, and gh_sync uses its parser. Every status belongs to one of four categories: **intake** (`backlog`, `queued`, `ready`), **claimed** (work in flight), **parked** (`blocked`, `paused`) or **terminal**. Each dispatch mode names its intake set in a table inside the module, not in config. Headless keeps `backlog|queued` per ADR 0015.

We decided this because five modules read ticket frontmatter with four different parsers and three different "dispatchable" rules. The 2026-11-08 review found the following:

- Partition treats `queued` as a path claim, while headless dispatches it.
- Partition skips tickets that have no status, while gh_sync treats a missing status as `in_progress`.
- The terminal-status set is copied four times.
- `attention.py` looks tickets up by filename, but no ticket id matches its filename (143 of 143).
- No dispatch path honours `assignee:`, so `assignee: human` does not stop automated pickup.

## Decisions that change behaviour

1. **`queued` is intake, not a claim.** A queued ticket no longer blocks peers whose `owns:` overlap with it. Only claimed tickets hold paths.
2. **A missing or unrecognised status fails closed.** The ticket is ineligible, and its `owns:` still counts as a claim.
3. **Assignee gates eligibility.**
   - `human` is never dispatchable.
   - A role (`arch`, `agy-docs`, `agy-gh`, … aliased onto `lib/roles.py` roles) is dispatchable only to a seat with that role.
   - A seat is dispatchable only to that seat, after stripping the slug suffix.
   - Any other value is ineligible.
   - A GitHub issue with any assignee becomes `assignee: human`, which keeps today's "assigned issues aren't picked" rule.
4. **A terminal ticket holds its paths only while its work is still queued for the arbiter.** A `resolved`/`done`/`closed` ticket's `owns:` counts as a claim only if `integration.jsonl` has an entry for it that is not yet `integrated` or `promoted`. A ticket missing from the ledger holds no claim. This narrows PART-1's evidence rule (`partition.sh:196-208`), under which any existing ledger that didn't record the ticket as integrated kept the claim. That rule meant every ticket landed outside the arbiter (a direct PR) blocked its paths forever: on 2026-11-08, 13 resolved tickets blocked ELIG-1 itself. The protection PART-1 was for still holds: paths whose work is queued but not merged stay held, matching the lease-until-integration rule in ADR 0012.
5. **Frontmatter only, `id:` canonical.** Ticket fields are never read from the body, and a ticket's id is never derived from its filename. Tickets synthesized from GitHub issues carry full frontmatter.

## Considered options

- **Mode intake sets in `swarm.config.toml`.** Rejected because the intake set is a safety policy, not an operator preference. A configurable intake invites a per-project `in_progress` intake.
- **Renaming the `architect` role to `arch` across the code.** Rejected in favour of one alias table: tickets and briefs keep the domain word `arch`.
- **Pure-bash parser.** Rejected because the drift came from bash `sed` dialects. `attention.py` and gh_sync's embedded Python already live in Python.

## Consequences

- **ELIG-1 needs a one-time human override to dispatch.** Under the pre-ADR rule it is blocked by the resolved tickets it fixes. This is a chicken-and-egg case, not a precedent.
- Seat *choice* (which eligible seat gets the ticket) stays with each dispatcher. It is a separate, later deepening.
- Delivered in three gated slices: ELIG-1 (module, partition, headless), ELIG-2 (supervisor guard, attention), ELIG-3 (gh_sync). Until ELIG-2 lands, the interactive path still ignores `assignee:`.
