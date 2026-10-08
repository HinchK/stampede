---
id: REVIEW-SHA-1
title: "review loop fails closed when the worker anchor carries a short sha and the reviewer a full one"
type: wayfinder:task
status: resolved
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

## Resolution (2026-10-08)

Resolved in commit `843f08578a58b06e494624c965416c7ed2a1dae0` (`843f085`).

Done per criteria 1-2:
- `loop-bot-herd.sh` harvest canonicalises the ARCH DONE sha at the one boundary
  where every downstream record inherits it (`git rev-parse --verify <sha>^{commit}`,
  quiet); the HEAD fallback now emits the full form too. An unresolvable anchor keeps
  its raw value and fails closed at the existing commit-reality check.
- `lib/lifecycle.sh` gains `review_canonical_sha SHA REPO_DIR` (rc 0 = full sha,
  rc 1 = unresolvable/ambiguous, rc 2 = no repo). `review_loop_on_review_verdict`
  resolves the INCOMING verdict sha before the equality check (rc 1 → fail closed
  `sha-unresolvable`), and best-effort-resolves the STORED sha so legacy short-stored
  states unblock. Exact equality after resolution — no prefix matching. rc 2 (no repo,
  the hermetic fake-sha suite) falls back to today's raw comparison, unchanged.
- Tests `tests/test_review_loop.sh` §12 (real scratch repo): 12a short-anchor +
  full-verdict PASS with canonical ENQUEUE (the CI-FIX-2 replay); 12b full-anchor +
  short-verdict PASS; 12c differing commits fail closed → review_blocked; 12d unknown
  sha fails closed; 12e ambiguous short sha (real 4-hex collision pair built via
  commit-tree) fails closed; 12f no-repo raw-equality regression guard.
  `bash tests/test_review_loop.sh` → 59/59; `make check` green (20 suites).

Recovery path (criterion 4) — NOT applied yet, needs this fix on `main` first:
CI-FIX-2's `reviews.json` entry (`review_blocked` @ short `d8b4d98`) is stale
bookkeeping for an already-resolved ticket. Post-promote, either delete the entry
(recommended — a closed ticket needs no review state; future stray verdicts fail
closed `no-active-review`) or re-deliver the reviewer's PASS verdict after removing
its `review-verdicts.seen` key; with canonical resolution both forms now match.

Side-effect audit (criterion 5), receipts from live state:
- `integration.jsonl` DOES carry a complete CI-FIX-2 record: status `integrated`,
  full sha `d8b4d985…`, fast-forward merge (merge_sha == gated sha). The PM audit's
  "no per-ticket record" claim was wrong — per-ticket enqueue/lease/state accounting
  happened; only the review state entry is stale.
- No CI-FIX-2 lease in `leases.json`. A duplicate future enqueue of the same sha
  cannot double-merge: the commit is already an ancestor of
  `swarm/stampede/integration` (merge-base --is-ancestor confirmed), so a drain merge
  is a no-op, and (ticket, sha) session-verdict dedupe blocks re-gating.
