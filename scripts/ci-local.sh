#!/usr/bin/env bash
#
# scripts/ci-local.sh — local CI-parity wrapper (DOG-18)
#
# `make check` is the repo's one aggregate gate and stays authoritative: this
# script runs it verbatim (same target, exit code propagated unmodified) and
# adds the one parity signal make check cannot see on its own — whether the
# LOCAL shellcheck matches the version CI pins (SC_VERSION in
# .github/workflows/ci.yml). That pin exists because the 0-warning lint bar
# is version-dependent (DOG-14: apt's build flagged warnings 0.11.0 does
# not), so a version skew is exactly the way local and CI can silently
# disagree while `make check` keeps passing.
#
# Modes:
#   default    mismatch is a WARNING; exit code is make check's own.
#   --strict   after a GREEN gate, exit 1 if parity could not be established
#              (mismatch, shellcheck missing, or no pin to compare against).
#              A failing gate always propagates its own exit code first —
#              strict never masks or alters the gate's verdict.
#
# This is deliberately NOT a second gate: it cannot disagree with
# `make check` about pass/fail; it only annotates the pin-parity signal.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CI_YML="$ROOT/.github/workflows/ci.yml"

usage() {
  cat <<EOF
Usage: scripts/ci-local.sh [--strict]

Runs \`make check\` (exit code authoritative, unmodified) and reports whether
the local shellcheck matches the CI pin (SC_VERSION in .github/workflows/ci.yml).

  default    pin mismatch is a warning; exit code is make check's own
  --strict   additionally exit 1 after a green gate when parity could not be
             established (mismatch, shellcheck missing, or no pin present)
EOF
}

STRICT=0
case "${1:-}" in
  "")            ;;
  --strict)      STRICT=1 ;;
  -h|--help)     usage; exit 0 ;;
  *)             usage >&2
                 printf 'ci-local: unknown argument: %s\n' "$1" >&2
                 exit 1 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 1; }

# CI pin: first SC_VERSION: assignment in the workflow, quotes optional.
PIN=$(sed -nE 's/^[[:space:]]*SC_VERSION:[[:space:]]*"?([^"[:space:]]+)"?/\1/p' \
       "$CI_YML" 2>/dev/null | head -n1)

parity=unknown   # ok | mismatch | no-shellcheck | no-pin
if [[ -z "$PIN" ]]; then
  printf 'ci-local: warning: no SC_VERSION pin found in .github/workflows/ci.yml — skipping parity check\n' >&2
  parity=no-pin
elif ! command -v shellcheck >/dev/null 2>&1; then
  printf 'ci-local: warning: shellcheck not on PATH — cannot check CI pin parity (make check lint will fail on its own if this matters)\n' >&2
  parity=no-shellcheck
else
  LOCAL_VER=$(shellcheck --version | awk '/^version:/{print $2; exit}')
  if [[ -n "$LOCAL_VER" && "$LOCAL_VER" == "${PIN#[vV]}" ]]; then
    printf 'ci-local: shellcheck parity: local %s == CI pin %s\n' "$LOCAL_VER" "$PIN"
    parity=ok
  else
    printf 'ci-local: warning: local shellcheck %s != CI pin %s — the 0-warning lint bar is version-dependent (DOG-14); install the pinned version for parity. The gate verdict below is make check own and stays authoritative.\n' \
      "${LOCAL_VER:-unknown}" "$PIN" >&2
    parity=mismatch
  fi
fi

# The gate itself: exit code captured and propagated verbatim.
if make -C "$ROOT" check; then
  GATE_RC=0
else
  GATE_RC=$?
fi
if (( GATE_RC != 0 )); then
  exit "$GATE_RC"
fi

if (( STRICT )); then
  case "$parity" in
    ok)           exit 0 ;;
    mismatch)     printf 'ci-local: --strict: shellcheck pin mismatch — install the pinned version for CI parity\n' >&2; exit 1 ;;
    no-shellcheck) printf 'ci-local: --strict: shellcheck not on PATH — parity unverified\n' >&2; exit 1 ;;
    no-pin)       printf 'ci-local: --strict: no SC_VERSION pin found — parity unverifiable\n' >&2; exit 1 ;;
  esac
fi
exit 0
