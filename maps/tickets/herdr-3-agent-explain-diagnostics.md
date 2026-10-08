---
id: HERDR-3
title: "stampede doctor surfaces herdr agent explain for ambiguous seats"
type: wayfinder:task
status: backlog
assignee: arch
owns: lib/cli/stampede-doctor.sh, tests/test_cli_doctor.sh
parent: maps/herdr-native-and-seat-utilization.md
blocked_by: [HERDR-1]
---

# HERDR-3 -- explain, don't guess, in doctor

## Intended Outcome

`stampede doctor` (lib/cli/stampede-doctor.sh), when it finds a seat in an ambiguous
Herdr lifecycle state (`unknown`) or a pane/state mismatch, runs
`herdr agent explain <seat> --verbose` and prints the priority-ordered detection rules
with the one that fired — so the operator sees ground truth instead of re-reading raw
pane text.

## Background

ADR 0017 Decision 2. The retrospective's `focused:true` collision and stale-scrollback
confusion would both have been resolved by one `explain` call. Doctor is the right
home: it is the already-trusted diagnostic surface (own suite
`tests/test_cli_doctor.sh`).

## Done-Criteria

1. Doctor's herdr/seat section gains an explain sub-check: probe
   (`herdr agent explain --help`) → on support, explain per *ambiguous* seat only
   (healthy seats skip it; do not spam N explains for a healthy herd).
2. Output includes the matched rule and, where `--json` is easier to render, a
   condensed human line (rule id + reason), not a JSON dump.
3. Probe-absent (older herdr): doctor prints a one-line "explain unavailable" note and
   continues — never fails the run.
4. No behavioral change to doctor's exit-code contract.
5. Tests extend `tests/test_cli_doctor.sh` with a stubbed `herdr` covering: supported
   + ambiguous seat (explain invoked), supported + healthy herd (explain not invoked),
   unsupported (note, exit contract intact).

## Verification Step

`make check` green. Live receipt: run `stampede doctor` against this session's herd
once landed and paste the explain line for one real seat.

## Notes

Seat-verify failure path in the launcher is deliberately NOT touched here —
`herdr-loop-swarm.sh` is HERDR-2's owns; if the audit says verify needs explain too,
that lands as a follow-up ticket keeping owns disjoint.
