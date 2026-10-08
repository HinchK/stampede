#!/bin/bash
# tests/test_quota.sh — lib/quota.sh + `stampede quota` (PUB-9)
#
# Hermetic: stub curl on PATH (fixture-driven — no test reaches the
# network), scratch configs and credential files, OPENROUTER_API_KEY
# force-unset. The CLI end-to-end runs against a scratch REPO_DIR so
# telemetry lands in the scratch traces dir only, and a before/after file
# snapshot proves the zero-writes rule (traces dir excepted).

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-quota.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin" "$SCRATCH/repo"

# Resolve the interpreter with the FULL path first (homebrew pythons live
# outside /usr/bin), then narrow: hermetic against the real network and
# real provider CLIs, not against the interpreter the product needs.
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/pyenv.sh"
if ! resolve_python >/dev/null 2>&1; then
  printf 'test_quota: SKIP — no tomllib-capable interpreter on PATH\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'test_quota: SKIP — jq not on PATH (a stampede preflight dependency)\n'
  exit 0
fi
JQ_DIR=$(cd "$(dirname "$(command -v jq)")" && pwd)

# Stub curl: fixture-driven. QUOTA_CURL_FIXTURE unset/missing → exit 7
# (unreachable endpoint). Args are logged so assertions can inspect the
# Authorization header the probe sent.
cat > "$SCRATCH/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${QUOTA_CURL_LOG:-/dev/null}"
if [[ -n "${QUOTA_CURL_FIXTURE:-}" && -f "$QUOTA_CURL_FIXTURE" ]]; then
  cat "$QUOTA_CURL_FIXTURE"
  exit 0
fi
exit 7
EOF
chmod +x "$SCRATCH/bin/curl"

unset OPENROUTER_API_KEY
PATH="$SCRATCH/bin:/usr/bin:/bin:$JQ_DIR"
export PATH

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/config.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/quota.sh"

echo "==> lib/quota.sh + stampede quota (PUB-9)"

# ── probe contract: opaque providers answer unknown, never a fabricated 0 ──
for k in claude opencode agy pi; do
  [[ "$(quota_probe_kind "$k")" == "unknown" ]] \
    && ok "$k answers unknown (no usage surface at landing)" || bad "$k: fabricated a value"
done
[[ "$(quota_probe_kind brand-new-llm)" == "unknown" ]] \
  && ok "unregistered kind answers unknown" || bad "unregistered kind: $out"

# ── agy probe: read-only pane scan for the quota wall (QUOTA-1) ────────────
# herdr stub: serves $QUOTA_HERDR_FIXTURE for `agent read <name>
# --source recent-unwrapped`, logs argv for read-only assertions.
QUOTA_HERDR_LOG="$SCRATCH/herdr.log"; : > "$QUOTA_HERDR_LOG"
herdr() {
  printf '%s\n' "$*" >> "$QUOTA_HERDR_LOG"
  if [[ "${1:-}" == "agent" && "${2:-}" == "read" && "${4:-}" == "--source" ]]; then
    [[ -f "${QUOTA_HERDR_FIXTURE:-}" ]] && cat "${QUOTA_HERDR_FIXTURE:-}"
    return 0
  fi
  return 0
}
q_fixture() { printf '%s' "$1" > "$SCRATCH/pane.txt"; export QUOTA_HERDR_FIXTURE="$SCRATCH/pane.txt"; }

q_fixture 'working on the ticket…
⚠ Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h26m33s.
'
[[ "$(quota_probe_kind agy quota-seat-x)" == "ok:5193s" ]] \
  && ok "agy: receipt message (1h26m33s) → ok:5193s" || bad "agy receipt: $(quota_probe_kind agy quota-seat-x)"
q_fixture '⚠ Individual quota reached. Resets in 45s.
'
[[ "$(quota_probe_kind agy s1)" == "ok:45s" ]] && ok "agy: 45s → ok:45s" || bad "agy 45s: $(quota_probe_kind agy s1)"
q_fixture 'quota wall. Resets in 2h — enjoy
'
[[ "$(quota_probe_kind agy s1)" == "unknown" ]] \
  && ok "agy: unrelated 'Resets in' line without the quota marker stays unknown" \
  || bad "agy false positive: $(quota_probe_kind agy s1)"
