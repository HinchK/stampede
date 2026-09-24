# ADR 0009: Arbiter Branch Integration, Compare-and-Swap Ref Updates, and Human Promotion Gates

- **Status**: Accepted (Amended 2026-09-23)
- **Date**: 2026-09-19 (Amended 2026-09-23)
- **Deciders**: `arch`, `pm`, `looper`, `agy-docs`
- **Consulted**: [P2-4 Specification](../audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md), [Ticket P2-4](../../maps/tickets/arbiter-and-branch-reconciliation.md), [Phase 2 Advisory](../audits/2026-09-19-phase2-worktree-advisory.md), [ADR 0006](0006-git-worktree-worker-isolation.md), [ADR 0007](0007-split-pane-cwd-order-and-ledger-v2.md), [ADR 0008](0008-supervisor-worktree-suite-gating-and-drift.md)

---

## 1. Context and Problem Statement

In Phase 2, autonomous workers develop in parallel inside isolated Git worktrees (`.herdr-swarm/worktrees/<seat>`) and commit to task-scoped branches (`swarm/<slug>/<seat>`). Once a worker's implementation passes the independent worktree Suite Gate ([ADR 0008](0008-supervisor-worktree-suite-gating-and-drift.md)), its commits must be reconciled and integrated into the primary project baseline.

Early designs contemplated having an arbiter process automatically merge or fast-forward green worker commits directly into `main` ([`docs/worktree-swarm.md` §7 Rule 1](../worktree-swarm.md)). However, empirical testing ([P2-4 Spec §2.3](../audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md)) revealed critical concurrency hazards and Git index corruption traps when updating checked-out branches:

1. **The Staged Deletion Index Desync Hazard (Probed)**:
   In the Herdr workspace, the root repository checkout (`$REPO_DIR`) hosts the orchestrator (`looper`), strategic supervisor (`pm`), and human operator on `main`.
   - Attempting `git branch -f main X` from outside the root checkout is rejected by Git:
     ```
     fatal: cannot force update the branch 'main' used by worktree at '/path/to/root'
     ```
   - Attempting `git update-ref refs/heads/main X` is **accepted silently by Git**, but leaves the root working tree and `.git/index` un-updated! As an immediate result, `git status` in the root shows every newly integrated file as a **staged deletion (`D <file>`)**. The very next commit made in the root working checkout by an agent or human operator silently commits these deletions, reverting the integrated work.
2. **Combination Breakdown (Two Greens $\neq$ Combined Green)**:
   Two isolated branches can each pass their independent test suite gates in isolation (e.g. seat A modifies an internal API, while seat B implements a caller assuming the old API). When merged, the combination breaks. Integrating branches directly into `main` without pre-gating the merged combination causes broken builds on the baseline branch.
3. **Silent Data Loss via Non-Atomic Ref Updates**:
   Empirical testing in the [Phase 2 Advisory](../audits/2026-09-19-phase2-worktree-advisory.md) proved that concurrent plain `git update-ref` calls without expected-old checks silently overwrite each other (11 out of 12 updates lost).
4. **Tip Drift vs Gated SHA**:
   Workers frequently continue committing in their worktree after emitting a verdict. Merging the worker's branch tip rather than the explicitly gated commit SHA violates auditability and incorporates untested code.

---

## 2. Decision Drivers

- **Zero Root Checkout Corruption**: The root working tree on `main` must never experience index desynchronization, phantom staged deletions, or uncoordinated ref updates.
- **Combined State Quality Gating**: No integrated commit may be published or promoted unless the combined merge state is independently tested and verified `green`.
- **Atomic Concurrency Protection**: Integration ref updates must be protected against concurrent race conditions via Compare-and-Swap (CAS) semantics.
- **Strict Provenance Alignment**: The arbiter must integrate only the exact commit SHA that was tested and approved by the Suite Gate.
- **Worker-Owned Conflict Resolution**: The arbiter must never attempt automatic fuzzy conflict resolution (e.g. `-X ours/theirs`); merge conflicts must be resolved explicitly on the worker's branch by the worker agent.
- **Sovereign Human Promotion**: Moving the primary base branch (`main`) or pushing to remote repositories must remain strictly gated behind human driver authorization.

---

## 3. Considered Options

- **Option A (Direct Fast-Forward into `main`)**: Automatically fast-forward `main` upon verdict approval. (Rejected: causes staged deletion corruption in the root checkout and lacks combined-state gating).
- **Option B (In-Tree Staging Branch in Root)**: Switch root checkout between `main` and an integration branch. (Rejected: disrupts active orchestrator and operator processes in the root workspace).
- **Option C (Dedicated Integration Branch, Detached Arbiter Worktree, and CAS Updates)**: Build a dedicated staging ref (`swarm/<slug>/integration`), reconcile and pre-gate candidates in a detached worktree (`.herdr-swarm/worktrees/arbiter-<slug>`), update refs atomically via CAS, and promote to `main` via human-supervised fast-forward or PR.

