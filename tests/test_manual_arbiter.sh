#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/.herdr-swarm"
printf 'REPO=local/repo\nTEST_CMD=make test\n' > "$TMP/repo/.herdr-swarm/profile.env"
export REPO_DIR="$TMP/repo" STATE_DIR="$TMP/repo/.herdr-swarm"

# Source without starting the watcher, replace all other pass functions, and
# prove one ordinary pass never invokes the drain seam.
# shellcheck source=/dev/null
source "$ROOT/loop-bot-herd.sh" status >/dev/null
touch "$STATE_DIR/seat-only"
export CONFIG_BOUNDED_LOOPER=1

# shellcheck disable=SC2034  # read by the sourced health_pass function
EXPECTED_SEATS=(arch-test)
printf '{"leases":[{"ticket":"9","seat":"arch-test"}]}' > "$STATE_DIR/leases.json"
herdr() { [[ "$*" == 'agent list' ]] && printf '%s\n' '{"result":{"agents":[{"name":"arch-test","agent_status":"blocked"}]}}'; }
attention_event() { echo "$*" >> "$TMP/health-attention"; }
health_out=$(health_pass 2>&1)
grep -q '^blocked 9 Herdr reports arch-test blocked arch-test$' "$TMP/health-attention" \
  || { echo 'blocked worker did not pause its leased ticket' >&2; exit 1; }
[[ "$health_out" != *ollama* ]] || { echo 'bounded health still probes deferred local model' >&2; exit 1; }

PYTHON_BIN="$TMP/attention-spy"
printf '#!/bin/sh\necho called >> "%s"\n' "$TMP/attention-calls" > "$PYTHON_BIN"
chmod +x "$PYTHON_BIN"
frontier_drain
[[ ! -f "$TMP/attention-calls" ]] || { echo 'seat-only mode inspected and dispatched tickets' >&2; exit 1; }

rm -f "$STATE_DIR/seat-only"
printf 'REPO=none\nTEST_CMD=make test\n' > "$STATE_DIR/profile.env"
# shellcheck disable=SC2034  # read by the sourced frontier_drain function
REPO=none
printf '17\n' > "$STATE_DIR/active-map"
printf '{"paused": false, "frontier_drain": false, "suite_gate": true}\n' > "$STATE_DIR/control.json"
cat > "$PYTHON_BIN" <<EOF
#!/bin/sh
case "\$*" in
  *' mode '*) printf 'medium\n' ;;
  *' next '*) printf '18\n'; echo next >> "$TMP/attention-calls" ;;
  *' event '*) printf '%s\n' '{"status":"dispatched"}'; echo event >> "$TMP/attention-calls" ;;
esac
EOF
chmod +x "$PYTHON_BIN"
frontier_drain
grep -q next "$TMP/attention-calls" || { echo 'local map intake never ran when REPO=none' >&2; exit 1; }
grep -qx 'new 18 map:17' "$TMP/health-attention" || { echo 'local map intake did not dispatch' >&2; exit 1; }
held_lines=$(wc -l < "$TMP/health-attention")
touch "$STATE_DIR/intake-hold"
: > "$TMP/attention-calls"
frontier_drain
[[ ! -s "$TMP/attention-calls" ]] || { echo 'intake-hold did not stop local map inspection' >&2; exit 1; }
[[ "$(wc -l < "$TMP/health-attention")" -eq "$held_lines" ]] || { echo 'intake-hold did not stop local map dispatch' >&2; exit 1; }
rm -f "$STATE_DIR/intake-hold"

# GREEN becomes arbiter-ready only after the review machine emits ENQUEUE.
_agy_quota_exhausted() { return 1; }
_dispatch_reviewer() { echo reviewer >> "$TMP/review-calls"; }
arbiter_enqueue() { echo queued >> "$TMP/enqueue-calls"; }
attention_event() { echo "$*" >> "$TMP/green-calls"; }
herdr() { echo "$*" >> "$TMP/herdr-calls"; }
worker_feedback reviewer 9 abc1234 review-r 'review this commit'
grep -q 'agent prompt reviewer review this commit' "$TMP/herdr-calls" \
  || { echo 'reviewer prompt swallowed by attention policy' >&2; exit 1; }
[[ ! -f "$TMP/green-calls" ]] || { echo 'reviewer dispatch falsely blocked ticket' >&2; exit 1; }
_review_directives 'DISPATCH_REVIEWER reviewer 9 abc1234 1 2' 9 abc1234
[[ ! -f "$TMP/green-calls" ]] || { echo 'premature arbiter-ready notice during review' >&2; exit 1; }
_review_directives 'ENQUEUE 9 arch-test abc1234' 9 abc1234
[[ -f "$TMP/enqueue-calls" && -f "$TMP/green-calls" ]] \
  || { echo 'arbiter-ready notice missing after enqueue' >&2; exit 1; }

