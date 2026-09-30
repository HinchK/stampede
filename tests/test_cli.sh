#!/bin/bash
# tests/test_cli.sh — bin/stampede entrypoint (PUB-1)
#
# Hermetic: builds a scratch tree with bin/stampede copied verbatim, a stub
# herdr-loop-swarm.sh that echoes its argv (proving pass-through is exec of
# the real argument vector, unchanged), and scratch lib/cli command modules.
# Never touches a live workspace.

set -u
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }
check() { # desc, want_rc, got_rc
  if [[ "$2" == "$3" ]]; then ok "$1 (rc=$3)"; else bad "$1 (want rc=$2, got rc=$3)"; fi
}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-cli.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

mkdir -p "$SCRATCH/bin" "$SCRATCH/lib/cli"
cp "$REPO_ROOT/bin/stampede" "$SCRATCH/bin/stampede"
chmod +x "$SCRATCH/bin/stampede"

# Stub launcher: records argv and exits 0 — enough to prove delegation.
cat > "$SCRATCH/herdr-loop-swarm.sh" <<'EOF'
#!/usr/bin/env bash
printf 'LAUNCHER-ARGV:%s\n' "$*"
exit 0
EOF
chmod +x "$SCRATCH/herdr-loop-swarm.sh"

# Scratch convention command with a dashed name (underscore folding).
cat > "$SCRATCH/lib/cli/stampede-hello-world.sh" <<'EOF'
#!/usr/bin/env bash
stampede_cmd_hello_world() {
  printf 'HELLO-ARGV:%s\n' "$*"
}
EOF

S="$SCRATCH/bin/stampede"

echo "==> bin/stampede entrypoint (PUB-1)"

# [1] lifecycle pass-through: argv reaches the launcher unchanged
out=$("$S" up /tmp/some-target -m s 2>&1); rc=$?
[[ "$out" == "LAUNCHER-ARGV:up /tmp/some-target -m s" ]] \
  && ok "up delegates argv verbatim" || bad "up argv mangled: $out"
check "up exit code" 0 "$rc"

out=$("$S" status mydir 2>&1)
[[ "$out" == "LAUNCHER-ARGV:status mydir" ]] && ok "status delegates" || bad "status: $out"

out=$("$S" down mydir -y --keep-ws 2>&1)
[[ "$out" == "LAUNCHER-ARGV:down mydir -y --keep-ws" ]] && ok "down delegates flags" || bad "down: $out"

out=$("$S" verify dir 5000 2>&1)
[[ "$out" == "LAUNCHER-ARGV:verify dir 5000" ]] && ok "verify delegates" || bad "verify: $out"

# [2] bare invocation and leading flags fall through to the launcher
out=$("$S" 2>&1)
[[ "$out" == "LAUNCHER-ARGV:" ]] && ok "bare invocation delegates" || bad "bare: $out"
out=$("$S" -m s 2>&1)
[[ "$out" == "LAUNCHER-ARGV:-m s" ]] && ok "leading flags delegate" || bad "flags: $out"

# [3] convention dispatch: discovered with no dispatcher edit
out=$("$S" hello-world a b 2>&1); rc=$?
[[ "$out" == "HELLO-ARGV:a b" ]] && ok "convention cmd discovered + underscore fold" || bad "hello-world: $out"
check "convention cmd exit code" 0 "$rc"

# [4] unknown command fails closed with usage
out=$("$S" definitely-not-a-cmd 2>&1); rc=$?
[[ "$rc" == 1 ]] && ok "unknown command rc=1" || bad "unknown rc=$rc"
[[ "$out" == *"unknown command: definitely-not-a-cmd"* && "$out" == *"Usage: stampede"* ]] \
  && ok "unknown command prints usage" || bad "usage missing: $out"

# [5] help surfaces discovered commands
out=$("$S" help 2>&1); rc=$?
[[ "$rc" == 0 ]] && ok "help rc=0" || bad "help rc=$rc"
[[ "$out" == *"hello-world"* && "$out" == *"herdr-loop-swarm.sh"* ]] \
  && ok "help lists discovered + legacy names" || bad "help incomplete: $out"

