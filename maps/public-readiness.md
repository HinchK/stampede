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
- **DOG-4 resolved (`4cb5f28`):** Relabeled the 80% token reduction claim in `docs/findings/swarm-orchestration-retrospective.md` as modelled per-turn context compaction rather than empirical measurement, added "The Trust Tax" subsection acknowledging total spend increase, and documented the PTY CLI usage reporting limitation.
- **DOG-5 resolved (`113a42f`):** Led README above the fold with the Zero Trust thesis, removed "Autonomous" from tagline, added explicit scope clause distinguishing ungated root seats from gated isolated seats, and enforced verb discipline.
- **DOG-14 resolved (`c0dbadd`):** Pinned shellcheck to v0.11.0 across both macOS and Ubuntu CI runners; addressed SC2119/SC2120 in `lib/preflight.sh` with scoped directives. Also fixed hardcoded home directory paths in `tests/test_partition.sh` (credit to arch-2 on #11).
- **DOG-15 resolved (`a2cbd9f`, PR #12):** Diagnosed and resolved both CI suite failures: macOS failure was due to missing `timeout(1)` (GNU coreutils absent on runner image) causing suite gate to exit 127 and halt drain, resolved via `resolve_timeout()` and `brew install coreutils`; Ubuntu failure was due to case-sensitive file resolution (`t-ser.md` vs `T-SER.md`) in `lib/partition.sh:292`, resolved via ticket frontmatter ID search. PR #9 CI green on both legs.
- **DOG-6 resolved (`0290750`, PR #15):** Added `CONTRIBUTING.md` (prerequisites including Python >= 3.11 for tomllib, `make check`, bash 3.2 platform floor, conventional commits, and the 4 git safety rules) and `SECURITY.md` (reporting route, response window, and the not-a-sandbox caveat).
- **DOG-7 resolved (`a00fafa`, PR #14):** Made kultivait/pi local engine completely optional: `enabled = false` in `[seats.pi]`, generalized `PROXY_CREDENTIALS` and emptied `serve_cmd`, removed `localhost:4114` literals, removed `briefs/pi.md`, and added 18-assertion `tests/test_config.sh`.
- **DOG-3 resolved (via PR #9, `16bf8a3`; closed late as bookkeeping debt):** CI live — `.github/workflows/ci.yml` runs `make check` on `macos-latest` and `ubuntu-latest` for every push and PR. Done-criteria re-verified at close: valid YAML, both legs run the aggregate gate, zero `setup-python` (the stock-interpreter configuration DOG-1 exists to survive stays exercised), no secrets. First run was red on both legs for environment reasons fixed by DOG-15 (`timeout(1)`) and DOG-14 (pinned shellcheck); latest run on `main` is green on both legs.
- **DOG-8 resolved (`30be2ac`, PR #58):** Hermetic test suite for `lib/gh_sync.sh` added in `tests/test_gh_sync.sh` (27 assertions) with stubbed `gh` on PATH testing zero-write dry-run default, drift detection, CREATE proposal label contracts, auth error handling, and directory requirements. Wired into aggregate gate (all 8 suites green).
- **DOG-11 resolved (`bd0b90c`, PR #59):** Fixed fresh-clone partition deadlock where gitignored `.herdr-swarm/integration.jsonl` caused all resolved tickets to be treated as active leaseholders. Inactive determination no longer treats missing gitignored evidence as active; warns once on absent state file. 29 partition suite assertions pass cleanly.

## Active Frontier

Release **one wave at a time** by moving files from `maps/tickets-staged/` into
`maps/tickets/`. A ticket the looper cannot see is a ticket it cannot pull —
that is the gate. Do not use `status:` for this (see hazard 3).

Waves 4–6 are now **charted**: their ticket files live in
`maps/tickets-staged/` with `owns:` lines verified disjoint within each
parallel wave. Release is the human's `mv`; `gh_sync --apply` then files the
GitHub issues for anything released.

- [x] **Wave 1 — runs alone.** DOG-1 interpreter resolver. Unblocks everything;
      the swarm cannot reliably run until it lands.
- [x] **Wave 1.5 — runs alone.** DOG-12 looper promote guardrail. Brief rule and
      `--confirm` gate in `lib/arbiter.sh` ensure human-only base merges.
- [x] **Wave 1.6 — runs alone.** DOG-13 arbiter orchestrator resolution. Anchors governing arbiter to orchestrator root (`$SCRIPT_DIR`), preventing unmerged/decoy target-local arbiters from bypassing promote guardrails.
- [x] **Wave 2 — parallel, file-disjoint.** [x] DOG-2 LICENSE · [x] DOG-3 CI ·
      [x] DOG-4 token-claim relabel · [x] DOG-5 README lede · [x] DOG-6 CONTRIBUTING+SECURITY ·
      [x] DOG-14 lint-toolchain pinning (`c0dbadd`) · [x] DOG-15 arbiter suite CI failure (`a2cbd9f`, PR #12).
      Verified disjoint by inspection of their `owns:` lines.
- [x] **Wave 3 — runs alone.** DOG-7 kultivait optional (shares
      `loop-bot-herd.sh` and `lib/config.sh` with DOG-1).
- [x] **Wave 4 — parallel.** [x] DOG-8 gh_sync tests (PR #58) · [x] DOG-11 fresh-clone partition deadlock (PR #59).
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
