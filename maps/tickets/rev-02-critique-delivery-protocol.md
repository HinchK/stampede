---
id: REV-2
title: "Critique delivery protocol: implementer refinement on existing worktree branch"
type: wayfinder:task
status: resolved
assignee: arch-1
owns: briefs/arch.in.md,briefs/arch.md,docs/user-guide.md
parent: maps/autonomous-reviewer-loop.md
blocked_by: [REV-1]
github_issue: 103
github_url: "https://github.com/HinchK/stampede/issues/103"
synced_at: "2026-09-30T17:16:14Z"
---

# REV-2 — Critique delivery protocol: implementer refinement on existing worktree branch (Wave 2)

## 1. Intended Outcome

1. Update `briefs/arch.in.md` (and re-render `briefs/arch.md`) so implementers know how to respond to critique dispatches (`DISPATCH CRITIQUE: #<ticket> round <N>/<MAX> — see <path>`).
2. When dispatched with a critique on an existing branch:
   - Implementer inspects cited `file:line` findings in `.herdr-swarm/reviews/<ticket>-<sha>.md`.
   - Implementer modifies code within their assigned ticket `owns:` list on the existing worktree branch.
   - Implementer ensures `make test` passes locally.
   - Implementer commits the refinement (`<sha2>`) and re-emits `ARCH DONE #<ticket> <sha2>`.
3. Update `docs/user-guide.md` with documentation on how the critique refinement cycle operates.

## 2. Problem

Currently, `arch` assumes every dispatch is a brand new ticket starting from a clean checkout of base. In an autonomous critique loop, `arch` must iterate on its in-flight branch without abandoning prior progress or creating disjoint worktrees.

## 3. Plan

- `briefs/arch.in.md`: Add Section "Critique and Refinement Dispatches": instructions on reading review reports, refining on the existing branch, re-running test suites, committing, and signaling completion.
- `briefs/arch.md`: Re-render from template.
- `docs/user-guide.md`: Update Cross-Provider Review section to document the autonomous critique loop and implementer refinement behavior.

## 4. Explicit Done-Criteria

- `briefs/arch.in.md` renders cleanly with 0 leftover template variables.
- Clear instructions prohibiting implementers from reverting unrelated code or resetting branches on critique dispatches.
- `make check` green.

## 5. Verification Step

```bash
bash lib/briefs.sh render arch <scratch-slug> && test -s <rendered-path>
make check
```

## 6. Resolution (2026-09-22, `efc857e`)

- **`briefs/arch.in.md`**: Added Section 4 "Critique and Refinement Dispatches" detailing exact protocol for handling `DISPATCH CRITIQUE: #<ticket> round <N>/<MAX> — see <path>`. Instructs implementers to read cited findings from `.herdr-swarm/reviews/<ticket>-<sha>.md`, refine on their in-flight branch without resetting or reverting unrelated code, verify locally with `{{TEST_CMD}}`, commit as `fix: address reviewer critique for #<ticket> (round <N>)`, re-emit `ARCH DONE #<ticket> <sha2>`, and respect `MAX` round budgets.
- **`briefs/arch.md`**: Re-rendered tracked brief through real engine with zero leftover template placeholders.
- **`docs/user-guide.md`**: Updated Section 9 with "The multi-turn critique loop" subsection covering round lifecycle, durable per-round findings audit trail, bounded escalation via `max_rounds`, and preservation of the two core invariants (Suite Gate remains prerequisite; promote remains human-only).
- **Verification**: `bash lib/briefs.sh render arch <scratch-slug>` verified with 0 unexpanded `{{ }}` tokens; `make check` 15/15 suites green, 358 assertions, 0 failed; 0 shellcheck warnings.
