#!/usr/bin/env bash
# tests/test_config.sh — swarm.config.toml binding suite (DOG-7)
# Covers enabled=false seat suppression in SEAT_KEYS (the reviewer/pi
# mechanism), PROXY_* emission (credentials/serve_cmd/endpoint/health), and
# the no-hardcoded-proxy-fallback policy: a config without [proxy] keys binds
# empty, never a localhost default. Scratch configs; cleans up after itself.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-cfg-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()  { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
# check LABEL DESCRIPTION 'ASSERTION (eval)'
check() {
  local label="$1" desc="$2" body="$3"
  if eval "$body" >/dev/null 2>&1; then ok "$label" "$desc"; else bad "$label" "$desc"; fi
}

# shellcheck disable=SC1091  # config.sh pulls in common.sh + pyenv.sh itself
source "$SCRIPT_DIR/lib/config.sh"

echo "── config binding suite (scratch: $TEST_DIR)"

# ── 1. enabled=false drops a seat from the roster (reviewer/pi mechanism) ───
C1="$TEST_DIR/seat-toggle.toml"
cat > "$C1" <<'TOML'
[seats.alpha]
name = "alpha"
default_kind = "agy"
model = "auto"

[seats.beta]
name = "beta"
default_kind = "agy"
model = "auto"
enabled = false
TOML
check "1a" "config_get_seats lists enabled seats only" \
  '[[ $(config_get_seats "$C1") == "alpha" ]]'
check "1b" "dump SEAT_KEYS omits disabled seat" \
  'eval "$(config_dump_env x "$C1")" && [[ $SEAT_KEYS == "alpha" ]]'
check "1c" "no SEAT_NAME binding for disabled seat" \
  'eval "$(config_dump_env slug1 "$C1")" && [[ -z ${SEAT_NAME_beta:-} ]]'
check "1d" "SEAT_NAME carries slug for enabled seat" \
  'eval "$(config_dump_env slug1 "$C1")" && [[ $SEAT_NAME_alpha == "alpha-slug1" ]]'

# ── 2. PROXY_* bindings come from [proxy], values passed through verbatim ───
C2="$TEST_DIR/proxy-full.toml"
cat > "$C2" <<'TOML'
[seats.alpha]
name = "alpha"

[proxy]
enabled = true
endpoint = "http://proxy.example:9000/v1"
health_check_url = "http://proxy.example:9000/health"
serve_cmd = "run-proxy"
credentials = "~/creds/proxy.toml"
TOML
check "2a" "PROXY_ENABLED from config" \
  'eval "$(config_dump_env x "$C2")" && [[ $PROXY_ENABLED == "true" ]]'
check "2b" "PROXY_ENDPOINT from config" \
  'eval "$(config_dump_env x "$C2")" && [[ $PROXY_ENDPOINT == "http://proxy.example:9000/v1" ]]'
check "2c" "PROXY_HEALTH_URL from config" \
  'eval "$(config_dump_env x "$C2")" && [[ $PROXY_HEALTH_URL == "http://proxy.example:9000/health" ]]'
check "2d" "PROXY_SERVE_CMD from config" \
  'eval "$(config_dump_env x "$C2")" && [[ $PROXY_SERVE_CMD == "run-proxy" ]]'
check "2e" "PROXY_CREDENTIALS from config (DOG-7 rename)" \
  'eval "$(config_dump_env x "$C2")" && [[ $PROXY_CREDENTIALS == "~/creds/proxy.toml" ]]'

# ── 3. missing [proxy] keys bind empty — never a localhost fallback (DOG-7) ─
C3="$TEST_DIR/proxy-empty.toml"
cat > "$C3" <<'TOML'
[seats.alpha]
name = "alpha"
TOML
check "3a" "no [proxy] -> PROXY_ENABLED false" \
  'eval "$(config_dump_env x "$C3")" && [[ $PROXY_ENABLED == "false" ]]'
check "3b" "no [proxy] -> PROXY_ENDPOINT empty, not a localhost default" \
  'eval "$(config_dump_env x "$C3")" && [[ -z $PROXY_ENDPOINT ]]'
check "3c" "no [proxy] -> PROXY_HEALTH_URL empty" \
  'eval "$(config_dump_env x "$C3")" && [[ -z $PROXY_HEALTH_URL ]]'
