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
- No blocking between them — disjoint `owns:`, safe to dispatch all three at once.
- Core Invariant, unchanged: promote/push stay human-only unless a valid session grant exists (`GRANT-1`); no
  cross-pane injection; never trust a self-reported "done" without independent verification.

## Decisions so far

(none yet — freshly chartered)

## Active Frontier

- [Expand CONTEXT.md vocabulary](tickets/context-1-vocabulary-expansion.md) (CONTEXT-1) — released, `agy-docs`.
- [Backfill GitHub issue sync](tickets/sync-1-gh-issue-backfill.md) (SYNC-1) — released, `agy-gh`.
- [Prove headless batch mode on a real run](tickets/prove-headless-1-real-batch-run.md) (PROVE-HEADLESS-1) —
  released, `arch`.

## Not yet specified

- Whether headless mode needs its own `swarm.config.toml` seat overrides (model, timeout) distinct from
  interactive mode — `headless-run-mode.md`'s own open item, revisit once PROVE-HEADLESS-1 has real usage data.

## Out of scope

- Any new feature work beyond closing these three specific gaps — this map is deliberately narrow.