q_fixture '⚠ Individual quota reached. Resets in 2h.
later: ⚠ Individual quota reached. Resets in 10m.
'
[[ "$(quota_probe_kind agy s1)" == "ok:600s" ]] \
  && ok "agy: most recent quota message wins" || bad "agy last-wins: $(quota_probe_kind agy s1)"
q_fixture 'normal pane output, no quota message at all
just agent chatter
'
[[ "$(quota_probe_kind agy s1)" == "unknown" ]] \
  && ok "agy: no signal → unknown (no fabrication)" || bad "agy no-match: $(quota_probe_kind agy s1)"
herdr() { printf '%s\n' "$*" >> "$QUOTA_HERDR_LOG"; return 1; }
[[ "$(quota_probe_kind agy s1)" == "unknown" ]] \
  && ok "agy: herdr failure → unknown" || bad "agy herdr-fail: $(quota_probe_kind agy s1)"
[[ "$(quota_probe_kind agy)" == "unknown" ]] \
  && ok "agy: no seat name → unknown" || bad "agy seatless: $(quota_probe_kind agy)"
unset -f herdr
grep -q '^agent read quota-seat-x --source recent-unwrapped --lines 200$' "$QUOTA_HERDR_LOG" \
  && ok "agy probe is read-only: exactly one agent read (--lines 200, HERDR-2), nothing else per call" \
  || bad "herdr calls: $(sort -u "$QUOTA_HERDR_LOG" | head -3)"
if grep -qv '^agent read ' "$QUOTA_HERDR_LOG"; then
  bad "agy probe issued non-read herdr traffic: $(grep -v '^agent read ' "$QUOTA_HERDR_LOG" | head -2)"
else
  ok "no non-read herdr traffic issued"
fi
unset QUOTA_HERDR_FIXTURE

# ── gate: point-in-time dispatch-safety exit codes (QUOTA-3) ────────────────
# The herdr FUNCTION stub above was unset; a PATH binary stub now serves
# both direct quota_gate calls in this shell and the CLI child process
# (`bash lib/quota.sh gate …` runs standalone and cannot see shell functions).
cat > "$SCRATCH/bin/herdr" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "agent" && "${2:-}" == "read" && "${4:-}" == "--source" ]]; then
  [[ -f "${QUOTA_HERDR_FIXTURE:-}" ]] && cat "${QUOTA_HERDR_FIXTURE:-}"
fi
exit 0
EOF
chmod +x "$SCRATCH/bin/herdr"

# exhaustion measured → exit 1, raw result on stdout
q_fixture '⚠ Individual quota reached. Resets in 10m.
'
rc=0; out=$(quota_gate agy s1) || rc=$?
[[ "$rc" == 1 && "$out" == "ok:600s" ]] \
  && ok "gate: measured exhaustion (ok:600s) → exit 1" || bad "gate exhausted: rc=$rc out=$out"
# no signal → exit 0 (never fail closed on absence of data)
q_fixture 'normal pane chatter, nothing parseable
'
rc=0; out=$(quota_gate agy s1) || rc=$?
[[ "$rc" == 0 && "$out" == "unknown" ]] \
  && ok "gate: unknown → exit 0 (absence of data is not exhaustion)" || bad "gate unknown: rc=$rc out=$out"
# herdr itself fails → unknown → exit 0
q_fixture 'should not matter'
herdr() { return 1; }
rc=0; out=$(quota_gate agy s1) || rc=$?
[[ "$rc" == 0 && "$out" == "unknown" ]] \
  && ok "gate: herdr failure → unknown → exit 0" || bad "gate herdr-fail: rc=$rc out=$out"
