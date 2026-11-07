# Reviewer Post-Mortem: reviewer-hinchk-stampede

### 1. My role and who instructed me
- **Seat**: `reviewer-hinchk-stampede`.
- **Human (HinchK)**: "Research autonomous evaluation and harness self-improvement loops", "why f3b61a3 was filed under three ids", and post-mortem request.
- **Looper (`looper-hinchk-stampede`)**: Review instructions for commits `65a21da` (#EHS-STEP2), `452a47d` (#EHS-10), `4742789` (#EHS-STEP3), `2459ec1` (#EHS-STEP4), `72419b1` (#HARNESS-HARDEN-1), `e1d09b9` (#EHS-STEP2/3), `f3b61a3` (#EHS-10).

### 2. What I did
- Authored `.herdr-swarm/research/harness-self-improvement-patterns.md` (autonomous harness design).
- Reviewed & issued `PASS` verdicts for 7 commits across tickets `EHS-STEP2`, `EHS-10`, `EHS-STEP3`, `EHS-STEP4`, `HARNESS-HARDEN-1` in `lib/lifecycle.sh`, `lib/worktree.sh`, `lib/briefs.sh`, `lib/arbiter.sh`.
- Audited `f3b61a3` integration queue triplication in `.herdr-swarm/integration.jsonl` (lines 156–158).

### 3. What failed or went wrong
- `f3b61a3` conflicted with integration ref `e1d09b9` in `tests/test_setup.sh` (`.herdr-swarm/integration.jsonl:156`).
- Arbiter waste & thrashing: identical tree `f3b61a3` was queued 3 times under different IDs, triggering redundant 300s test suite runs (`lib/arbiter.sh:380-425`).
- Flaky/fragile tests: `tests/test_setup.sh` failed under ambient swarm environment variables until scrubbed.

### 4. Work I did or saw that the human did not explicitly ask for
- Four-T scorecard (Tokens, Time, Toil, Trouble) metrics infrastructure in `lib/lifecycle.sh` (proposed by agents/looper).
- Autonomous harness self-improvement mutation framework (prompt evolution loops in research/spec).
- Looper synthetic batch re-queuing of tickets at latest git HEAD in `reviews.json`.

### 5. What I would delete, stop, or not have built
- **Delete**: Four-T scorecard, autonomous harness mutation loops, and multi-ticket synthetic re-queuing.
- **Stop**: Arbiter running full 300s test suite on doc-only changes or identical git trees already at integration HEAD.
- **Simplify**: Reduce Stampede back to a single orchestrator running tasks in worktrees without multi-layer supervisor bureaucracy.

### 6. What stops the swarm recovering itself
- **Synthetic queue state**: The looper re-queues stale tickets onto new SHAs without worker re-verification, creating synthetic git conflicts.
- **Fail-closed unassisted halts**: Arbiter halts on merge conflicts or tree drift; no automated rebase or handback protocol exists that resolves conflicts without human or manual triage.
- **Test environment pollution**: Test suite checks fail when running inside ambient swarm session contexts without manual environment scrubbing.
