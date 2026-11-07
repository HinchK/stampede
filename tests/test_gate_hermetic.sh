#!/usr/bin/env bash
# tests/test_gate_hermetic.sh — ARB-HERM-1: the suite gate must not inherit the pane environment.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PASS=0; FAIL=0
ok()  { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
resolve_timeout || { echo "no timeout(1); skipping"; exit 0; }
D=$(mktemp -d /tmp/test-herm-XXXX); trap 'rm -rf "$D"' EXIT

out=$(REPO_DIR=/leak STATE_DIR=/leak HERDR_PANE_ID=w1:p1 KEEP_ME=yes \
  gate_exec "$D" "$D" 10 'echo "[${REPO_DIR:-}|${STATE_DIR:-}|${HERDR_PANE_ID:-}|${KEEP_ME:-}]"')
[[ "$out" == "[|||yes]" ]] && ok "REPO_DIR/STATE_DIR/HERDR_* scrubbed, other env kept" || bad "env leaked: $out"

out=$(gate_exec "$D" "$D" 10 'pwd -P')
[[ "$out" == "$(cd "$D" && pwd -P)" ]] && ok "runs in the requested dir" || bad "cwd: $out"

rc=0; gate_exec "$D/missing" "$D" 10 true || rc=$?
[[ "$rc" == 127 ]] && ok "missing dir exits 127" || bad "missing dir rc=$rc"

rc=0; gate_exec "$D" "$D" 10 'exit 3' || rc=$?
[[ "$rc" == 3 ]] && ok "suite exit code propagates" || bad "rc=$rc"

grep -q 'worktrees/arbiter-' "$SCRIPT_DIR/lib/arbiter.sh" \
  && bad "gate worktree path still contains 'arbiter'" || ok "gate worktree path has no 'arbiter' substring"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