unset -f herdr
# a kind with no probe surface → unknown → exit 0
rc=0; out=$(quota_gate claude s1) || rc=$?
[[ "$rc" == 0 && "$out" == "unknown" ]] \
  && ok "gate: kind without a signal surface → exit 0" || bad "gate claude: rc=$rc out=$out"

# CLI end-to-end: standalone child process, no sourcing required
q_fixture 'working on the ticket…
⚠ Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h26m33s.
'
rc=0; out=$(bash "$REPO_ROOT/lib/quota.sh" gate agy quota-seat-x) || rc=$?
[[ "$rc" == 1 && "$out" == "ok:5193s" ]] \
  && ok "CLI: bash lib/quota.sh gate agy <seat> → exit 1 + raw result" || bad "CLI gate: rc=$rc out=$out"
q_fixture 'healthy seat, no quota message
'
rc=0; out=$(bash "$REPO_ROOT/lib/quota.sh" gate agy quota-seat-x) || rc=$?
[[ "$rc" == 0 && "$out" == "unknown" ]] \
  && ok "CLI: healthy seat → exit 0 + raw result" || bad "CLI healthy: rc=$rc out=$out"
rc=0; bash "$REPO_ROOT/lib/quota.sh" gate agy >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] \
  && ok "CLI: usage error exits 2, distinct from the gate's 0/1 contract" || bad "usage rc=$rc"
unset QUOTA_HERDR_FIXTURE

# ── HERDR-2: wait-output capability probe + blocking banner wait ────────────
# herdr function stub: rc-scriptable for `pane wait-output` (--help probes
# capability, other calls are the wait itself), fixture-serving for
# `agent read` (the fallback poll's probe), argv-logged for exact-arg checks.
T2_LOG="$SCRATCH/herdr2.log"; : > "$T2_LOG"
herdr() {
  printf '%s\n' "$*" >> "$T2_LOG"
  if [[ "${1:-}" == "pane" && "${2:-}" == "wait-output" && "${3:-}" == "--help" ]]; then
    return "${T2_CAP_RC:-0}"
  fi
  if [[ "${1:-}" == "pane" && "${2:-}" == "wait-output" ]]; then
    return "${T2_WAIT_RC:-0}"
  fi
  if [[ "${1:-}" == "agent" && "${2:-}" == "read" && "${4:-}" == "--source" ]]; then
    [[ -f "${QUOTA_HERDR_FIXTURE:-}" ]] && cat "${QUOTA_HERDR_FIXTURE:-}"
  fi
  return 0
}
wait_probe_reset() { _HERDR_WAIT_OUTPUT_CACHE=""; : > "$T2_LOG"; }

# capability probe: cached once per process
wait_probe_reset; export T2_CAP_RC=0
herdr_has_wait_output && herdr_has_wait_output \
  && ok "probe: supported herdr → yes on both calls" || bad "probe yes failed"
[[ "$(grep -c '^pane wait-output --help$' "$T2_LOG")" == 1 ]] \
  && ok "probe: capability checked exactly once per process" || bad "probe not cached: $(cat "$T2_LOG")"

# degradation: absent primitive → no, exactly one stderr line, still cached
wait_probe_reset; export T2_CAP_RC=1
if ! herdr_has_wait_output 2>"$SCRATCH/cap.err"; then ok "probe: unsupported herdr → no"; else bad "probe should say no"; fi
herdr_has_wait_output 2>>"$SCRATCH/cap.err" || true
[[ "$(grep -c 'wait-output unavailable' "$SCRATCH/cap.err")" == 1 ]] \
  && ok "probe: one degradation line, logged once (cached)" || bad "degradation spam: $(cat "$SCRATCH/cap.err")"

# wait-output path: exact argv (pane, --regex banner, --timeout ms)
wait_probe_reset; export T2_CAP_RC=0 T2_WAIT_RC=0
rc=0; quota_wait_banner agy-seat-q wX:p1 5000 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 0 ]] && ok "wait: banner detected via wait-output → 0" || bad "wait rc=$rc"
grep -qF 'pane wait-output wX:p1 --regex Individual quota reached.*Resets in --timeout 5000' "$T2_LOG" \
  && ok "wait: exact wait-output argv (pane + --regex banner + --timeout ms)" || bad "argv: $(cat "$T2_LOG")"
