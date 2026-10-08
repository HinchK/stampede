#!/usr/bin/env bash
# lib/lifecycle.sh — Swarm Lifecycle Management: Status & Teardown Protocol
# Prototype for Tickets: [Workspace Lifecycle and Clean Teardown Protocol],
#                       [Lifecycle Safe Teardown and Target Disambiguation (D1 fix)]
#
# Provides:
#   swarm_status:         Inspects active workspace, seated agents, profile, test health
#   swarm_down:           Gracefully retires recorded seat panes / agents, closes
#                         workspace (unless --keep-workspace), preserving audit logs
#   find_workspace_by_cwd: Strict cwd-identity workspace resolution (D1 fix)
#   review_loop_*:        Autonomous reviewer-loop state machine (REV-3)
#
# Review loop contract (REV-3):
#   State lives in <state_dir>/reviews.json; the functions below own the
#   policy and the durable state, and emit MACHINE DIRECTIVES on stdout for
#   the caller (supervisor / launcher) to execute:
#     ENQUEUE <ticket> <seat> <sha>            — arbiter-enqueue the gated sha
#     DISPATCH_REVIEWER <seat> <ticket> <sha> <round> <max>
#                                              — prompt the reviewer seat
#     DISPATCH_CRITIQUE <seat> <ticket> <round> <max> <findings-path>
#                                              — prompt the implementer seat
#     ALERT_BLOCKED <ticket> <sha> <round> <max>
#                                              — fail closed: human alert, no enqueue
#     ALERT_INVALID <ticket> <reason>          — corrupt/unknown input, fail closed
#   Effects (herdr prompts, arbiter runs, human escalation) belong to the
#   caller; this file never shells out. Enabling precedence: override file
#   (<state_dir>/review-loop.override, written by the launcher's
#   --no-review-loop) > $CONFIG_REVIEW_LOOP (config binding, REV-1) > 0.
#
# D1 fix invariants:
#   - find_workspace_by_cwd ONLY resolves workspaces whose pane cwd is exactly
#     the requested directory (physical paths). $HERDR_WORKSPACE_ID is returned
#     only when the caller workspace's panes actually live in the target dir.
#     No-match prints nothing and returns 0 (safe under `set -e` sourcing).
#   - swarm_down closes only panes recorded in .herdr-swarm/seats.json
#     (schema: {"workspace_id": "wX", "seats": [{"name": ..., "kind": ...,
#     "pane": "wX:pN"}]}); if the ledger is absent or stale (workspace_id
#     mismatch), it falls back to closing agent panes registered in the
#     matched workspace. Unrelated operator panes are never touched.
#   - swarm_down asks for interactive confirmation before closing anything
#     unless -y/--yes is passed; non-interactive without --yes aborts closed.

set -euo pipefail

# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$(dirname "${BASH_SOURCE[0]}")/worktree.sh"

# Terminal colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold 2>/dev/null || true); DIM=$(tput dim 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true); YELLOW=$(tput setaf 3 2>/dev/null || true); RED=$(tput setaf 1 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

# True if any pane of WS_ID has cwd exactly equal to ABS_TARGET (physical path).
_ws_matches_cwd() { # WS_ID ABS_TARGET
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -e --arg d "$2" '[.result.panes[]? | select(.cwd == $d)] | length > 0' >/dev/null 2>&1
}

# Resolve the workspace tied to a directory by strict cwd identity.
# Prints the workspace id, or nothing when no workspace matches. Always
# returns 0 (callers test output emptiness; safe under set -e sourcing).
find_workspace_by_cwd() {
  local target_dir="${1:-$PWD}"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || return 0

  # 1. Caller's own workspace — ONLY if its panes actually live in the target
  if [[ -n "${HERDR_WORKSPACE_ID:-}" ]] && _ws_matches_cwd "$HERDR_WORKSPACE_ID" "$abs_target"; then
    echo "$HERDR_WORKSPACE_ID"
    return 0
  fi

  # 2. Any workspace whose pane cwd is exactly the target (never label-based)
  local ws_list cand
  ws_list=$(herdr workspace list 2>/dev/null || true)
  while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    [[ "$cand" == "${HERDR_WORKSPACE_ID:-}" ]] && continue
    if _ws_matches_cwd "$cand" "$abs_target"; then
      echo "$cand"
      return 0
    fi
  done < <(jq -r '.result.workspaces[]?.workspace_id' <<<"$ws_list" 2>/dev/null)

  # 3. Fallback: a seated agent whose cwd is the target
  local ws_id
  ws_id=$(herdr agent list 2>/dev/null | jq -r --arg d "$abs_target" \
    '.result.agents[]? | select(.cwd == $d) | .workspace_id' | head -n1 || true)
  if [[ -n "$ws_id" ]]; then
    echo "$ws_id"
    return 0
  fi
  return 0
}

