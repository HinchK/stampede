#!/usr/bin/env bash
# lib/common.sh — Shared helpers for the swarm libraries
# Sourced by: lib/profile.sh, lib/config.sh, lib/briefs.sh, lib/lifecycle.sh
#
# Provides:
#   slugify: Herdr-legal agent-name slug emitter (grammar ^[a-z][a-z0-9_-]*$,
#            empirically established in docs/findings/herdr-semantics.md §C)

set -euo pipefail

# Convert an arbitrary project name into a Herdr-legal slug:
#   - lowercase everything
#   - any character outside [a-z0-9_-] becomes "-"
#   - prefix "s-" when the result does not start with a lowercase letter
#   - empty input falls back to "swarm"
# Examples: MyApp -> myapp · loop.bot -> loop-bot · 123-app -> s-123-app · a'b -> a-b
slugify() {
  local s="${1:-}"
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g')
  if [[ -z "$s" ]]; then
    printf 'swarm\n'
    return 0
  fi
  [[ "$s" =~ ^[a-z] ]] || s="s-${s}"
  printf '%s\n' "$s"
}
