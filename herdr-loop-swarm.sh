#!/usr/bin/env bash
#
# herdr-loop-swarm: Next-Generation Multi-Agent Swarm Orchestrator
# Coordinates AGY (Gemini), Claude Code, OpenCode (GLM-5.3), and Kultivait Local Proxy
# Location: ~/fun/loop-bot-herd-agy/herdr-loop-swarm.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="$SCRIPT_DIR/lib"
CONFIG_FILE="$SCRIPT_DIR/swarm.config.toml"
ENV_FILE="${PWD}/.env"

# ──────────────────────────────────────────────────────────────────────────
# Shared swarm libraries (loaded before dispatch so subcommands inherit them)
# ──────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/common.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/profile.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/lifecycle.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/config.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/briefs.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/preflight.sh"

# ──────────────────────────────────────────────────────────────────────────
# Lifecycle subcommands (delegating to lib/lifecycle.sh)
# ──────────────────────────────────────────────────────────────────────────
case "${1:-}" in
  status)
    swarm_status "${2:-$PWD}"
    exit $?
    ;;
  down)
    shift
    down_dir="$PWD"; down_yes=0; down_keep=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -y|--yes)               down_yes=1 ;;
        --keep-ws|--keep-workspace) down_keep=1 ;;
        -h|--help)
          printf 'Usage: %s down [dir] [-y|--yes] [--keep-ws|--keep-workspace]\n' "$(basename "$0")"
          exit 0 ;;
        -*) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
        *)  down_dir="$1" ;;
      esac
      shift
    done
    swarm_down "$down_dir" "$down_yes" "$down_keep"
    exit $?
    ;;
  up)
    # explicit launch; consume the subcommand token
    shift
    ;;
  verify)
    # post-seating readiness gate (lib/lifecycle.sh)
    swarm_verify_seats "${2:-$PWD}" "${3:-30000}"
    exit $?
    ;;
  -*|"")
    # flags or bare invocation: default to launch
    ;;
esac

# Command-Line Flags
CLI_MODE=""
CLI_MAP=""
CLI_TOPIC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)
      CLI_MODE="${2:-}"; shift 2 ;;
    -n|--map)
      CLI_MAP="${2:-}"; shift 2 ;;
    -t|--topic|--milestone)
      CLI_TOPIC="${2:-}"; shift 2 ;;
    -s|--seat-only)
      CLI_MODE="s"; shift ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [up] [OPTIONS] | status [dir] | down [dir] [FLAGS]

Autonomous Multi-Agent Orchestration Swarm (Herdr + AGY + Claude Code + OpenCode + Kultivait)

Subcommands:
  up (default)            Launch or re-attach the swarm for the current repo
  status [dir]            Show workspace, seats, profile, and recent activity
  verify [dir] [ms]       Check every seat is alive and brief-ready (default 30000ms)
  down [dir] [FLAGS]      Tear down the swarm tied to a directory
                            -y, --yes                      skip confirmation
                            --keep-ws, --keep-workspace    close seat panes only

Options (launch):
  -m, --mode <w|b|r|a|s>  Swarm mode:
                            w = Wayfinder Map (interactive chartering)
                            b = Brainstorm (PRD & ticket breakdown)
                            r = Resume Map (drain active Wayfinder map)
                            a = Auto-Queue (drain backlog / loop:ready)
                            s = Seat Only (initialize topology & briefs only)
  -n, --map <NUM>         Map issue number to resume (for mode 'r')
  -t, --topic <DESC>      Milestone description / topic (for modes 'w' or 'b')
  -s, --seat-only         Shorthand for --mode s
  -h, --help              Show this help message
EOF
      exit 0 ;;
    *)
      shift ;;
  esac
done

# Terminal Formatting
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  BLUE=$(tput setaf 4); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RED=$(tput setaf 1); CYAN=$(tput setaf 6)
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

_clear() {
  [[ -t 1 ]] || return 0
  if command -v tput >/dev/null 2>&1; then tput clear; else printf '\033[2J\033[3J\033[H'; fi
}

