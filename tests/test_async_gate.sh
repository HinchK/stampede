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
last_suite_of() { jq -r -s --arg t "$1" '[.[] | select((.ticket | tostring) == $t)] | .[-1].suite // "none"' "$LOG" 2>/dev/null || printf 'err'; }
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

# PROVE-2 flipped the shipped default (reviewer.loop = true), and the
# source-time `eval config_env` above binds CONFIG_REVIEW_LOOP from the repo's
# swarm.config.toml. Sections 1–12 assert the pre-review ambient (loop off →
# ENQUEUE) and §13 toggles the loop explicitly per scenario, so pin the ambient
# here: the suite must stay hermetic against the shipping default in either
# direction (off before PROVE-2, on after).
export CONFIG_REVIEW_LOOP=0

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
# [1b] budget is self-calibrating (the DOG-15 lesson applied to timing): the
# scan's own cost is spawn-dominated (gate jobs, jq, partition/lease checks
# since DOG-16), so a fixed 1500ms wall-clock budget fabricates a "blocked"
# verdict on any machine busy enough — like this one whenever the herd runs.
# We measure one reference spawn (sleep 0.05 under contention ≈ hundreds of
# ms; ≈50ms idle) and scale the budget. The scan chains roughly ten
# subprocess spawns (2 gate jobs, partition/lease checks, jq/ledger writes),
# so the budget carries a 10× spawn multiplier; a blocking wait is one full
# 3s gate PLUS those spawns and still exceeds it. [1a] remains the
# load-independent blocking detector: a blocked scan returns after the gates
# finish, so gate_running_count collapses.
now_ms() { perl -MTime::HiRes -e 'print int(Time::HiRes::time()*1000)'; }
command -v perl >/dev/null 2>&1 || now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
GATE_CONCURRENCY=2
VERDICT_A="ARCH DONE #301 $SHA_A"
VERDICT_B="ARCH DONE #302 $SHA_B"
r0=$(now_ms); sleep 0.05; r1=$(now_ms)
ref_spawn=$(( r1 - r0 ))
budget_ms=$(( 1500 + 10 * ref_spawn ))
t0=$(now_ms)
harvest_verdicts >/dev/null 2>&1
t1=$(now_ms)
elapsed_ms=$(( t1 - t0 ))
njobs=$(gate_running_count)
[[ "$njobs" == 2 ]] && assert_ok 1a "two gates spawned concurrently" || assert_bad 1a "two gates spawned (got $njobs)"
if (( elapsed_ms < budget_ms )); then assert_ok 1b "scan is non-blocking (${elapsed_ms}ms < ${budget_ms}ms budget, ref spawn ${ref_spawn}ms, 3s gate running)"; else assert_bad 1b "scan blocked (${elapsed_ms}ms ≥ ${budget_ms}ms budget, ref spawn ${ref_spawn}ms)"; fi
sleep 1.5
gate_reap >/dev/null 2>&1
b_state=$(last_suite_of 302); a_state=$(last_suite_of 301)
[[ "$b_state" == "green" ]] && assert_ok 1c "fast seat B recorded while slow seat A still gating" || assert_bad 1c "B reaped early (got $b_state)"
[[ "$a_state" == "none" ]] && assert_ok 1d "slow seat A not yet recorded (rc absent)" || assert_bad 1d "A premature (got $a_state)"
sleep 2.5
gate_reap >/dev/null 2>&1
expect 1e "$(last_suite_of 301)" green "slow seat A recorded after completion"

# ── 6: one job per (ticket, sha) across passes ─────────────────────────────
n301=$(jq -r -s '[.[] | select((.ticket | tostring) == "301")] | length' "$LOG")
harvest_verdicts >/dev/null 2>&1   # verdict lines still visible in panes
harvest_verdicts >/dev/null 2>&1
sleep 0.5; gate_reap >/dev/null 2>&1
n301b=$(jq -r -s '[.[] | select((.ticket | tostring) == "301")] | length' "$LOG")
[[ "$n301" == 1 && "$n301b" == 1 ]] && assert_ok 6 "same verdict across passes: one job, one record" || assert_bad 6 "dedupe (records ${n301} to ${n301b})"

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
rec=$(jq -r -s '[.[] | select((.ticket | tostring) == "306")] | .[-1]' "$LOG")
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

