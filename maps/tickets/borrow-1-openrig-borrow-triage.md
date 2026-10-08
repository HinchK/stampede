---
id: BORROW-1
title: "Triage OpenRig comparison borrows: adopt, decline, or keep fog — with receipts"
type: wayfinder:decision
status: backlog
assignee: human
owns: maps/pick-up-where-we-left-off.md
parent: maps/pick-up-where-we-left-off.md
---

# BORROW-1 — decide which OpenRig borrows become tickets

## Question

For each of the seven borrow candidates in
`.herdr-swarm/research/2026-10-08-openrig-comparison-review.md` §7 (and with its §8 declines as counterweights),
decide one of: **adopt** (stage an implementation ticket in this or a named future map), **decline** (with a
reason worth re-reading later), or **fog** (name what research must precede a decision). Record the outcome in
this map's Decisions — an ADR only if a borrow is load-bearing (same bar as ADR 0016 / REV-07).

The seven, abbreviated:

1. **Seeded-regression pairs** — a test only counts if it fails when the defect is seeded; start with verdict
   dedupe and CAS paths.
2. **Stub seat runtime** — a `worker = stub` seat whose scripted agent emits `ARCH DONE` on cue; full pipeline in
   suites, zero model cost.
3. **Evidence hashes on verdicts** — `sha256(log)` + host/pid on `session-verdicts.jsonl` rows.
4. **`INDETERMINATE` floor** — derived-at-read-time status instead of recorded labels.
5. **Snapshot before `down`** — capture transcript tails + verdict state before teardown closes panes.
6. **Cross-vendor review seat** — overlaps REV-07; triage there, cross-reference here.
7. **Notification webhook adapter** — fan-out for headless/CI runs where no pane exists.

## Provenance caveat

The research note is **external and self-labelled** ("do not ingest as authoritative swarm context"): written by
an outside reviewer reading OpenRig at `da5e9a92` (2026-10-08) against stampede `54460e3`. Its factual claims
carry `file:line` receipts and were primary-source checked, but the swarm has not re-verified them, and OpenRig
moves fast — re-check anything load-bearing before building on it.

## Notes

- Nothing here self-dispatches: post-triage staging is looper's to charter.
- Borrows 1 and 2 strengthen the verification core (more ways to prove the gates work); 3–5 are audit/UX
  polish; 6 is REV-07's; 7 only matters if headless/CI usage grows. Suggested triage order: 6 → 1 → 2 → rest.
