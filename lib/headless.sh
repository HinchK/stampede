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

# resolve_timeout (DOG-15 idiom, shared): every spawned worker is bounded by
# a hard wall-clock timeout, so the harness needs the same resolver the
# suite gates use. Sourced lazily-resilient: common.sh only defines helpers.
SCRIPT_DIR_HL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091  # sibling shared helpers (resolve_timeout)
source "${SCRIPT_DIR_HL}/lib/common.sh"

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

  # Absolute paths before the wrapper runs: the brief is validated against
  # the caller's cwd but resolved by the worker inside the worktree — a
  # relative pointer would name a different file there. Normalization comes
  # after the existence check so a bad path fails with the caller's own
  # spelling (and dirname of an existing file always resolves, keeping
  # set -e quiet).
  [[ -f "$brief" ]] || { printf 'headless: brief file not found: %s\n' "$brief" >&2; return 1; }
  brief=$(cd "$(dirname "$brief")" && pwd)/$(basename "$brief")
  wt=$(cd "$wt" && pwd)
  [[ -d "$wt" ]] || { printf 'headless: worktree dir not found: %s\n' "$wt" >&2; return 1; }
  case "$kind" in
    opencode|claude|agy) ;;
    *) printf 'headless: unknown vendor kind %s (known: opencode, claude, agy)\n' "$kind" >&2; return 1 ;;
  esac

  mkdir -p "$HL_PIDS" "$HL_LOGS" "$HL_CHANNEL"

  # Hard wall-clock bound (HEADLESS-5 hazard 2): an unattended worker that
  # hangs holds its lease and starves every later ticket touching the same
  # paths, so every spawn runs under timeout(1). Fail closed when no
  # runnable timeout exists — an unbounded headless worker is exactly the
  # wedge this exists to prevent (DOG-15 semantics: environment defect, not
  # a worker failure).
  if ! resolve_timeout; then
    printf 'headless: no runnable timeout(1) — refusing to spawn %s unbounded\n' "$worker" >&2
    return 1
  fi
  local tmo="${CONFIG_HEADLESS_WORKER_TIMEOUT_S:-${HEADLESS_WORKER_TIMEOUT_S:-600}}"

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
  # `exited rc=N` from `dead`. The vendor runs as a direct child of this
  # wrapper, and the wrapper's signal traps FORWARD to it before
  # concluding — a TERM to the pidfile pid must never orphan a vendor CLI
  # that is still executing inside the worktree (round-2 critique). A
  # signalled conclusion exits 128+SIG and deliberately writes NO marker:
  # killed is `dead`, never a fabricated `exited rc=N`.
  # Vendor invoked through its non-interactive entrypoint with the prompt
  # as a CLI argument — never PTY injection: there is no `send-keys`, no
  # `sleep`, no synthetic enter anywhere here.
  (
    cd "$wt" || exit 127
    child=""
    # shellcheck disable=SC2329  # invoked indirectly via the traps below
    _hl_signal() { # SIGNAL_NAME SIGNAL_NUMBER → forward, reap, conclude dead
      [[ -n "$child" ]] && kill -s "$1" "$child" 2>/dev/null || true
      wait "$child" 2>/dev/null
      exit $((128 + $2))
    }
    trap '_hl_signal TERM 15' TERM
    trap '_hl_signal INT 2'  INT
    trap '_hl_signal HUP 1'  HUP
    rc=0
    case "$kind" in
      claude)   "$TIMEOUT_BIN" "$tmo" claude -p "$prompt"    & child=$! ;;
      opencode) "$TIMEOUT_BIN" "$tmo" opencode run "$prompt" & child=$! ;;
      agy)      "$TIMEOUT_BIN" "$tmo" agy -p "$prompt"      & child=$! ;;
    esac
    wait "$child" || rc=$?
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
  # Process gone: the wrapper's exit marker separates a concluded run from
  # one that died without reporting. Scanned across the trailing lines, not
  # just the final one — late log noise (or a trailing blank line) must not
  # flip `exited` into `dead`.
  marker=$(tail -n5 "$HL_LOGS/$worker.log" 2>/dev/null \
             | sed -nE 's/^\[_exit_ rc=([0-9]+)\]$/\1/p' | tail -n1)
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
    # Children first (the vendor CLI is the wrapper's direct child): stopping
    # it immediately halts worktree mutation, and the wrapper's own traps
    # would forward too — belt and braces, because kill -9 to the wrapper
    # can't be trapped.
    pkill -P "$pid" 2>/dev/null || true
    kill -s "$sig" "$pid" 2>/dev/null || true
    printf 'headless: sent %s to %s (pid %s) + children\n' "$sig" "$worker" "$pid" >&2
  else
    printf 'headless: %s pidfile stale (pid %s dead) — cleaning up\n' "$worker" "${pid:-empty}" >&2
  fi
  rm -f "$pidfile"
  return 0
}

