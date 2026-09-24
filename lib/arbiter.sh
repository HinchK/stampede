#!/usr/bin/env bash
# lib/arbiter.sh — Arbiter Branch Merge & Integration PR Engine
# Prototype for Ticket: P2-4 · Implements ADR 0006 §4.E + PM P2-4 spec:
# serialized CAS integration into swarm/<slug>/integration, combined-tree
# gating in a detached worktree, and human-supervised promotion.
#
# Safety rules (measured, PM spec §2):
#   - The arbiter NEVER writes seat branches and NEVER moves the checked-out
#     base branch; integration advances only via
#     `git update-ref <ref> <candidate> <expected-old>` (compare-and-swap).
#   - The gated sha is integrated, not the branch tip (the sha is what was
#     tested; later worker commits stay on the seat branch).
#   - The combined tree is suite-gated BEFORE the ref moves; RED leaves the
#     ref unmoved.
#   - Conflicts are aborted and recorded — resolved by the worker on its own
#     branch, never by the arbiter.
#
# Configuration (env):
#   REPO_DIR      target repository     (default $PWD)
#   STATE_DIR     swarm state directory (default <REPO_DIR>/.herdr-swarm)
#   PROJECT_SLUG  slug for refs         (default slugify basename REPO_DIR)
#   BASE_BRANCH   base branch           (default current branch / main)
#   TEST_CMD      suite command for integration gating
#
# Queue: ${STATE_DIR}/integration.jsonl
#   {ts, ticket, seat, sha, status: queued|integrated|conflict|
#    integration_red|retry|superseded|promoted, integration_before,
#    merge_sha, files, gate, promoted_to, pr_url}

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091  # dynamically resolved sibling lib
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck disable=SC1091  # tomllib-capable interpreter (DOG-1)
source "$(dirname "${BASH_SOURCE[0]}")/pyenv.sh"
resolve_python

ARBITER_TMP_SLEEP=0.2

_arb_cfg() {
  ARB_REPO="${REPO_DIR:-$PWD}"
  ARB_STATE="${STATE_DIR:-${ARB_REPO}/.herdr-swarm}"
  ARB_SLUG="${PROJECT_SLUG:-$(slugify "$(basename "$ARB_REPO")")}"
  ARB_BASE="${BASE_BRANCH:-$(git -C "$ARB_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'main')}"
  ARB_QUEUE="${ARB_STATE}/integration.jsonl"
  ARB_REF="refs/heads/swarm/${ARB_SLUG}/integration"
  ARB_WT="${ARB_REPO}/.herdr-swarm/worktrees/arbiter-${ARB_SLUG}"
}

_arb_cmd_runnable() {
  local cmd="${TEST_CMD:-}"
  [[ -n "$cmd" && "$cmd" != "none" && "$cmd" != "true" ]]
}

_arb_record() { # JSON (single line) — append to queue
  mkdir -p "$ARB_STATE"
  printf '%s\n' "$1" >> "$ARB_QUEUE"
}

# Rewrite the status (+extra fields) of the first queued record matching
# (ticket, sha). Atomic via tmp+mv; output stays JSONL (one record per line).
_arb_set_status() { # TICKET SHA STATUS [EXTRA_JQ]
  local t="$1" s="$2" st="$3" extra="${4:-}"
  # Ticket ids are STRINGS (repo vocabulary: frontmatter id like "P3-4-spec");
  # numeric ids still work — they just round-trip as strings now.
  local filter="if (.ticket == \$t and .sha == \$s and .status == \"queued\") then . + {status: \$st}"
  [[ -n "$extra" ]] && filter+=" + ($extra)"
  filter+=" else . end"
  jq -s --arg t "$t" --arg s "$s" --arg st "$st" "map($filter) | .[]" "$ARB_QUEUE" \
    > "${ARB_QUEUE}.tmp" && mv "${ARB_QUEUE}.tmp" "$ARB_QUEUE"
}

_arb_telemetry() { # EVENT_TYPE TICKET SEAT SHA PAYLOAD_JSON
  "$PYTHON_BIN" "$SCRIPT_DIR/lib/telemetry.py" log \
    "$(telemetry_session_id "$ARB_STATE")" "$1" "$2" - "$3" "$4" \
    --trace-dir "${ARB_STATE}/traces" >/dev/null 2>&1 || true
}

