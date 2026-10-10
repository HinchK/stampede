#!/usr/bin/env bash
# lib/common.sh — Shared helpers for the swarm libraries
# Sourced by: lib/profile.sh, lib/config.sh, lib/briefs.sh, lib/lifecycle.sh,
#             lib/quota.sh
#
# Provides:
#   slugify: Herdr-legal agent-name slug emitter (grammar ^[a-z][a-z0-9_-]*$,
#            empirically established in docs/findings/herdr-semantics.md §C)
#   herdr_has_wait_output: once-per-process `pane wait-output` capability
#            probe (HERDR-2 / ADR 0017 D5)

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

# ── herdr pane wait-output capability (HERDR-2 / ADR 0017 D5) ───────────────
# Single-target output waits should block on `herdr pane wait-output` instead
# of timeout-and-recheck polls (ADR 0017 D1), but adoption is feature-gated:
# a Herdr without the primitive degrades to today's behavior, never fails.
# The probe runs once per process and logs exactly one degradation line when
# the primitive is absent.

# Brief-delivery anchor: the standing-brief prompt deliver_brief_nonce writes
# into the seat's pane — the stable, greppable "the brief reached this pane"
# marker the seat-verify seam waits on.
# shellcheck disable=SC2034  # consumed by sourcing siblings (lifecycle.sh)
BRIEF_ACK_REGEX='STANDING BRIEF:'

_HERDR_WAIT_OUTPUT_CACHE=""
herdr_has_wait_output() {
  if [[ -z "$_HERDR_WAIT_OUTPUT_CACHE" ]]; then
    if herdr pane wait-output --help >/dev/null 2>&1; then
      _HERDR_WAIT_OUTPUT_CACHE=yes
    else
      _HERDR_WAIT_OUTPUT_CACHE=no
      printf 'stampede: herdr pane wait-output unavailable — falling back to poll waits (ADR 0017 D5)\n' >&2
    fi
  fi
  [[ "$_HERDR_WAIT_OUTPUT_CACHE" == yes ]]
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

# ── verdict evidence (HASH-1) ───────────────────────────────────────────────
# Tamper-evident verdict rows: every new session-verdicts.jsonl record carries
# the supervising host and pid; rows produced by an actual gate run also carry
# a sha256 over that run's gate-log bytes, binding the claim to its evidence
# (OpenRig judgment-ledger format; mechanically re-executed evidence only).
evidence_host() { # short hostname, $HOSTNAME fallback
  local h=""
  h=$(hostname -s 2>/dev/null) || h=""
  [[ -n "$h" ]] || h="${HOSTNAME:-unknown}"
  printf '%s\n' "$h"
}

evidence_sha256() { # FILE → sha256 hex; rc 1 + empty when unreadable
  [[ -f "$1" && -r "$1" ]] || return 1
  shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' && return 0
  sha256sum "$1" 2>/dev/null | awk '{print $1}' && return 0
  return 1
}