# headless_reap — next-pass eviction of stale pidfiles (HEADLESS-5 hazard 2):
# a worker killed by its wall-clock (or by anything else) must not leave its
# marker dangling. Live holders are left alone — same kill -0 live/dead
# judgement as the arbiter lock and lease lock evictions (PROVE-7).
headless_reap() {
  _hl_cfg
  local pf pid
  [[ -d "$HL_PIDS" ]] || return 0
  for pf in "$HL_PIDS"/*.pid; do
    [[ -f "$pf" ]] || continue
    pid=$(head -n1 "$pf" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      continue
    fi
    printf 'headless: evicting stale pidfile %s (pid %s dead)\n' "$(basename "$pf")" "${pid:-empty}" >&2
    rm -f "$pf"
  done
  return 0
}

# ── re-verdict ceiling + dead letter (HEADLESS-5 hazards 1+3) ───────────────
# Pure functions over the supervisor's session-verdict log: the ceiling
# counts a ticket's own conclusive failures (RED/invalidated/stale — the
# three outcomes that trigger a critique re-verdict), never its greens.

headless_attempt_count() { # TICKET SESSION_LOG
  jq -r -s --arg t "$1" \
    '[.[] | select((.ticket|tostring) == $t and (.suite == "RED" or .suite == "invalidated" or .suite == "stale"))] | length' \
    "$2" 2>/dev/null || printf '0'
}

headless_deadletter_due() { # TICKET MAX_ATTEMPTS SESSION_LOG → rc 0 when due
  local n
  n=$(headless_attempt_count "$1" "$3")
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  (( n >= $2 ))
}

dead_letter_record() { # TICKET SHA REASON [SESSION] [STATE_DIR]
  local ticket="$1" sha="$2" reason="$3" session="${4:-none}" sd="${5:-${STATE_DIR:-$PWD/.herdr-swarm}}"
  mkdir -p "$sd"
  jq -cn --argjson ts "$(date +%s)" --arg s "$session" --arg t "$ticket" \
       --arg h "$sha" --arg r "$reason" \
       '{ts: $ts, session: $s, ticket: $t, sha: $h, reason: $r}' \
    >> "$sd/dead-letter.jsonl"
}

headless_deadletter_count() { # [SESSION] [DEADLETTER_FILE] → prints count
  local session="${1:-none}" f="${2:-${STATE_DIR:-$PWD/.herdr-swarm}/dead-letter.jsonl}"
  [[ -f "$f" ]] || { printf '0\n'; return 0; }
  jq -r -s --arg s "$session" '[.[] | select(.session == $s)] | length' "$f" 2>/dev/null || printf '0'
}

# CLI dispatcher (library siblings' convention; also keeps `bash -n` honest)
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-}"
  shift 2>/dev/null || true
  case "$cmd" in
    spawn)  headless_spawn "$@" ;;
    status) headless_status "$@" ;;
    kill)   headless_kill "$@" ;;
    reap)   headless_reap "$@" ;;
    # Batch entrypoint helper: a headless run exits non-zero when its own
    # session left anything in the dead-letter log (Hazard 3 — CI must see it).
    deadletter-check)
      n=$(headless_deadletter_count "${1:-none}" "${2:+$2/dead-letter.jsonl}")
      printf '%s\n' "$n"
      (( n == 0 ))
      ;;
    *)
      printf 'Usage: %s spawn <worker> <brief> <worktree> [kind] | status <worker> | kill <worker> [sig] | reap | deadletter-check <session> [state-dir]\n' "$0" >&2
      exit 1
      ;;
  esac
fi
