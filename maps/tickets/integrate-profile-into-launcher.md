---
id: T-INT-1
title: "Integrate Profile Detection into Swarm Launcher"
type: wayfinder:prototype
status: resolved
assignee: arch
prototype_asset: herdr-loop-swarm.sh
owns: herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
resolution:
  commit: b6237a0
  verified_by: looper
  date: "2026-09-19"
github_issue: 31
github_url: "https://github.com/HinchK/stampede/issues/31"
synced_at: "2026-09-22T03:50:13Z"
---

# Integrate Profile Detection into Swarm Launcher (T-INT-1)

## Question

How should `herdr-loop-swarm.sh` be integrated with `lib/profile.sh` and `lib/lifecycle.sh` to eliminate hardcoded kultivait defaults, eliminate fake-green `true` test fallbacks, enforce fail-closed pre-run validation, gate auto-queue mode against non-runnable test commands, and resolve workspaces by physical CWD?

## Preamble

1. **Intended Outcome**: Integrate `lib/profile.sh` and `find_workspace_by_cwd` from `lib/lifecycle.sh` into `herdr-loop-swarm.sh`. Replace ad-hoc ecosystem detection and hardcoded fallback defaults (`Standard-Pentest/kultivait`, `TEST_CMD="true"`) with `ensure_profile`. Gate mode `a` (auto-queue) using `test_cmd_is_runnable`. Key workspace resolution strictly by CWD before pane creation.
2. **Explicit Done-Criteria**:
   - `herdr-loop-swarm.sh` sources `lib/profile.sh` and `lib/lifecycle.sh`.
   - `grep -n 'Standard-Pentest\|TEST_CMD="true"' herdr-loop-swarm.sh` returns empty.
   - `ensure_profile "$PWD" 1` is called before layout engine / pane splits.
   - If mode `a` is selected and `! test_cmd_is_runnable "$TEST_CMD"`, launcher aborts with fatal error explaining that auto-queue requires a runnable test gate.
   - Workspace resolution in external mode uses `find_workspace_by_cwd "$PWD"` before falling back to creating a new workspace.
   - Running `herdr-loop-swarm.sh` in a non-git directory or without remotes (non-interactively) exits 1 fail-closed before any panes are created.
3. **Verification Step**: Run:
   `grep -n 'Standard-Pentest\|TEST_CMD="true"' herdr-loop-swarm.sh && exit 1 || true`
   and
   `mkdir -p /tmp/test-empty-repo && (cd /tmp/test-empty-repo && herdr-loop-swarm.sh --mode a < /dev/null 2>&1 | grep -q "FATAL") && rm -rf /tmp/test-empty-repo && echo "PASS: fail-closed profile integration"`

## Verification Log

- Sourced `lib/profile.sh` and `lib/lifecycle.sh` in `herdr-loop-swarm.sh`.
- Deleted hardcoded `Standard-Pentest/kultivait` and `TEST_CMD="true"` defaults; `grep -n 'Standard-Pentest\|TEST_CMD="true"' herdr-loop-swarm.sh` returned empty.
- Verified non-interactive execution in `/tmp/test-empty-repo` fails closed with FATAL before any panes are created.
- Verified auto-queue mode (`-m a`) fails closed with fatal error when `TEST_CMD="none"`.
- Tested `shellcheck herdr-loop-swarm.sh` clean (0 warnings).
- Resolved in commit `b6237a0`.
