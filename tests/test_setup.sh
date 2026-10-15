#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/my project"
mkdir -p "$REPO" "$TMP/bin"
git -C "$REPO" init -q
git -C "$REPO" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial

UNBORN="$TMP/unborn"
mkdir -p "$UNBORN"
git -C "$UNBORN" init -q
if "$ROOT/bin/stampede" setup "$UNBORN" --non-interactive --launcher "$TMP/unborn-yeehaw.sh" >"$TMP/unborn.out" 2>&1; then
  echo 'setup accepted unborn HEAD that cannot provision worktrees' >&2; exit 1
fi
grep -q 'initial commit' "$TMP/unborn.out" || { echo 'unborn repo guidance missing' >&2; exit 1; }

for provider in agy claude opencode; do
  printf '#!/bin/sh\n[ "$1" = --version ] && echo fake-%s\n' "$provider" > "$TMP/bin/$provider"
  chmod +x "$TMP/bin/$provider"
done
printf '#!/bin/sh\n[ "$1" = integration ] && echo "agy 1 installed; claude 6 installed; opencode 5 installed"\n' > "$TMP/bin/herdr"
chmod +x "$TMP/bin/herdr"
export PATH="$TMP/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
out=$("$ROOT/bin/stampede" setup "$REPO" --non-interactive --launcher "$TMP/yeehaw.sh") || fail 'setup failed'
[[ -f "$REPO/swarm.config.toml" && -x "$TMP/yeehaw.sh" ]] || fail 'config or launcher absent'
grep -q 'mode = "medium"' "$REPO/swarm.config.toml" || fail 'medium default absent'
grep -q 'bounded_looper = true' "$REPO/swarm.config.toml" || fail 'bounded looper absent'
! grep -q 'brew services start ollama' "$ROOT/herdr-loop-swarm.sh" || fail 'startup still offers deferred local models'
grep -q '\[seats.arch_2\]' "$REPO/swarm.config.toml" || fail 'second architect absent'
grep -q 'briefs/arch-frontier.md' "$REPO/swarm.config.toml" || fail 'architect still uses persistent-looper brief'
grep -q '\[seats.helper\]' "$REPO/swarm.config.toml" || fail 'helper absent'
grep -q 'briefs/helper.md' "$REPO/swarm.config.toml" || fail 'helper not bounded to its own brief'
grep -A9 '\[seats.pm\]' "$REPO/swarm.config.toml" | grep -q 'critical = true' \
  || fail 'PM seat is not marked critical'
grep -A9 '\[seats.arch_1\]' "$REPO/swarm.config.toml" | grep -q 'critical = true' \
  || fail 'architect seat is not marked critical'
grep -A9 '\[seats.docs\]' "$REPO/swarm.config.toml" | grep -q 'critical = true' \
  && fail 'docs seat must not be critical'
for seat in pm gh docs helper; do
  grep -A9 "\[seats.$seat\]" "$REPO/swarm.config.toml" | grep -q 'worktree = true' \
    || fail "$seat can write the base checkout"
done
grep -q 'model = "gemini-3.8-flash-low"' "$REPO/swarm.config.toml" || fail 'current AGY recommendation absent'
grep -q 'model = "zai-coding-plan/glm-5.3"' "$REPO/swarm.config.toml" || fail 'architect recommendation absent'
grep -q 'ctrl+b q' <<<"$out" || fail 'detach guidance absent'
grep -q 'arbiter .* drain' <<<"$out" || fail 'manual arbiter guidance absent'
grep -q 'arbiter .* init-ref' <<<"$out" || fail 'arbiter initialization guidance absent'
py_bin=$(/bin/bash "$ROOT/lib/pyenv.sh")
mkdir -p "$REPO/maps" "$REPO/.herdr-swarm"
printf '# Map 17\n- [x] #16\n- [ ] #18\n- [ ] #19\n' > "$REPO/maps/17.md"
printf '17\n' > "$REPO/.herdr-swarm/active-map"
map_next=$("$py_bin" "$ROOT/lib/attention.py" next "$REPO")
[[ "$map_next" == "18" ]] || fail "bounded map dispatcher failed to select unticked #18 (got: $map_next)"
rm -rf "$REPO/maps" "$REPO/.herdr-swarm/active-map"
grep -q '== start' "$TMP/yeehaw.sh" || fail 'launcher start command absent'
grep -q 'exec .* up ' "$TMP/yeehaw.sh" || fail 'launcher does not use up'
help_out=$("$TMP/yeehaw.sh" --help) || fail 'quick launcher help failed'
grep -q 'ctrl+b q' <<<"$help_out" || fail 'quick launcher help omits detach'
grep -q 'arbiter.*drain' <<<"$help_out" || fail 'quick launcher help omits manual arbiter'
! git -C "$REPO" show-ref --verify --quiet refs/heads/swarm/my-project/integration \
  || fail 'setup initialized arbiter without a human command'
