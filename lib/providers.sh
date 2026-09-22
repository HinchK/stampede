#!/usr/bin/env bash
# lib/providers.sh — the provider registry (PUB-2)
#
# One place that knows which agent-CLI kinds exist and how to probe them.
# The pipeline (dispatch, suite gate, arbiter) never consults this file —
# it is provider-blind by design; only seating-relevant surfaces do
# (doctor, init, fallback chains). A provider entry is: binary name,
# version probe, and an honest remediation string. No provider gets
# special treatment anywhere else in the codebase (design tenet 4,
# maps/public-multi-provider.md).
#
# Sourced by: lib/cli/stampede-doctor.sh (and later init/fallback/seating).
# Requires: lib/common.sh (resolve_timeout), lib/pyenv.sh (resolve_python)
# for config-seat enumeration.

set -euo pipefail

# ── Registry ───────────────────────────────────────────────────────────────
# providers_kind_binary <kind>   → binary name (echo) / rc 1 unknown kind
providers_kind_binary() {
  case "$1" in
    claude)   echo "claude" ;;
    opencode) echo "opencode" ;;
    agy)      echo "agy" ;;
    pi)       echo "pi" ;;
    *)        return 1 ;;
  esac
}

# providers_kind_remediation <kind> → install pointer (echo); rc 1 unknown
providers_kind_remediation() {
  case "$1" in
    claude)   echo "install: npm install -g @anthropic-ai/claude-code" ;;
    opencode) echo "install: curl -fsSL https://opencode.ai/install | bash" ;;
    agy)      echo "install the AGY CLI (see its vendor docs), or seat these roles with another provider kind" ;;
    pi)       echo "optional local engine — see the [seats.pi] note in swarm.config.toml" ;;
    *)        return 1 ;;
  esac
}

# providers_list_kinds — registry enumeration (one per line)
providers_list_kinds() {
  printf 'claude\nopencode\nagy\npi\n'
}

# ── Probing ────────────────────────────────────────────────────────────────
# providers_kind_probe <kind>
#   → "ok <resolved-binary> <version-first-line>"   provider usable
#   → "missing <remediation>"                       binary not on PATH
#   → "unknown-kind <kind>"                         not in the registry
# Read-only: a `--version` call bounded by timeout(1) (5s); CLIs without a
# fast --version still resolve — the version field degrades to "unknown".
providers_kind_probe() {
  local kind="$1" bin ver
  if ! bin=$(providers_kind_binary "$kind"); then
    printf 'unknown-kind %s\n' "$kind"
    return 0
  fi
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'missing %s\n' "$(providers_kind_remediation "$kind")"
    return 0
  fi
  bin=$(command -v "$bin")
  ver=$("$TIMEOUT_BIN" 5 "$bin" --version 2>/dev/null | head -n1 || true)
  printf 'ok %s %s\n' "$bin" "${ver:-unknown-version}"
}

# ── Config enumeration ─────────────────────────────────────────────────────
# providers_seats_from_config <toml-path>
#   → lines: "<seat-key>|<kind-or-empty>|<enabled:1|0>|<seat-name>"
# Lists ALL seats (enabled and disabled) in declaration order. Self-contained
# python (mirrors lib/config.sh's argv-transport rule: the TOML path travels
# as sys.argv, never interpolated). Requires resolve_python to have run.
providers_seats_from_config() {
  local toml_path="$1"
  "$PYTHON_BIN" - "$toml_path" <<'PYCODE'
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    cfg = tomllib.load(f)
for k, v in cfg.get('seats', {}).items():
    kind = v.get('default_kind', '')
    enabled = 1 if v.get('enabled', True) else 0
    name = v.get('name', k)
    print(f'{k}|{kind}|{enabled}|{name}')
PYCODE
}
