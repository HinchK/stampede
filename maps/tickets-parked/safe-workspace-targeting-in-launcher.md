---
id: T-016c
title: "Safe Workspace Discovery in Launcher across Nested Herdr Sessions"
type: wayfinder:prototype
status: in_progress
assignee: arch
prototype_asset: herdr-loop-swarm.sh
owns: herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
---

# Safe Workspace Discovery in Launcher across Nested Herdr Sessions (T-016c)

## Question

In `herdr-loop-swarm.sh`, lines 231-251 currently assume that if `HERDR_ENV=1`, the current workspace `HERDR_WORKSPACE_ID` is the target workspace. If a driver or orchestrator inside a Herdr workspace (like `wM`) runs `herdr-loop-swarm.sh up /tmp/scratch`, the launcher incorrectly sets `WS_ID="wM"`, risking pane collisions in the host workspace. How should `herdr-loop-swarm.sh` safely discover or create target workspaces regardless of `HERDR_ENV`?

## Preamble

1. **Intended Outcome**: `herdr-loop-swarm.sh` uses `find_workspace_by_cwd "$PWD"` to resolve the workspace tied to the target directory. If `find_workspace_by_cwd` returns a workspace, reuse it; otherwise create a new dedicated workspace for the target repository.
2. **Explicit Done-Criteria**:
   - `herdr-loop-swarm.sh`:
     - Delete the naive `if [[ "${HERDR_ENV:-}" != 1 ]]` branch that unconditionally sets `WS_ID="$HERDR_WORKSPACE_ID"`.
     - Always resolve `WS_ID=$(find_workspace_by_cwd "$PWD")`.
     - If `[[ -z "$WS_ID" ]]`, create workspace with `herdr workspace create --cwd "$PWD" --label "$WS_LABEL"`.
     - Set `EXTERNAL=1` whenever `"$WS_ID" != "${HERDR_WORKSPACE_ID:-}"` so attaching instructions are printed when launching external workspaces.
     - Shellcheck passes with 0 warnings.
3. **Verification Step**:
   - Verify `shellcheck herdr-loop-swarm.sh`.
   - Test `find_workspace_by_cwd "$PWD"` inside current workspace returns `wM`.
   - Commit changes and emit `ARCH DONE #18 <sha>`.
