#!/usr/bin/env bash
# lib/config.sh — TOML Swarm Configuration & Shell Binding Registry
# Prototype for Ticket: [TOML Configuration Schema and Shell Binding]
#
# Parses swarm.config.toml via a tomllib-capable interpreter (lib/pyenv.sh)
# and binds values to shell.

set -euo pipefail

# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck disable=SC1091  # tomllib-capable interpreter (DOG-1)
source "$(dirname "${BASH_SOURCE[0]}")/pyenv.sh"
resolve_python

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULT_CONFIG="${SCRIPT_DIR}/swarm.config.toml"

# Run python code with argv (never interpolated into the source): argv[1] is
# the TOML path, extra args follow. Stderr is suppressed; failure is tolerated
# (callers fall back to defaults).
_py_read() {
  local toml_path="$1"
  local py_code="$2"
  shift 2
  "$PYTHON_BIN" - "$toml_path" "$@" <<PYCODE 2>/dev/null || true
import sys, tomllib
try:
    with open(sys.argv[1], 'rb') as f:
        cfg = tomllib.load(f)
except Exception:
    sys.exit(1)
$py_code
PYCODE
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

# Dump complete shell environment with namespaced names.
# Slug is passed through slugify() (Herdr-legal), and slug/toml_path travel as
# python sys.argv — never interpolated into the Python source. Every emitted
# value is escaped with shlex.quote so `eval`-style consumption is safe for
# any input (e.g. slugs containing quotes).
config_dump_env() {
  local slug="${1:-}"
  local toml_path="${2:-$DEFAULT_CONFIG}"

  if [[ ! -f "$toml_path" ]]; then
    printf '# Config file not found: %s\n' "$toml_path" >&2
    return 1
  fi
  [[ -n "$slug" ]] && slug=$(slugify "$slug")

  "$PYTHON_BIN" - "$slug" "$toml_path" <<'PYCODE'
import sys, tomllib, shlex, os

slug = sys.argv[1]
toml_path = sys.argv[2]

with open(toml_path, 'rb') as f:
    cfg = tomllib.load(f)

def emit(key, val):
    print(f'export {key}={shlex.quote(str(val))}')

# HL-CFG-1: environment overrides configuration — the gate_concurrency
# hierarchy, extended to the headless knobs. A key already present in the
# environment (per-run tuning: CI overrides, test fixtures, `VAR=x … headless`)
# is left untouched; the TOML value binds only when the env slot is empty.
def emit_env_wins(key, val):
    if key not in os.environ:
        emit(key, val)

swarm = cfg.get('swarm', {})
proxy = cfg.get('proxy', {})
geom = cfg.get('geometry', {})
fanout = cfg.get('fanout', {})
seats = cfg.get('seats', {})
reviewer = cfg.get('reviewer', {})
headless = cfg.get('headless', {})

emit('SWARM_CONFIG_NAME', swarm.get('name', 'herd'))
emit('SWARM_WORKSPACE_LABEL', swarm.get('workspace_label', 'herd'))
emit('SWARM_LOG_PATH', swarm.get('log_path', '/tmp/herdr-process.log'))
emit('SWARM_TRACE_DIR', swarm.get('trace_dir', '.herdr-swarm/traces'))
emit('SWARM_WORKTREE_ROOT', swarm.get('worktree_root', '.herdr-swarm/worktrees'))
emit('FANOUT_GATE_CONCURRENCY', fanout.get('gate_concurrency', 2))
emit('FANOUT_MAX_WORKERS', fanout.get('max_workers', 2))
# Reviewer loop knobs (REV-1): strict types — `loop` must be a real TOML
# boolean (a truthy string would silently enable an autonomous loop) and
# `max_rounds` an integer >= 1 (0 rounds means "never review", which is
# loop=false, not a number).
reviewer_loop = reviewer.get('loop', False)
if not isinstance(reviewer_loop, bool):
    sys.exit("config error: reviewer.loop must be a boolean (true/false)")
reviewer_rounds = reviewer.get('max_rounds', 2)
if not isinstance(reviewer_rounds, int) or isinstance(reviewer_rounds, bool) or reviewer_rounds < 1:
    sys.exit("config error: reviewer.max_rounds must be an integer >= 1")
emit('CONFIG_REVIEW_LOOP', 1 if reviewer_loop else 0)
emit('CONFIG_REVIEW_MAX_ROUNDS', reviewer_rounds)
# Headless safety ceilings (HEADLESS-5): same strict-integer validation as
# reviewer.max_rounds — these bound unattended retries and wall clocks, so a
# truthy string or 0 must fail closed at binding time, not mid-run.
hl_attempts = headless.get('max_verdict_attempts', 2)
if not isinstance(hl_attempts, int) or isinstance(hl_attempts, bool) or hl_attempts < 1:
    sys.exit("config error: headless.max_verdict_attempts must be an integer >= 1")
hl_timeout = headless.get('worker_timeout_s', 600)
if not isinstance(hl_timeout, int) or isinstance(hl_timeout, bool) or hl_timeout < 1:
    sys.exit("config error: headless.worker_timeout_s must be an integer >= 1")
emit_env_wins('CONFIG_HEADLESS_MAX_ATTEMPTS', hl_attempts)
emit_env_wins('CONFIG_HEADLESS_WORKER_TIMEOUT_S', hl_timeout)
emit('PROXY_ENABLED', str(proxy.get('enabled', False)).lower())
# No localhost fallbacks (DOG-7): a config without [proxy] endpoint/health
# keys binds empty; the only live proxy URLs live in swarm.config.toml.
emit('PROXY_ENDPOINT', proxy.get('endpoint', ''))
emit('PROXY_HEALTH_URL', proxy.get('health_check_url', ''))
emit('PROXY_SERVE_CMD', proxy.get('serve_cmd', ''))
emit('PROXY_CREDENTIALS', proxy.get('credentials', ''))
emit('GEOM_MIN_COLS', geom.get('min_cols', 80))
emit('GEOM_MIN_ROWS', geom.get('min_rows', 20))

enabled_seats = [k for k, v in seats.items() if v.get('enabled', True)]
emit('SEAT_KEYS', ' '.join(enabled_seats))

for k in enabled_seats:
    s = seats[k]
    base_name = s.get('name', k)
    full_name = f'{base_name}-{slug}' if slug else base_name
    emit(f'SEAT_NAME_{k}', full_name)
    # Provider chain (PUB-6): `kinds` is the ordered fallback chain; a lone
    # `default_kind` is sugar for a single-element chain. kinds[0] is the
    # primary. A conflicting default_kind, an empty chain, or non-string
    # entries are config errors — a seat that can never resolve must fail
    # at parse time, not mid-seating.
    kinds = s.get('kinds', None)
    dk = s.get('default_kind', None)
    if kinds is not None:
        if not isinstance(kinds, list) or not kinds or not all(isinstance(x, str) and x for x in kinds):
            sys.exit(f"config error: seats.{k}.kinds must be a non-empty array of provider kind strings")
        if dk is not None and dk != kinds[0]:
            sys.exit(f"config error: seats.{k}: default_kind ({dk}) conflicts with kinds[0] ({kinds[0]}) — kinds[0] is the primary; drop default_kind or align it")
        chain = kinds
    else:
        chain = [dk if dk is not None else 'agy']
    emit(f'SEAT_KIND_{k}', chain[0])
    emit(f'SEAT_KINDS_{k}', ' '.join(chain))
    emit(f'SEAT_MODEL_{k}', s.get('model', 'auto'))
    emit(f'SEAT_BRIEF_{k}', s.get('brief', ''))
    emit(f'SEAT_TAB_{k}', s.get('tab', 'herd'))
    emit(f'SEAT_POS_{k}', s.get('position', ''))
    emit(f'SEAT_ROLE_{k}', s.get('role', ''))
    # Worktree isolation flag: strict boolean, no truthiness coercion (a
    # mistyped flag must never silently share the root checkout).
    wt = s.get('worktree', False)
    if not isinstance(wt, bool):
        sys.exit(f"config error: seats.{k}.worktree must be a boolean (got {type(wt).__name__})")
    if wt and (k in ('looper', 'pm') or s.get('name') in ('looper', 'pm')):
        sys.exit(f"config error: seats.{k} is a root anchor and cannot set worktree = true (ADR 0006 §4.A)")
    emit(f'SEAT_WORKTREE_{k}', 1 if wt else 0)
PYCODE
}

# Render --plan dry run markdown preview
config_plan_preview() {
  local slug="${1:-preview}"
  local toml_path="${2:-$DEFAULT_CONFIG}"
  slug=$(slugify "$slug")

  printf '# Swarm Topology & Seating Plan (Dry-Run)\n\n'
  # shellcheck disable=SC2016  # %s is a printf conversion, not a variable
  printf '**Configuration:** `%s`\n' "$toml_path"
  # shellcheck disable=SC2016  # %s is a printf conversion, not a variable
  printf '**Project Slug:** `%s`\n\n' "$slug"

  printf '| Seat Key | Runtime Agent Name | Engine Kind | Model | Tab | Brief File | Worktree | Role |\n'
  printf '|---|---|---|---|---|---|---|---|\n'

  for seat in $(config_get_seats "$toml_path"); do
    local base_name full_name kind model tab brief role wt wt_disp
    base_name=$(config_get_seat_prop "$seat" "name" "$seat" "$toml_path")
    full_name="${base_name}-${slug}"
    kind=$(config_get_seat_prop "$seat" "default_kind" "agy" "$toml_path")
    model=$(config_get_seat_prop "$seat" "model" "auto" "$toml_path")
    tab=$(config_get_seat_prop "$seat" "tab" "herd" "$toml_path")
    brief=$(config_get_seat_prop "$seat" "brief" "" "$toml_path")
    role=$(config_get_seat_prop "$seat" "role" "" "$toml_path")
    wt=$(config_get_seat_prop "$seat" "worktree" "false" "$toml_path")
    case "$wt" in
      true)  wt_disp="yes" ;;
      false) wt_disp="no" ;;
      *)     wt_disp="?invalid(${wt})" ;;
    esac

    # shellcheck disable=SC2016  # %s conversions, not variables
    printf '| `%s` | `%s` | %s | `%s` | %s | `%s` | %s | %s |\n' \
      "$seat" "$full_name" "$kind" "$model" "$tab" "$brief" "$wt_disp" "$role"
  done

  printf '\n**Ops Services:**\n'
  local proxy_on
  proxy_on=$(config_get "proxy.enabled" "false" "$toml_path")
  printf -- '- Routing proxy ([proxy] enabled): %s\n' "$proxy_on"
  # shellcheck disable=SC2016  # %s is a printf conversion, not a variable
  printf -- '- Telemetry Traces: `%s`\n' "$(config_get "swarm.trace_dir" ".herdr-swarm/traces" "$toml_path")"
}

# Alias: the markdown plan renderer (P2-2 naming)
config_plan_markdown() { config_plan_preview "$@"; }

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
    dump|--dump-env)
      config_dump_env "${2:-}" "${3:-$DEFAULT_CONFIG}"
      ;;
    plan|--plan)
      config_plan_preview "${2:-preview}" "${3:-$DEFAULT_CONFIG}"
      ;;
    markdown)
      config_plan_markdown "${2:-preview}" "${3:-$DEFAULT_CONFIG}"
      ;;
    *)
      echo "Usage: $0 [get <path>|seats|dump|--dump-env [slug]|plan [slug]] [config.toml]"
      exit 1
      ;;
  esac
fi
