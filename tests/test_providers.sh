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

# [8] chain resolution (PUB-6): first healthy kind wins, empty chain of
# healthy kinds returns nothing
out=$(providers_resolve_chain "opencode claude")
[[ "$out" == "claude" ]] && ok "resolver skips missing primary, lands on claude" || bad "resolve: '$out'"
out=$(providers_resolve_chain "claude opencode")
[[ "$out" == "claude" ]] && ok "healthy primary used directly" || bad "resolve2: '$out'"
if providers_resolve_chain "opencode pi" >/dev/null 2>&1; then
  bad "chain with no healthy kind must fail"
else
  ok "chain with no healthy kind fails"
fi
out=$(providers_resolve_chain "brand-new-llm claude")
[[ "$out" == "claude" ]] && ok "unknown kinds are skipped, not fatal" || bad "resolve3: '$out'"

# [9] opencode model preflight (D2): a configured model id opencode does not
# list is silently replaced at run time — the preflight fails closed, naming
# the seat and the offending id. The stub catalog mirrors the live ids.
printf '#!/usr/bin/env bash\nif [ "$1" = models ]; then\nprintf "%%s\\n" zai-coding-plan/glm-5.3 zai-coding-plan/glm-5.3-flash zai/glm-5.3\nexit 0\nfi\n[ "$1" = --version ] && echo opencode-stub\nexit 0\n' > "$SCRATCH/bin/opencode"
chmod +x "$SCRATCH/bin/opencode"
cat > "$SCRATCH/models.toml" <<'EOF'
[seats.good]
name = "good-seat"
kinds = ["opencode", "claude"]
model = "zai-coding-plan/glm-5.3"
[seats.bad]
name = "bad-seat"
default_kind = "opencode"
model = "zai/not-listed"
[seats.off]
name = "off-seat"
default_kind = "opencode"
model = "zai/not-listed"
enabled = false
[seats.other]
name = "other-seat"
default_kind = "claude"
model = "zai/not-listed"
EOF
if providers_check_opencode_models "$SCRATCH/models.toml" >/dev/null 2>&1; then
  bad "unlisted opencode model must fail the preflight"
else
  ok "unlisted opencode model fails the preflight"
fi
out=$(providers_check_opencode_models "$SCRATCH/models.toml" 2>&1) || true
[[ "$out" == *"bad-seat"* && "$out" == *"zai/not-listed"* ]] \
  && ok "failure names the seat and the offending model id" || bad "message: $out"
[[ "$out" != *"off-seat"* ]] && ok "disabled seats are not preflighted" || bad "disabled seat flagged: $out"
[[ "$out" != *"other-seat"* ]] && ok "non-opencode seats are not preflighted" || bad "claude seat flagged: $out"
sed 's/zai\/not-listed/zai-coding-plan\/glm-5.3/' "$SCRATCH/models.toml" > "$SCRATCH/models-fixed.toml"
if providers_check_opencode_models "$SCRATCH/models-fixed.toml" >/dev/null 2>&1; then
  ok "listed models pass the preflight"
else
  bad "listed model must pass"
fi
# Shipped config: the repo's own seats must be preflight-clean (D2 regression
# pin — the shipped config once carried zai/glm-5.3, an id the plan provider
# does not serve).
if providers_check_opencode_models "$REPO_ROOT/swarm.config.toml" >/dev/null 2>&1; then
  ok "shipped swarm.config.toml passes the model preflight"
else
  bad "shipped config fails the model preflight (run: $(providers_check_opencode_models "$REPO_ROOT/swarm.config.toml" 2>&1 | head -1))"
fi
# opencode absent: advisory skip — the fallback chain handles a missing
# binary; the preflight must not break machines without opencode.
rm "$SCRATCH/bin/opencode"
if providers_check_opencode_models "$SCRATCH/models-fixed.toml" >/dev/null 2>&1; then
  ok "absent opencode binary is advisory, not fatal"
else
  bad "absent opencode binary must not fail the preflight"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
