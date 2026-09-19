#!/usr/bin/env bash
# Layout Engine for Herdr Swarm
# Manages multi-tab pane topologies and enforces the 80x20 floor

set -euo pipefail

MIN_COLS=80
MIN_ROWS=20

# split_pane PANE_ID DIRECTION [RATIO]
split_pane() {
  local pane="$1"
  local dir="$2"
  local ratio="${3:-0.5}"
  local cwd="${4:-$PWD}"
  herdr pane split --pane "$pane" --direction "$dir" --ratio "$ratio" --cwd "$cwd" --no-focus \
    | jq -r '.result.pane.pane_id // empty'
}

# tab_by_label WS_ID LABEL -> prints "TAB_ID PANE_ID"
tab_by_label() {
  local ws_id="$1"
  local label="$2"
  local tab pane

  tab=$(herdr tab list --workspace "$ws_id" 2>/dev/null \
    | jq -r --arg l "$label" '.result.tabs[]? | select((.label // .title // "") == $l) | .tab_id' \
    | head -n1)

  if [[ -z "$tab" ]]; then
    local before now
    before=$(herdr pane list --workspace "$ws_id" 2>/dev/null | jq -r '.result.panes[]?.pane_id' | sort)
    tab=$(herdr tab create --workspace "$ws_id" --label "$label" 2>/dev/null \
      | jq -r '.result.tab.tab_id // empty')
    if [[ -z "$tab" ]]; then return 1; fi
    now=$(herdr pane list --workspace "$ws_id" 2>/dev/null | jq -r '.result.panes[]?.pane_id' | sort)
    pane=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$now") | head -n1)
  else
    pane=$(herdr pane list --workspace "$ws_id" 2>/dev/null \
      | jq -r --arg t "$tab" '.result.panes[]? | select(.tab_id == $t) | .pane_id' | head -n1)
  fi

  [[ -n "$pane" ]] || return 1
  printf '%s %s\n' "$tab" "$pane"
}

# check_and_relocate_geometry WS_ID ANCHOR_PANE PANE...
check_and_relocate_geometry() {
  local ws_id="$1"
  local anchor="$2"
  shift 2
  local layout rects
  layout=$(herdr pane layout --pane "$anchor" 2>/dev/null) || return 0
  rects=$(jq -r '.result.layout.panes[]? | "\(.pane_id) \(.rect.width)x\(.rect.height)"' <<<"$layout" 2>/dev/null) || return 0
  [[ -z "$rects" ]] && return 0

  local p line geom w h rescue_tab
  for p in "$@"; do
    line=$(grep -E "^${p} " <<<"$rects" || true)
    [[ -z "$line" ]] && continue
    geom=${line#* }; w=${geom%x*}; h=${geom#*x}
    if (( w > 0 && h > 0 && (w < MIN_COLS || h < MIN_ROWS) )); then
      printf '  \033[33m⚠ Pane %s is %sx%s (below %sx%s floor); relocating to dedicated tab\033[0m\n' \
        "$p" "$w" "$h" "$MIN_COLS" "$MIN_ROWS"
      rescue_tab=$(herdr tab create --workspace "$ws_id" --label "seat-${p##*:}" 2>/dev/null \
        | jq -r '.result.tab.tab_id // empty')
      if [[ -n "$rescue_tab" ]]; then
        herdr pane move "$p" --tab "$rescue_tab" >/dev/null 2>&1 || true
      fi
    fi
  done
}
