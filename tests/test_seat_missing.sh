#!/usr/bin/env bash
set -euo pipefail
# tests/test_seat_missing.sh — missing-seat visibility (D4)
#
# A seat whose launch fails on every chain kind never reaches the ledger,
# and a verify that only checks ledger seats cannot see it. Two scenarios:
#   A. a broken ARCH seat (critical) — up -m b must fail closed with a
#      failed-seat summary and must NOT emit a healthy swarm_ready event.
#   B. a broken docs seat (non-critical) — up succeeds, warns loudly, and
#      the swarm_ready payload names the missing seat.
ROOT=$(cd "$(dirname "$0")/.." && pwd)

make_env() { # REFUSE_PREFIX -> sets ENV_DIR (bin stubs + fresh target)
  ENV_DIR=$(mktemp -d)
  local target="$ENV_DIR/fresh project"
  mkdir -p "$target" "$ENV_DIR/bin"
  git -C "$target" init -q
  printf 'test:\n\t@true\n' > "$target/Makefile"
  git -C "$target" add Makefile
  git -C "$target" -c user.name=Test -c user.email=test@example.com commit -qm initial

  cat > "$ENV_DIR/bin/herdr" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
state_path = Path(os.environ['FAKE_HERDR_STATE'])
state = json.loads(state_path.read_text()) if state_path.exists() else {'workspaces': [], 'tabs': [], 'panes': [], 'agents': []}
a = sys.argv[1:]
with Path(os.environ['FAKE_HERDR_LOG']).open('a') as log:
    log.write(json.dumps(a) + '\n')
def option(flag, default=''):
    return a[a.index(flag) + 1] if flag in a else default
def emit(value):
    state_path.write_text(json.dumps(state))
    print(json.dumps({'result': value}))
def pane():
    number = len(state['panes']) + 1
    return f'w1:p{number}'
if a[:2] == ['integration', 'status']:
    print('agy installed; claude installed; opencode installed')
elif a[:2] == ['workspace', 'list']:
    emit({'workspaces': state['workspaces']})
elif a[:2] == ['workspace', 'create']:
    state['workspaces'].append({'workspace_id': 'w1', 'cwd': option('--cwd'), 'label': option('--label')})
    emit({'workspace': {'workspace_id': 'w1'}})
elif a[:2] == ['tab', 'list']:
    emit({'tabs': state['tabs']})
elif a[:2] == ['tab', 'create']:
    tab = f'w1:t{len(state["tabs"]) + 1}'
    state['tabs'].append({'tab_id': tab, 'label': option('--label')})
    state['panes'].append({'pane_id': pane(), 'tab_id': tab, 'cwd': state['workspaces'][0]['cwd']})
    emit({'tab': {'tab_id': tab}})
elif a[:2] == ['pane', 'list']:
    emit({'panes': state['panes']})
elif a[:2] == ['pane', 'split']:
    base = next(p for p in state['panes'] if p['pane_id'] == option('--pane'))
    child = {'pane_id': pane(), 'tab_id': base['tab_id'], 'cwd': option('--cwd', base['cwd'])}
    state['panes'].append(child)
    emit({'pane': child})
elif a[:2] == ['pane', 'layout']:
    emit({'layout': {'panes': []}})
elif a[:2] == ['agent', 'list']:
    emit({'agents': state['agents']})
elif a[:2] == ['agent', 'get']:
    agent = next((v for v in state['agents'] if v['name'] == a[2]), None)
    if agent is None: sys.exit(1)
    emit({'agent': agent})
elif a[:2] == ['agent', 'start']:
    refuse = os.environ.get('FAKE_HERDR_REFUSE', '')
    if refuse and a[2].startswith(refuse):
        sys.exit(1)
    seat_pane = option('--pane')
    seat = {'name': a[2], 'agent': option('--kind'), 'pane_id': seat_pane,
            'agent_status': 'idle', 'workspace_id': 'w1',
            'cwd': next(p['cwd'] for p in state['panes'] if p['pane_id'] == seat_pane)}
    state['agents'].append(seat)
    emit({'agent': seat})
else:
    emit({})
PY
  chmod +x "$ENV_DIR/bin/herdr"
  local kind
  for kind in agy claude opencode; do
    printf '#!/bin/sh\n[ "$1" = --version ] && echo fake-%s\n' "$kind" > "$ENV_DIR/bin/$kind"
    chmod +x "$ENV_DIR/bin/$kind"
  done
  printf '#!/bin/sh\nexit 0\n' > "$ENV_DIR/bin/gh"
  chmod +x "$ENV_DIR/bin/gh"
  PATH="$ENV_DIR/bin:$PATH"
  export PATH
  unset HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_ENV
  export FAKE_HERDR_STATE="$ENV_DIR/herdr-state.json" FAKE_HERDR_LOG="$ENV_DIR/herdr-calls.jsonl"
  "$ROOT/bin/stampede" setup "$target" --non-interactive --launcher "$ENV_DIR/yeehaw.sh" >/dev/null
  sed -i.bak 's/^default_kind = "opencode"$/kinds = ["opencode", "claude"]/' "$target/swarm.config.toml"
  mkdir -p "$target/.herdr-swarm"
  printf 'REPO=none\nTEST_CMD=make test\n' > "$target/.herdr-swarm/profile.env"
}

traces_of() { # TARGET -> stdout: every telemetry event line
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
for t in sorted(Path(sys.argv[1], '.herdr-swarm/traces').glob('*.jsonl')):
    for line in t.read_text().splitlines():
        print(line)
PY
}

echo "==> A: broken arch seat fails closed in mode b"
make_env
export FAKE_HERDR_REFUSE='arch-'
set +e
"$ENV_DIR/yeehaw.sh" start --brainstorm --topic "launch check" > "$ENV_DIR/up.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || { echo "A: up -m b exited 0 with a broken arch seat" >&2; tail -20 "$ENV_DIR/up.log" >&2; exit 1; }
grep -q "arch-1" "$ENV_DIR/up.log" || { echo "A: failed-seat summary does not name the arch seat" >&2; tail -20 "$ENV_DIR/up.log" >&2; exit 1; }
if traces_of "$ENV_DIR/fresh project" | grep -q '"swarm_ready"'; then
  echo "A: swarm_ready emitted despite a broken critical seat" >&2
  exit 1
fi

echo "==> B: broken docs seat is loud but non-fatal"
make_env
export FAKE_HERDR_REFUSE='docs-'
set +e
"$ENV_DIR/yeehaw.sh" start --brainstorm --topic "launch check" > "$ENV_DIR/up.log" 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || { echo "B: up -m b failed on a non-critical seat" >&2; tail -20 "$ENV_DIR/up.log" >&2; exit 1; }
grep -q "docs-" "$ENV_DIR/up.log" || { echo "B: missing docs seat not named in output" >&2; tail -20 "$ENV_DIR/up.log" >&2; exit 1; }
traces_of "$ENV_DIR/fresh project" | grep '"swarm_ready"' | grep -q '"missing_seats"' \
  || { echo "B: swarm_ready payload does not carry missing_seats" >&2; traces_of "$ENV_DIR/fresh project" >&2; exit 1; }
traces_of "$ENV_DIR/fresh project" | grep '"swarm_ready"' | grep -q 'docs-' \
  || { echo "B: swarm_ready does not name the docs seat" >&2; exit 1; }

printf 'test_seat_missing: PASS\n'
