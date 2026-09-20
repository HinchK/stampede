#!/usr/bin/env bash
# tests/test_partition.sh — P3-2 acceptance suite (spec §6, cases 1–15)
# Scratch git repo; cleans up after itself. Exit 0 = all pass.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
# shellcheck disable=SC2034  # vars are consumed inside those eval strings
# shellcheck disable=SC2015  # ok/bad never fail, so A && ok || bad is safe here
# shellcheck disable=SC2030,SC2031  # subshell exports are intentional (racing dispatchers)
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-part-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
REPO="$TEST_DIR/repo"
STATE="$REPO/.herdr-swarm"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()  { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
# conflict? LABEL DESCRIPTION A B
conflict() {
  if owns_overlaps "$3" "$4" "$REPO" >/dev/null 2>&1; then ok "$1" "$2"; else bad "$1" "$2 (no conflict detected)"; fi
}
no_conflict() {
  if owns_overlaps "$3" "$4" "$REPO" >/dev/null 2>&1; then bad "$1" "$2 (false conflict)"; else ok "$1" "$2"; fi
}

# shellcheck disable=SC1091  # sibling lib under test
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/partition.sh"

export REPO_DIR="$REPO" STATE_DIR="$STATE"

echo "── partition & lease suite (scratch: $REPO)"

# fixture: git repo with real files for glob expansion
mkdir -p "$REPO/lib/sub" "$REPO/docs/adr" "$REPO/docs/audits" "$REPO/tests" "$REPO/maps/tickets"
git -C "$REPO" init -q -b main
printf 'x\n' > "$REPO/lib/a.sh";  printf 'x\n' > "$REPO/lib/b.sh"
printf 'x\n' > "$REPO/lib/Foo.sh"
printf 'x\n' > "$REPO/lib/sub/a.sh"
printf 'x\n' > "$REPO/tests/test_partition.sh"; printf 'x\n' > "$REPO/tests/test_worktree.sh"
printf 'x\n' > "$REPO/docs/adr/0001.md"; printf 'x\n' > "$REPO/docs/audits/a.md"
printf '.herdr-swarm/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m baseline

# ── cases 1–9: pure core ───────────────────────────────────────────────────
no_conflict 1 "lib/a.sh vs lib/b.sh" "lib/a.sh" "lib/b.sh"
conflict   2 "lib/a.sh vs lib/a.sh" "lib/a.sh" "lib/a.sh"
conflict   3 "lib/ vs lib/sub/a.sh (dir prefix)" "lib/" "lib/sub/a.sh"
conflict   4 "tests/test_*.sh vs tests/test_partition.sh (glob)" "tests/test_*.sh" "tests/test_partition.sh"
conflict   5 "lib/*.sh vs lib/*.py (literal prefixes overlap — intended over-approximation)" "lib/*.sh" "lib/*.py"
no_conflict 6 "docs/adr/ vs docs/audits/" "docs/adr/" "docs/audits/"
conflict   7 "lib/Foo.sh vs lib/foo.sh (casefolded)" "lib/Foo.sh" "lib/foo.sh"

if owns_parse_line "lib/ok.sh,../outside" >/dev/null 2>&1; then
  bad 8 "../outside rejected at parse"
else
  err=$(owns_parse_line "lib/ok.sh,../outside" 2>&1 >/dev/null || true)
  if printf '%s' "$err" | grep -q 'outside'; then
    ok 8a "../outside rejected, entry named"
  else
    bad 8a "../outside rejected, entry named"
  fi
fi
if owns_parse_line "/etc/passwd" >/dev/null 2>&1; then bad 8b "/etc/passwd rejected"; else ok 8b "/etc/passwd rejected"; fi
if owns_parse_line "lib/ok.sh,lib/sub/../../escape" >/dev/null 2>&1; then bad 8c ".. segments rejected"; else ok 8c ".. segments rejected"; fi
okn=$(owns_parse_line " ./lib//x.sh , lib/y.sh " 2>/dev/null | tr '\n' ' ')
[[ "$okn" == "lib/x.sh lib/y.sh " ]] && ok 8d "normalization: ./, //, whitespace, casefold" || bad 8d "normalization (got: $okn)"

TF="$TEST_DIR/blocklist.md"
cat > "$TF" <<'EOF'
---
id: BLOCKED-1
title: "yaml block list ticket"
status: in_progress
owns:
  - lib/a.sh
  - lib/b.sh
---
body
EOF
if owns_parse_ticket "$TF" >/dev/null 2>&1; then
  bad 9 "YAML block list rejected"
else
  err=$(owns_parse_ticket "$TF" 2>&1 >/dev/null || true)
  if printf '%s' "$err" | grep -q "comma-separated"; then
    ok 9 "YAML block list rejected with comma-separated hint"
  else
    bad 9 "YAML block list rejected with comma-separated hint"
  fi
fi
TF2="$TEST_DIR/emptyowns.md"
printf -- '---\nid: E-1\nstatus: in_progress\nowns:\n---\n' > "$TF2"
owns_parse_ticket "$TF2" >/dev/null 2>&1 && bad 9b "empty owns rejected" || ok 9b "empty owns rejected"
TF3="$TEST_DIR/noowns.md"
printf -- '---\nid: N-1\nstatus: in_progress\n---\n' > "$TF3"
rc=0; owns_parse_ticket "$TF3" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] && ok 9c "absent owns returns 2 (fallback path)" || bad 9c "absent owns returns 2 (got $rc)"