check "3d" "no [proxy] -> PROXY_SERVE_CMD empty" \
  'eval "$(config_dump_env x "$C3")" && [[ -z $PROXY_SERVE_CMD ]]'
check "3e" "no [proxy] -> PROXY_CREDENTIALS empty" \
  'eval "$(config_dump_env x "$C3")" && [[ -z $PROXY_CREDENTIALS ]]'

# ── 4. self-dogfood: shipped defaults stay optional (DOG-7) ─────────────────
SHIPPED="$SCRIPT_DIR/swarm.config.toml"
check "4a" "shipped config: optional pi seat not in roster" \
  '[[ $(config_get_seats "$SHIPPED") != *pi* ]]'
check "4b" "shipped config: proxy disabled by default" \
  '[[ $(config_get "proxy.enabled" "false" "$SHIPPED") == "false" ]]'
check "4c" "shipped config: serve_cmd empty by default" \
  '[[ -z $(config_get "proxy.serve_cmd" "" "$SHIPPED") ]]'
check "4d" "shipped config: credentials path empty by default" \
  '[[ -z $(config_get "proxy.credentials" "" "$SHIPPED") ]]'

# ── 5. provider fallback chains (PUB-6) ────────────────────────────────────
C5="$TEST_DIR/kinds-chain.toml"
cat > "$C5" <<'TOML'
[seats.alpha]
name = "alpha"
kinds = ["opencode", "claude"]

[seats.beta]
name = "beta"
default_kind = "agy"
TOML
check "5a" "kinds chain emitted in order" \
  'eval "$(config_dump_env x "$C5")" && [[ $SEAT_KINDS_alpha == "opencode claude" ]]'
check "5b" "SEAT_KIND stays the primary (backward compat)" \
  'eval "$(config_dump_env x "$C5")" && [[ $SEAT_KIND_alpha == "opencode" ]]'
check "5c" "default_kind sugar -> single-element chain" \
  'eval "$(config_dump_env x "$C5")" && [[ $SEAT_KINDS_beta == "agy" && $SEAT_KIND_beta == "agy" ]]'
check "5d" "shipped config: arch seats carry opencode->claude chains" \
  'eval "$(config_dump_env x "$SCRIPT_DIR/swarm.config.toml")" && [[ $SEAT_KINDS_arch_1 == "opencode claude" ]]'

C5B="$TEST_DIR/kinds-conflict.toml"
cat > "$C5B" <<'TOML'
[seats.alpha]
name = "alpha"
kinds = ["opencode", "claude"]
default_kind = "agy"
TOML
check "5e" "default_kind conflicting with kinds[0] fails closed" \
  'if config_dump_env x "$C5B" >/dev/null 2>&1; then false; else true; fi'

C5C="$TEST_DIR/kinds-empty.toml"
cat > "$C5C" <<'TOML'
[seats.alpha]
name = "alpha"
kinds = []
TOML
check "5f" "empty kinds array fails closed" \
  'if config_dump_env x "$C5C" >/dev/null 2>&1; then false; else true; fi'

C5D="$TEST_DIR/kinds-junk.toml"
cat > "$C5D" <<'TOML'
[seats.alpha]
name = "alpha"
kinds = ["opencode", 7]
TOML
check "5g" "non-string chain entry fails closed" \
  'if config_dump_env x "$C5D" >/dev/null 2>&1; then false; else true; fi'

# ── 6. reviewer loop knobs (REV-1) ─────────────────────────────────────────
C6="$TEST_DIR/reviewer-defaults.toml"
cat > "$C6" <<'TOML'
[seats.alpha]
name = "alpha"
default_kind = "agy"
TOML
check "6a" "no [reviewer] table → CONFIG_REVIEW_LOOP 0" \
  'eval "$(config_dump_env x "$C6")" && [[ $CONFIG_REVIEW_LOOP == "0" ]]'
check "6b" "no [reviewer] table → CONFIG_REVIEW_MAX_ROUNDS default 2" \
  'eval "$(config_dump_env x "$C6")" && [[ $CONFIG_REVIEW_MAX_ROUNDS == "2" ]]'