# ── 13: review loop wiring (REV-5) ─────────────────────────────────────────
# The machine directives executed by the supervisor: loop off = ENQUEUE (the
# pre-REV-5 behavior, now with string ticket ids end-to-end); loop on =
# reviewer dispatch on green, verdict harvesting drives PASS→enqueue and
# BLOCK→critique. herdr stub extended to RECORD prompts (the observable side
# of DISPATCH directives) and serve the reviewer seat's pane.
PROMPTS="$TEST_DIR/prompts.log"; : > "$PROMPTS"
READS="$TEST_DIR/herdr-reads.log"; : > "$READS"
herdr() {
  if [[ "${1:-}" == "agent" && "${2:-}" == "read" ]]; then
    printf 'read %s\n' "$3" >> "$READS"
    [[ "${3:-}" == "seat-a" && -n "$VERDICT_A" ]] && printf '%s\n' "$VERDICT_A"
    [[ "${3:-}" == "seat-b" && -n "$VERDICT_B" ]] && printf '%s\n' "$VERDICT_B"
    [[ "${3:-}" == "seat-r" && -n "$VERDICT_R" ]] && printf '%s\n' "$VERDICT_R"
  fi
  if [[ "${1:-}" == "agent" && "${2:-}" == "prompt" ]]; then
    printf '%s :: %s\n' "$3" "$4" >> "$PROMPTS"
  fi
  return 0
}
export SEAT_NAME_reviewer="seat-r"
EXPECTED_SEATS+=(seat-r)
qcount() { jq -s --arg t "$1" --arg s "$2" '[.[] | select(.ticket == $t and .sha == $s and .status == "queued")] | length' "$Q" 2>/dev/null || printf '0'; }
rstate() { jq -r --arg t "$1" '.reviews[$t].state // "none"' "$STATE/reviews.json" 2>/dev/null || printf 'none'; }

# [13a] loop OFF + string ticket: green → direct enqueue, no review state
export CONFIG_REVIEW_LOOP=0 CONFIG_REVIEW_MAX_ROUNDS=2
rm -f "$WTB/gate.sh"; printf '#!/bin/sh\n# rev5 compat\nexit 0\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -q -m rev5compat
SHA_RC=$(git -C "$WTB" rev-parse HEAD)
VERDICT_A=""; VERDICT_B="ARCH DONE #REV-9 $SHA_RC"; VERDICT_R=""
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
[[ "$(qcount REV-9 "$SHA_RC")" == 1 ]] \
  && assert_ok 13a "loop off: string ticket REV-9 green → enqueued (backward compat)" \
  || assert_bad 13a "loop off enqueue (n=$(qcount REV-9 "$SHA_RC"))"
[[ ! -f "$STATE/reviews.json" ]] && assert_ok 13a2 "loop off: no review state written" || assert_bad 13a2 "state leaked with loop off"

# [13b] loop ON: green → awaiting_review + reviewer dispatch, NO enqueue
export CONFIG_REVIEW_LOOP=1
git -C "$WTB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m rev5b
SHA_RD=$(git -C "$WTB" rev-parse HEAD)
VERDICT_B="ARCH DONE #REV-10 $SHA_RD"
: > "$PROMPTS"
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
[[ "$(rstate REV-10)" == "awaiting_review" ]] \
  && assert_ok 13b "loop on: green → awaiting_review" || assert_bad 13b "state $(rstate REV-10)"
[[ "$(qcount REV-10 "$SHA_RD")" == 0 ]] \
  && assert_ok 13b2 "loop on: gated sha NOT enqueued pending review" || assert_bad 13b2 "enqueued before review"
grep -q "seat-r :: DISPATCH: Review #REV-10 @ ${SHA_RD} (round 1/2)" "$PROMPTS" \
  && assert_ok 13b3 "reviewer seat prompted with round/max" || assert_bad 13b3 "no reviewer prompt: $(cat "$PROMPTS")"
