#!/usr/bin/env bash
# lib/lifecycle.sh — Swarm Lifecycle Management: Status & Teardown Protocol
# Prototype for Tickets: [Workspace Lifecycle and Clean Teardown Protocol],
#                       [Lifecycle Safe Teardown and Target Disambiguation (D1 fix)]
#
# Provides:
#   swarm_status:         Inspects active workspace, seated agents, profile, test health
#   swarm_down:           Gracefully retires recorded seat panes / agents, closes
#                         workspace (unless --keep-workspace), preserving audit logs
#   find_workspace_by_cwd: Strict cwd-identity workspace resolution (D1 fix)
#
# D1 fix invariants:
#   - find_workspace_by_cwd ONLY resolves workspaces whose pane cwd is exactly
#     the requested directory (physical paths). $HERDR_WORKSPACE_ID is returned
#     only when the caller workspace's panes actually live in the target dir.
#     No-match prints nothing and returns 0 (safe under `set -e` sourcing).
#   - swarm_down closes only panes recorded in .herdr-swarm/seats.json
#     (schema: {"workspace_id": "wX", "seats": [{"name": ..., "kind": ...,
#     "pane": "wX:pN"}]}); if the ledger is absent or stale (workspace_id
#     mismatch), it falls back to closing agent panes registered in the
#     matched workspace. Unrelated operator panes are never touched.
#   - swarm_down asks for interactive confirmation before closing anything
#     unless -y/--yes is passed; non-interactive without --yes aborts closed.

set -euo pipefail

# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Terminal colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold 2>/dev/null || true); DIM=$(tput dim 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true); YELLOW=$(tput setaf 3 2>/dev/null || true); RED=$(tput setaf 1 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

# True if any pane of WS_ID has cwd exactly equal to ABS_TARGET (physical path).
_ws_matches_cwd() { # WS_ID ABS_TARGET
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -e --arg d "$2" '[.result.panes[]? | select(.cwd == $d)] | length > 0' >/dev/null 2>&1
}

# Resolve the workspace tied to a directory by strict cwd identity.
# Prints the workspace id, or nothing when no workspace matches. Always
# returns 0 (callers test output emptiness; safe under set -e sourcing).
find_workspace_by_cwd() {
  local target_dir="${1:-$PWD}"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || return 0

  # 1. Caller's own workspace — ONLY if its panes actually live in the target
  if [[ -n "${HERDR_WORKSPACE_ID:-}" ]] && _ws_matches_cwd "$HERDR_WORKSPACE_ID" "$abs_target"; then
    echo "$HERDR_WORKSPACE_ID"
    return 0
  fi

  # 2. Any workspace whose pane cwd is exactly the target (never label-based)
  local ws_list cand
  ws_list=$(herdr workspace list 2>/dev/null || true)
  while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    [[ "$cand" == "${HERDR_WORKSPACE_ID:-}" ]] && continue
    if _ws_matches_cwd "$cand" "$abs_target"; then
      echo "$cand"
      return 0
    fi
  done < <(jq -r '.result.workspaces[]?.workspace_id' <<<"$ws_list" 2>/dev/null)

  # 3. Fallback: a seated agent whose cwd is the target
  local ws_id
  ws_id=$(herdr agent list 2>/dev/null | jq -r --arg d "$abs_target" \
    '.result.agents[]? | select(.cwd == $d) | .workspace_id' | head -n1 || true)
  if [[ -n "$ws_id" ]]; then
    echo "$ws_id"
    return 0
  fi
  return 0
}

