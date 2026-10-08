#!/bin/bash
# tests/test_standby.sh — FALLBACK-1 standby orchestrator seat
#
# Hermetic: scratch target repo + swarm.config.toml fixture + PATH-stubbed
# herdr (agent get/wait/start, pane split/close, notification) driving the
# REAL lib/standby.sh through the REAL lib/quota.sh gate (whose probe also
# runs against the stubbed herdr — the wall is a banner in pane output).
# Covers: disabled-by-default refusal, wall/force takeover policy, the
# single-orchestrator lock, stand-down handshake, and brief render
# invariants (every hard rule present, all placeholders resolved).

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ [%s] %s\n' "$1" "$2"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ [%s] %s\n' "$1" "$2"; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-standby.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
STUB="$SCRATCH/bin"; mkdir -p "$STUB"

command -v jq >/dev/null 2>&1 || { printf 'test_standby: SKIP — jq missing\n'; exit 0; }
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/pyenv.sh"
resolve_python >/dev/null 2>&1 || { printf 'test_standby: SKIP — no tomllib interpreter\n'; exit 0; }
set +e   # pyenv.sh arms set -e; expected-failure cases below must not kill the suite

# ── herdr stub: scripted responses + a call log ────────────────────────────
LOG="$SCRATCH/herdr.log"; : > "$LOG"
SPLIT_RET='{"result":{"pane":{"pane_id":"w9:p42"}}}'
LOOPER_LIVE=1        # agent get rc for the real looper
START_RC=0
cat > "$STUB/herdr" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$LOG"
case " \$* " in
  *" agent get "*)  exit $(( 1 - LOOPER_LIVE )) ;;
  *" agent start "*) exit $START_RC ;;
  *" pane split "*) printf '%s\n' '$SPLIT_RET'; exit 0 ;;
  *" agent read "*)
    # quota probe reads the looper seat's pane: banner controlled below
    if [[ "\$3" == "looper-t-x" && -n "\$QUOTA_BANNER" ]]; then
      printf 'Individual quota reached. Resets in '
      printf '%s' "\$QUOTA_BANNER"
      printf '.\n'
    fi
    exit 0 ;;
  *" agent wait "*) exit 0 ;;
  *" pane close "*) exit 0 ;;
  *" notification "*) exit 0 ;;
esac
exit 0
EOF
chmod +x "$STUB/herdr"
export QUOTA_BANNER=""    # empty = account clear; set to wall it
PATH="$STUB:/usr/bin:/bin"
export PATH

# ── scratch target: git repo + profile + config + ledger ──────────────────
T="$SCRATCH/target"
mkdir -p "$T"
git -C "$T" init -q -b main
git -C "$T" config user.email t@t; git -C "$T" config user.name t
printf 'x\n' > "$T/x"; git -C "$T" add x; git -C "$T" commit -qm init
mkdir -p "$T/.herdr-swarm"
printf 'REPO=t/x\nTEST_CMD=make test\nECOSYSTEM=generic\nDOCS_DIR=docs\n' \
  > "$T/.herdr-swarm/profile.env"
CFG="$T/swarm.config.toml"
cat > "$CFG" <<'EOF'
[swarm]
name = "x"
[seats.looper]
name = "looper"
default_kind = "agy"
brief = "briefs/looper.in.md"
[seats.arch]
name = "arch"
default_kind = "opencode"
[seats.looper_standby]
name = "looper-standby"
default_kind = "opencode"
model = "zai-coding-plan/glm-5.3-flash"
brief = "briefs/looper-standby.in.md"
enabled = false
EOF
jq -cn '{version: 2, workspace_id: "w9", seats: [
  {name: "looper-t-x", kind: "agy", pane: "w9:p7", isolated: false},
  {name: "arch-t-x", kind: "opencode", pane: "w9:p3", isolated: true,
   worktree_dir: "/tmp/none", branch: "swarm/x/arch"}]}' > "$T/.herdr-swarm/seats.json"

