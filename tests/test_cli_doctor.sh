#!/bin/bash
# tests/test_cli_doctor.sh — `stampede doctor` end-to-end (PUB-2)
#
# Hermetic: scratch config + scratch PATH stubbing herdr/gh/jq/timeout and
# the provider CLIs under test, inside a scratch git repo. Proves the seat
# table (OK / MISSING+remediation / SKIP for disabled seats / BAD-KIND for
# unregistered kinds), preflight integration, and the exit-code contract:
# enabled seats decide the exit; disabled seats never do.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1 (rc=$3)"; else bad "$1 (want rc=$2, got rc=$3)"; fi; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-doctor.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin"
cd "$SCRATCH" && git init -q .

# ── PATH stubs: every preflight error-level probe goes green; provider
# presence is varied per case below.
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$SCRATCH/bin/$1"; chmod +x "$SCRATCH/bin/$1"; }
stub herdr   'exit 0'
stub gh      'exit 0'
stub jq      'exit 0'
stub timeout 'shift; exec "$@"'
stub claude  'echo "claude 1.2.3 (stub)"'
stub agy     'echo "agy 9.9 (stub)"'

# Resolve the interpreter with the FULL path first, then narrow.
if ! PYTHON_OUT=$(cd "$REPO_ROOT" && bash lib/pyenv.sh 2>/dev/null); then
  printf 'test_cli_doctor: SKIP — no tomllib-capable interpreter on PATH\n'
  exit 0
fi
export PYTHON_BIN="$PYTHON_OUT"

# Minimal PATH: scratch stubs + system basics. Real provider CLIs on the
# dev machine must not make a MISSING-seat case silently pass.
PATH="$SCRATCH/bin:/usr/bin:/bin"
export PATH

cfg="$SCRATCH/swarm.config.toml"

echo "==> stampede doctor (PUB-2)"

# [1] one healthy enabled seat + one disabled → rc 0, OK and SKIP rows
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
[seats.pi]
name = "pi"
default_kind = "pi"
enabled = false
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "healthy enabled + disabled seat → rc 0" 0 "$rc"
printf '%s\n' "$out" | grep -Eq 'pm +claude +OK' && ok "enabled healthy seat row OK" || bad "pm row missing"
printf '%s\n' "$out" | grep -q 'pi *pi *SKIP' && ok "disabled seat row SKIP" || bad "pi row missing SKIP"
[[ "$out" == *"preflight:"* ]] && ok "preflight matrix included" || bad "no preflight output"

# [2] enabled seat with missing provider → rc 1 + remediation in the row
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
[seats.arch_1]
name = "arch-1"
default_kind = "opencode"
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "missing provider on enabled seat → rc 1" 1 "$rc"
printf '%s\n' "$out" | grep -Eq 'arch_1 +opencode +MISSING' \
  && printf '%s\n' "$out" | grep -q 'opencode.ai' \
  && ok "MISSING row carries install pointer" || bad "arch_1 row missing"

# [3] enabled seat with unregistered kind → rc 1, BAD-KIND
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
[seats.weird]
name = "weird"
default_kind = "brand-new-llm"
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "unregistered kind on enabled seat → rc 1" 1 "$rc"
[[ "$out" == *"BAD-KIND"* ]] && ok "BAD-KIND surfaced" || bad "no BAD-KIND: $out"

# [4] preflight failure also fails doctor: kill the gh stub's auth
stub gh 'exit 1'
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "preflight error (gh auth) → rc 1" 1 "$rc"
[[ "$out" == *"gh-auth"* ]] && ok "gh-auth failure surfaced" || bad "gh-auth: $out"

# [5] missing config → rc 1, no table
out=$(STAMPEDE_CONFIG="$SCRATCH/nope.toml" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "missing config → rc 1" 1 "$rc"
[[ "$out" == *"config not found"* ]] && ok "missing config message" || bad "cfg msg: $out"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
