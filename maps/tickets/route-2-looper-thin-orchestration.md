---
id: ROUTE-2
title: "Looper brief: thin orchestration — dispatch budget, no self-serve research, herdr hygiene"
type: wayfinder:task
status: backlog
assignee: arch
owns: briefs/looper.in.md
parent: maps/herdr-native-and-seat-utilization.md
---

# ROUTE-2 -- looper orchestrates; it does not excavate

## Intended Outcome

`briefs/looper.in.md` gains a **Delegation-First** section: GitHub/git research and
gh operations go to `agy-gh` (research protocol per ROUTE-1); defect diagnosis and
heavy analysis go to an arch seat (research/diagnosis mode per ROUTE-3); looper's own
tool use stays orchestration-class, bounded by an explicit dispatch budget.

## Background

Epic charter 2026-10-07. The week's evidence: the majority of commits were looper's
bookkeeping and it self-served the HL-LEDGER-1 / PART-2-class diagnoses — good
outcomes, wrong seat economics: the opencode GLM engines were idle-capable while the
agy orchestrator burned its context on archaeology.

## Done-Criteria

1. **Dispatch budget heuristic**, stated as a bright line in the brief: if answering a
   question needs more than one round of `gh`/`git log`/`git diff` archaeology, or a
   diagnosis that would produce prose longer than a paragraph, it is a dispatch —
   ROUTE-1 research request to `agy-gh` (GitHub/CI/git questions) or ROUTE-3
   diagnosis dispatch to an arch seat (code questions). Looper's permitted
   orchestration-class checks (partition/lease status, verdict files, quota gate,
   `git status`-level facts) are enumerated so the line is unambiguous.
2. **Wait hygiene** per ADR 0017: for anchor waits (worker `ARCH DONE`, reviewer
   `REVIEW VERDICT`, `RESEARCH DONE`), prefer one
   `herdr pane wait-output <pane> --regex <anchor> --timeout <ms>` over
   wait/get re-check loops; for a confusing pane state, run
   `herdr agent explain <seat> --verbose` before the third re-read.
3. Bookkeeping (map checkboxes, `Decisions so far`, STATE checkpoints) stays looper's
   — this ticket thins research/diagnosis, not accountability.
4. Quota-gate dispatch discipline (QUOTA-4) and every existing guardrail (push,
   cross-pane injection, arbiter paths) unchanged and un-reworded.
5. Render check: `bash lib/briefs.sh render` substitutes cleanly; the anchor grammar
   referenced for `RESEARCH DONE` matches ROUTE-1's brief exactly.

## Verification Step

Human/pm review of the brief text (same class as QUOTA-4) plus `make check` green.
Acceptance evidence after a week of operation routes through ROUTE-4's panel — that is
the falsification loop, not this ticket.

## Notes

Brief-level instructions are followed on best effort (accepted limit, QUOTA-4 class).
Sequencing: do not dispatch until ROUTE-1 and ROUTE-3 are integrated — looper's brief
must not reference protocols whose own tickets have not landed.
