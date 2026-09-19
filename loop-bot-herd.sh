#!/usr/bin/env bash
#
# loop-bot-herd — the kultivait herd's supervisor loop.
#
# Not another kickoff wizard (herdr-kultivait-session.sh owns seating);
# this is the long-r  unning watcher that makes the swarm self-tending:
#
#   watch      poll loop: herd health, verdict harvest, suite gate,
#              credit/quota probes, unpushed watchdog, optional frontier drain
#   once       a single pass (cron-able)
#   status     one-shot readout, no side effects
#   dispatch   file-based brief delegation (nonce channel, no inline mangling)
#   pause/resume  toggle the loop's actions without killing it
#
# Human gates preserved by design: it never pushes, never answers worker
# dialogs, never force-closes issues, and frontier-drain is OFF by default
# (the looper stays the dispatcher unless you flip it on).
#
# Channel protocol (lesson from #215/#216): every dispatch gets a nonce
# output file; briefs travel as file paths, never inline text.

set -euo pipefail

# ── project binding ────────────────────────────────────────────────────────
# The supervisor is project-agnostic: REPO_DIR defaults to the invocation
# directory; REPO / TEST_CMD come from the project's rendered profile; seats
# come from the swarm distribution's swarm.config.toml; ALL session state
# lives inside <REPO_DIR>/.herdr-swarm/ (portable, teardown-aware).
REPO_DIR="${REPO_DIR:-$PWD}"
STATE_DIR="${STATE_DIR:-${REPO_DIR}/.herdr-swarm}"
CONTROL="$STATE_DIR/control.json"
SESSION_LOG="$STATE_DIR/session-verdicts.jsonl"
CHANNEL_DIR="${STATE_DIR}/channel"
POLL_S="${POLL_S:-30}"
UNPUSHED_NUDGE_S=$((60 * 60))       # one unpushed reminder per hour
CREDIT_WARN_USD="${CREDIT_WARN_USD:-1.00}"
SUITE_TIMEOUT_S="${SUITE_TIMEOUT_S:-300}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$SCRIPT_DIR/lib/profile.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$SCRIPT_DIR/lib/config.sh"

# Project profile (rendered by the launcher's ensure_profile pass)
PROFILE_ENV="${REPO_DIR}/.herdr-swarm/profile.env"
REPO=$(read_profile_var "REPO" "$PROFILE_ENV")
TEST_CMD=$(read_profile_var "TEST_CMD" "$PROFILE_ENV")

# Namespaced seat roster from swarm.config.toml (Herdr's agent registry is
# server-global, so seat names carry the project slug)
slug_source="${REPO:-}"
if [[ -z "$slug_source" || "$slug_source" == "none" ]]; then
  slug_source=$(basename "$REPO_DIR")
fi
PROJECT_SLUG=$(slugify "$slug_source")
config_env=$(config_dump_env "$PROJECT_SLUG")
eval "$config_env"

EXPECTED_SEATS=()
for seat_key in $SEAT_KEYS; do
  name_var="SEAT_NAME_${seat_key}"
  EXPECTED_SEATS+=("${!name_var}")
done

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  DIM=$(tput dim); RESET=$(tput sgr0)
  GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RED=$(tput setaf 1); BLUE=$(tput setaf 4)
else
  DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""; BLUE=""
fi

log()  { printf '%s[%s]%s %s\n' "$DIM" "$(date '+%H:%M:%S')" "$RESET" "$1"; }
ok()   { log "${GREEN}✓${RESET} $1"; }
warn() { log "${YELLOW}⚠${RESET} $1"; }
bad()  { log "${RED}✗${RESET} $1"; }
note() { log "${DIM}•${RESET} $1"; }
step() { log "${BLUE}▸${RESET} $1"; }

mkdir -p "$STATE_DIR" "$CHANNEL_DIR"

# ---- control file --------------------------------------------------------
# {"paused": false, "frontier_drain": false, "suite_gate": true}
ctl_get() {
  [[ -f "$CONTROL" ]] || printf '{"paused": false, "frontier_drain": false, "suite_gate": true}' > "$CONTROL"
  jq -r ".$1 // false" "$CONTROL" 2>/dev/null || echo false
}
ctl_set() { # key value(json bool)
  [[ -f "$CONTROL" ]] || printf '{"paused": false, "frontier_drain": false, "suite_gate": true}' > "$CONTROL"
  tmp=$(mktemp); jq --arg k "$1" --argjson v "$2" '.[$k] = $v' "$CONTROL" > "$tmp" && mv "$tmp" "$CONTROL"
}