if "$ROOT/bin/stampede" arbiter "$REPO" init-ref >/dev/null 2>&1; then
  fail 'arbiter ran without a project profile'
fi
mkdir -p "$REPO/.herdr-swarm"
printf 'TEST_CMD=make test\nREPO=none\n' > "$REPO/.herdr-swarm/profile.env"
git -C "$REPO" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
"$ROOT/bin/stampede" arbiter "$REPO" init-ref >/dev/null || fail 'manual project-bound arbiter init failed'
git -C "$REPO" show-ref --verify --quiet refs/heads/swarm/my-project/integration \
  || fail 'manual init used the wrong integration ref'
printf '{"ticket":"77","status":"queued"}\n' > "$REPO/.herdr-swarm/integration.jsonl"
status_out=$("$ROOT/bin/stampede" status "$REPO" 2>&1 || true)
grep -q 'Integration queue: 1 queued' <<<"$status_out" || fail 'status did not show pending integration'
grep -q 'stampede arbiter .* drain' <<<"$status_out" || fail 'status omitted manual drain command'

# A setup target's role choices must bind through the same parser launch uses.
bound=$(STAMPEDE_CONFIG_FILE="$REPO/swarm.config.toml" bash -c 'source "$1"; config_dump_env sample' _ "$ROOT/lib/config.sh")
grep -q 'export SEAT_MODEL_arch_2=zai-coding-plan/glm-5.3' <<<"$bound" || fail 'project model did not bind'
grep -q 'export CONFIG_ATTENTION_MODE=medium' <<<"$bound" || fail 'attention did not bind'
grep -q 'export CONFIG_BOUNDED_LOOPER=1' <<<"$bound" || fail 'bounded looper did not bind'
roster=$(REPO_DIR="$REPO" STATE_DIR="$REPO/.herdr-swarm" bash -c \
  'source "$1/loop-bot-herd.sh" status >/dev/null; printf "%s\n" "${EXPECTED_SEATS[@]}"' _ "$ROOT")
! grep -q '^looper-' <<<"$roster" || fail 'shell looper counted as missing agent'
grep -q '^arch-1-' <<<"$roster" || fail 'architect missing from supervisor roster'
[[ "$("$ROOT/bin/stampede" attention "$REPO" quiet)" == quiet ]] || fail 'attention command did not set mode'
[[ "$("$ROOT/bin/stampede" attention "$REPO")" == quiet ]] || fail 'attention mode did not persist'

cat > "$TMP/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_CALLS"
EOF
chmod +x "$TMP/bin/herdr"
export HERDR_CALLS="$TMP/herdr.calls"
mkdir -p "$TMP/seat-cwd"
bash -c 'source "$1"; cd "$2"; providers_start_agent looper agy p1 gemini-3.8-flash-low; providers_start_agent pm claude p2 sonnet; providers_start_agent arch opencode p3 zai-coding-plan/glm-5.3' _ "$ROOT/lib/providers.sh" "$TMP/seat-cwd"
grep -q 'agent start looper --kind agy --pane p1 -- --model gemini-3.8-flash-low' "$HERDR_CALLS" || fail 'AGY model not passed to Herdr'
grep -q 'agent start pm --kind claude --pane p2 -- --model sonnet' "$HERDR_CALLS" || fail 'Claude model not passed to Herdr'
grep -q 'agent start arch --kind opencode --pane p3$' "$HERDR_CALLS" || fail 'OpenCode start must not forward flags'
grep -q '"model": *"zai-coding-plan/glm-5.3"' "$TMP/seat-cwd/.opencode/opencode.json" 2>/dev/null || fail 'OpenCode model not pinned in seat project config'

