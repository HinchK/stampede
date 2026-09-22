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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