_quota_retry_deferred() { :; }
gate_recover() { :; }
health_pass() { :; }
harvest_verdicts() { :; }
gate_reap() { :; }
lease_release_integrated() { :; }
unpushed_watch() { :; }
credits_watch() { :; }
frontier_drain() { :; }
arbiter_auto_drain() { echo called >> "$TMP/drain-calls"; }
cmd_once
[[ ! -f "$TMP/drain-calls" ]] || { echo 'supervisor auto-drained an arbiter candidate' >&2; exit 1; }

# A ticket dispatch starts the worker from integrated work: an isolated seat's
# checkout is fast-forwarded to the integration tip, a diverged one is refused
# before any lease or prompt, and a root anchor is never moved.
G="$TMP/git"
gcommit() { git -C "$1" -c user.name=Test -c user.email=test@example.com commit -qm "$2"; }
git init -q -b main "$G"
printf 'base\n' > "$G/base.txt"; git -C "$G" add base.txt; gcommit "$G" base
W1="$TMP/w1" W2="$TMP/w2"
git -C "$G" worktree add -q -b swarm/test/arch_1 "$W1"
git -C "$G" worktree add -q -b swarm/test/arch_2 "$W2"
printf 'mine\n' > "$W2/mine.txt"; git -C "$W2" add mine.txt; gcommit "$W2" 'unintegrated work'
git -C "$G" checkout -q --detach
printf 'predecessor\n' > "$G/pred.txt"; git -C "$G" add pred.txt; gcommit "$G" 'integrated predecessor'
git -C "$G" branch swarm/test/integration
git -C "$G" checkout -q main
# shellcheck disable=SC2034  # read by the sourced dispatch_sync_worker function
REPO_DIR="$G" STATE_DIR="$TMP/sync-state" CHANNEL_DIR="$TMP/sync-channel" SWARM_CONFIG_NAME=test
mkdir -p "$STATE_DIR" "$CHANNEL_DIR"
printf '{"seats":[{"name":"arch-1-test","isolated":true,"worktree_dir":"%s"},{"name":"arch-2-test","isolated":true,"worktree_dir":"%s"},{"name":"pm-test","isolated":false,"worktree_dir":"%s"}]}' \
  "$W1" "$W2" "$G" > "$STATE_DIR/seats.json"
printf 'brief\n' > "$TMP/sync-brief.md"
dispatch_partition_guard() { echo "$1" >> "$TMP/sync-leases"; }
herdr() { echo "$*" >> "$TMP/sync-prompts"; }
main_before=$(git -C "$G" rev-parse main)
( cmd_dispatch arch-1-test "$TMP/sync-brief.md" 18 ) >/dev/null 2>&1 \
  || { echo 'dispatch to a stale-but-clean worker failed' >&2; exit 1; }
[[ "$(git -C "$W1" rev-parse HEAD)" == "$(git -C "$G" rev-parse swarm/test/integration)" ]] \
  || { echo 'worker checkout was not brought to the integration tip' >&2; exit 1; }
if ( cmd_dispatch arch-2-test "$TMP/sync-brief.md" 19 ) >/dev/null 2>&1; then
  echo 'dispatch to a diverged worker was not refused' >&2; exit 1
fi
! grep -qx arch-2-test "$TMP/sync-leases" || { echo 'refused dispatch still took a lease' >&2; exit 1; }
! grep -q 'arch-2-test' "$TMP/sync-prompts" || { echo 'refused dispatch still prompted the worker' >&2; exit 1; }
( cmd_dispatch pm-test "$TMP/sync-brief.md" 20 ) >/dev/null 2>&1 || { echo 'root anchor dispatch failed' >&2; exit 1; }
[[ "$(git -C "$G" rev-parse main)" == "$main_before" ]] || { echo 'dispatch moved the base checkout' >&2; exit 1; }

# A brief carrying ticket frontmatter is a ticket too: it syncs without the
# optional ticket argument.
W3="$TMP/w3"
git -C "$G" worktree add -q -b swarm/test/arch_3 "$W3" main
printf '{"seats":[{"name":"arch-3-test","isolated":true,"worktree_dir":"%s"}]}' "$W3" > "$STATE_DIR/seats.json"
printf -- '---\nid: 21\nowns: src/next.py\n---\n\nNext task\n' > "$TMP/sync-ticket-brief.md"
( cmd_dispatch arch-3-test "$TMP/sync-ticket-brief.md" ) >/dev/null 2>&1 \
  || { echo 'frontmatter ticket dispatch failed' >&2; exit 1; }
[[ "$(git -C "$W3" rev-parse HEAD)" == "$(git -C "$G" rev-parse swarm/test/integration)" ]] \
  || { echo 'frontmatter ticket brief skipped the checkout sync' >&2; exit 1; }

printf 'test_manual_arbiter: PASS\n'
