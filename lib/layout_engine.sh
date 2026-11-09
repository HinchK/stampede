#!/usr/bin/env bash
# Layout Engine for Herdr Swarm
# Tab lookup and pane splits for the herd and ops topology.

set -euo pipefail

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
# No-op. A rescue tab per cramped pane always left an empty shell behind:
# `herdr tab create` inserts a pane, and `herdr pane move --tab` without
# `--split` exits 2 on current Herdr, so the agent never moved. A 50/50
# split of a ~120-column window is 60 columns, under the old 80-column
# floor, so every seated pane tripped this on every launch.
check_and_relocate_geometry() {
  return 0
}

# enforce_tab_pane_limit WS_ID [MAX_PANES] — T-LAYOUT-4PANE invariant check.
# Counts live panes per tab; names every tab over the cap on stderr and
# returns 1 (0 when every tab is within MAX_PANES, default 4 — the 2×2
# grid of ADR 0011). Read-only: it checks, it never moves or closes panes.
enforce_tab_pane_limit() {
  local ws_id="$1" max="${2:-4}" over=0 tab count
  while IFS=$'\t' read -r tab count; do
    [[ -n "$tab" ]] || continue
    if (( count > max )); then
      printf 'layout: tab %s holds %d panes (cap %d)\n' "$tab" "$count" "$max" >&2
      over=1
    fi
  done < <(herdr pane list --workspace "$ws_id" 2>/dev/null \
    | jq -r '.result.panes[]? | .tab_id' | sort | uniq -c \
    | awk '{print $2 "\t" $1}')
  return "$over"
}
