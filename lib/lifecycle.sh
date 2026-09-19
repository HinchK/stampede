#!/usr/bin/env bash
# lib/lifecycle.sh — Swarm Lifecycle Management: Status & Teardown Protocol
# Prototype for Ticket: [Workspace Lifecycle and Clean Teardown Protocol]
#
# Provides:
#   swarm_status: Inspects active workspace, seated agents, profile, and test health
#   swarm_down: Gracefully stops agents, closes panes/workspace, preserving audit logs

set -euo pipefail

# Terminal colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold 2>/dev/null || true); DIM=$(tput dim 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true); YELLOW=$(tput setaf 3 2>/dev/null || true); RED=$(tput setaf 1 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

# Find workspace ID associated with target cwd
find_workspace_by_cwd() {
  local target_dir="${1:-$PWD}"
  local abs_target
  abs_target=$(cd "$target_dir" && pwd)
  local base_label
  base_label=$(basename "$abs_target")

  # 1. Environment variable if running inside Herdr
  if [[ -n "${HERDR_WORKSPACE_ID:-}" ]]; then
    echo "$HERDR_WORKSPACE_ID"
    return 0
  fi

  # 2. Check workspace list by label
  local ws_id
  ws_id=$(herdr workspace list 2>/dev/null | jq -r --arg l "$base_label" \
    '.result.workspaces[]? | select(.label == $l) | .workspace_id' | head -n1 || true)
  if [[ -n "$ws_id" ]]; then
    echo "$ws_id"
    return 0
  fi

  # 3. Check agent list by cwd
  ws_id=$(herdr agent list 2>/dev/null | jq -r --arg d "$abs_target" \
    '.result.agents[]? | select(.cwd == $d) | .workspace_id' | head -n1 || true)
  if [[ -n "$ws_id" ]]; then
    echo "$ws_id"
    return 0
  fi

  return 1
}

# Display detailed status of swarm for current directory
swarm_status() {
  local target_dir="${1:-$PWD}"
  local abs_target
  abs_target=$(cd "$target_dir" && pwd)

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

# Graceful Swarm Teardown
swarm_down() {
  local target_dir="${1:-$PWD}"
  local keep_ws="${2:-0}"
  local abs_target
  abs_target=$(cd "$target_dir" && pwd)

  printf '\n%s▸ Swarm Teardown — %s%s\n' "$BOLD" "$(basename "$abs_target")" "$RESET"

  local ws_id
  ws_id=$(find_workspace_by_cwd "$abs_target")
  if [[ -z "$ws_id" ]]; then
    printf '  %s✓ No active workspace found for %s. Already clean.%s\n\n' "$GREEN" "$abs_target" "$RESET"
    return 0
  fi

  # 1. Discover and close agent panes (retires agents safely)
  local agents_json
  agents_json=$(herdr agent list 2>/dev/null || echo '{"result":{"agents":[]}}')

  local agent_panes
  agent_panes=$(jq -r --arg ws "$ws_id" '.result.agents[]? | select(.workspace_id == $ws) | .pane_id' <<<"$agents_json")

  for pane in $agent_panes; do
    [[ -n "$pane" ]] || continue
    printf '  %s• Closing agent pane %s...%s\n' "$DIM" "$pane" "$RESET"
    herdr pane close "$pane" >/dev/null 2>&1 || true
  done

  # 2. Close entire workspace unless keep_ws flag requested
  if (( keep_ws )); then
    printf '  %s✓ Agent panes closed. Workspace %s retained (--keep-workspace).%s\n' "$GREEN" "$ws_id" "$RESET"
  else
    printf '  %s• Disposing workspace %s...%s\n' "$DIM" "$ws_id" "$RESET"
    herdr workspace close "$ws_id" >/dev/null 2>&1 || true
    printf '  %s✓ Workspace %s disposed cleanly.%s\n' "$GREEN" "$ws_id" "$RESET"
  fi

  # 3. Clean transient channel files (preserving profile.env, traces, and verdicts)
  rm -rf "${abs_target}/.herdr-swarm/channel"
  printf '  %s✓ Transient channel files purged (.herdr-swarm/profile.env and traces preserved).%s\n\n' "$GREEN" "$RESET"
}

# CLI dispatcher
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-status}"
  case "$cmd" in
    status)
      swarm_status "${2:-$PWD}"
      ;;
    down)
      keep=0
      [[ "${2:-}" == "--keep-workspace" || "${3:-}" == "--keep-workspace" ]] && keep=1
      swarm_down "${2:-$PWD}" "$keep"
      ;;
    *)
      echo "Usage: $0 [status [dir]|down [dir] [--keep-workspace]]"
      exit 1
      ;;
  esac
fi
