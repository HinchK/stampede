# Wayfinder Map: Stampede Public Multi-Provider PRD

## Destination

A stranger with **any one** provider CLI on a stock macOS/Linux machine goes
`clone` → `make check` → `stampede doctor` → first **verified green verdict**
inside 15 minutes, following nothing but `docs/user-guide.md`. From there the
same swarm scales to N providers — fallback chains, quota awareness,
cross-provider review — with zero pipeline changes.

**Any provider. Any repo. One verified pipeline.**

## Direction — what this repo is (the step back)

Stampede is not an agent framework and not a CLI wrapper. It is the
**zero-trust supervisor layer between a human and a herd of coding agents** —
CI for delegated coding work:

- `seat` heterogeneous agents (any terminal CLI) in isolated worktrees,
- `dispatch` file-disjoint tickets,
- `verify` every "done" claim by re-running the real suite on the exact sha,
- `integrate` green verdicts via CAS arbiter on a combined-result re-test,
- `promote` only ever by a human.

The architectural asset: **the pipeline is provider-blind.** The only
provider-coupled surfaces are pane seating (CLI kind) and brief delivery
(file path + nonce). Multi-provider is therefore not a feature to bolt on —
it is the existing architecture, exposed and instrumented. The herd has run
Claude + OpenCode/GLM + AGY/Gemini (+ optional local pi) side by side since
P3-1; the public has no way to discover that.

Three gaps between here and the destination:

1. **Onboarding is insider-only.** No single entrypoint, no provider-aware
   doctor, no journey-ordered guide, no demo that proves one full
   verdict loop. The 9-point preflight fails correctly but a stranger
   cannot self-serve from zero.
2. **Provider heterogeneity is implicit.** Nothing detects what you have,
   nothing degrades when a provider is missing/down, and the fact that
   seats are already heterogeneous is buried in ADRs.
3. **Trust claims are uninstrumented.** The README's whole thesis is
   "don't take the agent's word for it" — yet the swarm publishes no
   measured numbers about its own herd (the trust tax). Modelled claims
   were already relabelled once (DOG-4); the fix is instrumentation.

## Design — tenets

1. **The verdict protocol is the universal worker contract.** One anchored
   line (`ARCH DONE #<ticket> <sha>`) from any CLI that can read a brief
   file. No provider SDKs enter the pipeline. Ever.
2. **Fail-closed onboarding.** `doctor` and `init` probe and report; they
   never guess, never substitute, and never write a config that `up`
   would reject. Missing provider = actionable error with install pointer.
3. **Additive CLI surface.** `bin/stampede` is a thin dispatcher:
   `up/down/status/verify` pass through to the launcher unchanged; new
   commands are `lib/cli/stampede-<cmd>.sh` files the dispatcher discovers
   by existence. Features land as new files — the launcher and dispatcher
   stop being edit hotspots.
4. **Provider registry, not provider special-cases.** `lib/providers.sh`
   holds the per-kind probe table (binary, version, brief-delivery notes).
   Pipeline code stays ignorant of it; only `doctor`, `init`, and seating
   consult it.
5. **Instrument before claiming.** Telemetry events carry measured gate
   durations, verdict counts, re-verdict ratios, and provider-reported
   cost when available. Absent data is `unreported`, never modelled.
6. **The human remains the only base-branch mover.** Every wave below
   preserves the promote guardrail (DOG-12) and the human-only remote rule.

## PRD — requirements

### Epoch A — Stranger's First Green

- **R1** Single entrypoint: `stampede <cmd>` delegates to existing scripts;
      old script names stay valid (compat, zero rewrite).
- **R2** `stampede doctor`: provider-aware health table (seat → kind →
      binary → version → OK/MISSING+remediation), scriptable exit codes.
- **R3** `docs/user-guide.md`: journey-ordered (install → doctor → seat →
      first verdict → integrate), every command runnable on a fresh clone.
- **R4** `examples/demo-repo/`: a *real* tiny repo with a genuine test
      suite and three disjoint tickets; a walkthrough that produces one
      supervisor-gated green verdict end to end.
- **R5** Version discipline: `VERSION`, `CHANGELOG.md`, `stampede version`.

### Epoch B — Any Provider

- **R6** `stampede init`: interview (+ `--non-interactive`) writes a valid
      `swarm.config.toml` from probed providers; refuses zero providers;
      never overwrites without `--force` (+ `.bak`).
- **R7** Fallback chains: `kinds = ["opencode","claude"]` per seat; first
      healthy provider seats; `seat.fallback` telemetry event.
- **R8** Cross-provider review lane: with ≥2 providers, reviewer seat is a
      different kind than the implementer; documented, advisory (the suite
      gate stays the only gate).
- **R9** `stampede quota`: read-only provider headroom where the CLI
      exposes it; `unknown` otherwise. No auto-throttling yet.

### Epoch C — Trust Dashboard

