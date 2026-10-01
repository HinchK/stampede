# Wayfinder Map: Next Horizon — close the incident class, prove headless live, keep the surface honest

**Parent epic:** post-`maps/headless-run-mode.md` · **Charted:** 2026-09-24 (arch, from the
"review what we have done and where we need to go from here" brainstorm)

## Notes

The promote is currently load-bearing, not optional -- main is N tickets behind integration (check `git log --oneline main..swarm/stampede/integration | grep -c 'integrate #'`) and HORIZON-2 cannot safely run until it happens. (Integration promoted through 755227a; count is 0 until new tickets integrate).

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
| Close the Gaps | `maps/close-the-gaps.md` | PART-1, PART-2, PROVE-HEADLESS-1, SYNC-2: partition guards, headless scratch rehearsal |
| Harden Headless Mode | `maps/harden-headless-mode.md` | HL-WT-1, HL-CFG-1, HL-RED-1, HL-TMO-1, HL-DOCS-1: worktree targeting, env knobs, fail-closed exits, wall-clock timeout |

Suites: 19, all green, 0 shellcheck warnings. The herd now has two run modes
(pane pairing + unattended batch) sharing one gate, one arbiter, one verdict
protocol.

## What is actually unresolved

1. **HORIZON-1 is done** (BRIEF-1 integrated and on main, commit 32dc565 confirmed ancestor of main).
2. **CRED-1 was superseded by GRANT-1** (driver's explicit friction/safety-tradeoff call, 2026-09-2x) -- **DECISION-1** (new, dispatched) records this properly; until it lands, the incident class is still technically "unresolved" per this map's own destination criteria.
3. **Headless mode has been proven on a scratch repo** (PROVE-HEADLESS-1) and hardened against everything it found (Harden Headless Mode epic: HL-WT-1/HL-CFG-1/HL-RED-1/HL-TMO-1/HL-DOCS-1, all integrated) -- but never proven live on this repo's own real backlog against the POST-FIX code. **HORIZON-2** (staged, blocked on promote) closes this.
4. **The batch's no-review boundary question** (**HORIZON-3**) is still open, staged behind HORIZON-2 as originally planned.
5. **Parked-queue triage is done** (**HORIZON-5**, this round) -- three tickets closed as superseded, one kept parked, one closed-with-narrower-re-release (**QUOTA-1**).
6. **Public surface truth:** **HORIZON-4** (dispatched) closes the user-doc gap. Separately, CHANGELOG.md's current top entry (0.5.0) has zero mention of anything shipped this entire session (GRANT-1 through HL-DOCS-1) -- that's HORIZON-4's job to fix, called out explicitly in its brief.

## Destination

The next horizon is done when: the 2026-09-24 incident class is **closed or
consciously accepted with a written decision** (CRED-1 → decision receipt via DECISION-1);
`stampede headless` has **completed at least one real ticket end-to-end on
this repo** with receipts (HORIZON-2); the batch's no-review boundary is **feature or
accepted-limit, never silent** (HORIZON-3); and the parked queue and public docs **tell
the truth about what exists** (HORIZON-4, HORIZON-5, QUOTA-1).

## Tickets (charted; release/order is looper's call)

| Ticket | Seat | Blocked by | Synopsis |
|---|---|---|---|
| HORIZON-1 | human | — | Integrate BRIEF-1, promote integration → `main`, push (DONE, commit 32dc565 on main) |
| HORIZON-2 | arch (resolve to concrete idle-longest seat per the Arch Seat Balancing Convention at actual release/dispatch time) | HORIZON-1 (lands the brief the batch reads) | Prove `stampede headless` live: dispatch one real backlog ticket through the batch, receipts in a findings doc (STAGED) |
| HORIZON-3 | arch (resolve to concrete idle-longest seat per the Arch Seat Balancing Convention at actual release/dispatch time) | HORIZON-2 | Headless reviewer rounds in batch mode — or a written accepted-limit decision (STAGED) |
| HORIZON-4 | agy-docs | HORIZON-1, DECISION-1 | User-facing headless docs (user guide section, README, CHANGELOG entry naming the version) (RELEASED) |
| HORIZON-5 | pm | — | Parked-queue triage audit: keep/kill each of the five, cross-checking supersession (DONE, docs/audits/2026-09-30-parked-queue-triage.md) |
| DECISION-1 | agy-docs | — | Correct INCIDENT-1's stale CRED-1 reference; record CRED-1-to-GRANT-1 decision (RELEASED) |
| QUOTA-1 | arch (resolve to concrete idle-longest seat per the Arch Seat Balancing Convention at actual release/dispatch time) | — | Probe `agy` token consumption in lib/quota.sh with tests (RELEASED) |

## Decisions so far

- 2026-09-24 (charting): reference CRED-1/INCIDENT-1 rather than forking
  duplicates — one incident, one epic of follow-ups.
- 2026-09-24 (charting): HORIZON-2 sequences behind HORIZON-1 so the first
  live batch runs with the anti-bypass brief actually promoted (briefs render
  from `main`).
- 2026-09-24 (charting): no CRED-2 until CRED-1 answers — creating an
  implementation ticket for an unresearched mechanism is how theatre starts.
- 2026-09-30 (triage): HORIZON-5 completed; parked queue triaged (3 superseded deleted, 1 kept parked, 1 re-released as QUOTA-1).
- 2026-09-30 (dispatch): DECISION-1 and QUOTA-1 released; HORIZON-4 released from staged. HORIZON-2/3 remain staged until post-fix promote and sequencing.
