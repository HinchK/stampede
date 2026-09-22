#!/usr/bin/env bash
# tests/test_async_gate.sh — P3-3 acceptance suite (ADR 0013 / PM spec §4)
# Scratch repo, two isolated worktrees, stubbed herdr. Exit 0 = all pass.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
# shellcheck disable=SC2034  # vars are consumed inside those eval strings
# shellcheck disable=SC2015  # ok/bad never fail, so A && ok || bad is safe here
# shellcheck disable=SC2329  # ok/bad are invoked indirectly via assertion helpers
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-ag-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
RD="$TEST_DIR/repo"
STATE="$RD/.herdr-swarm"
Q="$STATE/integration.jsonl"
LOG="$STATE/session-verdicts.jsonl"
GATES="$STATE/gates"
PASS=0
FAIL=0

cleanup() {
  # kill any gate jobs still running so the scratch repo can be removed
  local j pid
  for j in "$GATES"/*.job; do
    [[ -e "$j" ]] || continue
    pid=$(jq -r '.pid // empty' "$j" 2>/dev/null || true)
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Assertion helpers are named assert_ok/assert_bad deliberately: the
# supervisor ships its own one-argument ok()/bad() loggers which its guts
# call — redefining those two-arg versions broke set -u inside gate_reap.
assert_ok()  { printf '  ✓ [%s] %s\n' "$1" "${2:-}"; PASS=$((PASS + 1)); }
assert_bad() { printf '  ✗ [%s] %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }
last_suite_of() { jq -r -s --argjson t "$1" '[.[] | select(.ticket == $t)] | .[-1].suite // "none"' "$LOG" 2>/dev/null || printf 'err'; }
expect() { # LABEL WANT GOT
  if [[ "$3" == "$2" ]]; then assert_ok "$1" "$4"; else assert_bad "$1" "$4 (wanted $2, got $3)"; fi
}

# NOTE: helper names are redefined AFTER the sources below win — loop-bot's
# own ok/bad/log would otherwise shadow the counters. (Re-defined again post-source.)

# fixture FIRST, then bind + source the supervisor (REPO_DIR/STATE_DIR must
# exist before loop-bot-herd.sh reads the profile at source time)
mkdir -p "$RD"
git -C "$RD" init -q -b main
printf '.herdr-swarm/\n' > "$RD/.gitignore"
git -C "$RD" add -A; git -C "$RD" -c user.email=t@t -c user.name=t commit -q -m base
mkdir -p "$STATE" "$GATES" "$STATE/gate-logs"
printf 'REPO="foo/bar"\nTEST_CMD="sh ./gate.sh"\nECOSYSTEM="generic"\nDOCS_DIR="docs"\n' > "$STATE/profile.env"

export REPO_DIR="$RD" STATE_DIR="$STATE"

# shellcheck disable=SC1091  # supervisor under test (functions only via status)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/loop-bot-herd.sh" status >/dev/null 2>&1
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/worktree.sh"

# Every gate this suite exercises bounds its run with timeout(1), which macOS
# does not ship. Fail once with the remedy rather than cascading into a dozen
# failures that all blame the supervisor for a missing binary (DOG-15).
if ! resolve_timeout; then
  printf 'test_async_gate: cannot run — no runnable timeout(1) (remedy above)\n' >&2
  exit 1
fi

mk_seat() { # SEAT SLEEP_SECONDS [EXTRA_GATE_LINES]
  local prov wt
  prov=$(worktree_provision "$1" ag HEAD "$RD" 2>/dev/null)
  wt=$(sed -n 1p <<<"$prov")
  { printf '#!/bin/sh\n'; [[ -n "$2" && "$2" != 0 ]] && printf 'sleep %s\n' "$2"; printf '%s\n' "${3:-exit 0}"; } > "$wt/gate.sh"
  git -C "$wt" add -A; git -C "$wt" -c user.email=t@t -c user.name=t commit -q -m "seat $1 gate"
  printf '%s %s\n' "$wt" "$(git -C "$wt" rev-parse HEAD)"
}

read -r WTA SHA_A <<< "$(mk_seat seat-a 3)"
read -r WTB SHA_B <<< "$(mk_seat seat-b 1)"

ledger() { # writes v2 ledger with isolated seats
  jq -cn --arg a "$WTA" --arg b "$WTB" '{version: 2, workspace_id: "wT", seats: [
    {name: "seat-a", kind: "opencode", pane: "wT:p1", worktree_dir: $a, branch: "swarm/ag/seat-a", isolated: true},
    {name: "seat-b", kind: "opencode", pane: "wT:p2", worktree_dir: $b, branch: "swarm/ag/seat-b", isolated: true}]}' > "$STATE/seats.json"
}
ledger

VERDICT_A=""; VERDICT_B=""
herdr() {
  if [[ "${1:-}" == "agent" && "${2:-}" == "read" ]]; then
    [[ "${3:-}" == "seat-a" && -n "$VERDICT_A" ]] && printf '%s\n' "$VERDICT_A"
    [[ "${3:-}" == "seat-b" && -n "$VERDICT_B" ]] && printf '%s\n' "$VERDICT_B"
  fi
  return 0
}
EXPECTED_SEATS=(seat-a seat-b)
ctl_get paused >/dev/null   # materialize control.json (suite_gate default true)

echo "── async gate suite (scratch: $RD)"

# ── 1+12: concurrent gates, non-blocking scan ──────────────────────────────
GATE_CONCURRENCY=2
VERDICT_A="ARCH DONE #301 $SHA_A"
VERDICT_B="ARCH DONE #302 $SHA_B"
t0=$(date +%s%N 2>/dev/null || date +%s)
harvest_verdicts >/dev/null 2>&1
t1=$(date +%s%N 2>/dev/null || date +%s)
elapsed_ms=$(( (t1 - t0) / 1000000 ))
njobs=$(gate_running_count)
[[ "$njobs" == 2 ]] && assert_ok 1a "two gates spawned concurrently" || assert_bad 1a "two gates spawned (got $njobs)"
if (( elapsed_ms < 1500 )); then assert_ok 1b "scan is non-blocking (${elapsed_ms}ms with 3s gate running)"; else assert_bad 1b "scan blocked (${elapsed_ms}ms)"; fi
sleep 1.5
gate_reap >/dev/null 2>&1
b_state=$(last_suite_of 302); a_state=$(last_suite_of 301)
[[ "$b_state" == "green" ]] && assert_ok 1c "fast seat B recorded while slow seat A still gating" || assert_bad 1c "B reaped early (got $b_state)"
[[ "$a_state" == "none" ]] && assert_ok 1d "slow seat A not yet recorded (rc absent)" || assert_bad 1d "A premature (got $a_state)"
sleep 2.5
gate_reap >/dev/null 2>&1
expect 1e "$(last_suite_of 301)" green "slow seat A recorded after completion"

# ── 6: one job per (ticket, sha) across passes ─────────────────────────────
n301=$(jq -r -s '[.[] | select(.ticket == 301)] | length' "$LOG")
harvest_verdicts >/dev/null 2>&1   # verdict lines still visible in panes
harvest_verdicts >/dev/null 2>&1
sleep 0.5; gate_reap >/dev/null 2>&1
n301b=$(jq -r -s '[.[] | select(.ticket == 301)] | length' "$LOG")
[[ "$n301" == 1 && "$n301b" == 1 ]] && assert_ok 6 "same verdict across passes: one job, one record" || assert_bad 6 "dedupe (records $n301→$n301b)"

# ── 2: concurrency cap (gc=1) queues the excess verdict ────────────────────
GATE_CONCURRENCY=1
git -C "$WTA" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "a2"
SHA_A2=$(git -C "$WTA" rev-parse HEAD)
git -C "$WTB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "b2"
SHA_B2=$(git -C "$WTB" rev-parse HEAD)
VERDICT_A="ARCH DONE #303 $SHA_A2"
VERDICT_B="ARCH DONE #304 $SHA_B2"
harvest_verdicts >/dev/null 2>&1
running=$(gate_running_count)
[[ "$running" == 1 ]] && assert_ok 2a "cap=1: exactly one gate active" || assert_bad 2a "cap enforcement (running=$running)"
sleep 3.5; gate_reap >/dev/null 2>&1
harvest_verdicts >/dev/null 2>&1   # deferred verdict re-harvested
[[ "$(gate_running_count)" == 1 ]] && assert_ok 2b "deferred verdict spawns after slot frees" || assert_bad 2b "re-spawn"
sleep 2; gate_reap >/dev/null 2>&1
expect 2c "$(last_suite_of 304)" green "all capped verdicts eventually recorded"

# ── 5: post-drift invalidation survives backgrounding ─────────────────────
rm -f "$WTB/gate.sh"; printf '#!/bin/sh\ngit commit -q --allow-empty -m mid-run; exit 0\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -q -m selfmut
SHA_M=$(git -C "$WTB" rev-parse HEAD)
VERDICT_B="ARCH DONE #305 $SHA_M"; VERDICT_A=""
GATE_CONCURRENCY=2
harvest_verdicts >/dev/null 2>&1
sleep 1; gate_reap >/dev/null 2>&1
expect 5 "$(last_suite_of 305)" invalidated "worker commit during gate → invalidated despite rc=0"
git -C "$WTB" reset -q --hard HEAD   # ensure clean for later cases

# ── 7: timeout → RED (rc 124), slot released ──────────────────────────────
rm -f "$WTB/gate.sh"; printf '#!/bin/sh\nsleep 5\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -q -m slowgate
SHA_T=$(git -C "$WTB" rev-parse HEAD)
VERDICT_B="ARCH DONE #306 $SHA_T"
SUITE_TIMEOUT_S=1
harvest_verdicts >/dev/null 2>&1
sleep 2.5; gate_reap >/dev/null 2>&1
rec=$(jq -r -s '[.[] | select(.ticket == 306)] | .[-1]' "$LOG")
[[ "$(jq -r .suite <<<"$rec")" == "RED" && "$(jq -r .exit_code <<<"$rec")" == 124 ]] \
  && assert_ok 7 "timeout → RED with rc=124, slot released (running=$(gate_running_count))" \
  || assert_bad 7 "timeout handling ($rec)"
SUITE_TIMEOUT_S=300

# ── 4: crash safety — dead pid without rc discarded, never green ──────────
rm -f "$WTB/gate.sh"; printf '#!/bin/sh\nsleep 8\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -q -m crashgate
SHA_K=$(git -C "$WTB" rev-parse HEAD)
VERDICT_B="ARCH DONE #307 $SHA_K"
harvest_verdicts >/dev/null 2>&1
CRASH_PID=$(jq -r '.pid' "$STATE"/gates/seat-b-"${SHA_K:0:7}".job)
kill "$CRASH_PID" 2>/dev/null || true
sleep 0.3
REC_OUT=$(gate_recover 2>&1 || true)
if [[ -e "$STATE/gates/seat-b-${SHA_K:0:7}.job" ]]; then
  assert_bad 4a "dead-pid job discarded"
else
  printf '%s' "$REC_OUT" | grep -q "never assumed green" && assert_ok 4a "dead-pid job discarded with fail-closed warning" || assert_bad 4a "warning text"
fi
n307=$(jq -r -s '[.[] | select(.ticket == 307)] | length' "$LOG")
[[ "$n307" == 0 ]] && assert_ok 4b "no record invented for the killed job (no green)" || assert_bad 4b "phantom record ($n307)"
# re-harvest re-spawns cleanly
kill %1 2>/dev/null || true
harvest_verdicts >/dev/null 2>&1
[[ -e "$STATE/gates/seat-b-${SHA_K:0:7}.job" ]] && assert_ok 4c "verdict re-harvested after crash discard" || assert_bad 4c "re-spawn"
for j in "$STATE"/gates/*.job; do [[ -e "$j" ]] && kill "$(jq -r .pid "$j")" 2>/dev/null || true; done
sleep 0.3; gate_recover >/dev/null 2>&1 || true
rm -f "$STATE"/gates/*.rc

# ── 8: green isolated verdict → arbiter_enqueue exactly once ───────────────
rm -f "$WTB/gate.sh"; printf '#!/bin/sh\nexit 0\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -q -m fastgreen
SHA_G=$(git -C "$WTB" rev-parse HEAD)
VERDICT_B="ARCH DONE #308 $SHA_G"
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
nq=$(jq -s '[.[] | select(((.ticket|tostring) == "308") and .status == "queued")] | length' "$Q" 2>/dev/null || printf 0)   # queue stores string ids (#ARB-STR)
[[ "$nq" == 1 ]] && assert_ok 8 "green isolated verdict enqueued to arbiter exactly once" || assert_bad 8 "arbiter enqueue (n=$nq)"

# ── 3: gate_concurrency=0 = legacy inline ─────────────────────────────────
rm -f "$WTB/gate.sh"; printf '#!/bin/sh\n# inline variant\nexit 0\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -q -m inline
SHA_I=$(git -C "$WTB" rev-parse HEAD)
VERDICT_B="ARCH DONE #309 $SHA_I"
GATE_CONCURRENCY=0
harvest_verdicts >/dev/null 2>&1
inline_state=$(last_suite_of 309)
njobs_inline=$(find "$STATE/gates" -name '*.job' 2>/dev/null | wc -l | tr -d ' ')
[[ "$inline_state" == "green" ]] && assert_ok 3a "gc=0: verdict recorded synchronously (inline)" || assert_bad 3a "inline gate ($inline_state)"
[[ "$njobs_inline" == 0 ]] && assert_ok 3b "gc=0: no job files created" || assert_bad 3b "stray jobs ($njobs_inline)"
GATE_CONCURRENCY=2

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