mkdir -p "$REPO/.herdr-swarm"
mkdir -p "$REPO/.herdr-swarm/tickets"
printf '%s\n' '---' 'id: 77' '---' > "$REPO/.herdr-swarm/tickets/77.md"
resolved=$(bash -c 'source "$1"; _partition_ticket_file 77 "$2"' _ "$ROOT/lib/partition.sh" "$REPO")
[[ "$resolved" == "$REPO/.herdr-swarm/tickets/77.md" ]] || fail 'runtime ticket cannot be leased'
REPO_DIR="$REPO" STATE_DIR="$REPO/.herdr-swarm" bash -c 'source "$1"; lease_acquire 77 arch-test "" -' _ "$ROOT/lib/partition.sh" \
  || fail 'runtime ticket lease acquisition failed'
jq -e '.leases[] | select(.ticket == "77" and .seat == "arch-test" and .exclusive == true)' \
  "$REPO/.herdr-swarm/leases.json" >/dev/null || fail 'runtime ticket lease was not recorded'
printf '{"workspace_id":"w1","seats":[{"name":"looper-test","kind":"shell","pane":"w1:p1","agentless":true},{"name":"arch-test","kind":"opencode","pane":"w1:p2"}]}' > "$REPO/.herdr-swarm/seats.json"
# D4 fixture: swarm_verify_seats compares the configured, enabled roster
# against the ledger, so the verify target needs a config whose namespaced
# roster matches the seeded ledger exactly (dir name "test" is the slug:
# looper-test / arch-test).
mkdir -p "$TMP/test/.herdr-swarm"
printf '[seats.looper]\nname = "looper"\ndefault_kind = "agy"\n\n[seats.arch_1]\nname = "arch"\ndefault_kind = "opencode"\ncritical = true\n' > "$TMP/test/swarm.config.toml"
cp "$REPO/.herdr-swarm/seats.json" "$TMP/test/.herdr-swarm/seats.json"
LIFECYCLE_TARGET="$TMP/test" bash -c '
  source "$1/lib/lifecycle.sh"
  BOLD= DIM= RESET= RED= GREEN=
  find_workspace_by_cwd() { printf "w1\n"; }
  herdr() { case "$*" in "pane list") printf "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\"}]}}\n" ;; "agent get looper-test") return 1 ;; *) return 0 ;; esac; }
  seat_wait_ready() { SEAT_WAIT_MODE=ready; return 0; }
  swarm_verify_seats "$LIFECYCLE_TARGET"
' _ "$ROOT" >/dev/null || fail 'agentless log/looper pane failed seat verification'
# D4 total-failure case: an EMPTY ledger with a configured critical seat
# must fail verification and name the missing critical seat — the early
# "no seats recorded" return must not bypass the roster comparison.
printf '[seats.looper]\nname = "looper"\ndefault_kind = "agy"\n\n[seats.arch_1]\nname = "arch"\ndefault_kind = "opencode"\ncritical = true\n\n[seats.builder]\nname = "builder"\ndefault_kind = "opencode"\ncritical = true\n\n[seats.arch_9]\nname = "arch-9"\ndefault_kind = "opencode"\n' > "$TMP/test/swarm.config.toml"
printf '{"workspace_id":"w1","seats":[]}' > "$TMP/test/.herdr-swarm/seats.json"
LIFECYCLE_TARGET="$TMP/test" bash -c '
  source "$1/lib/lifecycle.sh"
  BOLD= DIM= RESET= RED= GREEN= YELLOW=
  find_workspace_by_cwd() { printf "w1\n"; }
  herdr() { return 0; }
  seat_wait_ready() { SEAT_WAIT_MODE=ready; return 0; }
  swarm_verify_seats "$LIFECYCLE_TARGET" >/dev/null 2>&1 || true
  [[ -n "${SWARM_MISSING_CRITICAL:-}" ]] || exit 1
  case " ${SWARM_MISSING_CRITICAL} " in *" arch-test "*) ;; *) exit 1 ;; esac
  case " ${SWARM_MISSING_CRITICAL} " in *" builder-test "*) ;; *) exit 1 ;; esac
  case " ${SWARM_MISSING_CRITICAL} " in *" arch-9-test "*) exit 1 ;; esac
  case " ${SWARM_MISSING_SEATS:-} " in *" arch-9-test "*) exit 0 ;; *) exit 1 ;; esac
' _ "$ROOT" || fail 'empty ledger with a configured critical seat must fail verify (D4)'

