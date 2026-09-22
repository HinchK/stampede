#!/usr/bin/env bash
# tests/test_gh_sync.sh — hermetic suite for lib/gh_sync.sh (DOG-8)
#
# Stub gh on PATH (records every invocation, serves fixture JSON, mints
# create-issue URLs from a counter) — no network, no real repo, ever.
# Pins the five contract behaviours: dry-run-by-default zero writes, drift
# detection both directions, CREATE proposal labels, fail-closed auth, and
# the missing maps/tickets/ guard. Scratch dirs; cleans up after itself.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
# shellcheck disable=SC2034  # vars are consumed inside those eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-ghsync-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PASS=0
FAIL=0

BIN_DIR="$TEST_DIR/bin"       # stub gh lives here, first on PATH during runs
LOG="$TEST_DIR/gh.log"        # one line per stub gh invocation ("$*" joined)
ISSUES="$TEST_DIR/issues.json" # fixture answers for 'gh issue list'
COUNTER="$TEST_DIR/counter"   # monotonically growing issue number for creates
OUT="$TEST_DIR/out"           # gh_sync stdout of the last run
ERR="$TEST_DIR/err"           # gh_sync stderr of the last run
RC=0                          # gh_sync exit code of the last run
AUTH_MODE=ok                  # stub auth posture; 'fail' exercises fail-closed

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()  { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
# check LABEL DESCRIPTION 'ASSERTION (eval)'
check() {
  local label="$1" desc="$2" body="$3"
  if eval "$body" >/dev/null 2>&1; then ok "$label" "$desc"; else bad "$label" "$desc"; fi
}

# ── hermetic gh stub ────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# DOG-8 test stub: records invocations, answers from fixtures, never networks
log="${GH_STUB_LOG:-/dev/null}"
printf '%s\n' "$*" >> "$log"

cmd="${1:-} ${2:-}"

if [[ "$cmd" == "auth status" ]]; then
  if [[ "${GH_STUB_AUTH:-ok}" == "fail" ]]; then
    echo "gh: You are not logged into any GitHub hosts." >&2
    exit 1
  fi
  exit 0
fi

if [[ "$cmd" == "issue list" ]]; then
  cat "${GH_STUB_ISSUES:-/dev/null}"
  exit 0
fi

if [[ "$cmd" == "issue create" ]]; then
  n=100
  [[ -f "${GH_STUB_COUNTER:-}" ]] && n=$(cat "${GH_STUB_COUNTER}")
  n=$((n + 1))
  printf '%s\n' "$n" > "${GH_STUB_COUNTER:?counter file required}"
  printf 'https://github.com/test/repo/issues/%s\n' "$n"
  exit 0
fi

if [[ "$cmd" == "issue close" || "$cmd" == "issue reopen" ]]; then
  exit 0
fi

echo "gh-stub: unhandled invocation: $*" >&2
exit 1
STUB
chmod +x "$BIN_DIR/gh"
printf '100\n' > "$COUNTER"

# run_sync ...args — run gh_sync.sh under the stub; fresh log each run.
# Captures exit code in RC, stdout in OUT, stderr in ERR; never fails itself.
run_sync() {
  RC=0
  : > "$LOG"
  GH_STUB_LOG="$LOG" \
  GH_STUB_ISSUES="$ISSUES" \
  GH_STUB_AUTH="$AUTH_MODE" \
  GH_STUB_COUNTER="$COUNTER" \
  PATH="$BIN_DIR:$PATH" \
    bash "$SCRIPT_DIR/lib/gh_sync.sh" "$@" > "$OUT" 2> "$ERR" || RC=$?
  return 0
}

echo "── gh_sync hermetic suite (scratch: $TEST_DIR)"

# ── fixture: drift lab ──────────────────────────────────────────────────────
# T-A resolved <-> #11 OPEN      -> close remote
# T-B in_progress <-> #12 CLOSED -> reopen remote (push) / resolve local (both)
# T-C in_progress <-> #13 OPEN   -> in sync
R1="$TEST_DIR/drift"
mkdir -p "$R1/maps/tickets"
cat > "$R1/maps/tickets/alpha.md" <<'EOF'
---
id: T-A
title: "Alpha drift"
type: wayfinder:task
status: resolved
github_issue: 11
github_url: "https://github.com/test/repo/issues/11"
---

Body of T-A.
EOF
cat > "$R1/maps/tickets/beta.md" <<'EOF'
---
id: T-B
title: "Beta drift"
type: wayfinder:task
status: in_progress
github_issue: 12
github_url: "https://github.com/test/repo/issues/12"
---

Body of T-B.
EOF
cat > "$R1/maps/tickets/gamma.md" <<'EOF'
---
id: T-C
title: "Gamma steady"
type: wayfinder:task
status: in_progress
github_issue: 13
github_url: "https://github.com/test/repo/issues/13"
---

Body of T-C.
EOF
cat > "$ISSUES" <<'EOF'
[
  {"number": 11, "title": "[T-A] Alpha drift",  "state": "OPEN",   "stateReason": null,       "labels": [], "url": "https://github.com/test/repo/issues/11"},
  {"number": 12, "title": "[T-B] Beta drift",   "state": "CLOSED", "stateReason": "completed", "labels": [], "url": "https://github.com/test/repo/issues/12"},
  {"number": 13, "title": "[T-C] Gamma steady", "state": "OPEN",   "stateReason": null,       "labels": [], "url": "https://github.com/test/repo/issues/13"}
]
EOF

# ── 1. dry-run is the default and performs zero gh writes ───────────────────
check "1a" "default run (no flags) exits 0 despite drift" \
  'run_sync --target-dir "$R1" --repo test/repo; [[ $RC -eq 0 ]]'
check "1b" "zero gh write invocations under default dry-run" \
  '! grep -Eq "issue (create|close|reopen|edit)" "$LOG"'
check "1c" "read-only gh calls did happen (auth status, issue list)" \
  'grep -q "^auth status$" "$LOG" && grep -q "^issue list" "$LOG"'
check "1d" "human output carries the DRY RUN zero-write banner" \
  'grep -q "DRY RUN" "$OUT"'
check "1e" "dry-run leaves ticket frontmatter untouched (no synced_at)" \
  '! grep -q "^synced_at:" "$R1/maps/tickets/alpha.md"'
check "1f" "explicit --dry-run flag: still zero writes" \
  'run_sync --target-dir "$R1" --repo test/repo --dry-run; [[ $RC -eq 0 ]] && ! grep -Eq "issue (create|close|reopen|edit)" "$LOG"'

# ── 2. drift detection, both directions ─────────────────────────────────────
check "2a" "resolved ticket + OPEN remote -> UPDATE_REMOTE close" \
  'run_sync --target-dir "$R1" --repo test/repo --json; [[ $RC -eq 0 ]] && jq -e ".items[] | select(.ticket_id==\"T-A\") | .action==\"UPDATE_REMOTE\" and .subaction==\"close\"" "$OUT"'
check "2b" "open ticket + CLOSED remote (push) -> UPDATE_REMOTE reopen" \
  'jq -e ".items[] | select(.ticket_id==\"T-B\") | .action==\"UPDATE_REMOTE\" and .subaction==\"reopen\"" "$OUT"'
check "2c" "matched pair -> IN_SYNC" \
  'jq -e ".items[] | select(.ticket_id==\"T-C\") | .action==\"IN_SYNC\"" "$OUT"'
check "2d" "direction both flips the pull arm: open ticket + CLOSED remote -> UPDATE_LOCAL resolve" \
  'run_sync --direction both --target-dir "$R1" --repo test/repo --json; jq -e ".items[] | select(.ticket_id==\"T-B\") | .action==\"UPDATE_LOCAL\" and .subaction==\"resolve\"" "$OUT"'
check "2e" "summary counts add up (1 close, 1 pull, 1 in-sync, 3 total)" \
  'jq -e ".summary.update_remote==1 and .summary.update_local==1 and .summary.in_sync==1 and .summary.total==3" "$OUT"'

# ── 3. unlinked tickets propose CREATE with the label contract ──────────────
R2="$TEST_DIR/create"
mkdir -p "$R2/maps/tickets"
cat > "$R2/maps/tickets/delta.md" <<'EOF'
---
id: T-D
title: "Delta feature"
type: wayfinder:task
status: in_progress
---

Body of T-D.
EOF
cat > "$R2/maps/tickets/eps.md" <<'EOF'
---
id: T-E
title: "Epsilon spike"
type: wayfinder:prototype
status: in_progress
---

Body of T-E.
EOF
# An unrelated titled issue must not be mistaken for a LINK
cat > "$ISSUES" <<'EOF'
[
  {"number": 21, "title": "[T-Z] Unrelated", "state": "OPEN", "stateReason": null, "labels": [], "url": "https://github.com/test/repo/issues/21"}
]
EOF
check "3a" "unlinked tickets plan CREATE (no accidental LINK to unrelated issue)" \
  'run_sync --target-dir "$R2" --repo test/repo --json; [[ $RC -eq 0 ]] && jq -e "(.items | map(select(.action==\"CREATE\") | .ticket_id) | sort) == [\"T-D\",\"T-E\"]" "$OUT"'
check "3b" "CREATE detail carries the [ID] title form" \
  'jq -e ".items[] | select(.ticket_id==\"T-D\") | .detail | contains(\"[T-D] Delta feature\")" "$OUT"'
check "3c" "apply creates exactly two issues" \
  'run_sync --apply --target-dir "$R2" --repo test/repo; [[ $RC -eq 0 ]] && [[ $(grep -c "^issue create" "$LOG") -eq 2 ]]'
check "3d" "every create carries swarm:ticket label" \
  '[[ $(grep -cF -- "--label swarm:ticket" "$LOG") -eq 2 ]]'
check "3e" "task ticket gets type:task label" \
  'grep -qF -- "--label type:task" "$LOG"'
check "3f" "prototype ticket gets type:prototype label" \
  'grep -qF -- "--label type:prototype" "$LOG"'
check "3g" "create title is the [ID] title form" \
  'grep -qF -- "--title [T-D] Delta feature" "$LOG"'
check "3h" "frontmatter anchored: github_issue + github_url written back" \
  'grep -q "^github_issue: 101$" "$R2/maps/tickets/delta.md" && grep -qF "github_url: \"https://github.com/test/repo/issues/101\"" "$R2/maps/tickets/delta.md" && grep -q "^github_issue: 102$" "$R2/maps/tickets/eps.md"'
check "3i" "frontmatter anchored: synced_at stamped" \
  'grep -q "^synced_at:" "$R2/maps/tickets/delta.md" && grep -q "^synced_at:" "$R2/maps/tickets/eps.md"'
check "3j" "apply performed no close/reopen side effects" \
  '! grep -Eq "issue (close|reopen)" "$LOG"'

# ── 4. fail-closed auth blocks everything, with remediation ─────────────────
AUTH_MODE=fail
check "4a" "gh auth failure exits non-zero" \
  'run_sync --target-dir "$R1" --repo test/repo; [[ $RC -ne 0 ]]'
check "4b" "remediation text points at gh auth login" \
  'grep -F "gh auth login" "$ERR"'
check "4c" "auth failure stops before any gh read/write of issues" \
  '[[ $(wc -l < "$LOG" | tr -d " ") -eq 1 ]] && grep -q "^auth status$" "$LOG"'
check "4d" "auth failure blocks writes even under --apply" \
  'run_sync --apply --target-dir "$R1" --repo test/repo; [[ $RC -ne 0 ]] && ! grep -Eq "issue (create|close|reopen|edit)" "$LOG"'
AUTH_MODE=ok

# ── 5. missing maps/tickets/ exits non-zero (existing contract, pinned) ─────
R5="$TEST_DIR/notickets"
mkdir -p "$R5"
cat > "$ISSUES" <<'EOF'
[]
EOF
check "5a" "target without maps/tickets/ exits non-zero" \
  'run_sync --target-dir "$R5" --repo test/repo; [[ $RC -ne 0 ]]'
check "5b" "error names the missing tickets directory" \
  'grep -F "Maps tickets directory not found" "$ERR"'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
