#!/usr/bin/env bash
#
# herdr-loop-swarm: Next-Generation Multi-Agent Swarm Orchestrator
# Coordinates AGY (Gemini), Claude Code, OpenCode (GLM-5.3), and Kultivait Local Proxy
# Location: ~/fun/loop-bot-herd-agy/herdr-loop-swarm.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BRIEFS_DIR="$SCRIPT_DIR/briefs"
LIB_DIR="$SCRIPT_DIR/lib"
# shellcheck disable=SC2034  # reserved: wired by the TOML config binding integration
CONFIG_FILE="$SCRIPT_DIR/swarm.config.toml"
LOG_FILE="/tmp/herdr-process.log"
# shellcheck disable=SC2034  # reserved: wired by the telemetry integration
SESSION_ID="swarm-$(date +%Y%m%d-%H%M%S)"
ENV_FILE="${PWD}/.env"

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
Usage: $(basename "$0") [OPTIONS]

Autonomous Multi-Agent Orchestration Swarm (Herdr + AGY + Claude Code + OpenCode + Kultivait)

Options:
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

# Shared swarm libraries (profile detection + lifecycle workspace resolution)
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/profile.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$LIB_DIR/lifecycle.sh"

# ──────────────────────────────────────────────────────────────────────────
# Project Profile (fail-closed; see lib/profile.sh)
# ──────────────────────────────────────────────────────────────────────────

# Resolves REPO / TEST_CMD / ECOSYSTEM / DOCS_DIR before any workspace or pane
# is created. Prompts interactively when possible; aborts fail-closed when a
# required fact cannot be established (never defaults to a fake repo or a
# fake-green test command).
ensure_profile "$PWD" 1
good "Profile — repo: ${REPO:-none} · test: ${TEST_CMD} · ecosystem: ${ECOSYSTEM} · docs: ${DOCS_DIR}"

EXTERNAL=0
if [[ "${HERDR_ENV:-}" != 1 ]]; then
  EXTERNAL=1
  note "Running in external terminal mode"
  command -v herdr >/dev/null 2>&1 || {
    warn "herdr is not installed on PATH"
    say  "Install via: curl -fsSL https://herdr.dev/install.sh | sh"
    exit 1
  }
  if ! herdr workspace list >/dev/null 2>&1; then
    warn "Herdr daemon is not responding. Starting background server..."
    herdr server >/dev/null 2>&1 &
    sleep 2
  fi
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
# Layout Engine: 2-Tab Balanced Topology
# ──────────────────────────────────────────────────────────────────────────

printf '\n%s▸ Building Swarm Topology (Herd & Ops Tabs)%s\n' "$BOLD" "$RESET"

# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$LIB_DIR/layout_engine.sh"

read -r HerdTab HerdAnchor <<< "$(tab_by_label "$WS_ID" "herd")"
read -r OpsTab OpsAnchor   <<< "$(tab_by_label "$WS_ID" "ops")"

agent_alive() { herdr agent list 2>/dev/null | grep -q "\"$1\""; }

# Herd Tab Topology
agent_alive pm     || PM_PANE=$(split_pane "$HerdAnchor" right 0.5 "$PWD") || true
agent_alive arch   || ARCH_PANE=$(split_pane "${PM_PANE:-$HerdAnchor}" down 0.5 "$PWD") || true
agent_alive looper || LOOPER_PANE=$(split_pane "$HerdAnchor" down 0.5 "$PWD") || true

# Ops Tab Topology
agent_alive agy-docs || DOCS_PANE=$(split_pane "$OpsAnchor" right 0.5 "$PWD") || true
agent_alive agy-gh   || GH_PANE=$(split_pane "${DOCS_PANE:-$OpsAnchor}" down 0.5 "$PWD") || true
SRV_PANE=$(split_pane "$OpsAnchor" down 0.5 "$PWD") || true

# Stream Process Log to Ops Anchor
herdr pane rename "$OpsAnchor" "herdr-process.log" >/dev/null 2>&1 || true
herdr pane run "$OpsAnchor" "clear && tail -n 40 -f $LOG_FILE" >/dev/null 2>&1 || true