# Configs written before the critical field (stampede init, older setups)
# keep main's protected pair: the PM and the first architect. An explicit
# critical = false still wins.
printf '[seats.pm]\nname = "pm"\ndefault_kind = "claude"\n\n[seats.arch_1]\nname = "arch"\ndefault_kind = "opencode"\n\n[seats.docs]\nname = "docs"\ndefault_kind = "agy"\n' > "$TMP/test/swarm.config.toml"
LIFECYCLE_TARGET="$TMP/test" bash -c '
  source "$1/lib/lifecycle.sh"
  BOLD= DIM= RESET= RED= GREEN= YELLOW=
  find_workspace_by_cwd() { printf "w1\n"; }
  herdr() { return 0; }
  seat_wait_ready() { SEAT_WAIT_MODE=ready; return 0; }
  swarm_verify_seats "$LIFECYCLE_TARGET" >/dev/null 2>&1 || true
  case " ${SWARM_CRITICAL_SEATS:-} " in *" pm-test "*) ;; *) exit 1 ;; esac
  case " ${SWARM_CRITICAL_SEATS:-} " in *" arch-test "*) ;; *) exit 1 ;; esac
  case " ${SWARM_CRITICAL_SEATS:-} " in *" docs-test "*) exit 1 ;; esac
  exit 0
' _ "$ROOT" || fail 'legacy config without critical lost the PM/architect launch protection'
printf '[seats.pm]\nname = "pm"\ndefault_kind = "claude"\ncritical = false\n\n[seats.arch_1]\nname = "arch"\ndefault_kind = "opencode"\n' > "$TMP/test/swarm.config.toml"
LIFECYCLE_TARGET="$TMP/test" bash -c '
  source "$1/lib/lifecycle.sh"
  BOLD= DIM= RESET= RED= GREEN= YELLOW=
  find_workspace_by_cwd() { printf "w1\n"; }
  herdr() { return 0; }
  seat_wait_ready() { SEAT_WAIT_MODE=ready; return 0; }
  swarm_verify_seats "$LIFECYCLE_TARGET" >/dev/null 2>&1 || true
  case " ${SWARM_CRITICAL_SEATS:-} " in *" pm-test "*) exit 1 ;; esac
  exit 0
' _ "$ROOT" || fail 'explicit critical = false was overridden'

before=$(shasum "$REPO/swarm.config.toml" | cut -d' ' -f1)
repeat_out=$("$ROOT/bin/stampede" setup "$REPO" --non-interactive --launcher "$TMP/yeehaw.sh") \
  || fail 'idempotent repeat setup failed'
grep -q 'already configured' <<<"$repeat_out" || fail 'repeat setup did not explain no-op'
after=$(shasum "$REPO/swarm.config.toml" | cut -d' ' -f1)
[[ "$before" == "$after" ]] || fail 'repeat setup modified config'

python3 - "$REPO/swarm.config.toml" <<'PY'
from pathlib import Path
import sys
config = Path(sys.argv[1])
config.write_text(config.read_text().replace('name = "my-project"', 'name = "custom-integration"', 1))
PY

cat >> "$REPO/swarm.config.toml" <<'EOF'

[fanout]
gate_concurrency = 1
max_workers = 4

[reviewer]
loop = true
max_rounds = 3
failover_seat = "arch_1"

[seats.reviewer]
name = "reviewer"
role = "reviewer"
default_kind = "agy"
model = "gemini-3.8-flash-low"
brief = "briefs/reviewer.md"
tab = "ops"
enabled = true
EOF

python3 - "$REPO/swarm.config.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('name = "arch-1"\n', 'name = "builder"\nposition = "top-right"\nkinds = ["opencode", "claude"]\n', 1)
text = text.replace('[seats.helper]\n', '[seats.helper]\nenabled = false\n', 1)
text += '''
[seats.notes]
name = "notes"
role = "notes"
default_kind = "agy"
model = "gemini-3.8-flash-low"
brief = "briefs/notes.md"
tab = "ops"
position = "bottom"
'''
path.write_text(text)
PY
"$ROOT/bin/stampede" setup "$REPO" --non-interactive --force --launcher "$TMP/yeehaw.sh" \
  --attention quiet >/dev/null || fail 'attention-only edit failed'
