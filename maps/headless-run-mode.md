# Wayfinder Map: Headless Run Mode

## Destination

`bin/stampede headless [--max-tickets N] [--timeout M]` drains already-queued `backlog` tickets from
`maps/tickets/` without opening any Herdr panes — spawning worker CLIs as direct background subprocesses, using
the reply-channel protocol already in `loop-bot-herd.sh:734-738` for completion signaling instead of terminal
scrollback scraping. This is **additive**: `stampede up` (interactive, pane-based) remains the primary
human-in-the-loop mode and is unchanged. Headless mode exists for CI and unattended batch runs where no Herdr
daemon or display is available at all.

## Notes

- Domain: bash subprocess management, the existing partition/lease/arbiter pipeline (reused, not rebuilt), the
  reviewer loop (reused where seats support it).
- Source: `docs/findings/headless-mode-design.md` (HEADLESS-2 research, corrected 2026-09-24) — read it first, this
  map's tickets are the implementation extract of its recommended slices 3-4.
- Confirmed with the driver 2026-09-24: additive scope (not a pane-based-system replacement), Option A mechanism
  (direct subprocess spawning, not a detached Herdr session) — the CI trigger case has no Herdr daemon available at
  all, which settles the mechanism question the research doc left open.
- Core Invariant, unchanged: `looper` orchestrates and verifies; implementation is delegated to `arch`. Suite Gate,
  partition/lease, and the human promote gate are **reused as-is** — nothing about headless mode should touch or
  re-implement them, only the harvesting/dispatch surface changes.
- Seat scope, per the design doc's table: `arch-1`/`arch-2` (implementers) and `reviewer` run headless.
  `looper`'s interactive dispatch judgment is replaced by a deterministic queue-intake loop over `backlog` tickets.
  `pm`, `agy-docs`, `agy-gh` do not run headless — their work stays interactive/operator-governed.
- Issue tracker: Local Markdown Tracker. HEADLESS-4 through HEADLESS-6 are staged (sequential, each ticket needs
  the last one's actual code to exist) — release by `mv` as each blocker lands, per
  [[feedback-wayfinder-dispatch-hazards]].

## Decisions so far

- [Focus/no-focus investigation](tickets/headless-1-no-focus-dispatch.md) (HEADLESS-1, resolved): this installed
  `herdr` has no `--no-focus` option on `agent prompt`, and live probing showed focus wasn't being stolen in the
  first place. No fix needed or possible; documented in `docs/findings/herdr-semantics.md`.
- [Headless mode design research](tickets/headless-2-headless-design-research.md) (HEADLESS-2, resolved): produced
  `docs/findings/headless-mode-design.md` — architecture comparison, seat scoping, three unattended-specific
  hazards (runaway re-verdict loops, hanging-process lease starvation, silent swallowed alerts), corrected during
  PM review (a fabricated `lib/review.sh` citation fixed to `lib/lifecycle.sh`; a stale reference to HEADLESS-1 as
  still-open work corrected to reflect its actual resolution).
- **Destination and mechanism (grilled and settled 2026-09-24):** additive batch queue drainer, Option A (direct
  subprocess, not a detached Herdr session).
- **CLI naming, corrected during PM guidance (2026-09-24):** `stampede headless`, not `stampede drain --headless`
  — the latter collides with `arbiter_drain`'s already-established meaning (advancing the integration ref), a
  completely different operation from draining the ticket backlog unattended.
- **Re-verdict ceiling is config-driven, not hardcoded (2026-09-24 guidance):** `[headless] max_verdict_attempts`
  in `swarm.config.toml`, matching the `[reviewer].max_rounds` precedent, not a shell constant.

## Active Frontier

- [Headless subprocess harness](tickets/headless-3-subprocess-harness.md) (HEADLESS-3) — resolved, integrated @ b157772.
- [Wire headless verdict harvesting into the supervisor](tickets/headless-4-harvest-wiring.md) (HEADLESS-4)
  — resolved, integrated @ 85b2758.
- [Unattended safety hardening](tickets/headless-5-safety-hardening.md) (HEADLESS-5) — released,
  in progress.
- [`stampede headless` CLI entrypoint](tickets-staged/headless-6-cli-entrypoint.md) (HEADLESS-6) — staged,
  blocked by HEADLESS-5.
- [ADR: Headless Batch Drain Mode](tickets-staged/headless-7-adr.md) (HEADLESS-7) — staged, blocked by HEADLESS-6,
  written against what actually got built.

## Not yet specified

- Whether headless mode needs its own `swarm.config.toml` seat definitions (e.g. `[seats.arch_1].headless_model`)
  or reuses the interactive seat config as-is. Revisit once HEADLESS-3's harness shape is real.

## Out of scope

- Any change to the Suite Gate, partition/lease, or promote-gate mechanics — headless mode is a new dispatch and
  harvesting surface only, reusing all existing correctness gates unmodified.
- A detached/virtual Herdr session (design doc's Option B) — ruled out by the CI trigger case.
- Migrating the interactive pane-based mode to anything — `stampede up` is unchanged, permanently, per the
  additive destination.