# ---- 1. herd health ------------------------------------------------------
health_pass() {
  local listing alive=0
  listing=$(herdr agent list 2>/dev/null || echo '{}')
  for seat in "${EXPECTED_SEATS[@]}"; do
    if grep -q "\"$seat\"" <<<"$listing"; then
      alive=$((alive + 1))
    else
      warn "seat absent: $seat (seat it: ../kultivait-internals/herdr-briefs/ has its brief; herdr-kultivait-session.sh recovers)"
    fi
  done
  if (( alive == ${#EXPECTED_SEATS[@]} )); then
    ok "herd healthy (${alive}/${#EXPECTED_SEATS[@]} seats)"
  else
    warn "herd partial: ${alive}/${#EXPECTED_SEATS[@]}"
  fi
  if curl -sf --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
    : # ollama up — say nothing unless it's down (quiet loop)
  else
    warn "ollama not answering on :11434 — local tiers unavailable"
  fi
}

# ---- 2. verdict harvest + suite gate -------------------------------------
# ARCH DONE lines are the herd's completion protocol. Dedup is (ticket, sha):
# an identical code state is never re-gated, while a RED ticket re-verdicted
# at a NEW commit sha is re-evaluated through the suite gate. Tickets already
# gated green/skipped are permanently retired.
harvest_verdicts() {
  local seat out
  for seat in "${EXPECTED_SEATS[@]}"; do
    out=$(herdr agent read "$seat" 2>/dev/null || true)
    [[ -n "$out" ]] || continue
    while IFS= read -r line; do
      local ticket verdict_line ts sha
      verdict_line="$line"
      ticket=$(sed -nE 's/.*ARCH DONE #([0-9]+).*/\1/p' <<<"$verdict_line" | tail -n1)
      [[ -n "$ticket" ]] || continue
      # Commit sha: carried in the verdict line (ARCH DONE #N <sha>), else repo HEAD
      sha=$(sed -nE 's/.*ARCH DONE #[0-9]+[[:space:]]+([0-9a-fA-F]{7,40}).*/\1/p' <<<"$verdict_line" | tail -n1)
      [[ -n "$sha" ]] || sha=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
      ts=$(date +%s)
      if [[ -f "$SESSION_LOG" ]]; then
        # Permanent retire: this ticket already gated green or skipped
        if jq -e -s --argjson t "$ticket" 'any(.[]; .ticket == $t and (.suite == "green" or .suite == "skipped"))' "$SESSION_LOG" >/dev/null 2>&1; then
          continue
        fi
        # (ticket, sha) dedup: this exact code state was already evaluated
        if jq -e -s --argjson t "$ticket" --arg s "$sha" 'any(.[]; .ticket == $t and .sha == $s)' "$SESSION_LOG" >/dev/null 2>&1; then
          continue
        fi
      fi
      local suite_ok="skipped"
      if [[ "$(ctl_get suite_gate)" == "true" ]]; then
        if test_cmd_is_runnable "$TEST_CMD"; then
          log "verdict for #$ticket @ ${sha} — running suite gate: ${TEST_CMD}"
          if (cd "$REPO_DIR" && timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD" >/dev/null 2>&1); then
            suite_ok="green"; ok "suite gate GREEN for #$ticket @ ${sha}"
            echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
          else
            suite_ok="RED"; bad "suite gate RED for #$ticket @ ${sha} — NOT filed; arch must fix before done"
            echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
            herdr agent prompt "$seat" "LOOP-BOT: verdict for #$ticket @ ${sha} harvested but the suite is RED — fix, commit, and re-verdict with the new sha (gate is structural now)." >/dev/null 2>&1 || true
          fi
        else
          # No runnable suite for this project — never fake-green, record as skipped
          warn "TEST_CMD not runnable (${TEST_CMD:-<empty>}) — recording verdict for #$ticket without suite gate"
          echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
        fi
      else
        echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
      fi
      [[ "$suite_ok" == "green" || "$suite_ok" == "skipped" ]] && \
        herdr agent prompt looper "LOOP-BOT: filed verdict for #$ticket @ ${sha} from $seat's pane ($suite_ok)." >/dev/null 2>&1 || true
    done < <(grep -E "ARCH DONE #[0-9]+" <<<"$out" | tail -n 5)
  done
}

# ---- 3. unpushed-commit watchdog ------------------------------------------
unpushed_watch() {
  local n now key="unpushed_last_nudge"
  n=$(cd "$REPO_DIR" && git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
  (( n > 0 )) || return 0
  local last=0
  [[ -f "$STATE_DIR/$key" ]] && last=$(cat "$STATE_DIR/$key")
  now=$(date +%s)
  if (( now - last > UNPUSHED_NUDGE_S )); then
    warn "$n commit(s) local-only on main — human gate: git push origin main --tags"
    echo "$now" > "$STATE_DIR/$key"
  fi
}

# ---- 4. credit / quota probes ---------------------------------------------
credits_watch() {
  local key out
  key=$(python3 - << 'EOF' 2>/dev/null || true
from pathlib import Path
import tomllib
p = Path.home() / ".kultivait" / "credentials.toml"
if p.is_file():
    d = tomllib.loads(p.read_text())
    print(d.get("openrouter", {}).get("api_key", ""))
EOF
)
  [[ -n "$key" ]] || return 0
  out=$(curl -sf --max-time 5 -H "Authorization: Bearer $key" https://openrouter.ai/api/v1/credits 2>/dev/null || true)
  [[ -n "$out" ]] || { warn "OpenRouter /credits unreachable"; return 0; }
  python3 - "$out" "$CREDIT_WARN_USD" << 'EOF'
import json, sys
d = json.loads(sys.argv[1])
left = float(d["data"]["total_credits"]) - float(d["data"]["total_usage"])
if left < float(sys.argv[2]):
    print(f"WARN ${left:.2f} USD left on OpenRouter")
EOF
}

# ---- 5. optional frontier drain (looper remains dispatcher unless enabled) --
frontier_drain() {
  [[ "$(ctl_get frontier_drain)" == "true" ]] || return 0
  # Local-only projects have no GitHub frontier to drain
  [[ -n "${REPO:-}" && "$REPO" != "none" ]] || return 0
  local next
  next=$(gh issue list -R "$REPO" --state open --json number,title,assignees \
    --jq '[.[] | select((.assignees | length) == 0)] | sort_by(.number) | .[0] // empty | "#\(.number) \(.title)"' 2>/dev/null || true)
  [[ -n "$next" ]] || return 0
  local rate_key="frontier_last_nudge" now last=0
  [[ -f "$STATE_DIR/$rate_key" ]] && last=$(cat "$STATE_DIR/$rate_key")
  now=$(date +%s)
  (( now - last > 1800 )) || return 0
  echo "$now" > "$STATE_DIR/$rate_key"
  herdr agent prompt looper "LOOP-BOT (frontier drain, auto): next unassigned open ticket is $next — dispatch or park it deliberately." >/dev/null 2>&1 || true
  ok "frontier drain nudged looper → $next"
}

# ---- dispatch: nonce channel, file-based briefs ----------------------------
cmd_dispatch() { # dispatch WORKER BRIEF_FILE
  local worker="$1" brief="$2" nonce out
  [[ -f "$brief" ]] || { bad "brief file not found: $brief"; exit 1; }
  nonce=$(date +%s)-$RANDOM
  out="$CHANNEL_DIR/${worker}-${nonce}.md"
  herdr agent prompt "$worker" "BRIEF (file): $brief — read it with your file tools and execute. REPLY CHANNEL: write your complete response to $out and reply with only the path." >/dev/null
  ok "dispatched $worker ← $(basename "$brief") ; channel: $out"
  note "poll: while [ ! -s $out ]; do sleep 5; done"
}

cmd_once() {
  health_pass
  harvest_verdicts
  unpushed_watch
  credits_watch
  frontier_drain
}

cmd_watch() {
  log "loop-bot watching (poll ${POLL_S}s) — pause with: $0 pause"
  while true; do
    if [[ "$(ctl_get paused)" == "true" ]]; then
      log "paused — actions skipped (resume: $0 resume)"
    else
      cmd_once || true
    fi
    sleep "$POLL_S"
  done
}

cmd_status() {
  echo "control: $(cat "$CONTROL" 2>/dev/null || echo '(defaults)')"
  echo "verdicts filed: $(grep -c . "$SESSION_LOG" 2>/dev/null || echo 0)"
  echo "unpushed: $(cd "$REPO_DIR" && git rev-list --count origin/main..HEAD 2>/dev/null || echo '?') commit(s)"
  echo "channel dir: $CHANNEL_DIR ($(find "$CHANNEL_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ') file(s))"
}

case "${1:-watch}" in
  watch)   cmd_watch ;;
  once)    cmd_once ;;
  status)  cmd_status ;;
  pause)   ctl_set paused true;  ok "paused — polling continues, actions skip" ;;
  resume)  ctl_set paused false; ok "resumed" ;;
  drain-on)  ctl_set frontier_drain true;  ok "frontier drain ON (looper still decides)" ;;
  drain-off) ctl_set frontier_drain false; ok "frontier drain OFF" ;;
  gate-off)  ctl_set suite_gate false; ok "suite gate disabled (not recommended)" ;;
  gate-on)   ctl_set suite_gate true;  ok "suite gate enabled" ;;
  dispatch) shift; cmd_dispatch "$@" ;;
  *) cat <<EOF
usage: loop-bot-herd.sh [command]
  watch        supervisor loop (default): health, verdicts, suite gate,
               credits, unpushed watch, optional frontier drain
  once         single pass (cron-able)
  status       readout
  dispatch W B file-based delegation via the nonce channel
  pause|resume toggle actions without killing the loop
  drain-on|drain-off   frontier drain toggle (default off)
  gate-on|gate-off     suite gate toggle (default on)
EOF
  ;;
esac