S="$REPO_ROOT/lib/standby.sh"
LOCK="$T/.herdr-swamp/orchestrator.lock"; LOCK="$T/.herdr-swarm/orchestrator.lock"

echo "==> standby orchestrator seat (FALLBACK-1)"

# [1] disabled by default: up refuses before any wall logic
out=$(bash "$S" up "$T" 2>&1); rc=$?
[[ "$rc" -ne 0 && "$out" == *"disabled in config"* ]] \
  && ok 1 "disabled seat: up refuses with remediation" || bad 1 "rc=$rc out=$out"
[[ ! -f "$LOCK" ]] && ok 1b "no lock written on refusal" || bad 1b "lock leaked"

# also: the SHIPPED config ships the seat disabled (repo invariant)
if [[ "${STAMPEDE_TEST_REAL_CFG:-1}" == "1" ]] \
   && grep -A20 '^\[seats\.looper_standby\]' "$REPO_ROOT/swarm.config.toml" | grep -q 'enabled = false'; then
  ok 1c "shipped swarm.config.toml keeps looper_standby disabled by default"
else
  bad 1c "shipped config must keep [seats.looper_standby] enabled = false"
fi

# [2] enabled + wall clear + real looper live → refuse without --force
sed -i '' 's/^enabled = false$/enabled = true/' "$CFG"
out=$(bash "$S" up "$T" 2>&1); rc=$?
[[ "$rc" -ne 0 && "$out" == *"refusing"*"--force"* ]] \
  && ok 2 "clear quota + live looper: up refuses, names --force" || bad 2 "rc=$rc out=$out"
[[ ! -f "$LOCK" ]] && ok 2b "still no lock" || bad 2b "lock leaked"

# [3] enabled + walled → takeover succeeds: split by explicit anchor id,
#     start, brief delivered by path, lock written with holder=standby
export QUOTA_BANNER="1h30m0s"
out=$(bash "$S" up "$T" 2>&1); rc=$?
[[ "$rc" == 0 ]] && ok 3 "walled: up succeeds rc 0" || bad 3 "rc=$rc out=$out"
grep -q "pane split w9:p7 --direction down --cwd $T --no-focus" "$LOG" \
  && ok 3a "split addressed the looper anchor pane by explicit id (never --current)" \
  || bad 3a "split invocation wrong: $(grep 'pane split' "$LOG" | tail -1)"
grep -q -- "-- --model zai-coding-plan/glm-5.3-flash" "$LOG" \
  && ok 3b "agent start carries the configured flash model" || bad 3b "model arg missing"
[[ -f "$T/.herdr-swarm/briefs/looper-standby.md" ]] \
  && ok 3c "brief rendered into target .herdr-swarm/briefs/" || bad 3c "brief missing"
grep -q "agent prompt looper-standby-t-x " "$LOG" \
  && ok 3d "brief delivered by file-path prompt (nonce protocol)" || bad 3d "no delivery prompt"
jq -e '.holder == "standby" and .seat == "looper-standby-t-x" and .pane == "w9:p42" and .forced == false' \
  "$LOCK" >/dev/null 2>&1 \
  && ok 3e "lock: holder standby, seat, pane, forced=false" || bad 3e "lock: $(cat "$LOCK")"

# [4] single-orchestrator: while the lock is held, up refuses even walled
out=$(bash "$S" up "$T" 2>&1); rc=$?
[[ "$rc" == 0 ]] \
  && ok 4 "idempotent: up while already holding the lock → rc 0 no-op" || bad 4 "rc=$rc out=$out"
jq '.holder = "looper"' "$LOCK" > "$LOCK.tmp" && mv "$LOCK.tmp" "$LOCK"
out=$(bash "$S" up "$T" 2>&1); rc=$?
[[ "$rc" -ne 0 && "$out" == *"single-orchestrator"* ]] \
  && ok 4b "lock held by another holder: up refuses (double orchestration prevented)" \
  || bad 4b "rc=$rc out=$out"