# ── lock: atomic mkdir, pid-stamped, stale after process death ────────────
arbiter_lock() { # STATE_DIR
  local lk="$1/arbiter.lock" tries=0 pid
  while ! mkdir "$lk" 2>/dev/null; do
    pid=""
    [[ -f "$lk/pid" ]] && pid=$(cat "$lk/pid" 2>/dev/null || true)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$lk"   # holder is dead: stale lock
      continue
    fi
    tries=$((tries + 1))
    (( tries >= 50 )) && return 1
    sleep "$ARBITER_TMP_SLEEP"
  done
  printf '%s\n' "$$" > "$lk/pid"
}

arbiter_unlock() { # STATE_DIR
  rm -rf "${1}/arbiter.lock" 2>/dev/null || true
}

# ── enqueue ────────────────────────────────────────────────────────────────
# arbiter_enqueue TICKET SEAT SHA
arbiter_enqueue() {
  _arb_cfg
  local ticket="$1" seat="$2" sha="$3"
  local now
  now=$(date +%s)

  # Idempotent enqueue: an identical queued (ticket, sha) is a no-op
  if [[ -f "$ARB_QUEUE" ]]; then
    local dup
    dup=$(jq -r -c -s --arg t "$ticket" --arg s "$sha" \
      'any(.[]; .ticket == $t and .sha == $s and .status == "queued")' "$ARB_QUEUE" 2>/dev/null || true)
    [[ "$dup" == "true" ]] && return 0
  fi

  # Supersession: a newer green verdict for the same ticket supersedes any
  # still-queued older sha for it.
  if [[ -f "$ARB_QUEUE" ]]; then
    local older
    older=$(jq -r -c -s --arg t "$ticket" \
      'map(select(.ticket == $t and .status == "queued")) | .[0].sha // empty' "$ARB_QUEUE" 2>/dev/null || true)
    if [[ -n "$older" && "$older" != "$sha" ]]; then
      _arb_set_status "$ticket" "$older" "superseded" "{superseded_by: \"${sha}\"}"
      _arb_telemetry arbiter.superseded "$ticket" "$seat" "$older" \
        "$(jq -cn --arg s "$sha" '{summary:("superseded by " + $s)}')"
    fi
  fi

  _arb_record "$(jq -cn --argjson ts "$now" --arg t "$ticket" \
    --arg seat "$seat" --arg sha "$sha" \
    '{ts: $ts, ticket: $t, seat: $seat, sha: $sha, status: "queued"}')"
  _arb_telemetry arbiter.queued "$ticket" "$seat" "$sha" \
    "$(jq -cn '{summary:"queued for integration"}')"
}

# ── auto-wire: enqueue → drain in the same pass (PROVE-4) ──────────────────
# The settled steady state (grilled with the driver 2026-09-23): a green
# verdict's enqueue must not sit queued until an operator runs
# `lib/arbiter.sh drain`. Wiring the trigger here changes no gate: the drain
# still takes the arbiter lock (serialized against any concurrent drain),
# still never writes the base branch, and still aborts conflicts back to the
# worker. Only the manual step is removed — promote stays human (ADR 0009).
arbiter_enqueue_and_drain() { # TICKET SEAT SHA
  arbiter_enqueue "$@" || return $?
  arbiter_drain
}

# Queued-record count (0 when no queue exists) — the supervisor's auto-drain
# trigger predicate: drain only when there is something to drain.
arbiter_queued_count() {
  _arb_cfg
  [[ -f "$ARB_QUEUE" ]] || { printf '0\n'; return 0; }
  jq -r -s '[.[] | select(.status == "queued")] | length' "$ARB_QUEUE" 2>/dev/null || printf '0'
}

# ── detached worktree management ───────────────────────────────────────────
_arb_worktree() { # START_COMMIT — ensure detached worktree at START_COMMIT
  if [[ ! -d "$ARB_WT" ]]; then
    mkdir -p "$(dirname "$ARB_WT")"
    git -C "$ARB_REPO" worktree add --detach "$ARB_WT" "$1" >/dev/null 2>&1
  else
    git -C "$ARB_WT" checkout --detach -q "$1" >/dev/null 2>&1
    git -C "$ARB_WT" reset --hard -q "$1" >/dev/null 2>&1
  fi
  git -C "$ARB_WT" clean -qfd >/dev/null 2>&1 || true
}