say()   { printf '  %s\n' "$1"; }
step()  { printf '  %s•%s %s\n' "$BLUE" "$RESET" "$1"; }
note()  { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn()  { printf '  %s⚠ %s%s\n' "$YELLOW" "$1" "$RESET"; }
good()  { printf '  %s✓ %s%s\n' "$GREEN" "$1" "$RESET"; }
pause() { printf '  %s%s%s ' "$DIM" "${1:-Press Enter to continue}" "$RESET"; read -r _ || true; }

confirm() {
  local reply=""
  printf '  %s? %s [y/N] ' "$YELLOW" "$1"
  read -r reply || true
  [[ "$reply" =~ ^[Yy] ]]
}

ask() {
  local key="$1" prompt="$2" default_val="${3:-}" input
  if [[ -n "$default_val" ]]; then
    printf '  %s%s%s %s[Enter = %s]%s ' "$BOLD" "$prompt" "$RESET" "$DIM" "$default_val" "$RESET"
  else
    printf '  %s%s%s ' "$BOLD" "$prompt" "$RESET"
  fi
  read -r input || true
  [[ -z "$input" && -n "$default_val" ]] && input="$default_val"
  printf -v "$key" '%s' "$input"
}

write_env() {
  local key="$1" value="$2" tmp
  touch "$ENV_FILE"
  tmp=$(mktemp)
  grep -vE "^${key}=" "$ENV_FILE" > "$tmp" || true
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$ENV_FILE"
}

# ──────────────────────────────────────────────────────────────────────────
# Preflight & Environment Detection
# ──────────────────────────────────────────────────────────────────────────

_clear
printf '\n%s%s  ⚡ Herdr Loop Swarm — Autonomous Multi-Agent Orchestrator%s\n' "$BOLD" "$CYAN" "$RESET"
printf '%s  AGY (Gemini) · Claude Code · OpenCode (GLM-5.3) · Kultivait Local Proxy%s\n\n' "$DIM" "$RESET"

# ──────────────────────────────────────────────────────────────────────────
# Preflight: 9-point dependency & daemon verification (lib/preflight.sh)
# ──────────────────────────────────────────────────────────────────────────

# Runs before ANY workspace creation, pane split, or profile prompt. Silent on
# success; on failure the full matrix + remediation goes to stderr and we
# abort fail-closed.
preflight_run
if ! preflight_exit_code; then
  preflight_report_text >&2
  printf '  %s✖ FATAL: preflight verification failed — resolve the errors above before launching.%s\n' "$RED" "$RESET" >&2
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────
# Project Profile (fail-closed; see lib/profile.sh)
# ──────────────────────────────────────────────────────────────────────────

# Resolves REPO / TEST_CMD / ECOSYSTEM / DOCS_DIR before any workspace or pane
# is created. Prompts interactively when possible; aborts fail-closed when a
# required fact cannot be established (never defaults to a fake repo or a
# fake-green test command).
ensure_profile "$PWD" 1
good "Profile — repo: ${REPO:-none} · test: ${TEST_CMD} · ecosystem: ${ECOSYSTEM} · docs: ${DOCS_DIR}"

# Project slug: namespaces every agent name (Herdr's registry is server-global;
# grammar ^[a-z][a-z0-9_-]*$ per docs/findings/herdr-semantics.md). Falls back
# to the directory name for local-only projects so parallel swarms never
# collide on agent names.
slug_source="${REPO:-}"
if [[ -z "$slug_source" || "$slug_source" == "none" ]]; then
  slug_source=$(basename "$PWD")
fi
PROJECT_SLUG=$(slugify "$slug_source")
good "Project slug: ${PROJECT_SLUG}"

# Config binding: seats, kinds, models, tabs — single source of truth
config_env=$(config_dump_env "$PROJECT_SLUG" "$CONFIG_FILE")
eval "$config_env"
good "Config bound: ${SWARM_CONFIG_NAME} — seats: ${SEAT_KEYS}"

# Namespaced agent handles for kickoff dispatches
ARCH_AGENT="${SEAT_NAME_arch:-arch}"
LOOPER_AGENT="${SEAT_NAME_looper:-looper}"

# Stable telemetry session (shared with loop-bot so the Ops stream sees all)
SESSION_ID=$(telemetry_session_id "${PWD}/.herdr-swarm")

EXTERNAL=0
if [[ "${HERDR_ENV:-}" != 1 ]]; then
  EXTERNAL=1
  note "Running in external terminal mode"
  # (daemon responsiveness + binary presence already verified by preflight)
  WS_LABEL=$(basename "$PWD")
  WS_ID=$(find_workspace_by_cwd "$PWD")
  if [[ -z "$WS_ID" ]]; then
    note "Creating dedicated workspace: ${WS_LABEL} (none bound to this directory)"
    WS_ID=$(herdr workspace create --cwd "$PWD" --label "$WS_LABEL" 2>/dev/null \
      | jq -r '.result.workspace.workspace_id // .result.workspace_id // empty')
  else
    note "Reusing existing workspace ${WS_ID} (cwd-bound to this directory)"
  fi
  [[ -n "$WS_ID" ]] || { warn "Failed to initialize workspace"; exit 1; }
  good "Workspace active: ${WS_LABEL} (${WS_ID})"
else
  WS_ID="${HERDR_WORKSPACE_ID:-}"
  WS_LABEL="${HERDR_WORKSPACE_LABEL:-$(basename "$PWD")}"
  good "Inside Herdr workspace: ${WS_LABEL} (${WS_ID})"
fi

# Test validation command comes from the project profile (lib/profile.sh);
# there is deliberately no ad-hoc ecosystem sniffing or "true" fake-green here.

# Check Model Runtimes
if curl -sf --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
  good "Ollama local model runtime: active (:11434)"
else
  warn "Ollama is down"
  if confirm "Start Ollama now via 'brew services start ollama'?"; then
    brew services start ollama
    sleep 3
  fi
fi

# Check Kultivait Routing Proxy
if curl -sf --max-time 2 http://localhost:4114/openapi.json >/dev/null 2>&1; then
  good "Kultivait intelligent routing proxy: active (:4114)"
else
  note "Kultivait proxy is not running on :4114 (will launch in Ops tab)"
fi

# Canonical GitHub repository comes from the project profile (lib/profile.sh,
# resolved fail-closed above — prefer upstream over origin, never a hardcoded
# default). "none" means local-only operation; gh-dependent features degrade.
good "Target GitHub repository: ${REPO:-none}"

# ──────────────────────────────────────────────────────────────────────────
# Swarm Mode Selection
# ──────────────────────────────────────────────────────────────────────────

MODE="${CLI_MODE:-}"
if [[ -z "$MODE" ]]; then
  printf '\n%s▸ Select Swarm Mode%s\n' "$BOLD" "$RESET"
  say "  [w] Wayfinder Map — Interactive milestone charting with architect"
  say "  [b] Brainstorming — PRD & issue decomposition loop"
  say "  [r] Resume Map    — Drain an active Wayfinder Map issue"
  say "  [a] Auto-Queue    — Autonomous loop draining ready backlog issues"
  say "  [s] Seat Only     — Initialize swarm panes & briefs without dispatch"

  until [[ "${MODE:-}" =~ ^[wbras]$ ]]; do
    ask MODE "Mode (w/b/r/a/s):" "w"
    MODE=$(printf '%s' "${MODE:-}" | tr '[:upper:]' '[:lower:]')
  done
else
  MODE=$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]')
  good "Swarm mode selected via CLI: ${MODE}"