# [6] module without the contract function fails loudly
cat > "$SCRATCH/lib/cli/stampede-broken.sh" <<'EOF'
#!/usr/bin/env bash
# defines nothing
EOF
"$S" broken 2>/dev/null; rc=$?
[[ "$rc" == 1 ]] && ok "module without stampede_cmd_* fails rc=1" || bad "broken module rc=$rc"

# [7] real-tree smoke: the repo's own entrypoint resolves its real root
# (uses the true launcher's -h, which is read-only)
out=$("$REPO_ROOT/bin/stampede" -h 2>&1); rc=$?
[[ "$rc" == 0 && "$out" == *"Usage:"* ]] && ok "real entrypoint help works" || bad "real help rc=$rc"

# [8] headless subcommand: module, parsing, dispatch (HEADLESS-6)
[[ -f "$REPO_ROOT/lib/cli/stampede-headless.sh" ]] \
  && ok "headless module at convention path" || bad "module lib/cli/stampede-headless.sh missing"
out=$("$REPO_ROOT/bin/stampede" headless --help 2>&1); rc=$?
[[ "$rc" == 0 && "$out" == *"--max-tickets"* && "$out" == *"--timeout"* ]] \
  && ok "headless --help rc=0, documents both flags" || bad "headless --help rc=$rc: $out"
"$REPO_ROOT/bin/stampede" headless --bogus-flag >/dev/null 2>&1; rc=$?
[[ "$rc" != 0 ]] && ok "headless unknown flag rejected" || bad "bogus flag rc=$rc"
"$REPO_ROOT/bin/stampede" headless --max-tickets abc /tmp >/dev/null 2>&1; rc=$?
[[ "$rc" != 0 ]] && ok "headless non-numeric max rejected" || bad "abc max rc=$rc"
out=$("$REPO_ROOT/bin/stampede" help 2>&1)
[[ "$out" == *"headless"* ]] && ok "help lists headless" || bad "help missing headless"

