---
id: BORROW-1
title: "Triage OpenRig comparison borrows: adopt, decline, or keep fog — with receipts"
type: wayfinder:decision
status: resolved
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

## Resolution (2026-10-08)

Settled by the driver; recorded by `arch-1`. Per-item triage (research note §7), with every adopt
staged as a ticket in this milestone's map and every fog item carrying its unblocking condition:

| # | Borrow | Verdict | Disposition |
|---|---|---|---|
| 1 | Seeded-regression pairs | **adopt** | [SEEDED-1](seeded-1-seeded-regression-pairs.md) |
| 2 | Stub seat runtime | **fog** | Needs a research pass on the seat-type surface (config binding, brief delivery, headless harness) before it is specifiable — map fog |
| 3 | Evidence hashes on verdicts | **adopt** | [HASH-1](hash-1-evidence-hashes-on-verdicts.md) |
| 4 | `INDETERMINATE` status floor | **adopt** | [STATUS-INDET-1](status-indet-1-indeterminate-floor.md) |
| 5 | Snapshot before `down` | **adopt** | [SNAP-1](snap-1-snapshot-before-down.md) — capture only; restore/resume stays fog |
| 6 | Cross-vendor review seat | **fold** | Realized as the ADR 0018 failover path: [REV-FAILOVER-1](rev-failover-1-non-agy-reviewer-failover.md) |
| 7 | Notification webhook adapter | **fog** | Only justified when headless/CI runs without panes become routine — map fog |

§8 declines **affirmed** (each for the reason the research gave, aligned with standing ADRs):
daemon+SQLite core (flat-file state is `cat`/`jq`-inspectable and matches the bash substrate);
agent-managed topology via MCP tools (agents are the untrusted parties — inverts ADR 0001/0002's
trust boundary); shared-checkout seating (4/6 `index.lock` collision receipt, ADR 0006);
kernel-style default-permissive seats (the posture ADR 0001 exists to prevent); recording reviewer
verdicts as verification (an agent's word for green is the failure mode the supervisor gate
eliminates).

Provenance caveat discharged: adopts were re-checked against this repo's primary sources before
staging (each staged ticket cites repo files, not the external note alone).
