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
[seats.claude_primary]
name = "claude-primary"
kinds = ["claude", "opencode"]
model = "sonnet"
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
[[ "$out" != *"claude-primary"* ]] && ok "claude-primary fallback is not preflighted as opencode" || bad "claude primary flagged: $out"
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

# [10] model transport per kind (D1): opencode v2 has no TUI --model flag —
# a forwarded flag kills the seat. The model must travel by per-seat project
# config instead; kinds that support --model keep forwarding it.
cat > "$SCRATCH/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_STUB_CALLS"
EOF
chmod +x "$SCRATCH/bin/herdr"
export HERDR_STUB_CALLS="$SCRATCH/herdr.calls"
: > "$HERDR_STUB_CALLS"
SEAT_CWD="$SCRATCH/seat-home"; mkdir -p "$SEAT_CWD"

providers_start_agent pm claude p2 sonnet >/dev/null 2>&1
grep -q 'agent start pm --kind claude --pane p2 -- --model sonnet' "$HERDR_STUB_CALLS" \
  && ok "claude keeps --model forwarding" || bad "claude forward: $(cat "$HERDR_STUB_CALLS")"

: > "$HERDR_STUB_CALLS"
providers_start_agent arch opencode p3 zai-coding-plan/glm-5.3 "$SEAT_CWD" >/dev/null 2>&1
grep -q 'agent start arch --kind opencode --pane p3$' "$HERDR_STUB_CALLS" \
  && ok "opencode starts with no forwarded flags" || bad "opencode forward: $(cat "$HERDR_STUB_CALLS")"
[[ -f "$SEAT_CWD/.opencode/opencode.json" ]] \
  && ok "opencode project config written under the seat cwd" || bad "no .opencode/opencode.json under seat cwd"
grep -q '"model": *"zai-coding-plan/glm-5.3"' "$SEAT_CWD/.opencode/opencode.json" 2>/dev/null \
  && ok "project config pins the configured model" || bad "model pin: $(cat "$SEAT_CWD/.opencode/opencode.json" 2>/dev/null)"

printf '{"$schema":"https://opencode.ai/config.json","model":"zai-coding-plan/glm-4.6","permission":{"external_directory":"allow"}}\n' \
  > "$SEAT_CWD/.opencode/opencode.json"
providers_start_agent arch opencode p3 zai-coding-plan/glm-5.3 "$SEAT_CWD" >/dev/null 2>&1
python3 - "$SEAT_CWD/.opencode/opencode.json" <<'PY' && ok "existing project config merged, sibling keys preserved" || bad "merge clobbered sibling keys"
import json, sys
cfg = json.load(open(sys.argv[1]))
assert cfg["model"] == "zai-coding-plan/glm-5.3", cfg
assert cfg["permission"] == {"external_directory": "allow"}, cfg
PY
start_calls=$(grep -c 'agent start arch' "$HERDR_STUB_CALLS")
[[ "$start_calls" -eq 2 ]] && ok "start still invoked on the model-pinned path" || bad "start calls: $start_calls"

AUTO_CWD="$SCRATCH/auto-home"; mkdir -p "$AUTO_CWD"
: > "$HERDR_STUB_CALLS"
providers_start_agent arch opencode p4 auto "$AUTO_CWD" >/dev/null 2>&1
grep -q 'agent start arch --kind opencode --pane p4$' "$HERDR_STUB_CALLS" \
  && ok "auto model starts plainly, no flags" || bad "auto forward: $(cat "$HERDR_STUB_CALLS")"
[[ ! -e "$AUTO_CWD/.opencode" ]] \
  && ok "auto model writes no project config" || bad "auto model wrote a config"

# Runtime pins must not dirty a worker checkout. gate_tree_matches rejects
# any porcelain — untracked files included — so a new pin is excluded, and
# a tracked config is never edited (a later untracked opencode.jsonc wins).
init_pin_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  printf 'readme\n' > "$1/README"
  git -C "$1" add README
  git -C "$1" -c user.name=Test -c user.email=test@example.com commit -qm init
}
pin_repo_clean() { # DIR SHA
  [[ "$(git -C "$1" rev-parse HEAD)" == "$2" ]] \
    && [[ -z "$(git -C "$1" status --porcelain)" ]]
}

PIN_REPO="$SCRATCH/pin-repo"
init_pin_repo "$PIN_REPO"
pin_sha=$(git -C "$PIN_REPO" rev-parse HEAD)
providers_write_opencode_model "$PIN_REPO" zai-coding-plan/glm-5.3
pin_repo_clean "$PIN_REPO" "$pin_sha" \
  && ok "new pin leaves the checkout clean for the gate" || bad "new pin dirtied: $(git -C "$PIN_REPO" status --porcelain)"
