---
id: HL-LEDGER-1
title: "stampede headless ledger upsert clobbers live interactive seat in seats.json"
type: wayfinder:defect
status: backlog
assignee: arch
owns: lib/cli/stampede-headless.sh,tests/test_cli.sh
parent: maps/next-horizon.md
---

# HL-LEDGER-1 — prevent headless worker ledger collision with live interactive seats

**Severity:** HIGH (ledger corruption of live interactive seats; breaks supervisor routing and teardown).  
**Found by:** `looper` during pre-flight investigation for `#HORIZON-2`.

## Root Cause

In `lib/cli/stampede-headless.sh:104-133`:

```bash
local seat_name="arch_1" seat_kind="opencode" name_var="SEAT_NAME_${seat_key}" kind_var="SEAT_KIND_${seat_key}"
[[ -n "${!name_var:-}" ]] && seat_name=${!name_var}
[[ -n "${!kind_var:-}" ]] && seat_kind=${!kind_var}
...
rec=$(jq -cn --arg n "$seat_name" --arg k "$seat_kind" --arg w "$wt_dir" --arg b "$wt_branch" \
  '{name: $n, kind: $k, pane: "", worktree_dir: $w, branch: $b, isolated: true}')
if [[ -f "$ledger" ]]; then
  jq --argjson r "$rec" 'if any(.seats[]?; .name == $r.name) then .seats = map(if .name == $r.name then $r else . end) else .seats += [$r] end' \
    "$ledger" > "${ledger}.tmp" && mv "${ledger}.tmp" "$ledger"
```

1. In a live interactive repo (like this one), `SEAT_NAME_arch_1` binds to `"arch-1-hinchk-stampede"`.
2. `stampede headless` sets `seat_name="arch-1-hinchk-stampede"` and provisions `.herdr-swarm/worktrees/arch_1` on branch `swarm/stampede/arch_1`.
3. It then constructs a ledger record `$rec` with `name: "arch-1-hinchk-stampede"` and `pane: ""`.
4. The jq upsert matches the live interactive seat (`.name == $r.name`) already recorded in `.herdr-swarm/seats.json` by `herdr-loop-swarm.sh up`.
5. This **overwrites** the live seat:
   - Erases `pane: "wW:p5"` to `""`.
   - Replaces `worktree_dir: "/path/to/.herdr-swarm/worktrees/arch-1-hinchk-stampede"` with `".../worktrees/arch_1"`.
   - Replaces `branch: "swarm/hinchk-stampede/arch-1-hinchk-stampede"` with `"swarm/stampede/arch_1"`.
6. Consequence: The supervisor's `resolve_seat_gate` now routes live interactive arch-1 gate checks to the headless worktree, while `swarm down` or lifecycle commands lose track of the live pane and worktree mapping.

## Done-Criteria

1. Headless workers must be uniquely namespaced (e.g. `headless-<seat_name>` or `headless-<seat_key>-<slug>`) so their ledger records never match or overwrite a live interactive seat in `.herdr-swarm/seats.json`.
2. Alternatively, headless mode isolates its ledger or prevents overwriting live seats with active panes.
3. Test coverage added in `tests/test_cli.sh` asserting that running headless in a directory with pre-existing interactive seats in `seats.json` does not overwrite or mutate the interactive seat's `pane`, `worktree_dir`, or `branch`.
4. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_cli.sh
```