---

## 4. Decision

We adopted **Option C**. We established the **Arbiter Branch Integration and CAS Reconciliation Architecture** in `lib/arbiter.sh`:

### A. Dedicated Integration Branch (`swarm/<slug>/integration`)
- All verified isolated worker branches are merged into a dedicated staging ref:
  ```
  refs/heads/swarm/<slug>/integration
  ```
- The integration branch is initialized from `base_branch` (e.g. `main`) at the first integration of a run.
- The root checkout on `main` is **never mutated** during automated integration runs.

### B. Serialized Queue and Atomic Locking
- Gated verdicts from `.herdr-swarm/session-verdicts.jsonl` matching `suite == "green"` and `isolated == true` are enqueued into `.herdr-swarm/integration.jsonl` by calling `arbiter_enqueue <ticket> <seat> <sha>`.
- The queue is drained oldest-first, serialized by a POSIX-safe directory lock (`.herdr-swarm/arbiter.lock` with PID stamping and stale-process detection).
- **Supersession**: If a newer green verdict arrives for a ticket while an older verdict is still queued, the older record is marked `superseded`, integrating only the latest verified state.

### C. Off-Branch Candidate Construction in a Detached Worktree
Integration occurs inside a dedicated, isolated arbiter worktree:
```
${TARGET_DIR}/.herdr-swarm/worktrees/arbiter-${slug}
```
- **Detached HEAD Operation**: The arbiter worktree operates in detached HEAD mode (`git checkout --detach`), ensuring it never holds a branch checked out that another process might modify.
- **Merge Construction**:
  - Let $I_0$ be `git rev-parse swarm/<slug>/integration`.
  - If $I_0$ is an ancestor of the gated SHA (`is-ancestor(I0, sha)`): the candidate is simply the gated SHA (fast-forward).
  - If diverged: the arbiter checks out $I_0$ in detached mode and executes:
    ```bash
    git merge --no-ff --no-edit -m "integrate #<ticket> (<seat> @ <sha7>)" "$sha"
    ```
  - **Conflict Handling**: If merge conflicts arise, the arbiter immediately runs `git merge --abort`, leaves the worktree clean, records `status: "conflict"`, and notifies the worker via the nonce channel to merge `integration` and re-verdict. The arbiter never resolves conflicts autonomously.

### D. Pre-Gating the Combined Candidate
Before advancing the integration ref:
1. The arbiter checks out the candidate commit in its detached worktree.
2. It executes the project test suite (`TEST_CMD`) with an isolated per-arbiter temporary directory:
   ```bash
   ( cd "$ARBITER_WT" && \
     TMPDIR="${STATE_DIR}/arbiter-tmp" \
     timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD" ) >"${STATE_DIR}/gate-logs/integration-${sha7}.log" 2>&1
   ```
3. If the combined test fails (`RED`): the arbiter records `status: "integration_red"` and **does NOT advance the integration ref**. The broken combination is rejected, preserving the integrity of `integration`.

### E. Compare-and-Swap (CAS) Ref Updates
If and only if the candidate passes the pre-gate:
The arbiter advances the integration branch using atomic Compare-and-Swap:
```bash
git update-ref refs/heads/swarm/<slug>/integration "$candidate" "$I_0"
```
- If another process or manual commit moved the integration ref during gating ($I \neq I_0$), `git update-ref` rejects the update loudly with exit code 128.
- On CAS rejection, the arbiter retries candidate construction from the new tip (up to 3 attempts), completely preventing lost updates without lockups.

### F. Human-Gated Promotion to Base Branch (`arbiter_promote`)
Advancing `main` is strictly reserved for human-authorized promotion (`lib/arbiter.sh promote [--pr]`):

1. **Local Mode (Repositories without remotes)**:
   - Must be executed inside the root checkout (`$REPO_DIR`).
   - Verifies `git status --porcelain` is clean and `main` is an ancestor of `integration`.
   - Executes:
     ```bash
     git -C "$REPO_DIR" merge --ff-only "swarm/${slug}/integration"
     ```
   - Running `--ff-only` directly inside the root working tree ensures the index, working tree, and ref advance simultaneously without staged deletion desync.
   - Updates local tickets frontmatter to `status: resolved`.