grep -q '"model": *"zai-coding-plan/glm-5.3"' "$PIN_REPO/.opencode/opencode.json" \
  && ok "untracked checkout still receives the pin file" || bad "missing pin: $(cat "$PIN_REPO/.opencode/opencode.json" 2>/dev/null)"
git -C "$PIN_REPO" add -A
[[ -z "$(git -C "$PIN_REPO" diff --cached --name-only)" ]] \
  && ok "new pin is excluded from git add" || bad "pin staged: $(git -C "$PIN_REPO" diff --cached --name-only)"
exclude_file=$(git -C "$PIN_REPO" rev-parse --path-format=absolute --git-path info/exclude)
exclude_n=$(grep -cxF '/.opencode/opencode.json' "$exclude_file" || true)
providers_write_opencode_model "$PIN_REPO" zai-coding-plan/glm-5.3
exclude_n2=$(grep -cxF '/.opencode/opencode.json' "$exclude_file" || true)
[[ "$exclude_n" -eq "$exclude_n2" ]] \
  && ok "excluding the pin is idempotent" || bad "exclude lines $exclude_n -> $exclude_n2"

# Worker seats are linked worktrees. info/exclude lives in the common git
# dir, so the pin must stay invisible there too.
PIN_WT="$SCRATCH/pin-wt"
git -C "$PIN_REPO" worktree add -q "$PIN_WT" -b worker-pin
providers_write_opencode_model "$PIN_WT" zai-coding-plan/glm-5.3
wt_sha=$(git -C "$PIN_WT" rev-parse HEAD)
pin_repo_clean "$PIN_WT" "$wt_sha" \
  && grep -q '"model": *"zai-coding-plan/glm-5.3"' "$PIN_WT/.opencode/opencode.json" \
  && ok "worktree pin stays out of the worker checkout" \
  || bad "worktree pin: $(git -C "$PIN_WT" status --porcelain)"

TRACKED_REPO="$SCRATCH/tracked-pin"
init_pin_repo "$TRACKED_REPO"
mkdir -p "$TRACKED_REPO/.opencode"
printf '%s\n' '{"$schema":"https://opencode.ai/config.json","model":"zai-coding-plan/glm-4.6","permission":{"external_directory":"allow"}}' \
  > "$TRACKED_REPO/.opencode/opencode.json"
git -C "$TRACKED_REPO" add -f .opencode/opencode.json
git -C "$TRACKED_REPO" -c user.name=Test -c user.email=test@example.com commit -qm 'track opencode config'
tracked_sha=$(git -C "$TRACKED_REPO" rev-parse HEAD)
providers_write_opencode_model "$TRACKED_REPO" zai-coding-plan/glm-4.6
pin_repo_clean "$TRACKED_REPO" "$tracked_sha" && [[ ! -e "$TRACKED_REPO/.opencode/opencode.jsonc" ]] \
  && ok "matching tracked model writes no runtime file" || bad "match path: $(git -C "$TRACKED_REPO" status --porcelain) jsonc=$(ls "$TRACKED_REPO/.opencode")"
providers_write_opencode_model "$TRACKED_REPO" zai-coding-plan/glm-5.3
pin_repo_clean "$TRACKED_REPO" "$tracked_sha" \
  && ok "tracked config pin leaves the checkout clean" || bad "tracked pin dirtied: $(git -C "$TRACKED_REPO" status --porcelain)"
git -C "$TRACKED_REPO" diff --quiet -- .opencode/opencode.json \
  && ok "tracked opencode.json was not modified" || bad "tracked config changed"
grep -q '"model": *"zai-coding-plan/glm-5.3"' "$TRACKED_REPO/.opencode/opencode.jsonc" \
  && ok "tracked config is overridden by an excluded jsonc pin" || bad "jsonc pin: $(cat "$TRACKED_REPO/.opencode/opencode.jsonc" 2>/dev/null)"
python3 - "$TRACKED_REPO/.opencode/opencode.json" <<'PY' && ok "tracked sibling keys survived the pin" || bad "tracked siblings changed"
import json, sys
cfg = json.load(open(sys.argv[1]))
assert cfg["model"] == "zai-coding-plan/glm-4.6", cfg
assert cfg["permission"] == {"external_directory": "allow"}, cfg
PY
git -C "$TRACKED_REPO" add -A
[[ -z "$(git -C "$TRACKED_REPO" diff --cached --name-only)" ]] \
  && ok "jsonc override is excluded from git add" || bad "jsonc staged: $(git -C "$TRACKED_REPO" diff --cached --name-only)"

