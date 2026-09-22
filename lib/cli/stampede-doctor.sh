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
  printf '  %-10s %-20s %-9s %s\n' "SEAT" "KINDS" "STATE" "DETAIL"
  local fail=0 probe state detail bin ver k first chain
  while IFS='|' read -r seat kind enabled _name; do
    [[ -n "$seat" ]] || continue
    if [[ "$enabled" != "1" ]]; then
      printf '  %-10s %-20s %-9s %s\n' "$seat" "${kind:--}" "SKIP" "disabled in config"
      continue
    fi
    # Chain-aware (PUB-6): OK when ANY kind in the ordered chain is healthy;
    # a healthy non-primary kind is called out as the live fallback.
    first=""
    state="fail"
    detail=""
    IFS=',' read -ra chain <<<"$kind"
    for k in "${chain[@]}"; do
      [[ -z "$k" ]] && { state="bad-kind"; detail="no provider kind configured"; continue; }
      [[ -z "$first" ]] && first="$k"
      probe=$(providers_kind_probe "$k")
      case "${probe%% *}" in
        ok)
          if [[ "$k" == "$first" || -z "$first" ]]; then state="ok"; detail="$probe"
          else state="ok-fallback"; detail="primary ${first} unavailable — ${k} usable (${probe#ok })"; fi
          break
          ;;
        missing) state="missing"; detail="${probe#missing }" ;;
        unknown-kind) state="bad-kind"; detail="no registry entry for kind '${k}' — see lib/providers.sh" ;;
      esac
    done
    case "$state" in
      ok)
        bin=$(printf '%s' "$detail" | cut -d' ' -f2)
        ver=$(printf '%s' "$detail" | cut -s -d' ' -f3-)
        printf '  %-10s %-20s %-9s %s (%s)\n' "$seat" "$kind" "OK" "$bin" "${ver:-unknown-version}"
        ;;
      ok-fallback)
        printf '  %-10s %-20s %-9s %s\n' "$seat" "$kind" "FALLBACK" "$detail"
        ;;
      missing)
        printf '  %-10s %-20s %-9s %s\n' "$seat" "$kind" "MISSING" "$detail"
        fail=1
        ;;
      bad-kind)
        printf '  %-10s %-20s %-9s %s\n' "$seat" "${kind:--}" "BAD-KIND" "$detail"
        fail=1
        ;;
      fail)
        printf '  %-10s %-20s %-9s %s\n' "$seat" "${kind:--}" "MISSING" "no provider kinds configured"
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