# ── drain ──────────────────────────────────────────────────────────────────
# Serialized queue processor: oldest queued record first, one at a time.
arbiter_drain() {
  _arb_cfg
  [[ -f "$ARB_QUEUE" ]] || return 0

  arbiter_lock "$ARB_STATE" || {
    printf 'arbiter: another drain holds the lock\n' >&2
    return 0
  }

  while :; do
    local rec
    rec=$(jq -r -c -s 'map(select(.status == "queued")) | sort_by(.ts) | .[0] // empty' "$ARB_QUEUE" 2>/dev/null || true)
    [[ -n "$rec" ]] || break

    local ticket seat sha
    ticket=$(jq -r '.ticket' <<<"$rec")
    seat=$(jq -r '.seat' <<<"$rec")
    sha=$(jq -r '.sha' <<<"$rec")

    # I0 = integration tip (initialized from the base branch if missing)
    local i0
    if git -C "$ARB_REPO" show-ref --verify --quiet "$ARB_REF"; then
      i0=$(git -C "$ARB_REPO" rev-parse "$ARB_REF")
    else
      i0=$(git -C "$ARB_REPO" rev-parse "$ARB_BASE")
    fi

    if ! _arb_integrate "$ticket" "$seat" "$sha" "$i0"; then
      break   # record resolved (conflict/red/retry), or ungateable; stop the pass
    fi
  done

  arbiter_unlock "$ARB_STATE"
}

# Integrate one queued record; returns 0 when the queue entry was resolved.
_arb_integrate() { # TICKET SEAT SHA I0
  local ticket="$1" seat="$2" sha="$3" i0="$4"

  # 1. candidate: fast-forward or off-branch --no-ff merge
  local candidate
  if git -C "$ARB_REPO" merge-base --is-ancestor "$i0" "$sha" 2>/dev/null; then
    candidate="$sha"
    _arb_worktree "$candidate"
  else
    _arb_worktree "$i0"
    if ! git -C "$ARB_WT" merge --no-ff --no-edit \
         -m "integrate #${ticket} (${seat} @ ${sha:0:7})" "$sha" >/dev/null 2>&1; then
      local files
      files=$(git -C "$ARB_WT" diff --name-only --diff-filter=U | jq -R -s 'split("\n") | map(select(length > 0))')
      git -C "$ARB_WT" merge --abort >/dev/null 2>&1 || true
      git -C "$ARB_WT" reset --hard -q "$i0" >/dev/null 2>&1 || true
      _arb_set_status "$ticket" "$sha" "conflict" \
        "{integration_before: \"${i0}\", files: ${files}}"
      _arb_telemetry arbiter.conflict "$ticket" "$seat" "$sha" \
        "$(jq -cn --arg f "$files" '{summary:"conflict with integration", files: $f}')"
      printf 'arbiter: #%s conflicts with integration @ %s\n' "$ticket" "${i0:0:7}" >&2
      return 1
    fi
    candidate=$(git -C "$ARB_WT" rev-parse HEAD)
  fi

  # 2. pre-gate the combined tree (arbiter TMPDIR; log kept for diagnosis)
  if _arb_cmd_runnable; then
    # The bound resolves BEFORE the gate runs. Without a timeout(1) the gate
    # exits 127, which this function used to record as integration_red —
    # condemning a combined tree it never actually measured (DOG-15). Leave
    # the record queued instead: truthful (unprocessed), self-healing once the
    # dependency is installed, and the ref stays where it is either way.
    if ! resolve_timeout; then
      _arb_telemetry arbiter.gate_unavailable "$ticket" "$seat" "$sha" \
        "$(jq -cn '{summary:"gate harness unavailable: no runnable timeout(1)"}')"
      printf 'arbiter: #%s NOT gated — no runnable timeout(1); left queued, ref unmoved\n' "$ticket" >&2
      return 1
    fi
    local gate_dir="${ARB_STATE}/gate-logs"
    local gate_log="${gate_dir}/arbiter-${ticket}-${sha:0:7}.log"
    mkdir -p "$gate_dir" "${ARB_STATE}/arbiter-tmp"
    if ! (cd "$ARB_WT" && TMPDIR="${ARB_STATE}/arbiter-tmp" \
          "$TIMEOUT_BIN" "${SUITE_TIMEOUT_S:-300}" sh -c "$TEST_CMD") >"$gate_log" 2>&1; then
      _arb_set_status "$ticket" "$sha" "integration_red" \
        "{integration_before: \"${i0}\", gate: {log: \"${gate_log}\"}}"
      _arb_telemetry arbiter.red "$ticket" "$seat" "$sha" \
        "$(jq -cn --arg l "$gate_log" '{summary:"integration gate RED", log: $l}')"
      printf 'arbiter: #%s integration gate RED (ref NOT advanced; log: %s)\n' "$ticket" "$gate_log" >&2
      return 1
    fi
  fi

  # 3. CAS ref update — the tip may only move from exactly I0. A missing ref
  # is first created AT the base tip with empty-old (must-not-exist), which
  # loses loudly to any concurrent creator; the CAS then still guards the tip.
  if ! git -C "$ARB_REPO" show-ref --verify --quiet "$ARB_REF"; then
    git -C "$ARB_REPO" update-ref "$ARB_REF" "$i0" "" >/dev/null 2>&1 || true
  fi
  if ! git -C "$ARB_REPO" update-ref "$ARB_REF" "$candidate" "$i0" 2>/dev/null; then
    _arb_set_status "$ticket" "$sha" "retry" "{integration_before: \"${i0}\"}"
    _arb_telemetry arbiter.retry "$ticket" "$seat" "$sha" \
      "$(jq -cn '{summary:"CAS failed — integration tip moved concurrently"}')"
    printf 'arbiter: #%s CAS failed (integration tip moved) — retry from new tip\n' "$ticket" >&2
    return 1
  fi

  # 4. success
  _arb_set_status "$ticket" "$sha" "integrated" \
    "{integration_before: \"${i0}\", merge_sha: \"${candidate}\"}"
  _arb_telemetry arbiter.integrated "$ticket" "$seat" "$sha" \
    "$(jq -cn --arg m "$candidate" --arg b "$i0" \
       '{summary:("integrated @ " + $m[0:7]), merge_sha: $m, integration_before: $b}')"
  printf 'arbiter: #%s integrated @ %s (was %s)\n' "$ticket" "${candidate:0:7}" "${i0:0:7}" >&2
  return 0
}

