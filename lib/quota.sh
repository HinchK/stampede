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
quota_probe_kind() { # KIND [SEAT_NAME]
  local kind="$1" seat="${2:-}"
  case "$kind" in
    agy)
      # QUOTA-1: Antigravity/Gemini surfaces an account-level quota wall in
      # the seat's own pane output ("Individual quota reached … Resets in
      # 1h26m33s."). Read-only pane scan — no throttling, no rerouting, no
      # writes; the no-signal contract is unchanged: nothing parseable in
      # recent output → unknown, never a fabricated 0.
      if [[ -z "$seat" ]]; then
        printf 'unknown\n'
        return 0
      fi
      local out dur h=0 m=0 s=0
      out=$(herdr agent read "$seat" --source recent-unwrapped 2>/dev/null || true)
      [[ -n "$out" ]] || { printf 'unknown\n'; return 0; }
      # most recent marker wins (scrollback may carry several)
      dur=$(printf '%s\n' "$out" \
        | sed -nE 's/.*Individual quota reached.*Resets in ([0-9]+[hms]+[0-9hms]*)\..*/\1/p' \
        | tail -n1)
      [[ -n "$dur" ]] || { printf 'unknown\n'; return 0; }
      [[ "$dur" =~ ([0-9]+)h ]] && h=${BASH_REMATCH[1]}
      [[ "$dur" =~ ([0-9]+)m ]] && m=${BASH_REMATCH[1]}
      [[ "$dur" =~ ([0-9]+)s ]] && s=${BASH_REMATCH[1]}
      printf 'ok:%ss\n' "$(( h * 3600 + m * 60 + s ))"
      return 0
      ;;
  esac
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

# ── gate: point-in-time dispatch-safety check (QUOTA-3) ────────────────────
# quota_gate KIND [SEAT] → exit 0 = safe to dispatch, exit 1 = measured
# exhaustion (ok:<N>s — the agy pane-scan's seconds-until-reset). Deliberately
# NOT fail-closed: `unknown` and `error:*` mean "no measured signal", and
# absence of data is not evidence of exhaustion — a false "blocked" here
# would silently starve a healthy seat (the opposite polarity of a safety
# check). The raw probe result is printed either way so callers and humans
# see WHY, not just the code. Point-in-time only: no blocking, no retry
# queue, no new persistent state.
quota_gate() { # KIND [SEAT]
  local res
  res=$(quota_probe_kind "$1" "${2:-}")
  printf '%s\n' "$res"
  if [[ "$res" =~ ^ok:[0-9]+s$ ]]; then
    return 1
  fi
  return 0
}

# CLI dispatcher (library siblings' convention; also keeps `bash -n` honest).
# Usage errors exit 2 — deliberately distinct from the gate's own 0/1
# contract so scriptable callers never confuse "bad invocation" with
# "exhausted".
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-}"
  shift 2>/dev/null || true
  case "$cmd" in
    gate)
      if [[ $# -ne 2 || -z "$1" || -z "$2" ]]; then
        printf 'Usage: %s gate <kind> <seat>   (agy is the only kind with a signal today)\n' "$0" >&2
        exit 2
      fi
      quota_gate "$1" "$2"
      ;;
    *)
      printf 'Usage: %s gate <kind> <seat>\n' "$0" >&2
      exit 2 ;;
  esac
fi
