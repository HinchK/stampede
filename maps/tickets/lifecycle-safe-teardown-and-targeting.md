---
id: T-011-fix
title: "Lifecycle Safe Teardown and Target Disambiguation"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: lib/lifecycle.sh
parent: maps/universal-herdr-swarm.md
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