# ── case 10: candidate vs live lease → BLOCKED ─────────────────────────────
mkdir -p "$STATE"
jq -cn '{version:1,leases:[{ticket:"T-A",seat:"arch-1-x",branch:"swarm/x/arch-1",owns:["lib/partition.sh","tests/test_partition.sh"],exclusive:false,acquired_at:"now"}]}' > "$STATE/leases.json"
CAND="$REPO/maps/tickets/cand.md"
printf -- '---\nid: T-B\nstatus: ready\nowns: lib/partition.sh\n---\n' > "$CAND"
if PART_OUT=$(partition_check "$CAND" "$REPO" 2>&1); then
  bad 10 "overlapping candidate BLOCKED by lease"
else
  printf '%s' "$PART_OUT" | grep -q "T-A" && printf '%s' "$PART_OUT" | grep -q "lib/partition.sh" \
    && ok 10 "overlapping candidate BLOCKED (lease + intersection reported)" \
    || bad 10 "blocked report missing details"
fi
# ticket stays ready: status file untouched
grep -q 'status: ready' "$CAND" && ok 10b "blocked ticket stays ready" || bad 10b "blocked ticket stays ready"

# ── case 11: resolved-but-not-integrated stays active ──────────────────────
RES="$REPO/maps/tickets/t-res.md"
printf -- '---\nid: T-RES\nstatus: resolved\nowns: docs/adr/\n---\n' > "$RES"
CAND2="$REPO/maps/tickets/cand2.md"
printf -- '---\nid: T-C2\nstatus: ready\nowns: docs/adr/0009.md\n---\n' > "$CAND2"
# ensure no lease interference for this case
printf '{"version":1,"leases":[]}' > "$STATE/leases.json"
partition_check "$CAND2" "$REPO" >/dev/null 2>&1 && bad 11 "resolved-not-integrated blocks overlapping candidate" \
  || ok 11 "resolved-not-integrated still holds (candidate blocked)"
# once integrated → inactive → dispatchable
printf '{"ts":1,"ticket":"T-RES","seat":"x","sha":"abc","status":"integrated"}\n' > "$STATE/integration.jsonl"
partition_check "$CAND2" "$REPO" >/dev/null 2>&1 && ok 11b "integrated ticket releases the block" \
  || bad 11b "integrated ticket releases the block"
rm -f "$STATE/integration.jsonl"

# ── case 12: no-owns fallback = exclusive serialized ───────────────────────
# (T-RES must be integrated or it stays active and would block the exclusive
# candidate — re-establish its integration record first)
printf '{"ts":1,"ticket":"T-RES","seat":"x","sha":"abc","status":"integrated"}\n' > "$STATE/integration.jsonl"
jq -cn '{version:1,leases:[{ticket:"T-X",seat:"arch-2-x",branch:"",owns:["lib/zzz.c"],exclusive:false,acquired_at:"now"}]}' > "$STATE/leases.json"
rc=0; partition_check "$TF3" "$REPO" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] && ok 12a "no-owns candidate blocked while any lease is live" || bad 12a "no-owns blocked under live lease (got rc=$rc)"
printf '{"version":1,"leases":[]}' > "$STATE/leases.json"
rc=0; partition_check "$TF3" "$REPO" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] && ok 12b "no-owns candidate dispatches exclusively (rc=2) when idle" || bad 12b "exclusive dispatch rc=2 (got $rc)"
printf -- '---\nid: T-SER\nstatus: in_progress\n---\n' > "$REPO/maps/tickets/t-ser.md"
lease_acquire T-SER arch-9-x "swarm/x/arch-9" "-" >/dev/null 2>&1 || true
excl=$(jq -r '.leases[0].exclusive' "$STATE/leases.json")
owns0=$(jq -r '.leases[0].owns | length' "$STATE/leases.json")
[[ "$excl" == "true" && "$owns0" == 0 ]] && ok 12c "no-owns lease acquired exclusive with empty owns" || bad 12c "exclusive lease shape"