fi

MAP_NUM="${CLI_MAP:-}"
MILESTONE="${CLI_TOPIC:-}"

case "$MODE" in
  w|b)
    if [[ -z "$MILESTONE" ]]; then
      ask MILESTONE "Milestone description / topic:"
    fi
    ;;
  r)
    if [[ -z "$MAP_NUM" ]]; then
      note "Querying open Wayfinder maps on ${REPO}..."
      MAPS_JSON=$(gh issue list -R "$REPO" --label "wayfinder:map" --state open --json number,title 2>/dev/null || echo "[]")
      MAP_COUNT=$(jq 'length' <<<"$MAPS_JSON" 2>/dev/null || echo "0")
      if (( MAP_COUNT > 0 )); then
        say "Open Wayfinder maps:"
        jq -r '.[] | "    #\(.number) — \(.title)"' <<<"$MAPS_JSON" 2>/dev/null || true
        NEWEST_MAP=$(jq -r '.[0].number // empty' <<<"$MAPS_JSON" 2>/dev/null || true)
        ask MAP_NUM "Map Issue # to resume:" "$NEWEST_MAP"
      else
        ask MAP_NUM "Map Issue # to resume:" ""
      fi
    fi
    MAP_NUM="${MAP_NUM#\#}"
    ;;
  a)
    # Suite gate: auto-queue loops verify every ticket with TEST_CMD; a
    # non-runnable command would fake-green the loop — abort fail-closed.
    if ! test_cmd_is_runnable "${TEST_CMD:-}"; then
      printf '  %s✖ FATAL: auto-queue requires a runnable test validation command (found: "%s").%s\n' \
        "$RED" "${TEST_CMD:-<empty>}" "$RESET" >&2
      printf '    Fix: set TEST_CMD in %s/.herdr-swarm/profile.env (e.g. TEST_CMD="make test")\n' "$PWD" >&2
      exit 1
    fi
    note "Autonomous queue mode: will poll issues labeled 'loop:ready' or backlog"
    ;;
  s)
    note "Seat only mode: will initialize panes and deliver briefs without auto-dispatch"
    ;;