# wait-output timeout is authoritative (no silent fallthrough to polling)
export T2_WAIT_RC=3
rc=0; quota_wait_banner agy-seat-q wX:p1 5000 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] && ok "wait: wait-output timeout → 1 (verdict authoritative)" || bad "timeout rc=$rc"
export T2_WAIT_RC=0

# fallback path: capability absent → bounded poll of the one-shot probe
wait_probe_reset; export T2_CAP_RC=1
q_fixture '⚠ Individual quota reached. Resets in 10m.
'
rc=0; quota_wait_banner agy-seat-q wX:p1 3000 100 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 0 ]] && ok "wait fallback: poll measures banner → 0" || bad "fallback rc=$rc"
if grep -qv '^pane wait-output --help$' <(grep '^pane' "$T2_LOG"); then
  bad "fallback issued non-probe pane traffic: $(grep '^pane' "$T2_LOG")"
else
  ok "wait fallback: only the capability probe, never the wait call"
fi
q_fixture 'healthy seat, no quota message
'
rc=0; quota_wait_banner agy-seat-q wX:p1 400 150 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] && ok "wait fallback: no signal within budget → 1 (never fabricated)" || bad "fallback timeout rc=$rc"
# empty pane id: wait-output unusable even when supported → poll by seat name
wait_probe_reset; export T2_CAP_RC=0
q_fixture '⚠ Individual quota reached. Resets in 10m.
'
rc=0; quota_wait_banner agy-seat-q "" 3000 100 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 0 ]] && ok "wait: empty pane → poll by seat name despite capability" || bad "empty-pane rc=$rc"
unset QUOTA_HERDR_FIXTURE T2_CAP_RC T2_WAIT_RC
unset -f herdr

# CLI end-to-end: `wait` subcommand (PATH stub returns 0 → capability yes,
# wait succeeds); usage errors stay exit 2, distinct from 0/1
q_fixture '⚠ Individual quota reached. Resets in 10m.
'
rc=0; bash "$REPO_ROOT/lib/quota.sh" wait quota-seat-x wX:p9 >/dev/null 2>&1 || rc=$?
[[ "$rc" == 0 ]] && ok "CLI: wait blocks on the banner path → exit 0" || bad "CLI wait rc=$rc"
rc=0; bash "$REPO_ROOT/lib/quota.sh" wait >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] && ok "CLI: wait usage error exits 2" || bad "CLI wait usage rc=$rc"
unset QUOTA_HERDR_FIXTURE

# ── openrouter probe: configuration matrix ─────────────────────────────────
[[ "$(quota_probe_openrouter "")" == "unknown" ]] \
  && ok "no config, no env → unknown" || bad "no-config: $(quota_probe_openrouter "")"

printf '[proxy]\nenabled = false\ncredentials = "%s/creds.toml"\n' "$SCRATCH" > "$SCRATCH/off.toml"
[[ "$(quota_probe_openrouter "$SCRATCH/off.toml")" == "unknown" ]] \
  && ok "proxy disabled → unknown (config gate honored)" || bad "disabled: $(quota_probe_openrouter "$SCRATCH/off.toml")"

printf '[openrouter]\napi_key = "sk-file-test"\n' > "$SCRATCH/creds.toml"
printf '[proxy]\nenabled = true\ncredentials = "%s/creds.toml"\n' "$SCRATCH" > "$SCRATCH/on.toml"
printf '[proxy]\nenabled = true\ncredentials = "%s/empty-creds.toml"\n' "$SCRATCH" > "$SCRATCH/on-empty.toml"
printf '[openrouter]\n' > "$SCRATCH/empty-creds.toml"

