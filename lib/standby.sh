#!/usr/bin/env bash
# lib/standby.sh — FALLBACK-1: standby orchestrator seat
#
# Quota-triggered, single-command takeover and stand-down. When the agy
# account walls the herd, `up` seats a non-agy (opencode) orchestrator
# under a mechanics-only brief; `down` runs the stand-down handshake and
# only closes the pane after confirmation. A lock on the orchestrator role
# (.herdr-swarm/orchestrator.lock) makes double orchestration impossible:
# takeover requires the real looper to be quota-walled (lib/quota.sh gate
# exit 1) or an explicit --force.
#
# Panes are addressed by explicit workspace-qualified IDs only — never
# --current (ADR 0007). The seat lives in the target repo root (no
# worktree): an orchestrator coordinates; it does not implement.
set -euo pipefail

STANDBY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091  # sibling libs resolved from orchestrator root
source "$STANDBY_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$STANDBY_ROOT/lib/pyenv.sh"
# shellcheck disable=SC1091
source "$STANDBY_ROOT/lib/config.sh"
# shellcheck disable=SC1091  # substitute_template + deliver_brief_nonce
source "$STANDBY_ROOT/lib/briefs.sh"

# ── context helpers ────────────────────────────────────────────────────────

_standby_env() { # TARGET_DIR → exports SLUG/seat names/model/kind via config
  local target="$1"
  # slug derivation mirrors the supervisor: profile REPO, else dir basename
  local slug_source=""
  if [[ -f "$target/.herdr-swarm/profile.env" ]]; then
    # shellcheck disable=SC1091
    source "$STANDBY_ROOT/lib/profile.sh"
    slug_source=$(read_profile_var "REPO" "$target/.herdr-swarm/profile.env" 2>/dev/null || true)
    REPO_ENV="$slug_source"
    TEST_CMD_ENV=$(read_profile_var "TEST_CMD" "$target/.herdr-swarm/profile.env" 2>/dev/null || true)
  fi
  [[ -n "$slug_source" && "$slug_source" != "none" ]] || slug_source=$(basename "$target")
  SLUG=$(slugify "$slug_source")
  # The TARGET's config governs (a swarm-in-a-target runs on the target's
  # roster); fall back to the orchestrator's own config.
  local cfg="$target/swarm.config.toml"
  [[ -f "$cfg" ]] || cfg="${STAMPEDE_CONFIG:-$STANDBY_ROOT/swarm.config.toml}"
  eval "$(config_dump_env "$SLUG" "$cfg")"
  STANDBY_NAME="${SEAT_NAME_looper_standby:-}"
  LOOPER_NAME="${SEAT_NAME_looper:-looper-$SLUG}"
  STANDBY_KIND="${SEAT_KIND_looper_standby:-opencode}"
  STANDBY_MODEL="${SEAT_MODEL_looper_standby:-auto}"
  export SLUG STANDBY_NAME LOOPER_NAME
}

_standby_lock_file() { printf '%s/orchestrator.lock\n' "$1"; }

_standby_wall_rc() { # TARGET_DIR → 0 healthy, 1 walled (quota gate contract)
  bash "$STANDBY_ROOT/lib/quota.sh" gate agy "$LOOPER_NAME" "$1" >/dev/null 2>&1 \
    && return 0 || return $?
}

_standby_seat_enabled() { # is looper_standby in the enabled SEAT_KEYS roster?
  local k
  for k in ${SEAT_KEYS:-}; do
    [[ "$k" == "looper_standby" ]] && return 0
  done
  return 1
}