grep -q 'mode = "quiet"' "$REPO/swarm.config.toml" || fail 'attention-only edit missed the mode'
grep -A8 '\[seats.arch_1\]' "$REPO/swarm.config.toml" | grep -q 'name = "builder"' \
  || fail 'attention-only edit reset a custom seat name'
grep -A12 '\[seats.arch_1\]' "$REPO/swarm.config.toml" | grep -Fq 'kinds = ["opencode", "claude"]' \
  || fail 'attention-only edit dropped the fallback chain'
grep -A12 '\[seats.arch_1\]' "$REPO/swarm.config.toml" | grep -q 'position = "top-right"' \
  || fail 'attention-only edit dropped the seat position'
grep -A3 '\[seats.helper\]' "$REPO/swarm.config.toml" | grep -q 'enabled = false' \
  || fail 'attention-only edit cleared enabled = false'
grep -q '\[seats.notes\]' "$REPO/swarm.config.toml" || fail 'attention-only edit dropped a custom seat'
grep -q '\[seats.reviewer\]' "$REPO/swarm.config.toml" || fail 'attention-only edit dropped the reviewer'
"$ROOT/bin/stampede" setup "$REPO" --non-interactive --force --launcher "$TMP/yeehaw.sh" \
  --attention quiet --provider architect=claude --model architect=opus \
  --architect-count 3 --pm-count 2 >/dev/null || fail 'replacement failed'
grep -A8 '\[seats.arch_1\]' "$REPO/swarm.config.toml" | grep -q 'name = "builder"' \
  || fail 'provider edit reset a custom seat name'
grep -q '\[seats.notes\]' "$REPO/swarm.config.toml" || fail 'provider edit dropped a custom seat'
[[ -f "$REPO/swarm.config.toml.bak" && -f "$TMP/yeehaw.sh.bak" ]] || fail 'backups absent'
grep -q 'mode = "quiet"' "$REPO/swarm.config.toml" || fail 'chosen attention absent'
grep -q '\[seats.arch_3\]' "$REPO/swarm.config.toml" || fail 'scaled architect absent'
grep -q '\[seats.pm_2\]' "$REPO/swarm.config.toml" || fail 'scaled PM absent'
grep -q '\[seats.pm\]' "$REPO/swarm.config.toml" || fail 'primary PM key lost'
grep -A5 '\[seats.arch_3\]' "$REPO/swarm.config.toml" | grep -q 'default_kind = "claude"' || fail 'provider choice absent'
grep -A6 '\[seats.arch_3\]' "$REPO/swarm.config.toml" | grep -q 'model = "opus"' || fail 'model choice absent'
grep -A7 '\[seats.arch_3\]' "$REPO/swarm.config.toml" | grep -q 'cost_tier = "high"' || fail 'chosen Opus mispriced'
grep -q 'loop = true' "$REPO/swarm.config.toml" || fail 'edit disabled the reviewer loop'
grep -q '\[seats.reviewer\]' "$REPO/swarm.config.toml" || fail 'edit removed the reviewer seat'
grep -q 'max_rounds = 3' "$REPO/swarm.config.toml" || fail 'edit reset reviewer limit'
grep -q 'name = "custom-integration"' "$REPO/swarm.config.toml" || fail 'edit changed the integration ref name'
grep -q 'gate_concurrency = 1' "$REPO/swarm.config.toml" || fail 'edit reset fanout concurrency'
review_bound=$(STAMPEDE_CONFIG_FILE="$REPO/swarm.config.toml" bash -c 'source "$1"; config_dump_env sample' _ "$ROOT/lib/config.sh")
grep -q 'export CONFIG_REVIEW_LOOP=1' <<<"$review_bound" || fail 'reviewer loop did not bind after edit'
grep -q 'export SWARM_CONFIG_NAME=custom-integration' <<<"$review_bound" || fail 'integration ref name did not bind after edit'
"$ROOT/bin/stampede" setup "$REPO" --non-interactive --force --launcher "$TMP/yeehaw.sh" \
  --attention medium >/dev/null || fail 'editing existing setup failed'
grep -A6 '\[seats.arch_3\]' "$REPO/swarm.config.toml" | grep -q 'model = "opus"' \
  || fail 'edit reset a prior architect model choice'
grep -q '\[seats.pm_2\]' "$REPO/swarm.config.toml" || fail 'edit reset prior PM count'

cat > "$TMP/bin/agy" <<'EOF'
#!/bin/sh
if [ "$1" = models ]; then
  printf '%s\n' 'claude-opus-5-5-high' 'gemini-4-flash-low'
