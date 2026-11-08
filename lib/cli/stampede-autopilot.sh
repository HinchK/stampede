#!/usr/bin/env bash
# lib/cli/stampede-autopilot.sh — `stampede autopilot` (AUTOPILOT-1)
#
# One command that composes the switches which already exist instead of
# growing new safety policy. `on` flips the startup/arbiter ceremony off:
# quiet ticket intake (attention quiet + frontier drain), per-supervisor-pass
# arbiter drain, and a TTL'd promote grant so greens promote locally. `off`
# restores everything. Never touched: the suite gate, the state locks, the
# agent-pane promote block (GATE-1), and pushing — `git push` stays human.

stampede_cmd_autopilot() {
  local root repo="$PWD" cmd="" ttl=14400 config state config_env
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

  if [[ -d "${1:-}" ]]; then
    repo="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cat <<'EOF'
Usage: stampede autopilot [repo] on|off|status [--ttl SECONDS]

on      Autopilot: quiet ticket intake, automatic arbiter drain per pass,
        and a TTL'd promote grant (default 14400s = 4h) so the supervisor
        promotes locally when a drain lands. Creates the integration ref
        if it is missing.
off     Stop auto intake/drain/promote, revoke the grant, restore the
        attention mode you had before `on`.
status  Show the current autopilot state.

Stays on in every mode: the suite gate, the state locks, the agent-pane
promote block, and pushing — unpushed commits remain a human act.
EOF
        return 0
        ;;
      --ttl)
        ttl="${2:-}"
        if [[ ! "$ttl" =~ ^[0-9]+$ ]] || (( ttl < 1 )); then
          printf 'autopilot: --ttl needs a positive number of seconds\n' >&2
          return 1
        fi
        shift
        ;;
      on|off|status) cmd="$1" ;;
      *)
        printf 'autopilot: expected on, off, or status (run from a plain shell)\n' >&2
        return 2
        ;;
    esac
    shift
  done
  [[ -n "$cmd" ]] || { stampede_cmd_autopilot --help; return 2; }

  repo=$(cd "$repo" 2>/dev/null && pwd -P) || {
    printf 'autopilot: repository not found: %s\n' "$repo" >&2
    return 1
  }
  config="$repo/swarm.config.toml"
  state="$repo/.herdr-swarm"
  if [[ ! -f "$config" || ! -f "$state/profile.env" ]]; then
    printf 'autopilot: project configuration/profile missing; run stampede setup and up first\n' >&2
    return 1
  fi

  # shellcheck disable=SC1091  # sibling libs resolved from orchestrator root
  source "$root/lib/pyenv.sh"
  if ! resolve_python >/dev/null 2>&1; then
    printf 'autopilot: no tomllib-capable interpreter — see lib/preflight.sh\n' >&2
    return 1
  fi
  # shellcheck disable=SC1091
  source "$root/lib/config.sh"
  if ! config_env=$(config_dump_env "$(basename "$repo")" "$config"); then
    printf 'autopilot: invalid project configuration (%s)\n' "$config" >&2
    return 1
  fi
  eval "$config_env"

  _ap_ctl() { # KEY true|false — the supervisor's ctl_set write pattern
    local control="$state/control.json" tmp
    [[ -f "$control" ]] || printf '{"paused": false, "frontier_drain": false, "suite_gate": true}' > "$control"
    tmp=$(mktemp)
    jq --arg k "$1" --argjson v "$2" '.[$k] = $v' "$control" > "$tmp" && mv "$tmp" "$control"
  }

  case "$cmd" in
    on)
      # Grant FIRST: the one step that can refuse (an agent pane), and a
      # refusal must leave every other switch untouched.
      if ! REPO_DIR="$repo" STATE_DIR="$state" bash "$root/lib/arbiter.sh" grant-session --ttl "$ttl" >/dev/null; then
        printf 'autopilot: promote grant refused — run this from a plain human shell; nothing was changed\n' >&2
        return 1
      fi
      # The integration ref is a one-time explicit act (ARB-SLUG-1); a human
      # running `autopilot on` is that act. init-ref still refuses if the ref
      # exists, and the slug is the same canonical config name drain uses.
      if ! git -C "$repo" show-ref --verify --quiet "refs/heads/swarm/${SWARM_CONFIG_NAME}/integration"; then
        REPO_DIR="$repo" STATE_DIR="$state" PROJECT_SLUG="$SWARM_CONFIG_NAME" \
          bash "$root/lib/arbiter.sh" init-ref >&2 || return 1
      fi
      if [[ ! -f "$state/autopilot-prev-mode" ]]; then
        "$PYTHON_BIN" "$root/lib/attention.py" mode "$repo" > "$state/autopilot-prev-mode"
      fi
      "$PYTHON_BIN" "$root/lib/attention.py" mode "$repo" quiet >/dev/null
      _ap_ctl autopilot true
      _ap_ctl frontier_drain true
      local expires
      expires=$(jq -r '.expires_at // 0' "$state/promote-grant.json" 2>/dev/null || printf '0')
      printf 'autopilot: ON — quiet intake, per-pass drain + local promote\n'
      printf '  promote grant expires: %s\n' \
        "$(date -u -r "$expires" +%FT%TZ 2>/dev/null || date -u -d "@$expires" +%FT%TZ 2>/dev/null || printf '%ss from now' "$ttl")"
      printf '  still human: git push · still enforced: suite gate, locks, agent promote block\n'
      printf '  turn off with: stampede autopilot %s off\n' "$repo"
      ;;
    off)
      REPO_DIR="$repo" STATE_DIR="$state" bash "$root/lib/arbiter.sh" revoke-session >/dev/null 2>&1 \
        || printf 'autopilot: grant revoke refused (run from a plain shell) — flags still cleared\n' >&2
      _ap_ctl autopilot false
      _ap_ctl frontier_drain false
      if [[ -s "$state/autopilot-prev-mode" ]]; then
        "$PYTHON_BIN" "$root/lib/attention.py" mode "$repo" "$(cat "$state/autopilot-prev-mode")" >/dev/null
        rm -f "$state/autopilot-prev-mode"
        printf 'autopilot: OFF — attention restored; intake, drain, and promote are manual again\n'
      else
        printf 'autopilot: OFF — intake, drain, and promote are manual again (attention mode left as-is)\n'
      fi
      ;;
    status)
      printf 'attention mode:  %s\n' "$("$PYTHON_BIN" "$root/lib/attention.py" mode "$repo" 2>/dev/null || printf '?')"
      printf 'control flags:   autopilot=%s frontier_drain=%s suite_gate=%s\n' \
        "$(jq -r '.autopilot // false' "$state/control.json" 2>/dev/null || printf 'false')" \
        "$(jq -r '.frontier_drain // false' "$state/control.json" 2>/dev/null || printf 'false')" \
        "$(jq -r '.suite_gate // true' "$state/control.json" 2>/dev/null || printf 'true')"
      local grant_line='none'
      if [[ -f "$state/promote-grant.json" ]]; then
        local expires_now
        expires_now=$(jq -r '.expires_at // 0' "$state/promote-grant.json" 2>/dev/null || printf '0')
        if (( expires_now > $(date +%s) )); then
          grant_line="valid until $(date -u -r "$expires_now" +%FT%TZ 2>/dev/null || date -u -d "@$expires_now" +%FT%TZ 2>/dev/null || printf '%s' "$expires_now")"
        else
          grant_line='expired'
        fi
      fi
      printf 'promote grant:   %s\n' "$grant_line"
      if git -C "$repo" show-ref --verify --quiet "refs/heads/swarm/${SWARM_CONFIG_NAME}/integration"; then
        printf 'integration ref: %s\n' "$(git -C "$repo" rev-parse --short "refs/heads/swarm/${SWARM_CONFIG_NAME}/integration")"
      else
        printf 'integration ref: missing (autopilot on creates it)\n'
      fi
      ;;
  esac
}
