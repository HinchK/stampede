#!/usr/bin/env bash
# Agent Guard & Health Watchdog
# Monitors agent statuses, detects stalls, and applies circuit breakers

set -euo pipefail

# check_agent_health AGENT_NAME
check_agent_health() {
  local agent="$1"
  local info status
  info=$(herdr agent get "$agent" 2>/dev/null) || return 1
  status=$(jq -r '.result.agent.agent_status // "unknown"' <<<"$info")
  printf '%s' "$status"
}

# wait_agent_with_circuit_breaker AGENT_NAME TIMEOUT_SECS
wait_agent_with_circuit_breaker() {
  local agent="$1"
  local timeout_secs="${2:-300}"
  local timeout_ms=$(( timeout_secs * 1000 ))
  local res status

  # Use native event-driven herdr agent wait (zero polling overhead)
  res=$(herdr agent wait "$agent" --until idle --until done --until blocked --timeout "$timeout_ms" 2>/dev/null) || {
    printf '  \033[33m⚠ Agent %s timed out after %ds\033[0m\n' "$agent" "$timeout_secs"
    return 1
  }

  status=$(jq -r '.result.agent.agent_status // "unknown"' <<<"$res" 2>/dev/null || check_agent_health "$agent")
  if [[ "$status" == "blocked" ]]; then
    printf '  \033[31m✖ Agent %s entered BLOCKED state\033[0m\n' "$agent"
    return 2
  elif [[ "$status" == "idle" || "$status" == "done" ]]; then
    return 0
  fi

  return 0
}

# inspect_agent_last_lines AGENT_NAME NUM_LINES
inspect_agent_last_lines() {
  local agent="$1"
  local lines="${2:-30}"
  herdr agent read "$agent" --lines "$lines" --source recent-unwrapped 2>/dev/null || true
}
