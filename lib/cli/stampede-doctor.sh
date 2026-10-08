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
  local root config="${STAMPEDE_CONFIG:-}" seat kind enabled
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
  local cfg_names=""
  while IFS='|' read -r seat kind enabled _name; do
    [[ -n "$seat" ]] || continue
    if [[ "$enabled" != "1" ]]; then
      printf '  %-10s %-20s %-9s %s\n' "$seat" "${kind:--}" "SKIP" "disabled in config"
      continue
    fi
    cfg_names="${cfg_names}${_name:-$seat} "
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

  # Agent lifecycle (HERDR-3 / ADR 0017): explain, don't guess. When a
  # swarm seat sits in an ambiguous Herdr state (lifecycle `unknown` or
  # unclassified), doctor asks Herdr for ground truth —
  # `herdr agent explain` prints the priority-ordered detection rules and
  # which one fired. Healthy seats are skipped (no explain spam); the
  # section is advisory and never changes the exit code; a Herdr without
  # explain support gets one note, not a failure.
  printf '\n'
  local agents_json="" amb_list="" total_n="?" aname astate exline cn is_ours
  if herdr agent explain --help >/dev/null 2>&1 \
     && agents_json=$(herdr agent list 2>/dev/null) \
     && [[ -n "$agents_json" ]]; then
    total_n=$(jq -r '.result.agents | length' <<<"$agents_json" 2>/dev/null) || total_n="?"
    # Seat identity: exact live names from the seat ledger when it exists
    # (.herdr-swarm/seats.json records the namespaced names); otherwise the
    # <config-name> / <config-name>-* prefix heuristic. Ambiguous = a seat
    # of THIS swarm whose lifecycle state is unknown/unclassified.
    local ledger_names="" ld
    for ld in "${REPO_DIR:-$PWD}/.herdr-swarm/seats.json" "$PWD/.herdr-swarm/seats.json"; do
      if [[ -f "$ld" ]]; then
        ledger_names=$(jq -r '.seats[]?.name // empty' "$ld" 2>/dev/null) || ledger_names=""
        break
      fi
    done
    while IFS=$'\t' read -r aname astate; do
      [[ -n "$aname" ]] || continue
      is_ours=0
      if [[ -n "$ledger_names" ]]; then
        while IFS= read -r cn; do
          [[ "$aname" == "$cn" ]] && { is_ours=1; break; }
        done <<<"$ledger_names"
      else
        for cn in $cfg_names; do
          if [[ "$aname" == "$cn" || "$aname" == "$cn"-* ]]; then is_ours=1; break; fi
        done
      fi
      (( is_ours )) || continue
      [[ "$astate" == "unknown" || -z "$astate" || "$astate" == "null" ]] && amb_list+="$aname"$'\n'
    done < <(jq -r '.result.agents[]? | [(.name // "?"), (.agent_status // .state // "")] | @tsv' <<<"$agents_json" 2>/dev/null)
    if [[ -z "${amb_list//$'\n'/}" ]]; then
      printf 'agent lifecycle: %s live agent(s), none ambiguous — explain skipped\n' "$total_n"
    else
      while IFS= read -r aname; do
        [[ -n "$aname" ]] || continue
        exline=$(herdr agent explain "$aname" --format json 2>/dev/null | jq -r '
          [ (.state // "?"),
            ((.matched_rule // null) | if type == "object" then (.id // tostring) elif . == null then "none" else tostring end),
            ((.fallback_reason // .screen_detection_skip_reason // .warning // "no reason reported") | tostring) ]
          | "state=\(.[0]) · rule=\(.[1]) · reason=\(.[2])"' 2>/dev/null) || exline="explain query failed"
        printf 'explain %-26s %s\n' "$aname" "$exline"
      done <<<"$amb_list"
    fi
  else
    printf 'explain unavailable (herdr agent explain unsupported or herdr not answering) — lifecycle diagnostics skipped\n'
  fi

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
