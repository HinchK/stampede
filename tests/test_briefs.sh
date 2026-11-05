#!/bin/bash
# tests/test_briefs.sh — lib/briefs.sh deliver_brief_nonce (HERDR-4)
#
# Hermetic: herdr is a function stub (argv logged, rc scripted, pane fixture
# served) — no workspace, no panes, no network. The live-probe receipts the
# behaviour contracts here encode live in docs/findings/brief-delivery-probe.md.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-briefs.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/pyenv.sh"
if ! resolve_python >/dev/null 2>&1; then
  printf 'test_briefs: SKIP — no tomllib-capable interpreter on PATH\n'
  exit 0
fi
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/briefs.sh"   # also turns set -e on (sourced libs set it)

echo "==> lib/briefs.sh deliver_brief_nonce (HERDR-4)"

B_LOG="$SCRATCH/herdr.log"
BRIEF="$SCRATCH/worker.md"
printf '# standing brief fixture\n' > "$BRIEF"

# herdr stub: capability probe reads --help output; prompt/read rc-scripted.
herdr() {
  printf '%s\n' "$*" >> "$B_LOG"
  if [[ "${1:-}" == "agent" && "${2:-}" == "prompt" && "${3:-}" == "--help" ]]; then
    printf '%s\n' "${B_HELP_TEXT:---wait Wait for the first matching state observed after submission}"
    return 0
  fi
  if [[ "${1:-}" == "agent" && "${2:-}" == "prompt" ]]; then
    printf '%s\n' "${B_PROMPT_OUT:-{\"id\":\"cli:agent:prompt\",\"result\":{}}}"
    return "${B_PROMPT_RC:-0}"
  fi
  if [[ "${1:-}" == "agent" && "${2:-}" == "read" ]]; then
    [[ -f "${B_PANE_FIXTURE:-}" ]] && cat "${B_PANE_FIXTURE:-}"
    return 0
  fi
  return 0
}
reset() {
  : > "$B_LOG"
  _BRIEFS_PROMPT_WAIT_CACHE=""
  unset B_PROMPT_RC B_PROMPT_OUT B_PANE_FIXTURE B_HELP_TEXT
}

# [1] missing brief file → hard failure, no herdr traffic
reset
rc=0; deliver_brief_nonce seat-x "$SCRATCH/nope.md" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] && ok "missing brief file fails rc=1" || bad "missing file rc=$rc"
[[ ! -s "$B_LOG" ]] && ok "missing file: no herdr calls issued" || bad "traffic: $(head -2 "$B_LOG")"

# [2] probed support: ONE prompt with --wait, no enter, no blind pre-wait
reset
out=$(deliver_brief_nonce seat-x "$BRIEF" 2>"$SCRATCH/e") && rc=0 || rc=$?
[[ "$rc" == 0 && "$out" == *"Brief delivered to seat-x"* ]] \
  && ok "single-submission delivery on --wait-capable herdr" || bad "delivery: rc=$rc out=$out"
[[ "$(grep -c '^agent prompt seat-' "$B_LOG")" == 1 ]] \
  && ok "exactly one agent prompt per delivery" || bad "prompt count: $(grep -c '^agent prompt seat-' "$B_LOG")"
grep -q -- '--wait --timeout 90000$' "$B_LOG" \
  && ok "prompt carries --wait --timeout 90000 (options after text)" || bad "argv: $(cat "$B_LOG")"
if grep -Eq 'send-keys|^agent wait ' "$B_LOG"; then
  bad "legacy double-enter/pre-wait traffic present: $(grep -E 'send-keys|^agent wait ' "$B_LOG")"
else
  ok "no send-keys enter, no blind pre-send agent wait (dropped per probe)"
fi
grep -q '^agent prompt --help$' "$B_LOG" \
  && ok "capability probe ran (prompt --help)" || bad "no capability probe call"

# [3] capability cached once per process across deliveries
reset
deliver_brief_nonce seat-x "$BRIEF" >/dev/null 2>&1 || true
deliver_brief_nonce seat-y "$BRIEF" >/dev/null 2>&1 || true
[[ "$(grep -c '^agent prompt --help$' "$B_LOG")" == 1 ]] \
  && ok "capability probe cached once per process (two deliveries, one probe)" \
  || bad "probe count: $(grep -c '^agent prompt --help$' "$B_LOG")"

