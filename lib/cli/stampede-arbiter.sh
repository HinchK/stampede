#!/usr/bin/env bash
# Human-invoked arbiter entry point with the target's profile and config.
stampede_cmd_arbiter() {
  local root repo="$PWD" cmd config profile config_env
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
    printf 'Usage: stampede arbiter [repo] init-ref|drain|promote --confirm\n'
    printf 'Run these manually: init-ref once, drain after a GREEN gate, promote after review.\n'
    return 0
  fi
  if [[ -d "${1:-}" ]]; then
    repo="$1"
    shift
  fi
  repo=$(cd "$repo" 2>/dev/null && pwd -P) || { printf 'arbiter: repo not found\n' >&2; return 1; }
  cmd="${1:-}"
  case "$cmd" in
    init-ref|drain|promote|enqueue|enqueue-and-drain|grant-session|revoke-session|pr-body) ;;
    *) printf 'arbiter: expected init-ref, drain, promote, or another explicit arbiter command\n' >&2; return 2 ;;
  esac
  config="$repo/swarm.config.toml"
  profile="$repo/.herdr-swarm/profile.env"
  [[ -f "$config" && -f "$profile" ]] || {
    printf 'arbiter: project configuration/profile missing; run stampede setup and up first\n' >&2
    return 1
  }
  # shellcheck source=/dev/null
  source "$root/lib/config.sh"
  # shellcheck source=/dev/null
  source "$root/lib/profile.sh"
  if ! config_env=$(config_dump_env "$(basename "$repo")" "$config"); then
    printf 'arbiter: invalid project configuration\n' >&2
    return 1
  fi
  eval "$config_env"
  TEST_CMD=$(read_profile_var TEST_CMD "$profile" || true)
  if ! test_cmd_is_runnable "$TEST_CMD"; then
    printf 'arbiter: project profile has no runnable TEST_CMD; refusing an ungated integration\n' >&2
    return 1
  fi
  export REPO_DIR="$repo" STATE_DIR="$repo/.herdr-swarm" TEST_CMD SWARM_CONFIG_NAME
  unset PROJECT_SLUG
  bash "$root/lib/arbiter.sh" "$@"
}
