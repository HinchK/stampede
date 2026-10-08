#!/usr/bin/env bash
# tests/test_arbiter.sh — automated suite for lib/arbiter.sh (P2-4)
# Scratch git repo in /tmp/test-arb-$$; cleans up after itself. Exit 0 = pass.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
# shellcheck disable=SC2034  # vars are consumed inside those eval strings
set -euo pipefail

# GATE-1 hygiene: $HERDR_PANE_ID is exported into every Herdr-managed pane
# (agent seats AND the supervisor's gate pane), and arbiter_promote now
# refuses when it finds a live agent in the calling pane. The suite is
# hermetic by design, so scrub the ambient identity here — promote tests
# then run the "unset → allow" branch deterministically no matter which
# pane launched them.
unset HERDR_PANE_ID

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
# ARB-SLUG-1: the integration ref is initialized EXPLICITLY — this fixture
# used to rely on drain's implicit create-if-missing, which is exactly the
# phantom-branch mechanism this suite now proves is gone.
arbiter_init_ref >/dev/null 2>&1
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

# ── 7d. promote pane-identity gate (GATE-1) — fail-closed ──────────────────
# The gate's own logic runs against a stubbed `herdr` with HERDR_PANE_ID set
# per-command; the wiring is proven by REDEFINING _arb_promote_pane_check
# after sourcing (spec §4) — there is deliberately no env bypass to toggle.
PANE_ERR="$TEST_DIR/pane-check.txt"
MAIN_7D=$(git -C "$REPO" rev-parse main)

herdr() { # stub: one recognized agent parked in pane wT:p9
  [[ "${1:-}" == "agent" && "${2:-}" == "list" ]] \
    && printf '{"result":{"agents":[{"name":"stub-agent","pane_id":"wT:p9"}]}}\n' \
    || return 1
}

# (a) pane occupied by a recognized agent: refuse, naming the pane, move nothing
if HERDR_PANE_ID="wT:p9" arbiter_promote --confirm >/dev/null 2>"$PANE_ERR"; then
  bad "agent-occupied pane: promote refused"
else
  ok "agent-occupied pane: promote refused"
fi
grep -q "occupied by a recognized agent" "$PANE_ERR" && grep -q "wT:p9" "$PANE_ERR" \
  && ok "agent-pane refusal names pane + reason" \
  || bad "agent-pane refusal names pane + reason"
check "agent-pane refusal moved no ref" \
  '[[ $(git -C "$REPO" rev-parse main) == "$MAIN_7D" ]]'

# (b) herdr query fails: refuse (ambiguous state is not safe state)
herdr() { return 1; }
if HERDR_PANE_ID="wT:p9" arbiter_promote --confirm >/dev/null 2>"$PANE_ERR"; then
  bad "unqueryable pane: promote refused"
else
  ok "unqueryable pane: promote refused"
fi
grep -q "could not query herdr agent state" "$PANE_ERR" \
  && ok "query-failure refusal explains itself" \
  || bad "query-failure refusal explains itself"

# (c) Herdr-managed pane with no agent attached: allow (ff no-op completes)
herdr() { # stub: agent exists, but in some other pane
  [[ "${1:-}" == "agent" && "${2:-}" == "list" ]] \
    && printf '{"result":{"agents":[{"name":"stub-agent","pane_id":"wT:p1"}]}}\n' \
    || return 1
}
if HERDR_PANE_ID="wT:p9" arbiter_promote --confirm >/dev/null 2>&1; then
  ok "agentless managed pane: promote allowed"
else
  bad "agentless managed pane: promote allowed"
fi

# (d) wiring: a refusing pane check gates BOTH the local and --pr paths
saved_check=$(declare -f _arb_promote_pane_check)
_arb_promote_pane_check() { return 1; }
arbiter_promote --confirm >/dev/null 2>&1 \
  && bad "wiring: local promote gated by pane check" \
  || ok "wiring: local promote gated by pane check"
arbiter_promote --pr --confirm >/dev/null 2>&1 \
  && bad "wiring: --pr promote gated by pane check" \
  || ok "wiring: --pr promote gated by pane check"
eval "$saved_check"

