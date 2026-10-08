---
id: HERDR-2
title: "Adopt herdr pane wait-output for single-target waits (seat-verify, quota probe)"
type: wayfinder:task
status: resolved
assignee: arch
owns: herdr-loop-swarm.sh, lib/quota.sh, tests/test_quota.sh, tests/test_cli.sh
parent: maps/herdr-native-and-seat-utilization.md
blocked_by: [HERDR-1]
---

# HERDR-2 -- block, don't poll, on single-target output waits

## Intended Outcome

Call sites whose purpose is "wait until this pane shows X" block on
`herdr pane wait-output <pane_id> --regex <pattern> --timeout <ms>` instead of
poll-read-recheck loops, with a capability probe (`herdr pane wait-output --help`)
that fails soft to today's behavior.

## Background

ADR 0017 Decision 1. Two seams are in scope (the audit may add none without a new
ticket):

1. **Seat-verify wait** (`herdr-loop-swarm.sh`, post-seating verification and the
   auto-queue critical-seat check): today a 2s `agent wait --until ...` poll per
   critical seat. Where the wait is really "seat shows brief-ack output", a
   `wait-output` on the seat pane tightens the signal.
2. **Quota probe block** (`lib/quota.sh` `quota_probe_kind`): the probe reads
   `agent read` once (fine); but any *supervisor/looper* usage that loops the probe
   while a quota banner is pending should block on
   `--regex 'Individual quota reached.*Resets in'` with the existing timeout budget.

Explicitly **out of scope**: the supervisor multi-anchor harvest scan
(`harvest_verdicts`) stays `agent read` + anchored grep (ADR 0017 keep verdict).

## Done-Criteria

1. A shared probe helper (e.g. in `lib/common.sh` or a sibling) detects wait-output
   support once per process and logs one degradation line when absent.
2. Each in-scope seam uses wait-output when probed available, preserving exact current
   semantics when not (same timeouts, same "unknown never fabricated" contract).
3. Standing-brief instruction added is NOT this ticket (briefs are ROUTE-2's owns).
4. Tests: unit coverage of the probe + fallback branching with a stubbed `herdr`
   (existing suites stub herdr the same way); at least one assertion per seam that the
   wait-output path parses `--timeout`/regex args correctly and the fallback path is
   byte-equivalent to current behavior.

## Verification Step

`make check` green. Receipt in the ticket close-out: the probe+fallback branch table
and the stubbed-herdr test names that exercise each branch.

## Notes

Do not widen `--lines` assumptions here unless HERDR-1's alternate-screen assessment
says a seam reads anchored lines beyond 80 rows — then fix that seam with an explicit
`--lines` and cite the audit row.

## Resolution (2026-10-07)

Done. Probe + branch table:

| Seam | wait-output available | wait-output absent |
|---|---|---|
| `herdr_has_wait_output` (lib/common.sh, once-per-process cache) | `pane wait-output --help` rc 0 → cached yes | rc ≠ 0 → cached no + one stderr degradation line |
| seat-verify `swarm_verify_seats` / new `seat_wait_ready` (lib/lifecycle.sh; audit S18/S23 — the ticket's `owns:` omitted lifecycle.sh but the audit routes S23 here) | one `pane wait-output <pane> --regex 'STANDING BRIEF:' --timeout <ms>`, success labels `brief-ready`; timeout FAILS the seat (verdict authoritative, no fallthrough) | byte-identical pre-HERDR-2 `agent wait --until idle --until done --until working --timeout <ms>`, label `interactive-ready` |
| launcher auto-queue critical-seat loop (herdr-loop-swarm.sh S18) | same `seat_wait_ready`, pane resolved from seats.json | same, empty pane → agent-wait fallback |
| `quota_wait_banner` + CLI `wait` (lib/quota.sh, audit S24b) | one `pane wait-output <pane> --regex 'Individual quota reached.*Resets in' --timeout <ms>`, rc normalized to 0/1 | bounded poll of the one-shot probe (the hand-rolled loop this replaces), same no-fabrication contract |

Also per the audit §5 row for the quota probe: `agent read` widened to
`--lines 200` (banner older than 80 rows read stale-unknown under Herdr
0.9.3's alternate-screen model). Multi-anchor harvest scan untouched (ADR
0017 keep verdict). Installed herdr probed: wait-output SUPPORTED.

Stubbed-herdr tests exercising each branch — tests/test_quota.sh: "probe:
capability checked exactly once per process", "probe: one degradation line,
logged once (cached)", "wait: exact wait-output argv (pane + --regex banner
+ --timeout ms)", "wait: wait-output timeout → 1 (verdict authoritative)",
"wait fallback: poll measures banner → 0", "wait fallback: no signal within
budget → 1 (never fabricated)", "wait: empty pane → poll by seat name
despite capability", "CLI: wait blocks on the banner path → exit 0", "CLI:
wait usage error exits 2"; tests/test_cli.sh [16]: "verify: wait-output
path labels brief-ready", "verify: one capability probe across both seats",
"verify: seat pane waited with exact --regex/--timeout argv", "verify:
wait-output path never falls back to agent wait", "verify: fallback labels
interactive-ready (byte-identical)", "verify: fallback issues the exact
pre-HERDR-2 agent-wait argv", "verify: one degradation line per process on
stderr", "verify: wait-output timeout fails the seat with the standing
message", "verify: wait-output timeout is authoritative (no agent-wait
fallthrough)", plus launcher seam greps ("critical-seat loop routes through
seat_wait_ready" / "no direct agent-wait poll left").

Receipts: `make check` → `All suites green (19)`, `Lint clean`, test_quota
57/57, test_cli 73/73.