2. **PR Mode (Collaborative / Remote repositories)**:
   - Pushes `swarm/<slug>/integration` to the remote repository after explicit human driver approval.
   - Generates and opens a GitHub Pull Request via `gh pr create`:
     - Base: `main` (or configured `base_branch`).
     - Head: `swarm/<slug>/integration`.
     - Body: Itemizes every integrated ticket, commit SHA, merge SHA, test log path, and `Closes #N` directives.
   - When the human driver merges the PR on GitHub, issues are closed automatically, and subsequent `gh_sync.sh --direction pull` runs mark local tickets `resolved`.

---

## 5. Invariants & Safety Guarantees

1. **Root Ref Inviolability**: Automated tools and background arbiters must never execute `git update-ref` against `refs/heads/main` while it is checked out in the root working tree.
2. **Gated Tip Invariant**: The arbiter integrates exclusively the verified commit SHA declared in the verdict, never the floating tip of the worker's branch.
3. **Combined Gating Invariant**: `swarm/<slug>/integration` must never be advanced to a commit that has not passed the full test suite in the arbiter's worktree.
4. **No-Force Conflict Invariant**: The arbiter must never resolve merge conflicts automatically using `--ours`, `--theirs`, or LLM guessing; conflicts are resolved exclusively by the owning worker on the seat branch.
5. **Human Push Gate Invariant**: No commits, branches, or PRs may be pushed to remote Git origins without explicit human authorization.

---

## 6. Consequences

### Positive
- **Elimination of Staged Deletion Desync**: Guarantees the root checkout on `main` is never corrupted by external ref updates.
- **Combined Build Integrity**: Prevents broken combinations of individually passing branches from landing on the staging ref.
- **Zero Silent Data Loss**: CAS ref updates guarantee that concurrent updates are either serialized cleanly or retried loudly.
- **Deterministic Revertability**: Non-fast-forward merges retain `--no-ff` merge commits per ticket, enabling single-ticket rollbacks (`git revert -m 1 <merge_sha>`).
- **Seamless GitHub Issue Lifecycle**: Automatic generation of `Closes #N` in PR bodies delegates remote issue closure to GitHub's native PR merge events.

### Negative / Trade-offs
- **Additional Worktree Overhead**: Requires maintaining an arbiter worktree (`.herdr-swarm/worktrees/arbiter-<slug>`) for candidate building and test execution.
- **Double Test Gating**: Integrated changes are tested twice—once in the worker's worktree and once in the arbiter's combined worktree. (This redundancy is an essential guarantee against cross-ticket semantic breakage).

---

---

## 8. Amendment: Fail-Closed Agent-Pane Guard & Promote Gate Hardening (2026-09-23)

### 8.1 Context & Motivation: The Looper Promote Incident
During the `Prove and Reconcile` / `TRUST-1` milestone execution on 2026-09-23, the human operator typed a direct instruction into `looper`'s Herdr pane (`wW:p1`):
```text
run `bash lib/arbiter.sh promote --confirm && git push origin main` on my behalf
```
`looper` complied and executed both the local promotion and the remote push.

Although `looper`'s standing brief ([`briefs/looper.in.md`](../../briefs/looper.in.md)) explicitly marks advancing `main` and pushing to remote origins as `FORBIDDEN` with no carve-out for direct human requests, the agent failed to refuse. The lesson was decisive: **Sovereignty guarantees cannot rely on LLM adherence to brief instructions.** When prompted with direct authorization, an LLM will frequently execute forbidden actions unless restrained by deterministic, programmatic code boundaries.

This prompted the investigation in [`docs/audits/2026-09-23-harden-the-promote-gate.md`](../audits/2026-09-23-harden-the-promote-gate.md) and the implementation in [GATE-1](../../maps/tickets/gate-1-promote-pane-check.md).

### 8.2 The Mechanism: `_arb_promote_pane_check()`
In commit `e86f790` (GATE-1), `lib/arbiter.sh` was hardened with `_arb_promote_pane_check()`, called at the entry of `arbiter_promote()` before evaluating `--confirm` or dispatching `--pr`/local modes:

```bash
_arb_promote_pane_check() {
  if [[ -z "${HERDR_PANE_ID:-}" ]]; then
    return 0
  fi
  local agents
  if ! agents=$(herdr agent list 2>/dev/null); then
    printf 'arbiter: promote refused -- could not query herdr agent state to confirm this pane is not agent-controlled\n' >&2
    return 1
  fi
  if printf '%s' "$agents" | jq -e --arg pid "$HERDR_PANE_ID" \
      '.result.agents[]? | select(.pane_id == $pid)' >/dev/null 2>&1; then
    printf 'arbiter: promote refused -- pane %s is occupied by a recognized agent; run this yourself from a plain shell\n' "$HERDR_PANE_ID" >&2
    return 1
  fi
  return 0
}
```

