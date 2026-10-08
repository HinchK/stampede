---
id: ROUTE-1
title: "agy-gh brief gains a GitHub/git research mandate with findings-file protocol"
type: wayfinder:task
status: resolved
assignee: arch
owns: briefs/worker-gh.in.md
parent: maps/herdr-native-and-seat-utilization.md
---

# ROUTE-1 -- make agy-gh the GitHub & git research seat, on paper and in practice

## Intended Outcome

`briefs/worker-gh.in.md` (rendered into `agy-gh`'s standing brief) grows a
**Research & Archaeology** responsibility alongside issue lifecycle: GitHub issue/CI
research, `gh api` exploration, and read-only git archaeology on request, delivered as
a findings file at `.herdr-swarm/research/<topic>.md` with a one-line
`RESEARCH DONE <topic> <path>` anchor reply.

## Background

Epic charter 2026-10-07. The retrospective is blunt: `agy-gh` is the most underused
seat of the session — its brief covers claiming/closing/releasing only, so every
research need (CI evidence, issue history, git archaeology) defaulted to `looper`
doing it itself. The fix is a protocol, not a person: a research request shape that
`looper` can dispatch and harvest.

## Done-Criteria

1. Brief gains the research mandate: request shape (3-line preamble: intended
   question, done-criteria = the citations required, verification = the commands to
   re-run), findings-file convention `.herdr-swarm/research/<topic>.md` (topic slug
   unique per request), and the reply anchor `RESEARCH DONE <topic> <path>` so the
   dispatcher can wait on it (pairs with the wait-output hygiene from ROUTE-2).
2. Findings files must cite receipts (issue/PR URLs with numbers, `gh api` endpoints,
   commit shas) — same "claims need receipts" bar as tickets.
3. Boundary wording: research and gh/git **operations** only; no repo write-path git
   (commits/merges/rebases are arch/arbiter territory), no code edits (root-seat
   forbidden paths unchanged).
4. Existing responsibilities (claim/close/release, `-R {{REPO}}` discipline, push
   guardrail) unchanged.
5. `briefs/looper.in.md` is NOT edited here (ROUTE-2 owns it) — but this ticket's
   render must be verifiable standalone: `bash lib/briefs.sh render` output contains
   the new section with variables substituted.

## Verification Step

Human/pm review (brief text, same class as QUOTA-4) plus `make check` green.
Spot-check: render the brief for this slug and confirm the anchor grammar in the brief
matches what ROUTE-2 will tell looper to wait on — the two tickets must not disagree
by one character.

## Notes

The `.herdr-swarm/research/` directory is runtime state (add nothing to the repo tree
for it). Harvesting of `RESEARCH DONE` is deliberately *not* wired into the supervisor
— research is ungated read-only work; the anchor is for the dispatcher's wait-output,
not the verdict pipeline.

## Resolution (2026-10-07)

Done: Core Responsibilities item 2 "Research & Archaeology (read-only, on dispatcher
request)" — 3-line preamble shape (Question / Done-criteria / Verification), findings
at `.herdr-swarm/research/<topic>.md` with unique slug, receipts bar (issue/PR URLs
with numbers, `gh api` endpoints, commit SHAs), anchor
`RESEARCH DONE <topic> <path>` with a worked example. Guardrails gain "Research Is
Read-Only": no repo write-path commits/merges/rebases (arch/arbiter territory), no
code edits; claim/close/release, `-R {{REPO}}`, and push guardrail reworded not at
all. `briefs/looper.in.md` untouched (ROUTE-2). Anchor grammar is exactly
`RESEARCH DONE <topic> <path>` — ROUTE-2's criterion 5 must copy this verbatim.

Receipts:
- `bash lib/briefs.sh render <repo> hinchk-stampede` → all 6 briefs rendered; rendered
  worker-gh.md contains the new section with `{{GH_NAME}}`/`{{SLUG}}`/`{{REPO}}`/
  `{{LOOPER_NAME}}` substituted, zero leftover `{{` placeholders.
- `make check` → `All suites green (19)`, lint 0 warnings.
- `git status` after render → only `briefs/worker-gh.in.md` modified (`.herdr-swarm/`
  gitignored; nothing staged into the repo tree for `research/`).
