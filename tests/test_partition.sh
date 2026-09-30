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
LIB_PARTITION="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/partition.sh"
# shellcheck disable=SC1090  # path resolved above; racing subshells re-source it
source "$LIB_PARTITION"

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

# ── case 11: resolved tickets vs integration evidence (DOG-11) ─────────────
RES="$REPO/maps/tickets/t-res.md"
printf -- '---\nid: T-RES\nstatus: resolved\nowns: docs/adr/\n---\n' > "$RES"
CAND2="$REPO/maps/tickets/cand2.md"
printf -- '---\nid: T-C2\nstatus: ready\nowns: docs/adr/0009.md\n---\n' > "$CAND2"
# ensure no lease interference for this case
printf '{"version":1,"leases":[]}' > "$STATE/leases.json"
# evidence PRESENT but silent about T-RES → contrary evidence → still active
printf '{"ts":1,"ticket":"T-OTHER","seat":"x","sha":"abc","status":"integrated"}\n' > "$STATE/integration.jsonl"
partition_check "$CAND2" "$REPO" >/dev/null 2>&1 && bad 11 "resolved-not-integrated blocks overlapping candidate" \
  || ok 11 "resolved, absent from present evidence, still holds (candidate blocked)"
# evidence file itself absent (fresh clone / wiped state) → missing evidence
# is not activity → dispatchable, with exactly one warning line
rm -f "$STATE/integration.jsonl"
rc=0; WARN11=$(partition_check "$CAND2" "$REPO" 2>&1 >/dev/null) || rc=$?
warn_n=$(printf '%s' "$WARN11" | grep -c 'integration evidence absent' || true)
if [[ "$rc" == 0 && "$warn_n" == 1 ]]; then
  ok 11a "no evidence file: resolved ticket inactive, exactly one warning"
else
  bad 11a "no evidence file: rc=$rc warnings=$warn_n (want rc=0, 1)"
fi
# once integrated → inactive → dispatchable
printf '{"ts":1,"ticket":"T-RES","seat":"x","sha":"abc","status":"integrated"}\n' > "$STATE/integration.jsonl"
partition_check "$CAND2" "$REPO" >/dev/null 2>&1 && ok 11b "integrated ticket releases the block" \
  || bad 11b "integrated ticket releases the block"

# ── case 11c: superseded tickets hold no ownership claim (PART-1) ───────────
# A superseded ticket was never executed and never will be — it must not
# block a candidate on the same owned path, regardless of evidence state
# (the incident shape: CRED-1 superseded by GRANT-1 still colliding with a
# docs/findings/ candidate). Exercise both evidence states.
SUP="$REPO/maps/tickets/t-sup.md"
printf -- '---\nid: T-SUP\nstatus: superseded\nowns: docs/findings/\n---\n' > "$SUP"
CAND3="$REPO/maps/tickets/cand3.md"
printf -- '---\nid: T-C3\nstatus: ready\nowns: docs/findings/report.md\n---\n' > "$CAND3"
# evidence PRESENT and silent about T-SUP: superseded beats the contrary-
# evidence rule that keeps resolved tickets active — it never ran at all
partition_check "$CAND3" "$REPO" >/dev/null 2>&1 && ok 11c "superseded ticket does not block (evidence present)" \
  || bad 11c "superseded ticket blocked candidate (evidence present)"
# evidence ABSENT: same answer, no lease/evidence escape hatch needed
rm -f "$STATE/integration.jsonl"
partition_check "$CAND3" "$REPO" >/dev/null 2>&1 && ok 11c2 "superseded ticket does not block (no evidence)" \
  || bad 11c2 "superseded ticket blocked candidate (no evidence)"
rm -f "$SUP"