C6B="$TEST_DIR/reviewer-set.toml"
cat > "$C6B" <<'TOML'
[reviewer]
loop = true
max_rounds = 3

[seats.alpha]
name = "alpha"
default_kind = "agy"
TOML
check "6c" "loop = true → CONFIG_REVIEW_LOOP 1" \
  'eval "$(config_dump_env x "$C6B")" && [[ $CONFIG_REVIEW_LOOP == "1" ]]'
check "6d" "max_rounds = 3 → CONFIG_REVIEW_MAX_ROUNDS 3" \
  'eval "$(config_dump_env x "$C6B")" && [[ $CONFIG_REVIEW_MAX_ROUNDS == "3" ]]'
check "6e" "shipped config: reviewer loop ON by default (PROVE-2)" \
  'eval "$(config_dump_env x "$SHIPPED")" && [[ $CONFIG_REVIEW_LOOP == "1" && $CONFIG_REVIEW_MAX_ROUNDS == "2" ]]'
check "6e2" "shipped config: reviewer seat in roster (PROVE-2)" \
  '[[ $(config_get_seats "$SHIPPED") == *reviewer* ]]'

# ── 7. headless safety ceilings (HEADLESS-5) ───────────────────────────────
C7="$TEST_DIR/headless-defaults.toml"
cat > "$C7" <<'TOML'
[swarm]
name = "x"
TOML
check "7a" "no [headless] table → max attempts default 2" \
  'eval "$(config_dump_env x "$C7")" && [[ $CONFIG_HEADLESS_MAX_ATTEMPTS == "2" ]]'
check "7b" "no [headless] table → worker timeout default 600" \
  'eval "$(config_dump_env x "$C7")" && [[ $CONFIG_HEADLESS_WORKER_TIMEOUT_S == "600" ]]'
C7B="$TEST_DIR/headless-set.toml"
cat > "$C7B" <<'TOML'
[headless]
max_verdict_attempts = 3
worker_timeout_s = 900
TOML
check "7c" "explicit ceilings bind" \
  'eval "$(config_dump_env x "$C7B")" && [[ $CONFIG_HEADLESS_MAX_ATTEMPTS == "3" && $CONFIG_HEADLESS_WORKER_TIMEOUT_S == "900" ]]'
C7C="$TEST_DIR/headless-bad.toml"
cat > "$C7C" <<'TOML'
[headless]
max_verdict_attempts = "2"
TOML
check "7d" "truthy-string attempts fail closed" '! config_dump_env x "$C7C" >/dev/null 2>&1'
C7D="$TEST_DIR/headless-zero.toml"
cat > "$C7D" <<'TOML'
[headless]
max_verdict_attempts = 0
TOML
check "7e" "zero attempts fail closed" '! config_dump_env x "$C7D" >/dev/null 2>&1'
check "7f" "shipped config binds the headless ceilings" \
  'eval "$(config_dump_env x "$SHIPPED")" && [[ $CONFIG_HEADLESS_MAX_ATTEMPTS == "2" && $CONFIG_HEADLESS_WORKER_TIMEOUT_S == "600" ]]'

C6C="$TEST_DIR/reviewer-badloop.toml"
cat > "$C6C" <<'TOML'
[reviewer]
loop = "yes"

[seats.alpha]
name = "alpha"
default_kind = "agy"
TOML
check "6f" "loop as truthy string fails closed" \
  'if config_dump_env x "$C6C" >/dev/null 2>&1; then false; else true; fi'

C6D="$TEST_DIR/reviewer-badrounds.toml"
cat > "$C6D" <<'TOML'
[reviewer]
loop = true
max_rounds = 0

[seats.alpha]
name = "alpha"
default_kind = "agy"
TOML
check "6g" "max_rounds = 0 fails closed" \
  'if config_dump_env x "$C6D" >/dev/null 2>&1; then false; else true; fi'

C6E="$TEST_DIR/reviewer-strrounds.toml"
cat > "$C6E" <<'TOML'
[reviewer]
max_rounds = "two"

[seats.alpha]
name = "alpha"
default_kind = "agy"
TOML
check "6h" "max_rounds as string fails closed" \
  'if config_dump_env x "$C6E" >/dev/null 2>&1; then false; else true; fi'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
