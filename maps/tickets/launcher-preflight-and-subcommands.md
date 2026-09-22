---
id: T-INT-4
title: "Preflight Verification and Lifecycle Subcommands in Swarm Launcher"
type: wayfinder:prototype
status: resolved
resolution: "Integrated lib/preflight.sh matrix check fail-closed before workspace/pane mutation and added up, down, status lifecycle subcommands delegating to lib/lifecycle.sh. Commit 5ca2049."
assignee: arch
prototype_asset: herdr-loop-swarm.sh
owns: herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
github_issue: 32
github_url: "https://github.com/HinchK/stampede/issues/32"
synced_at: "2026-09-22T03:16:07Z"
---

# Preflight Verification and Lifecycle Subcommands in Swarm Launcher (T-INT-4, T-008)

## Question

How should `herdr-loop-swarm.sh` integrate `lib/preflight.sh` to validate the 9-point preflight matrix before creating any workspaces or splitting panes, and support `up`, `down`, and `status` subcommands delegating to `lib/lifecycle.sh`?

## Preamble

1. **Intended Outcome**: Integrate `lib/preflight.sh` into `herdr-loop-swarm.sh` to run the 9-point verification matrix before any workspace or pane creation, and wire `up`, `down`, and `status` CLI subcommands delegating to `lib/lifecycle.sh`.
2. **Explicit Done-Criteria**:
   - `herdr-loop-swarm.sh` accepts subcommands:
     - `status [dir]`: calls `swarm_status "${dir:-$PWD}"` and exits.
     - `down [dir] [-y|--yes] [--keep-ws]`: calls `swarm_down "${dir:-$PWD}" "$assume_yes" "$keep_ws"` and exits.
     - `up` (or omitted): runs preflight verification; if passed, continues swarm launch.
   - Before any workspace or pane creation, `preflight_run` executes. If `! preflight_exit_code`, prints human-readable remediation and aborts with exit code 1.
   - Deletes the ad-hoc daemon check and binary sniff lines.
   - Updates `--help` text to document subcommands (`up`, `down`, `status`).
   - Shellcheck on `herdr-loop-swarm.sh` passes cleanly with 0 warnings.
3. **Verification Step**: Run:
   `./herdr-loop-swarm.sh status >/dev/null && echo "PASS: status subcommand"`
   and
   `./herdr-loop-swarm.sh --help | grep -E 'up|down|status' && echo "PASS: usage subcommands"`
   and
   `shellcheck herdr-loop-swarm.sh && echo "PASS: clean shellcheck"`
