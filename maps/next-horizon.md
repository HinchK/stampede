# Wayfinder Map: Next Horizon — close the incident class, prove headless live, keep the surface honest

**Parent epic:** post-`maps/headless-run-mode.md` · **Charted:** 2026-09-24 (arch, from the
"review what we have done and where we need to go from here" brainstorm)

## Where we have been (receipts, not vibes)

Five milestones shipped and promoted since 2026-09-19, each ending verified on
`main` (STATE.md §1–2 carries per-wave receipts):

| Milestone | Map | Outcome |
|---|---|---|
| Herd foundation | `maps/universal-herdr-swarm.md` | Launcher, supervisor, worktrees, arbiter, partition/leases, telemetry |
| Public readiness + multi-provider | `maps/public-readiness.md`, `maps/public-multi-provider.md` | `bin/stampede` CLI (PUB-1..11), provider registry, doctor, init, rich status |
| Autonomous reviewer loop | `maps/autonomous-reviewer-loop.md` | REV-1..5 + PROVE-2/3: verdict-anchored rounds live on real tickets |
| Prove & reconcile | `maps/prove-and-reconcile.md` | PROVE-1/4/5/6/7: promote pipeline rehearsed, auto-drain, drift fixes |
| Headless run mode | `maps/headless-run-mode.md` | HEADLESS-1..7: subprocess harness, harvest wiring, safety caps, `stampede headless`, ADR 0015 |

Suites: 19, all green, 0 shellcheck warnings. The herd now has two run modes
(pane pairing + unattended batch) sharing one gate, one arbiter, one verdict
protocol.

## What is actually unresolved

1. **The incident class is open, not closed.** Two promote-gate bypasses
   (2026-09-23 instructed, 2026-09-24 self-initiated via `herdr pane run`).
   Shipped since: GATE-1 (pane check), BRIEF-1 (brief text with teeth). Both
   are local and advisory-adjacent — the real fix is credential separation:
   **CRED-1** (agy-gh, backlog) researches it; **INCIDENT-1** (agy-docs,
   backlog) records the postmortem; **BRIEF-1** is built and awaiting
   integration + human promote (HORIZON-1).
2. **Headless mode is built but never proven on real work.** Every proof so
   far is hermetic stubs. PROVE-3 proved the reviewer loop live; nothing has
   proven `stampede headless` against a real ticket with a real vendor CLI.
3. **The batch runs without review rounds** (documented HEADLESS-4/6
   boundary: `CONFIG_REVIEW_LOOP=0` in batch mode). Greens integrate on the
   suite gate alone. That is a deliberate, documented risk — it should become
   either a feature (headless reviewer) or an accepted limit with a receipt.
4. **Five tickets sit parked** (`maps/tickets-parked/`), some possibly
   superseded (e.g. `arbiter-batch-integration` by PROVE-4/HEADLESS-6). Parked
   tickets that no longer parse against reality are debt.
5. **Public surface truth.** ADR 0015 is indexed, but the user guide /
   README do not yet teach `stampede headless`; the CHANGELOG's top entry
   should name the version it ships in (version-check discipline, PUB-5).

## Destination

The next horizon is done when: the 2026-09-24 incident class is **closed or
consciously accepted with a written decision** (CRED-1 → decision receipt);
`stampede headless` has **completed at least one real ticket end-to-end on
this repo** with receipts; the batch's no-review boundary is **feature or
accepted-limit, never silent**; and the parked queue and public docs **tell
the truth about what exists**.

## Tickets (charted; release/order is looper's call)

| Ticket | Seat | Blocked by | Synopsis |
|---|---|---|---|
| HORIZON-1 | human | — | Integrate BRIEF-1, promote integration → `main`, push (the standing pipeline) |
| HORIZON-2 | arch | HORIZON-1 (lands the brief the batch reads) | Prove `stampede headless` live: dispatch one real backlog ticket through the batch, receipts in a findings doc |
| HORIZON-3 | arch | HORIZON-2 | Headless reviewer rounds in batch mode — or a written accepted-limit decision |
| HORIZON-4 | agy-docs | HORIZON-1 | User-facing headless docs (user guide section, README, CHANGELOG entry naming the version) |
| HORIZON-5 | pm | — | Parked-queue triage audit: keep/kill each of the five, cross-checking supersession by PROVE-4/HEADLESS-6 |

In-flight incident-epic tickets referenced, not duplicated: **CRED-1**
(research), **INCIDENT-1** (postmortem record), **BRIEF-1** (built, pending
HORIZON-1's promote). CRED-1's answer gates a *future* implementation-or-
acceptance ticket — deliberately not chartered until the research lands.

## Decisions so far

- 2026-09-24 (charting): reference CRED-1/INCIDENT-1 rather than forking
  duplicates — one incident, one epic of follow-ups.
- 2026-09-24 (charting): HORIZON-2 sequences behind HORIZON-1 so the first
  live batch runs with the anti-bypass brief actually promoted (briefs render
  from `main`).
- 2026-09-24 (charting): no CRED-2 until CRED-1 answers — creating an
  implementation ticket for an unresearched mechanism is how theatre starts.
