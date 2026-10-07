---
id: REV-06
title: "Docs/maps-only commits fast-path past the reviewer dispatch"
type: wayfinder:task
status: in_progress
assignee: arch-1-hinchk-stampede
owns: lib/lifecycle.sh,tests/test_review_loop.sh
parent: maps/dispatch-safety-and-review-policy.md
---

# REV-06 -- skip review for pure docs/maps changes

## Intended Outcome

`review_loop_on_gate_green` (in `lib/lifecycle.sh`) checks whether every file changed in the gated commit sits
under a documentation-only path set (`docs/`, `maps/`, `README.md`, `CHANGELOG.md`, `CONTEXT.md`, `STATE.md`
-- verify this list against what root-anchor seats are actually permitted to touch, don't invent a different
list). If so, it emits `ENQUEUE` directly (the pre-review-loop behavior) instead of `DISPATCH_REVIEWER` --
skipping the reviewer round entirely for that ticket.

## Background

Chartered via /wayfinder grilling, 2026-10-07, resolving one of three fog items in
`maps/autonomous-reviewer-loop.md`'s "Not yet specified" section. Scope settled deliberately narrow: **docs/
maps paths only** -- test-file-only changes do NOT qualify for the fast-path, even though the original fog note
mentioned "documentation-only or test-only." Reasoning: weakening a test file is a real, concrete way to hide a
defect under cover of "just tests," and this session has no incident suggesting doc-only changes have ever
hidden a problem, so starting narrow is the safer initial scope. Widening to test-only changes later is a
separate decision, informed by how this one actually performs in practice -- not bundled in here.

## Done-Criteria

1. `review_loop_on_gate_green` determines the full set of files changed in `$sha` (likely `git diff --name-only
   <parent>..<sha>` or equivalent -- use whatever this repo's existing commit-diffing convention already is,
   don't invent a new one) and classifies the commit as docs-only if every changed path matches the
   documentation path set.
2. A docs-only commit emits `ENQUEUE` (bypassing `awaiting_review` state entirely) -- the exact same directive
   shape as when `review_loop_enabled` is `0`, reusing that existing path rather than adding a parallel one.
3. A commit touching even one non-doc file (including test files) takes the normal review-loop path,
   unchanged.
4. Telemetry/logging: a fast-pathed commit is visibly distinguishable from a normal `ENQUEUE` (e.g. a log line
   noting why), so this isn't silently indistinguishable from the review-loop-disabled case when someone's
   reading `.herdr-swarm/traces/` later.
5. Test coverage in `tests/test_review_loop.sh` for: an all-docs commit fast-paths; a mixed commit (one doc
   file + one code file) does not; an all-test-file commit does not (confirming the narrow scope held).
6. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_review_loop.sh
```
