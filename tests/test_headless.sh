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
# preserve the failing status through cleanup (bash 3.2 EXIT-trap quirk:
# a plain trap body can re-report success and hide a red run)
trap 'rc=$?; rm -rf "$TEST_DIR"; exit $rc' EXIT

ok()   { printf '  ✓ [%s] %s\n' "$1" "${2:-}"; PASS=$((PASS + 1)); }
bad()  { printf '  ✗ [%s] %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }
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
# 2f. round-2 critique: a relative BRIEF path resolves against the caller's
# cwd at validation time but the worker resolves it inside the worktree —
# spawn must normalize to absolute so the pointer means the same file.
export HL_STUB_RECORD="$TEST_DIR/stub-rel.txt"
( cd "$TEST_DIR" && headless_spawn worker-r brief.md "$WT" opencode >/dev/null )
sleep 0.6
check 2f  "relative brief normalized to absolute in the delivered prompt" \
  'grep -qE "argv=run BRIEF \(file\): $TEST_DIR/brief.md " "$TEST_DIR/stub-rel.txt"'
export HL_STUB_RECORD="$TEST_DIR/stub-record.txt"

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

# 4f. round-2 critique: marker detection must survive trailing log noise —
# the conclusion marker is the last marker line, not strictly the final line.
printf '\n\n' >> "$STATE_DIR/logs/worker-e.log"
check 4f  "status still reports exited rc=0 despite trailing blank lines" \
  '[[ $(headless_status worker-e) == "exited rc=0" ]]'

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

# ── 6. kill: signal delivered, pidfile cleaned, CHILD dies too ─────────────
# Round-2 critique: the pidfile records the wrapper subshell; TERM to the
# wrapper must not orphan the vendor CLI child still running in the worktree.
export HL_STUB_SLEEP=30
headless_spawn worker-z "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
sleep 0.4
zpid=$(cat "$STATE_DIR/pids/worker-z.pid")
zchild=$(pgrep -P "$zpid" | head -n1)
check 6pre "vendor child located before kill" '[[ -n "$zchild" ]]'
headless_kill worker-z >/dev/null
sleep 0.5
check 6a  "kill terminates the wrapper" '! kill -0 "$zpid" 2>/dev/null'
check 6a2 "kill terminates the vendor child (no orphan)" '! kill -0 "$zchild" 2>/dev/null'
check 6b  "kill removes the pidfile" '[[ ! -f "$STATE_DIR/pids/worker-z.pid" ]]'
check 6c  "kill of an untracked worker is idempotent (rc 0)" 'headless_kill worker-ghost >/dev/null 2>&1'

# 6d. direct TERM to the wrapper (outside headless_kill) also reaches the
# child: the wrapper's signal traps forward, then it concludes WITHOUT the
# exit marker — a killed run is `dead`, never `exited rc=N`.
headless_spawn worker-t "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
sleep 0.4
tpid=$(cat "$STATE_DIR/pids/worker-t.pid")
tchild=$(pgrep -P "$tpid" | head -n1)
kill -TERM "$tpid" 2>/dev/null
sleep 0.5
check 6d  "direct TERM: wrapper forwards signal to child" '! kill -0 "$tchild" 2>/dev/null'
check 6d2 "signalled run reports dead (no fabricated exit marker)" \
  '[[ $(headless_status worker-t) == dead ]]'

# ── 7. hard wall-clock timeout on every spawn (HEADLESS-5 hazard 2) ────────
# Fail closed when no runnable timeout(1) exists (DOG-15 pattern): spawn
# must refuse rather than run unbounded.
if TIMEOUT_BIN="/nonexistent/timeout" headless_spawn worker-to "$TEST_DIR/brief.md" "$WT" opencode >/dev/null 2>&1; then
  bad "7a spawn refuses when timeout(1) is unresolvable"
else
  ok "7a spawn refuses when timeout(1) is unresolvable"
fi
[[ ! -f "$STATE_DIR/pids/worker-to.pid" ]] \
  && ok "7a2 refused spawn left no pidfile" || bad "7a2 refused spawn left no pidfile"
# shellcheck disable=SC1091  # resolve_timeout lives in the sibling common lib
if source "$SCRIPT_DIR/lib/common.sh" && resolve_timeout; then
  export HL_STUB_SLEEP=30 CONFIG_HEADLESS_WORKER_TIMEOUT_S=1
  headless_spawn worker-hang "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
  sleep 2.5
  [[ "$(headless_status worker-hang)" == "exited rc=124" ]] \
    && ok "7b hung worker timeout-killed at the wall clock (rc=124)" \
    || bad "7b hung worker: $(headless_status worker-hang)"
  unset CONFIG_HEADLESS_WORKER_TIMEOUT_S
  export HL_STUB_SLEEP=0.3
else
  printf '  · [7b] skipped — no runnable timeout(1) on this machine\n' >&2
fi

# headless_reap: stale pidfiles (dead holder) evicted on the next pass,
# live ones untouched (PROVE-7's kill -0 idiom, surfaced for pids/).
stale_pid=$(sh -c 'sleep 0.1 & printf %s $!' | head -n1)
sleep 0.4
printf '%s\n' "$stale_pid" > "$STATE_DIR/pids/worker-gone.pid"
export HL_STUB_SLEEP=30
headless_spawn worker-live "$TEST_DIR/brief.md" "$WT" opencode >/dev/null
headless_reap >/dev/null 2>&1
check 7c  "reap evicts the stale pidfile" '[[ ! -f "$STATE_DIR/pids/worker-gone.pid" ]]'
check 7d  "reap leaves the live worker's pidfile alone" \
  '[[ -f "$STATE_DIR/pids/worker-live.pid" ]]'
headless_kill worker-live >/dev/null 2>&1
export HL_STUB_SLEEP=0.3

# ── 8. re-verdict ceiling + dead-letter (HEADLESS-5 hazards 1+3) ───────────
SLOG="$TEST_DIR/session.jsonl"; : > "$SLOG"
# two conclusive failures for DL-1 — attempt 1 critiques, attempt 2 dead-letters
printf '{"ticket":"DL-1","sha":"aaaaaaa","suite":"RED"}\n' >> "$SLOG"
[[ $(headless_attempt_count DL-1 "$SLOG") == 1 ]] \
  && ok "8a attempt count reads the session log" || bad "8a attempt count: $(headless_attempt_count DL-1 "$SLOG")"
if headless_deadletter_due DL-1 2 "$SLOG" 2>/dev/null; then
  bad "8b below ceiling: not yet dead-letter due"
else
  ok "8b below ceiling: not yet dead-letter due"
fi
printf '{"ticket":"DL-1","sha":"bbbbbbb","suite":"RED"}\n' >> "$SLOG"
headless_deadletter_due DL-1 2 "$SLOG" \
  && ok "8c at ceiling: dead-letter due" || bad "8c at ceiling: not due"
printf '{"ticket":"DL-2","sha":"ccccccc","suite":"green"}\n' >> "$SLOG"
if headless_deadletter_due DL-2 2 "$SLOG" 2>/dev/null; then
  bad "8d green tickets never dead-letter"
else
  ok "8d green tickets never dead-letter"
fi

dead_letter_record DL-1 bbbbbbb "suite RED twice — re-verdict ceiling" sess-test
dead_letter_record DL-9 ddddddd "review blocked after 2 rounds" sess-test
dead_letter_record DL-3 eeeeeee "other run" sess-other
DL="$STATE_DIR/dead-letter.jsonl"
check 8e  "dead-letter records are structured JSONL" \
  'jq -e -s "length == 3" "$DL" >/dev/null'
check 8f  "records carry session, ticket, sha, reason" \
  'jq -e -s ".[0] | .session == \"sess-test\" and .ticket == \"DL-1\" and .reason != \"\"" "$DL" >/dev/null'
[[ $(headless_deadletter_count sess-test "$DL") == 2 ]] \
  && ok "8g per-run count filters by session" || bad "8g count: $(headless_deadletter_count sess-test "$DL")"
if "$SCRIPT_DIR/lib/headless.sh" deadletter-check sess-test "$STATE_DIR" >/dev/null 2>&1; then
  bad "8h deadletter-check exits non-zero when this run has entries"
else
  ok "8h deadletter-check exits non-zero when this run has entries"
fi
"$SCRIPT_DIR/lib/headless.sh" deadletter-check sess-clean "$STATE_DIR" >/dev/null 2>&1 \
  && ok "8i deadletter-check exits 0 for a clean run" || bad "8i clean run exited non-zero"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))