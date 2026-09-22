#!/usr/bin/env bash
# lib/quota.sh — read-only provider headroom probing (PUB-9)
#
# One probe function per provider surface, one result contract — a single
# line, exactly one of:
#   ok:<number><unit>   a number the provider itself reported (measured)
#   unknown             the provider exposes nothing probeable — never a
#                       fabricated 0 (0 means "empty", a lie with teeth)
#   error:<msg>         the provider exposed something and the probe failed
#
# Read-only: a bounded GET against the provider's own API using credentials
# the user already holds. No throttling, no rerouting, no writes anywhere.
# Surfaces that expose nothing (every seat-kind CLI at landing) answer
# `unknown`; a provider that ships a parseable usage report grows a case
# arm or its own quota_probe_* function here.
#
# Requires: lib/config.sh (config_get), lib/pyenv.sh (PYTHON_BIN resolved),
# jq and curl on PATH.

set -euo pipefail

# quota_probe_kind KIND — the seat-kind probe seam (registry kinds: claude,
# opencode, agy, pi). No seat-kind CLI exposes a parseable local usage
# surface at landing, so every kind answers `unknown` — an unregistered
# kind gets the same honest answer. Never a fabricated 0.
quota_probe_kind() { # KIND
  printf 'unknown\n'
}

# quota_probe_openrouter [CONFIG_PATH] — the [proxy] credentials surface
# (OpenRouter-style; the same file the supervisor's credit probe reads).
# Key resolution order: env OPENROUTER_API_KEY first (explicit beats
# implicit), then the config-gated [proxy] credentials file's
# openrouter.api_key. Anything unconfigured answers `unknown`; a configured
# but unreachable or unparsable endpoint answers `error:<msg>`.
quota_probe_openrouter() { # [CONFIG_PATH]
  local cfg="${1:-}" key="" creds="" out left
  if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    key="$OPENROUTER_API_KEY"
  else
    if [[ -z "$cfg" || ! -f "$cfg" ]] \
       || [[ "$(config_get "proxy.enabled" "false" "$cfg")" != "true" ]]; then
      printf 'unknown\n'
      return 0
    fi
    creds=$(config_get "proxy.credentials" "" "$cfg")
    [[ -n "$creds" ]] || { printf 'unknown\n'; return 0; }
    creds="${creds/#\~/$HOME}"
    [[ -f "$creds" ]] || { printf 'unknown\n'; return 0; }
    key=$("$PYTHON_BIN" - "$creds" <<'PYCODE' 2>/dev/null || true
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    print(tomllib.load(f).get("openrouter", {}).get("api_key", ""))
PYCODE
)
    [[ -n "$key" ]] || { printf 'unknown\n'; return 0; }
  fi
  if ! out=$(curl -sf --max-time 5 -H "Authorization: Bearer $key" \
        https://openrouter.ai/api/v1/credits 2>/dev/null); then
    printf 'error:credits endpoint unreachable\n'
    return 0
  fi
  # Both credit fields must be present numbers. A null or missing field
  # must never collapse to 0 through arithmetic defaults — headroom is
  # measured or it is not reported.
  if ! left=$(jq -r 'if (.data.total_credits | type) == "number" and (.data.total_usage | type) == "number"
                     then .data.total_credits - .data.total_usage
                     else error("missing or non-numeric credit fields") end' \
                  <<<"$out" 2>/dev/null); then
    printf 'error:unparsable credits response\n'
    return 0
  fi
  [[ -n "$left" ]] || { printf 'error:unparsable credits response\n'; return 0; }
  printf 'ok:%sUSD\n' "$left"
}
