#!/usr/bin/env bash
set -euo pipefail
# tests/test_seat_fallback.sh — launch-failure fallback (PUB-6, D3)
#
# Binary health orders the provider chain; a start that fails to register a
# ready agent must fall through to the next kind. The fake herdr rejects
# opencode starts (binary present and healthy — the launch itself fails) and
# accepts claude, so a healthy chain is exercised end to end: opencode
# attempted first, claude seated, seat.fallback telemetry recorded, and the
# opencode-only model never forwarded to the claude fallback.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TARGET="$TMP/fresh project"
mkdir -p "$TARGET" "$TMP/bin"
git -C "$TARGET" init -q
printf 'test:\n\t@true\n' > "$TARGET/Makefile"
git -C "$TARGET" add Makefile
git -C "$TARGET" -c user.name=Test -c user.email=test@example.com commit -qm initial

cat > "$TMP/bin/herdr" <<'PY'
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
    seat_pane = option('--pane')
    seat = {'name': a[2], 'agent': option('--kind'), 'pane_id': seat_pane,
            'agent_status': 'idle', 'workspace_id': 'w1',
            'cwd': next(p['cwd'] for p in state['panes'] if p['pane_id'] == seat_pane)}
    if seat['agent'] == 'opencode':
        # Launch failure (D3): binary healthy, start never reaches a ready
        # agent — exactly the failure the chain must survive.
        sys.exit(1)
    state['agents'].append(seat)
    emit({'agent': seat})
else:
    emit({})
PY
chmod +x "$TMP/bin/herdr"
for kind in agy claude opencode; do
  printf '#!/bin/sh\n[ "$1" = --version ] && echo fake-%s\n' "$kind" > "$TMP/bin/$kind"
  chmod +x "$TMP/bin/$kind"
done
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
unset HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_ENV
export FAKE_HERDR_STATE="$TMP/herdr-state.json" FAKE_HERDR_LOG="$TMP/herdr-calls.jsonl"
"$ROOT/bin/stampede" setup "$TARGET" --non-interactive --launcher "$TMP/yeehaw.sh" >/dev/null
# Architect seats get the shipped fallback chain: primary opencode, claude
# behind it (mirrors [seats.arch_*] kinds in the repo's swarm.config.toml).
sed -i.bak 's/^default_kind = "opencode"$/kinds = ["opencode", "claude"]/' "$TARGET/swarm.config.toml"
mkdir -p "$TARGET/.herdr-swarm"
printf 'REPO=none\nTEST_CMD=make test\n' > "$TARGET/.herdr-swarm/profile.env"

"$TMP/yeehaw.sh" start --seat-only > "$TMP/up.log" 2>&1 || { tail -40 "$TMP/up.log"; exit 1; }

python3 - "$TARGET/.herdr-swarm/seats.json" "$FAKE_HERDR_LOG" <<'PY'
import json, sys
ledger = json.load(open(sys.argv[1]))
calls = [json.loads(line) for line in open(sys.argv[2])]
seats = {s['name']: s for s in ledger['seats']}
arch = [s for n, s in seats.items() if n.startswith('arch-')]
assert len(arch) == 2, seats
assert all(s['kind'] == 'claude' for s in arch), seats
starts = [c for c in calls if c[:2] == ['agent', 'start']]
for seat in arch:
    seq = [c for c in starts if c[2] == seat['name']]
    assert len(seq) == 2, (seat['name'], starts)
    assert seq[0][seq[0].index('--kind') + 1] == 'opencode', seq[0]
    assert seq[1][seq[1].index('--kind') + 1] == 'claude', seq[1]
    # The opencode-only model never travels to the claude fallback.
    assert '--model' not in seq[1], seq[1]
# No opencode seat ever registered (launch refused); pm stayed claude.
oc_seated = [c for c in starts if c[c.index('--kind') + 1] == 'opencode']
assert len(oc_seated) == 2, starts
PY

# seat.fallback telemetry: one event per arch seat, launch-failure reason.
python3 - "$TARGET" <<'PY'
import json, sys
from pathlib import Path
traces = list(Path(sys.argv[1], '.herdr-swarm/traces').glob('*.jsonl'))
events = [json.loads(line) for t in traces for line in t.read_text().splitlines()]
fb = [e for e in events if e.get('event_type') == 'seat.fallback']
assert len(fb) == 2, events
for e in fb:
    p = e.get('payload') or {}
    assert p.get('used') == 'claude', p
    assert p.get('wanted') == 'opencode', p
    assert p.get('reason') == 'launch_failed', p
PY
printf 'test_seat_fallback: PASS\n'