# Geometry Guard Floor
check_and_relocate_geometry "$WS_ID" "$HerdAnchor" "${PM_PANE:-}" "${ARCH_PANE:-}" "${LOOPER_PANE:-}"
check_and_relocate_geometry "$WS_ID" "$OpsAnchor" "${DOCS_PANE:-}" "${GH_PANE:-}"

good "Layout established: Herd Tab (${HerdTab}) & Ops Tab (${OpsTab})"

# ──────────────────────────────────────────────────────────────────────────
# Seating Agents & Standing Briefs
# ──────────────────────────────────────────────────────────────────────────

printf '\n%s▸ Seating Agents & Delivering Standing Briefs%s\n' "$BOLD" "$RESET"

seat_agent_safe() {
  local name="$1" pane="$2" kind="$3"
  shift 3
  if agent_alive "$name"; then
    note "Agent '${name}' is already seated"
    return 0
  fi
  step "Starting agent '${name}' (${kind})..."
  herdr agent start "$name" --kind "$kind" --pane "$pane" -- "$@" >/dev/null 2>&1 || {
    warn "Failed to seat agent '${name}' in pane ${pane}"
    return 1
  }
}

deliver_brief() {
  local name="$1" brief_file="$2"
  if [[ -f "$brief_file" ]]; then
    # Synchronize readiness before prompting to prevent dropped inputs during boot
    herdr agent wait "$name" --until idle --timeout 15000 >/dev/null 2>&1 || true
    herdr agent prompt "$name" "$(cat "$brief_file")" >/dev/null 2>&1 || true
    good "Brief delivered to '${name}' ($(basename "$brief_file"))"
  fi
}

# Seating
seat_agent_safe looper   "${LOOPER_PANE:-$HerdAnchor}" agy
seat_agent_safe arch     "${ARCH_PANE:-$HerdAnchor}"   opencode --model zai/glm-5.3
seat_agent_safe agy-docs "${DOCS_PANE:-$OpsAnchor}"    agy
seat_agent_safe agy-gh   "${GH_PANE:-$OpsAnchor}"      agy
seat_agent_safe pm       "${PM_PANE:-$HerdAnchor}"     claude

# Deliver Briefs
deliver_brief looper   "$BRIEFS_DIR/looper.md"
deliver_brief arch     "$BRIEFS_DIR/arch.md"
deliver_brief agy-docs "$BRIEFS_DIR/worker-docs.md"
deliver_brief agy-gh   "$BRIEFS_DIR/worker-gh.md"
deliver_brief pm       "$BRIEFS_DIR/overseer-pm.md"

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
    herdr agent focus arch >/dev/null 2>&1 || true
    herdr agent prompt arch "MILESTONE CHARTER: Chart milestone map for '${MILESTONE}' on repo ${REPO}. Follow your seat brief." >/dev/null 2>&1 || true
    good "Arch is ready for your input in the Herd tab"
    ;;
  b)
    step "Focusing arch for Brainstorming & PRD breakdown..."
    herdr agent focus arch >/dev/null 2>&1 || true
    herdr agent prompt arch "BRAINSTORM: Direction -> Design -> PRD -> Tickets for '${MILESTONE}'. Follow your seat brief." >/dev/null 2>&1 || true
    good "Arch is ready for brainstorming in the Herd tab"
    ;;
  r)
    step "Kicking Looper on Map #${MAP_NUM}..."
    herdr agent prompt looper "KICKOFF: Work Wayfinder Map #${MAP_NUM} on ${REPO} per your seat brief — drain the frontier in map order until closed, then run milestone closeout and report." >/dev/null 2>&1 || true
    herdr agent focus looper >/dev/null 2>&1 || true
    good "Looper is active on Map #${MAP_NUM}"
    ;;
  a)
    step "Kicking Looper in autonomous queue mode..."
    herdr agent prompt looper "KICKOFF: Autonomous queue mode on ${REPO} — pull open unblocked tickets in order, execute through arch/docs/gh, verify with '${TEST_CMD}', and report when queue is empty." >/dev/null 2>&1 || true
    herdr agent focus looper >/dev/null 2>&1 || true
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
say "Process log: tail -f /tmp/herdr-process.log"
say "Telemetry traces: ~/.herdr-loop-swarm/traces/"
