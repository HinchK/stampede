#!/usr/bin/env bash
# tests/test_layout_engine.sh — tab layout invariants.
#
# Part 1: cramped panes must not grow rescue tabs.
#
# A 50/50 split of a ~120-column window is 60 columns, under the 80-column
# floor, so every seated pane used to trip check_and_relocate_geometry.
# That function created a tab (and its empty shell pane) and then ran
# `herdr pane move --tab` without `--split`, which current Herdr rejects.
# The agent stayed put. The empty tab remained. Every launch added them.
#
# Part 2 (T-LAYOUT-4PANE): no tab may ever hold more than 4 panes (the
# 2×2 grid of ADR 0011). The bounded-looper logging/monitor views
# (telemetry-stream, supervisor, worklog, handoff) live in a dedicated
# 'logs' tab; 'ops' holds interactive agent seats only.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENV_DIR=$(mktemp -d)
T=""
trap 'rm -rf "$ENV_DIR" ${T:+"$T"}' EXIT

cat > "$ENV_DIR/herdr" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
with open(os.environ["HERDR_LOG"], "a") as log:
    log.write(json.dumps(a) + "\n")
def emit(value):
    print(json.dumps({"result": value}))
if a[:2] == ["pane", "layout"]:
    emit({"layout": {"panes": [
        {"pane_id": "w1:p4", "rect": {"width": 60, "height": 40}},
        {"pane_id": "w1:p5", "rect": {"width": 60, "height": 13}},
    ]}})
elif a[:2] == ["tab", "create"]:
    emit({"tab": {"tab_id": "w1:t9"}})
else:
    emit({})
PY
chmod +x "$ENV_DIR/herdr"
export HERDR_LOG="$ENV_DIR/calls.jsonl"
export PATH="$ENV_DIR:$PATH"

# shellcheck disable=SC1091
source "$ROOT/lib/layout_engine.sh"
check_and_relocate_geometry w1 w1:p2 w1:p4 w1:p5

if [[ -f "$HERDR_LOG" ]] && grep -Eq '"tab", "create"|"pane", "move"' "$HERDR_LOG"; then
  echo "cramped panes created a rescue tab or tried to move" >&2
  cat "$HERDR_LOG" >&2
  exit 1
fi

if grep -n 'check_and_relocate_geometry' "$ROOT/herdr-loop-swarm.sh" >/dev/null; then
  echo "launcher still runs the geometry rescue" >&2
  exit 1
fi

echo "ok: cramped panes do not create rescue tabs"

# ── Part 2: T-LAYOUT-4PANE — no tab exceeds 4 panes ────────────────────────
T=$(mktemp -d)
mkdir -p "$T/bin"

# Stateful fake herdr (frontier-launch pattern): tabs/panes/agents in a JSON
# state file, every invocation appended to a call log. `pane close` removes
# the pane so anchor-closing is observable in the final state.
cat > "$T/bin/herdr" <<'PY'
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
    # Monotonic ids: `pane close` removes entries, so deriving the next id
    # from len(panes) would REUSE live pane ids (real Herdr never does).
    number = state.get('next_pane', len(state['panes']) + 1)
    state['next_pane'] = number + 1
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
    state['panes'].append({'pane_id': pane(), 'tab_id': tab, 'cwd': state['workspaces'][0]['cwd'] if state['workspaces'] else '/tmp'})
    emit({'tab': {'tab_id': tab}})
elif a[:2] == ['pane', 'list']:
    emit({'panes': state['panes']})
elif a[:2] == ['pane', 'split']:
    base = next(p for p in state['panes'] if p['pane_id'] == option('--pane'))
    child = {'pane_id': pane(), 'tab_id': base['tab_id'], 'cwd': option('--cwd', base.get('cwd', '/tmp'))}
    state['panes'].append(child)
    emit({'pane': child})
elif a[:2] == ['pane', 'close']:
    state['panes'] = [p for p in state['panes'] if p['pane_id'] != a[2]]
    emit({})
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
chmod +x "$T/bin/herdr"
for kind in agy claude opencode; do
  printf '#!/bin/sh\n[ "$1" = --version ] && echo fake-%s\n' "$kind" > "$T/bin/$kind"
  chmod +x "$T/bin/$kind"
done
printf '#!/bin/sh\nexit 0\n' > "$T/bin/gh"
chmod +x "$T/bin/gh"
unset HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_ENV
export PATH="$T/bin:$PATH"
export FAKE_HERDR_STATE="$T/herdr-state.json" FAKE_HERDR_LOG="$T/herdr-calls.jsonl"

# 2a. unit: enforce_tab_pane_limit flags a >4 tab and passes a ≤4 state.
declare -F enforce_tab_pane_limit >/dev/null \
  || { echo 'enforce_tab_pane_limit is missing from lib/layout_engine.sh' >&2; exit 1; }
