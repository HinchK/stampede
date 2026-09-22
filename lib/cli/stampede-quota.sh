#!/usr/bin/env bash
# lib/cli/stampede-quota.sh — `stampede quota` (PUB-9)
#
# Read-only per-provider headroom: one table row per configured seat kind
# (seats enumerated through PUB-2's registry; lib/quota.sh does the
# probing) plus the [proxy] surface, plus one quota.probe telemetry event
# per actual probe.
#
# Exit: 0 when every probe answered — `unknown` is a truthful answer, not
# a failure; 1 on config trouble or when any probe returned error:.
# Disabled seats print SKIP, are never probed, never emit events.
#
# Writes: telemetry only, and only inside <REPO_DIR>/.herdr-swarm/traces/
# (the PUB-9 zero-writes rule). The herd's live session id is reused
# READ-ONLY when one exists so quota events stream into the Ops pane;
# telemetry_session_id() is deliberately not called — it would write the
# session file outside the trace dir.

_quota_row() { # SEAT KIND PROBE — render one row + best-effort telemetry
  local seat="$1" kind="$2" probe="$3" status
  case "$probe" in
    ok:*)    status="ok" ;;
    error:*) status="error"; QUOTA_FAIL=1 ;;
    *)       status="unknown" ;;
  esac
  printf '  %-14s %-12s %s\n' "$seat" "$kind" "$probe"
  "$PYTHON_BIN" "$QUOTA_ROOT/lib/telemetry.py" log "$QUOTA_SESSION" quota.probe "$seat" - \
    "$(jq -cn --arg s "$seat" --arg k "$kind" --arg st "$status" \
       '{seat:$s, kind:$k, status:$st, summary:("quota " + $st + ": " + $s + "/" + $k)}')" \
    --trace-dir "$QUOTA_TRACE_DIR" >/dev/null 2>&1 || true
}

stampede_cmd_quota() {
  local root config seat kinds enabled _name k chain probe arg
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  config="${STAMPEDE_CONFIG:-$root/swarm.config.toml}"

  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        cat <<'EOF'
Usage: stampede quota

Read-only provider headroom: one row per configured seat kind plus the
[proxy] surface. Providers that expose nothing report `unknown` — never 0.
Telemetry events land in <REPO_DIR>/.herdr-swarm/traces/ only.

Exit: 0 when every probe answered; 1 on config trouble or any probe error.
EOF
        return 0
        ;;
    esac
  done

  # shellcheck disable=SC1091  # sibling libs resolved from orchestrator root
  source "$root/lib/common.sh"
  # shellcheck disable=SC1091
  source "$root/lib/pyenv.sh"
  # shellcheck disable=SC1091
  source "$root/lib/config.sh"
  # shellcheck disable=SC1091
  source "$root/lib/providers.sh"
  # shellcheck disable=SC1091
  source "$root/lib/quota.sh"

  if ! resolve_python; then
    printf 'quota: cannot resolve a tomllib-capable interpreter — see lib/preflight.sh\n' >&2
    return 1
  fi
  if [[ ! -f "$config" ]]; then
    printf 'quota: config not found: %s\n' "$config" >&2
    return 1
  fi

  QUOTA_ROOT="$root"
  QUOTA_TRACE_DIR="${REPO_DIR:-$PWD}/.herdr-swarm/traces"
  QUOTA_SESSION=$(cat "${REPO_DIR:-$PWD}/.herdr-swarm/telemetry-session" 2>/dev/null || printf 'stampede-quota')
  QUOTA_FAIL=0

  printf 'stampede quota — provider headroom (read-only)\n\n'
  printf '  %-14s %-12s %s\n' "SEAT" "KIND" "HEADROOM"

  while IFS='|' read -r seat kinds enabled _name; do
    [[ -n "$seat" ]] || continue
    if [[ "$enabled" != "1" || -z "$kinds" ]]; then
      if [[ "$enabled" != "1" ]]; then
        printf '  %-14s %-12s %s\n' "$seat" "${kinds:--}" "SKIP (disabled)"
      else
        printf '  %-14s %-12s %s\n' "$seat" "-" "SKIP (no kind configured)"
      fi
      continue
    fi
    chain=()
    IFS=',' read -ra chain <<<"$kinds"
    for k in "${chain[@]}"; do
      [[ -n "$k" ]] || continue
      probe=$(quota_probe_kind "$k")
      _quota_row "$seat" "$k" "$probe"
    done
  done < <(providers_seats_from_config "$config")

  probe=$(quota_probe_openrouter "$config")
  _quota_row "-" "openrouter" "$probe"

  return "$QUOTA_FAIL"
}