# Display detailed status of swarm for current directory
swarm_status() {
  local target_dir="${1:-$PWD}"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || return 1

  printf '\n%s%s⚡ Herdr Swarm Status — %s%s\n' "$BOLD" "$CYAN" "$(basename "$abs_target")" "$RESET"
  printf '%sDirectory: %s%s\n\n' "$DIM" "$abs_target" "$RESET"

  # 1. Daemon Check
  if ! herdr workspace list >/dev/null 2>&1; then
    printf '  %s✖ Herdr daemon is not responding.%s\n\n' "$RED" "$RESET"
    return 1
  fi

  # 2. Workspace Status
  local ws_id
  ws_id=$(find_workspace_by_cwd "$abs_target")
  if [[ -z "$ws_id" ]]; then
    printf '  %s• Workspace:%s %s[Inactive — No active workspace found for this path]%s\n' "$DIM" "$RESET" "$YELLOW" "$RESET"
    printf '    Launch with: %s./herdr-loop-swarm.sh%s\n\n' "$BOLD" "$RESET"
    return 0
  fi
  printf '  %s✓ Workspace:%s %s (%s)\n' "$GREEN" "$RESET" "$(basename "$abs_target")" "$ws_id"

  # 3. Profile Information
  local env_file="${abs_target}/.herdr-swarm/profile.env"
  if [[ -f "$env_file" ]]; then
    printf '  %s✓ Profile:%s\n' "$GREEN" "$RESET"
    printf '      Repo:      %s\n' "$(grep -E '^REPO=' "$env_file" | cut -d'=' -f2- || echo "none")"
    printf '      Test Cmd:  %s\n' "$(grep -E '^TEST_CMD=' "$env_file" | cut -d'=' -f2- || echo "none")"
    printf '      Ecosystem: %s\n' "$(grep -E '^ECOSYSTEM=' "$env_file" | cut -d'=' -f2- || echo "generic")"
  else
    printf '  %s• Profile:%s uninitialized (.herdr-swarm/profile.env)\n' "$DIM" "$RESET"
  fi

  # 4. Seated Agents
  printf '\n%s  Seated Agents in Workspace (%s):%s\n' "$BOLD" "$ws_id" "$RESET"
  local agents_json
  agents_json=$(herdr agent list 2>/dev/null || echo '{"result":{"agents":[]}}')

  local count
  count=$(jq -r --arg ws "$ws_id" '[.result.agents[]? | select(.workspace_id == $ws)] | length' <<<"$agents_json" 2>/dev/null || echo 0)

  if (( count == 0 )); then
    printf '    %s(No agents currently registered in this workspace)%s\n' "$DIM" "$RESET"
  else
    printf '    %-18s %-10s %-12s %-10s\n' "AGENT NAME" "KIND" "STATUS" "PANE ID"
    printf '    %-18s %-10s %-12s %-10s\n' "------------------" "----------" "------------" "----------"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local aname akind astat apane
      read -r aname akind astat apane <<<"$line"
      [[ "$aname" == "null" || -z "$aname" ]] && aname="(unnamed)"
      local stat_color="$GREEN"
      [[ "$astat" == "working" ]] && stat_color="$CYAN"
      [[ "$astat" == "blocked" ]] && stat_color="$RED"
      printf '    %-18s %-10s %s%-12s%s %-10s\n' "$aname" "$akind" "$stat_color" "$astat" "$RESET" "$apane"
    done < <(jq -r --arg ws "$ws_id" '.result.agents[]? | select(.workspace_id == $ws) | "\(.name) \(.agent) \(.agent_status) \(.pane_id)"' <<<"$agents_json")
  fi

  # 5. Telemetry & Verdicts
  local trace_dir="${abs_target}/.herdr-swarm/traces"
  if [[ -d "$trace_dir" ]]; then
    local latest_trace
    latest_trace=$(find "$trace_dir" -maxdepth 1 -name "*.jsonl" 2>/dev/null | sort | tail -n1 || true)
    if [[ -n "$latest_trace" ]]; then
      printf '\n%s  Recent Activity (%s):%s\n' "$BOLD" "$(basename "$latest_trace")" "$RESET"
      tail -n 3 "$latest_trace" | while IFS= read -r ev; do
        [[ -n "$ev" ]] && printf '    %s•%s %s\n' "$DIM" "$RESET" "$ev"
      done
    fi
  fi
  printf '\n'
}

# Interactive yes/no gate. Prompts on stderr (or /dev/tty when stdin is not a
# terminal); refuses (returns 1) when no usable terminal exists — scripts must
# pass --yes explicitly.
lifecycle_confirm() { # PROMPT
  local reply="" prompt="$1"
  if [[ -t 0 ]]; then
    printf '  %s? %s%s [y/N] ' "$YELLOW" "$prompt" "$RESET" >&2
    read -r reply || return 1
  else
    exec 3</dev/tty 2>/dev/null || return 1
    printf '  %s? %s%s [y/N] ' "$YELLOW" "$prompt" "$RESET" >&3 2>/dev/null || true
    if ! read -r reply <&3; then
      exec 3<&- 2>/dev/null || true
      return 1
    fi
    exec 3<&- 2>/dev/null || true
  fi
  [[ "$reply" =~ ^[Yy] ]]
}