# ── promotion (human gate) ─────────────────────────────────────────────────
# arbiter_pr_body OUT_FILE — generated PR body listing integrated tickets
arbiter_pr_body() { # OUT_FILE
  _arb_cfg
  {
    # shellcheck disable=SC2016  # backticks are literal markdown, %s are printf conversions
    printf 'Herd integration for `%s` (base `%s`)\n\n' "$ARB_SLUG" "$ARB_BASE"
    printf 'Integrated tickets:\n\n'
    if [[ -f "$ARB_QUEUE" ]]; then
      jq -r -s 'map(select(.status == "integrated" or .status == "promoted"))
             | sort_by(.ticket)
             | .[] | "- #\(.ticket) \(.seat) @ \(.sha[0:7]) → merge \((.merge_sha // .sha)[0:7])\nCloses #\(.ticket)"' \
        "$ARB_QUEUE" >> "$1" 2>/dev/null || true
    fi
  } > "$1"
}

# _arb_promote_pane_check — GATE-1 fail-closed agent-pane guard.
# Local, non-airtight hardening (spec docs/audits/2026-09-23-harden-the-promote-gate.md §3):
# an agent instructed — even by the human, in its own pane — to run the promote
# must be stopped by more than its brief. Herdr injects $HERDR_PANE_ID into
# every pane it manages, so:
#   - unset            → allow (no Herdr context at all; a plain human shell)
#   - set, query fails → refuse (ambiguous state is not safe state — a stale
#                        workspace identity must never read as "safe")
#   - set, live agent in that pane → refuse, naming the pane
#   - set, managed but agentless   → allow (the human's own raw shell pane)
# This does NOT stop a deliberate bypass (same OS user, same credentials —
# spec §1); it closes the observed failure mode only. No env bypass exists.
_arb_promote_pane_check() {
  if [[ -z "${HERDR_PANE_ID:-}" ]]; then
    return 0
  fi
  local agents
  if ! agents=$(herdr agent list 2>/dev/null); then
    printf 'arbiter: promote refused -- could not query herdr agent state to confirm this pane is not agent-controlled\n' >&2
    return 1
  fi
  if printf '%s' "$agents" | jq -e --arg pid "$HERDR_PANE_ID" \
      '.result.agents[]? | select(.pane_id == $pid)' >/dev/null 2>&1; then
    printf 'arbiter: promote refused -- pane %s is occupied by a recognized agent; run this yourself from a plain shell\n' "$HERDR_PANE_ID" >&2
    return 1
  fi
  return 0
}

