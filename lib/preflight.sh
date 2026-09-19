#!/usr/bin/env bash
# lib/preflight.sh — Preflight Dependency & Daemon Verification
# Prototype for Ticket: T-008 (Preflight Dependency and Daemon Verification)
#
# Validates, before any workspace initialization or seating:
#   - Herdr daemon responsiveness (herdr workspace list, with retry)
#   - Core binaries: jq, git, python3 (with tomllib / >= 3.11)
#   - GitHub CLI presence and authentication (fail-closed)
#   - Agent CLIs: agy, claude, opencode (advisory report)
#   - Git work-tree state (advisory)
#
# Usage (standalone):
#   ./lib/preflight.sh [--quiet] [--json]
#     --quiet   suppress text output; exit code only
#     --json    machine-readable JSON report (requires jq; falls back to text
#               remediation if jq itself is missing)
#
# Sourced usage:
#   source lib/preflight.sh
#   preflight_run            # populates PF_* accumulators
#   preflight_report_text    # human output
#   preflight_report_json    # JSON output
#   preflight_exit_code      # 0 if no errors, 1 otherwise
#
# Exit: 0 when all required checks pass; 1 with remediation hints otherwise.

set -euo pipefail

# Terminal colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true); YELLOW=$(tput setaf 3 2>/dev/null || true); RED=$(tput setaf 1 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)
else
  BOLD=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

# ── Accumulators (newline-delimited scalars; bash-3.2 safe) ────────────────
PF_RESULTS=""      # "name|status|detail" per check; status ∈ ok|warn|error
PF_REMEDIATION=""  # remediation lines (errors only)
PF_COUNT_OK=0
PF_COUNT_WARN=0
PF_COUNT_ERR=0

pf_record() { # NAME STATUS DETAIL [REMEDIATION]
  local name="$1" st="$2" detail="$3" fix="${4:-}"
  PF_RESULTS+="${name}|${st}|${detail}"$'\n'
  case "$st" in
    ok)   PF_COUNT_OK=$((PF_COUNT_OK + 1)) ;;
    warn) PF_COUNT_WARN=$((PF_COUNT_WARN + 1)) ;;
    error)
      PF_COUNT_ERR=$((PF_COUNT_ERR + 1))
      [[ -n "$fix" ]] && PF_REMEDIATION+="${fix}"$'\n'
      ;;
  esac
}

# ── Individual checks ──────────────────────────────────────────────────────

# Herdr daemon: binary present AND 'workspace list' answers. Retry covers a
# daemon that was just launched and is still binding its socket.
pf_check_herdr() {
  if ! command -v herdr >/dev/null 2>&1; then
    pf_record "herdr-daemon" "error" "herdr binary not on PATH" \
      "install herdr: curl -fsSL https://herdr.dev/install.sh | sh"
    return 0
  fi
  local attempt
  for attempt in 1 2 3; do
    if herdr workspace list >/dev/null 2>&1; then
      pf_record "herdr-daemon" "ok" "daemon responsive (attempt ${attempt})"
      return 0
    fi
    [[ "$attempt" -lt 3 ]] && sleep 1
  done
  pf_record "herdr-daemon" "error" "herdr installed but daemon not answering (tried 3x)" \
      "start the daemon: herdr server (background) or open the herdr app"
}

pf_check_bin() { # LABEL CMD REMEDIATION
  local label="$1" cmd="$2" fix="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    pf_record "bin-${cmd}" "ok" "found: $(command -v "$cmd")"
  else
    pf_record "bin-${cmd}" "error" "${label} binary not on PATH" "$fix"
  fi
}

# python3 with tomllib (capability probe, not version parsing)
pf_check_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    pf_record "python3-tomllib" "error" "python3 not on PATH" \
      "install python >= 3.11 (brew install python@3.12) or use uv"
    return 0
  fi
  local ver
  if ver=$(python3 -c 'import tomllib, sys; print(sys.version.split()[0])' 2>/dev/null); then
    pf_record "python3-tomllib" "ok" "python3 ${ver} with tomllib"
  else
    pf_record "python3-tomllib" "error" "python3 present but tomllib unavailable (needs >= 3.11)" \
      "install python >= 3.11 (brew install python@3.12) or use uv"
  fi
}

# GitHub CLI + auth — fail-closed: agy-gh seat and repo targeting depend on it.
pf_check_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    pf_record "gh-auth" "error" "gh CLI not on PATH" \
      "install: brew install gh  then: gh auth login"
    return 0
  fi
  if gh auth status >/dev/null 2>&1; then
    local acct
    acct=$(gh auth status 2>&1 | sed -nE 's/.*account ([^ ]+) \(keyring\).*/\1/p' | head -n1)
    pf_record "gh-auth" "ok" "authenticated${acct:+ as ${acct}}"
  else
    pf_record "gh-auth" "error" "gh installed but not authenticated (or token expired)" \
      "authenticate: gh auth login"
  fi
}

