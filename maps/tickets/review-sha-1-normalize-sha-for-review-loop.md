---
id: REVIEW-SHA-1
title: "review loop fails closed when the worker anchor carries a short sha and the reviewer a full one"
type: wayfinder:task
status: backlog
assignee: arch
owns: lib/lifecycle.sh, loop-bot-herd.sh, tests/test_review_loop.sh
parent: maps/universal-herdr-swarm.md
---

# REVIEW-SHA-1 -- one canonical sha form across gate, review and arbiter

## Intended Outcome

A ticket whose worker anchor uses a short sha (`ARCH DONE #T d8b4d98`) reviews and
integrates exactly like one using a full sha. No `review_blocked` for a PASS that
names the same commit.

## Background (receipts, PM audit 2026-10-08)

`.herdr-swarm/reviews.json`: CI-FIX-2 stored `sha: "d8b4d98"` (short, copied from the
worker's anchor); the reviewer issued
`REVIEW VERDICT #CI-FIX-2 d8b4d985b4b6ecd2ae867e33956784916e1ff613 PASS` (full).
`lib/lifecycle.sh:248` does `[[ "$sha" == "$cur_sha" ]]` -> history shows
`fail_closed sha-mismatch:expected:d8b4d98` twice (08:48:58Z, 08:51:54Z) and state
`review_blocked`, although the review PASSED. QUOTA-5 (full sha in its anchor) went
`review_passed` normally. Fail-closed is the CORRECT posture and stays; the defect is
non-canonical input.

Side effect to examine: CI-FIX-2's commit reached `swarm/stampede/integration` only as
an ancestor of QUOTA-5's integrate (`fbfd44d`), with no `integrate #CI-FIX-2` record,
while its review state says blocked. Reviewed-and-passed content landed, but via a path
that bypasses the per-ticket enqueue/lease/state accounting.

## Done-Criteria

1. Canonicalise to the full 40-char sha at ONE point (preferred: verdict harvest in
   `loop-bot-herd.sh` where the sha is parsed, `git rev-parse --verify <sha>^{commit}`),
   so `session-verdicts.jsonl`, `reviews.json`, arbiter queue and trace events all carry
   the full form.
2. `review_loop_on_review_verdict` resolves the incoming sha the same way before the
   equality check. Still exact equality after resolution: NO prefix/substring matching
   (short-sha ambiguity is a real hazard), and an unresolvable or ambiguous sha still
   fails closed.
3. Tests: short-anchor + full-verdict PASS succeeds; full-anchor + short-verdict PASS
   succeeds; a different commit sharing no resolution still fails closed; ambiguous or
   unknown sha fails closed.
4. Document a recovery path for a ticket stuck `review_blocked` by this defect
   (e.g. re-verdict with the full sha) and apply it to CI-FIX-2 in the hand-off, or
   state why not.
5. Hand-off states whether the ancestry-integration of CI-FIX-2 left any stale lease or
   queue entry, and whether `arbiter drain` can ever double-merge it.

## Verification Step

`make check` green; replay the CI-FIX-2 shape (short stored, full verdict) in the suite.