FIX_OK="$SCRATCH/fixture-ok.json"
printf '{"data":{"total_credits":10.0,"total_usage":2.5}}' > "$FIX_OK"
# NOTE: exported, not prefix-assigned — `VAR=x out=$(fn)` does not propagate
# the variable into a function's command substitution.
export QUOTA_CURL_FIXTURE="$FIX_OK"
out=$(quota_probe_openrouter "$SCRATCH/on.toml")
unset QUOTA_CURL_FIXTURE
[[ "$out" == "ok:7.5USD" ]] \
  && ok "credentials file + fixture → ok:7.5USD (10.0 - 2.5 parsed)" || bad "parse: '$out'"

FIX_ENV="$SCRATCH/fixture-env.json"
printf '{"data":{"total_credits":5,"total_usage":0}}' > "$FIX_ENV"
export QUOTA_CURL_FIXTURE="$FIX_ENV" QUOTA_CURL_LOG="$SCRATCH/curl-env.log" OPENROUTER_API_KEY="sk-env-test"
out=$(quota_probe_openrouter "")
unset QUOTA_CURL_FIXTURE QUOTA_CURL_LOG OPENROUTER_API_KEY
[[ "$out" == "ok:5USD" ]] && ok "env OPENROUTER_API_KEY probes without config" || bad "env key: '$out'"
grep -q "Authorization: Bearer sk-env-test" "$SCRATCH/curl-env.log" \
  && ok "probe sent the bearer header from the env key" || bad "header missing"

export QUOTA_CURL_FIXTURE="$FIX_OK"
out=$(quota_probe_openrouter "$SCRATCH/on-empty.toml")
unset QUOTA_CURL_FIXTURE
[[ "$out" == "unknown" ]] \
  && ok "credentials file without api_key → unknown" || bad "empty creds: '$out'"

# ── error contract: exposed-but-broken surfaces say error ──────────────────
out=$(quota_probe_openrouter "$SCRATCH/on.toml")
[[ "$out" == "error:credits endpoint unreachable" ]] \
  && ok "unreachable endpoint → error (rc still 0: caller decides)" || bad "unreachable: '$out'"
printf 'not json at all' > "$SCRATCH/fixture-garbage.json"
export QUOTA_CURL_FIXTURE="$SCRATCH/fixture-garbage.json"
out=$(quota_probe_openrouter "$SCRATCH/on.toml")
unset QUOTA_CURL_FIXTURE
[[ "$out" == "error:unparsable credits response" ]] && ok "garbage response → error" || bad "garbage: '$out'"
printf '{"data":{}}' > "$SCRATCH/fixture-empty.json"
export QUOTA_CURL_FIXTURE="$SCRATCH/fixture-empty.json"
out=$(quota_probe_openrouter "$SCRATCH/on.toml")
unset QUOTA_CURL_FIXTURE
[[ "$out" == "error:unparsable credits response" ]] && ok "missing fields → error" || bad "empty data: '$out'"
printf '{"data":{"total_credits":null,"total_usage":null}}' > "$SCRATCH/fixture-null.json"
export QUOTA_CURL_FIXTURE="$SCRATCH/fixture-null.json"
out=$(quota_probe_openrouter "$SCRATCH/on.toml")
unset QUOTA_CURL_FIXTURE
[[ "$out" == "error:unparsable credits response" ]] \
  && ok "null fields → error, never a fabricated 0" || bad "null fields: '$out'"

# ── CLI end-to-end: table keyed to configured seats + telemetry + writes ───
cat > "$SCRATCH/e2e.toml" <<EOF
[seats.alpha]
name = "alpha"
default_kind = "claude"
[seats.beta]
name = "beta"
default_kind = "pi"
enabled = false
[proxy]
enabled = true
credentials = "$SCRATCH/creds.toml"
EOF

export STAMPEDE_CONFIG="$SCRATCH/e2e.toml"
export REPO_DIR="$SCRATCH/repo"
S="$REPO_ROOT/bin/stampede"

