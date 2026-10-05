---
id: QUOTA-1
title: "Probe agy (Antigravity/Gemini) quota headroom via its own pane-output signal"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/quota.sh,tests/test_quota.sh
parent: maps/next-horizon.md
---

# QUOTA-1 -- agy quota probe, read-only

## Intended Outcome

`quota_probe_kind agy` stops always answering `unknown` and instead reports real headroom when it's knowable,
using the same read-only, no-fabrication contract the rest of `lib/quota.sh` already follows
(`ok:<number><unit>` / `unknown` / `error:<msg>`).

## Background

`lib/quota.sh` (shipped under `PUB-9`) is deliberately read-only -- "no throttling, no rerouting, no writes
anywhere" -- and `quota_probe_kind()` answers `unknown` for every registered kind because "no seat-kind CLI
exposes a parseable local usage surface at landing." That premise just failed for real: on 2026-09-30, `looper`
(`agy`/Gemini via Antigravity CLI) hit an account-level quota wall mid-session with a structured, parseable
message in its own pane output:

```
⚠ Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h26m33s.
```

This is a real surface to probe, not a speculative one -- the original parked ticket (`cross-llm-quota-and-
credit-probing`, closed as superseded-in-spirit, see `docs/audits/2026-09-30-parked-queue-triage.md`) imagined
live API header probing across three providers; this ticket is much narrower: read the one signal `agy` already
emits, for `agy` only.

## Done-Criteria

1. `quota_probe_kind agy` scans the seat's own recent pane output (via `herdr agent read <name> --source
   recent-unwrapped`) for the `Individual quota reached... Resets in <duration>` pattern and, when found, reports
   `ok:<seconds>s` (seconds until reset) or an equivalent clear unit -- never a fabricated 0, same as every other
   probe in this file.
2. No match (no quota message in recent output) answers `unknown`, exactly as before -- this is strictly
   additive, not a behavior change for the no-signal case.
3. No throttling, no rerouting, no writes -- same read-only contract as the rest of `lib/quota.sh`. This ticket
   does not touch `loop-bot-herd.sh`'s poll loop.
4. New test coverage in `tests/test_quota.sh` for the match and no-match cases against fixture pane output.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_quota.sh
```

## Notes

Keep this scoped to `agy` and to surfacing the number, not acting on it. If `loop-bot-herd.sh` should eventually
pause dispatch on a seat with known-exhausted quota, that's a separate, future ticket informed by actually having
this probe available first.

## Resolution

- **Author:** `arch-1-hinchk-stampede` (commit `0684b3f639ed7f666dd3ea02443d33b35d0445fd`)
- **Review:** `reviewer-hinchk-stampede` Round 1/2 PASS (`.herdr-swarm/reviews/QUOTA-1-0684b3f639ed7f666dd3ea02443d33b35d0445fd.md`)
- **Integrated:** `0684b3f` onto `swarm/stampede/integration` via `arbiter_enqueue_and_drain`
- **Summary:** `quota_probe_kind agy [seat]` scans recent pane output (via `herdr agent read <seat> --source recent-unwrapped`) for the Antigravity quota wall (`Individual quota reached... Resets in <duration>`) and reports `ok:<seconds>s` computed from the most recent marker. Preserves strictly read-only contract without writes or throttling; answers `unknown` on absent markers, missing seats, or unreadable panes. Added 10 tests in `tests/test_quota.sh` (37/37 pass); `make check` green (19 suites).
