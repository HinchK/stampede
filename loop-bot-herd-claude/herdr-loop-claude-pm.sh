#!/usr/bin/env bash
# herdr-loop-swarm — a parallel, self-healing evolution of the kultivait herd.
#
# Today's herd is SEQUENTIAL: looper dispatches arch one ticket at a time on a
# single main checkout. This fans a task list into N workers, each in its own
# git worktree, watches them via herdr's own agent signals, verifies every task
# independently, and integrates through one arbiter that opens a single PR.
#
# Design (each point earned from an observed failure in the sequential herd):
#   1. Parallel workers, not one-at-a-time.
#   2. git worktree per task  → isolation; main never drifts mid-flight.
#   3. file-ownership partition → reject splits where two tasks write one file.
#   4. watchdog from herdr agent_status + state_change_seq → reap/relaunch
#      stalled workers, queue blocked ones for the human (don't hang the loop).
#   5. durable ledger in .swarm/ → cold `resume` reconstructs, never re-derives.
#   6. independent verify gate → a task is done only when the suite runs GREEN
#      with a non-zero test count in its worktree (no self-reported false-green).
#   7. cost-routed workers + an arbiter → cheapest capable agent per task;
#      one integrated PR at the end.
#
# SAFE BY DEFAULT: dry-run unless --live. Never pushes the base branch; the
# arbiter opens a PR, a human merges.
#
# Usage:
#   herdr-loop-swarm.sh run   --repo <dir> --tasks <file> [--live] [--max N]
#   herdr-loop-swarm.sh resume --repo <dir> [--live]
#   herdr-loop-swarm.sh status --repo <dir>
#   herdr-loop-swarm.sh stop   --repo <dir>
#   herdr-loop-swarm.sh partition-check --tasks <file>
#
# Tasks file: one task per line, "|"-delimited, 4 fields (blank/# lines ignored)
#   id | tier | owns (space-separated paths) | prompt
# tier ∈ {code, docs, mechanical, hard} → routed to an agent kind (see route_kind).

set -uo pipefail

# ── config (env overridable) ──────────────────────────────────────────────
REPO=""; TASKS=""; LIVE=0; SWARM_MAX="${SWARM_MAX:-3}"
BASE_BRANCH="${BASE_BRANCH:-main}"
TICK_SECS="${TICK_SECS:-20}"
STALL_SECS="${STALL_SECS:-600}"     # working but no state change this long = stalled
MAX_RELAUNCH="${MAX_RELAUNCH:-1}"
TEST_CMD="${TEST_CMD:-}"            # auto-detected if empty
# tier → herdr agent kind (reduce→right-size→localize, applied to the fleet)
KIND_CODE="${KIND_CODE:-opencode}"     # GLM-5.3 etc. — real code
KIND_DOCS="${KIND_DOCS:-agy}"          # cheap/fast — docs, README, logs
KIND_MECH="${KIND_MECH:-agy}"          # mechanical migrations, renames
KIND_HARD="${KIND_HARD:-claude}"       # hard design / verification
KIND_ARBITER="${KIND_ARBITER:-claude}"

now()  { date +%s; }
iso()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
die()  { printf 'error: %s\n' "$1" >&2; exit 1; }
log()  { printf '[swarm %s] %s\n' "$(iso)" "$1"; }

SWARM=""   # set once REPO known: $REPO/.swarm
ledger() { printf '{"ts":"%s","task":"%s","event":"%s","detail":"%s"}\n' \
             "$(iso)" "$1" "$2" "${3:-}" >> "$SWARM/ledger.jsonl"; }

route_kind() {
  case "$1" in
    docs) printf '%s' "$KIND_DOCS" ;;
    mechanical) printf '%s' "$KIND_MECH" ;;
    hard) printf '%s' "$KIND_HARD" ;;
    code|*) printf '%s' "$KIND_CODE" ;;
  esac
}

# ── task ingestion + the partition invariant (#3) ─────────────────────────
# parse_tasks FILE emits "id\ttier\towns\tprompt" for valid lines.
parse_tasks() {
  awk -F'|' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { gsub(/^[ \t]+|[ \t]+$/,"",$1); gsub(/^[ \t]+|[ \t]+$/,"",$2);
      gsub(/^[ \t]+|[ \t]+$/,"",$3); sub(/^[ \t]+/,"",$4);
      if ($1=="") next;
      printf "%s\t%s\t%s\t%s\n",$1,$2,$3,$4 }' "$1"
}