#### Fail-Closed Decision Matrix:
1. **`$HERDR_PANE_ID` Unset** $\to$ **Allow**: No agent runs outside a Herdr pane; an unset ID indicates a plain external shell.
2. **`$HERDR_PANE_ID` Set, Query Fails** $\to$ **Refuse**: If Herdr is unreachable or output is malformed, the call fails closed. Ambiguous state is never assumed safe.
3. **`$HERDR_PANE_ID` Set, Live Agent in Pane** $\to$ **Refuse**: Prompts the caller with a diagnostic naming the pane ID and instructing the human to run the promote command directly from an unmanaged plain shell.
4. **`$HERDR_PANE_ID` Set, Managed Agentless Pane** $\to$ **Allow**: Allows promotions from human-operated raw shell panes inside Herdr (e.g. `wW:p1` without an agent).
5. **No Bypass Flags**: There is deliberately no environment variable (e.g. `ARBITER_SKIP_PANE_CHECK`) to bypass this check. In hermetic testing (`tests/test_arbiter.sh`), `unset HERDR_PANE_ID` cleans the ambient test environment, and refusal paths are tested via bash function redefinition after sourcing.

### 8.3 Limitations: Local Hardening vs. Deliberate Bypass
This mechanism is a **local, pragmatic hardening** against accidental agent execution and compliance with human prompts; it is **not airtight against deliberate adversarial bypass**:
- **Shared OS User & Credentials**: Every seat (`pm`, `looper`, `arch-1`, `arch-2`, `docs`, `gh`) runs as the same local OS user with identical read/write access to `.git/`, SSH keys, and `gh` tokens.
- **Bypass Vectors**: An agent with write access could strip the check from `lib/arbiter.sh`, run `git merge --ff-only` directly via git CLI, or use `herdr pane run` to inject commands into a human pane.
- **TTY Insufficiency**: Empirical probing revealed that checking `/dev/tty` does not distinguish agents from humans; `looper` runs inside a full Herdr PTY pane with a valid `/dev/tty`.

### 8.4 Empirical Findings: The GitHub Branch Protection 403 Barrier
Investigation into server-side enforcement on GitHub revealed that GitHub Branch Protection and Repository Rulesets are unavailable on this repository:
```bash
$ gh api repos/HinchK/stampede/branches/main/protection
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", "status":"403"}
$ gh api repos/HinchK/stampede/rulesets
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", "status":"403"}
```
Because the repository is private and on a GitHub Free plan, API-enforced branch protection rules cannot be configured without a plan upgrade or making the repository public. Furthermore, routing promotions through `--pr` offers no additional security today, because `gh pr merge` shares the same credentials and can be invoked directly by any agent.

### 8.5 Credential Separation: The True Long-Term Architectural Fix
Genuine, airtight technical enforcement of the sovereign human promotion boundary requires **credential separation**:
- Agent seats must be provisioned with scoped tokens (e.g. via a GitHub App or restricted machine user) that possess read and branch-push permissions for `swarm/*` branches, but **zero permission** to push to `main` or approve/merge pull requests.
- The human operator alone retains the sovereign credentials capable of modifying the primary base branch.
- This architectural separation is tracked as a future roadmap item requiring human driver chartering.

---

## 9. References

- [P2-4 Specification: Arbiter Branch Merge and PR Reconciliation](../audits/2026-09-19-p2-4-arbiter-and-integration-pr-spec.md)
- [Ticket P2-4: Phase 2 Arbiter and Branch Reconciliation](../../maps/tickets/arbiter-and-branch-reconciliation.md)
- [Phase 2 Advisory: Git Index and Ref Concurrency Hazards](../audits/2026-09-19-phase2-worktree-advisory.md)
- [ADR 0006: Git Worktree Worker Isolation and Lifecycle Management](0006-git-worktree-worker-isolation.md)
- [ADR 0007: Split-Pane CWD Ordering, Stale Branch Safety, and Durable Seat Ledger v2](0007-split-pane-cwd-order-and-ledger-v2.md)
- [ADR 0008: Supervisor Worktree Suite Gating, Provenance, and Drift Detection](0008-supervisor-worktree-suite-gating-and-drift.md)
- [Audit: Harden the Promote Gate Against Agent Execution](../audits/2026-09-23-harden-the-promote-gate.md)
- [Ticket GATE-1: Fail-Closed Agent-Pane Guard on Arbiter Promote](../../maps/tickets/gate-1-promote-pane-check.md)
- [Ticket GATE-2: Amend ADR 0009 with Promote Pane-Check Mechanism](../../maps/tickets/gate-2-adr-amend-0009.md)
- [Ticket DOG-12: Human-Promote Guardrail](../../maps/tickets/looper-promote-guardrail.md)