# Agent CLIs — advisory only; seating is config-driven and partial herds are
# possible, so absence is a warning, not a failure.
pf_check_agents() {
  local agent seat
  for agent in agy claude opencode; do
    case "$agent" in
      agy)      seat="looper, docs, gh, reviewer" ;;
      claude)   seat="pm" ;;
      opencode) seat="arch" ;;
      *)        seat="" ;;
    esac
    if command -v "$agent" >/dev/null 2>&1; then
      pf_record "agent-${agent}" "ok" "found (seats: ${seat})"
    else
      pf_record "agent-${agent}" "warn" "not on PATH — seats needing it: ${seat}"
    fi
  done
}

# Git work tree — advisory: launcher expects to run from a repo root.
pf_check_git_repo() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    pf_record "git-repo" "ok" "inside a git work tree"
  else
    pf_record "git-repo" "warn" "not inside a git repository — run from the project root"
  fi
}

# ── Orchestration ──────────────────────────────────────────────────────────
preflight_run() {
  PF_RESULTS=""; PF_REMEDIATION=""
  PF_COUNT_OK=0; PF_COUNT_WARN=0; PF_COUNT_ERR=0
  pf_check_herdr
  pf_check_bin "jq" jq "install: brew install jq"
  pf_check_bin "git" git "install: xcode-select --install"
  pf_check_python
  pf_check_gh
  pf_check_agents
  pf_check_git_repo
}

preflight_exit_code() {
  [[ "$PF_COUNT_ERR" -eq 0 ]]
}

# ── Reporting ──────────────────────────────────────────────────────────────
preflight_report_text() { # FD
  local fd="${1:-1}"
  local name st detail icon color
  while IFS='|' read -r name st detail; do
    [[ -n "$name" ]] || continue
    case "$st" in
      ok)    icon="✓"; color="$GREEN" ;;
      warn)  icon="⚠"; color="$YELLOW" ;;
      error) icon="✗"; color="$RED" ;;
      *)     icon="?"; color="" ;;
    esac
    printf '%s%s%s %-18s %s\n' "$color" "$icon" "$RESET" "$name" "$detail" >&"$fd"
  done <<<"$PF_RESULTS"

  if [[ -n "$PF_REMEDIATION" ]]; then
    printf '\n%s%sRemediation:%s\n' "$BOLD" "$RED" "$RESET" >&"$fd"
    local fix
    while IFS= read -r fix; do
      [[ -n "$fix" ]] && printf '  %s→%s %s\n' "$CYAN" "$RESET" "$fix" >&"$fd"
    done <<<"$PF_REMEDIATION"
  fi

  printf '\n%s%spreflight: %d ok, %d warn, %d error%s\n' "$BOLD" \
    "$GREEN" "$PF_COUNT_OK" "$PF_COUNT_WARN" "$PF_COUNT_ERR" "$RESET" >&"$fd"
}

preflight_report_json() { # FD — requires jq
  local fd="${1:-1}"
  if ! command -v jq >/dev/null 2>&1; then
    printf 'preflight: --json requested but jq is missing (it is a required dependency)\n' >&"$fd"
    return 1
  fi
  {
    printf '%s\n' "$PF_RESULTS" | awk -F'|' 'NF==3 {printf "%s\t%s\t%s\n", $1, $2, $3}'
    [[ -n "$PF_REMEDIATION" ]] || printf '\n'
  } | jq -R -s '
    split("\n") as $lines
    | ($lines | map(select(test("\\t"))) | map(split("\t"))) as $checks
    | ($lines | map(select((test("\\t") | not) and (length > 0)))) as $fixes
    | {
        ok: ('"$PF_COUNT_ERR"' == 0),
        summary: {ok: '"$PF_COUNT_OK"', warn: '"$PF_COUNT_WARN"', error: '"$PF_COUNT_ERR"'},
        checks: [$checks[] | {name: .[0], status: .[1], detail: .[2]}],
        remediation: $fixes
      }' >&"$fd"
}

# ── Standalone CLI ─────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  PF_QUIET=0
  PF_JSON=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -q|--quiet) PF_QUIET=1; shift ;;
      --json)     PF_JSON=1; shift ;;
      -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) printf 'unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
    esac
  done

  preflight_run

  if [[ "$PF_JSON" -eq 1 ]]; then
    if ! preflight_report_json; then
      preflight_report_text
    fi
  elif [[ "$PF_QUIET" -eq 0 ]]; then
    preflight_report_text
  fi

  preflight_exit_code || {
    [[ "$PF_QUIET" -eq 0 && "$PF_JSON" -eq 0 ]] && printf 'preflight FAILED\n' >&2
    exit 1
  }
  exit 0
fi
