#!/usr/bin/env bash
set -euo pipefail
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
unset HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_ENV
export PATH="$TMP/bin:$PATH"
export FAKE_HERDR_STATE="$TMP/herdr-state.json" FAKE_HERDR_LOG="$TMP/herdr-calls.jsonl"
"$ROOT/bin/stampede" setup "$TARGET" --non-interactive --launcher "$TMP/yeehaw.sh" >/dev/null
mkdir -p "$TARGET/.herdr-swarm"
printf 'REPO=none\nTEST_CMD=make test\n' > "$TARGET/.herdr-swarm/profile.env"

"$TMP/yeehaw.sh" start --seat-only > "$TMP/first.log" 2>&1 || { tail -40 "$TMP/first.log"; exit 1; }
python3 - "$TARGET/.herdr-swarm/seats.json" "$FAKE_HERDR_LOG" <<'PY'
import json, sys
ledger = json.load(open(sys.argv[1]))
calls = [json.loads(line) for line in open(sys.argv[2])]
seats = ledger['seats']
assert len([s for s in seats if not s.get('agentless')]) == 6, seats
assert all(s['isolated'] for s in seats if not s.get('agentless')), seats
assert len([s for s in seats if s.get('agentless')]) >= 5, seats
starts = [c for c in calls if c[:2] == ['agent', 'start']]
assert len(starts) == 6, starts
oc_starts = [c for c in starts if c[c.index('--kind') + 1] == 'opencode']
assert len(oc_starts) == 2, starts
assert all('--model' not in c for c in oc_starts), starts
assert any('--model' in c and 'sonnet' in c for c in starts), starts
arch = next(s for s in seats if s['name'].startswith('arch-1'))
pin = open(arch['worktree_dir'] + '/.opencode/opencode.json').read()
assert 'zai-coding-plan/glm-5.3' in pin, pin
assert not any(c[:2] == ['agent', 'start'] and 'looper' in c[2] for c in calls), calls
assert not any('arbiter' in ' '.join(c) for c in calls), calls
PY
[[ -f "$TARGET/.herdr-swarm/seat-only" ]] || { echo 'seat-only intake marker absent' >&2; exit 1; }

first_panes=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["panes"]))' "$FAKE_HERDR_STATE")
"$TMP/yeehaw.sh" start --seat-only > "$TMP/second.log" 2>&1 || { tail -40 "$TMP/second.log"; exit 1; }
second_panes=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["panes"]))' "$FAKE_HERDR_STATE")
[[ "$first_panes" == "$second_panes" ]] || { echo 'reattach duplicated Herdr panes' >&2; exit 1; }
watch_calls=$(python3 -c 'import json,sys; print(sum(1 for line in open(sys.argv[1]) if "loop-bot-herd.sh" in " ".join(json.loads(line)) and json.loads(line)[:2] == ["pane", "run"]))' "$FAKE_HERDR_LOG")
[[ "$watch_calls" -ge 2 ]] || { echo 'dead supervisor was not restarted on reattach' >&2; exit 1; }
printf '%s\n' "$$" > "$TARGET/.herdr-swarm/supervisor.pid"
"$TMP/yeehaw.sh" start --seat-only > "$TMP/third.log" 2>&1 || { tail -40 "$TMP/third.log"; exit 1; }
watch_calls_after=$(python3 -c 'import json,sys; print(sum(1 for line in open(sys.argv[1]) if "loop-bot-herd.sh" in " ".join(json.loads(line)) and json.loads(line)[:2] == ["pane", "run"]))' "$FAKE_HERDR_LOG")
[[ "$watch_calls" == "$watch_calls_after" ]] || { echo 'live supervisor was started twice' >&2; exit 1; }
printf 'test_frontier_launch: PASS\n'
