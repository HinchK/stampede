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

# shellcheck disable=SC1091  # shared wait-output capability probe (HERDR-2)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

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
      # --lines 200: under Herdr 0.9.3's alternate-screen model a banner
      # older than the default 80 rows reads stale-unknown; the audit's §5
      # row for this seam sanctions the wider read (HERDR-2 note,
      # docs/findings/herdr-surface-audit.md).
      out=$(herdr agent read "$seat" --source recent-unwrapped --lines 200 2>/dev/null || true)
      [[ -n "$out" ]] || { printf 'unknown\n'; return 0; }
      # QUOTA-5: the real agy banner is TWO lines —
      #   "⚠ Individual quota reached. Please upgrade your subscription …"
      #   "Resets in 22m24s."
      # so a line-anchored match can never see it. Join the read into one
      # string and allow a bounded gap (the upgrade sentence, ~60 chars)
      # between marker and reset; .{0,120} also covers the legacy
      # single-line form. grep -o emits every match in pane order, so the
      # last one is the most recent marker (scrollback may carry several).
      dur=$(printf '%s\n' "$out" | tr '\n' ' ' \
        | grep -oE 'Individual quota reached.{0,120}Resets in ([0-9]+[hms]+[0-9hms]*)' \
        | sed -nE 's/.*Resets in ([0-9]+[hms]+[0-9hms]*).*/\1/p' \
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

# quota_wait_banner SEAT PANE [TIMEOUT_MS [POLL_MS]] — the blocking variant
# of the agy pane scan (HERDR-2 / ADR 0017 D1) for consumers that would
# otherwise hand-roll a quota_gate poll loop while a banner is pending.
# Blocks until the quota banner surfaces in the seat's pane: one
# `herdr pane wait-output` call where the capability probe says yes (exact
# argv: --regex <banner> --timeout <ms>), else a bounded poll of the
# one-shot probe — the hand-rolled loop this replaces, same result
# contract. Exit 0: banner detected (exhaustion measured). Exit 1: no
# signal within the budget — absence of data is not exhaustion, and no
# signal is ever fabricated.
# QUOTA-5: the real banner is two lines, and wait-output matches pane lines —
# a regex spanning the marker and the reset phrase can never match the split
# form. The marker phrase alone identifies the banner in both shapes (it is
# the first line of the two-line form and the head of the legacy single line);
# the exact reset is measured afterwards by the pane-read probe.
QUOTA_BANNER_REGEX='Individual quota reached'
quota_wait_banner() { # SEAT PANE [TIMEOUT_MS [POLL_MS]]
  local seat="$1" pane="${2:-}" timeout_ms="${3:-30000}" poll_ms="${4:-2000}"
  if [[ -n "$seat" && -n "$pane" ]] && herdr_has_wait_output; then
    if herdr pane wait-output "$pane" --regex "$QUOTA_BANNER_REGEX" --timeout "$timeout_ms" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  local deadline
  deadline=$(( $(date +%s) * 1000 + timeout_ms ))
  while :; do
    if [[ "$(quota_probe_kind agy "$seat")" =~ ^ok: ]]; then
      return 0
    fi
    if (( $(date +%s) * 1000 + poll_ms > deadline )); then
      return 1
    fi
    sleep "$(printf '%d.%03d' $((poll_ms / 1000)) $((poll_ms % 1000)))"
  done
}

# ── gate: point-in-time dispatch-safety check (QUOTA-3) ────────────────────
# quota_gate KIND [SEAT] [TARGET_DIR] → exit 0 = safe to dispatch, exit 1 =
# measured exhaustion. Deliberately NOT fail-closed: `unknown` and `error:*`
# mean "no measured signal", and absence of data is not evidence of
# exhaustion — a false "blocked" here would silently starve a healthy seat
# (the opposite polarity of a safety check). The raw result is printed on
# stdout (one pure line, `unknown` or `ok:<N>s`) so callers and humans see
# WHY, not just the code; account-wide detail goes to stderr. Point-in-time
# only: no retry queue.
#
# QUOTA-5 — the agy wall is ACCOUNT-WIDE ("Individual" = the Google account,
# not the seat): three agy seats hit the wall simultaneously on 2026-10-08
# while each seat's own pane looked clean to the others. So for agy the gate
# probes EVERY agy seat recorded in <target>/.herdr-swarm/seats.json (plus
# the named seat) and applies the LONGEST remaining reset; a banner in any
# one of them defers dispatch to all of them.
#
# Stale-banner guard: pane scrollback has no timestamps, so banner age is
# judged against a first-seen record in <target>/.herdr-swarm/quota-banner-
# seen.json — {"<seat>": {"seen": <epoch>, "reset_s": <N>}}. A measured
# banner is trusted while now <= seen + reset_s + slack; past that its own
# stated window has expired, and the scrollback line is dead text — the gate
# answers no-signal for it unless the measured reset has GROWN past the
# recorded one (a new wall instance prints a new, larger countdown, which
# re-registers). A seat whose probe turns clean has its record cleared.
QUOTA_STALE_SLACK=60
QUOTA_NEW_BANNER_TOL=30

_quota_banner_secs() { # "ok:<N>s" -> N (empty when not an ok-seconds result)
  local r="${1:-}"
  if [[ "$r" =~ ^ok:([0-9]+)s$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
  return 0
}

_quota_seen_write() { # FILE JQ_JSON  (atomic tmp+mv)
  local f="$1" body="$2"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$body" > "${f}.tmp" && mv "${f}.tmp" "$f"
}

quota_gate() { # KIND [SEAT] [TARGET_DIR]
  local kind="$1" seat="${2:-}" target="${3:-$PWD}"
  local res
  if [[ "$kind" != "agy" ]]; then
    res=$(quota_probe_kind "$kind" "$seat")
    printf '%s\n' "$res"
    if [[ "$res" =~ ^ok:[0-9]+s$ ]]; then
      return 1
    fi
    return 0
  fi

  # Account-wide roster: named seat + every agy seat in the ledger.
  local seats_file="${target}/.herdr-swarm/seats.json" names="" n
  if [[ -n "$seat" ]]; then
    names="$seat"
  fi
  if [[ -f "$seats_file" ]]; then
    names="$(printf '%s\n' "$names"
      jq -r '.seats[]? | select(.kind == "agy") | .name' "$seats_file" 2>/dev/null || true)"
  fi
  names=$(printf '%s\n' "$names" | awk 'NF' | sort -u)

  local seen_f="${target}/.herdr-swarm/quota-banner-seen.json"
  local now longest=0 walled="" secs first reset_s elapsed
  now=$(date +%s)
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    res=$(quota_probe_kind agy "$n")
    secs=$(_quota_banner_secs "$res")
    if [[ -z "$secs" ]]; then
      # Clean probe: the wall observably lifted for this seat — clear record.
      if [[ -f "$seen_f" ]] && jq -e --arg n "$n" 'has($n)' "$seen_f" >/dev/null 2>&1; then
        _quota_seen_write "$seen_f" "$(jq --arg n "$n" 'del(.[$n])' "$seen_f")"
      fi
      continue
    fi
    first=""; reset_s=""
    if [[ -f "$seen_f" ]]; then
      first=$(jq -r --arg n "$n" '.[$n].seen // ""' "$seen_f" 2>/dev/null)
      reset_s=$(jq -r --arg n "$n" '.[$n].reset_s // ""' "$seen_f" 2>/dev/null)
    fi
    if [[ -n "$first" && -n "$reset_s" ]]; then
      elapsed=$(( now - first ))
      if (( elapsed > reset_s + QUOTA_STALE_SLACK )); then
        if (( secs > reset_s + QUOTA_NEW_BANNER_TOL )); then
          # Countdown grew past the recorded one: a NEW wall instance.
          printf 'quota: %s: new banner instance (%ss > recorded %ss) — re-registered\n' \
            "$n" "$secs" "$reset_s" >&2
          _quota_seen_write "$seen_f" "$(jq --arg n "$n" --argjson s "$secs" --argjson t "$now" \
            '.[$n] = {seen: $t, reset_s: $s}' "$seen_f")"
        else
          printf 'quota: %s: scrollback banner states %ss but its window expired %ss ago — ignored as stale\n' \
            "$n" "$secs" "$(( elapsed - reset_s ))" >&2
          continue
        fi
      fi
    else
      # First sight: register {now, secs} and trust.
      local body='{}'
      [[ -f "$seen_f" ]] && body="$(cat "$seen_f" 2>/dev/null || echo '{}')"
      _quota_seen_write "$seen_f" "$(printf '%s' "$body" | jq --arg n "$n" --argjson s "$secs" --argjson t "$now" \
        '.[$n] = {seen: $t, reset_s: $s}')"
    fi
    if (( secs > longest )); then
      longest=$secs
    fi
    walled="${walled}${walled:+, }${n}(${secs}s)"
  done <<<"$names"

  if (( longest > 0 )); then
    printf 'ok:%ss\n' "$longest"
    printf 'quota: account-wide wall: banner on %s — longest reset applies to every agy dispatch\n' \
      "$walled" >&2
    return 1
  fi
  printf 'unknown\n'
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
      if [[ $# -lt 2 || $# -gt 3 || -z "$1" || -z "$2" ]]; then
        printf 'Usage: %s gate <kind> <seat> [target_dir]   (agy is the only kind with a signal today; agy scans every agy seat in the target ledger)\n' "$0" >&2
        exit 2
      fi
      quota_gate "$1" "$2" "${3:-$PWD}"
      ;;
    wait)
      if [[ $# -lt 2 || $# -gt 3 || -z "$1" || -z "$2" ]]; then
        printf 'Usage: %s wait <seat> <pane> [timeout_ms]   (blocks until the agy quota banner surfaces)\n' "$0" >&2
        exit 2
      fi
      quota_wait_banner "$1" "$2" "${3:-30000}"
      ;;
    *)
      printf 'Usage: %s gate <kind> <seat>\n' "$0" >&2
      exit 2 ;;
  esac
fi
