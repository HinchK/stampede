#!/usr/bin/env bash
# tests/test_autopilot.sh — `stampede autopilot` (AUTOPILOT-1)
#
# Three teeth:
#   1. on/off compose the real switches (attention.json, control.json, the
#      promote grant, the integration ref) and off restores the prior mode.
#   2. the supervisor pass drains on autopilot and promotes ONLY under a
#      valid grant (stubs around the sourced supervisor, like
#      test_manual_arbiter.sh).
#   3. arbiter_promote is a silent no-op when the base is already at the
#      integration tip, and still fast-forwards when it is not.
#
# The repo var is $R, never $REPO: the sourced supervisor rebinds REPO from
# the profile, and `git -C ""` is a silent no-op that targets $PWD.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── 1. on/off end-to-end against the real attention/arbiter seams ─────────
R="$TMP/repo"
mkdir -p "$R/.herdr-swarm"
git init -q -b main "$R"
git -C "$R" -c user.name=T -c user.email=t@e commit -q --allow-empty -m base
printf '[swarm]\nname = "test"\n' > "$R/swarm.config.toml"
printf 'REPO=""\nREPO_LOCAL_ONLY=1\nTEST_CMD="make -n test"\n' > "$R/.herdr-swarm/profile.env"
# Real projects git-ignore the swarm state (stampede setup writes this same
# exclude); promote's clean-tree gate sees untracked files as dirt.
printf '.herdr-swarm/\nswarm.config.toml\n' > "$R/.git/info/exclude"

# shellcheck disable=SC1091  # shared interpreter resolver
source "$ROOT/lib/pyenv.sh"
resolve_python >/dev/null
"$PYTHON_BIN" "$ROOT/lib/attention.py" mode "$R" loud >/dev/null

# shellcheck source=/dev/null  # convention-dispatched command module
source "$ROOT/lib/cli/stampede-autopilot.sh"
stampede_cmd_autopilot "$R" on >/dev/null

[[ "$(jq -r .mode "$R/.herdr-swarm/attention.json")" == "quiet" ]] \
  || { echo 'on: attention mode is not quiet' >&2; exit 1; }
jq -e '.autopilot == true and .frontier_drain == true' "$R/.herdr-swarm/control.json" >/dev/null \
  || { echo 'on: control flags not set' >&2; exit 1; }
[[ "$(jq -r .expires_at "$R/.herdr-swarm/promote-grant.json")" -gt "$(date +%s)" ]] \
  || { echo 'on: promote grant missing or expired' >&2; exit 1; }
git -C "$R" show-ref --verify --quiet refs/heads/swarm/test/integration \
  || { echo 'on: integration ref not created' >&2; exit 1; }
[[ "$(cat "$R/.herdr-swarm/autopilot-prev-mode")" == "loud" ]] \
  || { echo 'on: previous attention mode not remembered' >&2; exit 1; }

stampede_cmd_autopilot "$R" status >/dev/null

stampede_cmd_autopilot "$R" off >/dev/null
[[ ! -f "$R/.herdr-swarm/promote-grant.json" ]] \
  || { echo 'off: promote grant not revoked' >&2; exit 1; }
jq -e '.autopilot == false and .frontier_drain == false' "$R/.herdr-swarm/control.json" >/dev/null \
  || { echo 'off: control flags not cleared' >&2; exit 1; }
[[ "$(jq -r .mode "$R/.herdr-swarm/attention.json")" == "loud" ]] \
  || { echo 'off: previous attention mode not restored' >&2; exit 1; }

# ── 2. the supervisor pass: drain on autopilot, promote only with a grant ──
export REPO_DIR="$R" STATE_DIR="$R/.herdr-swarm"
# shellcheck disable=SC1090,SC1091  # supervisor sourced for its function surface (read-only pass)
source "$ROOT/loop-bot-herd.sh" status >/dev/null
_review_recover_assignments() { :; }
_quota_retry_deferred() { :; }
gate_recover() { :; }
health_pass() { :; }
harvest_verdicts() { :; }
gate_reap() { :; }
arbiter_handback_feedback() { :; }
lease_release_integrated() { :; }
unpushed_watch() { :; }
credits_watch() { :; }
frontier_drain() { :; }
arbiter_auto_drain() { echo drain >> "$TMP/hook"; }
arbiter_promote() { echo promote >> "$TMP/hook"; }
# _arb_cfg and _arb_grant_valid stay REAL: the hook must bind the arbiter
# state and evaluate the seeded grant file exactly as production does.

printf '{"paused":false,"frontier_drain":true,"suite_gate":true,"autopilot":true}\n' > "$STATE_DIR/control.json"
printf '{"granted_at": %s, "expires_at": %s}\n' "$(date +%s)" "$(( $(date +%s) + 3600 ))" \
  > "$STATE_DIR/promote-grant.json"
cmd_once >/dev/null
grep -q drain "$TMP/hook" || { echo 'autopilot pass did not drain' >&2; exit 1; }
grep -q promote "$TMP/hook" || { echo 'autopilot pass did not promote under a valid grant' >&2; exit 1; }

: > "$TMP/hook"
rm -f "$STATE_DIR/promote-grant.json"
cmd_once >/dev/null
grep -q drain "$TMP/hook" || { echo 'autopilot pass did not drain without a grant' >&2; exit 1; }
if grep -q promote "$TMP/hook"; then
  echo 'autopilot promoted without a valid grant' >&2
  exit 1
fi

# ── 3. promote: silent no-op at the tip, real fast-forward behind it ───────
out=$(REPO_DIR="$R" STATE_DIR="$STATE_DIR" PROJECT_SLUG=test BASE_BRANCH=main PROMOTE_CONFIRM=1 \
  bash "$ROOT/lib/arbiter.sh" promote 2>&1) \
  || { echo "no-op promote failed: $out" >&2; exit 1; }
[[ -z "$out" ]] || { echo "no-op promote was not silent: $out" >&2; exit 1; }

git -C "$R" checkout -q --detach
git -C "$R" -c user.name=T -c user.email=t@e commit -q --allow-empty -m advance
git -C "$R" branch -f swarm/test/integration HEAD
git -C "$R" checkout -q main
out=$(REPO_DIR="$R" STATE_DIR="$STATE_DIR" PROJECT_SLUG=test BASE_BRANCH=main PROMOTE_CONFIRM=1 \
  bash "$ROOT/lib/arbiter.sh" promote 2>&1) \
  || { echo "real promote failed: $out" >&2; exit 1; }
[[ "$(git -C "$R" rev-parse main)" == "$(git -C "$R" rev-parse swarm/test/integration)" ]] \
  || { echo 'real promote did not fast-forward main' >&2; exit 1; }
grep -q 'promoted integration' <<<"$out" || { echo 'real promote printed no receipt' >&2; exit 1; }

echo 'autopilot: all checks passed'