python3 - "$FAKE_HERDR_STATE" <<'PY'
import json, sys
panes = []
panes += [{'pane_id': f'w1:p{i}', 'tab_id': 'w1:t1'} for i in range(1, 5)]   # t1: 4 panes (at cap)
panes += [{'pane_id': f'w1:p{i}', 'tab_id': 'w1:t2'} for i in range(5, 10)]  # t2: 5 panes (over)
json.dump({'workspaces': [], 'tabs': [
    {'tab_id': 'w1:t1', 'label': 'herd'},
    {'tab_id': 'w1:t2', 'label': 'ops'}], 'panes': panes, 'agents': []}, open(sys.argv[1], 'w'))
PY
if enforce_tab_pane_limit w1 4 >/dev/null 2>"$T/enf.err"; then
  echo 'enforce_tab_pane_limit passed a 5-pane tab' >&2
  exit 1
fi
grep -q 'w1:t2' "$T/enf.err" \
  || { echo "enforce_tab_pane_limit did not name the offending tab: $(cat "$T/enf.err")" >&2; exit 1; }
python3 - "$FAKE_HERDR_STATE" <<'PY'
import json, sys
panes = [{'pane_id': f'w1:p{i}', 'tab_id': 'w1:t1'} for i in range(1, 5)]
json.dump({'workspaces': [], 'tabs': [{'tab_id': 'w1:t1', 'label': 'herd'}],
           'panes': panes, 'agents': []}, open(sys.argv[1], 'w'))
PY
enforce_tab_pane_limit w1 4 2>"$T/enf2.err" \
  || { echo "enforce_tab_pane_limit failed a 4-pane tab: $(cat "$T/enf2.err")" >&2; exit 1; }
echo "ok: enforce_tab_pane_limit caps tabs at 4 panes"

# 2b. integration: the real launcher seats a fresh swarm under the fake herdr
# and the invariant holds — 'logs' exists with the model-free 2×2, 'ops'
# holds only agent seats, no tab exceeds 4 panes.
rm -f "$FAKE_HERDR_STATE" "$FAKE_HERDR_LOG"
TARGET="$T/fresh project"
mkdir -p "$TARGET"
git -C "$TARGET" init -q
printf 'test:\n\t@true\n' > "$TARGET/Makefile"
git -C "$TARGET" add Makefile
git -C "$TARGET" -c user.name=Test -c user.email=test@example.com commit -qm initial
"$ROOT/bin/stampede" setup "$TARGET" --non-interactive --launcher "$T/yeehaw.sh" >/dev/null
mkdir -p "$TARGET/.herdr-swarm"
printf 'REPO=""\nREPO_LOCAL_ONLY=1\nTEST_CMD=make test\n' > "$TARGET/.herdr-swarm/profile.env"
"$T/yeehaw.sh" start --seat-only > "$T/up.log" 2>&1 \
  || { tail -40 "$T/up.log" >&2; exit 1; }
python3 - "$FAKE_HERDR_STATE" "$FAKE_HERDR_LOG" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
calls = [json.loads(l) for l in open(sys.argv[2])]
labels = {t['tab_id']: t.get('label') for t in state['tabs']}
by_tab = {}
for p in state['panes']:
    by_tab.setdefault(p['tab_id'], set()).add(p['pane_id'])

# (a) strict invariant: every tab <= 4 panes
for tid, ids in sorted(by_tab.items()):
    assert len(ids) <= 4, ('tab over cap', labels.get(tid), len(ids), sorted(ids))

# (b) a dedicated logs tab exists holding exactly the 4 model-free views
logs_tabs = [tid for tid, lbl in labels.items() if lbl == 'logs']
assert len(logs_tabs) == 1, ('logs tab missing', labels)
logs_ids = by_tab[logs_tabs[0]]
assert len(logs_ids) == 4, ('logs tab pane count', len(logs_ids))

# (c) every view pane (telemetry stream, supervisor watch, tail) is in logs
def run_panes(marker):
    return {c[2] for c in calls if c[:2] == ['pane', 'run'] and marker in ' '.join(c[3:])}
view_panes = set()
for marker in ('telemetry.py', 'loop-bot-herd.sh', 'tail -n 30 -F'):
    view_panes |= run_panes(marker)
assert view_panes, 'no view panes were started'
assert view_panes <= logs_ids, ('view pane outside the logs tab', view_panes - logs_ids)

# (d) no agent pane lives in the logs tab
agent_panes = {c[c.index('--pane') + 1] for c in calls if c[:2] == ['agent', 'start']}
assert agent_panes, 'no agents were seated'
assert not (agent_panes & logs_ids), ('agent seated in the logs tab', agent_panes & logs_ids)

# (e) ops holds exactly its agent seats (interactive seats only)
ops_tabs = [tid for tid, lbl in labels.items() if lbl == 'ops']
assert len(ops_tabs) == 1, ('ops tab missing', labels)
ops_ids = by_tab[ops_tabs[0]]
ops_agents = {p for p in agent_panes if p in ops_ids}
assert ops_ids == ops_agents, ('ops tab holds non-agent panes', ops_ids ^ ops_agents)
print('layout invariants verified')
PY
echo "ok: no tab exceeds 4 panes (logs tab carries the model-free views)"
