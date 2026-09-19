#!/usr/bin/env bash
# lib/config.sh — TOML Swarm Configuration & Shell Binding Registry
# Prototype for Ticket: [TOML Configuration Schema and Shell Binding]
#
# Parses swarm.config.toml via python3 tomllib and binds values to shell.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULT_CONFIG="${SCRIPT_DIR}/swarm.config.toml"

_py_read() {
  local toml_path="$1"
  local py_code="$2"
  python3 -c "
import sys, tomllib
try:
    with open('$toml_path', 'rb') as f:
        cfg = tomllib.load(f)
except Exception as e:
    sys.exit(1)
$py_code
" 2>/dev/null || true
}

# Get a scalar value by dot path (e.g. 'swarm.name', 'proxy.enabled')
config_get() {
  local key_path="$1"
  local default_val="${2:-}"
  local toml_path="${3:-$DEFAULT_CONFIG}"

  if [[ ! -f "$toml_path" ]]; then
    printf '%s\n' "$default_val"
    return 0
  fi

  local val
  val=$(_py_read "$toml_path" "
keys = '$key_path'.split('.')
cur = cfg
for k in keys:
    if isinstance(cur, dict) and k in cur:
        cur = cur[k]
    else:
        cur = None
        break
if cur is not None:
    if isinstance(cur, bool):
        print('true' if cur else 'false')
    else:
        print(cur)
")
  if [[ -n "$val" ]]; then
    printf '%s\n' "$val"
  else
    printf '%s\n' "$default_val"
  fi
}

# List all enabled seat keys in declaration order
config_get_seats() {
  local toml_path="${1:-$DEFAULT_CONFIG}"
  _py_read "$toml_path" "
seats = cfg.get('seats', {})
enabled = []
for k, v in seats.items():
    if v.get('enabled', True):
        enabled.append(k)
print(' '.join(enabled))
"
}

# Get seat property
config_get_seat_prop() {
  local seat_key="$1"
  local prop="$2"
  local default_val="${3:-}"
  local toml_path="${4:-$DEFAULT_CONFIG}"

  config_get "seats.${seat_key}.${prop}" "$default_val" "$toml_path"
}

# Dump complete shell environment with namespaced names
config_dump_env() {
  local slug="${1:-}"
  local toml_path="${2:-$DEFAULT_CONFIG}"

  if [[ ! -f "$toml_path" ]]; then
    printf '# Config file not found: %s\n' "$toml_path" >&2
    return 1
  fi

  python3 -c "
import tomllib

with open('$toml_path', 'rb') as f:
    cfg = tomllib.load(f)

slug = '$slug'
swarm = cfg.get('swarm', {})
proxy = cfg.get('proxy', {})
geom = cfg.get('geometry', {})
seats = cfg.get('seats', {})

print(f'export SWARM_CONFIG_NAME=\"{swarm.get(\"name\", \"herd\")}\"')
print(f'export SWARM_WORKSPACE_LABEL=\"{swarm.get(\"workspace_label\", \"herd\")}\"')
print(f'export SWARM_LOG_PATH=\"{swarm.get(\"log_path\", \"/tmp/herdr-process.log\")}\"')
print(f'export SWARM_TRACE_DIR=\"{swarm.get(\"trace_dir\", \".herdr-swarm/traces\")}\"')
print(f'export PROXY_ENABLED=\"{str(proxy.get(\"enabled\", False)).lower()}\"')
print(f'export PROXY_ENDPOINT=\"{proxy.get(\"endpoint\", \"http://localhost:4114/v1\")}\"')
print(f'export GEOM_MIN_COLS={geom.get(\"min_cols\", 80)}')
print(f'export GEOM_MIN_ROWS={geom.get(\"min_rows\", 20)}')

enabled_seats = [k for k, v in seats.items() if v.get('enabled', True)]
print(f'export SEAT_KEYS=({' '.join(enabled_seats)})')

for k in enabled_seats:
    s = seats[k]
    base_name = s.get('name', k)
    full_name = f'{base_name}-{slug}' if slug else base_name
    print(f'export SEAT_NAME_{k}=\"{full_name}\"')
    print(f'export SEAT_KIND_{k}=\"{s.get(\"default_kind\", \"agy\")}\"')
    print(f'export SEAT_MODEL_{k}=\"{s.get(\"model\", \"auto\")}\"')
    print(f'export SEAT_BRIEF_{k}=\"{s.get(\"brief\", \"\")}\"')
    print(f'export SEAT_TAB_{k}=\"{s.get(\"tab\", \"herd\")}\"')
    print(f'export SEAT_POS_{k}=\"{s.get(\"position\", \"\")}\"')
    print(f'export SEAT_ROLE_{k}=\"{s.get(\"role\", \"\")}\"')
"
}

# Render --plan dry run markdown preview
config_plan_preview() {
  local slug="${1:-preview}"
  local toml_path="${2:-$DEFAULT_CONFIG}"

  printf '# Swarm Topology & Seating Plan (Dry-Run)\n\n'
  printf '**Configuration:** `%s`\n' "$toml_path"
  printf '**Project Slug:** `%s`\n\n' "$slug"

  printf '| Seat Key | Runtime Agent Name | Engine Kind | Model | Tab | Brief File | Role |\n'
  printf '|---|---|---|---|---|---|---|\n'

  for seat in $(config_get_seats "$toml_path"); do
    local base_name full_name kind model tab brief role
    base_name=$(config_get_seat_prop "$seat" "name" "$seat" "$toml_path")
    full_name="${base_name}-${slug}"
    kind=$(config_get_seat_prop "$seat" "default_kind" "agy" "$toml_path")
    model=$(config_get_seat_prop "$seat" "model" "auto" "$toml_path")
    tab=$(config_get_seat_prop "$seat" "tab" "herd" "$toml_path")
    brief=$(config_get_seat_prop "$seat" "brief" "" "$toml_path")
    role=$(config_get_seat_prop "$seat" "role" "" "$toml_path")

    printf '| `%s` | `%s` | %s | `%s` | %s | `%s` | %s |\n' \
      "$seat" "$full_name" "$kind" "$model" "$tab" "$brief" "$role"
  done

  printf '\n**Ops Services:**\n'
  local proxy_on
  proxy_on=$(config_get "proxy.enabled" "false" "$toml_path")
  printf -- '- Kultivait Proxy: %s\n' "$proxy_on"
  printf -- '- Telemetry Traces: `%s`\n' "$(config_get "swarm.trace_dir" ".herdr-swarm/traces" "$toml_path")"
}

# CLI dispatcher
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-dump}"
  case "$cmd" in
    get)
      config_get "${2:-}" "${3:-}" "${4:-$DEFAULT_CONFIG}"
      ;;
    seats)
      config_get_seats "${2:-$DEFAULT_CONFIG}"
      ;;
    dump)
      config_dump_env "${2:-}" "${3:-$DEFAULT_CONFIG}"
      ;;
    plan|--plan)
      config_plan_preview "${2:-preview}" "${3:-$DEFAULT_CONFIG}"
      ;;
    *)
      echo "Usage: $0 [get <path>|seats|dump [slug]|plan [slug]] [config.toml]"
      exit 1
      ;;
  esac
fi
