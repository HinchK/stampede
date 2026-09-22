#!/usr/bin/env bash
# lib/cli/stampede-version.sh — `stampede version` (PUB-5)
#
# Prints the semver from VERSION plus `git describe --tags --always
# --dirty` when the orchestrator checkout is a git repository with tags,
# else the short sha, else just the semver. Degrades cleanly outside a
# repo — version must never be the command that fails.

stampede_cmd_version() {
  local root v desc
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  v=$(cat "$root/VERSION" 2>/dev/null || printf 'unknown')
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    desc=$(git -C "$root" describe --tags --always --dirty 2>/dev/null || true)
    printf 'stampede %s (%s)\n' "$v" "${desc:-no-tags}"
  else
    printf 'stampede %s\n' "$v"
  fi
}
