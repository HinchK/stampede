# ADR 0008: Supervisor Worktree Suite Gating, Provenance, and Drift Detection

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [P2-3 Specification](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md), [Ticket P2-3](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-worktree-suite-gating.md), [ADR 0002](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0002-exact-sha-supervisor-deduplication.md), [ADR 0006](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0006-git-worktree-worker-isolation.md), [ADR 0007](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md)

---

## 1. Context and Problem Statement

In Phase 2, the swarm architecture introduced isolated Git worktrees ([ADR 0006](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0006-git-worktree-worker-isolation.md), [ADR 0007](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md)), seating coding agents (`arch`, parallel workers) inside dedicated directories (`.herdr-swarm/worktrees/<seat>`) on isolated branches (`swarm/<slug>/<seat>`).

However, empirical auditing ([P2-3 Spec](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md)) uncovered a critical structural vulnerability in the supervisor daemon (`loop-bot-herd.sh`):

1. **Structural False-Green Gate**: The supervisor historically executed test suites exclusively in the root repository checkout (`cd "$REPO_DIR" && $TEST_CMD`). When an isolated worker emitted a completion verdict (`ARCH DONE #<ticket> <sha>`), the supervisor ran tests against the base branch (`main`) in `$REPO_DIR`, where the worker's changes did not exist. The test suite gated clean `main` code, reported `green`, and retired the ticket without testing a single line of the worker's implementation.
2. **Worktree Fallback Hazard**: If an isolated seat's worktree was removed or broken, a naive fallback to `$REPO_DIR` silently recreated the structural false green.
3. **Time-of-Check to Time-of-Use (TOCTOU) Drift**: Autonomous workers often continue modifying files, generating scratch scripts, or editing code *after* printing a verdict line. Gating a worktree whose working directory does not match the verdict's declared commit SHA tests uncommitted, unvetted code. Furthermore, naive git checks (`--untracked-files=no`) ignored stray test files (e.g. `*_test.py`) that test runners would collect during execution.
4. **Branch Reset Data Loss**: In early provisioning prototypes, `worktree_provision` invoked `git worktree add -B "$branch"`. The `-B` flag forcefully resets an existing branch to the baseline ref (`base_branch`), silently wiping out unmerged worker commits.
5. **Divergent Commit Provenance**: Because all worktrees share the common `.git` object store, `git cat-file -e "$sha"` returns success for *any* commit in the repository. A worker could emit a SHA belonging to another worker or to `main`, passing naive existence checks.
6. **Contradictory Ticket Retirement**: Early supervisor versions retired tickets if `suite == "green"` or `suite == "skipped"`. Retiring skipped tickets violated the human escalation requirement, allowing untested changes to be marked permanently complete.

---

## 2. Decision Drivers

- **Zero False-Green Test Passes**: Tests must execute strictly against the worker's actual code in its dedicated worktree directory.
- **Fail-Closed Resolution**: If an isolated seat's worktree cannot be verified, the supervisor must never fall back to the root checkout; it must fail closed and escalate to human operators.
- **Strict TOCTOU Drift Invalidation**: Gated code states must be immutable and clean. If a worker mutates files before or during a test run, the run must be rejected or invalidated.
- **Provenance Authentication**: Declared commit SHAs must be proven to reside on the seat's assigned branch and represent genuine new commits ahead of the baseline.
- **Data Loss Prevention (Branch Preservation)**: Swarm seating must never reset or discard unmerged worker commits.
- **Strict Retirement Boundary**: Only test runs that execute and pass (`green`) may permanently retire tickets.

---

## 3. Considered Options

- **Option A (Root Checkout with Temporary Cherry-Pick)**: Keep supervisor in `$REPO_DIR` and cherry-pick the worker's commit into a scratch branch on `main`. (Hazardous: pollutes root index, risks merge conflicts, and collides with operator work).
- **Option B (Permissive Worktree Fallback)**: Attempt to gate in `worktree_dir`; if missing or errored, fall back to `$REPO_DIR`. (Dangerous: revives the structural false green whenever worktrees are misconfigured).
- **Option C (Ledger-First Fail-Closed Gating with Pre/Post Drift & Provenance Gates)**: Resolve execution directory strictly from `seats.json` v2, enforce 3-point commit provenance, validate pre- and post-condition drift, prevent branch resets, and restrict ticket retirement to `green` verdicts.

