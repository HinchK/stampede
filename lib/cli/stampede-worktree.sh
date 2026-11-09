#!/usr/bin/env bash
# lib/cli/stampede-worktree.sh — `stampede worktree` CLI command
#
# Dispatches worktree audit and sweep commands to scripts/worktree-sweep.sh.
#
# Usage:
#   stampede worktree [dir] [--apply] [--force] [--base <ref>]

stampede_cmd_worktree() {
  local root
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
  "$root/scripts/worktree-sweep.sh" "$@"
}