# Display detailed status of swarm for current directory
# ── Autonomous review loop state machine (REV-3) ───────────────────────────
# Pure state + policy: never prompts, never runs the arbiter, never touches
# git. Callers execute the directives these functions print on stdout.

_review_state_file() { # STATE_DIR
  printf '%s/reviews.json\n' "$1"
}

review_loop_init() { # [STATE_DIR=$PWD/.herdr-swarm] — idempotent
  local sd="${1:-$PWD/.herdr-swarm}"
  local f; f=$(_review_state_file "$sd")
  [[ -f "$f" ]] && return 0
  mkdir -p "$sd"
  printf '{"version":1,"reviews":{}}\n' > "$f"
}

# Effective loop enablement: override file > CONFIG_REVIEW_LOOP env > 0.
review_loop_enabled() { # [STATE_DIR]
  local sd="${1:-$PWD/.herdr-swarm}"
  if [[ -f "$sd/review-loop.override" ]]; then
    printf '%s\n' "$(head -n1 "$sd/review-loop.override" | tr -d '[:space:]')"
    return 0
  fi
  printf '%s\n' "${CONFIG_REVIEW_LOOP:-0}"
}

review_loop_max_rounds() { # [STATE_DIR]
  printf '%s\n' "${CONFIG_REVIEW_MAX_ROUNDS:-2}"
}

review_loop_findings_path() { # TICKET SHA [STATE_DIR] — absolute evidence path
  local sd="${3:-$PWD/.herdr-swarm}"
  printf '%s/reviews/%s-%s.md\n' "$sd" "$1" "$2"
}

_review_write() { # STATE_DIR JQ_FILTER [JQARGS...] — atomic temp+mv write
  local sd="$1" filt="$2"; shift 2
  local f tmp
  f=$(_review_state_file "$sd")
  tmp="${f}.tmp$$"
  # shellcheck disable=SC2016  # jq program, not shell
  if ! jq "$@" "$filt" "$f" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    printf 'review_loop: refusing to write corrupt state (%s)\n' "$f" >&2
    return 1
  fi
  mv "$tmp" "$f"
}