---

## 4. Decision

We adopted **Option C**. We established the **Worktree Suite Gating and Drift Validation Engine** in [`loop-bot-herd.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/loop-bot-herd.sh) and [`lib/worktree.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/worktree.sh):

### A. Ledger-First Directory Resolution (`resolve_seat_gate`)
The supervisor resolves the gate directory strictly from `.herdr-swarm/seats.json` v2 by matching the exact namespaced seat identifier (`arch-<slug>`):

```bash
resolve_seat_gate() {
  local seat="$1" ledger="${STATE_DIR}/seats.json" rec
  GATE_DIR="$REPO_DIR"; GATE_BRANCH=""; GATE_ISOLATED=false
  [[ -f "$ledger" ]] || return 0

  rec=$(jq -c --arg s "$seat" '.seats[]? | select(.name == $s)' "$ledger" 2>/dev/null | head -n1)
  [[ -n "$rec" ]] || return 0

  GATE_ISOLATED=$(jq -r '.isolated // false' <<<"$rec")
  GATE_BRANCH=$(jq -r '.branch // empty' <<<"$rec")

  if [[ "$GATE_ISOLATED" == "true" ]]; then
    GATE_DIR=$(jq -r '.worktree_dir // empty' <<<"$rec")
    # FAIL-CLOSED: Missing worktree or detached branch NEVER falls back to root
    [[ -n "$GATE_DIR" && -d "$GATE_DIR" ]] || return 1
    [[ "$(git -C "$GATE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$GATE_BRANCH" ]] || return 1
  else
    GATE_DIR=$(jq -r --arg d "$REPO_DIR" '.worktree_dir // $d' <<<"$rec")
  fi
}
```

- **Fail-Closed Guarantee**: If `GATE_ISOLATED == true` and the directory is missing or invalid, `resolve_seat_gate` returns `1`. The supervisor records `suite: "unresolvable"`, halts gating, alerts `looper`, and **never falls back to the root repository**.

### B. Three-Point Commit Provenance Verification
Before executing tests, the supervisor validates the declared SHA against the common Git directory (`--git-common-dir`):

1. **Existence (V1)**: Verifies the commit object exists:
   ```bash
   git --git-dir="$GIT_COMMON" cat-file -e "${full_sha}^{commit}"
   ```
2. **Branch Containment (V2)**: Confirms the commit is an ancestor of the seat's assigned branch:
   ```bash
   git --git-dir="$GIT_COMMON" merge-base --is-ancestor "$full_sha" "refs/heads/$GATE_BRANCH"
   ```
   *(Rejects commits belonging to other workers or orphaned branches).*
3. **Own Work Assertion (V3)**: Verifies the commit contains at least one new commit ahead of the baseline:
   ```bash
   git --git-dir="$GIT_COMMON" rev-list --count "$BASE_REF..$full_sha" >= 1
   ```
   *(Rejects raw baseline commits from `main`).*

Any failure marks the verdict `suite: "rejected"` with reasons `not_found`, `not_on_branch`, or `not_own_work`, escalating to the human operator without retiring the ticket.

### C. Pre-Condition and Post-Condition Drift Detection (TOCTOU Safety)
To ensure the test suite gates the exact immutable commit state:

1. **Pre-Condition Check**:
   Immediately prior to test execution in `GATE_DIR`:
   ```bash
   [[ "$(git -C "$GATE_DIR" rev-parse HEAD)" == "$full_sha" ]]
   [[ -z "$(git -C "$GATE_DIR" status --porcelain)" ]]
   ```
   - Must be clean **including untracked files** (standard `status --porcelain` without `--untracked-files=no`).
   - If dirty or `HEAD != sha`: records `suite: "stale"`, skips execution, and prompts the agent to commit or clean stray files.
2. **Isolated Test Execution**:
   ```bash
   ( cd "$GATE_DIR" && \
     TMPDIR="${STATE_DIR}/gate-tmp/${seat}" \
     timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD" ) >"${STATE_DIR}/gate-logs/${seat}-${sha7}.log" 2>&1
   ```
   - Uses dedicated per-seat `TMPDIR` to prevent temp file collisions (Hazard H5).
   - Captures output in structured logs for post-mortem analysis.
