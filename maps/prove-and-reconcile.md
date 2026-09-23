# Wayfinder Map: Prove and Reconcile

## Destination

`main` and `swarm/stampede/integration` are reconciled, DOG-17/18 promoted and pushed; the Autonomous Reviewer Loop
has produced at least one real, harvested `PASS`/`BLOCK` verdict outside the test suites; `arbiter_drain` runs
automatically after a successful enqueue (promote to `main` stays the untouchable human gate); and `CLAUDE.md` /
`ci.yml` no longer claim a stale suite count.

## Notes

- **This map carries execution into its tickets**, per wayfinder's override clause — most of these are "do the
  thing," not "decide the thing." The decisions were already made in the grilling round that chartered this map
  (see Decisions so far); the tickets are the todo list itself.
- Domain: git branch reconciliation, `swarm.config.toml`, the Autonomous Reviewer Loop, ADR authorship.
- Source: `docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md` (PM audit, evidence-backed).
- Core Invariant: `looper` orchestrates and verifies; implementation is delegated to `arch`. Promotion to `main` and
  pushes to `origin` are human-only, always (ADR 0009, `CONTEXT.md` Git Remote Safety).
- Issue tracker: Local Markdown Tracker (`maps/tickets/`) — release directly, per driver instruction (2026-09-23);
  don't stage. `agy-gh` should run `gh_sync --apply` once these land to file the matching GitHub issues.
- `pi` is explicitly **out of scope** for this map (see below).

## Decisions so far

- **Reconcile owner:** precedent (`d7f875f`) shows the human driver did the equivalent fix directly last time;
  continuing that pattern rather than assuming an arch/looper ticket (PROVE-1).
- **`arbiter_drain` steady state (grilled and settled 2026-09-23):** auto-wire it to run immediately after a
  successful `arbiter_enqueue`. ADR 0009 only locks *promote*-to-`main` as sovereign-human; it never decided
  *drain* (which only advances the integration ref). Recorded via a new ADR (PROVE-5), not an amendment to 0009 —
  0009 answers a different question (why direct-to-`main` automerge was rejected).
- **Reviewer-loop proof-run sequencing:** blocked by the reconcile/promote, not parallel to it — no supervisor
  process is currently running (`ps aux` confirmed empty), and a `swarm.config.toml` flip made on an arch worktree
  branch only takes effect once it reaches `main` through the same pipeline the launcher/supervisor read from.
- **Issue tracker mechanics:** local Markdown, released directly into `maps/tickets/` (not staged) — confirmed with
  the driver 2026-09-23; DOG-16 means a released ticket immediately holds a lease on its `owns:` paths.

## Active Frontier

- [Reconcile main into integration, promote and push DOG-17/18](tickets/prove-reconcile-and-promote.md) (PROVE-1)
- [Enable the Reviewer seat](tickets/prove-enable-reviewer-seat.md) (PROVE-2)
- [Prove the Reviewer Loop on a real ticket](tickets/prove-reviewer-loop-real-verdict.md) (PROVE-3) — blocked by PROVE-1, PROVE-2
- [Auto-wire arbiter_drain after enqueue](tickets/prove-auto-wire-arbiter-drain.md) (PROVE-4)
- [Record the arbiter_drain decision in a new ADR](tickets/prove-drain-adr.md) (PROVE-5) — blocked by PROVE-4
- [Fix stale suite-count claims in CLAUDE.md and ci.yml](tickets/prove-fix-suite-count-drift.md) (PROVE-6)

## Not yet specified

- Headless mode (no panes, no focus calls) — flagged in the 9/21 public-readiness review as the capability that
  would make "autonomous" literally true. Not yet scoped; revisit once this map's items land.
- Trust-tax instrumentation — measuring the five proxies named in the 9/21 review instead of the retrospective's
  modeled 80% token-reduction claim. Not yet scoped.

## Out of scope

- Seating or enabling `pi` — its brief was deleted in DOG-7, and kultivait is unreachable on this machine right now
  (`curl localhost:4114` refused, 2026-09-23). Re-propose only once it's actually running.
- Any change to `docs/adr/` or `docs/audits/` history beyond adding the new drain ADR (PROVE-5) — existing records
  aren't rewritten.