# Entry point after a supervisor Suite Gate went green on (ticket, seat, sha).
# REV-06: docs/maps-only commits fast-path past the reviewer round — the
# narrowed path set is deliberate (test files do NOT qualify: weakening a
# test is a real way to hide a defect under cover of "just tests"). Any
# classification failure — unresolvable sha, missing repo, empty diff —
# fails SAFE: the normal review path. Changed paths follow the repo's
# existing git diff convention (partition/arbiter use diff --name-only;
# diff-tree gives the same list without naming the parent).
_review_commit_is_docs_only() { # SHA → rc 0 = every changed path is doc-class
  local repo="${REPO_DIR:-$PWD}" paths p
  paths=$(git -C "$repo" diff-tree --no-commit-id --name-only -r "$1" 2>/dev/null) || return 1
  [[ -n "$paths" ]] || return 1
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    case "$p" in
      docs/*|maps/*|README.md|CHANGELOG.md|CONTEXT.md|STATE.md) ;;
      *) return 1 ;;
    esac
  done <<<"$paths"
  return 0
}

review_loop_on_gate_green() { # TICKET SEAT SHA [STATE_DIR]
  local ticket="$1" seat="$2" sha="$3" sd="${4:-$PWD/.herdr-swarm}"
  local f; f=$(_review_state_file "$sd")

  if [[ "$(review_loop_enabled "$sd")" != "1" ]]; then
    printf 'ENQUEUE %s %s %s\n' "$ticket" "$seat" "$sha"
    return 0
  fi

  # REV-06 fast-path: an all-docs commit enqueues directly, with a durable
  # state record + log marker so it is visibly distinguishable from the
  # loop-off ENQUEUE when reading traces/state later.
  if _review_commit_is_docs_only "$sha"; then
    printf 'ENQUEUE %s %s %s\n' "$ticket" "$seat" "$sha"
    review_loop_init "$sd"
    # shellcheck disable=SC2016  # jq program, not shell
    _review_write "$sd" \
      '.reviews[$t] = {seat:$s, sha:$h, state:"docs_fast_path", updated:$now, history:((.reviews[$t].history // []) + [{event:"docs_fast_path", sha:$h, at:$now}])}' \
      --arg t "$ticket" --arg s "$seat" --arg h "$sha" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'review loop: #%s @ %s is docs/maps-only — fast-path ENQUEUE, no review round\n' "$ticket" "$sha" >&2
    return 0
  fi

  review_loop_init "$sd"
  local round max state
  max=$(review_loop_max_rounds "$sd")
  state=$(jq -r --arg t "$ticket" '.reviews[$t].state // "none"' "$f")
  if [[ "$state" == "critique_dispatched" ]]; then
    round=$(jq -r --arg t "$ticket" '.reviews[$t].round' "$f")   # carry the incremented round
  else
    round=1                                                       # fresh (or terminal-state redo at a new sha)
  fi
  # shellcheck disable=SC2016  # jq program, not shell
  _review_write "$sd" \
    '.reviews[$t] = {seat:$s, sha:$h, round:($r|tonumber), state:"awaiting_review", max_rounds:($m|tonumber), updated:$now, history:((.reviews[$t].history // []) + [{event:"gate_green", sha:$h, round:($r|tonumber), at:$now}])}' \
    --arg t "$ticket" --arg s "$seat" --arg h "$sha" --arg r "$round" --arg m "$max" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local reviewer_seat="${SEAT_NAME_reviewer:-reviewer}"
  printf 'DISPATCH_REVIEWER %s %s %s %s %s\n' "$reviewer_seat" "$ticket" "$sha" "$round" "$max"
}

# Fail-closed helper: transition an existing review to review_blocked (when
# state exists) and emit the invalid-input alert. Always returns 1.
_review_fail_closed() { # TICKET STATE_DIR REASON
  local ticket="$1" sd="$2" reason="$3"
  local f; f=$(_review_state_file "$sd")
  if [[ -f "$f" ]] && jq -e --arg t "$ticket" '.reviews[$t] != null' "$f" >/dev/null 2>&1; then
    # shellcheck disable=SC2016  # jq program, not shell
    _review_write "$sd" \
      '.reviews[$t].state = "review_blocked" | .reviews[$t].updated = $now | .reviews[$t].history = ((.reviews[$t].history // []) + [{event:"fail_closed", reason:$reason, at:$now}])' \
      --arg t "$ticket" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg reason "$reason" || true
  fi
  printf 'ALERT_INVALID %s %s\n' "$ticket" "$reason"
  return 1
}

# Entry point for a reviewer verdict anchor: REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>.
review_loop_on_review_verdict() { # TICKET SHA VERDICT [STATE_DIR]
  local ticket="$1" sha="$2" verdict="$3" sd="${4:-$PWD/.herdr-swarm}"
  local f; f=$(_review_state_file "$sd")

  [[ -f "$f" ]] || { printf 'ALERT_INVALID %s no-review-state\n' "$ticket"; return 1; }

  local state cur_sha seat round max
  state=$(jq -r --arg t "$ticket" '.reviews[$t].state // "none"' "$f")
  cur_sha=$(jq -r --arg t "$ticket" '.reviews[$t].sha // ""' "$f")
  seat=$(jq -r --arg t "$ticket" '.reviews[$t].seat // ""' "$f")
  round=$(jq -r --arg t "$ticket" '.reviews[$t].round // 0' "$f")
  max=$(jq -r --arg t "$ticket" '.reviews[$t].max_rounds // 0' "$f")

  case "$verdict" in
    PASS|BLOCK) ;;
    *) _review_fail_closed "$ticket" "$sd" "unknown-verdict:${verdict:-empty}"; return 1 ;;
  esac
  [[ "$state" != "none" ]] || { _review_fail_closed "$ticket" "$sd" "no-active-review"; return 1; }
  [[ "$sha" == "$cur_sha" ]] || { _review_fail_closed "$ticket" "$sd" "sha-mismatch:expected:${cur_sha:-none}"; return 1; }

  if [[ "$verdict" == "PASS" ]]; then
    # shellcheck disable=SC2016  # jq program, not shell
    _review_write "$sd" \
      '.reviews[$t].state = "review_passed" | .reviews[$t].updated = $now | .reviews[$t].history += [{event:"verdict", verdict:"PASS", sha:$h, at:$now}]' \
      --arg t "$ticket" --arg h "$sha" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'ENQUEUE %s %s %s\n' "$ticket" "$seat" "$sha"
    return 0
  fi

  # BLOCK — idempotent re-delivery while critique_dispatched (no double increment)
  if [[ "$state" == "critique_dispatched" ]]; then
    printf 'DISPATCH_CRITIQUE %s %s %s %s %s\n' "$seat" "$ticket" "$round" "$max" "$(review_loop_findings_path "$ticket" "$sha" "$sd")"
    return 0
  fi

  if (( round < max )); then
    local next=$(( round + 1 ))
    # shellcheck disable=SC2016  # jq program, not shell
    _review_write "$sd" \
      '.reviews[$t].round = ($r|tonumber) | .reviews[$t].state = "critique_dispatched" | .reviews[$t].updated = $now | .reviews[$t].history += [{event:"verdict", verdict:"BLOCK", sha:$h, round:($r|tonumber), at:$now}]' \
      --arg t "$ticket" --arg h "$sha" --arg r "$next" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'DISPATCH_CRITIQUE %s %s %s %s %s\n' "$seat" "$ticket" "$next" "$max" "$(review_loop_findings_path "$ticket" "$sha" "$sd")"
  else
    # shellcheck disable=SC2016  # jq program, not shell
    _review_write "$sd" \
      '.reviews[$t].state = "review_blocked" | .reviews[$t].updated = $now | .reviews[$t].history += [{event:"verdict", verdict:"BLOCK", sha:$h, round:($r|tonumber), budget_exhausted:true, at:$now}]' \
      --arg t "$ticket" --arg h "$sha" --arg r "$round" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'ALERT_BLOCKED %s %s %s %s\n' "$ticket" "$sha" "$round" "$max"
    return 0   # the loop worked as designed; the BLOCK is the answer, not an error
  fi
}

# Human-readable + greppable status. Safe on absent state.
review_loop_status() { # [STATE_DIR] [INDENT]
  local sd="${1:-$PWD/.herdr-swarm}" ind="${2:-}"
  local f; f=$(_review_state_file "$sd")
  local en max ovr=""
  en=$(review_loop_enabled "$sd")
  max=$(review_loop_max_rounds "$sd")
  if [[ -f "$sd/review-loop.override" ]]; then
    ovr=" [override: $(head -n1 "$sd/review-loop.override" | tr -d '[:space:]')]"
  fi
  if [[ "$en" == "1" ]]; then
    printf '%s%sReview Loop:%s enabled (max_rounds %s)%s\n' "$ind" "${BOLD:-}" "${RESET:-}" "$max" "$ovr"
  else
    printf '%s%sReview Loop:%s disabled%s\n' "$ind" "${BOLD:-}" "${RESET:-}" "$ovr"
  fi
  if [[ -f "$f" ]] && jq -e '.reviews | length > 0' "$f" >/dev/null 2>&1; then
    printf '%s  %-16s %-9s %-18s %s\n' "$ind" "TICKET" "ROUND" "STATE" "SHA"
    jq -r '.reviews | to_entries[] | "\(.key) \(.value.round)/\(.value.max_rounds) \(.value.state) \(.value.sha[0:10])"' "$f" \
      | while IFS= read -r line; do
          [[ -n "$line" ]] && printf '%s  %s\n' "$ind" "$line"
        done
  fi
  return 0
}

swarm_status() {
  local target_dir="${1:-$PWD}"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || return 1

  printf '\n%s%s⚡ Herdr Swarm Status — %s%s\n' "$BOLD" "$CYAN" "$(basename "$abs_target")" "$RESET"
  printf '%sDirectory: %s%s\n\n' "$DIM" "$abs_target" "$RESET"

  # 1. Daemon Check
  if ! herdr workspace list >/dev/null 2>&1; then
    printf '  %s✖ Herdr daemon is not responding.%s\n\n' "$RED" "$RESET"
    return 1
  fi

  # 2. Workspace Status
  local ws_id
  ws_id=$(find_workspace_by_cwd "$abs_target")
  if [[ -z "$ws_id" ]]; then
    printf '  %s• Workspace:%s %s[Inactive — No active workspace found for this path]%s\n' "$DIM" "$RESET" "$YELLOW" "$RESET"
    printf '    Launch with: %s./herdr-loop-swarm.sh%s\n\n' "$BOLD" "$RESET"
    return 0
  fi
  printf '  %s✓ Workspace:%s %s (%s)\n' "$GREEN" "$RESET" "$(basename "$abs_target")" "$ws_id"

  # 3. Profile Information
  local env_file="${abs_target}/.herdr-swarm/profile.env"
  if [[ -f "$env_file" ]]; then
    printf '  %s✓ Profile:%s\n' "$GREEN" "$RESET"
    printf '      Repo:      %s\n' "$(grep -E '^REPO=' "$env_file" | cut -d'=' -f2- || echo "none")"
    printf '      Test Cmd:  %s\n' "$(grep -E '^TEST_CMD=' "$env_file" | cut -d'=' -f2- || echo "none")"
    printf '      Ecosystem: %s\n' "$(grep -E '^ECOSYSTEM=' "$env_file" | cut -d'=' -f2- || echo "generic")"
  else
    printf '  %s• Profile:%s uninitialized (.herdr-swarm/profile.env)\n' "$DIM" "$RESET"
  fi

  # 4. Seated Agents
  printf '\n%s  Seated Agents in Workspace (%s):%s\n' "$BOLD" "$ws_id" "$RESET"
  local agents_json
  agents_json=$(herdr agent list 2>/dev/null || echo '{"result":{"agents":[]}}')

  local count
  count=$(jq -r --arg ws "$ws_id" '[.result.agents[]? | select(.workspace_id == $ws)] | length' <<<"$agents_json" 2>/dev/null || echo 0)

  if (( count == 0 )); then
    printf '    %s(No agents currently registered in this workspace)%s\n' "$DIM" "$RESET"
  else
    printf '    %-18s %-10s %-12s %-10s\n' "AGENT NAME" "KIND" "STATUS" "PANE ID"
    printf '    %-18s %-10s %-12s %-10s\n' "------------------" "----------" "------------" "----------"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local aname akind astat apane
      read -r aname akind astat apane <<<"$line"
      [[ "$aname" == "null" || -z "$aname" ]] && aname="(unnamed)"
      local stat_color="$GREEN"
      [[ "$astat" == "working" ]] && stat_color="$CYAN"
      [[ "$astat" == "blocked" ]] && stat_color="$RED"
      printf '    %-18s %-10s %s%-12s%s %-10s\n' "$aname" "$akind" "$stat_color" "$astat" "$RESET" "$apane"
    done < <(jq -r --arg ws "$ws_id" '.result.agents[]? | select(.workspace_id == $ws) | "\(.name) \(.agent) \(.agent_status) \(.pane_id)"' <<<"$agents_json")
  fi

  # 5. Telemetry & Verdicts
  local trace_dir="${abs_target}/.herdr-swarm/traces"
  if [[ -d "$trace_dir" ]]; then
    local latest_trace
    latest_trace=$(find "$trace_dir" -maxdepth 1 -name "*.jsonl" 2>/dev/null | sort | tail -n1 || true)
    if [[ -n "$latest_trace" ]]; then
      printf '\n%s  Recent Activity (%s):%s\n' "$BOLD" "$(basename "$latest_trace")" "$RESET"
      tail -n 3 "$latest_trace" | while IFS= read -r ev; do
        [[ -n "$ev" ]] && printf '    %s•%s %s\n' "$DIM" "$RESET" "$ev"
      done
    fi
  fi
  # 6. Review Loop (REV-3): enabled/disabled, budget, active reviews
  review_loop_status "${abs_target}/.herdr-swarm" "  "

  printf '\n'
}

# Interactive yes/no gate. Prompts on stderr (or /dev/tty when stdin is not a
# terminal); refuses (returns 1) when no usable terminal exists — scripts must
# pass --yes explicitly.
lifecycle_confirm() { # PROMPT
  local reply="" prompt="$1"
  if [[ -t 0 ]]; then
    printf '  %s? %s%s [y/N] ' "$YELLOW" "$prompt" "$RESET" >&2
    read -r reply || return 1
  else
    exec 3</dev/tty 2>/dev/null || return 1
    printf '  %s? %s%s [y/N] ' "$YELLOW" "$prompt" "$RESET" >&3 2>/dev/null || true
    if ! read -r reply <&3; then
      exec 3<&- 2>/dev/null || true
      return 1
    fi
    exec 3<&- 2>/dev/null || true
  fi
  [[ "$reply" =~ ^[Yy] ]]
}

# Retire isolated worktrees listed in the seat ledger: unlock, then prune
# (prune itself checkpoints tracked edits and salvages untracked files;
# branches always survive). Only ledger-recorded paths under the swarm root
# are touched.
_swarm_retire_worktrees() { # ABS_TARGET ISOLATED_SEATS(tab-separated records)
  local abs_target="$1" records="$2"
  local wname wdir wbranch
  while IFS=$'\t' read -r wname wdir wbranch; do
    [[ -n "$wname" ]] || continue
    [[ -n "$wdir" && -d "$wdir" ]] || continue
    # Root checkout is inviolable; ledger dirs outside the swarm root are not ours
    [[ "$wdir" == "$abs_target" ]] && continue
    [[ "$wdir" == "${abs_target}/.herdr-swarm/worktrees/"* ]] || continue
    printf '  %s• Retiring isolated worktree %s (%s)...%s\n' "$DIM" "$wname" "$wbranch" "$RESET"
    git -C "$abs_target" worktree unlock "$wdir" >/dev/null 2>&1 || true
    # Derive the slug from the recorded branch (swarm/<slug>/<seat>)
    local slug="${wbranch#swarm/}"
    slug="${slug%/*}"
    worktree_prune "$wname" "${slug:-herd}" 0 "$abs_target" || \
      printf '  %s⚠ prune failed for %s (inspect manually)%s\n' "$YELLOW" "$wdir" "$RESET"
  done <<<"$records"
}

# Graceful Swarm Teardown.
# Closes only panes recorded in .herdr-swarm/seats.json (when the ledger is
# fresh for the matched workspace); otherwise closes agent panes registered in
# the matched workspace. Never touches panes of unrelated workspaces.
# Isolated worktrees from the ledger are unlocked + pruned (checkpoint and
# salvage inside; branches retained) unless --keep-workspace is set.
swarm_down() { # TARGET_DIR ASSUME_YES KEEP_WS
  local target_dir="$1" assume_yes="$2" keep_ws="$3"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || {
    printf '  %s✖ Cannot access target directory: %s%s\n' "$RED" "$target_dir" "$RESET"
    return 1
  }

  printf '\n%s▸ Swarm Teardown — %s%s\n' "$BOLD" "$(basename "$abs_target")" "$RESET"

  # Isolated worktree retirement (P2-H H3): ledger v2 seats with
  # isolated == true get unlocked + pruned (checkpoint/salvage inside).
  # Runs regardless of workspace state so locked trees never leak; skipped
  # under --keep-workspace (retention semantics keep the whole session).
  local seats_file="${abs_target}/.herdr-swarm/seats.json"
  local isolated_seats=""
  if [[ -f "$seats_file" ]] && (( ! keep_ws )); then
    isolated_seats=$(jq -r '.seats[]? | select(.isolated == true)
      | "\(.name)\t\(.worktree_dir // empty)\t\(.branch // empty)"' "$seats_file" 2>/dev/null || true)
  fi

  local ws_id
  ws_id=$(find_workspace_by_cwd "$abs_target")
  if [[ -z "$ws_id" ]]; then
    if [[ -n "$isolated_seats" ]]; then
      printf '  %s• No active workspace; retiring isolated worktrees only%s\n' "$DIM" "$RESET"
      _swarm_retire_worktrees "$abs_target" "$isolated_seats"
    fi
    rm -rf "${abs_target}/.herdr-swarm/channel"
    printf '  %s✓ No active workspace found for %s. Already clean.%s\n\n' "$GREEN" "$abs_target" "$RESET"
    return 0
  fi

  # Build the retirement plan: recorded seats first, live registry as fallback
  local panes="" pane_source=""
  if [[ -f "$seats_file" ]] \
     && [[ "$(jq -r '.workspace_id // empty' "$seats_file" 2>/dev/null)" == "$ws_id" ]]; then
    panes=$(jq -r '.seats[]?.pane // empty' "$seats_file" 2>/dev/null | sort -u)
    pane_source="seats.json ledger"
  else
    [[ -f "$seats_file" ]] && pane_source="seats.json STALE (workspace mismatch) — using live registry"
    panes=$(herdr agent list 2>/dev/null | jq -r --arg ws "$ws_id" \
      '.result.agents[]? | select(.workspace_id == $ws) | .pane_id' | sort -u)
    [[ -n "$pane_source" ]] || pane_source="live agent registry"
  fi

  # Present the plan
  printf '  %s• Workspace:%s %s\n' "$DIM" "$RESET" "$ws_id"
  printf '  %s• Pane source:%s %s\n' "$DIM" "$RESET" "$pane_source"
  if [[ -n "$panes" ]]; then
    printf '  %s• Panes to close:%s\n' "$DIM" "$RESET"
    local pane
    while IFS= read -r pane; do
      [[ -n "$pane" ]] && printf '      - %s\n' "$pane"
    done <<<"$panes"
  else
    printf '  %s• Panes to close:%s (none recorded)\n' "$DIM" "$RESET"
  fi
  if [[ -n "$isolated_seats" ]]; then
    printf '  %s• Worktrees to retire (unlock + prune, branches kept):%s\n' "$DIM" "$RESET"
    while IFS=$'\t' read -r wname wdir _wb; do
      [[ -n "$wname" ]] && printf '      - %s\n' "$wdir"
    done <<<"$isolated_seats"
  fi
  if (( keep_ws )); then
    printf '  %s• Workspace %s will be RETAINED (--keep-workspace)%s\n' "$DIM" "$ws_id" "$RESET"
  else
    printf '  %s• Workspace %s will be CLOSED%s\n' "$YELLOW" "$ws_id" "$RESET"
  fi

  # Confirmation gate (D1: never close anything unattended without --yes)
  if (( ! assume_yes )); then
    if ! lifecycle_confirm "Tear down this swarm?"; then
      printf '  %s✖ Aborted — nothing was closed.%s\n\n' "$RED" "$RESET"
      return 1
    fi
  fi

  # Execute: retire agents by closing their panes
  if [[ -n "$panes" ]]; then
    local pane
    while IFS= read -r pane; do
      [[ -n "$pane" ]] || continue
      printf '  %s• Closing pane %s...%s\n' "$DIM" "$pane" "$RESET"
      herdr pane close "$pane" >/dev/null 2>&1 || true
    done <<<"$panes"
  fi

  # Execute: retire isolated worktrees (checkpoint + salvage + prune)
  [[ -n "$isolated_seats" ]] && _swarm_retire_worktrees "$abs_target" "$isolated_seats"

  # Close the workspace itself unless retention requested
  if (( keep_ws )); then
    printf '  %s✓ Seat panes closed. Workspace %s retained (--keep-workspace).%s\n' "$GREEN" "$ws_id" "$RESET"
  else
    printf '  %s• Disposing workspace %s...%s\n' "$DIM" "$ws_id" "$RESET"
    herdr workspace close "$ws_id" >/dev/null 2>&1 || true
    printf '  %s✓ Workspace %s disposed cleanly.%s\n' "$GREEN" "$ws_id" "$RESET"
  fi

  # Clean transient channel files (profile.env, seats.json, traces, verdicts preserved)
  rm -rf "${abs_target}/.herdr-swarm/channel"
  printf '  %s✓ Transient channel files purged (profile, seats, traces preserved).%s\n\n' "$GREEN" "$RESET"
}

# seat_wait_ready NAME PANE TIMEOUT_MS — one single-target readiness wait
# (HERDR-2 / ADR 0017 D1). With `pane wait-output` available, block once on
# the brief-delivery anchor in the seat's pane (the tightened brief-ready
# signal the audit's S18/S23 rows asked for); without it, the pre-HERDR-2
# agent-lifecycle wait, unchanged. On success SEAT_WAIT_MODE names the signal
# that passed ("brief-ready" | "interactive-ready") for the caller's label.
seat_wait_ready() { # NAME PANE TIMEOUT_MS
  local name="$1" pane="${2:-}" timeout_ms="${3:-30000}"
  if [[ -n "$pane" ]] && herdr_has_wait_output; then
    SEAT_WAIT_MODE=brief-ready
    herdr pane wait-output "$pane" --regex "$BRIEF_ACK_REGEX" --timeout "$timeout_ms" >/dev/null 2>&1
    return
  fi
  SEAT_WAIT_MODE=interactive-ready
  herdr agent wait "$name" --until idle --until "done" --until working --timeout "$timeout_ms" >/dev/null 2>&1
}

# Post-seating readiness gate. Every seat must exist and have settled into a
# stable post-boot state. NOTE: "ready" includes WORKING — an agent that is
# executing has demonstrably booted and consumed its standing brief; a strict
# idle/done-only wait cannot pass against a live, busy swarm (verified
# empirically). Blocked, unknown, or never-booted seats time out and fail.
swarm_verify_seats() { # [TARGET_DIR] [TIMEOUT_MS]
  local target_dir="${1:-$PWD}"
  local timeout_ms="${2:-30000}"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd -P) || {
    printf '  %s✖ cannot access target directory: %s%s\n' "$RED" "$target_dir" "$RESET"
    return 1
  }

  local ws_id
  ws_id=$(find_workspace_by_cwd "$abs_target")
  if [[ -z "$ws_id" ]]; then
    printf '  %s✖ no active workspace for %s%s\n' "$RED" "$abs_target" "$RESET"
    return 1
  fi

  # Seat roster: fresh seats.json ledger, else live agents in the workspace
  local seats_file="${abs_target}/.herdr-swarm/seats.json"
  local seats_spec="" src_label
  if [[ -f "$seats_file" ]] && [[ "$(jq -r '.workspace_id // empty' "$seats_file" 2>/dev/null)" == "$ws_id" ]]; then
    seats_spec=$(jq -r '.seats[]? | "\(.name)\t\(.kind)\t\(.pane)"' "$seats_file" 2>/dev/null)
    src_label="seats.json ledger"
  else
    seats_spec=$(herdr agent list 2>/dev/null | jq -r --arg ws "$ws_id" \
      '.result.agents[]? | select(.workspace_id == $ws) | "\(.name)\t\(.agent)\t\(.pane_id)"')
    src_label="live agent registry"
  fi

  printf '%s▸ Seat Verification — %s (%s)%s\n' "$BOLD" "$ws_id" "$src_label" "$RESET"

  if [[ -z "$seats_spec" ]]; then
    printf '  %s✖ no seats recorded for this workspace%s\n' "$RED" "$RESET"
    return 1
  fi

  local failures=0 name kind pane
  while IFS=$'\t' read -r name kind pane; do
    [[ -n "$name" ]] || continue
    if ! herdr agent get "$name" >/dev/null 2>&1; then
      printf '  %s✖ %s: agent not registered%s\n' "$RED" "$name" "$RESET"
      failures=1
      continue
    fi
    if seat_wait_ready "$name" "$pane" "$timeout_ms"; then
      printf '  %s✓ %s (%s in %s): %s%s\n' "$GREEN" "$name" "$kind" "$pane" "$SEAT_WAIT_MODE" "$RESET"
    else
      printf '  %s✖ %s: not ready within %sms%s\n' "$RED" "$name" "$timeout_ms" "$RESET"
      failures=1
    fi
  done <<<"$seats_spec"

  return "$failures"
}

# CLI dispatcher
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-status}"
  shift 2>/dev/null || true
  dir="$PWD"
  assume=0
  keep=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)          assume=1 ;;
      --keep-workspace)  keep=1 ;;
      -h|--help)
        cat <<EOF
Usage: $(basename "$0") [status [dir] | down [dir] [-y|--yes] [--keep-workspace]]
  status   Show swarm status for a directory (default: \$PWD)
  down     Tear down the swarm tied to a directory (default: \$PWD)
             -y, --yes         skip confirmation (required when non-interactive)
             --keep-workspace  close seat panes only, retain the workspace
EOF
        exit 0 ;;
      -*) printf 'unknown flag: %s (try --help)\n' "$1" >&2; exit 2 ;;
      *)  dir="$1" ;;
    esac
    shift
  done
  case "$cmd" in
    status) swarm_status "$dir" ;;
    down)   swarm_down "$dir" "$assume" "$keep" ;;
    *)      printf 'unknown command: %s (try --help)\n' "$cmd" >&2; exit 1 ;;
  esac
fi
