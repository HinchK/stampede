#!/bin/bash
# tests/test_cli_init.sh — `stampede init` acceptance (PUB-7)
#
# Hermetic: scratch target dirs with copied brief templates, stub provider
# CLIs on a minimal PATH (so real installs cannot mask the zero-provider
# case), and acceptance through the REAL parser — every generated config
# must satisfy config_dump_env, because 'never writes invalid config' is
# the whole point of the command.
#
# shellcheck disable=SC2154  # SEAT_*/CONFIG_* vars are assigned dynamically by `eval "$(config_dump_env …)"` and only then asserted

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1 (rc=$3)"; else bad "$1 (want rc=$2, got rc=$3)"; fi; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-init.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# Resolve interpreter with the FULL path, then narrow.
if ! PYTHON_OUT=$(cd "$REPO_ROOT" && bash lib/pyenv.sh 2>/dev/null); then
  printf 'test_cli_init: SKIP — no tomllib-capable interpreter on PATH\n'
  exit 0
fi
export PYTHON_BIN="$PYTHON_OUT"

mkdir -p "$SCRATCH/bin"
stub() { printf '#!/usr/bin/env bash\necho "%s 1.0 (stub)"\n' "$1" > "$SCRATCH/bin/$1"; chmod +x "$SCRATCH/bin/$1"; }
PATH="$SCRATCH/bin:/usr/bin:/bin"
export PATH

new_target() { # name -> fresh target dir with briefs copied in
  local d="$SCRATCH/$1"
  mkdir -p "$d/briefs"
  cp "$REPO_ROOT"/briefs/*.md "$d/briefs/"
  printf '%s\n' "$d"
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/config.sh"

echo "==> stampede init (PUB-7)"

# ── preset × provider matrix: every generated config parses for real ─────
stub claude; stub opencode
for preset in minimal standard; do
  T=$(new_target "m-${preset}-single")
  out=$(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset "$preset" --kinds claude 2>&1) && rc=0 || rc=$?
  check "[$preset] single forced kind writes config" 0 "$rc"
  if config_dump_env t1 "$T/swarm.config.toml" >/dev/null 2>&1; then
    ok "[$preset] generated config passes the real parser"
  else
    bad "[$preset] generated config does not parse"
  fi
  eval "$(config_dump_env t1 "$T/swarm.config.toml")"
  if [[ "$preset" == "minimal" ]]; then
    [[ "$SEAT_KEYS" == "looper arch_1" ]] && ok "[minimal] roster: looper + arch_1" || bad "[minimal] roster: $SEAT_KEYS"
  else
    [[ "$SEAT_KEYS" == "pm arch_1 looper docs gh" ]] && ok "[standard] roster: 5 seats" || bad "[standard] roster: $SEAT_KEYS"
  fi
  [[ "$SEAT_KIND_arch_1" == "claude" && "$SEAT_KINDS_arch_1" == "claude" ]] \
    && ok "[$preset] single kind binds default_kind sugar" || bad "[$preset] kind binding"
  [[ "${SEAT_WORKTREE_arch_1:-0}" == "1" ]] && ok "[$preset] worker seat isolated (worktree)" || bad "[$preset] worktree"
done

T=$(new_target "m-multi")
(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset minimal --kinds opencode,claude >/dev/null 2>&1)
eval "$(config_dump_env t2 "$T/swarm.config.toml")"
[[ "$SEAT_KINDS_arch_1" == "opencode claude" && "$SEAT_KIND_arch_1" == "opencode" ]] \
  && ok "multi kind chain: primary first, fallback after" || bad "chain: ${SEAT_KINDS_arch_1:-none}"

T=$(new_target "m-detect")
(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset minimal >/dev/null 2>&1)
eval "$(config_dump_env t3 "$T/swarm.config.toml")"
[[ "$SEAT_KINDS_looper" == "claude opencode" ]] \
  && ok "detection fills the chain in registry order" || bad "detect: ${SEAT_KINDS_looper:-none}"

# ── fail-closed paths ─────────────────────────────────────────────────────
T=$(new_target "f-zero")
rm -f "$SCRATCH/bin/claude" "$SCRATCH/bin/opencode"
out=$(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset minimal 2>&1) && rc=0 || rc=$?
check "zero providers detected → rc 1" 1 "$rc"
[[ "$out" == *"stampede doctor"* ]] && ok "zero-provider error points at doctor" || bad "no doctor pointer: $out"
[[ ! -f "$T/swarm.config.toml" ]] && ok "nothing written on failure" || bad "config leaked on failure"

T=$(new_target "f-badkind")
out=$(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset minimal --kinds claude,tesla 2>&1) && rc=0 || rc=$?
check "unregistered kind → rc 1" 1 "$rc"
[[ "$out" == *"not provider kinds"* ]] && ok "unknown kind named in error" || bad "err: $out"

T=$(new_target "f-nopreset")
(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive >/dev/null 2>&1) && rc=0 || rc=$?
check "--non-interactive without --preset → rc 2" 2 "$rc"

T=$(new_target "f-notty")
(cd "$T" && "$REPO_ROOT/bin/stampede" init </dev/null >/dev/null 2>&1) && rc=0 || rc=$?
check "interactive with non-tty stdin → rc 1" 1 "$rc"

T=$(new_target "f-briefs")
mkdir -p "$T/briefs" && rm "$T"/briefs/*.md
(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset standard --kinds claude >/dev/null 2>&1) && rc=0 || rc=$?
check "missing brief templates → rc 1" 1 "$rc"

# ── non-destructive overwrite discipline ─────────────────────────────────
T=$(new_target "f-force")
stub claude
(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset minimal --kinds claude >/dev/null 2>&1)
printf '# my hand edits\n' >> "$T/swarm.config.toml"
(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset minimal --kinds claude >/dev/null 2>&1) && rc=0 || rc=$?
check "existing config without --force → rc 1" 1 "$rc"
grep -q '# my hand edits' "$T/swarm.config.toml" && ok "refusal preserves hand edits" || bad "hand edits lost"
(cd "$T" && "$REPO_ROOT/bin/stampede" init --non-interactive --preset minimal --kinds claude --force >/dev/null 2>&1) && rc=0 || rc=$?
check "--force overwrites" 0 "$rc"
[[ -f "$T/swarm.config.toml.bak" ]] && grep -q '# my hand edits' "$T/swarm.config.toml.bak" \
  && ok ".bak preserves the previous file" || bad "bak missing or wrong"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