esac

# ──────────────────────────────────────────────────────────────────────────
# Layout Engine: 2-Tab Balanced Topology + Dynamic Seating
# ──────────────────────────────────────────────────────────────────────────

printf '\n%s▸ Building Swarm Topology (Herd & Ops Tabs)%s\n' "$BOLD" "$RESET"

# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$LIB_DIR/layout_engine.sh"

read -r HerdTab HerdAnchor <<< "$(tab_by_label "$WS_ID" "herd")"
read -r OpsTab OpsAnchor   <<< "$(tab_by_label "$WS_ID" "ops")"

agent_alive() { herdr agent list 2>/dev/null | grep -q "\"$1\""; }
pane_of_agent() { herdr agent get "$1" 2>/dev/null | jq -r '.result.agent.pane_id // empty'; }

# Render project briefs from briefs/*.in.md templates (profile- & slug-aware)
printf '\n%s▸ Rendering Standing Briefs%s\n' "$BOLD" "$RESET"
render_all_briefs "$PWD" "$PROJECT_SLUG"

printf '\n%s▸ Seating Agents & Delivering Standing Briefs%s\n' "$BOLD" "$RESET"

# Seat ledger lines ("name|kind|pane") + per-tab pane collections
SEAT_LEDGER=""
SEATED_HERD_PANES=""
SEATED_OPS_PANES=""

# Dynamic seating: iterate config seats grouped by tab. Topology per tab:
# seat 0 splits right of the tab anchor, seat 1 below seat 0, rest below the
# anchor (reproduces the classic herd/ops floor plan from declaration order).
for tab_name in herd ops; do
  tab_anchor="$HerdAnchor"
  [[ "$tab_name" == "ops" ]] && tab_anchor="$OpsAnchor"

  seat_idx=0
  prev_pane=""
  for seat_key in $SEAT_KEYS; do
    tab_var="SEAT_TAB_${seat_key}"
    [[ "${!tab_var}" == "$tab_name" ]] || continue

    name_var="SEAT_NAME_${seat_key}"
    kind_var="SEAT_KIND_${seat_key}"
    model_var="SEAT_MODEL_${seat_key}"
    brief_var="SEAT_BRIEF_${seat_key}"
    seat_name="${!name_var}"
    seat_kind="${!kind_var}"
    seat_model="${!model_var}"
    seat_brief="${!brief_var}"

    # Rendered brief: config "briefs/foo.md" -> .herdr-swarm/briefs/foo.md
    rendered_brief="${PWD}/.herdr-swarm/briefs/$(basename "$seat_brief")"

    seat_pane=""
    if agent_alive "$seat_name"; then
      note "Agent '${seat_name}' is already seated"
      seat_pane=$(pane_of_agent "$seat_name")
    else
      case "$seat_idx" in
        0) seat_pane=$(split_pane "$tab_anchor" right 0.5 "$PWD") ;;
        1) seat_pane=$(split_pane "${prev_pane:-$tab_anchor}" down 0.5 "$PWD") ;;
        *) seat_pane=$(split_pane "$tab_anchor" down 0.5 "$PWD") ;;
      esac
      if [[ -z "$seat_pane" ]]; then
        warn "No pane available for '${seat_name}' — seating into tab anchor"
        seat_pane="$tab_anchor"
      fi

      step "Starting agent '${seat_name}' (${seat_kind})..."
      if [[ "$seat_kind" == "opencode" && -n "$seat_model" && "$seat_model" != "auto" ]]; then
        herdr agent start "$seat_name" --kind "$seat_kind" --pane "$seat_pane" -- --model "$seat_model" >/dev/null 2>&1 \
          || { warn "Failed to seat agent '${seat_name}' in pane ${seat_pane}"; seat_pane=""; }
      else
        herdr agent start "$seat_name" --kind "$seat_kind" --pane "$seat_pane" >/dev/null 2>&1 \
          || { warn "Failed to seat agent '${seat_name}' in pane ${seat_pane}"; seat_pane=""; }
      fi
      if [[ -n "$seat_pane" ]]; then
        # Nonce file-path protocol (lib/briefs.sh): never inline brief text
        deliver_brief_nonce "$seat_name" "$rendered_brief" \
          || warn "Brief delivery failed for '${seat_name}'"
      fi
    fi

    if [[ -n "$seat_pane" ]]; then
      SEAT_LEDGER+="${seat_name}|${seat_kind}|${seat_pane}"$'\n'
      if [[ "$tab_name" == "ops" ]]; then
        SEATED_OPS_PANES+=" ${seat_pane}"
      else
        SEATED_HERD_PANES+=" ${seat_pane}"
      fi
      prev_pane="$seat_pane"
    else
      [[ -n "$prev_pane" ]] || prev_pane="$tab_anchor"
    fi
    seat_idx=$((seat_idx + 1))
  done
