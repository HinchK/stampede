#!/usr/bin/env bash
#
# loop-bot-herd — the swarm's supervisor loop.
#
# Not another kickoff wizard (herdr-loop-swarm.sh owns seating);
# this is the long-running watcher that makes the swarm self-tending:
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
# shellcheck disable=SC1091  # tomllib-capable interpreter (DOG-1)
source "$SCRIPT_DIR/lib/pyenv.sh"
resolve_python
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$SCRIPT_DIR/lib/profile.sh"
# shellcheck disable=SC1091  # dynamically resolved sibling libs
source "$SCRIPT_DIR/lib/config.sh"
# The arbiter is governance: it loads from the orchestrator (SCRIPT_DIR),
# never from the target tree under REPO_DIR. A supervisor install without
# its arbiter is broken — fail loudly before anything runs, and never fall
# back to a target-local copy (DOG-13).
if [[ ! -f "$SCRIPT_DIR/lib/arbiter.sh" ]]; then
  printf 'loop-bot-herd: FATAL — arbiter missing from orchestrator: %s/lib/arbiter.sh\n' "$SCRIPT_DIR" >&2
  printf 'loop-bot-herd: refusing to run; the target tree is never a fallback arbiter source\n' >&2
  exit 1
fi
# shellcheck disable=SC1091  # dynamically resolved sibling lib (arbiter enqueue at reap)
source "$SCRIPT_DIR/lib/arbiter.sh"

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

# ── asynchronous gate engine (ADR 0013) ────────────────────────────────────
# gate_concurrency: [fanout] config > env override; default 2; clamped 1–8;
# 0 = legacy inline gating (config-level rollback path).
GATE_CONCURRENCY="${GATE_CONCURRENCY:-${FANOUT_GATE_CONCURRENCY:-2}}"
case "$GATE_CONCURRENCY" in
  ''|*[!0-9]*) GATE_CONCURRENCY=2 ;;
esac
if (( GATE_CONCURRENCY > 8 )); then GATE_CONCURRENCY=8; fi

# Telemetry session (stable per project; shared with the launcher's Ops stream)
SESSION_ID=$(telemetry_session_id "$STATE_DIR")

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
      warn "seat absent: $seat (briefs/ has its brief; ./herdr-loop-swarm.sh up <target-dir> re-seats it)"
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
# at a NEW commit sha is re-evaluated through the suite gate. ONLY a green
# gate permanently retires a ticket; stale/invalidated/unresolvable records
# never block a later re-verdict at the same sha (P2-3).

