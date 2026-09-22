#!/bin/bash
# tests/test_review_loop.sh — autonomous reviewer-loop state machine (REV-3)
#
# Hermetic by construction: the state machine never shells out (directives
# only), so no herdr/arbiter stubs are needed — every test asserts the
# durable state file plus the directive stream a caller would execute.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }
directive() { # OUTPUT LABEL DIRECTIVE — assert OUTPUT contains the directive line
  if printf '%s\n' "$1" | grep -qF "$3"; then ok "$2"; else bad "$2 (wanted: $3)"; fi
}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-revloop.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
SD="$SCRATCH/.herdr-swarm"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/lifecycle.sh"

unset CONFIG_REVIEW_LOOP CONFIG_REVIEW_MAX_ROUNDS SEAT_NAME_reviewer
export SEAT_NAME_reviewer="reviewer-test"
T="TICKET-9"
A1="aaaaaaa1111111111111111111111111111111111111111111111111111aa"
A2="bbbbbbb2222222222222222222222222222222222222222222222222222bb"
seat="arch-1"

state_of() { jq -r --arg t "$T" '.reviews[$t].state // "none"' "$SD/reviews.json"; }
round_of() { jq -r --arg t "$T" '.reviews[$t].round // 0' "$SD/reviews.json"; }

echo "==> review loop state machine (REV-3)"

# ── 1. loop disabled: gate green flows straight to enqueue ───────────────
out=$(CONFIG_REVIEW_LOOP=0 review_loop_on_gate_green "$T" "$seat" "$A1" "$SD") && rc=0 || rc=$?
[[ "$rc" == 0 ]] && ok "loop off: rc 0" || bad "loop off rc=$rc"
directive "$out" "loop off: ENQUEUE directive" "ENQUEUE $T $seat $A1"
[[ ! -f "$SD/reviews.json" ]] && ok "loop off: no state file written" || bad "loop off wrote state"

# ── 2. loop on: gate green -> awaiting_review round 1 + reviewer dispatch ─
export CONFIG_REVIEW_LOOP=1 CONFIG_REVIEW_MAX_ROUNDS=2
out=$(review_loop_on_gate_green "$T" "$seat" "$A1" "$SD") && rc=0 || rc=$?
[[ "$rc" == 0 ]] && ok "gate green rc 0" || bad "gate green rc=$rc"
directive "$out" "reviewer dispatched with round/max" "DISPATCH_REVIEWER reviewer-test $T $A1 1 2"
[[ "$(state_of)" == "awaiting_review" && "$(round_of)" == 1 ]] \
  && ok "state: awaiting_review round 1" || bad "state: $(state_of) r$(round_of)"

# ── 3. direct PASS -> review_passed + enqueue ─────────────────────────────
out=$(review_loop_on_review_verdict "$T" "$A1" PASS "$SD") && rc=0 || rc=$?
[[ "$rc" == 0 ]] && ok "PASS rc 0" || bad "PASS rc=$rc"
directive "$out" "PASS enqueues gated sha" "ENQUEUE $T $seat $A1"
[[ "$(state_of)" == "review_passed" ]] && ok "state: review_passed" || bad "state: $(state_of)"

# ── 4. full cycle: BLOCK r1 -> critique -> refine -> re-verdict -> PASS ───
out=$(review_loop_on_gate_green "$T" "$seat" "$A1" "$SD")
out=$(review_loop_on_review_verdict "$T" "$A1" BLOCK "$SD") && rc=0 || rc=$?
[[ "$rc" == 0 ]] && ok "BLOCK r1 rc 0" || bad "BLOCK rc=$rc"
directive "$out" "critique dispatched round 2/2" "DISPATCH_CRITIQUE $seat $T 2 2"
[[ "$(state_of)" == "critique_dispatched" && "$(round_of)" == 2 ]] \
  && ok "state: critique_dispatched round 2" || bad "state: $(state_of) r$(round_of)"
if printf '%s\n' "$out" | grep -qF "$SD/reviews/$T-$A1.md"; then
  ok "critique cites absolute findings path"
else
  bad "findings path missing: $out"
fi
out=$(review_loop_on_review_verdict "$T" "$A1" BLOCK "$SD")   # duplicate BLOCK: idempotent
directive "$out" "duplicate BLOCK re-delivers same round (no increment)" "DISPATCH_CRITIQUE $seat $T 2 2"
[[ "$(round_of)" == 2 ]] && ok "round not double-incremented" || bad "round drifted: $(round_of)"

out=$(review_loop_on_gate_green "$T" "$seat" "$A2" "$SD")      # refinement at new sha
directive "$out" "re-review dispatched at new sha, round carried" "DISPATCH_REVIEWER reviewer-test $T $A2 2 2"
[[ "$(state_of)" == "awaiting_review" && "$(round_of)" == 2 ]] \
  && ok "refinement: awaiting_review round 2" || bad "refine: $(state_of) r$(round_of)"
out=$(review_loop_on_review_verdict "$T" "$A2" PASS "$SD")
directive "$out" "round-2 PASS enqueues refined sha" "ENQUEUE $T $seat $A2"
[[ "$(state_of)" == "review_passed" ]] && ok "cycle complete: review_passed" || bad "cycle: $(state_of)"

