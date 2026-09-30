---
id: PROVE-HEADLESS-1
title: "Prove bin/stampede headless on a real batch run"
type: wayfinder:task
status: backlog
assignee: arch-2
owns: docs/findings/
parent: maps/close-the-gaps.md
github_issue: 88
github_url: "https://github.com/HinchK/stampede/issues/88"
synced_at: "2026-09-30T17:14:49Z"
---

# PROVE-HEADLESS-1 — real headless batch run

## Intended Outcome

`HEADLESS-1` through `HEADLESS-7` shipped a complete unattended batch-drain mode, but `bin/stampede headless` has
never actually been run end-to-end against real queued work — the same "built but unproven" gap the Autonomous
Reviewer Loop had before `PROVE-3` found two real bugs on its first live run. This ticket closes that gap the same
way: run it for real, not in the abstract.

## Background

Do **not** run this against this live repo's own `maps/tickets/` — the backlog is currently empty (everything's
resolved), which would prove nothing, and this repo's own tickets are not a safe sandbox for a first real run of
unattended batch dispatch. Use an ephemeral scratch repo instead, matching this project's own established
dogfooding pattern (see `docs/audits/2026-09-19-dogfooding-rehearsal-receipt.md` for precedent — same idea, applied
to headless mode instead of the interactive launcher).

## Done-Criteria

1. Set up a scratch git repo under `/tmp` with a small number (2-3) of genuinely trivial, safe `backlog` tickets
   (e.g. a one-line doc fix, something with an obvious, low-risk done-criteria).
2. Run `bin/stampede headless` against it with `herdr` deliberately not on `PATH`, confirming no Herdr daemon
   dependency at all.
3. Confirm tickets actually drain: real subprocess dispatch, real suite gate, real harvest, real integration —
   not a dry run.
4. Deliberately exercise at least one safety mechanism from `HEADLESS-5`: either let one ticket hit the
   re-verdict ceiling (a ticket designed to fail its gate) to confirm `DEAD_LETTER` + non-zero exit actually fire,
   or let a subprocess run past its timeout to confirm eviction works. Don't just run the happy path.
5. Write up what actually happened in `docs/findings/headless-batch-run-receipt.md` — real command output, real
   timings, and be honest about anything that didn't work as designed.

## Verification Step

Human/pm review of the receipt doc, including the actual terminal output quoted, not summarized.

## Notes

Dispatch process note (2026-09-30): Dispatch to `arch-2` proceeded via direct `lease_acquire` after `bash lib/partition.sh check` reported BLOCKED (due to PART-1's false positive). This process gap is chartered as `PART-2` and flagged for the eventual review; it does not block the in-flight run.

If something doesn't work as designed, that's the point of this ticket — report it plainly (matching this
project's whole "claims need receipts" ethos) rather than quietly working around it. A found defect here is a
successful outcome for this ticket, same as it was for `PROVE-3`.
