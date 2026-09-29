---
id: SUPER-1
title: "Supervisor: normalize ledger isolated boolean/integer across gate spawn, reap, and test harness"
type: wayfinder:task
status: resolved
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

## Resolution

- **Root Cause**: `herdr-loop-swarm.sh` serialized `isolated` as an integer (`1`/`0`) in `seats.json`, while `loop-bot-herd.sh` expected boolean strings (`"true"`), causing `gate_reap` to skip the review loop seam for green gates on isolated worker seats.
- **Implementation**:
  - `herdr-loop-swarm.sh`: Serializes JSON boolean `true`/`false` matching ledger v2 contract.
  - `loop-bot-herd.sh`: Robust normalization in `resolve_seat_gate`, `gate_spawn`, and `gate_reap` accepting `true`, `1`, `"1"`, and `"true"`, ensuring backward compatibility with existing on-disk ledgers.
- **Suite Gate**: `tests/test_async_gate.sh` §15 (+3 tests, 54/54 passing) proving integer-ledger green gates enqueue into arbiter and run in isolated worktree; `make check` all 19 suites green, 0 shellcheck warnings.
- **Review**: Autonomous Reviewer Loop PASS verdict by `reviewer-hinchk-stampede` (Round 1/2) in `.herdr-swarm/reviews/SUPER-1-3080ff9a3b4202d7b55f610626264a429924ad26.md`.
- **Integrated**: Re-integrated cleanly on real integration branch `swarm/stampede/integration` at `611cc4e` on top of `GRANT-1` (`c7d8367`). Verified via `git merge-base --is-ancestor 3080ff9 refs/heads/swarm/stampede/integration` and full `make check` green (19 suites). Lease released.
