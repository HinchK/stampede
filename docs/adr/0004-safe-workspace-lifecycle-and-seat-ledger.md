# ADR 0004: Safe Workspace Lifecycle, Physical CWD Resolution, and Seat Ledger

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`
- **Consulted**: [T-001](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/herdr-semantics.md), [T-011](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/workspace-lifecycle-and-clean-teardown-protocol.md), [T-011-fix](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/lifecycle-safe-teardown-and-targeting.md)

---

## 1. Context and Problem Statement

Herdr is an agent-centric terminal workspace multiplexer. Unlike tmux sessions, Herdr organizes terminals into workspaces containing tabs, panes, and agents.

During empirical testing and lifecycle hardening, multiple severe safety hazards were identified in earlier lifecycle implementations:

1. **Dangerous `--current` Targeting**: The flag `--current` in `herdr pane split` resolves to whichever pane currently has interactive focus in the GUI/TUI, **not** to the workspace being scripted. Splitting with `--current` from an automated script while a human operator or orchestrator clicked elsewhere resulted in panes splitting inside the wrong workspace ([`docs/findings/herdr-semantics.md`](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/herdr-semantics.md) §A3).
2. **Accidental Workspace Teardown**: Running `swarm down /path/to/other-project` from inside a running Herdr pane previously fell back to `$HERDR_WORKSPACE_ID`. This caused the command to destroy the operator's current workspace rather than targeting the intended project directory (Disaster Scenario D1).
3. **Destruction of Operator Panes**: When closing agents, Herdr has no `agent stop` command; agents are retired when their hosting pane is closed. Naive teardown routines closed all panes in a workspace or killed processes by PID, destroying human operator shells and dev servers.

---

## 2. Decision Drivers

- **Zero Collateral Damage**: Tearing down a swarm must never close unrelated operator panes, shells, or active workspaces.
- **Strict Physical Targeting**: Target workspaces must be resolved by physical working directory path (`$PWD`), not by volatile labels or ambient environment variables.
- **Deterministic Agent Retirement**: Swarm teardown must retire only the panes and agents created by the swarm launcher.
- **Audit Preservation**: Operational logs (`.herdr-swarm/traces/`, `.herdr-swarm/session-verdicts.jsonl`, `profile.env`) must survive teardown for post-run analysis.

---

## 3. Considered Options

- **Option A (Blind Workspace Close)**: Always call `herdr workspace close <id>` on teardown. (Destructive: kills human operator sessions and wipes history).
- **Option B (Label-Based Matching)**: Tag workspaces and panes with string labels. (Fragile: labels can be renamed, duplicated, or cleared).
- **Option C (Physical CWD Matching, Durable Seat Ledger, and Explicit Confirmation)**: Resolve workspaces strictly by matching physical pane working directories (`cwd`), track allocated panes in `.herdr-swarm/seats.json`, and selectively retire only ledger-recorded panes.

---

## 4. Decision

We adopted **Option C**. We implemented strict workspace targeting, durable seat accounting, and safe selective teardown in [`lib/lifecycle.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/lifecycle.sh):

### A. Strict Physical CWD Workspace Resolution (`find_workspace_by_cwd`)
`find_workspace_by_cwd` resolves workspaces strictly by verifying that the panes in a workspace physically reside at the target directory:
1. Resolves target path to absolute canonical path (`abs_target=$(cd "$target" && pwd -P)`).
2. Inspects panes across workspaces using `herdr pane list`.
3. If `$HERDR_WORKSPACE_ID` is present, it verifies that the caller's workspace panes actually match `$abs_target`. If they do not (e.g. caller is in `wM` targeting `/tmp/project`), the caller workspace is safely ignored.
4. Returns the matched workspace ID, or empty string if no matching workspace exists.

### B. Prohibition of `--current`
All pane operations throughout `herdr-loop-swarm.sh` and supporting libraries are forbidden from using `--current`. All splits and agent starts explicitly address workspace-prefixed pane IDs (`wX:pY`) obtained deterministically from tab anchors.

### C. Durable Seat Ledger (`.herdr-swarm/seats.json`)
At launch, the swarm launcher records every created seat in a machine-readable ledger:
```json
{
  "workspace_id": "wM",
  "seats": [
    {"name": "arch-kultivait", "kind": "opencode", "pane": "wM:p2"},
    {"name": "pm-kultivait", "kind": "claude", "pane": "wM:p3"},
    {"name": "looper-kultivait", "kind": "agy", "pane": "wM:p4"}
  ]
}
```

### D. Non-Destructive Selective Teardown (`swarm_down`)
When `swarm_down` runs:
1. **Interactive Confirmation Gate (`lifecycle_confirm`)**: Prompts the user before closing anything. In non-interactive contexts without `-y` / `--yes`, it aborts cleanly (exit 1).
2. **Selective Pane Retirement**:
   - Inspects `${TARGET_DIR}/.herdr-swarm/seats.json`.
   - Validates that the recorded `workspace_id` matches the resolved workspace.
   - Iterates through only the recorded `pane` IDs and issues `herdr pane close "$pane"`, automatically retiring the seated agent without touching other panes in the workspace.
   - If the ledger is missing or stale (workspace ID mismatch), it safely falls back to closing only panes registered to swarm agents in that workspace.
3. **Workspace Disposition**:
   - Closes the workspace (`herdr workspace close "$ws_id"`) only if `--keep-workspace` is not specified and no other operator panes remain.
   - If `--keep-workspace` is requested, the workspace and operator shell remain intact while the agent panes are safely retired.
4. **Audit Trail Retention**:
   - Deletes transient prompt channel files (`.herdr-swarm/briefs/`).
   - Explicitly preserves `.herdr-swarm/seats.json`, `.herdr-swarm/profile.env`, `.herdr-swarm/traces/`, and `.herdr-swarm/session-verdicts.jsonl`.

---

## 5. Consequences

### Positive
- **Guaranteed Operator Safety**: Running `down` never closes operator panes or foreign workspaces.
- **Safe Multi-Workspace Host**: Multiple projects and scratch workspaces can coexist safely.
- **Preserved Diagnostics**: Audit traces, test verdicts, and profile configurations remain available after shutdown.
- **Idempotent Cleanup**: Calling `down` repeatedly or on an already-stopped swarm succeeds without errors.

### Negative / Trade-offs
- **State File Dependency**: `.herdr-swarm/seats.json` must be kept consistent with live allocations. (Mitigated by fallback to live workspace agent registry if ledger is missing or mismatched).