# partition_check FILE: fail if any owned path appears in more than one task.
partition_check() {
  local file="$1" bad=0
  parse_tasks "$file" | awk -F'\t' '{ n=split($3,a," "); for(i=1;i<=n;i++) if(a[i]!="") print a[i]"\t"$1 }' \
    | sort | awk -F'\t' '
      { if ($1==prev && $2!=powner) { print "CONFLICT: " $1 " claimed by both " powner " and " $2; bad=1 }
        prev=$1; powner=$2 }
      END { exit bad }' || bad=1
  # also reject duplicate task ids
  local dups
  dups=$(parse_tasks "$file" | cut -f1 | sort | uniq -d)
  [ -n "$dups" ] && { printf 'CONFLICT: duplicate task id(s): %s\n' "$dups"; bad=1; }
  return $bad
}

# ── per-task state on disk (resumable; no assoc arrays for bash 3.2) ───────
tset() { printf '%s' "$3" > "$SWARM/tasks/$1/$2"; }
tget() { cat "$SWARM/tasks/$1/$2" 2>/dev/null; }
task_ids() { [ -d "$SWARM/tasks" ] && ls "$SWARM/tasks" 2>/dev/null; }
count_status() { local s="$1" n=0 id; for id in $(task_ids); do [ "$(tget "$id" status)" = "$s" ] && n=$((n+1)); done; echo "$n"; }

load_tasks() {
  local id tier owns prompt line
  while IFS=$'\t' read -r id tier owns prompt; do
    [ -n "$id" ] || continue
    if [ -d "$SWARM/tasks/$id" ]; then continue; fi   # resume: keep existing state
    mkdir -p "$SWARM/tasks/$id"
    tset "$id" tier "$tier"; tset "$id" owns "$owns"; tset "$id" prompt "$prompt"
    tset "$id" status pending; tset "$id" retries 0
    ledger "$id" loaded "tier=$tier kind=$(route_kind "$tier")"
  done < <(parse_tasks "$TASKS")
}

detect_test_cmd() {
  [ -n "$TEST_CMD" ] && { printf '%s' "$TEST_CMD"; return; }
  if [ -f "$REPO/pyproject.toml" ]; then printf 'uv run pytest -q'
  elif [ -f "$REPO/package.json" ]; then printf 'npm test --silent'
  else printf 'true'; fi
}

# ── seating a worker (#1,#2,#7) ───────────────────────────────────────────
worker_prompt() {  # id
  local id="$1"
  cat <<EOF
SWARM WORKER — task "$id". You are one of several agents working in parallel.
Work ONLY inside this worktree ($(tget "$id" worktree)); it is your branch
swarm/$id off $BASE_BRANCH. Files you own: $(tget "$id" owns). Do not touch files
you do not own — another worker owns them.

TASK: $(tget "$id" prompt)

RULES (a self-reported "done" is not accepted):
- Commit at every task boundary with a clear message. Small commits.
- Before you say you are finished, run the full suite in THIS worktree:
    $(detect_test_cmd)
  and paste the real output. A green summary line is not enough — the run must
  show a non-zero test count. The supervisor re-runs it independently.
- If you are blocked on a decision only a human can make, STOP and say
  "BLOCKED: <question>". Do not guess; the swarm keeps moving other tasks.
- End with "DONE $id" on its own line once the suite is green.
EOF
}

seat_worker() {  # id
  local id tier kind wt br pane agent
  id="$1"; tier="$(tget "$id" tier)"; kind="$(route_kind "$tier")"
  wt="$SWARM/wt/$id"; br="swarm/$id"
  if [ "$LIVE" -eq 0 ]; then
    tset "$id" worktree "$wt"; tset "$id" branch "$br"; tset "$id" status running
    tset "$id" last_seq 0; tset "$id" last_change "$(now)"
    log "DRY-RUN would seat '$id' (kind=$kind) in worktree $wt on $br"
    ledger "$id" seated-dry "kind=$kind"
    return 0
  fi
  git -C "$REPO" worktree add -q -b "$br" "$wt" "$BASE_BRANCH" 2>/dev/null \
    || git -C "$REPO" worktree add -q "$wt" "$br" 2>/dev/null \
    || { ledger "$id" worktree-fail; tset "$id" status failed; return 1; }
  tset "$id" worktree "$wt"; tset "$id" branch "$br"
  pane=$(herdr pane split --current --direction down --cwd "$wt" --no-focus 2>/dev/null | jq -r '.result.pane.pane_id') \
    || { ledger "$id" pane-fail; tset "$id" status failed; return 1; }
  tset "$id" pane "$pane"; agent="w-$id"
  if herdr agent start "$agent" --kind "$kind" --pane "$pane" >/dev/null 2>&1; then
    tset "$id" agent "$agent"
    herdr agent prompt "$agent" "$(worker_prompt "$id")" >/dev/null 2>&1 || true
    tset "$id" status running; tset "$id" last_seq 0; tset "$id" last_change "$(now)"
    log "seated '$id' → agent $agent (kind=$kind) in $wt"
    ledger "$id" seated "kind=$kind agent=$agent pane=$pane"
  else
    ledger "$id" agent-start-fail "kind=$kind"; tset "$id" status failed
  fi
}

