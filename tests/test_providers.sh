#!/bin/bash
# tests/test_providers.sh — lib/providers.sh registry (PUB-2)
#
# Hermetic: stub provider CLIs and a stub timeout(1) on a scratch PATH;
# the registry table itself is what's under test — probing, honest
# remediation, and unknown-kind fail-closed behaviour.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-providers.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin"

# Stub timeout(1): drop the duration arg, exec the rest.
cat > "$SCRATCH/bin/timeout" <<'EOF'
#!/usr/bin/env bash
shift
exec "$@"
EOF
chmod +x "$SCRATCH/bin/timeout"

# Stub providers: claude reports a version; agy exists but --version is
# silent (unknown-version degradation); opencode and pi are NOT stubbed.
printf '#!/usr/bin/env bash\necho "claude 1.2.3 (stub)"\n' > "$SCRATCH/bin/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/bin/agy"
chmod +x "$SCRATCH/bin/claude" "$SCRATCH/bin/agy"

# Resolve the interpreter with the FULL path first (homebrew pythons live
# outside /usr/bin), then narrow: hermetic against real provider CLIs, not
# against the interpreter the product itself needs.
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/pyenv.sh"
if ! resolve_python >/dev/null 2>&1; then
  printf 'test_providers: SKIP — no tomllib-capable interpreter on PATH\n'
  exit 0
fi

# Minimal PATH: scratch stubs + system basics only. Real provider CLIs on
# the dev machine (opencode lives outside /usr/bin) must not leak into the
# "missing provider" assertions — hermetic means hermetic.
PATH="$SCRATCH/bin:/usr/bin:/bin"
export PATH
export TIMEOUT_BIN="$SCRATCH/bin/timeout"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/providers.sh"

echo "==> lib/providers.sh registry (PUB-2)"

# [1] healthy provider: ok + resolved path + captured version
out=$(providers_kind_probe claude)
[[ "$out" == ok* && "$out" == *"1.2.3"* ]] && ok "claude probes ok with version" || bad "claude: $out"

# [2] present CLI, silent --version: degrades to unknown-version, still ok
out=$(providers_kind_probe agy)
[[ "$out" == "ok "* && "$out" == *"unknown-version" ]] && ok "silent --version degrades to unknown-version" || bad "agy: $out"

# [3] missing provider: honest remediation, never a guess
out=$(providers_kind_probe opencode)
[[ "$out" == "missing "* && "$out" == *"opencode.ai"* ]] && ok "opencode missing with install pointer" || bad "opencode: $out"

# [4] unknown kind: fail-closed, no invented provider
out=$(providers_kind_probe brand-new-llm)
[[ "$out" == "unknown-kind brand-new-llm" ]] && ok "unknown kind rejected" || bad "unknown: $out"

# [5] registry enumeration is the source of truth for kinds
out=$(providers_list_kinds | tr '\n' ' ')
[[ "$out" == *"claude"* && "$out" == *"opencode"* && "$out" == *"agy"* && "$out" == *"pi"* ]] \
  && ok "registry lists all four kinds" || bad "kinds: $out"

# [6] config enumeration: all seats, enabled flag, declaration order
cat > "$SCRATCH/swarm.config.toml" <<'EOF'
[seats.alpha]
name = "alpha"
default_kind = "claude"
[seats.beta]
name = "beta"
default_kind = "pi"
enabled = false
[seats.gamma]
name = "gamma"
default_kind = "agy"
EOF
out=$(providers_seats_from_config "$SCRATCH/swarm.config.toml")
[[ "$(printf '%s\n' "$out" | head -1)" == "alpha|claude|1|alpha" ]] \
  && ok "seat row shape: key|kind|enabled|name" || bad "row1: $out"
printf '%s\n' "$out" | grep -q '^beta|pi|0|beta$' && ok "disabled seat enumerated as 0" || bad "beta row"
[[ "$(printf '%s\n' "$out" | tail -1)" == "gamma|agy|1|gamma" ]] && ok "declaration order kept" || bad "order: $out"

# [7] missing config fails loudly (python exits non-zero under set -e)
if providers_seats_from_config "$SCRATCH/nope.toml" >/dev/null 2>&1; then
  bad "missing config must fail"
else
  ok "missing config fails"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
