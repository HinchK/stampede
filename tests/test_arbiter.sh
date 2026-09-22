#!/usr/bin/env bash
# tests/test_arbiter.sh — automated suite for lib/arbiter.sh (P2-4)
# Scratch git repo in /tmp/test-arb-$$; cleans up after itself. Exit 0 = pass.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
# shellcheck disable=SC2034  # vars are consumed inside those eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-arb-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
REPO="$TEST_DIR/repo"
Q="$REPO/.herdr-swarm/integration.jsonl"
IREF="refs/heads/swarm/ptest/integration"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()   { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ck()   { # TICKET WANT_STATUS LABEL
  got=$(jq -r -s --arg t "$1" '[.[] | select((.ticket|tostring) == $t)] | .[-1].status // "none"' "$Q" 2>/dev/null || printf 'err')
  if [[ "$got" == "$2" ]]; then ok "$3"; else bad "$3 (wanted $2, got $got)"; fi
}
cks()  { # STRING-TICKET WANT_STATUS LABEL — repo ticket ids are strings (P3-4-spec)
  got=$(jq -r -s --arg t "$1" '[.[] | select((.ticket|tostring) == $t)] | .[-1].status // "none"' "$Q" 2>/dev/null || printf 'err')
  if [[ "$got" == "$2" ]]; then ok "$3"; else bad "$3 (wanted $2, got $got)"; fi
}

# shellcheck disable=SC1091  # sibling lib under test
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/arbiter.sh"

# The gate under test bounds every run with timeout(1), and macOS ships none.
# Fail once, with the remedy, instead of cascading into a dozen downstream
# assertion failures that all blame the arbiter for a missing binary (DOG-15).
if ! resolve_timeout; then
  printf 'test_arbiter: cannot run — no runnable timeout(1) (remedy above)\n' >&2
  exit 1
fi

commit_at() { # DIR MSG — commit all in DIR, print sha
  git -C "$1" add -A >/dev/null
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "$2"
  git -C "$1" rev-parse HEAD
}

export REPO_DIR="$REPO" STATE_DIR="$REPO/.herdr-swarm" PROJECT_SLUG="ptest" BASE_BRANCH="main"

echo "── arbiter suite (scratch: $REPO)"

# ── fixture ────────────────────────────────────────────────────────────────
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
printf '#!/bin/sh\nexit 0\n' > "$REPO/check.sh"
printf '.herdr-swarm/\n' > "$REPO/.gitignore"
sha_base=$(commit_at "$REPO" baseline)
export TEST_CMD="sh ./check.sh"

git -C "$REPO" branch "swarm/ptest/seat-a" main
git -C "$REPO" branch "swarm/ptest/seat-b" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wa" "swarm/ptest/seat-a"
printf 'alpha\n' > "$TEST_DIR/wa/alpha.txt"
SHA_A=$(commit_at "$TEST_DIR/wa" "seat-a work")
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wb" "swarm/ptest/seat-b"
printf 'bravo\n' > "$TEST_DIR/wb/bravo.txt"
SHA_B=$(commit_at "$TEST_DIR/wb" "seat-b work")
git -C "$REPO" branch "swarm/ptest/seat-c" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wc" "swarm/ptest/seat-c"

# ── 1. enqueue + supersession ──────────────────────────────────────────────
arbiter_enqueue 201 seat-a "$SHA_A"
arbiter_enqueue 202 seat-b "$SHA_B"
check "enqueue appends two queued records" \
  '[[ $(jq -s "[.[] | select(.status == \"queued\")] | length" "$Q") == 2 ]]'
check "queue stays JSONL (one object per line)" \
  '[[ $(jq -s "length" "$Q") == $(grep -c . "$Q") ]]'

arbiter_enqueue 201 seat-a "$SHA_A"          # identical re-enqueue
check "identical re-enqueue does not supersede" \
  '[[ $(jq -s "[.[] | select(.status == \"superseded\")] | length" "$Q") == 0 ]]'

git -C "$REPO" worktree add -q --detach "$TEST_DIR/wa2" "swarm/ptest/seat-a" 2>/dev/null || true
printf 'a2\n' > "$TEST_DIR/wa2/a2.txt"
SHA_A2=$(commit_at "$TEST_DIR/wa2" "seat-a v2")
arbiter_enqueue 201 seat-a "$SHA_A2"          # newer sha for same ticket
check "newer sha supersedes older queued record" \
  '[[ $(jq -s --arg s1 "$SHA_A" "[.[] | select(.sha == \$s1)] | map(select(.status == \"superseded\")) | length" "$Q") == 1 ]]'
# restore deterministic state: drop the A2 records, requeue A
jq -s --arg s2 "$SHA_A2" 'map(select(.sha != $s2)) | .[]' "$Q" > "$Q.tmp" && mv "$Q.tmp" "$Q"
arbiter_enqueue 201 seat-a "$SHA_A"
git -C "$REPO" worktree remove --force "$TEST_DIR/wa2" >/dev/null 2>&1 || true

# ── 2. drain: ff integration + diverged merge ─────────────────────────────
arbiter_drain 2>/dev/null
ck 201 integrated "drain: #201 integrated"
ck 202 integrated "drain: #202 integrated"
check "#201 gated sha is reachable from integration ref" \
  'git -C "$REPO" merge-base --is-ancestor "$SHA_A" '"$IREF"''
check "#202 gated sha is reachable from integration ref" \
  'git -C "$REPO" merge-base --is-ancestor "$SHA_B" '"$IREF"''
check "records log full-sha CAS integration_before" \
  '[[ $(jq -r -s --arg t3 201 "[.[] | select((.ticket|tostring) == \$t3 and .status == \"integrated\")] | .[0].integration_before | length" "$Q") == 40 ]]'
check "integration tree contains both seats' files (merge or ff chain)" '
  integ=$(git -C "$REPO" rev-parse '"$IREF"')
  git -C "$REPO" cat-file -p "${integ}:alpha.txt" | grep -q alpha \
    && git -C "$REPO" cat-file -p "${integ}:bravo.txt" | grep -q bravo'
check "main untouched by drain" \
  '[[ $(git -C "$REPO" rev-parse main) == "$sha_base" ]]'

# ── 3. conflict handling ───────────────────────────────────────────────────
printf 'ALPHA-CONFLICT\n' > "$TEST_DIR/wc/alpha.txt"
SHA_C=$(commit_at "$TEST_DIR/wc" "seat-c conflicting work")
arbiter_enqueue 203 seat-c "$SHA_C"
arbiter_drain 2>/dev/null
ck 203 conflict "conflicting branch recorded as conflict"
check "conflict record lists the file" \
  '[[ $(jq -r -s --arg t2 203 "[.[] | select((.ticket|tostring) == \$t2)] | .[-1].files[0]" "$Q") == "alpha.txt" ]]'
check "integration ref unmoved after conflict" \
  '[[ $(git -C "$REPO" rev-parse '"$IREF"') != "$SHA_C" ]]'
check "arbiter worktree clean after merge --abort" \
  '[[ -z "$(git -C "$REPO/.herdr-swarm/worktrees/arbiter-ptest" status --porcelain)" ]]'

# ── 4. integration_red leaves the ref unmoved ──────────────────────────────
printf 'RED\n' > "$TEST_DIR/wc/red.flag"
printf '#!/bin/sh\nif [ -f red.flag ]; then exit 1; fi\nexit 0\n' > "$TEST_DIR/wc/check.sh"
rm -f "$TEST_DIR/wc/alpha.txt"
SHA_R=$(commit_at "$TEST_DIR/wc" "breaks combined suite")
REF_BEFORE=$(git -C "$REPO" rev-parse "$IREF")
arbiter_enqueue 204 seat-c "$SHA_R"
arbiter_drain 2>/dev/null
ck 204 integration_red "RED combined tree recorded as integration_red"
check "integration ref NOT advanced on RED" \
  '[[ $(git -C "$REPO" rev-parse '"$IREF"') == "$REF_BEFORE" ]]'

# ── 4b. an ungateable gate is NOT a RED verdict (DOG-15) ───────────────────
# macOS ships no timeout(1), so `timeout N sh -c "$TEST_CMD"` exits 127 where
# coreutils is absent. That used to be recorded as integration_red —
# condemning a combined tree the gate had never actually measured, which is
# the one failure mode the gate exists to prevent. A gate that cannot run must
# leave the record queued, must not move the ref, and must still integrate
# normally once the binary is available.
git -C "$REPO" branch "swarm/ptest/seat-e" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/we" "swarm/ptest/seat-e"
printf 'echo\n' > "$TEST_DIR/we/echo.txt"
SHA_E=$(commit_at "$TEST_DIR/we" "seat-e work")
REF_PRE_UNGATED=$(git -C "$REPO" rev-parse "$IREF")
arbiter_enqueue 208 seat-e "$SHA_E"

export TIMEOUT_BIN="$TEST_DIR/no-such-timeout"   # resolver rejects it strictly
arbiter_drain 2>/dev/null
ck 208 queued "ungateable gate leaves the record queued (not integration_red)"
check "no integration_red recorded when the gate could not run" \
  '[[ $(jq -r -s --arg t 208 "[.[] | select((.ticket|tostring) == \$t and .status == \"integration_red\")] | length" "$Q") == 0 ]]'
check "integration ref unmoved when the gate could not run" \
  '[[ $(git -C "$REPO" rev-parse '"$IREF"') == "$REF_PRE_UNGATED" ]]'
unset TIMEOUT_BIN                                 # resolver re-probes PATH

arbiter_drain 2>/dev/null
ck 208 integrated "queued record integrates once a timeout(1) is available"

# ── 5. CAS: tip moved during the gate → retry ──────────────────────────────
# The gate command races the CAS: it advances the integration ref to a NEW
# commit (not I0), so the compare-and-swap must reject.
printf '#!/bin/sh\nc=$(git commit-tree HEAD^{tree} -p HEAD -m racer)\ngit update-ref refs/heads/swarm/ptest/integration "$c"; exit 0\n' > "$TEST_DIR/wc/check.sh"
rm -f "$TEST_DIR/wc/red.flag"
SHA_M=$(commit_at "$TEST_DIR/wc" "gate mutates ref")
arbiter_enqueue 205 seat-c "$SHA_M"
arbiter_drain 2>/dev/null
ck 205 retry "concurrent ref move during gate → CAS retry"

# repair the integration line: the racer's check.sh is still in the tree;
# land an exit-0 gate so later scenarios gate cleanly
printf '#!/bin/sh\nexit 0\n' > "$TEST_DIR/wc/check.sh"
SHA_FIX=$(commit_at "$TEST_DIR/wc" "restore gate after racer")
arbiter_enqueue 207 seat-c "$SHA_FIX"
arbiter_drain 2>/dev/null
ck 207 integrated "post-racer repair integrated"

# ── 6. gated sha, not branch tip ───────────────────────────────────────────
git -C "$REPO" branch "swarm/ptest/seat-d" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wd" "swarm/ptest/seat-d"
printf '#!/bin/sh\nexit 0\n' > "$TEST_DIR/wd/check.sh"
printf 'v1\n' > "$TEST_DIR/wd/feature.txt"
SHA_D1=$(commit_at "$TEST_DIR/wd" "gated state")
arbiter_enqueue 206 seat-d "$SHA_D1"
printf 'v2-sneaky\n' > "$TEST_DIR/wd/feature.txt"
commit_at "$TEST_DIR/wd" "post-verdict tip commit" >/dev/null
arbiter_drain 2>/dev/null
ck 206 integrated "gated sha integrated despite newer branch tip"
check "integration contains GATED content, not tip" \
  'git -C "$REPO" cat-file -p "${SHA_D1}:feature.txt" | grep -q "v1"'

# ── 7. promotion (local mode) — human-gated (DOG-12) ───────────────────────
# 7a. unconfirmed promote refuses with the human-action message and moves nothing
MAIN_BEFORE=$(git -C "$REPO" rev-parse main)
if arbiter_promote >/dev/null 2>"$TEST_DIR/promote-refusal.txt"; then bad "unconfirmed promote refused"; else ok "unconfirmed promote refused"; fi
if grep -qi "human" "$TEST_DIR/promote-refusal.txt" \
   && grep -q -- "--confirm" "$TEST_DIR/promote-refusal.txt" \
   && grep -q "PROMOTE_CONFIRM=1" "$TEST_DIR/promote-refusal.txt"; then
  ok "refusal names the required human action"
else
  bad "refusal names the required human action"
fi
check "main unmoved after unconfirmed promote" \
  '[[ $(git -C "$REPO" rev-parse main) == "$MAIN_BEFORE" ]]'
check "refusal flips no records to promoted" \
  '[[ $(jq -s "[.[] | select(.status == \"promoted\")] | length" "$Q") == 0 ]]'

# 7b. dirty-root guard still applies WITH explicit confirmation
printf 'dirty\n' > "$REPO/stray.txt"
if arbiter_promote --confirm >/dev/null 2>&1; then bad "dirty root promote refused"; else ok "dirty root promote refused"; fi
rm "$REPO/stray.txt"

# 7c. confirmed promote (env form) behaves exactly as the pre-guardrail promote
( export PROMOTE_CONFIRM=1; arbiter_promote >/dev/null 2>&1 )
check "confirmed promote ff-advances main to integration" \
  '[[ $(git -C "$REPO" rev-parse main) == $(git -C "$REPO" rev-parse '"$IREF"') ]]'
check "root tree clean after promote" \
  '[[ -z "$(git -C "$REPO" status --porcelain)" ]]'
check "integrated records marked promoted" \
  '[[ $(jq -s "[.[] | select(.status == \"promoted\")] | length" "$Q") -ge 2 ]]'

# ── 8. PR body generation (no network) ─────────────────────────────────────
arbiter_pr_body "$REPO/.herdr-swarm/pr-body.md"
check "PR body lists integrated tickets with Closes lines" \
  'grep -q "Closes #206" "$REPO/.herdr-swarm/pr-body.md"'

# ── 9. string ticket ids (repo vocabulary: frontmatter id like P3-4-spec) ──
# The queue must accept the ids maps/tickets actually uses — the pm branch
# reconciliation enqueues them verbatim.
git -C "$REPO" branch "swarm/ptest/seat-s" "$sha_base"
git -C "$REPO" worktree add -q --detach "$TEST_DIR/ws" "swarm/ptest/seat-s"
printf 'sigma\n' > "$TEST_DIR/ws/sigma.txt"
SHA_S=$(commit_at "$TEST_DIR/ws" "seat-s work")
if arbiter_enqueue "P3-4-spec" seat-s "$SHA_S" 2>/dev/null; then ok "string ticket enqueues"; else bad "string ticket enqueues"; fi
arbiter_drain >/dev/null 2>&1
cks "P3-4-spec" integrated "string ticket drains to integrated"
check "string ticket merge commit references the string id" \
  'git -C "$REPO" log --format=%s -1 "$(git -C "$REPO" rev-parse '"$IREF"')" | grep -q "integrate #P3-4-spec"'
if arbiter_enqueue "P3-4-spec" seat-s "$SHA_S" 2>/dev/null; then ok "string re-enqueue tolerated"; else bad "string re-enqueue tolerated"; fi

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