providers_write_opencode_model "$TRACKED_REPO" zai-coding-plan/glm-4.6
pin_repo_clean "$TRACKED_REPO" "$tracked_sha" \
  && [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$TRACKED_REPO/.opencode/opencode.jsonc")" == "zai-coding-plan/glm-4.6" ]] \
  && ok "a later runtime pin follows the requested model without dirtying the checkout" \
  || bad "retarget dirtied: $(git -C "$TRACKED_REPO" status --porcelain) $(cat "$TRACKED_REPO/.opencode/opencode.jsonc" 2>/dev/null)"

BOTH_REPO="$SCRATCH/both-tracked"
init_pin_repo "$BOTH_REPO"
mkdir -p "$BOTH_REPO/.opencode"
printf '%s\n' '{"model":"zai-coding-plan/glm-4.6"}' > "$BOTH_REPO/.opencode/opencode.json"
printf '%s\n' '{"model":"zai-coding-plan/glm-4.6","permission":{"edit":"allow"}}' > "$BOTH_REPO/.opencode/opencode.jsonc"
git -C "$BOTH_REPO" add -f .opencode/opencode.json .opencode/opencode.jsonc
git -C "$BOTH_REPO" -c user.name=Test -c user.email=test@example.com commit -qm 'track both configs'
both_sha=$(git -C "$BOTH_REPO" rev-parse HEAD)
if providers_write_opencode_model "$BOTH_REPO" zai-coding-plan/glm-5.3 2>/dev/null; then
  bad "tracked jsonc pin should refuse rather than edit"
else
  ok "tracked jsonc with a different model is left untouched"
fi
pin_repo_clean "$BOTH_REPO" "$both_sha" \
  && ok "refused pin leaves the tracked checkout clean" || bad "refused pin dirtied: $(git -C "$BOTH_REPO" status --porcelain)"

# [11] healthy-chain enumeration (D3): launch retries need every healthy
# kind in chain order, not just the winner.
out=$(providers_healthy_chain "opencode claude" | tr '\n' ' ')
[[ "$out" == "claude " ]] && ok "healthy chain skips missing kinds" || bad "healthy chain: '$out'"
printf '#!/usr/bin/env bash\nif [ "$1" = --version ]; then echo opencode-stub; exit 0; fi\nexit 0\n' > "$SCRATCH/bin/opencode"
chmod +x "$SCRATCH/bin/opencode"
out=$(providers_healthy_chain "opencode claude agy" | tr '\n' ' ')
[[ "$out" == "opencode claude agy " ]] && ok "healthy chain keeps declaration order" || bad "order: '$out'"
out=$(providers_healthy_chain "brand-new-llm claude" | tr '\n' ' ')
[[ "$out" == "claude " ]] && ok "healthy chain skips unknown kinds" || bad "unknown skip: '$out'"
out=$(providers_healthy_chain "pi brand-new-llm" | tr '\n' ' ')
[[ -z "$out" ]] && ok "empty chain when nothing is healthy" || bad "empty: '$out'"

# A commented opencode.jsonc that already pins the model is a match: JSONC
# comments must not refuse the seat. The $schema URL holds a "//" that a
# naive comment strip would corrupt.
JSONC_REPO="$SCRATCH/jsonc-pin"
init_pin_repo "$JSONC_REPO"
mkdir -p "$JSONC_REPO/.opencode"
cat > "$JSONC_REPO/.opencode/opencode.jsonc" <<'JSONC'
{
  // project pin
  "$schema": "https://opencode.ai/config.json",
  /* block
     comment */
  "model": "zai-coding-plan/glm-5.3", // trailing note
  "permission": {"edit": "allow",},
}
JSONC
git -C "$JSONC_REPO" add -f .opencode/opencode.jsonc
git -C "$JSONC_REPO" -c user.name=Test -c user.email=test@example.com commit -qm 'track commented jsonc'
jsonc_sha=$(git -C "$JSONC_REPO" rev-parse HEAD)
providers_write_opencode_model "$JSONC_REPO" zai-coding-plan/glm-5.3 2>/dev/null \
  && pin_repo_clean "$JSONC_REPO" "$jsonc_sha" \
  && ok "commented tracked jsonc with the pinned model is accepted untouched" \
  || bad "commented jsonc refused: $(git -C "$JSONC_REPO" status --porcelain)"
if providers_write_opencode_model "$JSONC_REPO" zai-coding-plan/glm-4.6 2>/dev/null; then
  bad "commented tracked jsonc with a different model was edited"
else
  pin_repo_clean "$JSONC_REPO" "$jsonc_sha" && ok "commented tracked jsonc with another model is refused, untouched" \
    || bad "refusal dirtied: $(git -C "$JSONC_REPO" status --porcelain)"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