# [9] headless end-to-end: scratch repo, stub vendor, NO herdr on PATH
HB_BIN=$(mktemp -d "$SCRATCH/hb-bin.XXXXXX")
cat > "$HB_BIN/opencode" <<'EOF'
#!/bin/sh
brief=$(printf '%s\n' "$*" | sed -nE 's/.*BRIEF \(file\): ([^ ]+) .*/\1/p')
tid=$(sed -nE 's/^id:[[:space:]]*//p' "$brief" 2>/dev/null | head -n1 | tr -d '[:space:]')
sha=$(git rev-parse HEAD 2>/dev/null || printf 0000000000000000000000000000000000000000)
reply=$(printf '%s\n' "$*" | sed -nE 's/.*REPLY CHANNEL: write your complete response to ([^ ]+) and.*/\1/p')
[ -n "$reply" ] && printf 'worker reply for %s\n' "${tid:-unknown}" > "$reply"
printf 'ARCH DONE #%s %s\n' "${tid:-unknown}" "$sha"
EOF
chmod +x "$HB_BIN/opencode"
# timeout(1) is required by the harness (fail-closed otherwise); reuse the
# machine's own if present, else the e2e degrades to the skip note below.
if command -v gtimeout >/dev/null 2>&1; then ln -s "$(command -v gtimeout)" "$HB_BIN/timeout"
elif command -v timeout >/dev/null 2>&1; then ln -s "$(command -v timeout)" "$HB_BIN/timeout"; fi
# jq must be on the stripped HB_PATH too: when pyenv resolves to a python
# outside /opt/homebrew/bin (e.g. ~/.local/bin/python3.14), HB_PATH loses
# the homebrew dir entirely and the batch's jq-dependent steps (seats.json
# ledger, queue reads) fail under the batch shell's set -e.
if command -v jq >/dev/null 2>&1; then ln -s "$(command -v jq)" "$HB_BIN/jq"; fi
# git as well: Apple's /usr/bin/git shim is present, but keep the invocation
# environment identical to a real one when homebrew git exists.
if command -v git >/dev/null 2>&1 && [[ "$(command -v git)" != /usr/bin/* ]]; then ln -s "$(command -v git)" "$HB_BIN/git"; fi
# The supervisor source-time needs a tomllib-capable interpreter (DOG-1) —
# the stripped PATH must carry the one this repo resolves.
HB_PY=$(bash "$REPO_ROOT/lib/pyenv.sh" 2>/dev/null || true)
HB_PATH="$HB_BIN:/usr/bin:/bin"
[[ -n "$HB_PY" ]] && HB_PATH="$HB_BIN:$(dirname "$HB_PY"):/usr/bin:/bin"
HR_REPO=$(mktemp -d "$SCRATCH/hr-repo.XXXXXX")
git -C "$HR_REPO" init -q -b main
git -C "$HR_REPO" config user.email t@t; git -C "$HR_REPO" config user.name t
git -C "$HR_REPO" remote add origin https://github.com/t/scratch.git
printf '.herdr-swarm/\n' > "$HR_REPO/.gitignore"
printf 'test:\n\t@true\n' > "$HR_REPO/Makefile"
mkdir -p "$HR_REPO/maps/tickets"
printf 'x\n' > "$HR_REPO/f.txt"; git -C "$HR_REPO" add -A; git -C "$HR_REPO" commit -qm base
printf -- '---\nid: T-RESOLVED\nstatus: resolved\nowns: f.txt\n---\nbody\n' > "$HR_REPO/maps/tickets/t0.md"
  printf -- '---\nid: T-1\nstatus: backlog\nowns: f.txt\n---\nbody one\n' > "$HR_REPO/maps/tickets/t1.md"
  printf -- '---\nid: T-2\nstatus: backlog\n---\nbody two\n' > "$HR_REPO/maps/tickets/t2.md"
  git -C "$HR_REPO" add -A; git -C "$HR_REPO" commit -qm tickets
  # slugify for the ARB-SLUG-1 init-ref below (the ref must be created under
  # the same slug the batch itself resolves from the profile REPO).
  # set +e/+o pipefail: lib/common.sh runs `set -euo pipefail` at its top —
  # without the restore, the leak flips this suite (written for set -u only)
  # into fail-abort mode, and any later non-zero command (e.g. [10]'s
  # deliberately-failing batch) kills the whole suite before rc capture.
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  set +e +o pipefail
  # ARB-SLUG-1 (arrived via integration): drain refuses when the canonical
  # integration ref is missing — one-time explicit init, exactly the setup a
  # real repo gets, with the slug the batch itself will resolve (profile
  # REPO "t/scratch" → slugify).
  PROJECT_SLUG="$(slugify t/scratch)" REPO_DIR="$HR_REPO" STATE_DIR="$HR_REPO/.herdr-swarm" \
    BASE_BRANCH=main PATH="$HB_PATH" bash "$REPO_ROOT/lib/arbiter.sh" init-ref >/dev/null 2>&1 || true
  git -C "$HR_REPO" show-ref --verify --quiet "refs/heads/swarm/$(slugify t/scratch)/integration" \
    && ok "integration ref initialized (ARB-SLUG-1 one-time setup)" || bad "init-ref failed"

if [[ -e "$HB_BIN/timeout" ]]; then
  out=$(PATH="$HB_PATH" "$REPO_ROOT/bin/stampede" headless "$HR_REPO" --max-tickets 1 2>&1); rc=$?
  [[ "$rc" == 0 ]] && ok "headless e2e rc=0 without herdr on PATH" || bad "e2e rc=$rc: $(printf '%s' "$out" | tail -3)"
  jq -e -s 'any(.[]; (.ticket|tostring) == "T-1" and .suite == "green")' \
    "$HR_REPO/.herdr-swarm/session-verdicts.jsonl" >/dev/null 2>&1 \
    && ok "T-1 gated green via log-harvested verdict" || bad "no green T-1 verdict"
  jq -e -s 'any(.[]; (.ticket|tostring) == "T-2")' \
    "$HR_REPO/.herdr-swarm/session-verdicts.jsonl" >/dev/null 2>&1 \
    && bad "max-tickets=1 ignored (T-2 processed)" || ok "max-tickets=1 honored (T-2 untouched)"
  jq -e -s 'any(.[]; (.ticket|tostring) == "T-RESOLVED")' \
    "$HR_REPO/.herdr-swarm/session-verdicts.jsonl" >/dev/null 2>&1 \
    && bad "resolved ticket dispatched" || ok "resolved tickets skipped"
  jq -e -s 'any(.[]; (.ticket|tostring) == "T-1" and .status == "integrated")' \
    "$HR_REPO/.herdr-swarm/integration.jsonl" >/dev/null 2>&1 \
    && ok "green verdict drained to integrated IN-BATCH (HL-RED-1)" || bad "T-1 not integrated in-batch: $(tail -3 "$HR_REPO/.herdr-swarm/integration.jsonl" 2>/dev/null)"
  jq -e -s 'any(.[]; ((.ticket|tostring) == "T-1") and .status == "queued")' \
    "$HR_REPO/.herdr-swarm/integration.jsonl" >/dev/null 2>&1 \
    && bad "T-1 left queued (undrained)" || ok "nothing left queued after the batch"
  jq -e '(.leases | length) == 0' "$HR_REPO/.herdr-swarm/leases.json" >/dev/null 2>&1 \
    && ok "lease released after in-batch integration" || bad "lease still held: $(cat "$HR_REPO/.herdr-swarm/leases.json" 2>/dev/null)"
  ls "$HR_REPO/.herdr-swarm/channel"/*.md >/dev/null 2>&1 \
    && ok "reply channel opened for the worker" || bad "no channel file"
  grep -lq 'ARCH DONE #T-1' "$HR_REPO"/.herdr-swarm/logs/*.log 2>/dev/null \
    && ok "vendor log captured the verdict anchor" || bad "no verdict in logs/"
else
  printf '  · [9] skipped — no timeout(1) available for the harness\n'
fi

# [10] headless wall-clock timeout: never-verdict worker, finite exit
if [[ -e "$HB_BIN/timeout" ]]; then
  HR2=$(mktemp -d "$SCRATCH/hr2.XXXXXX")
  git -C "$HR2" init -q -b main
  git -C "$HR2" config user.email t@t; git -C "$HR2" config user.name t
  git -C "$HR2" remote add origin https://github.com/t/scratch2.git
  printf '.herdr-swarm/\n' > "$HR2/.gitignore"
  printf 'test:\n\t@true\n' > "$HR2/Makefile"
  mkdir -p "$HR2/maps/tickets"
  printf 'x\n' > "$HR2/f.txt"; git -C "$HR2" add -A; git -C "$HR2" commit -qm base
  printf -- '---\nid: T-HANG\nstatus: backlog\n---\nbody\n' > "$HR2/maps/tickets/th.md"
  git -C "$HR2" add -A; git -C "$HR2" commit -qm tickets
  printf '#!/bin/sh\nsleep 60\n' > "$HB_BIN/opencode"; chmod +x "$HB_BIN/opencode"
  t0=$SECONDS
  PATH="$HB_PATH" "$REPO_ROOT/bin/stampede" headless "$HR2" --max-tickets 1 --timeout 3 >/dev/null 2>&1; rc=$?
  el=$((SECONDS - t0))
  [[ "$rc" != 0 ]] && ok "timeout batch exits non-zero (rc=$rc)" || bad "hang batch rc=0"
  [[ "$el" -lt 30 ]] && ok "timeout bounded the run (${el}s)" || bad "run took ${el}s"
  jq -e -s 'any(.[]; .ticket == "T-HANG")' "$HR2/.herdr-swarm/dead-letter.jsonl" >/dev/null 2>&1 \
    && ok "unconcluded ticket dead-lettered" || bad "no dead-letter for T-HANG"
  [[ -z "$(ls "$HR2/.herdr-swarm/pids" 2>/dev/null)" ]] \
    && ok "worker killed + pidfile cleaned at batch end" || bad "pidfile left: $(ls "$HR2/.herdr-swarm/pids")"
fi

# [11] HL-RED-1: first-RED no longer concludes a ticket — the critique turn
# runs (empty-commit re-verdict), the ceiling is reachable in-batch, the
# dead letter names it, the lease frees, and the batch exits 1.
if [[ -e "$HB_BIN/timeout" ]]; then
  HR3=$(mktemp -d "$SCRATCH/hr3.XXXXXX")
  git -C "$HR3" init -q -b main
  git -C "$HR3" config user.email t@t; git -C "$HR3" config user.name t
  git -C "$HR3" remote add origin https://github.com/t/scratch3.git
  printf '.herdr-swarm/\n' > "$HR3/.gitignore"
  printf 'test:\n\t@exit 1\n' > "$HR3/Makefile"          # the gate is RED, always
  mkdir -p "$HR3/maps/tickets"
  printf 'x\n' > "$HR3/f.txt"; git -C "$HR3" add -A; git -C "$HR3" commit -qm base
  printf -- '---\nid: T-RED\nstatus: backlog\n---\nbody\n' > "$HR3/maps/tickets/tred.md"
  git -C "$HR3" add -A; git -C "$HR3" commit -qm tickets
  cat > "$HB_BIN/opencode" <<'EOF'
#!/bin/sh
brief=$(printf '%s\n' "$*" | sed -nE 's/.*BRIEF \(file\): ([^ ]+) .*/\1/p')
reply=$(printf '%s\n' "$*" | sed -nE 's/.*REPLY CHANNEL: write your complete response to ([^ ]+) and.*/\1/p')
[ -n "$reply" ] && printf 'worker reply\n' > "$reply"
if grep -q 'headless critique turn' "$brief" 2>/dev/null; then
  tid=$(sed -nE 's/^ARCH DONE #([A-Za-z0-9_.-]+).*/\1/p' "$brief" | head -n1)
  git commit -q --allow-empty -m "critique re-verdict" 2>/dev/null
  printf 'ARCH DONE #%s %s\n' "$tid" "$(git rev-parse HEAD)"
else
  tid=$(sed -nE 's/^id:[[:space:]]*//p' "$brief" | head -n1 | tr -d '[:space:]')
  printf 'ARCH DONE #%s %s\n' "$tid" "$(git rev-parse HEAD)"
fi
EOF
  chmod +x "$HB_BIN/opencode"
  PATH="$HB_PATH" "$REPO_ROOT/bin/stampede" headless "$HR3" --max-tickets 1 --timeout 90 >"$SCRATCH/hl-red.out" 2>&1; rc=$?
  [[ "$rc" == 1 ]] \
    && ok "RED-to-ceiling batch exits 1 (was 0)" || bad "T-RED batch rc=$rc: $(tail -3 "$SCRATCH/hl-red.out")"
  nrec=$(jq -s '[.[] | select((.ticket|tostring) == "T-RED")] | length' \
    "$HR3/.herdr-swarm/session-verdicts.jsonl" 2>/dev/null)
  nred=$(jq -s '[.[] | select((.ticket|tostring) == "T-RED" and (.suite == "RED" or .suite == "invalidated"))] | length' \
    "$HR3/.herdr-swarm/session-verdicts.jsonl" 2>/dev/null)
  twoshas=$(jq -r -s '[.[] | select((.ticket|tostring) == "T-RED")] | ([.[].sha] | unique | length)' \
    "$HR3/.herdr-swarm/session-verdicts.jsonl" 2>/dev/null)
  [[ "$nred" -ge 1 && "$nrec" -ge 2 && "$twoshas" == 2 ]] \
    && ok "critique cycle ran both attempts (${nrec} records at ${twoshas} shas; ceiling attempt records as dead_letter)" \
    || bad "attempts: nrec=$nrec nred=$nred shas=$twoshas"
  jq -e -s 'any(.[]; (.ticket|tostring) == "T-RED" and .suite == "dead_letter")' \
    "$HR3/.herdr-swarm/session-verdicts.jsonl" >/dev/null 2>&1 \
    && ok "ceiling reached: DEAD_LETTER recorded" || bad "no dead_letter record"
  jq -e -s 'any(.[]; .ticket == "T-RED" and ((.reason // "") | contains("re-verdict ceiling")))' \
    "$HR3/.herdr-swarm/dead-letter.jsonl" >/dev/null 2>&1 \
    && ok "dead-letter reason names the ceiling" || bad "reason wrong: $(cat "$HR3/.herdr-swarm/dead-letter.jsonl" 2>/dev/null)"
  jq -e '(.leases | length) == 0' "$HR3/.herdr-swarm/leases.json" >/dev/null 2>&1 \
    && ok "dead-lettered ticket's lease released" || bad "lease held: $(cat "$HR3/.herdr-swarm/leases.json" 2>/dev/null)"
fi

# [12] HL-RED-1: in-batch drain+release un-wedges later no-owns tickets —
# two whole-repo tickets through ONE batch (pre-fix, the first green's
# lease parked the second forever).
if [[ -e "$HB_BIN/timeout" ]]; then
  HR4=$(mktemp -d "$SCRATCH/hr4.XXXXXX")
  git -C "$HR4" init -q -b main
  git -C "$HR4" config user.email t@t; git -C "$HR4" config user.name t
  git -C "$HR4" remote add origin https://github.com/t/scratch4.git
  printf '.herdr-swarm/\n' > "$HR4/.gitignore"
  printf 'test:\n\t@true\n' > "$HR4/Makefile"
  mkdir -p "$HR4/maps/tickets"
  printf 'x\n' > "$HR4/f.txt"; git -C "$HR4" add -A; git -C "$HR4" commit -qm base
  printf -- '---\nid: T-A\nstatus: backlog\n---\nbody a\n' > "$HR4/maps/tickets/ta.md"
  printf -- '---\nid: T-B\nstatus: backlog\n---\nbody b\n' > "$HR4/maps/tickets/tb.md"
  git -C "$HR4" add -A; git -C "$HR4" commit -qm tickets
  # ARB-SLUG-1: same one-time init as [9], slug matching the batch's resolve
  # (profile REPO "t/scratch4")
  PROJECT_SLUG="$(slugify t/scratch4)" REPO_DIR="$HR4" STATE_DIR="$HR4/.herdr-swarm" \
    BASE_BRANCH=main PATH="$HB_PATH" bash "$REPO_ROOT/lib/arbiter.sh" init-ref >/dev/null 2>&1 || true
  cat > "$HB_BIN/opencode" <<'EOF'
#!/bin/sh
brief=$(printf '%s\n' "$*" | sed -nE 's/.*BRIEF \(file\): ([^ ]+) .*/\1/p')
tid=$(sed -nE 's/^id:[[:space:]]*//p' "$brief" 2>/dev/null | head -n1 | tr -d '[:space:]')
sha=$(git rev-parse HEAD 2>/dev/null || printf 0000000000000000000000000000000000000000)
reply=$(printf '%s\n' "$*" | sed -nE 's/.*REPLY CHANNEL: write your complete response to ([^ ]+) and.*/\1/p')
[ -n "$reply" ] && printf 'worker reply for %s\n' "${tid:-unknown}" > "$reply"
printf 'ARCH DONE #%s %s\n' "${tid:-unknown}" "$sha"
EOF
  chmod +x "$HB_BIN/opencode"
  PATH="$HB_PATH" "$REPO_ROOT/bin/stampede" headless "$HR4" --max-tickets 2 --timeout 90 >"$SCRATCH/hl-uw.out" 2>&1; rc=$?
  [[ "$rc" == 0 ]] && ok "two no-owns tickets, one batch, rc=0" || bad "unwedge batch rc=$rc: $(tail -3 "$SCRATCH/hl-uw.out")"
  for T in T-A T-B; do
    jq -e -s "any(.[]; (.ticket|tostring) == \"$T\" and .suite == \"green\")" \
      "$HR4/.herdr-swarm/session-verdicts.jsonl" >/dev/null 2>&1 \
      && ok "$T dispatched and gated green (no wedge)" || bad "$T not processed"
    jq -e -s "any(.[]; (.ticket|tostring) == \"$T\" and .status == \"integrated\")" \
      "$HR4/.herdr-swarm/integration.jsonl" >/dev/null 2>&1 \
      && ok "$T integrated in-batch" || bad "$T not integrated"
  done
  jq -e '(.leases | length) == 0' "$HR4/.herdr-swarm/leases.json" >/dev/null 2>&1 \
    && ok "all leases released at batch end" || bad "leases held: $(cat "$HR4/.herdr-swarm/leases.json" 2>/dev/null)"
fi

# [13] HL-DOCS-1: honest dead-letter reasons with log pointers — a worker
# that exits without a verdict names its real exit status and the worker
# log in both the batch output and dead-letter.jsonl (receipt F2: the old
# generic "batch wall clock exhausted" hid provider/sandbox failures).
if [[ -e "$HB_BIN/timeout" ]]; then
  HR5=$(mktemp -d "$SCRATCH/hr5.XXXXXX")
  git -C "$HR5" init -q -b main
  git -C "$HR5" config user.email t@t; git -C "$HR5" config user.name t
  git -C "$HR5" remote add origin https://github.com/t/scratch5.git
  printf '.herdr-swarm/\n' > "$HR5/.gitignore"
  printf 'test:\n\t@true\n' > "$HR5/Makefile"
  mkdir -p "$HR5/maps/tickets"
  printf 'x\n' > "$HR5/f.txt"; git -C "$HR5" add -A; git -C "$HR5" commit -qm base
  printf -- '---\nid: T-NOVERDICT\nstatus: backlog\n---\nbody\n' > "$HR5/maps/tickets/tnv.md"
  git -C "$HR5" add -A; git -C "$HR5" commit -qm tickets
  # the worker crashes instantly, no verdict line — the exact shape of the
  # PROVE-HEADLESS-1 attempt-1 failures (stale model, sandbox rejection)
  printf '#!/bin/sh\nexit 7\n' > "$HB_BIN/opencode"; chmod +x "$HB_BIN/opencode"
  PATH="$HB_PATH" "$REPO_ROOT/bin/stampede" headless "$HR5" --max-tickets 1 --timeout 45 >"$SCRATCH/hl-nv.out" 2>&1; rc=$?
  [[ "$rc" == 1 ]] \
    && ok "no-verdict batch exits 1" || bad "T-NOVERDICT rc=$rc: $(tail -3 "$SCRATCH/hl-nv.out")"
  jq -e -s 'any(.[]; .ticket == "T-NOVERDICT" and ((.reason // "") | contains("worker exited rc=7 without a verdict")))' \
    "$HR5/.herdr-swarm/dead-letter.jsonl" >/dev/null 2>&1 \
    && ok "dead-letter reason names the real exit status (rc=7)" \
    || bad "reason: $(cat "$HR5/.herdr-swarm/dead-letter.jsonl" 2>/dev/null)"
  jq -e -s 'any(.[]; .ticket == "T-NOVERDICT" and ((.reason // "") | contains("worker log:")) and ((.reason // "") | contains(".herdr-swarm/logs/")))' \
    "$HR5/.herdr-swarm/dead-letter.jsonl" >/dev/null 2>&1 \
    && ok "dead-letter record carries the worker-log pointer" || bad "no log pointer in record"
  grep -q "worker log:.*logs/.*\.log" "$SCRATCH/hl-nv.out" \
    && ok "batch output points at logs/<seat>.log" || bad "no pointer in output: $(tail -2 "$SCRATCH/hl-nv.out")"
  grep -q "T-NOVERDICT DEAD_LETTER" "$HR5/.herdr-swarm/headless-notices.log" 2>/dev/null \
    && ok "durable headless notice carries the honest reason" || bad "no durable notice"
  jq -e -s 'any(.[]; (.ticket|tostring) == "T-NOVERDICT")' \
    "$HR5/.herdr-swarm/session-verdicts.jsonl" >/dev/null 2>&1 \
    && bad "phantom session record invented" || ok "no session record (worker never verdicted)"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