_standby_anchor_pane() { # TARGET_DIR → an explicit pane id to split from
  # Prefer the real looper's recorded pane; else any recorded seat pane.
  # Splits route by the target ID's own workspace — never --current.
  local f="$1/.herdr-swarm/seats.json"
  [[ -f "$f" ]] || return 1
  jq -r --arg lo "$LOOPER_NAME" '
    ([.seats[]? | select(.name == $lo) | .pane // empty] | first // "") as $lo
    | if $lo != "" then $lo
      else ([.seats[]? | .pane // empty] | map(select(length > 0)) | first // "")
      end' "$f" 2>/dev/null | awk 'NF'
}

_standby_notify() { # TITLE BODY — fire-and-forget; a notification failure
  # must never fail a standby command (HERDR-5 mechanism)
  herdr notification show "[stampede:${SLUG}] $1" --body "$2" >/dev/null 2>&1 || true
}

_standby_render_brief() { # TARGET_DIR → renders the standby brief by path
  local tmpl="$STANDBY_ROOT/briefs/looper-standby.in.md"
  local out="$1/.herdr-swarm/briefs/looper-standby.md"
  mkdir -p "$(dirname "$out")"
  local vars
  vars=$(jq -cn \
    --arg SLUG "$SLUG" \
    --arg REPO "${REPO_ENV:-$SLUG}" \
    --arg TEST_CMD "${TEST_CMD_ENV:-make test}" \
    --arg ARBITER_BIN "$STANDBY_ROOT/lib/arbiter.sh" \
    --arg LOOPER_NAME "$LOOPER_NAME" \
    --arg ARCH_NAME "${SEAT_NAME_arch_1:-${SEAT_NAME_arch:-arch-$SLUG}}" \
    '{SLUG:$SLUG, REPO:$REPO, TEST_CMD:$TEST_CMD, ARBITER_BIN:$ARBITER_BIN,
      LOOPER_NAME:$LOOPER_NAME, ARCH_NAME:$ARCH_NAME}')
  substitute_template "$tmpl" "$out" "$vars"
  printf '%s\n' "$out"
}

# ── commands ───────────────────────────────────────────────────────────────

standby_status() { # TARGET_DIR
  local target="$1"
  _standby_env "$target"
  local lock_f; lock_f=$(_standby_lock_file "$target/.herdr-swarm")
  local wall_rc=0 wall="clear" live="absent" holder="none"
  _standby_wall_rc "$target" || wall_rc=$?
  (( wall_rc == 1 )) && wall="WALLED"
  herdr agent get "$LOOPER_NAME" >/dev/null 2>&1 && live=live
  if [[ -f "$lock_f" ]]; then
    holder=$(jq -r '.holder // "unknown"' "$lock_f")
  fi
  printf 'standby[%s] target=%s\n' "$SLUG" "$target"
  printf '  wall:        %s (quota gate agy %s)\n' "$wall" "$LOOPER_NAME"
  printf '  real looper: %s\n' "$live"
  printf '  orchestrator lock: %s\n' "$holder"
  printf '  config:      looper_standby %s\n' \
    "$(_standby_seat_enabled && printf 'enabled' || printf 'DISABLED')"
}

standby_up() { # TARGET_DIR FORCE
  local target="$1" force="$2"
  _standby_env "$target"
  local state="$target/.herdr-swarm"
  local lock_f; lock_f=$(_standby_lock_file "$state")

  # Gate 1 — config opt-in: disabled seats are never seated, here or by `up`.
  if ! _standby_seat_enabled; then
    printf 'standby: [seats.looper_standby] is disabled in config — enable it (enabled = true) first\n' >&2
    return 1
  fi

  # Gate 2 — single orchestrator: an existing lock blocks takeover outright.
  if [[ -f "$lock_f" ]]; then
    local holder; holder=$(jq -r '.holder // "unknown"' "$lock_f")
    if [[ "$holder" == "standby" ]]; then
      printf 'standby: already holding the orchestrator lock (seat %s)\n' \
        "$(jq -r '.seat // "?"' "$lock_f")"
      return 0
    fi
    printf 'standby: orchestrator lock held by %s — refusing (single-orchestrator guarantee)\n' "$holder" >&2
    return 1
  fi

  # Gate 3 — takeover precondition: walled, or explicit force.
  local wall_rc=0
  _standby_wall_rc "$target" || wall_rc=$?
  if (( wall_rc != 1 )) && [[ "$force" != "1" ]]; then
    printf 'standby: refusing — quota gate reports the account CLEAR (rc=%s) and the real looper is not walled\n' "$wall_rc" >&2
    printf 'standby: takeover requires the wall (lib/quota.sh gate agy) or --force\n' >&2
    return 1
  fi
  (( wall_rc == 1 )) || printf 'standby: WARNING — forced takeover without a detected wall\n' >&2

  # Seat: split by explicit pane id (never --current), cwd = repo root.
  local anchor pane_json pane
  anchor=$(_standby_anchor_pane "$target") || {
    printf 'standby: no recorded seat pane to split from (seats.json) — seat the swarm first\n' >&2
    return 1
  }
  pane_json=$(herdr pane split "$anchor" --direction down --cwd "$target" --no-focus 2>/dev/null) || {
    printf 'standby: pane split failed (anchor %s)\n' "$anchor" >&2
    return 1
  }
  pane=$(jq -r '.result.pane.pane_id // empty' <<<"$pane_json")
  [[ -n "$pane" ]] || { printf 'standby: split returned no pane id\n' >&2; return 1; }

  if ! herdr agent start "$STANDBY_NAME" --kind "$STANDBY_KIND" --pane "$pane" \
        -- --model "$STANDBY_MODEL" >/dev/null 2>&1; then
    printf 'standby: agent start failed (kind %s) — closing the split pane\n' "$STANDBY_KIND" >&2
    herdr pane close "$pane" >/dev/null 2>&1 || true
    return 1
  fi

  local brief
  brief=$(_standby_render_brief "$target") || {
    printf 'standby: brief render failed — closing the split pane\n' >&2
    herdr pane close "$pane" >/dev/null 2>&1 || true
    return 1
  }
  # shellcheck disable=SC1091  # deliver_brief_nonce sourced from briefs.sh
  deliver_brief_nonce "$STANDBY_NAME" "$brief" || true

  mkdir -p "$state"
  jq -n --arg seat "$STANDBY_NAME" --arg pane "$pane" --argjson forced "${force:-0}" \
    --argjson ts "$(date +%s)" \
    '{holder: "standby", seat: $seat, pane: $pane, forced: ($forced == 1), since: $ts}' \
    > "$lock_f"
  printf 'standby: %s seated in %s (cwd %s) under the mechanics brief\n' "$STANDBY_NAME" "$pane" "$target"
  printf 'standby: orchestrator lock acquired (%s). Handoff file expected at %s/research/looper-standby-handoff.md\n' "$lock_f" "$state"
  _standby_notify "standby orchestrator UP" "$STANDBY_NAME holds the orchestrator lock (pane $pane); wall was ${wall_rc:-clear}${force:+ [FORCED]}"
  return 0
}

standby_down() { # TARGET_DIR ASSUME_YES
  local target="$1" yes="$2"
  _standby_env "$target"
  local state="$target/.herdr-swarm"
  local lock_f; lock_f=$(_standby_lock_file "$state")

  if [[ ! -f "$lock_f" ]]; then
    printf 'standby: not holding the orchestrator lock — nothing to stand down\n'
    return 0
  fi
  local holder seat pane
  holder=$(jq -r '.holder // "unknown"' "$lock_f")
  seat=$(jq -r '.seat // "?"' "$lock_f")
  pane=$(jq -r '.pane // ""' "$lock_f")
  if [[ "$holder" != "standby" ]]; then
    printf 'standby: lock held by %s, not the standby seat — refusing\n' "$holder" >&2
    return 1
  fi

  # Handshake 1 — handoff file present and non-empty (warn, never block).
  local handoff="$state/research/looper-standby-handoff.md"
  if [[ ! -s "$handoff" ]]; then
    printf 'standby: WARNING — handoff file missing/empty (%s); standing down loses the standby record\n' "$handoff" >&2
  else
    printf 'standby: handoff file present (%s)\n' "$handoff"
  fi

  # Handshake 2 — seat quiesced (best effort; the confirm below is the gate).
  if ! herdr agent wait "$seat" --until idle --until "done" --timeout 10000 >/dev/null 2>&1; then
    printf 'standby: WARNING — %s not idle within 10s; confirm it is not mid-dispatch before standing down\n' "$seat" >&2
  fi

  # Handshake 3 — explicit confirmation; --yes is the scripted form.
  if [[ "$yes" != "1" ]]; then
    local reply=""
    printf 'Stand down %s (close pane %s, release the orchestrator lock)? [y/N] ' "$seat" "$pane"
    read -r reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || { printf 'standby: stand-down cancelled\n'; return 0; }
  fi

  [[ -z "$pane" ]] || herdr pane close "$pane" >/dev/null 2>&1 || true
  rm -f "$lock_f"
  printf 'standby: %s stood down — pane closed, orchestrator lock released. %s resumes cleanly (it must read the handoff first).\n' "$seat" "${LOOPER_NAME}"
  _standby_notify "standby orchestrator DOWN" "$seat stood down; lock released — ${LOOPER_NAME} resumes (read the handoff)"
  return 0
}

# ── CLI ────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-status}"; shift || true
  force=0; yes=0; target=""
  while (( $# > 0 )); do
    case "$1" in
      --force) force=1 ;;
      --yes)   yes=1 ;;
      -*) printf 'usage: %s {status|up|down} [target_dir] [--force|--yes]\n' "$0" >&2; exit 2 ;;
      *)  target="$1" ;;
    esac
    shift
  done
  target="${target:-${REPO_DIR:-$PWD}}"
  target=$(cd "$target" 2>/dev/null && pwd) || {
    printf 'standby: target dir not found\n' >&2; exit 1; }
  case "$cmd" in
    status) standby_status "$target" ;;
    up)     standby_up "$target" "$force" ;;
    down)   standby_down "$target" "$yes" ;;
    *)      printf 'usage: %s {status|up|down} [target_dir] [--force|--yes]\n' "$0" >&2; exit 2 ;;
  esac
fi