fi
EOF
chmod +x "$TMP/bin/agy"
NEW_REPO="$TMP/new model repo"
mkdir -p "$NEW_REPO"
git -C "$NEW_REPO" init -q
git -C "$NEW_REPO" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
"$ROOT/bin/stampede" setup "$NEW_REPO" --non-interactive --launcher "$TMP/new-yeehaw.sh" >/dev/null \
  || fail 'setup did not handle changed catalog'
grep -q 'model = "gemini-4-flash-low"' "$NEW_REPO/swarm.config.toml" \
  || fail 'AGY fallback picked a costly model over available Flash'

LINKED="$TMP/linked checkout"
git -C "$REPO" worktree add --detach -q "$LINKED"
"$ROOT/bin/stampede" setup "$LINKED" --non-interactive --launcher "$TMP/linked-yeehaw.sh" >/dev/null \
  || fail 'setup failed in a linked Git worktree'
git -C "$LINKED" check-ignore -q .herdr-swarm/test.log \
  || fail 'linked worktree runtime state is not excluded'

fresh_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
}
seat_block() { # FILE KEY — the [seats.KEY] table body
  awk -v h="[seats.$2]" '$0 == h { on = 1; next } /^\[/ { on = 0 } on' "$1"
}

# A provider-only edit applies the provider's compatible model too, so an
# OpenCode model is never left behind on a Claude seat.
EDIT_REPO="$TMP/edit repo"
fresh_repo "$EDIT_REPO"
"$ROOT/bin/stampede" setup "$EDIT_REPO" --non-interactive --launcher "$TMP/edit-yeehaw.sh" >/dev/null \
  || fail 'edit fixture setup failed'
"$ROOT/bin/stampede" setup "$EDIT_REPO" --non-interactive --force --launcher "$TMP/edit-yeehaw.sh" \
  --provider architect=claude >/dev/null || fail 'provider-only edit failed'
seat_block "$EDIT_REPO/swarm.config.toml" arch_1 | grep -q 'default_kind = "claude"' \
  || fail 'provider-only edit did not change the existing architect provider'
seat_block "$EDIT_REPO/swarm.config.toml" arch_1 | grep -q 'model = "sonnet"' \
  || fail 'provider-only edit kept an incompatible OpenCode model on a Claude seat'

# Interactive answers reach existing seats, not only fresh ones.
printf '%s\n' edit '' '' '' '' '' '' '' '' '' '' opencode zai-coding-plan/glm-5.3-flash '' '' '' '' yes \
  | "$ROOT/bin/stampede" setup "$EDIT_REPO" --launcher "$TMP/edit-yeehaw.sh" >/dev/null 2>&1 \
  || fail 'interactive edit failed'
seat_block "$EDIT_REPO/swarm.config.toml" arch_1 | grep -q 'default_kind = "opencode"' \
  || fail 'interactive provider answer was not saved to the existing architect'
seat_block "$EDIT_REPO/swarm.config.toml" arch_1 | grep -q 'model = "zai-coding-plan/glm-5.3-flash"' \
  || fail 'interactive model answer was not saved to the existing architect'

# The launcher path answered interactively can never replace the config.
SAME_REPO="$TMP/same file repo"
fresh_repo "$SAME_REPO"
if printf '%s\n' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' "$SAME_REPO/swarm.config.toml" yes \
    | "$ROOT/bin/stampede" setup "$SAME_REPO" --launcher "$TMP/same-yeehaw.sh" >/dev/null 2>&1; then
  fail 'setup accepted the config path as the launcher destination'
fi
[[ ! -e "$SAME_REPO/swarm.config.toml" ]] || python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
  "$SAME_REPO/swarm.config.toml" || fail 'launcher overwrote the generated config'

# An attention-only edit keeps the architect roster size when the existing
# architect has a custom key or a descriptive role.
ROLE_REPO="$TMP/role repo"
fresh_repo "$ROLE_REPO"
cat > "$ROLE_REPO/swarm.config.toml" <<'EOF'
[seats.looper]
name = "looper"
role = "Autonomous Loop Orchestrator"
default_kind = "agy"
model = "gemini-3.8-flash-low"

[seats.pm]
name = "pm"
role = "Product Manager & Overseer"
default_kind = "claude"
model = "sonnet"