agent_seq()    { herdr agent get "$1" 2>/dev/null | jq -r '.result.agent.state_change_seq // .result.state_change_seq // 0' 2>/dev/null; }
agent_status() { herdr agent get "$1" 2>/dev/null | jq -r '.result.agent.agent_status // .result.agent_status // "unknown"' 2>/dev/null; }

# ── independent verification (#6) ─────────────────────────────────────────
verify_task() {  # id
  local id="$1" wt out tc
  wt="$(tget "$id" worktree)"; tc="$(detect_test_cmd)"
  if [ "$LIVE" -eq 0 ] || [ "$tc" = "true" ]; then
    tset "$id" status done; tset "$id" sha "$(git -C "$wt" rev-parse --short HEAD 2>/dev/null || echo dry)"
    ledger "$id" verified-skip "dry-run or no suite"; return 0
  fi
  out=$(cd "$wt" && eval "$tc" 2>&1); local rc=$?
  # require exit 0 AND a non-zero test count (kills false-green)
  if [ $rc -eq 0 ] && printf '%s' "$out" | grep -qE '[1-9][0-9]* (passed|tests? passed|passing)'; then
    tset "$id" status done; tset "$id" sha "$(git -C "$wt" rev-parse --short HEAD)"
    ledger "$id" verified "$(printf '%s' "$out" | grep -oE '[0-9]+ passed' | head -1)"
  else
    tset "$id" status failed; ledger "$id" verify-fail "rc=$rc"
  fi
}

# ── the supervisor loop + watchdog (#4) ───────────────────────────────────
tick() {
  local id st seq last age
  for id in $(task_ids); do
    st="$(tget "$id" status)"; [ "$st" = "running" ] || continue
    if [ "$LIVE" -eq 0 ]; then verify_task "$id"; continue; fi   # dry-run: auto-complete
    local ast; ast="$(agent_status "w-$id")"
    case "$ast" in
      idle|done)  tset "$id" status verifying; ledger "$id" turn-idle; verify_task "$id" ;;
      blocked)    tset "$id" status blocked; ledger "$id" blocked "needs human — see: herdr agent read w-$id" ;;
      working)
        seq="$(agent_seq "w-$id")"; last="$(tget "$id" last_seq)"
        if [ "${seq:-0}" != "${last:-0}" ]; then tset "$id" last_seq "$seq"; tset "$id" last_change "$(now)"
        else
          age=$(( $(now) - $(tget "$id" last_change) ))
          if [ "$age" -ge "$STALL_SECS" ]; then
            local r; r="$(tget "$id" retries)"
            log "task '$id' STALLED (${age}s no progress)"; ledger "$id" stalled "age=${age}s"
            herdr agent send-keys "w-$id" ctrl+c >/dev/null 2>&1 || true
            git -C "$(tget "$id" worktree)" add -A >/dev/null 2>&1 || true
            git -C "$(tget "$id" worktree)" commit -qm "swarm: checkpoint stalled $id" >/dev/null 2>&1 || true
            if [ "${r:-0}" -lt "$MAX_RELAUNCH" ]; then tset "$id" retries $((r+1)); tset "$id" status pending
              ledger "$id" relaunch "attempt=$((r+1))"
            else tset "$id" status failed; ledger "$id" gave-up; fi
          fi
        fi ;;
      *) : ;;
    esac
  done
}

# ── arbiter: integrate all green branches into ONE PR (#7) ────────────────
arbiter() {
  local ids="" id
  for id in $(task_ids); do [ "$(tget "$id" status)" = "done" ] && ids="$ids swarm/$id"; done
  [ -n "$ids" ] || { log "no green branches to integrate"; return 0; }
  log "arbiter: integrating branches:$ids"
  if [ "$LIVE" -eq 0 ]; then
    log "DRY-RUN would seat arbiter ($KIND_ARBITER) to merge:$ids → one PR against $BASE_BRANCH"
    ledger _arbiter dry "branches:$ids"; return 0
  fi
  local pane agent
  pane=$(herdr pane split --current --direction down --cwd "$REPO" --no-focus 2>/dev/null | jq -r '.result.pane.pane_id')
  agent="arbiter"; herdr agent start "$agent" --kind "$KIND_ARBITER" --pane "$pane" >/dev/null 2>&1 \
    || { ledger _arbiter start-fail; return 1; }
  herdr agent prompt "$agent" "$(cat <<EOF
SWARM ARBITER. Integrate these completed branches into ONE pull request against
$BASE_BRANCH:$ids
Steps: review each branch as a code reviewer; merge them in dependency order
(a branch that others build on first); resolve conflicts; run the full suite on
the INTEGRATED result ($(detect_test_cmd)) and paste real output showing a
non-zero test count; then open ONE PR with a per-task summary table. Do NOT push
$BASE_BRANCH directly. If integration fails, stop and report which branch broke it.
EOF
)" >/dev/null 2>&1 || true
  ledger _arbiter seated "branches:$ids"
  log "arbiter seated (agent=$agent) — it will open one PR; a human merges"
}

