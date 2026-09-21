# Wayfinder Map: Stampede Public Readiness

## Destination

`loop-bot-herd-agy` becomes `stampede`: a repository a stranger can clone on a
stock macOS or Linux machine, run `make check` on, understand from its first
screen, and legally use — with the kultivait/pi local engine fully optional and
every claim in the docs backed by something the repo can show.

## Notes

- Domain: bash orchestration, Python interpreter resolution, CI, open-source
  release hygiene, documentation truth.
- Core Invariant: `looper` orchestrates and verifies; implementation is delegated
  to `arch`. The human is the only one who merges to `main`.
- **This map is dogfood.** The target repo is a clone of the orchestrator itself.
  The swarm is rewriting its own source while a pinned copy supervises.
- Suite Gate: `make test`. Lint bar: 0 shellcheck warnings. Platform floor:
  bash 3.2 under `/bin/bash`.
- Issue tracker: Local Markdown Tracker (`maps/tickets/`).

### Hazards specific to this run

1. **`partition_check` / `lease_acquire` have no callers.** File-overlap
   protection is NOT live. Ticket disjointness is enforced by the human releasing
   tickets in waves — never by co-dispatching and hoping.
2. **`blocked_by` is parsed by nothing.** The dependency DAG is advisory prose
   the looper reads. Sequencing is a human act, and it is done by **moving ticket
   files**, not by editing `status:`.
3. **There is no inert ticket status.** `lib/partition.sh:187-199` recognises
   `in_progress` (active), `backlog`/`ready` (dispatchable), and
   `resolved`/`done`/`closed` (inactive only once integrated). Anything else —
   including `blocked` — hits the `*` fail-closed branch and counts as **active**,
   holding a phantom lease on its files. A ticket that is not yet released must
   therefore live **outside** `maps/tickets/`, in `maps/tickets-staged/`.
4. **A fresh clone has no `integration.jsonl`** (`.herdr-swarm/` is gitignored),
   so `partition_check` treats all 38 historical tickets as active lease-holders
   and blocks everything. Harmless today because nothing calls it — see DOG-11,
   which must land before the planned dispatch-path wiring.
3. **`arbiter_drain` and `arbiter_promote` are operator-invoked.** Green verdicts
   enqueue automatically (`loop-bot-herd.sh:261`), then stop. If nothing seems to
   integrate, that is why — run the drain.
5. **DOG-1 edits the supervisor.** It changes `loop-bot-herd.sh`, `Makefile` and
   `lib/config.sh` in the target. Safe only because orchestration runs from a
   separate pinned source repo. Never point the launcher at its own directory.
6. **The Suite Gate is under edit in DOG-1.** `make test` is the gate and the
   Makefile is in scope. A broken Makefile turns every verdict RED — which is
   correct fail-closed behaviour, not a swarm malfunction.

## Decisions so far

- Source of this backlog: `docs/audits/2026-09-21-public-readiness-review.md`
  (external review, authored outside the swarm — evidence-bearing, not
  swarm-certified).
- **First dogfood finding, before the loop ran:** `partition_check` deadlocks in
  any fresh clone because its integration evidence is gitignored. Filed as
  DOG-11. The exercise paid for itself during bootstrap.
- **DOG-1 resolved (`3a9a70d`):** Centralized Python interpreter resolution in
  `lib/pyenv.sh` (`resolve_python()`), replacing bare `python3` invocations across
  `Makefile`, supervisor, library scripts, and test suites with a probe for
  `tomllib` and actionable remediation advice.
- **DOG-12 resolved (`3d679ef`):** Both increments landed (6 suites green):
  - Increment 1 (`a7be67a`): Enforced human-promote invariant in `briefs/looper.in.md` and added `lib/arbiter.sh` promote guardrail requiring `--confirm` or `PROMOTE_CONFIRM=1` (4 new assertions in `tests/test_arbiter.sh`).
  - Increment 2: Established direct-to-base write boundaries and ungated blast radius warnings in `briefs/worker-docs.in.md`, `briefs/worker-gh.in.md`, and `briefs/overseer-pm.in.md`.
- **DOG-13 resolved (`81958f1`):** Resolved governance loading gap where `lib/arbiter.sh` was invoked relative to target cwd rather than orchestrator root. Anchored arbiter resolution to absolute `SCRIPT_DIR` across `lib/briefs.sh` (`ARBITER_BIN`), `briefs/looper.in.md`, and added loud pre-execution checks in `loop-bot-herd.sh` and `herdr-loop-swarm.sh`. (6 suites green, 152 passed; decoy target arbiter with stripped guard confirmed ignored).
- **DOG-2 resolved (`f1c12d9`):** Added verbatim Apache-2.0 `LICENSE` file at repo root with `Copyright 2026 HinchK` (zero placeholders), establishing open-source licensing terms.

## Active Frontier

Release **one wave at a time** by moving files from `maps/tickets-staged/` into
`maps/tickets/`. A ticket the looper cannot see is a ticket it cannot pull —
that is the gate. Do not use `status:` for this (see hazard 3).

- [x] **Wave 1 — runs alone.** DOG-1 interpreter resolver. Unblocks everything;
      the swarm cannot reliably run until it lands.
- [x] **Wave 1.5 — runs alone.** DOG-12 looper promote guardrail. Brief rule and
      `--confirm` gate in `lib/arbiter.sh` ensure human-only base merges.
- [x] **Wave 1.6 — runs alone.** DOG-13 arbiter orchestrator resolution. Anchors governing arbiter to orchestrator root (`$SCRIPT_DIR`), preventing unmerged/decoy target-local arbiters from bypassing promote guardrails.
- [ ] **Wave 2 — parallel, file-disjoint.** [x] DOG-2 LICENSE · DOG-3 CI ·
      DOG-4 token-claim relabel · DOG-5 README lede · DOG-6 CONTRIBUTING+SECURITY.
      Verified disjoint by inspection of their `owns:` lines.
- [ ] **Wave 3 — runs alone.** DOG-7 kultivait optional (shares
      `loop-bot-herd.sh` and `lib/config.sh` with DOG-1).
- [ ] **Wave 4 — parallel.** DOG-8 gh_sync tests (shares `lib/gh_sync.sh` with
      DOG-7) · DOG-11 fresh-clone partition deadlock. Disjoint from each other.
- [ ] **Wave 5 — runs alone.** DOG-9 relative links (touches nearly every
      markdown file; must follow DOG-5).
- [ ] **Wave 6 — HUMAN.** DOG-10 rename + slug migration. Floor down, ref moved
      by hand. Never dispatched unattended.

## Not yet specified

- Trust-tax instrumentation: brief bytes delivered, suite-gate runs per retired
  ticket, re-verdicts per ticket, dispatches per integration, wall-clock per
  ticket. Post-publication; publishing real numbers later beats publishing a
  modelled 80% now.
- Headless mode (no panes, no focus calls) — the capability that would make
  "autonomous" true rather than aspirational.
- Wiring `partition_check` / `lease_acquire` into the dispatch path — **blocked
  on DOG-11**, which this bootstrap discovered.

## Out of scope

- Pushing to `origin`. Human-only, every time.
- Any change to `docs/adr/` or `docs/audits/` history. Those record why the
  fail-closed policies exist; scrubbing them destroys the provenance.
- Renaming `.herdr-swarm/`.
