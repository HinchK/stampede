# Wayfinder Map: Repo Truth Pass

**Charted:** 2026-11-08 (arch-1-stampede, MILESTONE CHARTER dispatch: *"run ponytail audit
and review, clean-up and update documentation, and communicate how the lib/* tools are
supposed to be used"*) · Follows the post-incident arbiter-fix arc (postmortem §11; PRs
#178–#183 through `71b23e6`, built in plain sessions without a map) · Supersedes nothing
active: `maps/headless-live.md` closed 2026-10-05, `maps/pick-up-where-we-left-off.md`
complete 2026-10-08, `maps/evolving-harness-swarm/map.md` superseded 2026-11-07.

## Why this is the next epic

Receipts, not vibes:

- The last whole-repo audit is 2026-10-09 and its findings 6–8 are permanently lost
  because the report lived outside the repository
  (`docs/audits/2026-10-09-ponytail-audit.md` §4). Everything since — the incident
  discards, the plain-session arbiter-fix arc (PRs #178–#183), AUTOPILOT-1, the prior-art
  borrows — is unaudited surface.
- STATE.md's freshest checkpoint is 2026-11-05, pre-incident; CHANGELOG `[Unreleased]`
  does not yet record the arbiter fixes; HANDOFF.md still carries incident-era notes.
- `lib/` is 31 files / 9,140 lines / ~171 public functions with no per-module usage
  reference — the only guidance is CLAUDE.md's ~10-line cheat-sheet. The postmortem
  (§5) shows what agents building blind on that surface produces.
- Found while charting (2026-11-08): `make test` goes RED from any seated agent pane —
  TEST-ISO-1 below, receipts in its ticket. The verification invariant itself needs one
  repair before the rest of the milestone can be trusted from seats.

## Destination

Done when: the fresh ponytail audit is committed **in-repo** with every finding triaged
(`FIX-NOW` / `CHARTER` / `ACCEPT`) and looper has processed the triage; `docs/lib-guide.md`
is published and linked, covering all 31 lib files with mechanically verified truth; the
public and state docs pass a receipt-backed truth sweep; `make test` is green from plain
shells **and** seated agent panes; `make check` green throughout.

## Notes

- Domain: repo quality audit (ponytail method), documentation truth, library-surface
  reference.
- Sequencing:
  - **TEST-ISO-1** first (or concurrent with AUDIT-1 on the other arch seat): it restores
    "green from any seat," which every later ticket's local verification leans on.
    Disjoint `owns:` from AUDIT-1 (`tests/test_autopilot.sh` vs `docs/audits/…`) — safe
    to dispatch together under the Arch Seat Balancing Convention.
  - **LIBDOC-1** after AUDIT-1: the guide documents the tree the audit assessed; if the
    triage marks lib/ changes `FIX-NOW`, looper resequences.
  - **DOCSWEEP-1** last: folds the whole milestone into STATE.md/CHANGELOG and adds the
    public lib-guide link.
- Class discipline: AUDIT-1 is a research dispatch — findings and triage only;
  implementing any finding is looper's to charter, never inside the audit. LIBDOC-1 and
  DOCSWEEP-1 are docs-class and ride the REV-06 fast path (no reviewer round expected).
- Core Invariants, unchanged: human-only promote/push (GATE-1/GRANT-1 — TEST-ISO-1
  *pins* the agent-pane grant refusal, never weakens it); fail-closed partition checks;
  no cross-pane injection; one project slug (ADR 0019).

## Tickets

| Ticket | Seat | Blocked by | Synopsis |
|---|---|---|---|
| TEST-ISO-1 | arch | — | Make `tests/test_autopilot.sh` hermetic to ambient `HERDR_*` context; pin the agent-pane grant refusal as a tooth; `make test` green from any seat |
| AUDIT-1 | arch | — | Fresh whole-repo ponytail audit; report committed in-repo at `docs/audits/2026-11-08-ponytail-audit.md`; triage table `FIX-NOW`/`CHARTER`/`ACCEPT` |
| LIBDOC-1 | arch | AUDIT-1 | `docs/lib-guide.md` — per-module purpose/consumers/contract for all 31 lib files, mechanically verified; linked from CONTRIBUTING + CLAUDE |
| DOCSWEEP-1 | agy-docs | LIBDOC-1 | Truth-sweep README / user-guide / STATE / CHANGELOG / CONTEXT; archival banners for HANDOFF / LEGACY; README → lib-guide link |

## Decisions so far

- 2026-11-08 (charting): the new audit's numbering is independent of the 2026-10-09
  report; that report's findings 6–8 stay void (its own §4 rule) — overlap is
  cross-referenced by class, never by number.
- 2026-11-08 (charting): committing the audit report in-repo is a done-criterion, not a
  habit — the 2026-10-09 report's loss is the direct cause of this rule.
- 2026-11-08 (charting): the lib usage guide lives at `docs/lib-guide.md` (docs-class)
  rather than expanding CLAUDE.md — CLAUDE.md stays a cheat-sheet pointing at the guide;
  agents read short, humans read deep.
- 2026-11-08 (charting): README.md is owned by DOCSWEEP-1 only — the guide ticket links
  from CONTRIBUTING/CLAUDE instead — so the two docs tickets never share a file and
  cannot conflict even if resequenced.
- 2026-11-08 (found while charting): TEST-ISO-1 — `make test` RED from any seated agent
  pane; reproduced 3× from the arch-1 seat pane; mechanism: `tests/test_autopilot.sh:39`
  → `lib/cli/stampede-autopilot.sh:93-96` → `lib/arbiter.sh:538-553`, `591-594`; CI and
  plain shells green (verified 2026-11-08: `env -u HERDR_ENV -u HERDR_SOCKET_PATH -u
  HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_BIN_PATH make test` →
  "All suites green (34)"; the supervisor's gate runner scrubs `HERDR_*` the same way).
  The product behavior is correct (GATE-1/GRANT-1); the suite's plain-shell environment
  assumption is the defect. Same isolation class as postmortem §4.1 / #164.
- 2026-11-08 (charting): no version work in this milestone — `[Unreleased]` honesty only;
  VERSION stays 0.6.0 and releasing stays the human's act (PUB-5).

## Out of scope

- Implementing anything the audit finds — triage produces the recommendation; chartering
  `FIX-NOW`/`CHARTER` follow-ups is looper's. This map closes on triage processed, not
  on fixes landed.
- ARB-TREE-CACHE-1: its refile condition ("after the arbiter fixes") is met, but it
  re-enters only as an audit finding through triage — not pre-chartered here.
- Any feature work, any 0.7.0 release paperwork, any change to the human-only
  promote/push gates.
