#!/usr/bin/env bash
# lib/cli/stampede-headless.sh — `stampede headless` (HEADLESS-6, slice 3c)
#
# The user-facing unattended batch command tying HEADLESS-3/4/5 together:
# iterate backlog tickets in <dir>/maps/tickets (deterministic queue intake —
# the replacement for looper's interactive judgment, per the headless map),
# dispatch each through the lib/headless.sh subprocess harness, harvest and
# gate them through the supervisor's HEADLESS-4 wiring (same anchored
# regexes, same suite gate, same arbiter enqueue), and respect HEADLESS-5's
# ceilings and dead-letter exits. No Herdr daemon, no panes, no PTY.
#
# Not named `drain` on purpose (PM guidance 2026-09-24): drain already means
# arbiter_drain advancing swarm/<slug>/integration — a different operation.
#
# Usage: stampede headless [dir] [--max-tickets N] [--timeout M]
#   dir           target repo (default $PWD)
#   --max-tickets stop after N dispatched tickets (default 5; the design
#                 doc's session cap — a batch, never an infinite loop)
#   --timeout     whole-batch wall clock in seconds (default 1800)
# Exit: 0 batch completed with every dispatched ticket green · 1 usage/
# config error, any dead letter, or any ticket concluding RED/DEAD_LETTER
# (HL-RED-1) · 3 a dispatched ticket hit the wall clock unconcluded with
# no dead-letterable failure.