# NOTE: sourcing lib/*.sh above turned on `set -e` in this shell (the libs
# set it themselves); every call expected to fail is captured errexit-safe
# (`|| rc=$?`), and fixture env travels via export, never via a
# prefix assignment (which does not reach command substitutions).
snap_before=$(cd "$SCRATCH/repo" && find . -type f | sort)
export QUOTA_CURL_FIXTURE="$FIX_OK"
rc=0; out=$("$S" quota 2>&1) || rc=$?
unset QUOTA_CURL_FIXTURE
[[ "$rc" == 0 ]] && ok "quota exits 0 when probes answer (ok or unknown)" || bad "rc=$rc: $out"
printf '%s' "$out" | grep -q $'^[[:space:]]*alpha[[:space:]]*claude[[:space:]]*unknown' \
  && ok "enabled seat row rendered (alpha/claude/unknown)" || bad "alpha row missing: $out"
printf '%s' "$out" | grep -q "SKIP (disabled)" \
  && ok "disabled seat skipped, never probed" || bad "beta not skipped: $out"
printf '%s' "$out" | grep -q $'^[[:space:]]*-[[:space:]]*openrouter[[:space:]]*ok:7.5USD' \
  && ok "proxy surface row rendered (openrouter/ok:7.5USD)" || bad "proxy row: $out"

# telemetry: one quota.probe event per actual probe (alpha + proxy; not beta)
TRACE="$SCRATCH/repo/.herdr-swarm/traces/stampede-quota.jsonl"
n=$(jq -r -s '[.[] | select(.event_type == "quota.probe")] | length' "$TRACE" 2>/dev/null || printf 0)
[[ "$n" == 2 ]] && ok "exactly one quota.probe event per probe (2)" || bad "events: $n"
jq -e -s 'any(.[]; .event_type == "quota.probe" and .agent == "alpha" and .payload.status == "unknown")' "$TRACE" >/dev/null 2>&1 \
  && ok "alpha event carries status unknown" || bad "alpha event malformed"
jq -e -s 'any(.[]; .event_type == "quota.probe" and .payload.seat == "-" and .payload.kind == "openrouter" and .payload.status == "ok")' "$TRACE" >/dev/null 2>&1 \
  && ok "proxy event carries status ok" || bad "proxy event malformed"
jq -r -s '[.[] | select(.event_type == "quota.probe")]|map(.payload.seat)|join(",")' "$TRACE" 2>/dev/null | grep -q beta \
  && bad "disabled seat emitted an event" || ok "disabled seat emitted no event"

# zero writes outside the trace dir (PUB-9 rule)
snap_after=$(cd "$SCRATCH/repo" && find . -type f | sort)
stray=$(comm -13 <(printf '%s\n' "$snap_before") <(printf '%s\n' "$snap_after") | grep -v '^./.herdr-swarm/traces/' || true)
[[ -z "$stray" && -n "$snap_after" ]] \
  && ok "zero writes outside .herdr-swarm/traces/" || bad "stray writes: $stray"

# session reuse is read-only: a pre-existing session id is honored, not rewritten
mkdir -p "$SCRATCH/repo/.herdr-swarm"
printf 'swarm-test-0001\n' > "$SCRATCH/repo/.herdr-swarm/telemetry-session"
export QUOTA_CURL_FIXTURE="$FIX_OK"
"$S" quota >/dev/null 2>&1 || true
unset QUOTA_CURL_FIXTURE
[[ -f "$SCRATCH/repo/.herdr-swarm/traces/swarm-test-0001.jsonl" ]] \
  && ok "existing herd session id reused for quota events" || bad "session not reused"

# any probe error → exit 1 (read-only observability still escalates trouble)
rm -f "$SCRATCH/repo/.herdr-swarm/traces"/*.jsonl
rc=0; out=$("$S" quota 2>&1) || rc=$?
[[ "$rc" == 1 ]] && ok "quota exits 1 when a probe errors" || bad "error rc=$rc"
printf '%s' "$out" | grep -q "error:credits endpoint unreachable" \
  && ok "error surfaced in the table" || bad "error row missing"

# help
out=$("$S" quota --help 2>&1); rc=$?
[[ "$rc" == 0 && "$out" == *"Usage: stampede quota"* ]] && ok "--help rc=0" || bad "help rc=$rc"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