# ── driver ────────────────────────────────────────────────────────────────
supervisor() {
  local pending running blocked
  while :; do
    running="$(count_status running)"; pending="$(count_status pending)"
    # fill open slots
    if [ "$running" -lt "$SWARM_MAX" ] && [ "$pending" -gt 0 ]; then
      local id
      for id in $(task_ids); do
        [ "$(count_status running)" -lt "$SWARM_MAX" ] || break
        [ "$(tget "$id" status)" = "pending" ] && seat_worker "$id"
      done
    fi
    tick
    running="$(count_status running)"; pending="$(count_status pending)"; blocked="$(count_status blocked)"
    log "status: $(count_status done) done · $running running · $pending pending · $blocked blocked · $(count_status failed) failed"
    if [ "$running" -eq 0 ] && [ "$pending" -eq 0 ]; then
      [ "$blocked" -gt 0 ] && { log "swarm idle with $blocked task(s) BLOCKED on a human — run: $0 status --repo $REPO"; }
      break
    fi
    [ "$LIVE" -eq 0 ] && continue   # dry-run resolves in one pass
    sleep "$TICK_SECS"
  done
  arbiter
}

cmd_status() {
  printf '%-20s %-10s %-8s %-8s %s\n' TASK STATUS TIER RETRY BRANCH
  local id
  for id in $(task_ids); do
    printf '%-20s %-10s %-8s %-8s %s\n' "$id" "$(tget "$id" status)" "$(tget "$id" tier)" \
      "$(tget "$id" retries)" "$(tget "$id" branch)"
  done
}

cmd_stop() {
  local id
  for id in $(task_ids); do
    local a; a="$(tget "$id" agent)"; [ -n "$a" ] && herdr agent send-keys "$a" ctrl+c >/dev/null 2>&1 || true
  done
  log "sent stop to all seated workers (worktrees + branches left in place)"
}

# ── arg parsing ─────────────────────────────────────────────────────────────
CMD="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --tasks) TASKS="$2"; shift 2 ;;
    --max)   SWARM_MAX="$2"; shift 2 ;;
    --live)  LIVE=1; shift ;;
    *) die "unknown arg: $1" ;;
  esac
done

case "$CMD" in
  partition-check)
    [ -n "$TASKS" ] || die "need --tasks <file>"
    if partition_check "$TASKS"; then echo "OK: no file-ownership conflicts, no duplicate ids"; else exit 1; fi ;;
  run|resume)
    [ -n "$REPO" ] || die "need --repo <dir>"
    REPO="$(cd "$REPO" && pwd -P)"; SWARM="$REPO/.swarm"
    git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "--repo is not a git repo: $REPO"
    mkdir -p "$SWARM/tasks" "$SWARM/wt"
    if [ "$CMD" = "run" ]; then
      [ -n "$TASKS" ] || die "run needs --tasks <file>"
      partition_check "$TASKS" || die "fix the file-ownership conflicts above before running"
      load_tasks
    else
      [ -n "$(task_ids)" ] || die "nothing to resume (no .swarm/tasks); use 'run' first"
      # resume: any running task whose agent is gone becomes pending again
      for id in $(task_ids); do
        [ "$(tget "$id" status)" = "running" ] && [ "$LIVE" -eq 1 ] \
          && [ "$(agent_status "w-$id")" = "unknown" ] && { tset "$id" status pending; ledger "$id" resume-requeue; }
      done
    fi
    log "$CMD: repo=$REPO max=$SWARM_MAX live=$LIVE base=$BASE_BRANCH"
    supervisor ;;
  status)  [ -n "$REPO" ] || die "need --repo <dir>"; SWARM="$(cd "$REPO" && pwd -P)/.swarm"; cmd_status ;;
  stop)    [ -n "$REPO" ] || die "need --repo <dir>"; SWARM="$(cd "$REPO" && pwd -P)/.swarm"; cmd_stop ;;
  ''|-h|--help)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $CMD (try: run resume status stop partition-check)" ;;
esac
