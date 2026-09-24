#!/usr/bin/env bash
# lib/headless.sh — headless subprocess harness (HEADLESS-3, slice 3a)
#
# Spawns a worker's vendor CLI as a plain background subprocess — no Herdr
# pane, no PTY, no keystroke injection. Approach A of
# docs/findings/headless-mode-design.md §2: direct child processes, PIDs in
# ${STATE_DIR}/pids/, durable output in ${STATE_DIR}/logs/, briefs delivered
# through the vendor's non-interactive entrypoint using the same compact
# pointer + nonce channel protocol as the supervisor's dispatch
# (loop-bot-herd.sh cmd_dispatch: nonce, $CHANNEL_DIR/<worker>-<nonce>.md,
# "REPLY CHANNEL: write your complete response to $out and reply with only
# the path").
#
# Lifecycle states (headless_status):
#   running      pid alive (kill -0)                       → rc 0
#   exited rc=N  pid gone, wrapper's exit marker present    → rc 1
#   dead         pid gone, no marker (hard-kill / crash)    → rc 1
#   untracked    no pidfile for this worker                 → rc 2
# The wrapper subshell appends "[_exit_ rc=N]" to the log after the vendor
# exits, which is what makes exited distinguishable from dead — kill -0
# alone cannot tell them apart.
#
# PID liveness uses the same `kill -0 "$pid" 2>/dev/null` idiom as the
# stale-holder eviction in lib/arbiter.sh, lib/partition.sh, lib/worktree.sh
# and arbiter_auto_drain (PROVE-7) — reused, not reinvented.
#
# This library is standalone by design: loop-bot-herd.sh integration
# (harvesting verdicts from channels/logs) is HEADLESS-4 and deliberately
# not attempted here.
#
# Environment:
#   STATE_DIR   swarm state dir (default <REPO_DIR or $PWD>/.herdr-swarm)
#   CHANNEL_DIR reply-channel dir (default $STATE_DIR/channel — same path
#               the supervisor binds, loop-bot-herd.sh:33)

set -euo pipefail

_hl_cfg() {
  HL_STATE="${STATE_DIR:-${REPO_DIR:-$PWD}/.herdr-swarm}"
  HL_PIDS="${HL_STATE}/pids"
  HL_LOGS="${HL_STATE}/logs"
  HL_CHANNEL="${CHANNEL_DIR:-${HL_STATE}/channel}"
}

# headless_spawn WORKER BRIEF_FILE WORKTREE_DIR [KIND]
# KIND: opencode (default) | claude | agy. Fails closed on: missing brief,
# missing worktree, unknown kind, or an already-running worker. Stale
# pidfiles (dead pid) are evicted, matching the arbiter lock pattern.
headless_spawn() {
  _hl_cfg
  local worker="${1:?worker name required}" brief="${2:?brief file required}" \
        wt="${3:?worktree dir required}" kind="${4:-opencode}"
  local pidfile="$HL_PIDS/$worker.pid" log="$HL_LOGS/$worker.log"

  [[ -f "$brief" ]] || { printf 'headless: brief file not found: %s\n' "$brief" >&2; return 1; }
  [[ -d "$wt" ]] || { printf 'headless: worktree dir not found: %s\n' "$wt" >&2; return 1; }
  case "$kind" in
    opencode|claude|agy) ;;
    *) printf 'headless: unknown vendor kind %s (known: opencode, claude, agy)\n' "$kind" >&2; return 1 ;;
  esac

  mkdir -p "$HL_PIDS" "$HL_LOGS" "$HL_CHANNEL"

  # Double-spawn guard: a live pid for this worker means one subprocess per
  # worktree is already enforced — refuse rather than pile a second vendor
  # onto the same tree. A dead pid is a stale marker: evict and proceed.
  if [[ -f "$pidfile" ]]; then
    local old
    old=$(head -n1 "$pidfile" 2>/dev/null || true)
    if [[ -n "$old" ]] && kill -0 "$old" 2>/dev/null; then
      printf 'headless: %s already running (pid %s) — refuse double spawn\n' "$worker" "$old" >&2
      return 1
    fi
    printf 'headless: evicting stale pidfile for %s (pid %s dead)\n' "$worker" "${old:-empty}" >&2
    rm -f "$pidfile"
  fi

  # Nonce channel + compact pointer prompt — the exact dispatch protocol.
  local nonce out prompt
  nonce=$(date +%s)-$RANDOM
  out="$HL_CHANNEL/${worker}-${nonce}.md"
  prompt="BRIEF (file): $brief — read it with your file tools and execute. REPLY CHANNEL: write your complete response to $out and reply with only the path."

  # Wrapper subshell: cwd = worktree, both output streams to the durable
  # log, exit marker appended after the vendor exits so status can tell
  # `exited rc=N` from `dead`. Vendor invoked through its non-interactive
  # entrypoint with the prompt as a CLI argument — never PTY injection:
  # there is no `send-keys`, no `sleep`, no synthetic enter anywhere here.
  (
    cd "$wt" || exit 127
    rc=0
    case "$kind" in
      claude)   claude -p "$prompt"   || rc=$? ;;
      opencode) opencode run "$prompt" || rc=$? ;;
      agy)      agy -p "$prompt"      || rc=$? ;;
    esac
    printf '\n[_exit_ rc=%s]\n' "$rc"
    exit "$rc"
  ) >"$log" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" > "$pidfile"

  printf 'headless: spawned %s (kind=%s, pid=%s) log=%s channel=%s\n' \
    "$worker" "$kind" "$pid" "$log" "$out"
  printf 'headless: poll: while [ ! -s %s ]; do sleep 5; done\n' "$out"
}