# [4] legacy herdr (no --wait): prompt-only, still no enter
reset
B_HELP_TEXT="Usage: herdr agent prompt <TARGET> <TEXT>"
out=$(deliver_brief_nonce seat-x "$BRIEF" 2>"$SCRATCH/e") && rc=0 || rc=$?
[[ "$rc" == 0 ]] && ok "legacy path delivers rc=0" || bad "legacy rc=$rc"
[[ "$(grep -c '^agent prompt seat-' "$B_LOG")" == 1 ]] \
  && ok "legacy path: one prompt, no --wait flag" || bad "legacy argv: $(cat "$B_LOG")"
if grep -q -- '--wait' "$B_LOG"; then
  bad "legacy path passed --wait to a herdr without it"
else
  ok "legacy path omits --wait (probed absent)"
fi

# [5] agent_blocked: refused pre-send → reported, never retried
reset
export B_PROMPT_RC=1
export B_PROMPT_OUT='{"error":{"code":"agent_blocked","message":"agent seat-x is blocked"}}'
out=$(deliver_brief_nonce seat-x "$BRIEF" 2>"$SCRATCH/e") && rc=0 || rc=$?
[[ "$rc" == 1 ]] && ok "agent_blocked fails rc=1 (surfaced)" || bad "blocked rc=$rc"
grep -q "FAILED for seat-x: agent_blocked" "$SCRATCH/e" \
  && ok "agent_blocked reported with reason (no retry)" || bad "blocked msg: $(cat "$SCRATCH/e")"
[[ "$(grep -c '^agent prompt seat-x ' "$B_LOG")" == 1 ]] \
  && ok "agent_blocked: exactly one prompt (not retried)" || bad "retried: $(grep '^agent prompt seat-x ' "$B_LOG")"

# [6] stall is indeterminate: marker in pane → delivered (claude probe receipt)
reset
export B_PROMPT_RC=1
export B_PROMPT_OUT='{"error":{"code":"agent_prompt_stalled","message":"no observed working or blocked state within 5000 ms"}}'
printf 'chatter\nSTANDING BRIEF: You are seated as seat-x\nchatter\n' > "$SCRATCH/pane.txt"
export B_PANE_FIXTURE="$SCRATCH/pane.txt"
out=$(deliver_brief_nonce seat-x "$BRIEF" 2>"$SCRATCH/e") && rc=0 || rc=$?
[[ "$rc" == 0 && "$out" == *"verified by pane read after agent_prompt_stalled"* ]] \
  && ok "stall + marker in pane → delivered (verified, not failed)" || bad "stall-verify: rc=$rc out=$out err=$(cat "$SCRATCH/e")"

# [7] stall with no marker → FAILED after bounded reads
reset
export B_PROMPT_RC=1
export B_PROMPT_OUT='{"error":{"code":"agent_prompt_stalled","message":"no observed state"}}'
printf 'unrelated pane output only\n' > "$SCRATCH/pane2.txt"
export B_PANE_FIXTURE="$SCRATCH/pane2.txt"
out=$(deliver_brief_nonce seat-x "$BRIEF" 2>"$SCRATCH/e") && rc=0 || rc=$?
[[ "$rc" == 1 ]] && grep -q "FAILED for seat-x: agent_prompt_stalled" "$SCRATCH/e" \
  && ok "stall unverified → FAILED:agent_prompt_stalled" || bad "stall-unverified rc=$rc err=$(cat "$SCRATCH/e")"
[[ "$(grep -c '^agent read seat-x ' "$B_LOG")" == 3 ]] \
  && ok "bounded verification: exactly three pane reads" || bad "reads: $(grep -c '^agent read seat-x ' "$B_LOG")"

# [8] hard prompt failure → surfaced, not swallowed
reset
export B_PROMPT_RC=1
export B_PROMPT_OUT='{"error":{"code":"agent_not_found","message":"agent target seat-x not found"}}'
out=$(deliver_brief_nonce seat-x "$BRIEF" 2>"$SCRATCH/e") && rc=0 || rc=$?
[[ "$rc" == 1 ]] && grep -q "FAILED for seat-x: agent_not_found" "$SCRATCH/e" \
  && ok "hard failure surfaced with the herdr error code" || bad "hard-fail rc=$rc err=$(cat "$SCRATCH/e")"