[seats.builder]
name = "builder"
role = "architect"
default_kind = "opencode"
model = "zai-coding-plan/glm-5.3"
EOF
"$ROOT/bin/stampede" setup "$ROLE_REPO" --non-interactive --force --launcher "$TMP/role-yeehaw.sh" \
  --attention quiet >/dev/null || fail 'custom-key attention edit failed'
grep -q '\[seats.builder\]' "$ROLE_REPO/swarm.config.toml" || fail 'custom architect key was dropped'
! grep -q '\[seats.arch_' "$ROLE_REPO/swarm.config.toml" || fail 'attention-only edit added architects beside builder'
grep -c '^\[seats.pm' "$ROLE_REPO/swarm.config.toml" | grep -qx 1 || fail 'descriptive PM role grew the PM roster'
DESC_REPO="$TMP/descriptive repo"
fresh_repo "$DESC_REPO"
sed -e 's/^\[seats.builder\]/[seats.arch_1]/' -e 's/^name = "builder"/name = "arch-1"/' \
  -e 's/^role = "architect"/role = "Implementation Engine (GLM-5.3)"/' \
  "$ROLE_REPO/swarm.config.toml.bak" > "$DESC_REPO/swarm.config.toml"
"$ROOT/bin/stampede" setup "$DESC_REPO" --non-interactive --force --launcher "$TMP/desc-yeehaw.sh" \
  --attention quiet >/dev/null || fail 'descriptive-role attention edit failed'
! grep -q '\[seats.arch_2\]' "$DESC_REPO/swarm.config.toml" || fail 'descriptive architect role grew the roster'
seat_block "$DESC_REPO/swarm.config.toml" arch_1 | grep -q 'critical = true' \
  || fail 'descriptive architect role lost its critical default'

# A repurposed singleton key is not rendered twice: [seats.docs] serving as
# the architect leaves the docs role a fresh, unused key.
REUSE_REPO="$TMP/reuse repo"
fresh_repo "$REUSE_REPO"
sed -e 's/^\[seats.builder\]/[seats.docs]/' "$ROLE_REPO/swarm.config.toml.bak" > "$REUSE_REPO/swarm.config.toml"
"$ROOT/bin/stampede" setup "$REUSE_REPO" --non-interactive --force --launcher "$TMP/reuse-yeehaw.sh" \
  --attention quiet >/dev/null 2>&1 || fail 'repurposed docs key broke an attention-only edit'
[[ "$(grep -c '^\[seats.docs\]$' "$REUSE_REPO/swarm.config.toml")" == 1 ]] || fail 'seat key rendered twice'
seat_block "$REUSE_REPO/swarm.config.toml" docs | grep -q 'role = "architect"' || fail 'repurposed seat lost its role'

# An automatic catalog substitute is not an edit: when a pinned model has
# left the provider's listing, an attention-only edit keeps every seat's pin.
PIN_REPO="$TMP/pin repo"
fresh_repo "$PIN_REPO"
cat > "$PIN_REPO/swarm.config.toml" <<'EOF'
[seats.looper]
name = "looper"
default_kind = "agy"
model = "gemini-3.8-flash-low"

[seats.arch_1]
name = "arch-1"
default_kind = "opencode"
model = "zai-coding-plan/glm-4.6"

[seats.arch_2]
name = "arch-2"
default_kind = "opencode"
model = "zai-coding-plan/glm-5.3"
EOF
cat > "$TMP/bin/opencode" <<'EOF'
#!/bin/sh
[ "$1" = models ] && printf '%s\n' zai-coding-plan/glm-5.3 zai-coding-plan/glm-5.3-flash
exit 0
EOF
chmod +x "$TMP/bin/opencode"
"$ROOT/bin/stampede" setup "$PIN_REPO" --non-interactive --force --launcher "$TMP/pin-yeehaw.sh" \
  --attention quiet >/dev/null || fail 'attention edit with a delisted pin failed'
seat_block "$PIN_REPO/swarm.config.toml" arch_1 | grep -q 'model = "zai-coding-plan/glm-4.6"' \
  || fail 'attention-only edit replaced a delisted model pin'
seat_block "$PIN_REPO/swarm.config.toml" arch_2 | grep -q 'model = "zai-coding-plan/glm-5.3"' \
  || fail 'attention-only edit changed a second seat pin'

printf 'test_setup: PASS\n'