# headless_status WORKER → prints running | "exited rc=N" | dead | untracked
# rc 0 alive · rc 1 not alive · rc 2 untracked
headless_status() {
  _hl_cfg
  local worker="${1:?worker name required}"
  local pidfile="$HL_PIDS/$worker.pid" pid marker
  if [[ ! -f "$pidfile" ]]; then
    printf 'untracked\n'
    return 2
  fi
  pid=$(head -n1 "$pidfile" 2>/dev/null || true)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    printf 'running (pid %s)\n' "$pid"
    return 0
  fi
  # Process gone: the wrapper's exit marker (last line of the log) separates
  # a concluded run from one that died without reporting.
  marker=$(tail -n1 "$HL_LOGS/$worker.log" 2>/dev/null \
             | sed -nE 's/^\[_exit_ rc=([0-9]+)\]$/\1/p')
  if [[ -n "$marker" ]]; then
    printf 'exited rc=%s\n' "$marker"
  else
    printf 'dead\n'
  fi
  return 1
}

# headless_kill WORKER [SIGNAL=TERM] — best-effort signal + pidfile cleanup.
# Killing an untracked worker is idempotent (rc 0): batch cleanup callers
# must not have to care whether the worker already finished.
headless_kill() {
  _hl_cfg
  local worker="${1:?worker name required}" sig="${2:-TERM}"
  local pidfile="$HL_PIDS/$worker.pid" pid
  if [[ ! -f "$pidfile" ]]; then
    printf 'headless: %s not running (no pidfile)\n' "$worker" >&2
    return 0
  fi
  pid=$(head -n1 "$pidfile" 2>/dev/null || true)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -s "$sig" "$pid" 2>/dev/null || true
    printf 'headless: sent %s to %s (pid %s)\n' "$sig" "$worker" "$pid" >&2
  else
    printf 'headless: %s pidfile stale (pid %s dead) — cleaning up\n' "$worker" "${pid:-empty}" >&2
  fi
  rm -f "$pidfile"
  return 0
}

# CLI dispatcher (library siblings' convention; also keeps `bash -n` honest)
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-}"
  shift 2>/dev/null || true
  case "$cmd" in
    spawn)  headless_spawn "$@" ;;
    status) headless_status "$@" ;;
    kill)   headless_kill "$@" ;;
    *)
      printf 'Usage: %s spawn <worker> <brief-file> <worktree-dir> [kind] | status <worker> | kill <worker> [signal]\n' "$0" >&2
      exit 1
      ;;
  esac
fi
