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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