# resolve_seat_gate SEAT → sets GATE_DIR, GATE_BRANCH, GATE_ISOLATED.
# Ledger-first (seats.json v2, read fresh every pass). Isolated seats whose
# worktree is missing or on the wrong branch return 1 — NEVER fall back to
# the root (that would gate the wrong tree and false-green it).
resolve_seat_gate() {
  local seat="$1"
  local ledger="${STATE_DIR}/seats.json"
  local rec
  GATE_DIR="$REPO_DIR"; GATE_BRANCH=""; GATE_ISOLATED=false
  [[ -f "$ledger" ]] || return 0
  rec=$(jq -c --arg s "$seat" '.seats[]? | select(.name == $s)' "$ledger" 2>/dev/null | head -n1)
  [[ -n "$rec" ]] || return 0
  GATE_ISOLATED=$(jq -r '.isolated // false' <<<"$rec")
  GATE_BRANCH=$(jq -r '.branch // empty' <<<"$rec")
  if [[ "$GATE_ISOLATED" == "true" ]]; then
    GATE_DIR=$(jq -r '.worktree_dir // empty' <<<"$rec")
    [[ -n "$GATE_DIR" && -d "$GATE_DIR" ]] || return 1
    [[ "$(git -C "$GATE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$GATE_BRANCH" ]] || return 1
  else
    GATE_DIR=$(jq -r --arg d "$REPO_DIR" '.worktree_dir // $d' <<<"$rec")
  fi
  return 0
}

# gate_tree_matches GATE_DIR SHA → 0 when HEAD == sha and tree is pristine
# (porcelain includes untracked files — an untracked *_test.py would be
# collected by the runner, so it counts as drift).
gate_tree_matches() {
  local dir="$1" want_sha="$2"
  local head_full sha_full
  head_full=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
  sha_full=$(git -C "$dir" rev-parse "${want_sha}^{commit}" 2>/dev/null || true)
  [[ -n "$head_full" && "$head_full" == "$sha_full" ]] || return 1
  [[ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]
}

# ── async gate job engine (ADR 0013: durable jobs, bounded, non-blocking) ──
# Job records:   ${STATE_DIR}/gates/<seat>-<sha7>.job  (atomic tmp+mv, pid inside)
# Completion:    <job>.rc written atomically by the job itself — the ONLY
#                completion signal; a half-written rc is impossible.
# Logs:          ${STATE_DIR}/gate-logs/<seat>-<sha7>.log (kept after reap)
# Crash rule:    dead pid without rc = discarded, re-harvested next pass.
#                NEVER inferred green.
# bash 3.2 safe: no wait -n, no associative arrays — file polling only.

gate_spawn() { # SEAT TICKET SHA GATE_DIR VERDICT_LINE ISOLATED
  local seat="$1" ticket="$2" sha="$3" dir="$4" vline="$5" isolated="${6:-false}"
  local jid="${seat}-${sha:0:7}"
  local jdir="${STATE_DIR}/gates"
  local jlog="${STATE_DIR}/gate-logs/${jid}.log"
  local jrc="${jdir}/${jid}.rc"
  mkdir -p "$jdir" "${STATE_DIR}/gate-logs" "${STATE_DIR}/gate-tmp/${seat}"
  (
    set +e
    if ! cd "$dir" 2>/dev/null; then
      printf '127' > "${jrc}.tmp" && mv "${jrc}.tmp" "$jrc"
      exit 0
    fi
    TMPDIR="${STATE_DIR}/gate-tmp/${seat}" timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD" > "$jlog" 2>&1
    local rc=$?
    printf '%s' "$rc" > "${jrc}.tmp" && mv "${jrc}.tmp" "$jrc"
  ) >/dev/null 2>&1 &
  local gpid=$!
  jq -cn --arg s "$seat" --argjson t "$ticket" --arg sha "$sha" --arg d "$dir" \
    --arg st "$(date -u +%FT%TZ)" --argjson pid "$gpid" --arg v "$vline" --arg iso "$isolated" \
    '{version: 1, seat: $s, ticket: $t, sha: $sha, dir: $d, start_time: $st,
      pid: $pid, isolated: ($iso == "true"), verdict_line: $v}' \
    > "${jdir}/${jid}.job.tmp" && mv "${jdir}/${jid}.job.tmp" "${jdir}/${jid}.job"
  log "gate job spawned: ${jid} (pid ${gpid}, cap ${GATE_CONCURRENCY})"
}

# running jobs = .job files whose .rc has not landed yet
gate_running_count() {
  local j n=0
  for j in "$STATE_DIR"/gates/*.job; do
    [[ -e "$j" ]] || continue
    [[ -f "${j%.job}.rc" ]] || n=$((n + 1))
  done
  printf '%s' "$n"
}

# one job per (ticket, sha): a duplicate verdict line never double-spawns
gate_job_running() { # TICKET SHA
  local j
  for j in "$STATE_DIR"/gates/*.job; do
    [[ -e "$j" ]] || continue
    jq -e --argjson t "$1" --arg s "$2" '.ticket == $t and .sha == $s' "$j" >/dev/null 2>&1 && return 0
  done
  return 1
}

# Non-blocking reap: for every finished job, post-check drift → verdict
# record → telemetry → (green && isolated) arbiter_enqueue → cleanup.
gate_reap() {
  local job jrc jid meta seat ticket sha dir iso rc_val suite_ok ts gate_log
  for job in "$STATE_DIR"/gates/*.job; do
    [[ -e "$job" ]] || continue
    jrc="${job%.job}.rc"
    [[ -f "$jrc" ]] || continue
    meta=$(cat "$job" 2>/dev/null || true)
    if [[ -z "$meta" ]]; then
      rm -f "$job" "$jrc"
      continue
    fi
    seat=$(jq -r '.seat // empty' <<<"$meta")
    ticket=$(jq -r '.ticket // empty' <<<"$meta")
    sha=$(jq -r '.sha // empty' <<<"$meta")
    dir=$(jq -r '.dir // empty' <<<"$meta")
    iso=$(jq -r '.isolated // false' <<<"$meta")
    [[ -n "$seat" && -n "$ticket" && -n "$sha" && -n "$dir" ]] || { rm -f "$job" "$jrc"; continue; }
    rc_val=$(cat "$jrc" 2>/dev/null || printf '1')
    ts=$(date +%s)
    jid=$(basename "$job" .job)
    gate_log="${STATE_DIR}/gate-logs/${jid}.log"

    if ! gate_tree_matches "$dir" "$sha"; then
      suite_ok="invalidated"; bad "gate job ${jid}: INVALIDATED — tree drifted during the background run"
      herdr agent prompt "$seat" "LOOP-BOT: suite run for #$ticket @ ${sha} was INVALIDATED — the tree changed during the gate. Re-verdict 'ARCH DONE #$ticket <sha>' from a stable tree." >/dev/null 2>&1 || true
    elif [[ "$rc_val" == "0" ]]; then
      suite_ok="green"; ok "gate job ${jid}: GREEN (log: $gate_log)"
      herdr agent prompt looper "LOOP-BOT: filed verdict for #$ticket @ ${sha} from $seat's pane (green)." >/dev/null 2>&1 || true
      if [[ "$iso" == "true" ]]; then
        arbiter_enqueue "$ticket" "$seat" "$sha" >/dev/null 2>&1 \
          || warn "arbiter enqueue failed for #$ticket @ ${sha}"
      fi
    else
      suite_ok="RED"; bad "gate job ${jid}: RED (rc=${rc_val}) — NOT filed; worker must fix (log: $gate_log)"
      herdr agent prompt "$seat" "LOOP-BOT: verdict for #$ticket @ ${sha} harvested but the suite is RED — fix, commit, and re-verdict with the new sha (gate log: $gate_log)." >/dev/null 2>&1 || true
    fi

    echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"exit_code\": $rc_val, \"log\": \"$gate_log\"}" >> "$SESSION_LOG"
    "$PYTHON_BIN" "$SCRIPT_DIR/lib/telemetry.py" log "$SESSION_ID" suite.verdict "$seat" "$ticket" \
      "$(jq -cn --arg s "$suite_ok" --arg sha "$sha" --arg seat "$seat" --arg t "$ticket" \
        '{suite:$s, sha:$sha, summary:("suite " + $s + " @ " + $sha), details:("seat=" + $seat + " ticket=#" + $t)}')" \
      --trace-dir "${STATE_DIR}/traces" >/dev/null 2>&1 || true
    rm -f "$job" "$jrc"   # conclusive: job done, log kept
  done
}

# Crash recovery (ADR 0013 §D): adopt live pids, discard dead pids without rc.
gate_recover() {
  local job jrc pid
  for job in "$STATE_DIR"/gates/*.job; do
    [[ -e "$job" ]] || continue
    jrc="${job%.job}.rc"
    [[ -f "$jrc" ]] && continue
    pid=$(jq -r '.pid // empty' "$job" 2>/dev/null || true)
    if [[ -n "$pid" && "$pid" != "null" ]] && ! kill -0 "$pid" 2>/dev/null; then
      warn "gate job $(basename "$job" .job): pid ${pid} died without rc — DISCARDED (never assumed green); verdict re-harvests next pass"
      rm -f "$job"
    fi
    # alive → adopted as-is; its rc write still lands and the next reap takes it
  done
}

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
        # Permanent retire: this ticket already gated GREEN (only green retires)
        if jq -e -s --argjson t "$ticket" 'any(.[]; .ticket == $t and .suite == "green")' "$SESSION_LOG" >/dev/null 2>&1; then
          continue
        fi
        # (ticket, sha) dedup: this exact code state was already CONCLUSIVELY
        # evaluated. Drift records (stale/invalidated/unresolvable) are excluded
        # so a cleaned-up re-verdict at the same sha is properly gated.
        if jq -e -s --argjson t "$ticket" --arg s "$sha" \
          'any(.[]; .ticket == $t and .sha == $s and (.suite != "stale" and .suite != "invalidated" and .suite != "unresolvable"))' \
          "$SESSION_LOG" >/dev/null 2>&1; then
          continue
        fi
      fi
      # Commit reality check (V1): the verdict sha must exist in the shared
      # object store. Fabricated/stale shas are never suite-gated.
      if ! git -C "$REPO_DIR" cat-file -e "${sha}^{commit}" 2>/dev/null; then
        warn "verdict for #$ticket @ ${sha}: commit not found in repo — skipped, human evaluation required"
        echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"skipped\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
        herdr agent prompt looper "LOOP-BOT: verdict for #$ticket @ ${sha} names a commit absent from the repo — do NOT retire the ticket; human evaluation required." >/dev/null 2>&1 || true
        continue
      fi
      # Gate target resolution (ledger v2): isolated seats gate in their own
      # worktree; a missing/mismatched one is unresolvable, never root-gated.
      if ! resolve_seat_gate "$seat"; then
        warn "verdict for #$ticket @ ${sha}: seat '$seat' gate unresolvable (isolated worktree missing or wrong branch) — NOT gated"
        echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"unresolvable\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
        herdr agent prompt looper "LOOP-BOT: verdict for #$ticket @ ${sha} from $seat could not be resolved to a gate directory (worktree missing or on the wrong branch). Do NOT retire the ticket — human evaluation required." >/dev/null 2>&1 || true
        continue
      fi
      local gate_log_dir="${STATE_DIR}/gate-logs"
      mkdir -p "$gate_log_dir" "${STATE_DIR}/gate-tmp/${seat}"
      local gate_log="${gate_log_dir}/${seat}-${sha}.log"
      # Pre-condition drift: the tree must be exactly the verdict's commit.
      if ! gate_tree_matches "$GATE_DIR" "$sha"; then
        warn "verdict for #$ticket @ ${sha}: gate tree is STALE (HEAD moved or dirty/untracked files) — not gating"
        echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"stale\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
        herdr agent prompt "$seat" "LOOP-BOT: verdict for #$ticket @ ${sha} rejected as STALE — the gate tree does not match that commit (uncommitted or untracked files, or HEAD moved). Commit your changes or remove stray files (no git stash), then re-verdict 'ARCH DONE #$ticket <new sha>'." >/dev/null 2>&1 || true
        continue
      fi
      local suite_ok="skipped"
      if [[ "$(ctl_get suite_gate)" == "true" ]] && test_cmd_is_runnable "$TEST_CMD"; then
        if (( GATE_CONCURRENCY > 0 )); then
          # ── async path (ADR 0013): spawn and keep scanning ──
          if gate_job_running "$ticket" "$sha"; then
            continue   # already gated; reap will record
          fi
          if (( $(gate_running_count) >= GATE_CONCURRENCY )); then
            note "gate slots full (cap ${GATE_CONCURRENCY}) — verdict for #$ticket @ ${sha} deferred to next pass"
            continue
          fi
          gate_spawn "$seat" "$ticket" "$sha" "$GATE_DIR" "$verdict_line" "$GATE_ISOLATED"
          continue   # verdict record lands at reap time
        fi
        # ── legacy inline path (gate_concurrency = 0): unchanged semantics ──
        log "verdict for #$ticket @ ${sha} — running suite gate in ${GATE_DIR}: ${TEST_CMD}"
        local gate_rc=1
        if (cd "$GATE_DIR" && TMPDIR="${STATE_DIR}/gate-tmp/${seat}" timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD") >"$gate_log" 2>&1; then
          gate_rc=0
        fi
        # Post-condition drift (TOCTOU): the worker must not have touched
        # the tree while the suite ran — a moved/dirtied tree invalidates
        # the run regardless of exit code.
        if ! gate_tree_matches "$GATE_DIR" "$sha"; then
          suite_ok="invalidated"; bad "suite run for #$ticket @ ${sha} INVALIDATED — tree changed during the gate"
          echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"log\": \"$gate_log\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
          herdr agent prompt "$seat" "LOOP-BOT: suite run for #$ticket @ ${sha} was INVALIDATED — the tree changed during the gate. Re-verdict 'ARCH DONE #$ticket <sha>' from a stable tree." >/dev/null 2>&1 || true
        elif [[ "$gate_rc" -eq 0 ]]; then
          suite_ok="green"; ok "suite gate GREEN for #$ticket @ ${sha} (log: $gate_log)"
          echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"log\": \"$gate_log\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
        else
          suite_ok="RED"; bad "suite gate RED for #$ticket @ ${sha} — NOT filed; arch must fix before done (log: $gate_log)"
          echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"log\": \"$gate_log\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
          herdr agent prompt "$seat" "LOOP-BOT: verdict for #$ticket @ ${sha} harvested but the suite is RED — fix, commit, and re-verdict with the new sha (gate log: $gate_log)." >/dev/null 2>&1 || true
        fi
      elif [[ "$(ctl_get suite_gate)" == "true" ]]; then
        # No runnable suite for this project — never fake-green, record as skipped
        warn "TEST_CMD not runnable (${TEST_CMD:-<empty>}) — recording verdict for #$ticket without suite gate"
        echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
      else
        echo "{\"ts\": $ts, \"ticket\": $ticket, \"sha\": \"$sha\", \"seat\": \"$seat\", \"suite\": \"$suite_ok\", \"verdict\": $(jq -Rn --arg v "$verdict_line" '$v' )}" >> "$SESSION_LOG"
      fi

      # Telemetry: suite verdict event (streams live into the Ops pane)
      "$PYTHON_BIN" "$SCRIPT_DIR/lib/telemetry.py" log "$SESSION_ID" suite.verdict "$seat" "$ticket" \
        "$(jq -cn --arg s "$suite_ok" --arg sha "$sha" --arg seat "$seat" --arg t "$ticket" \
          '{suite:$s, sha:$sha, summary:("suite " + $s + " @ " + $sha), details:("seat=" + $seat + " ticket=#" + $t)}')" \
        --trace-dir "${STATE_DIR}/traces" >/dev/null 2>&1 || true
      # Acceptance semantics: only a GREEN gate retires a ticket. RED demands
      # fix-and-reverdict. SKIPPED (gate off / no runnable TEST_CMD) is never
      # reported to looper as accepted completion — it escalates to the human.
      if [[ "$suite_ok" == "green" ]]; then
        herdr agent prompt looper "LOOP-BOT: filed verdict for #$ticket @ ${sha} from $seat's pane (green)." >/dev/null 2>&1 || true
      elif [[ "$suite_ok" == "skipped" ]]; then
        bad "verdict for #$ticket @ ${sha} recorded WITHOUT suite verification — HUMAN EVALUATION REQUIRED"
        herdr agent prompt looper "LOOP-BOT: verdict for #$ticket @ ${sha} from $seat's pane could NOT be suite-verified (gate off or non-runnable TEST_CMD). Do NOT retire the ticket — human evaluation required." >/dev/null 2>&1 || true
      fi
    done < <(grep -E '^[[:space:]]*ARCH DONE #[0-9]+[[:space:]]+[0-9a-fA-F]{7,40}[[:space:]]*$' <<<"$out" | tail -n 5)
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
# Only meaningful when the optional routing proxy is enabled in
# swarm.config.toml — a universal target repo has no kultivait credentials.
credits_watch() {
  local key out
  [[ "$(config_get "proxy.enabled" "false" "${SWARM_CONFIG:-$SCRIPT_DIR/swarm.config.toml}")" == "true" ]] || return 0
  key=$("$PYTHON_BIN" - "${KULTIVAIT_CREDENTIALS:-$HOME/.kultivait/credentials.toml}" << 'EOF' 2>/dev/null || true
import sys, tomllib
from pathlib import Path
p = Path(sys.argv[1])
if p.is_file():
    d = tomllib.loads(p.read_text())
    print(d.get("openrouter", {}).get("api_key", ""))
EOF
)
  [[ -n "$key" ]] || return 0
  out=$(curl -sf --max-time 5 -H "Authorization: Bearer $key" https://openrouter.ai/api/v1/credits 2>/dev/null || true)
  [[ -n "$out" ]] || { warn "OpenRouter /credits unreachable"; return 0; }
  "$PYTHON_BIN" - "$out" "$CREDIT_WARN_USD" << 'EOF'
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
  gate_recover
  health_pass
  harvest_verdicts
  gate_reap
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
