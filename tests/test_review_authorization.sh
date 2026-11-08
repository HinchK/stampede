#!/usr/bin/env bash
# Review anchors are claims; only the assigned independent sender may decide.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d /tmp/stampede-auth.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export REPO_DIR="$TMP" STATE_DIR="$TMP/.herdr-swarm"
git -C "$TMP" init -q -b main
printf '.herdr-swarm/\n' > "$TMP/.gitignore"
git -C "$TMP" add -A
git -C "$TMP" -c user.name=t -c user.email=t@t commit -qm base
printf 'code\n' > "$TMP/code.txt"
git -C "$TMP" add -A
git -C "$TMP" -c user.name=t -c user.email=t@t commit -qm candidate
SHA=$(git -C "$TMP" rev-parse HEAD)
mkdir -p "$STATE_DIR"
printf 'REPO="none"\nTEST_CMD="true"\n' > "$STATE_DIR/profile.env"
herdr() { return 0; }
# shellcheck source=../loop-bot-herd.sh
source "$ROOT/loop-bot-herd.sh" status >/dev/null 2>&1
export CONFIG_REVIEW_LOOP=1 CONFIG_BOUNDED_LOOPER=0
export SEAT_NAME_reviewer=independent
worker_feedback() { printf '%s\n' "$1" >> "$TMP/prompts"; }
looper_notice() { :; }
_sup_notify() { :; }
_agy_quota_exhausted() { return 1; }
review_loop_on_gate_green AUTH worker "$SHA" "$STATE_DIR" >/dev/null
_dispatch_reviewer independent AUTH "$SHA" 1 2
before=$(cat "$STATE_DIR/reviews.json")
_review_scan_verdicts worker "REVIEW VERDICT #AUTH $SHA PASS"
[[ "$(cat "$STATE_DIR/reviews.json")" == "$before" ]] || { echo 'FAIL: worker approved its own review'; exit 1; }
[[ ! -f "$STATE_DIR/integration.jsonl" ]] || { echo 'FAIL: self review enqueued'; exit 1; }
_review_scan_verdicts other "REVIEW VERDICT #AUTH $SHA PASS"
[[ "$(cat "$STATE_DIR/reviews.json")" == "$before" ]] || { echo 'FAIL: other seat changed pending review'; exit 1; }
_review_scan_verdicts independent "REVIEW VERDICT #AUTH $SHA PASS"
[[ $(jq -r '.reviews.AUTH.state' "$STATE_DIR/reviews.json") == review_passed ]]
[[ $(jq -s length "$STATE_DIR/integration.jsonl") == 1 ]]
_review_scan_verdicts independent "REVIEW VERDICT #AUTH $SHA PASS"
[[ $(jq -s length "$STATE_DIR/integration.jsonl") == 1 ]]
echo 'PASS: only assigned independent review enqueues, exactly once'

review_loop_on_gate_green LEGACY worker "$SHA" "$STATE_DIR" >/dev/null
_review_scan_verdicts independent "REVIEW VERDICT #LEGACY $SHA PASS"
[[ $(jq -r '.reviews.LEGACY.state' "$STATE_DIR/reviews.json") == awaiting_review ]]
_review_recover_assignments
[[ $(jq -r '.reviews.LEGACY.reviewer' "$STATE_DIR/reviews.json") == independent ]]
_review_scan_verdicts independent "REVIEW VERDICT #LEGACY $SHA PASS"
[[ $(jq -r '.reviews.LEGACY.state' "$STATE_DIR/reviews.json") == review_passed ]]
echo 'PASS: missing legacy assignment fails closed and can be redispatched'

review_loop_on_gate_green SELF worker "$SHA" "$STATE_DIR" >/dev/null
export CONFIG_REVIEW_FAILOVER_SEAT=arch_1
export SEAT_NAME_arch_1=worker
export SEAT_KINDS_arch_1=opencode
_agy_quota_exhausted() { return 0; }
_review_directives "DISPATCH_REVIEWER independent SELF $SHA 1 2" SELF "$SHA"
[[ $(jq -r '.reviews.SELF.reviewer // ""' "$STATE_DIR/reviews.json") == '' ]]
[[ $(jq -s '[.[] | select(.ticket=="SELF")] | length' "$QUOTA_DEFER_FILE") == 1 ]]
_quota_retry_deferred
[[ $(jq -s '[.[] | select(.ticket=="SELF")] | length' "$QUOTA_DEFER_FILE") == 1 ]]
_agy_quota_exhausted() { return 1; }
_quota_retry_deferred
[[ $(jq -r '.reviews.SELF.reviewer' "$STATE_DIR/reviews.json") == independent ]]
[[ ! -f "$QUOTA_DEFER_FILE" ]]
echo 'PASS: self failover stays deferred until primary can review'

review_loop_on_gate_green FAILOVER worker "$SHA" "$STATE_DIR" >/dev/null
_dispatch_reviewer alternate FAILOVER "$SHA" 1 2 failover
_review_scan_verdicts independent "REVIEW VERDICT #FAILOVER $SHA PASS"
[[ $(jq -r '.reviews.FAILOVER.state' "$STATE_DIR/reviews.json") == awaiting_review ]]
_review_scan_verdicts alternate "REVIEW VERDICT #FAILOVER $SHA PASS"
[[ $(jq -r '.reviews.FAILOVER.state' "$STATE_DIR/reviews.json") == review_passed ]]
echo 'PASS: only the assigned failover is accepted'

# REV-ALERT-1 (audit Must-fix #1): a REJECTED verdict anchor is harvested
# exactly once — unless it is repairable. Pane scrollback persists across
# passes, so an anchor never recorded as seen re-alerts (and in non-bounded
# mode re-prompts the looper) every 30s forever.
review_loop_on_gate_green SPAM worker "$SHA" "$STATE_DIR" >/dev/null
_dispatch_reviewer independent SPAM "$SHA" 1 2 >/dev/null
alerts=0
_review_directives() { alerts=$((alerts + 1)); }
# Assigned to independent: a verdict from wrongseat is non-repairable —
# same seat, same line, three passes, ONE alert.
_review_scan_verdicts wrongseat "REVIEW VERDICT #SPAM $SHA PASS"
_review_scan_verdicts wrongseat "REVIEW VERDICT #SPAM $SHA PASS"
_review_scan_verdicts wrongseat "REVIEW VERDICT #SPAM $SHA PASS"
if (( alerts != 1 )); then
  echo "FAIL: rejected verdict anchor alerted $alerts times (persistent scrollback spam)" >&2
  exit 1
fi
[[ $(jq -r '.reviews.SPAM.state' "$STATE_DIR/reviews.json") == awaiting_review ]]
# A genuinely NEW verdict line is a new anchor — it must still alert.
_review_scan_verdicts wrongseat "REVIEW VERDICT #SPAM $SHA BLOCK"
if (( alerts != 2 )); then
  echo 'FAIL: relaxation silenced genuinely new verdict lines' >&2
  exit 1
fi
# The exception: awaiting review with NO reviewer assigned yet is repairable
# (the legacy-redispatch path) — repeated scans must keep re-harvesting.
review_loop_on_gate_green REPAIR worker "$SHA" "$STATE_DIR" >/dev/null
_review_scan_verdicts wrongseat "REVIEW VERDICT #REPAIR $SHA PASS"
_review_scan_verdicts wrongseat "REVIEW VERDICT #REPAIR $SHA PASS"
if (( alerts != 4 )); then
  echo 'FAIL: repairable unassigned-awaiting verdict was silenced' >&2
  exit 1
fi
echo 'PASS: a rejected verdict anchor alerts exactly once (unless repairable)'