# Graceful Swarm Teardown.
# Closes only panes recorded in .herdr-swarm/seats.json (when the ledger is
# fresh for the matched workspace); otherwise closes agent panes registered in
# the matched workspace. Never touches panes of unrelated workspaces.
swarm_down() { # TARGET_DIR ASSUME_YES KEEP_WS
  local target_dir="$1" assume_yes="$2" keep_ws="$3"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || {
    printf '  %s✖ Cannot access target directory: %s%s\n' "$RED" "$target_dir" "$RESET"
    return 1
  }

  printf '\n%s▸ Swarm Teardown — %s%s\n' "$BOLD" "$(basename "$abs_target")" "$RESET"

  local ws_id
  ws_id=$(find_workspace_by_cwd "$abs_target")
  if [[ -z "$ws_id" ]]; then
    rm -rf "${abs_target}/.herdr-swarm/channel"
    printf '  %s✓ No active workspace found for %s. Already clean.%s\n\n' "$GREEN" "$abs_target" "$RESET"
    return 0
  fi

  # Build the retirement plan: recorded seats first, live registry as fallback
  local seats_file="${abs_target}/.herdr-swarm/seats.json"
  local panes="" pane_source=""
  if [[ -f "$seats_file" ]] \
     && [[ "$(jq -r '.workspace_id // empty' "$seats_file" 2>/dev/null)" == "$ws_id" ]]; then
    panes=$(jq -r '.seats[]?.pane // empty' "$seats_file" 2>/dev/null | sort -u)
    pane_source="seats.json ledger"
  else
    [[ -f "$seats_file" ]] && pane_source="seats.json STALE (workspace mismatch) — using live registry"
    panes=$(herdr agent list 2>/dev/null | jq -r --arg ws "$ws_id" \
      '.result.agents[]? | select(.workspace_id == $ws) | .pane_id' | sort -u)
    [[ -n "$pane_source" ]] || pane_source="live agent registry"
  fi

  # Present the plan
  printf '  %s• Workspace:%s %s\n' "$DIM" "$RESET" "$ws_id"
  printf '  %s• Pane source:%s %s\n' "$DIM" "$RESET" "$pane_source"
  if [[ -n "$panes" ]]; then
    printf '  %s• Panes to close:%s\n' "$DIM" "$RESET"
    local pane
    while IFS= read -r pane; do
      [[ -n "$pane" ]] && printf '      - %s\n' "$pane"
    done <<<"$panes"
  else
    printf '  %s• Panes to close:%s (none recorded)\n' "$DIM" "$RESET"
  fi
  if (( keep_ws )); then
    printf '  %s• Workspace %s will be RETAINED (--keep-workspace)%s\n' "$DIM" "$ws_id" "$RESET"
  else
    printf '  %s• Workspace %s will be CLOSED%s\n' "$YELLOW" "$ws_id" "$RESET"
  fi

  # Confirmation gate (D1: never close anything unattended without --yes)
  if (( ! assume_yes )); then
    if ! lifecycle_confirm "Tear down this swarm?"; then
      printf '  %s✖ Aborted — nothing was closed.%s\n\n' "$RED" "$RESET"
      return 1
    fi
  fi

  # Execute: retire agents by closing their panes
  if [[ -n "$panes" ]]; then
    local pane
    while IFS= read -r pane; do
      [[ -n "$pane" ]] || continue
      printf '  %s• Closing pane %s...%s\n' "$DIM" "$pane" "$RESET"
      herdr pane close "$pane" >/dev/null 2>&1 || true
    done <<<"$panes"
  fi

  # Close the workspace itself unless retention requested
  if (( keep_ws )); then
    printf '  %s✓ Seat panes closed. Workspace %s retained (--keep-workspace).%s\n' "$GREEN" "$ws_id" "$RESET"
  else
    printf '  %s• Disposing workspace %s...%s\n' "$DIM" "$ws_id" "$RESET"
    herdr workspace close "$ws_id" >/dev/null 2>&1 || true
    printf '  %s✓ Workspace %s disposed cleanly.%s\n' "$GREEN" "$ws_id" "$RESET"
  fi

  # Clean transient channel files (profile.env, seats.json, traces, verdicts preserved)
  rm -rf "${abs_target}/.herdr-swarm/channel"
  printf '  %s✓ Transient channel files purged (profile, seats, traces preserved).%s\n\n' "$GREEN" "$RESET"
}