# (e) unstubbed check, no Herdr context: the hermetic allow path (as 7b/7c)
unset -f herdr
arbiter_promote --confirm >/dev/null 2>&1 \
  && ok "no pane context: unstubbed check allows" \
  || bad "no pane context: unstubbed check allows"

# ── 7f. session-scoped promote grant (GRANT-1) ─────────────────────────────
# The grant is the human's one-per-session opt-in: creation is pane-gated
# exactly like promote, a valid grant waives pane check + confirm for
# promote calls, expiry/revoke/malformed files behave as no grant at all.
GRANT="$REPO/.herdr-swarm/promote-grant.json"

# (a) grant creation from a non-agent context writes the structured file
rm -f "$GRANT"
arbiter_grant_session --ttl 600 >/dev/null 2>&1 \
  && ok "grant-session succeeds from non-agent context" \
  || bad "grant-session refused from non-agent context"
jq -e --arg p "no-herdr-context" \
  '(.granted_at | type == "number") and (.expires_at | type == "number") and (.granted_from_pane == $p) and (.expires_at - .granted_at == 600)' \
  "$GRANT" >/dev/null 2>&1 \
  && ok "grant file carries granted_at/expires_at/TTL/pane origin" \
  || bad "grant file malformed: $(cat "$GRANT" 2>/dev/null)"

# (b) grant creation from an agent pane refuses, writes nothing
herdr() { # stub: agent parked in this pane
  [[ "${1:-}" == "agent" && "${2:-}" == "list" ]] \
    && printf '{"result":{"agents":[{"name":"stub-agent","pane_id":"wT:p9"}]}}\n' \
    || return 1
}
if HERDR_PANE_ID="wT:p9" arbiter_grant_session --ttl 600 >/dev/null 2>&1; then
  bad "grant-session refuses from agent pane"
else
  ok "grant-session refuses from agent pane"
fi
rm -f "$GRANT"
if HERDR_PANE_ID="wT:p9" arbiter_grant_session --ttl 600 >/dev/null 2>&1; then :; fi
[[ ! -f "$GRANT" ]] \
  && ok "refused grant writes no file" || bad "refused grant wrote a file"

# (c) valid grant: promote needs neither --confirm nor a clean pane
arbiter_grant_session --ttl 600 >/dev/null 2>&1
if HERDR_PANE_ID="wT:p9" arbiter_promote >/dev/null 2>&1; then
  ok "grant-gated promote succeeds from an agent pane, no flags"
else
  bad "grant-gated promote refused (grant not honored)"
fi
rm -f "$GRANT"

# (d) expiry: a past expires_at behaves as no grant
jq -cn --argjson now "$(date +%s)" '{granted_at: ($now - 7200), expires_at: ($now - 3600), granted_from_pane: "no-herdr-context"}' > "$GRANT"
if HERDR_PANE_ID="wT:p9" arbiter_promote >/dev/null 2>&1; then
  bad "expired grant still authorizes promote"
else
  ok "expired grant behaves as no grant"
fi
# malformed file likewise
printf 'not json at all\n' > "$GRANT"
if HERDR_PANE_ID="wT:p9" arbiter_promote >/dev/null 2>&1; then
  bad "malformed grant file still authorizes promote"
else
  ok "malformed grant file behaves as no grant"
fi
rm -f "$GRANT"

# (e) revoke: pane-gated itself, and a revoked session refuses promote again
arbiter_grant_session --ttl 600 >/dev/null 2>&1
if HERDR_PANE_ID="wT:p9" arbiter_revoke_session >/dev/null 2>&1; then
  bad "revoke-session refuses from agent pane"
else
  ok "revoke-session refuses from agent pane"
fi
[[ -f "$GRANT" ]] \
  && ok "agent-paned revoke left the grant in place" || bad "agent-paned revoke deleted the grant"
arbiter_revoke_session >/dev/null 2>&1
[[ ! -f "$GRANT" ]] \
  && ok "revoke-session removes the grant file" || bad "grant survived revoke"
if arbiter_promote >/dev/null 2>&1; then
  bad "post-revoke promote without confirm refuses"
else
  ok "post-revoke promote without confirm refuses"
fi
unset -f herdr

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

