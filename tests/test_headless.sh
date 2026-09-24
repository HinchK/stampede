#!/usr/bin/env bash
# tests/test_headless.sh — lib/headless.sh suite (HEADLESS-3)
# Hermetic: stub vendor CLIs on PATH (short-lived shell scripts standing in
# for claude/opencode/agy), no network, no Herdr daemon, no PTY anywhere.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-headless-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()   { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
bad()  { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { # LABEL DESCRIPTION 'ASSERTION (eval)'
  local label="$1" desc="$2" body="$3"
  if eval "$body" >/dev/null 2>&1; then ok "$label" "$desc"; else bad "$label" "$desc"; fi
}

# Hermetic state + fake vendor CLI bin dir. The stubs record their argv and
# cwd to a file whose path travels via the environment (inherited by the
# spawned subshell), sleep a controllable interval, exit a controllable rc.
export STATE_DIR="$TEST_DIR/state"
export HL_STUB_RECORD="$TEST_DIR/stub-record.txt"
WT="$TEST_DIR/wt"; mkdir -p "$WT"
BIN="$TEST_DIR/bin"; mkdir -p "$BIN"
for vendor in claude opencode agy; do
  cat > "$BIN/$vendor" <<'STUB'
#!/bin/sh
{ printf 'cwd=%s\n' "$(pwd)"; printf 'argv=%s\n' "$*"; } > "$HL_STUB_RECORD"
sleep "${HL_STUB_SLEEP:-0.3}"
exit "${HL_STUB_RC:-0}"
STUB
  chmod +x "$BIN/$vendor"
done
export PATH="$BIN:$PATH"

# Guard the red state loudly: sourcing a missing lib under bash 3.2 with an
# EXIT trap can exit 0, and every headless_* assertion would then pass
# vacuously as "command not found" under `!`.
if [[ ! -f "$SCRIPT_DIR/lib/headless.sh" ]]; then
  printf 'test_headless: lib/headless.sh does not exist (build it first)\n' >&2
  exit 1
fi
# shellcheck disable=SC1091  # library under test
source "$SCRIPT_DIR/lib/headless.sh"

printf 'brief body\n' > "$TEST_DIR/brief.md"

echo "── headless harness suite (scratch: $TEST_DIR)"

# ── 1. spawn: pid file, log file, live process, prompt via CLI argv ────────
export HL_STUB_SLEEP=0.6
out_line=$(headless_spawn worker-a "$TEST_DIR/brief.md" "$WT" opencode)
check 1a  "spawn creates pid file with the live pid" \
  '[[ -f "$STATE_DIR/pids/worker-a.pid" ]] && kill -0 "$(cat "$STATE_DIR/pids/worker-a.pid")" 2>/dev/null'
check 1b  "spawn creates the log file" \
  '[[ -f "$STATE_DIR/logs/worker-a.log" ]]'
check 1c  "spawn stdout names pid, log, and channel" \
  'grep -q "pid=" <<<"$out_line" && grep -q "log=" <<<"$out_line" && grep -q "channel=" <<<"$out_line"'
check 1d  "status reports running while stub is alive" \
  '[[ $(headless_status worker-a) == running* ]]'

# ── 2. brief delivery: compact pointer via vendor entrypoint, no PTY ───────
sleep 1
REC=$(cat "$HL_STUB_RECORD")
check 2a  "vendor ran inside the worktree" \
  'grep -q "cwd=$WT" <<<"$REC"'
check 2b  "prompt delivered as CLI argv (opencode run form)" \
  'grep -q "^argv=run BRIEF (file):" <<<"$REC"'
check 2c  "prompt carries the REPLY CHANNEL pointer" \
  'grep -q "REPLY CHANNEL: write your complete response to" <<<"$REC"'
check 2d  "channel file path is namespaced by worker under state/channel" \
  'grep -qE "REPLY CHANNEL: write your complete response to [^ ]*/channel/worker-a-[0-9]+-[0-9]+\.md" <<<"$REC"'
check 2e  "no keystroke-injection machinery in executable library lines" \
  '! sed "/^[[:space:]]*#/d" "$SCRIPT_DIR/lib/headless.sh" | grep -nE "send-keys|agent prompt|enter$" '

# ── 3. vendor-specific entrypoints ─────────────────────────────────────────
export HL_STUB_SLEEP=0.1 HL_STUB_RECORD="$TEST_DIR/stub-claude.txt"
headless_spawn worker-c "$TEST_DIR/brief.md" "$WT" claude >/dev/null
sleep 0.5
check 3a  "claude kind invokes claude -p" \
  'grep -q "^argv=-p BRIEF (file):" "$TEST_DIR/stub-claude.txt"'
HL_STUB_RECORD="$TEST_DIR/stub-agy.txt" headless_spawn worker-g "$TEST_DIR/brief.md" "$WT" agy >/dev/null
sleep 0.5
check 3b  "agy kind invokes agy -p" \
  'grep -q "^argv=-p BRIEF (file):" "$TEST_DIR/stub-agy.txt"'
check 3c  "unknown vendor kind fails closed, nothing spawned" \
  '! headless_spawn worker-x "$TEST_DIR/brief.md" "$WT" gemini 2>/dev/null'
check 3d  "missing brief file fails closed" \
  '! headless_spawn worker-x "$TEST_DIR/nope.md" "$WT" opencode 2>/dev/null'
check 3e  "missing worktree dir fails closed" \
  '! headless_spawn worker-x "$TEST_DIR/brief.md" "$TEST_DIR/no-wt" opencode 2>/dev/null'

# ── 4. lifecycle: exited vs dead vs untracked ──────────────────────────────
export HL_STUB_RECORD="$TEST_DIR/stub-record.txt"
export HL_STUB_SLEEP=0.2 HL_STUB_RC=0
headless_spawn worker-e "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
sleep 0.8
check 4a  "clean exit reported as exited rc=0" \
  '[[ $(headless_status worker-e) == "exited rc=0" ]]'
check 4b  "exit marker durable in the log" \
  'grep -q "^\[_exit_ rc=0\]$" "$STATE_DIR/logs/worker-e.log"'
export HL_STUB_RC=3
headless_spawn worker-e2 "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
sleep 0.8
check 4c  "vendor failure reported as exited rc=3" \
  '[[ $(headless_status worker-e2) == "exited rc=3" ]]'
headless_spawn worker-k "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
kill -9 "$(cat "$STATE_DIR/pids/worker-k.pid")" 2>/dev/null
sleep 0.8
check 4d  "hard kill (no marker) reported as dead" \
  '[[ $(headless_status worker-k) == dead ]]'
check 4e  "never-spawned worker reported untracked" \
  '[[ $(headless_status worker-ghost 2>/dev/null) == untracked ]]'

# ── 5. spawn guards: double-spawn refused, stale pidfile evicted ───────────
export HL_STUB_SLEEP=1
headless_spawn worker-d "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
check 5a  "double-spawn while running is refused" \
  '! headless_spawn worker-d "$TEST_DIR/brief.md" "$WT" opencode 2>/dev/null'
headless_kill worker-d >/dev/null 2>&1
sleep 0.3
# stale pidfile: spawn a short-lived pid outside the lib, wait for its death
stale_pid=$(sh -c 'sleep 0.1 & printf %s $!' | head -n1)
sleep 0.4
printf '%s\n' "$stale_pid" > "$STATE_DIR/pids/worker-s.pid"
check 5b  "spawn evicts a stale pidfile and proceeds" \
  'headless_spawn worker-s "$TEST_DIR/brief.md" "$WT" opencode >/dev/null 2>&1'
headless_kill worker-s >/dev/null 2>&1

# ── 6. kill: signal delivered, pidfile cleaned ─────────────────────────────
export HL_STUB_SLEEP=30
headless_spawn worker-z "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
zpid=$(cat "$STATE_DIR/pids/worker-z.pid")
headless_kill worker-z >/dev/null
sleep 0.3
check 6a  "kill terminates the subprocess" '! kill -0 "$zpid" 2>/dev/null'
check 6b  "kill removes the pidfile" '[[ ! -f "$STATE_DIR/pids/worker-z.pid" ]]'
check 6c  "kill of an untracked worker is idempotent (rc 0)" 'headless_kill worker-ghost >/dev/null 2>&1'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