# ── case 12: no-owns fallback = exclusive serialized ───────────────────────
# (11b left T-RES integrated on record; keep it that way — present evidence
# naming the ticket is what keeps it inactive here)
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
  # shellcheck disable=SC1090  # resolved once at the top of this file
  source "$LIB_PARTITION"
  export REPO_DIR="$REPO" STATE_DIR="$STATE"
  lease_acquire T-RACE seat-a br-a "lib/a.sh" >/dev/null 2>&1 && echo WON > "$A_OUT" || echo LOST > "$A_OUT"
) &
(
  # shellcheck disable=SC1090  # resolved once at the top of this file
  source "$LIB_PARTITION"
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

# ── case 16 (DOG-11): fresh clone — no .herdr-swarm at all ─────────────────
# The full deadlock repro: many resolved tickets (with and without owns) and
# zero gitignored state must not phantom-block any dispatch.
rm -f "$REPO/maps/tickets/t-ser.md"   # in_progress fixture would be a REAL active ticket
printf -- '---\nid: R-1\nstatus: resolved\nowns: lib/a.sh\n---\n' > "$REPO/maps/tickets/r1.md"
printf -- '---\nid: R-2\nstatus: resolved\nowns: tests/\n---\n' > "$REPO/maps/tickets/r2.md"
printf -- '---\nid: R-3\nstatus: resolved\n---\n' > "$REPO/maps/tickets/r3.md"
CAND16="$REPO/maps/tickets/cand16.md"
printf -- '---\nid: T-C16\nstatus: ready\nowns: docs/audits/a.md\n---\n' > "$CAND16"
CAND16B="$REPO/maps/tickets/cand16b.md"
printf -- '---\nid: T-C16B\nstatus: ready\n---\n' > "$CAND16B"
rm -rf "$STATE"
rc=0; WARN16=$(partition_check "$CAND16" "$REPO" 2>&1 >/dev/null) || rc=$?
warn_n=$(printf '%s' "$WARN16" | grep -c 'integration evidence absent' || true)
if [[ "$rc" == 0 && "$warn_n" == 1 ]]; then
  ok 16a "fresh clone: disjoint-owns candidate dispatches, exactly one warning"
else
  bad 16a "fresh clone disjoint candidate (rc=$rc warnings=$warn_n, want rc=0, 1)"
fi
rc=0; partition_check "$CAND16B" "$REPO" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] && ok 16b "fresh clone: no-owns candidate exclusive (rc=2), not buried by phantom leases" \
  || bad 16b "fresh clone exclusive candidate (rc=$rc, want 2)"

# ── DOG-16: supervisor dispatch wiring — guard + lease lifecycle ───────────
# Sources the REAL supervisor (its `status` command runs harmlessly at source
# time) and drives its dispatch path against this scratch repo: dispatch
# ACQUIRES, overlap blocks fail-closed before any prompt is sent, and the
# release pass fires only on integrated/promoted evidence — queued (green,
# not yet merged) never releases (ADR 0012 §5, premature-release anti-pattern).
# Supervisor loggers (ok/bad, one-arg) clobber the suite's two-arg versions
# at source, so this section asserts through sup_ok/sup_bad.
SUITE_REPO="$REPO"   # supervisor source overwrites REPO from profile.env
mkdir -p "$STATE"
printf 'REPO="foo/bar"\nTEST_CMD="sh ./gate.sh"\nECOSYSTEM="generic"\nDOCS_DIR="docs"\n' > "$STATE/profile.env"
SUPERVISOR_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/loop-bot-herd.sh"
# shellcheck disable=SC1090  # path resolved above
source "$SUPERVISOR_SH" status >/dev/null 2>&1
REPO="$SUITE_REPO"