grep -q '"event_type": "review.dispatched"' "$STATE"/traces/*.jsonl 2>/dev/null \
  && assert_ok 13b4 "review.dispatched telemetry emitted" || assert_bad 13b4 "no dispatched telemetry"

# [13c] reviewer PASS → review_passed + enqueue (exactly once across passes)
VERDICT_R="REVIEW VERDICT #REV-10 $SHA_RD PASS"
harvest_verdicts >/dev/null 2>&1
[[ "$(rstate REV-10)" == "review_passed" ]] \
  && assert_ok 13c "PASS → review_passed" || assert_bad 13c "state $(rstate REV-10)"
[[ "$(qcount REV-10 "$SHA_RD")" == 1 ]] \
  && assert_ok 13c2 "PASS → arbiter enqueued" || assert_bad 13c2 "enqueue on pass (n=$(qcount REV-10 "$SHA_RD"))"
grep -q '"event_type": "review.verdict"' "$STATE"/traces/*.jsonl 2>/dev/null \
  && assert_ok 13c3 "review.verdict telemetry emitted" || assert_bad 13c3 "no verdict telemetry"
harvest_verdicts >/dev/null 2>&1   # scrollback still shows the anchor...
[[ "$(qcount REV-10 "$SHA_RD")" == 1 ]] \
  && assert_ok 13c4 "seen-file dedup: re-harvest does not double-enqueue" || assert_bad 13c4 "double enqueue"

# [13d] reviewer BLOCK → critique dispatch to implementer, no enqueue
git -C "$WTB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m rev5d
SHA_RE=$(git -C "$WTB" rev-parse HEAD)
VERDICT_B="ARCH DONE #REV-11 $SHA_RE"; VERDICT_R=""
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
mkdir -p "$STATE/reviews"
printf '[BLOCK] lib/x.sh:42 — unvalidated input → validate before use\n[CONCERNS] tests/x.sh:7 — weak assertion\n' \
  > "$STATE/reviews/REV-11-$SHA_RE.md"
VERDICT_R="REVIEW VERDICT #REV-11 $SHA_RE BLOCK"
: > "$PROMPTS"
harvest_verdicts >/dev/null 2>&1
[[ "$(rstate REV-11)" == "critique_dispatched" ]] \
  && assert_ok 13d "BLOCK → critique_dispatched" || assert_bad 13d "state $(rstate REV-11)"
grep -q "seat-b :: DISPATCH CRITIQUE: #REV-11 round 2/2 — see ${STATE}/reviews/REV-11-${SHA_RE}.md" "$PROMPTS" \
  && assert_ok 13d2 "implementer prompted with critique + findings path" || assert_bad 13d2 "no critique prompt: $(cat "$PROMPTS")"
[[ "$(qcount REV-11 "$SHA_RE")" == 0 ]] \
  && assert_ok 13d3 "blocked-under-budget sha NOT enqueued" || assert_bad 13d3 "enqueued on block"
grep -q '"recipient": "seat-b"' "$STATE"/traces/*.jsonl 2>/dev/null \
  && assert_ok 13d4 "review.critique telemetry names recipient" || assert_bad 13d4 "no critique telemetry"
grep -q '"findings_count": 2' "$STATE"/traces/*.jsonl 2>/dev/null \
  && assert_ok 13d5 "verdict telemetry counts findings from the evidence file" || assert_bad 13d5 "findings_count wrong"

# [13e] supervisor sources cleanly under TERM=dumb (tput hardening receipt)
RROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dumb_rc=0
( cd "$RROOT" && TERM=dumb bash -c 'set -euo pipefail; REPO_DIR="$REPO_DIR" STATE_DIR="$STATE_DIR" source ./loop-bot-herd.sh status' ) >/dev/null 2>&1 || dumb_rc=$?
[[ "$dumb_rc" == 0 ]] && assert_ok 13e "supervisor sources cleanly under TERM=dumb" || assert_bad 13e "TERM=dumb source rc=$dumb_rc"
unset CONFIG_REVIEW_LOOP SEAT_NAME_reviewer

# ── 14: headless harvest wiring (HEADLESS-4) ────────────────────────────────
# Verdicts read from logs/<seat>.log (lib/headless.sh harness) instead of
# `herdr agent read`; gate + downstream identical; worker feedback becomes a
# headless_spawn critique turn; looper notices become durable log lines.
# Stub vendor CLI per HEADLESS-3's suite: bin-dir script recording its argv.
HB_BIN="$TEST_DIR/hb-bin"; mkdir -p "$HB_BIN"
printf '#!/bin/sh\nprintf "argv=%%s cwd=%%s\\n" "$*" "$(pwd)" >> "%s"\nsleep "${HB_STUB_SLEEP:-0.3}"\nexit "${HB_STUB_RC:-0}"\n' \
  "$TEST_DIR/hb-argv.log" > "$HB_BIN/opencode"
chmod +x "$HB_BIN/opencode"
export PATH="$HB_BIN:$PATH"
mkdir -p "$STATE/logs"

# [14a] headless green: log-scraped verdict, gate identical, enqueued
: > "$READS"
SHA_H1=$(git -C "$WTB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m headless1 && git -C "$WTB" rev-parse HEAD)
printf 'worker chatter\nARCH DONE #H-1 %s\n' "$SHA_H1" > "$STATE/logs/seat-b.log"
VERDICT_B=""   # pane read must not be the source here
export HEADLESS_MODE=1
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
[[ "$(last_suite_of H-1)" == "green" ]] \
  && assert_ok 14a "headless: log verdict gated green" || assert_bad 14a "headless green ($(last_suite_of H-1))"
[[ ! -s "$READS" ]] \
  && assert_ok 14a2 "headless: no herdr agent read issued" || assert_bad 14a2 "pane read leaked: $(cat "$READS")"
[[ "$(qcount H-1 "$SHA_H1")" == 1 ]] \
  && assert_ok 14a3 "headless green enqueues exactly like pane mode" || assert_bad 14a3 "enqueue ($(qcount H-1 "$SHA_H1"))"

# [14b] headless RED: critique turn via headless_spawn, not PTY injection
: > "$PROMPTS"; : > "$TEST_DIR/hb-argv.log"
printf '#!/bin/sh\nexit 3\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -qm headlessred
SHA_H2=$(git -C "$WTB" rev-parse HEAD)
printf 'ARCH DONE #H-2 %s\n' "$SHA_H2" > "$STATE/logs/seat-b.log"
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
[[ "$(last_suite_of H-2)" == "RED" ]] \
  && assert_ok 14b "headless RED recorded by the same gate" || assert_bad 14b "headless RED ($(last_suite_of H-2))"
CRIT_BRIEF="$STATE/briefs/seat-b-H-2-${SHA_H2}-red.md"
# the critique turn is a BACKGROUND spawn — give the vendor stub a beat to
# exec and record its argv before asserting on it (race observed 2026-09-24:
# identical code flaked here purely on scheduling)
sleep 0.5
[[ -f "$CRIT_BRIEF" ]] \
  && assert_ok 14b2 "RED feedback written as a critique brief" || assert_bad 14b2 "no critique brief at $CRIT_BRIEF"
grep -q "ARCH DONE #H-2" "$CRIT_BRIEF" && grep -q "suite is RED" "$CRIT_BRIEF" \
  && assert_ok 14b3 "critique brief carries re-verdict protocol + reason" || assert_bad 14b3 "critique brief content"
grep -q "BRIEF (file): $CRIT_BRIEF" "$TEST_DIR/hb-argv.log" \
  && assert_ok 14b4 "critique delivered via headless_spawn (vendor argv)" || assert_bad 14b4 "vendor argv: $(cat "$TEST_DIR/hb-argv.log")"
! grep -q "seat-b :: LOOP-BOT.*RED" "$PROMPTS" \
  && assert_ok 14b5 "no PTY prompt injected for RED in headless mode" || assert_bad 14b5 "herdr prompt leaked: $(cat "$PROMPTS")"
sleep 0.5   # let the stub vendor exit before the next spawn guard

# [14c] headless skipped-verdict: looper notice durable, no pane prompt
: > "$PROMPTS"
printf 'ARCH DONE #H-3 deadbeefdeadbeef\n' > "$STATE/logs/seat-b.log"
harvest_verdicts >/dev/null 2>&1
[[ "$(last_suite_of H-3)" == "skipped" ]] \
  && assert_ok 14c "fabricated sha still skipped (fail-closed unchanged)" || assert_bad 14c "H-3 $(last_suite_of H-3)"
[[ -f "$STATE/headless-notices.log" ]] && grep -q "absent from the repo" "$STATE/headless-notices.log" \
  && assert_ok 14c2 "looper notice durably logged (no swallowed alert)" || assert_bad 14c2 "no durable notice"
! grep -q "looper ::" "$PROMPTS" \
  && assert_ok 14c3 "no herdr prompt to looper in headless mode" || assert_bad 14c3 "looper prompt leaked"

# [14e] headless re-verdict ceiling (HEADLESS-5): second conclusive RED for
# the same ticket → DEAD_LETTER, lease released, NO third critique spawn.
export CONFIG_HEADLESS_MAX_ATTEMPTS=2
printf '#!/bin/sh\nexit 3\n' > "$WTB/gate.sh"   # still the failing gate
git -C "$WTB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m dl1
SHA_H4=$(git -C "$WTB" rev-parse HEAD)
printf 'ARCH DONE #H-4 %s\n' "$SHA_H4" > "$STATE/logs/seat-b.log"
printf '{"version":1,"leases":[{"ticket":"H-4","seat":"seat-b","paths":[]}]}\n' > "$STATE/leases.json"
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
[[ "$(last_suite_of H-4)" == "RED" ]] \
  && assert_ok 14e1 "attempt 1: RED critiques as usual" || assert_bad 14e1 "attempt 1 ($(last_suite_of H-4))"
grep -q '"ticket":"H-4"' "$STATE/leases.json" 2>/dev/null \
  && assert_ok 14e2 "lease held while attempts remain" || assert_bad 14e2 "lease missing mid-retries"
sleep 0.5
: > "$TEST_DIR/hb-argv.log"
git -C "$WTB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m dl2
SHA_H5=$(git -C "$WTB" rev-parse HEAD)
printf 'ARCH DONE #H-4 %s\n' "$SHA_H5" > "$STATE/logs/seat-b.log"
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
[[ "$(last_suite_of H-4)" == "dead_letter" ]] \
  && assert_ok 14e3 "attempt 2 at ceiling: DEAD_LETTER recorded" || assert_bad 14e3 "attempt 2 ($(last_suite_of H-4))"
jq -e -s 'any(.[]; .ticket == "H-4" and .reason != "")' "$STATE/dead-letter.jsonl" >/dev/null 2>&1 \
  && assert_ok 14e4 "dead-letter.jsonl carries the structured record" || assert_bad 14e4 "no dead-letter record"
! grep -q '"ticket":"H-4"' "$STATE/leases.json" 2>/dev/null \
  && assert_ok 14e5 "DEAD_LETTER released the lease" || assert_bad 14e5 "lease still held"
[[ ! -s "$TEST_DIR/hb-argv.log" ]] \
  && assert_ok 14e6 "no critique spawn past the ceiling" || assert_bad 14e6 "spawned anyway: $(cat "$TEST_DIR/hb-argv.log")"
unset CONFIG_HEADLESS_MAX_ATTEMPTS

# [14f] in-batch drain + lease release (HL-RED-1, receipt F5): greens must
# not sit queued and leases must not outlive integration — the step the
# headless batch now runs after every concluded ticket (and the CLI e2e in
# tests/test_cli.sh exercises through the full batch).
printf '#!/bin/sh\nexit 0\n' > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -q -m gate0
# clean queue first: earlier sections left stale queued records whose
# fixture trees conflict head-of-line (drain stops there, by design — that
# is the parked arbiter-batch-integration ticket's concern, not this step's)
if [[ -f "$Q" ]]; then
  jq -s -c 'map(select(.status != "queued")) | .[]' "$Q" > "$Q.tmp" && mv "$Q.tmp" "$Q"
fi
SHA_H9=$(git -C "$WTB" rev-parse HEAD)
arbiter_enqueue H-9 seat-b "$SHA_H9" >/dev/null 2>&1
printf '{"version":1,"leases":[{"ticket":"H-9","seat":"seat-b","paths":[]}]}\n' > "$STATE/leases.json"
out14f=$(headless_drain_and_release 2>&1 || true)
h9st=$(jq -r -s --arg t H-9 '[.[] | select((.ticket|tostring) == $t)] | .[-1].status // "none"' "$Q" 2>/dev/null)
[[ "$h9st" == "integrated" ]] \
  && assert_ok 14f "in-batch step drains queued records to integrated" || assert_bad 14f "H-9 status: $h9st"
! grep -q '"ticket":"H-9"' "$STATE/leases.json" 2>/dev/null \
  && assert_ok 14f2 "integrated lease released in the same step" || assert_bad 14f2 "lease still held"
grep -q "arbiter: #H-9 integrated" <<<"$out14f" \
  && assert_ok 14f3 "drain outcome surfaced in the step output" || assert_bad 14f3 "no drain line: $out14f"

# [14d] pane mode untouched by all of the above
unset HEADLESS_MODE
VERDICT_A=""
harvest_verdicts >/dev/null 2>&1
[[ -s "$READS" ]] \
  && assert_ok 14d "pane mode still reads via herdr agent read" || assert_bad 14d "pane read missing"

# ── 15: integer-isolated ledger values (SUPER-1) ───────────────────────────
# The launcher wrote `"isolated": 1` (integer) while every reader compared
# against "true" — green suites on isolated seats then never reached the
# review seam / arbiter enqueue. Prove the integer shape flows through
# resolve → spawn → reap → ENQUEUE with the launcher's own ledger shape.
ledger_int() { # same v2 ledger, isolated as INTEGER 1 — the launcher's shape
  jq -cn --arg a "$WTA" --arg b "$WTB" '{version: 2, workspace_id: "wT", seats: [
    {name: "seat-a", kind: "opencode", pane: "wT:p1", worktree_dir: $a, branch: "swarm/ag/seat-a", isolated: 1},
    {name: "seat-b", kind: "opencode", pane: "wT:p2", worktree_dir: $b, branch: "swarm/ag/seat-b", isolated: 1}]}' > "$STATE/seats.json"
}
ledger_int
export HEADLESS_MODE=1
printf '#!/bin/sh\nprintf "%%s\\n" "$PWD" > "%s/gate-cwd.txt"\nexit 0\n' "$STATE" > "$WTB/gate.sh"
git -C "$WTB" add -A; git -C "$WTB" -c user.email=t@t -c user.name=t commit -qm intgate
SHA_I1=$(git -C "$WTB" rev-parse HEAD)
printf 'ARCH DONE #I-1 %s\n' "$SHA_I1" > "$STATE/logs/seat-b.log"
harvest_verdicts >/dev/null 2>&1
sleep 0.6; gate_reap >/dev/null 2>&1
sleep 0.5   # settle: ENQUEUE directives run inside the reap pass
[[ "$(last_suite_of I-1)" == "green" ]] \
  && assert_ok 15a "integer-isolated seat gates green" || assert_bad 15a "green ($(last_suite_of I-1))"
[[ "$(qcount I-1 "$SHA_I1")" == 1 ]] \
  && assert_ok 15b "integer-isolated green reaches the arbiter queue (review seam ran)" \
  || assert_bad 15b "enqueue n=$(qcount I-1 "$SHA_I1")"
[[ "$(cat "$STATE/gate-cwd.txt" 2>/dev/null)" == "$WTB" ]] \
  && assert_ok 15c "integer-isolated seat gated in its worktree, not root" \
  || assert_bad 15c "gate ran in: $(cat "$STATE/gate-cwd.txt" 2>/dev/null)"
unset HEADLESS_MODE

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