3. **Post-Condition Check (TOCTOU Invalidation)**:
   Immediately after the suite finishes, the supervisor re-verifies `HEAD == full_sha` and `status --porcelain` is clean.
   - If the worker modified the tree during execution, the verdict is recorded as `suite: "invalidated"` regardless of exit code. **A moving target is never granted green.**

### D. Branch Preservation Invariant (Eliminating `-B`)
In [`lib/worktree.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/worktree.sh), `worktree_provision` is prohibited from using `git worktree add -B`.
- New branches are created with `-b`:
  ```bash
  git -C "$target_dir" worktree add -q -b "$branch" "$wt_dir" "$base_branch"
  ```
- Existing branches are attached **without reset**:
  ```bash
  git -C "$target_dir" worktree add -q "$wt_dir" "$branch"
  ```
  *(Validated against stale commit checks per [ADR 0007](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md)).*

Unmerged worker commits are permanently preserved in Git history and cannot be silently overwritten during re-seating.

### E. Ticket Retirement Semantics
The deduplication and retirement filter in `loop-bot-herd.sh` is strictly restricted:
- **Only `suite == "green"` permanently retires a ticket**.
- `suite == "RED"`: Triggers a fix-and-reverdict cycle; a subsequent verdict with a *new commit SHA* is admitted through the gate ([ADR 0002](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0002-exact-sha-supervisor-deduplication.md)).
- `suite == "stale"` or `"invalidated"`: Excluded from SHA deduplication; once the worker cleans its tree or re-commits, the verdict can be re-evaluated.
- `suite == "rejected"`, `"unresolvable"`, or `"skipped"`: Escalates to human operator and orchestrator; never retired automatically.

---

## 5. Invariants & Safety Guarantees

1. **Gate Placement Invariant**: Automated test commands for isolated seats must execute inside that seat's verified `worktree_dir`. Under no circumstances may an isolated seat be gated in `$REPO_DIR`.
2. **Fail-Closed Seat Resolution**: If an isolated seat's directory does not exist on disk, the suite gate is aborted immediately.
3. **Clean-Tree Invariant**: No test run may proceed if untracked, unstaged, or uncommitted files exist in the worktree.
4. **Immutability Invariant**: Changes to the working tree or branch HEAD during test execution permanently invalidate the test outcome.
5. **Branch Inviolability**: Swarm provisioning commands must never force-reset existing worker branches.

---

## 6. Consequences

### Positive
- **Elimination of Structural False Greens**: Guarantees that code tested by the supervisor is exclusively the code authored by the worker.
- **TOCTOU Robustness**: Eradicates test contamination caused by workers making edits while tests are running.
- **Provenance Integrity**: Prevents workers from claiming false credit for commits on other branches or baseline commits on `main`.
- **Absolute Data Safety**: Workers' unmerged branch commits can never be destroyed by launcher re-seats.
- **Accurate Audit Records**: Session verdict logs record full provenance (`gate_cwd`, `own_commits`, `duration_s`, `log` path), providing total transparency in the Ops telemetry stream.

### Negative / Trade-offs
- **Strict Tree Cleanliness**: Workers cannot leave stray scratch files or untracked test fixtures in their worktrees without failing the pre-condition check (`suite: "stale"`). (This strictness is an intended guarantee of build determinism).
- **Sequential Gating**: Gates execute sequentially (`gate_concurrency = 1`) to avoid port and resource contention until multi-gate resource sandboxing is implemented.

---

## 7. References

- [P2-3 Specification: Supervisor Worktree Suite Gating](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md)
- [Ticket P2-3: Supervisor Worktree Suite Gating and Drift Validation](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-worktree-suite-gating.md)
- [ADR 0002: Exact-SHA Supervisor Protocol and Re-Verdict Deduplication](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0002-exact-sha-supervisor-deduplication.md)
- [ADR 0006: Git Worktree Worker Isolation and Lifecycle Management](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0006-git-worktree-worker-isolation.md)
- [ADR 0007: Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md)
