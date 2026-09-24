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
# Exit: 0 batch completed · 1 usage/config/dead-letter present · 3 a
# dispatched ticket hit the wall clock unconcluded.

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

  local deadline=$(( SECONDS + batch_timeout )) dispatched=0 timed_out=0 tid concluded
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

    # Wait for THIS ticket to conclude: harvest + reap until the session
    # log carries its record, the worker dies AND no gate job remains in
    # flight, or the batch budget runs out. Gates and enqueues happen inside
    # those passes — the async gate job may outlive the worker's exit, so
    # "worker gone" alone is not a conclusion.
    concluded=""
    while :; do
      harvest_verdicts >/dev/null 2>&1 || true
      gate_reap >/dev/null 2>&1 || true
      if jq -e -s --arg t "$tid" 'any(.[]; (.ticket|tostring) == $t)' \
           "$SESSION_LOG" >/dev/null 2>&1; then
        concluded=1
        break
      fi
      if (( SECONDS >= deadline )); then break; fi
      local hl_st
      hl_st=$(headless_status "$seat_name" 2>/dev/null || true)
      case "$hl_st" in
        running*) ;;   # still working — keep waiting
        *)
          # The verdict anchor may have landed in the log after this
          # iteration's harvest but before the worker's exit — one more
          # pass before giving up.
          harvest_verdicts >/dev/null 2>&1 || true
          gate_reap >/dev/null 2>&1 || true
          if jq -e -s --arg t "$tid" 'any(.[]; (.ticket|tostring) == $t)' \
               "$SESSION_LOG" >/dev/null 2>&1; then
            concluded=1
            break
          fi
          # That pass may have just spawned the gate job — an in-flight
          # job keeps the ticket alive; give up only with nothing running.
          [[ -n "$(ls "${STATE_DIR}/gates"/*.job 2>/dev/null)" ]] || break
          ;;
      esac
      sleep 2
    done
    if [[ -z "$concluded" ]]; then
      printf 'headless: #%s did not conclude within the batch budget — dead-lettering\n' "$tid" >&2
      dead_letter_record "$tid" "$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || printf unknown)" \
        "batch wall clock exhausted before a verdict" "$SESSION_ID"
      lease_release "$tid" >/dev/null 2>&1 || true
      timed_out=1
    fi
    # Park or clean up the worker for the next sequential dispatch.
    headless_kill "$seat_name" >/dev/null 2>&1 || true
  done

  # Final drain of in-flight gate jobs, then the batch verdict.
  sleep 1
  gate_reap >/dev/null 2>&1 || true
  local dl
  dl=$(headless_deadletter_count "$SESSION_ID")
  printf 'headless: batch done — %d dispatched, %d dead-letter record(s) this session\n' \
    "$dispatched" "$dl"
  if (( dl > 0 )); then
    printf 'headless: DEAD LETTERS present — see %s\n' "${STATE_DIR}/dead-letter.jsonl" >&2
    return 1
  fi
  if (( timed_out )); then
    return 3
  fi
  return 0
}
