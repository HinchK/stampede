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
- Issue tracker: Local Markdown Tracker (`maps/tickets/`). Per driver instruction (2026-09-23), release directly
  rather than defaulting to staging everything — **refined during chartering** to match this repo's own documented
  dispatch hazards (`maps/public-readiness.md` hazards 2–3): `blocked_by` is parsed by nothing (advisory prose in
  `briefs/looper.in.md` only), a released ticket with no `owns:` grabs an exclusive whole-repo lease the moment
  it's dispatched (DOG-16), and `assignee: human` does not reliably stop automated pickup (`lib/gh_sync.sh` never
  calls the real GitHub assignee API). So the three tickets with no real ordering hazard release directly; the
  three that are genuinely sequenced or human-timed stage instead, exactly like DOG-10 did. `agy-gh` should run
  `gh_sync --apply` once Wave 1 lands to file the matching GitHub issues.
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
- **PROVE-2 resolved (`d7c3563`):** Reviewer loop and seat enabled in `swarm.config.toml` (`reviewer.loop = true`, `seats.reviewer.enabled = true`; commit `d7c3563`, 18 suites green).
- **PROVE-6 resolved (`b02609d`):** Fixed stale suite-count claims across `CLAUDE.md`, `.github/workflows/ci.yml`, and `CONTRIBUTING.md` (all 18 suites listed alphabetically; assertion counts dropped to prevent drift; commit `b02609d`).
- **PROVE-4 resolved (`16dd481`):** Auto-wired `arbiter_drain` after successful `arbiter_enqueue` (`arbiter_enqueue_and_drain` in `lib/arbiter.sh`, background drain pass step in `loop-bot-herd.sh`; commit `16dd481`, 53 assertions passing in `tests/test_arbiter.sh`).
- **Wave 1 Complete:** All three Wave 1 tickets (PROVE-2, PROVE-6, PROVE-4) resolved and integrated on `swarm/stampede/integration` at merge commit `430aa44`.

## Active Frontier

**Wave 1 — COMPLETE** (all integrated on `swarm/stampede/integration` at `430aa44`):

- [x] [Enable the Reviewer seat](tickets/prove-enable-reviewer-seat.md) (PROVE-2)
- [x] [Auto-wire arbiter_drain after enqueue](tickets/prove-auto-wire-arbiter-drain.md) (PROVE-4)
- [x] [Fix stale suite-count claims in CLAUDE.md and ci.yml](tickets/prove-fix-suite-count-drift.md) (PROVE-6)

**Wave 2 — staged in `maps/tickets-staged/`, released by human `mv` once ready** (sequenced or human-timed; a
no-`owns:` or `assignee: human` ticket dispatched early would either stall (exclusive lease, DOG-16) or run before
its prerequisites — see Notes):

- [Reconcile main into integration, promote and push DOG-17/18](tickets-staged/prove-reconcile-and-promote.md)
  (PROVE-1) — release and work whenever the human is ready; not gated on anything else in this map.
- [Prove the Reviewer Loop on a real ticket](tickets-staged/prove-reviewer-loop-real-verdict.md) (PROVE-3) —
  release once PROVE-1 and PROVE-2 have both landed on `main`.
- [Record the arbiter_drain decision in a new ADR](tickets-staged/prove-drain-adr.md) (PROVE-5) — release once
  PROVE-4 has landed.

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
