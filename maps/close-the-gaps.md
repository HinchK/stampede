# Wayfinder Map: Close the Gaps

## Destination

`CONTEXT.md` reflects every major concept shipped this session, GitHub Issues mirror the actual ticket backlog via
`gh_sync`, and headless batch mode has been proven against a real run — closing the "shipped but not
documented/synced/proven" gap that's opened up across `agy-docs`, `agy-gh`, and the implementation seats.

## Notes

- Domain: documentation vocabulary, GitHub issue sync, headless batch dispatch.
- Three independent tickets, one per underused seat, confirmed with the driver 2026-09-30 specifically to make
  sure `agy-gh`, `agy-docs`, and the OpenCode (`arch-1`/`arch-2`) panes are all doing real work, not just the
  implementation seats.
- Arch Seat Balancing Convention: a ticket assigned the generic `arch` label resolves to whichever of `arch-1-hinchk-stampede` / `arch-2-hinchk-stampede` has the older (further behind) `state_change_seq` at dispatch time (i.e. whichever has sat idle longest), not always `arch-1`. Check `herdr agent list` at dispatch time to decide.
- No blocking between them — disjoint `owns:`, safe to dispatch all three at once.
- Core Invariant, unchanged: promote/push stay human-only unless a valid session grant exists (`GRANT-1`); no
  cross-pane injection; never trust a self-reported "done" without independent verification.

## Decisions so far

- [Partition superseded status handling](tickets/part-1-superseded-ownership-check.md) (PART-1, resolved): `_partition_ticket_active()` in `lib/partition.sh` now classifies `superseded` as unconditionally inactive (matching `backlog|ready`), releasing path ownership without requiring integration evidence. Suite 41/41 passing; integrated on `swarm/stampede/integration` at `c4603eb`. Unblocks `PROVE-HEADLESS-1`.
- [Expand CONTEXT.md vocabulary](tickets/context-1-vocabulary-expansion.md) (CONTEXT-1, resolved): Added definitions, citations, and `_Avoid_` directives to `CONTEXT.md` for 7 post-Phase 1 concepts (Arbiter Integration Pipeline, Worktree Isolation, Partition & Lease, Autonomous Reviewer Loop, Headless Batch Drain, Session-Scoped Promote Grant, Fail-Closed Ref Resolution). Committed at `5b64e8b`.
- [Backfill GitHub issue sync](tickets/sync-1-gh-issue-backfill.md) (SYNC-1, resolved): Backfilled 44 GitHub issues (#66–#109) with 41 closed and 3 backlog open (`CONTEXT-1` #69, `PART-1` #82, `PROVE-HEADLESS-1` #88), establishing 100% parity (98/98 tickets in sync) between local tickets and upstream GitHub Issues. Committed at `c3cab1f`.
- PROVE-HEADLESS-1 dispatch process note: The PROVE-HEADLESS-1 dispatch was found to have used an irregular path (`lease_acquire` bypassing `check`'s BLOCKED verdict) — substantively harmless since the underlying conflict was PART-1's false positive, but the process gap is real and is now chartered as PART-2.
- [Close lease_acquire check bypass](tickets/part-2-lease-acquire-bypass.md) (PART-2, resolved): Factored active-ticket ownership conflict logic into `_partition_active_conflicts()` so both `partition_check` and `lease_acquire` enforce the identical rule before state mutation (excluding self-ticket for normal dispatch flow). Suite 47/47 passing; integrated on `swarm/stampede/integration` at `9905b54`.

## Active Frontier

- [Prove headless batch mode on a real run](tickets/prove-headless-1-real-batch-run.md) (PROVE-HEADLESS-1) —
  in flight, `arch-2`. (Running headless batch in `/tmp`; flagged for eventual review per PART-2 process note).
- [Recognize superseded in gh_sync.sh](tickets/sync-2-gh-sync-status-vocabulary.md) (SYNC-2) —
  released, staged. (Add `superseded` to `lib/gh_sync.sh` closed-recognition set).




## Not yet specified

- Whether headless mode needs its own `swarm.config.toml` seat overrides (model, timeout) distinct from
  interactive mode — `headless-run-mode.md`'s own open item, revisit once PROVE-HEADLESS-1 has real usage data.

## Out of scope

- Any new feature work beyond closing these three specific gaps — this map is deliberately narrow.