# Post-seating readiness gate. Every seat must exist and have settled into a
# stable post-boot state. NOTE: "ready" includes WORKING — an agent that is
# executing has demonstrably booted and consumed its standing brief; a strict
# idle/done-only wait cannot pass against a live, busy swarm (verified
# empirically). Blocked, unknown, or never-booted seats time out and fail.
swarm_verify_seats() { # [TARGET_DIR] [TIMEOUT_MS]
  local target_dir="${1:-$PWD}"
  local timeout_ms="${2:-30000}"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || {
    printf '  %s✖ cannot access target directory: %s%s\n' "$RED" "$target_dir" "$RESET"
    return 1
  }

  local ws_id
  ws_id=$(find_workspace_by_cwd "$abs_target")
  if [[ -z "$ws_id" ]]; then
    printf '  %s✖ no active workspace for %s%s\n' "$RED" "$abs_target" "$RESET"
    return 1
  fi

  # Seat roster: fresh seats.json ledger, else live agents in the workspace
  local seats_file="${abs_target}/.herdr-swarm/seats.json"
  local seats_spec="" src_label
  if [[ -f "$seats_file" ]] && [[ "$(jq -r '.workspace_id // empty' "$seats_file" 2>/dev/null)" == "$ws_id" ]]; then
    seats_spec=$(jq -r '.seats[]? | "\(.name)\t\(.kind)\t\(.pane)"' "$seats_file" 2>/dev/null)
    src_label="seats.json ledger"
  else
    seats_spec=$(herdr agent list 2>/dev/null | jq -r --arg ws "$ws_id" \
      '.result.agents[]? | select(.workspace_id == $ws) | "\(.name)\t\(.agent)\t\(.pane_id)"')
    src_label="live agent registry"
  fi

  printf '%s▸ Seat Verification — %s (%s)%s\n' "$BOLD" "$ws_id" "$src_label" "$RESET"

  if [[ -z "$seats_spec" ]]; then
    printf '  %s✖ no seats recorded for this workspace%s\n' "$RED" "$RESET"
    return 1
  fi

  local failures=0 name kind pane
  while IFS=$'\t' read -r name kind pane; do
    [[ -n "$name" ]] || continue
    if ! herdr agent get "$name" >/dev/null 2>&1; then
      printf '  %s✖ %s: agent not registered%s\n' "$RED" "$name" "$RESET"
      failures=1
      continue
    fi
    if herdr agent wait "$name" --until idle --until "done" --until working --timeout "$timeout_ms" >/dev/null 2>&1; then
      printf '  %s✓ %s (%s in %s): interactive-ready%s\n' "$GREEN" "$name" "$kind" "$pane" "$RESET"
    else
      printf '  %s✖ %s: not ready within %sms%s\n' "$RED" "$name" "$timeout_ms" "$RESET"
      failures=1
    fi
  done <<<"$seats_spec"

  return "$failures"
}

# CLI dispatcher
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-status}"
  shift 2>/dev/null || true
  dir="$PWD"
  assume=0
  keep=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)          assume=1 ;;
      --keep-workspace)  keep=1 ;;
      -h|--help)
        cat <<EOF
Usage: $(basename "$0") [status [dir] | down [dir] [-y|--yes] [--keep-workspace]]
  status   Show swarm status for a directory (default: \$PWD)
  down     Tear down the swarm tied to a directory (default: \$PWD)
             -y, --yes         skip confirmation (required when non-interactive)
             --keep-workspace  close seat panes only, retain the workspace
EOF
        exit 0 ;;
      -*) printf 'unknown flag: %s (try --help)\n' "$1" >&2; exit 2 ;;
      *)  dir="$1" ;;
    esac
    shift
  done
  case "$cmd" in
    status) swarm_status "$dir" ;;
    down)   swarm_down "$dir" "$assume" "$keep" ;;
    *)      printf 'unknown command: %s (try --help)\n' "$cmd" >&2; exit 1 ;;
  esac
fi
