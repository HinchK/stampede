---
id: SUPER-1
title: "Supervisor: normalize ledger isolated boolean/integer across gate spawn, reap, and test harness"
type: wayfinder:task
status: backlog
assignee: arch
owns: loop-bot-herd.sh,tests/test_async_gate.sh,herdr-loop-swarm.sh
parent: maps/universal-herdr-swarm.md
---

# SUPER-1 — Ledger isolated type normalization in supervisor gate harvest

## Intended Outcome

Eliminate the type mismatch between how `herdr-loop-swarm.sh` writes `isolated` in `.herdr-swarm/seats.json` (integer `1`/`0`) and how `loop-bot-herd.sh` parses it (`true`/`false`), which caused `loop-bot-herd.sh`'s `gate_reap` to misidentify isolated worker seats as non-isolated and drop their transition to the review loop and integration queue upon green suite completion.

## Problem

1. `herdr-loop-swarm.sh` (line 542) sets `--argjson isolated "$seat_isolated"`, writing `"isolated": 1` (integer) into `seats.json`.
2. `loop-bot-herd.sh` `resolve_seat_gate` (line 192, 194) evaluates `GATE_ISOLATED=$(jq -r '.isolated // false' <<<"$rec")`, giving string `"1"`. `[[ "$GATE_ISOLATED" == "true" ]]` evaluates to false.
3. `gate_spawn` (line 253) passes `--arg iso "$isolated"` and evaluates `isolated: ($iso == "true")`, which evaluates to `false` in jq when `$iso` is `"1"`.
4. In `gate_reap` (line 295, 313), `iso=$(jq -r '.isolated // false' <<<"$meta")` is `"false"`. The block `if [[ "$iso" == "true" ]]; then` is skipped entirely, meaning `review_loop_on_gate_green` and `_review_directives` are never called for a green suite on an isolated seat.
5. In `tests/test_async_gate.sh` (line 92), the test fixture hardcoded `{..., isolated: true}`, which masked the defect during automated testing because the test used boolean `true` while the real launcher produced integer `1`.

## Done-Criteria

1. `herdr-loop-swarm.sh`: writes `isolated` as a JSON boolean (`true` / `false`), matching `lib/cli/stampede-headless.sh` and the ledger v2 contract.
2. `loop-bot-herd.sh`:
   - `resolve_seat_gate()` normalizes `isolated` robustly so that both boolean `true` and integer `1` (or `"1"`, `"true"`) are recognized as isolated.
   - `gate_spawn()` records `isolated: true` in `.job` whenever the seat is isolated (handling boolean or integer inputs).
   - `gate_reap()` evaluates `iso` robustly (handling boolean `true` or integer `1`).
3. `tests/test_async_gate.sh`:
   - Updates fixture(s) or adds explicit test assertion exercising an isolated seat defined with integer `isolated: 1` in `seats.json`, proving that green suites correctly trigger review loop dispatch / enqueueing under integer ledger values.
4. `make check` green (all 19 suites pass, 0 shellcheck warnings).

## Verification Step

```bash
bash tests/test_async_gate.sh
make check
```
