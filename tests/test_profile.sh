#!/usr/bin/env bash
# tests/test_profile.sh — ecosystem/test-command detection suite
# Covers the make / run_all.sh branches (#PROFILE-MAKE), marker precedence,
# and the fail-closed generic path. Scratch dirs; cleans up after itself.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-prof-$$-XXXX)
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

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/profile.sh"
# shellcheck disable=SC1091  # resolver: python entry points fail with the
# remedy, never a traceback (DOG-1)
source "$SCRIPT_DIR/lib/pyenv.sh"

echo "── profile detection suite (scratch: $TEST_DIR)"

# ── 1. Makefile with a test target → ecosystem make, TEST_CMD "make test" ──
R1="$TEST_DIR/make-repo"; mkdir -p "$R1"
printf 'test:\n\techo hi\n' > "$R1/Makefile"
check "1a" "Makefile w/ test target -> ecosystem make" \
  '[[ $(detect_ecosystem "$R1") == make ]]'
check "1b" "Makefile w/ test target -> TEST_CMD make test" \
  '[[ $(detect_test_cmd "$R1") == "make test" ]]'

# ── 2. Makefile WITHOUT a test target stays fail-closed generic ────────────
R2="$TEST_DIR/mk-notest"; mkdir -p "$R2"
printf 'build:\n\techo hi\n' > "$R2/Makefile"
check "2a" "Makefile w/o test target -> generic" \
  '[[ $(detect_ecosystem "$R2") == generic ]]'
check "2b" "Makefile w/o test target -> detect_test_cmd fails closed" \
  '! detect_test_cmd "$R2"'

# ── 3. run_all.sh convention ────────────────────────────────────────────────
R3="$TEST_DIR/runall-repo"; mkdir -p "$R3"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R3/run_all.sh"
chmod +x "$R3/run_all.sh"
check "3a" "run_all.sh (executable) -> ecosystem run_all" \
  '[[ $(detect_ecosystem "$R3") == run_all ]]'
check "3b" "run_all.sh (executable) -> TEST_CMD ./run_all.sh" \
  '[[ $(detect_test_cmd "$R3") == "./run_all.sh" ]]'
R3b="$TEST_DIR/runall-nox"; mkdir -p "$R3b"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R3b/run_all.sh"
check "3c" "run_all.sh (not executable) -> TEST_CMD bash run_all.sh" \
  '[[ $(detect_test_cmd "$R3b") == "bash run_all.sh" ]]'

# ── 4. ecosystem markers take precedence over a stray Makefile ─────────────
R4="$TEST_DIR/py-repo"; mkdir -p "$R4"
printf '[project]\nname = "x"\n' > "$R4/pyproject.toml"
printf 'test:\n\techo hi\n' > "$R4/Makefile"
check "4a" "pyproject beats Makefile -> python" \
  '[[ $(detect_ecosystem "$R4") == python ]]'
# The python TEST_CMD branches on which runner is installed, so pin the
# environment rather than inheriting the developer's. Asserting only the uv
# branch made this suite pass wherever uv happened to exist and fail on a
# runner without it — the same class of defect as DOG-15's missing timeout(1).
PROBE_BIN="$TEST_DIR/stub-bin"; mkdir -p "$PROBE_BIN"
printf '#!/bin/sh\nexit 0\n' > "$PROBE_BIN/uv"; chmod +x "$PROBE_BIN/uv"
check "4b" "python TEST_CMD with uv present -> uv run pytest -q" \
  '[[ $(PATH="$PROBE_BIN:$PATH" detect_test_cmd "$R4") == "uv run pytest -q" ]]'
check "4c" "python TEST_CMD with no uv and no poetry.lock -> pytest -q" \
  '[[ $(PATH=/usr/bin:/bin detect_test_cmd "$R4") == "pytest -q" ]]'

# ── 5. empty repo stays fail-closed ─────────────────────────────────────────
R5="$TEST_DIR/empty-repo"; mkdir -p "$R5"
check "5a" "empty repo -> generic" '[[ $(detect_ecosystem "$R5") == generic ]]'
check "5b" "empty repo -> detect_test_cmd fails closed" '! detect_test_cmd "$R5"'

# ── 6. runnable gate still rejects synthetic commands ───────────────────────
check "6a" '"make test" is runnable' 'test_cmd_is_runnable "make test"'
check "6b" '"" not runnable' '! test_cmd_is_runnable ""'
check "6c" '"none" not runnable' '! test_cmd_is_runnable none'
check "6d" '"true" not runnable' '! test_cmd_is_runnable true'

# ── 7. self-dogfood: this repo's Makefile detected from a clean clone copy ──
R7="$TEST_DIR/selfclone"; mkdir -p "$R7"
cp "$SCRIPT_DIR/Makefile" "$R7/Makefile"
check "7a" "self-dogfood: swarm repo -> make" '[[ $(detect_ecosystem "$R7") == make ]]'
check "7b" "self-dogfood: swarm repo -> make test (clean clone, no profile.env)" \
  '[[ $(detect_test_cmd "$R7") == "make test" ]]'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