done

# Ops services pane (proxy host) — split below the ops anchor
SRV_PANE=$(split_pane "$OpsAnchor" down 0.5 "$PWD") || true

# Live telemetry stream occupies the Ops anchor pane (replaces raw log tail)
herdr pane rename "$OpsAnchor" "telemetry-stream" >/dev/null 2>&1 || true
herdr pane run "$OpsAnchor" "python3 -u '$LIB_DIR/telemetry.py' stream '$SESSION_ID' '${PWD}/.herdr-swarm/traces'" >/dev/null 2>&1 || true

# Geometry Guard Floor
# shellcheck disable=SC2086  # intentional word splitting over collected pane ids
check_and_relocate_geometry "$WS_ID" "$HerdAnchor" ${SEATED_HERD_PANES:-}
# shellcheck disable=SC2086  # intentional word splitting over collected pane ids
check_and_relocate_geometry "$WS_ID" "$OpsAnchor" ${SEATED_OPS_PANES:-}

good "Layout established: Herd Tab (${HerdTab}) & Ops Tab (${OpsTab})"

# Durable seat ledger for selective teardown (lib/lifecycle.sh swarm_down)
mkdir -p "${PWD}/.herdr-swarm"
if [[ -n "$SEAT_LEDGER" ]]; then
  printf '%s' "$SEAT_LEDGER" | jq -R -s -c --arg ws "$WS_ID" \
    'split("\n") | map(select(length > 0) | split("|"))
     | {workspace_id: $ws, seats: map({name: .[0], kind: .[1], pane: .[2]})}' \
    > "${PWD}/.herdr-swarm/seats.json"
  good "Seat ledger written: ${PWD}/.herdr-swarm/seats.json"
fi

# ──────────────────────────────────────────────────────────────────────────
# Post-Seating Verification (T-010): readiness + brief acknowledgment gate
# ──────────────────────────────────────────────────────────────────────────

if swarm_verify_seats "$PWD"; then
  good "All seats verified ready"
else
  warn "One or more seats failed readiness verification"
  if [[ "$MODE" == "a" ]]; then
    # Auto-queue fails closed when CRITICAL seats (arch, pm) are not ready —
    # an unattended loop must not start on an unverified herd.
    critical_fail=0
    for critical_seat in "$ARCH_AGENT" "${SEAT_NAME_pm:-pm}"; do
      if ! herdr agent wait "$critical_seat" --until idle --until "done" --until working --timeout 2000 >/dev/null 2>&1; then
        bad "Critical seat not ready: ${critical_seat}"
        critical_fail=1
      fi
    done
    if (( critical_fail )); then
      printf '  %s✖ FATAL: auto-queue requires verified seats (arch, pm). Re-run seating or investigate panes.%s\n' "$RED" "$RESET" >&2
      exit 1
    fi
    note "Critical seats (arch, pm) ready — continuing despite non-critical seat failures"
  else
    note "Continuing (non-autonomous mode) — investigate failed seats before dispatching work"
  fi
fi

