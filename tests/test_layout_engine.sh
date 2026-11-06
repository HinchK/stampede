#!/usr/bin/env bash
# Cramped panes must not grow rescue tabs.
#
# A 50/50 split of a ~120-column window is 60 columns, under the 80-column
# floor, so every seated pane used to trip check_and_relocate_geometry.
# That function created a tab (and its empty shell pane) and then ran
# `herdr pane move --tab` without `--split`, which current Herdr rejects.
# The agent stayed put. The empty tab remained. Every launch added them.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENV_DIR=$(mktemp -d)
trap 'rm -rf "$ENV_DIR"' EXIT

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
