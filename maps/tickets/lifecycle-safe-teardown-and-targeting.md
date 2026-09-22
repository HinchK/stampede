---
id: T-011-fix
title: "Lifecycle Safe Teardown and Target Disambiguation"
type: wayfinder:prototype
status: closed
assignee: arch
prototype_asset: lib/lifecycle.sh
owns: lib/lifecycle.sh
parent: maps/universal-herdr-swarm.md
github_issue: 33
github_url: "https://github.com/HinchK/stampede/issues/33"
synced_at: "2026-09-22T03:50:13Z"
---

# Lifecycle Safe Teardown and Target Disambiguation (D1 Fix)

## Question

How must `find_workspace_by_cwd` and `swarm_down` in `lib/lifecycle.sh` be hardened so that executing `down` from inside a Herdr pane never closes the caller's workspace unless it strictly matches the target path, and how should seated panes be tracked and selectively retired without terminating unrelated operator panes?

## Preamble

1. **Intended Outcome**: Harden `lib/lifecycle.sh` so `find_workspace_by_cwd` resolves strictly against the requested target directory (never blindly returning `$HERDR_WORKSPACE_ID` when targeting another directory), and `swarm_down` closes only project-recorded seat panes (`.herdr-swarm/seats.json`) with interactive confirmation (or `--yes` bypass).
2. **Explicit Done-Criteria**:
   - `find_workspace_by_cwd "$target"` checks workspace/agent `cwd` matching `$target`. Only returns `$HERDR_WORKSPACE_ID` if the current workspace's cwd actually matches `$target`.
   - `swarm_down` reads `.herdr-swarm/seats.json` if present and closes only recorded panes; falls back to workspace-matched agent panes if absent.
   - `swarm_down` requires interactive confirmation or `-y`/`--yes` before closing panes or workspace.
   - `down <other-dir>` executed from inside workspace `wM` does not touch or close workspace `wM`.
   - Shellcheck passes cleanly with 0 warnings.
3. **Verification Step**: Run `shellcheck lib/lifecycle.sh && bash -c 'source lib/lifecycle.sh; ws=$(find_workspace_by_cwd /tmp); [[ -z "$ws" ]] && echo "PASS: /tmp does not resolve to caller HERDR_WORKSPACE_ID"'`.

## Resolution

Hardened and validated in [`lib/lifecycle.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/lifecycle.sh):
1. **Strict CWD Target Matching (`find_workspace_by_cwd`):** Checks physical pane CWDs across workspaces rather than fragile labels. If `$HERDR_WORKSPACE_ID` is set, verifies that its panes actually match the target directory before returning; returns empty string and exit 0 for unrelated paths (e.g. `/tmp` never matches the caller's workspace).
2. **Recorded Seats Ledger (`seats.json`):** `swarm_down` inspects `.herdr-swarm/seats.json` (validating workspace ID match) to selectively close only recorded swarm panes, preserving operator anchor panes when `--keep-workspace` is specified. Falls back to live workspace agents if the ledger is absent or stale.
3. **Interactive Confirmation Gate (`lifecycle_confirm`):** Prompts the operator before any destructive pane or workspace disposal. Refuses execution (exit 1) in non-interactive environments unless `--yes` / `-y` is explicitly supplied.