# ── 10. auto-wire: enqueue triggers drain in the same call (PROVE-4) ───────
# A green enqueue must not sit queued until an operator runs drain. The
# trigger is exercised end-to-end: ff integration with no separate drain
# call, conflict hand-back, CLI parity, and lock serialization.
arbiter_drain 2>/dev/null   # section 9's tolerated re-enqueue left a queued record
MAIN_AUTO=$(git -C "$REPO" rev-parse main)
check "queued_count predicate: 0 on a drained queue" \
  '[[ $(arbiter_queued_count) == 0 ]]'

git -C "$REPO" branch "swarm/ptest/seat-f" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wf" "swarm/ptest/seat-f"
printf 'foxtrot-alpha\n' > "$TEST_DIR/wf/alpha.txt"
printf 'foxtrot\n' > "$TEST_DIR/wf/foxtrot.txt"
SHA_F=$(commit_at "$TEST_DIR/wf" "seat-f work")
check "queued_count predicate: 1 after an enqueue" \
  'arbiter_enqueue 209 seat-f "$SHA_F" >/dev/null 2>&1; [[ $(arbiter_queued_count) == 1 ]]'
arbiter_enqueue_and_drain 209 seat-f "$SHA_F" 2>/dev/null
ck 209 integrated "auto-wire: enqueue_and_drain integrates without a separate drain"
check "auto-wire advanced the integration ref past main" \
  'git -C "$REPO" merge-base --is-ancestor "$SHA_F" '"$IREF"' && [[ $(git -C "$REPO" rev-parse '"$IREF"') != "$MAIN_AUTO" ]]'
check "auto-wire leaves the queue drained" \
  '[[ $(arbiter_queued_count) == 0 ]]'
check "auto-wire never touches main" \
  '[[ $(git -C "$REPO" rev-parse main) == "$MAIN_AUTO" ]]'

# conflict during auto-drain: aborted + recorded + ref unmoved (ADR 0009
# invariant unchanged — the arbiter never resolves conflicts itself)
git -C "$REPO" branch "swarm/ptest/seat-g" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wg" "swarm/ptest/seat-g"
printf 'ALPHA-CONFLICT\n' > "$TEST_DIR/wg/alpha.txt"
SHA_G=$(commit_at "$TEST_DIR/wg" "seat-g conflicting work")
REF_PRE_G=$(git -C "$REPO" rev-parse "$IREF")
arbiter_enqueue_and_drain 210 seat-g "$SHA_G" 2>/dev/null
ck 210 conflict "auto-wire conflict aborts and records (no automatic resolution)"
check "auto-wire conflict leaves the integration ref unmoved" \
  '[[ $(git -C "$REPO" rev-parse '"$IREF"') == "$REF_PRE_G" ]]'
check "auto-wire conflict lists the conflicting file" \
  '[[ $(jq -r -s --arg t2 210 "[.[] | select((.ticket|tostring) == \$t2)] | .[-1].files[0]" "$Q") == "alpha.txt" ]]'
check "auto-wire conflict never touches main" \
  '[[ $(git -C "$REPO" rev-parse main) == "$MAIN_AUTO" ]]'

# CLI parity: the enqueue subcommand auto-drains (operator runs one step,
# not two); drain stays for manual re-runs. seat-g's follow-up restores
# alpha.txt to its base content so the merge is clean.
printf 'alpha\n' > "$TEST_DIR/wg/alpha.txt"
printf 'golf\n' > "$TEST_DIR/wg/golf.txt"
SHA_G2=$(commit_at "$TEST_DIR/wg" "seat-g clean work")
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/arbiter.sh" \
  enqueue 211 seat-g "$SHA_G2" >/dev/null 2>&1
ck 211 integrated "CLI enqueue auto-drains (no separate drain invocation)"
check "CLI auto-drain never touches main" \
  '[[ $(git -C "$REPO" rev-parse main) == "$MAIN_AUTO" ]]'

