---
id: ROUTE-3
title: "Arch brief: research/diagnosis dispatch mode for the opencode GLM engines"
type: wayfinder:task
status: backlog
assignee: arch
owns: briefs/arch.in.md
parent: maps/herdr-native-and-seat-utilization.md
---

# ROUTE-3 -- arch seats take research and diagnosis dispatches, not just implementation

## Intended Outcome

`briefs/arch.in.md` gains a **Research & Diagnosis Dispatches** section: a second
accepted dispatch shape beside implementation tickets. A research/diagnosis dispatch
asks a question answerable from the repo/git/docs (root cause of a defect, spike on a
mechanism, audit of a surface) and is completed by a findings file under
`docs/findings/` plus the normal `ARCH DONE #<id> <sha>` verdict.

## Background

Epic charter 2026-10-07. The driver's read: the opencode GLM panes are not doing
enough of the heavy lifting. Today the arch brief only describes implementation and
critique-refinement postures, so open questions default to looper self-serving them.
The engines exist; the protocol for aiming them at analysis did not.

## Done-Criteria

1. New section defines the dispatch shape: 3-line preamble (intended question,
   done-criteria = required citations/evidence, verification = command(s) whose output
   proves the answer), findings file `docs/findings/<topic>.md` with receipts
   (file:line, command output, shas), and `ARCH DONE #<id> <sha>` on the commit that
   adds the findings file.
2. Findings-only commits are docs-class: they ride the REV-06 fast path past reviewer
   dispatch; the brief says so explicitly so a worker does not expect a review round.
3. Any follow-on *implementation* the research recommends is a new ticket via looper —
   the research dispatch ends at the findings file (single-dispatch scope guardrail
   restated for this mode).
4. Existing implementation/critique protocol text unchanged.
5. Render check via `bash lib/briefs.sh render` for this slug.

## Verification Step

Human/pm review plus `make check` green. Field proof lands with this epic's own
operation: HERDR-1 (the herdr surface audit) is exactly this dispatch shape — run it
as the first live exercise of the mode.

## Notes

Pairing: ROUTE-2's looper brief routes code questions here; this brief accepts them.
The two tickets share no files (arch.in.md vs looper.in.md) — dispatchable in
parallel.