# arbiter_promote [--pr] [--confirm]  (or env PROMOTE_CONFIRM=1)
arbiter_promote() {
  # GATE-1: agent-pane guard fires before the --confirm gate and before the
  # --pr/local dispatch — a PR promote still pushes the integration branch,
  # which the Push Guardrail forbids agents just as much as a local ff-merge.
  if ! _arb_promote_pane_check; then
    return 1
  fi

  _arb_cfg
  local mode="local" confirmed=0 arg
  for arg in "$@"; do
    case "$arg" in
      --pr)      mode="pr" ;;
      --confirm) confirmed=1 ;;
    esac
  done

  # Human gate (DOG-12): moving a base branch is a human-only act. A brief is
  # a request, not enforcement — this refusal is the enforcement. It fires
  # before every other check so the human-action message is always the one
  # printed.
  if [[ "$confirmed" -ne 1 && "${PROMOTE_CONFIRM:-0}" != "1" ]]; then
    printf 'arbiter: promote REFUSED — promoting advances the base branch and is reserved for the human driver\n' >&2
    printf 'arbiter: required human action: run it yourself, exactly one of:\n' >&2
    printf 'arbiter:   bash lib/arbiter.sh promote --confirm\n' >&2
    printf 'arbiter:   PROMOTE_CONFIRM=1 bash lib/arbiter.sh promote\n' >&2
    printf 'arbiter: agents must never pass --confirm or set PROMOTE_CONFIRM — main moves only by human promote\n' >&2
    return 1
  fi

  git -C "$ARB_REPO" show-ref --verify --quiet "$ARB_REF" || {
    printf 'arbiter: no integration branch %s\n' "$ARB_REF" >&2
    return 1
  }
  local integ
  integ=$(git -C "$ARB_REPO" rev-parse "$ARB_REF")

  if [[ "$mode" == "pr" ]]; then
    local body="${ARB_STATE}/pr-body.md"
    arbiter_pr_body "$body"
    git -C "$ARB_REPO" push origin "swarm/${ARB_SLUG}/integration"
    gh pr create --base "$ARB_BASE" --head "swarm/${ARB_SLUG}/integration" \
      --title "herd: integrate ${ARB_SLUG}" --body-file "$body"
    local pr_url
    pr_url=$(gh pr view --json url -q .url 2>/dev/null || printf 'unknown')
    _arb_record "$(jq -cn --argjson ts "$(date +%s)" --arg t 0 \
      --arg st promoted --arg u "$pr_url" \
      '{ts: $ts, ticket: $t, status: $st, promoted_to: "pr", pr_url: $u}')"
    return 0
  fi

  # local mode: ff-only into the base branch, inside the root checkout
  local cur_branch dirt
  cur_branch=$(git -C "$ARB_REPO" rev-parse --abbrev-ref HEAD)
  dirt=$(git -C "$ARB_REPO" status --porcelain 2>/dev/null)
  if [[ "$cur_branch" != "$ARB_BASE" ]]; then
    printf 'arbiter: promote refused — root is on %s, not %s\n' "$cur_branch" "$ARB_BASE" >&2
    return 1
  fi
  if [[ -n "$dirt" ]]; then
    printf 'arbiter: promote refused — root working tree is dirty\n' >&2
    return 1
  fi
  if ! git -C "$ARB_REPO" merge-base --is-ancestor "$ARB_BASE" "$ARB_REF"; then
    printf 'arbiter: promote refused — %s has moved independently (not fast-forwardable)\n' "$ARB_BASE" >&2
    return 1
  fi
  git -C "$ARB_REPO" merge --ff-only "swarm/${ARB_SLUG}/integration" >/dev/null

  # mark every integrated record promoted
  if [[ -f "$ARB_QUEUE" ]]; then
    jq -s -c 'map(if .status == "integrated" then (.status = "promoted") + {promoted_to: "base"} else . end) | .[]' \
      "$ARB_QUEUE" > "${ARB_QUEUE}.tmp" && mv "${ARB_QUEUE}.tmp" "$ARB_QUEUE"
  fi
  _arb_telemetry arbiter.promoted 0 human "$integ" \
    "$(jq -cn --arg b "$ARB_BASE" '{summary:("promoted to " + $b)}')"
  printf 'arbiter: promoted integration to %s\n' "$ARB_BASE" >&2
}

# CLI dispatcher
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  cmd="${1:-}"
  shift 2>/dev/null || true
  case "$cmd" in
    enqueue) arbiter_enqueue_and_drain "$@" ;;   # PROVE-4: enqueue auto-drains
    drain)   arbiter_drain ;;
    promote) arbiter_promote "$@" ;;
    pr-body) arbiter_pr_body "${1:?out-file}" ;;
    *)
      printf 'Usage: %s enqueue <ticket> <seat> <sha> | drain | promote [--pr] [--confirm] | pr-body <file>\n' "$0" >&2
      printf '       enqueue also drains the queue in the same invocation (PROVE-4); drain remains for manual re-runs\n' >&2
      exit 1 ;;
  esac
fi