# Telemetry: swarm-ready lifecycle event (streams live into the Ops pane)
TRACE_DIR_PATH="${PWD}/.herdr-swarm/traces"
mkdir -p "$TRACE_DIR_PATH"
_ready_payload=$(jq -cn \
  --arg mode "$MODE" --arg slug "$PROJECT_SLUG" --arg repo "${REPO:-none}" \
  --argjson seats "$(jq '.seats | length' "${PWD}/.herdr-swarm/seats.json" 2>/dev/null || echo 0)" \
  '{action:"swarm_ready", mode:$mode, slug:$slug, repo:$repo, seats:$seats,
    summary:("swarm seated+verified (mode=" + $mode + ", seats=" + ($seats|tostring) + ")")}')
python3 "$LIB_DIR/telemetry.py" log "$SESSION_ID" swarm.lifecycle "$LOOPER_AGENT" - "$_ready_payload" \
  --trace-dir "$TRACE_DIR_PATH" >/dev/null 2>&1 || true
good "Telemetry session: ${SESSION_ID} → ${TRACE_DIR_PATH}"

# Start Kultivait Proxy in Ops pane if not already active
if ! curl -sf --max-time 2 http://localhost:4114/openapi.json >/dev/null 2>&1; then
  step "Starting Kultivait routing proxy on :4114..."
  herdr pane run "$SRV_PANE" "uv run kultivait serve" >/dev/null 2>&1 || true
fi

# ──────────────────────────────────────────────────────────────────────────
# Kickoff Execution
# ──────────────────────────────────────────────────────────────────────────

printf '\n%s▸ Dispatching Kickoff%s\n' "$BOLD" "$RESET"

case "$MODE" in
  w)
    step "Focusing arch for Wayfinder Chartering pass..."
    herdr agent focus "$ARCH_AGENT" >/dev/null 2>&1 || true
    herdr agent prompt "$ARCH_AGENT" "MILESTONE CHARTER: Chart milestone map for '${MILESTONE}' on repo ${REPO}. Follow your seat brief." >/dev/null 2>&1 || true
    good "Arch is ready for your input in the Herd tab"
    ;;
  b)
    step "Focusing arch for Brainstorming & PRD breakdown..."
    herdr agent focus "$ARCH_AGENT" >/dev/null 2>&1 || true
    herdr agent prompt "$ARCH_AGENT" "BRAINSTORM: Direction -> Design -> PRD -> Tickets for '${MILESTONE}'. Follow your seat brief." >/dev/null 2>&1 || true
    good "Arch is ready for brainstorming in the Herd tab"
    ;;
  r)
    step "Kicking Looper on Map #${MAP_NUM}..."
    herdr agent prompt "$LOOPER_AGENT" "KICKOFF: Work Wayfinder Map #${MAP_NUM} on ${REPO} per your seat brief — drain the frontier in map order until closed, then run milestone closeout and report." >/dev/null 2>&1 || true
    herdr agent focus "$LOOPER_AGENT" >/dev/null 2>&1 || true
    good "Looper is active on Map #${MAP_NUM}"
    ;;
  a)
    step "Kicking Looper in autonomous queue mode..."
    herdr agent prompt "$LOOPER_AGENT" "KICKOFF: Autonomous queue mode on ${REPO} — pull open unblocked tickets in order, execute through arch/docs/gh, verify with '${TEST_CMD}', and report when queue is empty." >/dev/null 2>&1 || true
    herdr agent focus "$LOOPER_AGENT" >/dev/null 2>&1 || true
    good "Looper is active in autonomous mode"
    ;;
  s)
    good "Swarm is seated and idle. Ready for manual prompts."
    ;;
esac

# ──────────────────────────────────────────────────────────────────────────
# Completion
# ──────────────────────────────────────────────────────────────────────────

printf '\n%s%s✓ Swarm Setup Complete%s\n' "$BOLD" "$GREEN" "$RESET"
if (( EXTERNAL )); then
  say "Attach to the swarm session via:"
  printf '  %s%sherdr%s\n\n' "$BOLD" "$CYAN" "$RESET"
else
  say "Swarm active in tabs: 'herd' (pm, arch, looper) & 'ops' (docs, gh, serve, log)"
fi
say "Live telemetry: Ops tab 'telemetry-stream' pane"
say "Telemetry traces: ${PWD}/.herdr-swarm/traces/"
