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