sup_ok()  { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
sup_bad() { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
prompts_n() { wc -l < "$PROMPTS" | tr -d ' '; }

PROMPTS="$TEST_DIR/prompts.log"; : > "$PROMPTS"
herdr() { printf '%s\n' "$*" >> "$PROMPTS"; return 0; }

mkdir -p "$REPO/maps/tickets"
printf '{"version":1,"leases":[]}' > "$STATE/leases.json"
rm -f "$STATE/integration.jsonl"
D16_A="$REPO/maps/tickets/dog16-a.md"    # id ≠ filename: exercises the id: scan
printf -- '---\nid: DOG16-A\nstatus: ready\nowns: lib/dog16/a.sh\n---\nbody\n' > "$D16_A"
D16_B="$REPO/maps/tickets/dog16-b.md"    # overlaps A on lib/dog16/a.sh
printf -- '---\nid: DOG16-B\nstatus: ready\nowns: lib/dog16/a.sh, lib/dog16/b.sh\n---\nbody\n' > "$D16_B"
D16_C="$REPO/maps/tickets/dog16-c.md"    # no owns → exclusive fallback
printf -- '---\nid: DOG16-C\nstatus: ready\n---\nbody\n' > "$D16_C"

# 17a: end-to-end dispatch of a disjoint ticket prompts AND holds a lease
if ( cmd_dispatch arch-1-x "$D16_A" ) >/dev/null 2>&1; then
  held=$(jq -r '[.leases[] | select(.ticket == "DOG16-A" and .seat == "arch-1-x")] | length' "$STATE/leases.json")
  if [[ "$(prompts_n)" -ge 1 ]] && grep -q "BRIEF (file): $D16_A" "$PROMPTS" && [[ "$held" == 1 ]]; then
    sup_ok 17a "dispatch prompted the worker and acquired its path lease (id-scan resolved)"
  else
    sup_bad 17a "dispatch incomplete (prompts=$(prompts_n), lease=$held)"
  fi
else
  sup_bad 17a "dispatch of disjoint ticket blocked"
fi

# 17b: overlapping ticket blocked fail-closed — holder named, nothing sent
grc=0; BLK=$(dispatch_partition_guard arch-2-x "$D16_B" 2>&1) || grc=$?
n0=$(prompts_n)
b_lease=$(jq -r '[.leases[] | select(.ticket == "DOG16-B")] | length' "$STATE/leases.json")
if [[ "$grc" == 1 ]] && printf '%s' "$BLK" | grep -q 'BLOCKED' \
   && printf '%s' "$BLK" | grep -q 'DOG16-A' && [[ "$n0" == 1 && "$b_lease" == 0 ]]; then
  sup_ok 17b "overlap blocked with holder named, no prompt, no lease"
else
  sup_bad 17b "overlap guard (rc=$grc, prompts=$n0, lease=$b_lease)"
fi

# 17b2: the blocked dispatch exits non-zero from cmd_dispatch itself
if ( cmd_dispatch arch-2-x "$D16_B" ) >/dev/null 2>&1; then
  sup_bad 17b2 "blocked dispatch exited 0"
else
  [[ "$(prompts_n)" == 1 ]] && sup_ok 17b2 "cmd_dispatch exits 1 on collision, prompt count unchanged" \
    || sup_bad 17b2 "blocked dispatch leaked a prompt ($(prompts_n))"
fi

# 17c: re-dispatch of a leased ticket is blocked too — re-brief is a deliberate
# lease release, never a silent double-dispatch (fail-closed)
grc=0; dispatch_partition_guard arch-1-x "$D16_A" >/dev/null 2>&1 || grc=$?
[[ "$grc" == 1 ]] && sup_ok 17c "re-dispatch of the leased ticket blocked" \
  || sup_bad 17c "re-dispatch guard (rc=$grc)"

# 17d: no-owns candidate runs alone or not at all
grc=0; dispatch_partition_guard arch-3-x "$D16_C" >/dev/null 2>&1 || grc=$?
[[ "$grc" == 1 ]] && sup_ok 17d "no-owns candidate blocked while any lease is live" \
  || sup_bad 17d "no-owns guard under live lease (rc=$grc)"
lease_release DOG16-A
grc=0; dispatch_partition_guard arch-3-x "$D16_C" >/dev/null 2>&1 || grc=$?
c_n=$(jq -r '[.leases[] | select(.ticket == "DOG16-C")] | length' "$STATE/leases.json")
excl_flag=$(jq -r '.leases[] | select(.ticket == "DOG16-C") | .exclusive' "$STATE/leases.json")
if [[ "$grc" == 0 && "$c_n" == 1 && "$excl_flag" == "true" ]]; then
  sup_ok 17d2 "no-owns candidate dispatched with an EXCLUSIVE lease once idle"
else
  sup_bad 17d2 "exclusive dispatch (rc=$grc, leases=$c_n, exclusive=$excl_flag)"
fi

# 17e: release pass — integrated evidence frees a lease; queued never does
jq -cn '{version:1,leases:[
  {ticket:"DOG16-A",seat:"arch-1-x",branch:"",owns:["lib/dog16/a.sh"],exclusive:false,acquired_at:"t"},
  {ticket:"DOG16-C",seat:"arch-3-x",branch:"",owns:[],exclusive:true,acquired_at:"t"}]}' > "$STATE/leases.json"
printf '{"ts":1,"ticket":"DOG16-A","seat":"arch-1-x","sha":"abc","status":"integrated"}\n' > "$STATE/integration.jsonl"
printf '{"ts":2,"ticket":"DOG16-C","seat":"arch-3-x","sha":"def","status":"queued"}\n' >> "$STATE/integration.jsonl"
RL_OUT=$(lease_release_integrated 2>&1 || true)
a_gone=$(jq -r '[.leases[] | select(.ticket == "DOG16-A")] | length' "$STATE/leases.json")
c_held=$(jq -r '[.leases[] | select(.ticket == "DOG16-C")] | length' "$STATE/leases.json")
if [[ "$a_gone" == 0 && "$c_held" == 1 ]] && printf '%s' "$RL_OUT" | grep -q 'DOG16-A'; then
  sup_ok 17e "integrated lease released by name; queued (green, unmerged) lease held"