# serialization: while another drain holds arbiter.lock, enqueue_and_drain
# defers (record stays queued, ref unmoved) and the record integrates once
# the lock frees — auto-wiring adds no new lock, it reuses the existing one.
git -C "$REPO" branch "swarm/ptest/seat-h" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wh" "swarm/ptest/seat-h"
printf 'hotel\n' > "$TEST_DIR/wh/hotel.txt"
SHA_H=$(commit_at "$TEST_DIR/wh" "seat-h work")
mkdir -p "$REPO/.herdr-swarm/arbiter.lock"
printf '%s\n' "$$" > "$REPO/.herdr-swarm/arbiter.lock/pid"   # live holder: this shell
REF_PRE_H=$(git -C "$REPO" rev-parse "$IREF")
ARBITER_TMP_SLEEP=0.02   # bounded loser wait: 50 tries × 0.02s ≈ 1s
arbiter_enqueue_and_drain 212 seat-h "$SHA_H" 2>/dev/null
ck 212 queued "drain defers while another drain holds the lock"
check "deferred auto-wire leaves the integration ref unmoved" \
  '[[ $(git -C "$REPO" rev-parse '"$IREF"') == "$REF_PRE_H" ]]'
rm -rf "$REPO/.herdr-swarm/arbiter.lock"
arbiter_drain 2>/dev/null
ck 212 integrated "deferred record integrates once the lock frees"

# ── 11. killed drain process does not block later drains (PROVE-7) ─────────
# PROVE-4's auto-drain originally ran `arbiter_drain` inside a forked
# subshell, where bash's $$ still reports the parent — so arbiter_lock
# recorded the supervisor's pid as holder, and a drain killed mid-gate left
# a lock that never went stale. The drain must run as its own process
# (lock pid == the drain job's pid), and a dead holder must be evictable.
ARB_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/arbiter.sh"
git -C "$REPO" branch "swarm/ptest/seat-k" main
git -C "$REPO" worktree add -q --detach "$TEST_DIR/wk" "swarm/ptest/seat-k"
printf 'kilo\n' > "$TEST_DIR/wk/kilo.txt"
SHA_K=$(commit_at "$TEST_DIR/wk" "seat-k work")
arbiter_enqueue 213 seat-k "$SHA_K" >/dev/null 2>&1
# spawn a real drain process whose gate sleeps, so it holds arbiter.lock
TEST_CMD="sleep 5" bash "$ARB_LIB" drain >>"$TEST_DIR/drain-killed.log" 2>&1 &
KILLED_PID=$!
n=0
until [[ -f "$REPO/.herdr-swarm/arbiter.lock/pid" ]] || (( n >= 50 )); do sleep 0.1; n=$((n + 1)); done
check "separate-process drain records its OWN pid in the lock" \
  '[[ "$(cat "$REPO/.herdr-swarm/arbiter.lock/pid" 2>/dev/null)" == "$KILLED_PID" ]]'
kill -9 "$KILLED_PID" 2>/dev/null || true
wait "$KILLED_PID" 2>/dev/null || true
check "killed drain leaves the lock behind (stale holder)" \
  '[[ -d "$REPO/.herdr-swarm/arbiter.lock" ]]'
arbiter_enqueue_and_drain 213 seat-k "$SHA_K" 2>/dev/null
ck 213 integrated "stale lock evicted — killed drain does not block later drains"
check "recovering drain acquires and releases the lock cleanly" \
  '[[ ! -d "$REPO/.herdr-swarm/arbiter.lock" ]]'

# ── 10. fail-closed integration ref + canonical slug (ARB-SLUG-1) ──────────
# A slug that resolves to a missing integration ref (wrong source, typo, or
# the supervisor/launcher disagreement that created a phantom fork rooted at
# main) must REFUSE — never fall back to base and never create the ref.
PHANTOM_REF="refs/heads/swarm/phantom-slug/integration"
SHA_PH=$(git -C "$REPO" rev-parse main)
printf '{"ts": 1, "ticket": "PH-1", "seat": "seat-x", "sha": "%s", "status": "queued"}\n' "$SHA_PH" >> "$Q"
PH_ERR="$TEST_DIR/phantom-refusal.txt"
if PROJECT_SLUG=phantom-slug arbiter_drain >/dev/null 2>"$PH_ERR"; then
  bad "10a missing integration ref: drain refuses"
else
  ok "10a missing integration ref: drain refuses"
fi
grep -q "REFUSED" "$PH_ERR" && grep -q "init-ref" "$PH_ERR" \
  && ok "10b refusal names the ref and the explicit init remedy" \
  || bad "10b refusal text: $(head -2 "$PH_ERR")"