jq '.holder = "standby"' "$LOCK" > "$LOCK.tmp" && mv "$LOCK.tmp" "$LOCK"

# [5] clear wall + --force → forced takeover, lock records forced=true
rm -f "$LOCK"; export QUOTA_BANNER=""
out=$(bash "$S" up "$T" --force 2>&1); rc=$?
[[ "$rc" == 0 ]] && ok 5 "--force overrides the clear wall (rc 0, warned)" || bad 5 "rc=$rc out=$out"
[[ "$out" == *"forced takeover"* ]] && ok 5b "forced takeover warned" || bad 5b "no warning: $out"
jq -e '.forced == true' "$LOCK" >/dev/null 2>&1 && ok 5c "lock records forced=true" || bad 5c "lock: $(cat "$LOCK")"

# [6] down: missing handoff warns but --yes proceeds; pane closed, lock gone
out=$(bash "$S" down "$T" --yes 2>&1); rc=$?
[[ "$rc" == 0 && "$out" == *"WARNING"*"handoff"* ]] \
  && ok 6 "down warns on missing handoff, still stands down with --yes" || bad 6 "rc=$rc out=$out"
grep -q "pane close w9:p42" "$LOG" && ok 6a "recorded pane closed by explicit id" || bad 6a "close missing"
[[ ! -f "$LOCK" ]] && ok 6b "lock released" || bad 6b "lock lingers"

# [7] down without the lock: no-op; down with foreign holder: refuse
out=$(bash "$S" down "$T" --yes 2>&1); rc=$?
[[ "$rc" == 0 && "$out" == *"nothing to stand down"* ]] \
  && ok 7 "down without lock is a clean no-op" || bad 7 "rc=$rc out=$out"
jq -cn '{holder: "looper", seat: "looper-t-x", pane: "w9:p7"}' > "$LOCK"
out=$(bash "$S" down "$T" --yes 2>&1); rc=$?
[[ "$rc" -ne 0 ]] && ok 7b "down refuses a foreign-held lock" || bad 7b "rc=$rc out=$out"
rm -f "$LOCK"

# [8] handoff present: down proceeds without warning, names the real looper
export QUOTA_BANNER="1h30m0s"
bash "$S" up "$T" >/dev/null 2>&1
mkdir -p "$T/.herdr-swarm/research"
printf '# handoff\n- dispatched T1 to arch-t-x\n' > "$T/.herdr-swarm/research/looper-standby-handoff.md"
out=$(bash "$S" down "$T" --yes 2>&1); rc=$?
[[ "$rc" == 0 && "$out" == *"handoff file present"*"looper-t-x resumes"* ]] \
  && ok 8 "clean handshake: handoff noted, resumption named" || bad 8 "rc=$rc out=$out"

# [9] brief render invariants: every hard rule, zero unresolved placeholders
B="$T/.herdr-swarm/briefs/looper-standby.md"
grep -q '{{' "$B" && bad 9 "unresolved placeholders in rendered brief" || ok 9 "all placeholders resolved"
for rule in \
  "no agy dispatch" "Never promote" "arbiter promote" "git stash" \
  "Never write \`main\`" "forbidden paths" "blocked review is reported as BLOCKED" \
  "No cross-pane injection" "ARCH DONE" "partition.sh check" "wait-output" \
  "looper-standby-handoff.md" "3-line preamble"; do
  if grep -qi -- "$rule" "$B"; then ok "9r" "brief rule present: $rule"
  else bad "9r" "brief rule MISSING: $rule"; fi
done

# [10] status: wall, lock and config state readable, rc 0
export QUOTA_BANNER=""
out=$(bash "$S" status "$T" 2>&1); rc=$?
[[ "$rc" == 0 ]] && ok 10 "status rc 0" || bad 10 "rc=$rc"
[[ "$out" == *"wall:        clear"* && "$out" == *"real looper: live"* && "$out" == *"looper_standby enabled"* ]] \
  && ok 10a "status reports wall/looper/config truthfully" || bad 10a "out=$out"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