# [9] template values are data: a quote in a value or a path must not break the render
mkdir -p "$SCRATCH/o'dir"
printf 'run: {{TEST_CMD}}\n' > "$SCRATCH/o'dir/t.in.md"
substitute_template "$SCRATCH/o'dir/t.in.md" "$SCRATCH/o'dir/t.md" \
  "$(jq -cn --arg c 'pytest -k "not slow"' '{TEST_CMD: $c}')" 2>/dev/null || true
[[ "$(cat "$SCRATCH/o'dir/t.md" 2>/dev/null)" == 'run: pytest -k "not slow"' ]] \
  && ok "quoted test command + apostrophe path render verbatim" || bad "render: $(cat "$SCRATCH/o'dir/t.md" 2>&1)"

# [10] LOOPER-1 D2: render_all_briefs never emits 'none' placeholders —
# a local-only repo (no GitHub remote) renders no `-R none`/`-R local-only`
# and says so plainly; an unset proxy endpoint drops its line entirely.
RENDER_TGT="$SCRATCH/render-target"
mkdir -p "$RENDER_TGT/.herdr-swarm"
printf 'test:\n\techo hi\n' > "$RENDER_TGT/Makefile"
printf 'REPO=""\nREPO_LOCAL_ONLY=1\nTEST_CMD="make test"\n' > "$RENDER_TGT/.herdr-swarm/profile.env"
render_all_briefs "$RENDER_TGT" "dev" >/dev/null 2>&1 || true
RB="$RENDER_TGT/.herdr-swarm/briefs"

if [[ -f "$RB/looper.md" ]]; then
  ok "local-only: looper.md rendered"
else
  bad "local-only: looper.md not rendered"
fi
grep -q -- '-R none' "$RB"/*.md 2>/dev/null \
  && bad "local-only: '-R none' leaked into a brief" || ok "local-only: no '-R none' anywhere"
grep -rq -- '-R local-only' "$RB" 2>/dev/null \
  && bad "local-only: '-R local-only' leaked into a brief" || ok "local-only: no '-R local-only' anywhere"
grep -q 'local-only' "$RB/looper.md" 2>/dev/null \
  && ok "local-only: looper.md says so plainly" || bad "local-only: no plain local-only statement"
grep -rq 'Local routing proxy endpoint: ``' "$RB" 2>/dev/null \
  && bad "unset proxy: empty-backtick endpoint line rendered" || ok "unset proxy: endpoint line dropped"

# [11] a real repo keeps -R <slug>; a configured endpoint keeps its line.
printf 'REPO="acme/widget"\nTEST_CMD="make test"\n' > "$RENDER_TGT/.herdr-swarm/profile.env"
cat > "$SCRATCH/proxied.config.toml" <<'EOF'
[swarm]
name = "proxied-dev"
[proxy]
enabled = true
endpoint = "http://127.0.0.1:8787"
EOF
STAMPEDE_CONFIG_FILE="$SCRATCH/proxied.config.toml" render_all_briefs "$RENDER_TGT" "dev" >/dev/null 2>&1 || true
grep -q -- '-R acme/widget' "$RB/worker-gh.md" 2>/dev/null \
  && ok "repo set: '-R acme/widget' present" || bad "repo set: -R slug missing"
grep -q 'Local routing proxy endpoint: `http://127.0.0.1:8787`' "$RB/looper.md" 2>/dev/null \
  && ok "proxy set: endpoint line rendered with value" || bad "proxy set: endpoint line missing"

# [12] PROXY_ENDPOINT='none' is treated as unset, not rendered.
sed 's|http://127.0.0.1:8787|none|' "$SCRATCH/proxied.config.toml" > "$SCRATCH/none-proxy.config.toml"
STAMPEDE_CONFIG_FILE="$SCRATCH/none-proxy.config.toml" render_all_briefs "$RENDER_TGT" "dev" >/dev/null 2>&1 || true
grep -rq 'Local routing proxy endpoint' "$RB" 2>/dev/null \
  && bad "proxy=none: endpoint line still rendered" || ok "proxy=none: endpoint line dropped"

unset -f herdr
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