check "10c no phantom branch created by the refusal" \
  '! git -C "$REPO" show-ref --verify --quiet '"$PHANTOM_REF"''
ck PH-1 queued "10d queued record untouched by the refused drain"

# explicit one-time init creates it; re-init refuses
if PROJECT_SLUG=phantom-slug arbiter_init_ref >/dev/null 2>&1; then
  ok "10e init-ref creates the missing integration ref"
else
  bad "10e init-ref failed"
fi
check "10f init rooted the ref at the base branch" \
  '[[ "$(git -C "$REPO" rev-parse '"$PHANTOM_REF"')" == "$SHA_PH" ]]'
if PROJECT_SLUG=phantom-slug arbiter_init_ref >/dev/null 2>&1; then
  bad "10g re-init of an existing ref refuses"
else
  ok "10g re-init of an existing ref refuses"
fi

# with the ref initialized, the queued record drains cleanly
PROJECT_SLUG=phantom-slug arbiter_drain >/dev/null 2>&1
ck PH-1 integrated "10h drain proceeds once the ref exists explicitly"

# slug resolution precedence: explicit env > [swarm] name > basename
slug_of() { ( eval "$1 _arb_cfg" >/dev/null 2>&1; printf '%s' "${ARB_SLUG:-}" ); }
[[ "$(slug_of 'PROJECT_SLUG=env-slug; SWARM_CONFIG_NAME=cfg-name;')" == "env-slug" ]] \
  && ok "10i explicit PROJECT_SLUG wins" || bad "10i precedence: $(slug_of 'PROJECT_SLUG=env-slug; SWARM_CONFIG_NAME=cfg-name;')"
[[ "$(slug_of 'unset PROJECT_SLUG; SWARM_CONFIG_NAME=cfg-name;')" == "cfg-name" ]] \
  && ok "10j config [swarm] name is the canonical default" || bad "10j config name not honored"
[[ "$(slug_of 'unset PROJECT_SLUG; unset SWARM_CONFIG_NAME;')" == "repo" ]] \
  && ok "10k basename is the last-resort fallback" || bad "10k fallback: $(slug_of 'unset PROJECT_SLUG; unset SWARM_CONFIG_NAME;')"

# ── 11: seeded-regression pair — CAS drops expected-old (SEEDED-1) ─────────
# The pair discipline (tests/helpers/seed.sh): the §5 race scenario must go
# RED when the compare-and-swap is seeded into a plain update-ref — the
# exact silent concurrency-loser ADR 0009 exists to reject. The healthy
# half replays the race (gate advances the ref mid-run → CAS rejects,
# record retry); the seeded half plants the defect in _arb_integrate and
# asserts the SAME retry assertion fails (the racer's tip is overwritten).
# shellcheck disable=SC1091  # shared seeded-pair helper (SEEDED-1)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers/seed.sh"

printf '#!/bin/sh\nc=$(git commit-tree HEAD^{tree} -p HEAD -m racer-sd1)\ngit update-ref '"$IREF"' "$c"; exit 0\n' > "$TEST_DIR/wc/check.sh"
SHA_SD1=$(commit_at "$TEST_DIR/wc" "sd racer 1")
arbiter_enqueue sd1 seat-sd "$SHA_SD1"
arbiter_drain 2>/dev/null
ck sd1 retry "healthy half: concurrent ref move during gate → CAS retry"

SHA_SD2=$(commit_at "$TEST_DIR/wc" "sd racer 2")
arbiter_enqueue sd2 seat-sd "$SHA_SD2"
sd2_last() { jq -r -s --arg t sd2 '[.[] | select((.ticket|tostring) == $t)] | .[-1].status // "none"' "$Q" 2>/dev/null; }
if with_seeded_defect _arb_integrate \
  's/update-ref "\$ARB_REF" "\$candidate" "\$i0"/update-ref "$ARB_REF" "$candidate"/' \
  'arbiter_drain >/dev/null 2>&1; [[ "$(sd2_last)" == "retry" ]]'; then
  ok "seeded half: retry assertion FAILS when expected-old is dropped (teeth proven)"
else
  bad "seeded half: assertion passed despite dropped expected-old — no teeth"
fi
# the seed's drain overwrote the racer's tip; nothing follows that reads it

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))

# ── summary ────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
