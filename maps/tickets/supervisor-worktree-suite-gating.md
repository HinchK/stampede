---
id: P2-3
title: "Supervisor Worktree Suite Gating and Drift Validation"
type: wayfinder:prototype
status: resolved
commit: 420d5e6
assignee: arch
prototype_asset: loop-bot-herd.sh,lib/worktree.sh
owns: loop-bot-herd.sh,lib/worktree.sh
parent: maps/universal-herdr-swarm.md
github_issue: 49
github_url: "https://github.com/HinchK/stampede/issues/49"
synced_at: "2026-09-22T03:16:07Z"
---

# Supervisor Worktree Suite Gating and Drift Validation (P2-3)

## Context & Problem Statement

In Phase 2, workers operate in isolated Git worktrees (`.herdr-swarm/worktrees/<seat>`). However, the supervisor daemon (`loop-bot-herd.sh`) historically executed tests inside the root checkout (`$REPO_DIR`), creating a structural false green: changes made in a worker's worktree were not tested, and verdicts simply gated `main`'s code.

PM's comprehensive specification in [docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md) defines the exact requirements for ledger-first seat directory resolution, commit provenance checks, pre- and post-run drift validation, and branch preservation.

## Preamble

1. **Intended Outcome**: `arch` implements P2-3 in `loop-bot-herd.sh` and `lib/worktree.sh` following PM's specification in `docs/audits/2026-09-19-p2-3-supervisor-gating-spec.md`.
2. **Explicit Done-Criteria**:
   - `lib/worktree.sh`:
     - Fix branch reset bug in `worktree_provision`: use `-b` for new branches, and for existing branches, attach without resetting via `-B` to prevent destroying unmerged commits.
   - `loop-bot-herd.sh`:
     - Implement `resolve_seat_gate "$seat"` resolving `GATE_DIR`, `GATE_BRANCH`, and `GATE_ISOLATED` from `.herdr-swarm/seats.json` v2. Fail closed if an isolated worktree is missing.
     - Pre-condition drift check: verify `HEAD == sha` in `GATE_DIR` and `git status --porcelain` is empty (including untracked files). If dirty, record `suite: "stale"` and prompt seat to commit.
     - Execute suite inside `GATE_DIR`:
       `( cd "$GATE_DIR" && TMPDIR="${STATE_DIR}/gate-tmp/${seat}" timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD" ) >"${STATE_DIR}/gate-logs/${seat}-${sha}.log" 2>&1`.
     - Post-condition drift check: re-verify `HEAD == sha` and clean tree. If worker moved tree during test, record `suite: "invalidated"`.
     - Deduplication: only GREEN suite runs retire a ticket; stale/unresolvable/invalidated verdicts do not permanently retire tickets.
   - Quality checks:
     - `shellcheck loop-bot-herd.sh lib/worktree.sh` passes cleanly with 0 warnings.
     - `bash tests/test_worktree.sh` passes 21/21 assertions.
3. **Verification Step**:
   - Run `bash tests/test_worktree.sh`.
   - Run `shellcheck loop-bot-herd.sh lib/worktree.sh`.
   - Commit changes and emit `ARCH DONE #23 <commit_sha>`.