- **R10** Trust-tax telemetry schema: gate duration, verdict/re-verdict
      counts per ticket, provider-reported cost when available.
- **R11** `stampede status --rich`: session summary from traces and
      verdicts — tickets by verdict, gates run, integrations, per-seat
      activity, re-verdict ratio.

### North-star metrics

- **M1** Time-to-first-green-verdict on a stock machine with one provider
  CLI, following only the user guide: **< 15 minutes**.
- **M2** Providers configurable with **zero code changes**: ≥4 kinds
  probed (claude, opencode, agy, pi), ordered fallback per seat.
- **M3** Every published trust claim traceable to a telemetry event —
  no modelled numbers.

## Active Frontier

All tickets staged in `maps/tickets-staged/` (invisible to the looper until
the human `mv`s them — same release discipline as the public-readiness
map). Waves continue numbering after that map's Wave 7.

- [x] **Wave 8 — runs alone.** PUB-1 `bin/stampede` entrypoint + CLI convention (`19217bc`).
- [x] **Wave 9 — parallel, file-disjoint.** PUB-2 doctor + provider registry (`9ffdbe8`) · PUB-3 user guide (`d3a03dd`) · PUB-4 demo repo (`a9b6e51`) · PUB-5 version + changelog (`fb63928`).
- [x] **Wave 10 — runs alone.** PUB-6 fallback chains (`c752a8a`).
- [x] **Wave 11 — parallel, file-disjoint.** [x] PUB-7 init (`3a534c0`) · [x] PUB-8 cross-provider reviewer lane (`eda9042`) · [x] PUB-9 quota probing (`d5083eb`) · [x] PUB-10 trust-tax telemetry (`e8a7450`).
- [x] **Wave 12 — runs alone.** PUB-11 rich status (`cf5f7b1`: read-only session trust dashboard over traces/verdicts/arbiter queue; `status --rich|--json` routed by a disclosed seam in `bin/stampede`, plain `status [dir]` delegation unchanged).

Dependency edges (advisory prose; waves enforce them for real):
PUB-2..5 ← PUB-1 · PUB-7 ← PUB-2,PUB-6 · PUB-9 ← PUB-2 · PUB-8 ← PUB-3 ·
PUB-11 ← PUB-10.

## Hazards specific to this run

1. **Queue behind public-readiness Waves 6–7.** DOG-10 (rename) moves the
   floor; DOG-16 (dispatch wiring) owns the supervisor. No PUB ticket owns
   `loop-bot-herd.sh`, `lib/partition.sh`, or `herdr-loop-swarm.sh` except
   PUB-6 — and it runs alone in Wave 10, after DOG-16 lands.
2. **`bin/stampede` encodes script paths.** DOG-10 renames the repo and
   slug but not the script filenames; PUB-1 must resolve them relative to
   its own location (`$SCRIPT_DIR`), never `$PWD` — the DOG-13 lesson.
3. **`README.md` is single-writer.** PUB-1 owns it in Wave 8; later waves
   document in `docs/user-guide.md`, not the README.
4. **`swarm.config.toml` is single-writer per wave** (PUB-6 in W10, PUB-7
   in W11 — never co-dispatched).
5. **The demo repo is fail-closed too.** `examples/demo-repo` carries a
   real `make test` with genuine assertions. A demo with
   `TEST_CMD="true"` would green-light the very lie this product exists
   to catch.
6. **`lib/cli/` must fail closed.** Unknown subcommand → usage + exit 1;
   passthrough commands are delegated, never reimplemented, so launcher
   behaviour stays byte-identical.
7. **Reviewer is advisory.** Cross-provider review (PUB-8) feeds the
   human/looper; only the Suite Gate retires tickets. No second gate.
8. **`gh_sync --apply` files GitHub issues for whatever the human
   releases** — every PUB ticket carries `parent:
   maps/public-multi-provider.md` so the map travels with them.

## Decisions so far

- Source of this backlog: human-directed arch brainstorm (2026-09-21):
   direction → design → PRD → tickets for public ease-of-use and
   multi-provider positioning.
- Supersedes the parked `P3` quota ticket (`maps/tickets-parked/
  cross-llm-quota-and-credit-probing.md`) — PUB-9 revives it, narrowed to
  read-only probing (no auto-pause) to keep the blast radius small.
- Trust-tax instrumentation graduates from public-readiness
  "not yet specified" into PUB-10/PUB-11 here.

## Not yet specified

- Auto-throttling / rerouting on quota exhaustion (PUB-9 is read-only).
- Cost attribution when a provider CLI reports no usage — `unreported`
  until a spec exists.

## Out of scope

- Pushing to `origin`. Human-only, every time.
- Renaming `.herdr-swarm/` or editing `docs/adr/` / `docs/audits/` history.
- Shipping agent runtimes or models — stampede supervises herds, it does
  not become one of them.
- Multi-repo swarms (one target repo per swarm).
