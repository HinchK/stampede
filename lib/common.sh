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

# Stable per-project telemetry session id: minted once, persisted in the
# swarm state dir, shared by launcher + supervisor so one Ops-pane stream
# shows every event (lifecycle, dispatches, suite verdicts).
telemetry_session_id() { # STATE_DIR
  local f="${1}/telemetry-session"
  if [[ -f "$f" && -s "$f" ]]; then
    cat "$f"
    return 0
  fi
  mkdir -p "$1"
  printf 'swarm-%s\n' "$(date +%Y%m%d-%H%M%S)" > "$f"
  cat "$f"
}

# ── timeout(1) resolver (DOG-15) ───────────────────────────────────────────
# Every suite gate bounds its run with `timeout`, but macOS ships no
# /usr/bin/timeout: GNU coreutils is not part of the base system. A missing
# binary makes `timeout N sh -c "$TEST_CMD"` exit 127 — indistinguishable
# from "the suite failed" — so an unresolved gate silently fabricates a RED
# verdict it never measured. That is the one failure mode the gate exists to
# prevent, so resolve the binary explicitly and fail closed.
#
# Contract (mirrors resolve_python in lib/pyenv.sh):
#   - $TIMEOUT_BIN already set: honoured strictly. Runnable -> exported;
#     missing or not runnable -> hard error with a remedy. An explicit choice
#     is never silently overridden.
#   - unset: probe `timeout` then `gtimeout` (Homebrew coreutils installs the
#     g-prefixed name); the first runnable one wins and is exported.
#   - success is silent; failure prints a remedy to stderr and returns 1.
#
# Callers must treat a non-zero return as "this gate cannot run" and must not
# record a RED/failing verdict from it — the tree was never measured.

# Capability probe: behaviour, not name matching — it must actually bound a
# command right now.
_timeout_runnable() { # CANDIDATE
  "$1" 1 true >/dev/null 2>&1
}

resolve_timeout() {
  if [[ -n "${TIMEOUT_BIN:-}" ]]; then
    if _timeout_runnable "$TIMEOUT_BIN"; then
      export TIMEOUT_BIN
      return 0
    fi
    printf 'timeout: TIMEOUT_BIN=%s is not a runnable timeout(1)\n' "$TIMEOUT_BIN" >&2
    printf 'timeout: remedy: unset TIMEOUT_BIN, or point it at GNU timeout (brew install coreutils)\n' >&2
    return 1
  fi
  local cand
  for cand in timeout gtimeout; do
    if command -v "$cand" >/dev/null 2>&1 && _timeout_runnable "$cand"; then
      TIMEOUT_BIN=$(command -v "$cand")
      export TIMEOUT_BIN
      return 0
    fi
  done
  printf 'timeout: no runnable timeout(1) found (tried: timeout, gtimeout)\n' >&2
  printf 'timeout: macOS ships none, and an unbounded suite gate can wedge integration\n' >&2
  printf 'timeout: remedy: brew install coreutils, or export TIMEOUT_BIN=/path/to/timeout\n' >&2
  return 1
}