else
  sup_bad 17e "release pass (A=$a_gone, C=$c_held)"
fi

# 17f: promoted evidence also frees; after it, the lease set is empty
printf '{"ts":3,"ticket":"DOG16-C","status":"promoted"}\n' >> "$STATE/integration.jsonl"
lease_release_integrated >/dev/null 2>&1
c_gone=$(jq -r '[.leases[] | select(.ticket == "DOG16-C")] | length' "$STATE/leases.json")
[[ "$c_gone" == 0 ]] && sup_ok 17f "promoted lease released" || sup_bad 17f "promoted release (C=$c_gone)"

# 17g: an explicitly named ticket that resolves to no file never dispatches
grc=0; dispatch_partition_guard arch-1-x "$D16_A" "DOG16-NOPE" >/dev/null 2>&1 || grc=$?
[[ "$grc" == 1 ]] && sup_ok 17g "unresolvable named ticket fail-closed" \
  || sup_bad 17g "unresolvable ticket guard (rc=$grc)"

# 17h: a plain brief (no ticket frontmatter) still dispatches, lease-free
PLAIN="$TEST_DIR/plain-brief.md"; printf 'no frontmatter here\n' > "$PLAIN"
if ( cmd_dispatch arch-1-x "$PLAIN" ) >/dev/null 2>&1; then
  p_lease=$(jq -r '(.leases // []) | length' "$STATE/leases.json")
  grep -q "BRIEF (file): $PLAIN" "$PROMPTS" && [[ "$p_lease" == 0 ]] \
    && sup_ok 17h "non-ticket brief dispatched without a partition lease" \
    || sup_bad 17h "non-ticket dispatch (prompts=$(prompts_n), leases=$p_lease)"
else
  sup_bad 17h "non-ticket brief dispatch blocked"
fi

# ── case 18: lease_acquire cannot bypass a check BLOCKED verdict (PART-2) ───
# An active ticket's ownership claim must gate lease_acquire itself, not
# only `check` — no narrower command may launder a BLOCKED into a lease.
ACT="$REPO/maps/tickets/p2-act.md"
printf -- '---\nid: P2-ACT\nstatus: in_progress\nowns: lib/shared/\n---\nbody\n' > "$ACT"
NEW="$REPO/maps/tickets/p2-new.md"
printf -- '---\nid: P2-NEW\nstatus: ready\nowns: lib/shared/x.sh\n---\nbody\n' > "$NEW"
printf '{"version":1,"leases":[]}' > "$STATE/leases.json"   # NO live lease conflict
partition_check "$NEW" "$REPO" >/dev/null 2>&1 \
  && sup_bad 18a "check BLOCKED by active ticket (fixture sanity)" \
  || sup_ok 18a "check BLOCKED by active ticket (fixture sanity)"
if lease_acquire P2-NEW seat-x "" "lib/shared/x.sh" >/dev/null 2>&1; then
  sup_bad 18b "blocked ticket cannot lease via explicit paths"
else
  sup_ok 18b "blocked ticket cannot lease via explicit paths"
fi
if lease_acquire P2-NEW seat-x >/dev/null 2>&1; then
  sup_bad 18c "blocked ticket cannot lease via its ticket file"
else
  sup_ok 18c "blocked ticket cannot lease via its ticket file"
fi
if [[ $(jq -r '(.leases // []) | length' "$STATE/leases.json") == 0 ]]; then
  sup_ok 18d "refused acquire wrote no lease"
else
  sup_bad 18d "refused acquire wrote a lease"
fi
# the gate tracks ACTIVITY, not the ticket's existence: once the blocker
# goes superseded (PART-1), the same acquire succeeds
printf -- '---\nid: P2-ACT\nstatus: superseded\nowns: lib/shared/\n---\nbody\n' > "$ACT"
if lease_acquire P2-NEW seat-x >/dev/null 2>&1; then
  sup_ok 18e "inactive blocker no longer gates the acquire"
else
  sup_bad 18e "inactive blocker still gates the acquire"
fi
if [[ $(jq -r '(.leases // []) | length' "$STATE/leases.json") == 1 ]]; then
  sup_ok 18f "successful acquire wrote exactly one lease"
else
  sup_bad 18f "lease count wrong after acquire"
fi
rm -f "$ACT" "$NEW"

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