stampede_cmd_headless() {
  local root dir="" max_tickets=5 batch_timeout=1800
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

  _headless_usage() {
    cat <<EOF
Usage: stampede headless [dir] [--max-tickets N] [--timeout M]

Unattended batch: dispatch backlog tickets from <dir>/maps/tickets to
headless worker subprocesses, gate every verdict, dead-letter failures.
No Herdr daemon, no panes.

  dir             target repo (default: \$PWD)
  --max-tickets N stop after N dispatched tickets (default 5)
  --timeout M     whole-batch wall clock, seconds (default 1800)
EOF
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-tickets)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || { printf 'headless: --max-tickets needs a number\n' >&2; _headless_usage >&2; return 1; }
        max_tickets=$2; shift 2 ;;
      --timeout)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || { printf 'headless: --timeout needs a number (seconds)\n' >&2; _headless_usage >&2; return 1; }
        batch_timeout=$2; shift 2 ;;
      -h|--help) _headless_usage; return 0 ;;
      --*)       printf 'headless: unknown flag: %s\n' "$1" >&2; _headless_usage >&2; return 1 ;;
      *)         [[ -z "$dir" ]] || { printf 'headless: one target dir only\n' >&2; return 1; }
                 dir=$1; shift ;;
    esac
  done
  dir="${dir:-$PWD}"
  [[ -d "$dir" ]] || { printf 'headless: target dir not found: %s\n' "$dir" >&2; return 1; }
  dir=$(cd "$dir" && pwd)

  # Profile is fail-closed (lib/profile.sh): an unresolvable repo/test
  # command must abort BEFORE anything is dispatched.
  # shellcheck disable=SC1091  # orchestrator-root libs
  source "$root/lib/profile.sh"
  if ! ensure_profile "$dir" 0; then
    printf 'headless: profile unresolvable for %s — refusing to run unattended\n' "$dir" >&2
    return 1
  fi

  # The supervisor IS the harvest/gate machine (HEADLESS-4): source its
  # functions with the headless seam active. Sourcing binds seats from the
  # distribution config, the telemetry session, and every gate function —
  # nothing here reimplements them. The `status` source-arg runs its
  # read-only dispatcher pass (the harness suite's own sourcing pattern);
  # stdout is suppressed but stderr is not — a source-time failure must
  # surface, never vanish.
  export HEADLESS_MODE=1
  export REPO_DIR="$dir" STATE_DIR="$dir/.herdr-swarm"
  # shellcheck disable=SC1090,SC1091  # supervisor sourced for its function surface
  source "$root/loop-bot-herd.sh" status >/dev/null

  # The interactive herd's reviewer loop is out of scope for the batch:
  # greens route straight to the arbiter queue (the pre-REV-5 ENQUEUE
  # path). The batch's quality machinery is the suite gate + HEADLESS-5
  # ceilings + dead-letter exits; headless reviewer rounds are follow-up
  # (the loop's review_loop_enabled reads this env at directive time).
  export CONFIG_REVIEW_LOOP=0

  # Worker seat: the first arch seat in the bound roster (deterministic),
  # falling back to any non-orchestration seat, then arch_1 by name.
  local seat_key="" key want
  for want in arch_1 arch_2; do
    for key in $SEAT_KEYS; do
      [[ "$key" == "$want" ]] && seat_key=$key && break 2
    done
  done
  if [[ -z "$seat_key" ]]; then
    for key in $SEAT_KEYS; do
      case "$key" in looper|pm|reviewer) continue ;; esac
      seat_key=$key; break
    done
  fi
  seat_key="${seat_key:-arch_1}"
  local seat_name="arch_1" seat_kind="opencode" name_var="SEAT_NAME_${seat_key}" kind_var="SEAT_KIND_${seat_key}"
  [[ -n "${!name_var:-}" ]] && seat_name=${!name_var}
  [[ -n "${!kind_var:-}" ]] && seat_kind=${!kind_var}

  # Isolated worktree for the worker (the same architecture the interactive
  # launcher seats): the worker commits to swarm/<slug>/<seat>, the suite
  # gate runs on that tree, and a green verdict enqueues for the arbiter —
  # root-checkout workers never auto-enqueue (supervisor semantics), which
  # would leave the batch's greens unintegrated.
  # shellcheck disable=SC1091  # sibling lib (provisioning)
  source "$root/lib/worktree.sh"
  local base_branch wt_dir wt_branch prov
  base_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || printf main)
  if ! prov=$(worktree_provision "$seat_key" "$PROJECT_SLUG" "$base_branch" "$dir" 2>/dev/null); then
    printf 'headless: worktree provision failed for %s — refusing to run on the root checkout\n' "$seat_key" >&2
    return 1
  fi
  wt_dir=$(sed -n 1p <<<"$prov"); wt_branch=$(sed -n 2p <<<"$prov")
  # Ledger entry (seats.json v2): what makes resolve_seat_gate treat the
  # worker as isolated and gate/enqueue against the worktree.
  mkdir -p "$STATE_DIR"
  local ledger="$STATE_DIR/seats.json" rec
  rec=$(jq -cn --arg n "$seat_name" --arg k "$seat_kind" --arg w "$wt_dir" --arg b "$wt_branch" \
    '{name: $n, kind: $k, pane: "", worktree_dir: $w, branch: $b, isolated: true}')
  if [[ -f "$ledger" ]]; then
    jq --argjson r "$rec" 'if any(.seats[]?; .name == $r.name) then .seats = map(if .name == $r.name then $r else . end) else .seats += [$r] end' \
      "$ledger" > "${ledger}.tmp" && mv "${ledger}.tmp" "$ledger"
  else
    jq -cn --argjson r "$rec" '{version: 2, seats: [$r]}' > "$ledger"
  fi

  # Deterministic queue: maps/tickets with status backlog|queued, filename
  # order (glob sort) — no interactive judgment involved.
  local tickets=() f st
  for f in "$dir"/maps/tickets/*.md; do
    [[ -f "$f" ]] || continue
    st=$(sed -nE 's/^status:[[:space:]]*//p' "$f" | head -n1 | tr -d '[:space:]')
    if [[ "$st" == "backlog" || "$st" == "queued" ]]; then
      tickets+=("$f")
    fi
  done
  printf 'headless: %s — %d dispatchable ticket(s), cap %d, budget %ss, worker %s (%s)\n' \
    "$dir" "${#tickets[@]}" "$max_tickets" "$batch_timeout" "$seat_name" "$seat_kind"
  if (( ${#tickets[@]} == 0 )); then
    printf 'headless: queue empty — nothing to do\n'
    return 0
  fi

  # A ticket's LATEST session record decides its state (HL-RED-1): RED is
  # only ever an intermediate outcome — conclusion means the latest record
  # is green or dead_letter.
  _hl_latest_suite() { # TID
    jq -r -s --arg t "$1" \
      '[.[] | select((.ticket|tostring) == $t)] | .[-1].suite // "none"' \
      "$SESSION_LOG" 2>/dev/null || printf 'none'
  }

  local deadline=$(( SECONDS + batch_timeout )) dispatched=0 timed_out=0 tid concluded final
  local dispatched_ids=()
  for f in "${tickets[@]}"; do
    (( dispatched >= max_tickets )) && break
    if (( SECONDS >= deadline )); then
      printf 'headless: batch wall clock exhausted — stopping with %d dispatched\n' "$dispatched" >&2
      timed_out=1
      break
    fi
    tid=$(sed -nE 's/^id:[[:space:]]*//p' "$f" | head -n1 | tr -d '[:space:]')
    tid="${tid:-$(basename "$f" .md)}"
    # Partition/lease gate (same primitives the interactive dispatch uses):
    # an owns-overlap or a held lease parks the ticket, it never forces in.
    # partition_check: 0 = clear, 2 = exclusive-clear (no owns — runs
    # alone), 1 = blocked. Only 1 parks.
    local prc=0
    partition_check "$f" "$dir" >/dev/null 2>&1 || prc=$?
    if (( prc == 1 )); then
      printf 'headless: #%s parked — partition overlap\n' "$tid"
      continue
    fi
    if ! lease_acquire "$tid" "$seat_name" >/dev/null 2>&1; then
      printf 'headless: #%s parked — lease held\n' "$tid"
      continue
    fi
    printf 'headless: dispatching #%s → %s (brief: %s, worktree: %s)\n' "$tid" "$seat_name" "$f" "$wt_dir"
    if ! headless_spawn "$seat_name" "$f" "$wt_dir" "$seat_kind" >/dev/null; then
      printf 'headless: #%s spawn failed — parking\n' "$tid" >&2
      lease_release "$tid" >/dev/null 2>&1 || true
      continue
    fi
    dispatched=$((dispatched + 1))
    dispatched_ids+=("$tid")

    # Wait for THIS ticket to conclude. HL-RED-1: a RED/invalidated/stale
    # record is NOT a conclusion while re-verdict attempts remain below
    # max_verdict_attempts — worker_feedback spawns a critique turn on those
    # outcomes, and this loop must let it run. The pre-fix loop treated any
    # record as conclusive, instantly killed the critique turn, made the
    # ceiling unreachable in-batch, and exited 0 on a failed ticket.
    # Conclusion now means: the ticket's LATEST record is green or
    # dead_letter.
    concluded="" final="none" broke=""
    while :; do
      harvest_verdicts >/dev/null 2>&1 || true
      gate_reap >/dev/null 2>&1 || true
      final=$(_hl_latest_suite "$tid")
      case "$final" in
        green|dead_letter) concluded=1; break ;;
      esac
      if (( SECONDS >= deadline )); then broke=deadline; break; fi
      local hl_st
      hl_st=$(headless_status "$seat_name" 2>/dev/null || true)
      case "$hl_st" in
        running*) ;;   # worker or critique turn still working — keep waiting
        *)
          # Not running: one settling pass (a verdict may have landed at the
          # worker's very exit), then give up only when nothing changed and
          # no gate job is in flight. A critique turn that died without
          # re-verdicting also ends here: its remaining attempts can never
          # run, so waiting would only burn the batch budget.
          harvest_verdicts >/dev/null 2>&1 || true
          gate_reap >/dev/null 2>&1 || true
          local settle
          settle=$(_hl_latest_suite "$tid")
          [[ "$settle" != "$final" ]] && continue
          [[ -n "$(ls "${STATE_DIR}/gates"/*.job 2>/dev/null)" ]] || { broke=stalled; break; }
          ;;
      esac
      sleep 2
    done
    if [[ -n "$concluded" ]]; then
      printf 'headless: #%s concluded %s\n' "$tid" "$final"
    else
      printf 'headless: #%s UNCONCLUDED (last state: %s)\n' "$tid" "$final" >&2
    fi
    if [[ -z "$concluded" ]]; then
      local reason wst wlog
      wlog="${STATE_DIR}/logs/${seat_name}.log"
      # The honest cause lives in the durable worker log (HL-DOCS-1, receipt
      # F2): the wrapper's exit marker names the vendor CLI's real exit
      # status. headless_status is useless here — the pass-level reaper has
      # already evicted the dead worker's pidfile by the time we report, so
      # the pidfile-based status reads "untracked".
      wst=""
      if [[ -f "$wlog" ]]; then
        wst=$(sed -nE 's/^\[_exit_ rc=([0-9]+)\]$/exited rc=\1/p' "$wlog" 2>/dev/null | tail -n1)
        [[ -n "$wst" ]] || wst="dead (no exit marker)"
      else
        wst="untracked (no worker log)"
      fi
      case "$final:$broke" in
        *:deadline)
          reason="batch wall clock exhausted before a verdict (last state: ${final}; worker: ${wst})" ;;
        RED:*|invalidated:*|stale:*)
          reason="critique turn ended without a concluding re-verdict (last: ${final})" ;;
        *)
          # "worker exited rc=N without a verdict" — provider errors, invalid
          # configs, and sandbox rejections all surface through this shape,
          # with the log pointer carrying the actual error text.
          reason="worker ${wst} without a verdict" ;;
      esac
      reason="${reason} — worker log: ${wlog}"
      printf 'headless: #%s did not conclude — dead-lettering: %s\n' "$tid" "$reason" >&2
      _headless_notice "#${tid} DEAD_LETTER: ${reason}"
      dead_letter_record "$tid" "$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || printf unknown)" \
        "$reason" "$SESSION_ID"
      lease_release "$tid" >/dev/null 2>&1 || true
      timed_out=1
    fi
    # Park or clean up the worker for the next sequential dispatch — only
    # after a true conclusion (HL-RED-1): below-ceiling REDs left the
    # critique turn running on purpose.
    headless_kill "$seat_name" >/dev/null 2>&1 || true
    # In-batch integration (HL-RED-1, receipt F5): drain queued records and
    # free integrated leases NOW, not in an operator's `once` pass — later
    # tickets in this batch must not park on a lease the batch itself
    # holds, and greens must not sit queued after the batch exits.
    headless_drain_and_release
  done

  # Final drain of in-flight gate jobs, then drain+release once more (late
  # gates can enqueue after the last ticket's step), then the batch verdict.
  sleep 1
  gate_reap >/dev/null 2>&1 || true
  headless_drain_and_release
  local dl failed=0 t
  # Contract check (HL-RED-1): every dispatched ticket's LATEST record must
  # be green. Anything else — a leftover RED, a dead_letter — fails the run
  # even if no dead-letter entry survived to be counted below.
  for t in ${dispatched_ids[@]+"${dispatched_ids[@]}"}; do
    case "$(_hl_latest_suite "$t")" in
      green) ;;
      *) failed=1 ;;
    esac
  done
  dl=$(headless_deadletter_count "$SESSION_ID")
  printf 'headless: batch done — %d dispatched, %d dead-letter record(s) this session\n' \
    "$dispatched" "$dl"
  if (( dl > 0 || failed )); then
    (( dl > 0 )) && printf 'headless: DEAD LETTERS present — see %s\n' "${STATE_DIR}/dead-letter.jsonl" >&2
    (( failed )) && printf 'headless: batch has ticket(s) that did not conclude green\n' >&2
    return 1
  fi
  if (( timed_out )); then
    return 3
  fi
  return 0
}