# ── case 13: two dispatchers racing → exactly one acquires ─────────────────
printf '{"version":1,"leases":[]}' > "$STATE/leases.json"
A_OUT="$TEST_DIR/a.out"; B_OUT="$TEST_DIR/b.out"
(
  # shellcheck disable=SC1091
  source "/Users/hinchk/Fun/loop-bot-herd-agy/lib/partition.sh"
  export REPO_DIR="$REPO" STATE_DIR="$STATE"
  lease_acquire T-RACE seat-a br-a "lib/a.sh" >/dev/null 2>&1 && echo WON > "$A_OUT" || echo LOST > "$A_OUT"
) &
(
  # shellcheck disable=SC1091
  source "/Users/hinchk/Fun/loop-bot-herd-agy/lib/partition.sh"
  export REPO_DIR="$REPO" STATE_DIR="$STATE"
  lease_acquire T-RACE2 seat-b br-b "lib/" >/dev/null 2>&1 && echo WON > "$B_OUT" || echo LOST > "$B_OUT"
) &
wait
# overlapping owns (lib/race/ prefix vs lib/race.c) → at most one WON
wons=0
[[ "$(cat "$A_OUT")" == WON ]] && wons=$((wons + 1))
[[ "$(cat "$B_OUT")" == WON ]] && wons=$((wons + 1))
[[ $wons -eq 1 ]] && ok 13 "racing dispatchers: exactly one acquires" || bad 13 "racing dispatchers (wins=$wons, want 1)"

# ── case 14: stale lease (seat vanished) released with warning ─────────────
jq -cn '{version:2,workspace_id:"wT",seats:[{name:"arch-1-x",kind:"opencode",pane:"wT:p1",isolated:false}]}' > "$STATE/seats.json"
jq -cn '{version:1,leases:[{ticket:"T-STALE",seat:"ghost-seat",branch:"",owns:["lib/old.c"],exclusive:false,acquired_at:"now"}]}' > "$STATE/leases.json"
REC_OUT=$(lease_reconcile 2>&1 || true)
if jq -e '.leases | length == 0' "$STATE/leases.json" >/dev/null 2>&1; then
  printf '%s' "$REC_OUT" | grep -q "T-STALE" && ok 14 "stale lease released with named warning" || bad 14 "released silently (warning missing)"
else
  bad 14 "stale lease released"
fi

# ── case 15: drift check records owns_violation, blocks nothing ────────────
BASE=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -b drift-br
printf 'x\n' > "$REPO/lib/declared.c"; printf 'x\n' > "$REPO/lib/undeclared.c"
git -C "$REPO" add -A; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m drift
HEAD2=$(git -C "$REPO" rev-parse HEAD)
DRIFT_OUT=$(partition_drift_check T-15 "lib/declared.c" "$BASE" "$HEAD2" "$REPO" 2>&1 || true)
if jq -e 'select(.ticket == "T-15" and .violation == "owns_violation" and (.files | index("lib/undeclared.c"))) ' \
     "$STATE/owns-violations.jsonl" >/dev/null 2>&1; then
  printf '%s' "$DRIFT_OUT" | grep -q "undeclared" && ok 15 "owns_violation recorded with file list, non-blocking" || bad 15 "recorded but unreported"
else
  bad 15 "owns_violation recorded"
fi
partition_check "$CAND2" "$REPO" >/dev/null 2>&1
ok 15b "drift does not block later dispatch (exit path exercised)"

# ── suggest ────────────────────────────────────────────────────────────────
SUG=$(partition_suggest main drift-br "$REPO")
if printf '%s' "$SUG" | grep -q 'lib/declared.c' && printf '%s' "$SUG" | grep -q 'lib/undeclared.c'; then
  ok S "suggest proposes owns from branch diff (collapsed: $SUG)"
else
  bad S "suggest (got: $SUG)"
fi

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