# ── 5. persistent BLOCK: budget exhausted -> review_blocked, no enqueue ──
review_loop_on_gate_green "$T" "$seat" "$A1" "$SD" >/dev/null
review_loop_on_review_verdict "$T" "$A1" BLOCK "$SD" >/dev/null     # r1 -> critique r2
review_loop_on_gate_green "$T" "$seat" "$A2" "$SD" >/dev/null       # refine at sha2
out=$(review_loop_on_review_verdict "$T" "$A2" BLOCK "$SD") && rc=0 || rc=$?
[[ "$rc" == 0 ]] && ok "budget-exhausted BLOCK rc 0 (designed answer)" || bad "rc=$rc"
directive "$out" "ALERT_BLOCKED with budget" "ALERT_BLOCKED $T $A2 2 2"
if printf '%s\n' "$out" | grep -q "ENQUEUE"; then bad "blocked review must NOT enqueue"; else ok "no enqueue on blocked"; fi
[[ "$(state_of)" == "review_blocked" ]] && ok "state: review_blocked" || bad "state: $(state_of)"

# ── 6. corrupt / invalid verdicts fail closed ─────────────────────────────
review_loop_on_gate_green "$T" "$seat" "$A1" "$SD" >/dev/null
out=$(review_loop_on_review_verdict "$T" "$A1" MAYBE "$SD" 2>/dev/null) && rc=0 || rc=$?
[[ "$rc" == 1 ]] && ok "unknown verdict rc 1" || bad "unknown verdict rc=$rc"
directive "$out" "unknown verdict alerts" "ALERT_INVALID $T unknown-verdict:MAYBE"
[[ "$(state_of)" == "review_blocked" ]] && ok "unknown verdict blocks review" || bad "state: $(state_of)"

out=$(review_loop_on_review_verdict "$T" "$(printf 'c%.0s' {1..40})" PASS "$SD" 2>/dev/null) && rc=0 || rc=$?
[[ "$rc" == 1 ]] && ok "sha mismatch rc 1" || bad "mismatch rc=$rc"
directive "$out" "sha mismatch alerts with expected sha" "ALERT_INVALID $T sha-mismatch"

out=$(review_loop_on_review_verdict "GHOST-1" "$A1" PASS "$SD" 2>/dev/null) && rc=0 || rc=$?
[[ "$rc" == 1 ]] && ok "verdict for unknown ticket rc 1" || bad "ghost rc=$rc"

# ── 6b. missing state file: directive on STDOUT per the line-15 contract ──
rm -rf "$SCRATCH/fresh"
out=$(review_loop_on_review_verdict "$T" "$A1" PASS "$SCRATCH/fresh/.herdr-swarm" 2>/dev/null) && rc=0 || rc=$?
[[ "$rc" == 1 ]] && ok "no state file: rc 1" || bad "no-state rc=$rc"
directive "$out" "no-review-state alert flows through stdout" "ALERT_INVALID $T no-review-state"
[[ ! -f "$SCRATCH/fresh/.herdr-swarm/reviews.json" ]] \
  && ok "no-review-state does not create state" || bad "state created on invalid input"

# corrupt state file: reads fail, writes refuse, nothing enqueues
cp "$SD/reviews.json" "$SD/reviews.json.good"
printf '{"version":1,"reviews":{"BROKEN"' > "$SD/reviews.json"
out=$(review_loop_on_review_verdict "$T" "$A1" PASS "$SD" 2>/dev/null) && rc=0 || rc=$?
[[ "$rc" -ne 0 ]] && ok "corrupt state: non-zero exit" || bad "corrupt rc=$rc"
if printf '%s\n' "$out" | grep -q "ENQUEUE"; then bad "corrupt state must not enqueue"; else ok "corrupt state: no enqueue"; fi
mv "$SD/reviews.json.good" "$SD/reviews.json"

# ── 7. --no-review-loop override outranks config ──────────────────────────
printf '0\n' > "$SD/review-loop.override"
out=$(review_loop_on_gate_green "$T" "$seat" "$A1" "$SD")
directive "$out" "override file disables loop despite config=1" "ENQUEUE $T $seat $A1"
[[ "$(review_loop_enabled "$SD")" == 0 ]] && ok "review_loop_enabled honours override" || bad "enabled=$(review_loop_enabled "$SD")"
rm -f "$SD/review-loop.override"
out=$(review_loop_on_gate_green "$T" "$seat" "$A1" "$SD")
directive "$out" "override removal restores config=1" "DISPATCH_REVIEWER reviewer-test $T $A1"

# ── 8. status output ──────────────────────────────────────────────────────
out=$(review_loop_status "$SD")
[[ "$out" == *"enabled (max_rounds 2)"* ]] && ok "status: enabled + budget" || bad "status: $out"
[[ "$out" == *"$T"* ]] && ok "status lists ticket rows" || bad "status missing ticket"
printf '0\n' > "$SD/review-loop.override"
out=$(review_loop_status "$SD")
[[ "$out" == *"disabled"* && "$out" == *"override: 0"* ]] && ok "status: override surfaced" || bad "status: $out"

# ── 9. launcher flag wiring (parser + help + bin/stampede passthrough) ────
help_out=$("$REPO_ROOT/herdr-loop-swarm.sh" -h 2>&1)
[[ "$help_out" == *"--no-review-loop"* ]] && ok "launcher help documents --no-review-loop" || bad "help missing flag"
grep -q 'CLI_NO_REVIEW_LOOP=1' "$REPO_ROOT/herdr-loop-swarm.sh" \
  && ok "launcher parser sets the override flag" || bad "parser arm missing"
grep -q 'review-loop.override' "$REPO_ROOT/herdr-loop-swarm.sh" \
  && ok "launcher writes the durable override marker" || bad "override write missing"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
