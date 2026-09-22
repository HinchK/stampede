#!/usr/bin/env bash
# lib/cli/stampede-doctor.sh — `stampede doctor` (PUB-2)
#
# Provider-aware health check: one table row per configured seat —
# seat → kind → resolved binary → version → OK/MISSING/SKIP with an
# actionable remediation — followed by the existing 9-point preflight.
#
# Exit: 0 when every ENABLED seat's provider probes OK and preflight has no
# errors; 1 otherwise. Disabled seats (enabled = false) report SKIP and
# never affect the exit code — you opted out, you don't get gaslit.

stampede_cmd_doctor() {
  local root config="${STAMPEDE_CONFIG:-}" seat kind enabled name
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  [[ -n "$config" ]] || config="$root/swarm.config.toml"

  # shellcheck disable=SC1091  # sibling libs resolved from orchestrator root
  source "$root/lib/common.sh"
  # shellcheck disable=SC1091
  source "$root/lib/pyenv.sh"
  # shellcheck disable=SC1091
  source "$root/lib/providers.sh"

  if ! resolve_python; then
    printf 'doctor: cannot resolve a tomllib-capable interpreter — run lib/preflight.sh for the full remedy\n' >&2
    return 1
  fi
  resolve_timeout || {
    printf 'doctor: no runnable timeout(1) — probes cannot be bounded; install coreutils or export TIMEOUT_BIN\n' >&2
    return 1
  }

  if [[ ! -f "$config" ]]; then
    printf 'doctor: config not found: %s\n' "$config" >&2
    return 1
  fi

  printf 'stampede doctor — provider health (%s)\n\n' "$config"
  printf '  %-10s %-10s %-9s %s\n' "SEAT" "KIND" "STATE" "DETAIL"
  local fail=0 line probe state detail bin ver
  while IFS='|' read -r seat kind enabled name; do
    [[ -n "$seat" ]] || continue
    if [[ "$enabled" != "1" ]]; then
      printf '  %-10s %-10s %-9s %s\n' "$seat" "${kind:--}" "SKIP" "disabled in config"
      continue
    fi
    probe=$(providers_kind_probe "$kind")
    state=${probe%% *}
    detail=${probe#* }
    case "$state" in
      ok)
        bin=$(printf '%s' "$detail" | cut -d' ' -f1)
        ver=$(printf '%s' "$detail" | cut -s -d' ' -f2-)
        printf '  %-10s %-10s %-9s %s (%s)\n' "$seat" "$kind" "OK" "$bin" "${ver:-unknown-version}"
        ;;
      missing)
        printf '  %-10s %-10s %-9s %s\n' "$seat" "$kind" "MISSING" "$detail"
        fail=1
        ;;
      unknown-kind)
        printf '  %-10s %-10s %-9s %s\n' "$seat" "${kind:--}" "BAD-KIND" "no registry entry for kind '$kind' — see lib/providers.sh"
        fail=1
        ;;
    esac
  done < <(providers_seats_from_config "$config")

  # The standing 9-point matrix: daemon, jq, git, python+tomllib, timeout,
  # gh auth, agent CLIs (advisory), git work tree (advisory).
  printf '\n'
  # shellcheck disable=SC1091
  source "$root/lib/preflight.sh"
  preflight_run
  preflight_report_text
  preflight_exit_code || fail=1
  return "$fail"
}
