# Herd Audit — 2026-09-19 (`pm`)

Scope: `loop-bot-herd-agy` (launcher, supervisor, libs, briefs, claude variant), live herd in workspace `wM`,
target repo `Standard-Pentest/kultivait`, arch's brainstorm (`/tmp/arch-out.md`, PRD-001), and looper's
`STATE.md` plan (baseline commit `95044cc`).

## TL;DR

The last milestone shipped clean. The new "universal herd" plan is sound in direction, but **looper's M1 is ordered
against the evidence**. It front-loads a fix for an overstated blocker (T-004), a namespacing refactor decided before
its research spike (T-005), and a heavy test harness (T-013). Meanwhile the one real correctness risk (T-002: wrong-repo default plus an
always-green gate) sits in M2. Re-order before arch picks up T-001.

## State of the herd

- **Map #228 (PyPI debut, v0.4.1) closed 8/8** on 2026-09-17. Suite **independently re-run by pm: 869 passed, 4 skipped, 1 warning (7.46s)**, which matches worker receipts; kultivait `main` has 0 unpushed
  commits and no open issues. Human push gate honored ("User authorized push" in process log).
- **Seats:** all 5 up in `wM`. arch's pane title shows a `rate_limit_event`; check its quota before dispatching.
- **T-014 is done** (`95044cc`, local only, no remote), but `STATE.md` §3–4 still lists it as the next action. Stale checkpoint.

## Arch's blockers, independently checked

| Claim | Verdict | Evidence |
|---|---|---|
| V1 — panes/agents land in the wrong workspace (no focus) | **Overstated → LOW** | `pane split` takes an explicit `PANE_ID`, `agent start` takes `--pane <ID>`, and IDs are workspace-prefixed (`wM:p6`). The anchor chain starts in `tab_by_label`, and both `tab list` and `tab create` accept `--workspace` (verified via `--help`). Residual risk only in `tab_by_label`'s pane-diff detection of a new tab's first pane. |
| V2 — silent `Standard-Pentest/kultivait` default | **Confirmed, and worse than stated** | `herdr-loop-swarm.sh:186`. Combined with `TEST_CMD="true"` when no manifest is found (`:142`), mode `a` in an unrecognized dir drives kultivait's backlog with a gate that is **always green**. |
| V3 — agent names are global | **Plausible, unproven** | `herdr agent get pm` resolves a bare name, but only one workspace has agents. T-001 must answer this before T-005 is built. |
| V4–V11 | Agree | Config dead (shellcheck: `CONFIG_FILE`, `SESSION_ID` unused), briefs kultivait-flavored, telemetry/guard never wired, README overclaims. |

## New findings (not in arch's audit)

1. **Suite-gate dedupe blocks re-verdicts — MED (dormant).** `loop-bot-herd.sh:97` skips any ticket already in
   `session-verdicts.jsonl`, *including RED records*. After RED, arch is told to "fix and re-verdict", but the re-verdict is
   never gated or filed. The same grep also **matches by substring**: ticket `#23` matches the record for `#230` (verified), so a prefix-numbered ticket is silently skipped. Fix: rewrite the check with `jq` for an exact ticket match where `suite != "RED"`.
2. **`dispatch` exits 127 — MED.** `loop-bot-herd.sh:182` calls `note`, which that script never defines. The prompt is sent,
   then the command dies under `set -e`.
3. **The supervisor has never run.** `~/.kultivait/loop-bot/session-verdicts.jsonl` does not exist, so the harvest, gate, and dedupe
   paths are unexercised.
4. **Observability has no contract.** Agents append free-form, differently-shaped events to one
   `~/.herdr-loop-swarm/traces/traces.jsonl`; `telemetry.py`'s per-session schema is unused. Receipts and the process log live in
   shared `/tmp` paths (cross-project collisions, lost on reboot; PRD-001 itself exists only in `/tmp/arch-out.md`).
5. **`agent_guard.sh:24`:** `agent wait` already defaults to idle|done|blocked; the repeated `--until` flags are redundant and
   trip shellcheck SC1010.
6. **Product identity is split three ways:** seating wizard (`herdr-loop-swarm.sh`), supervisor (`loop-bot-herd.sh`,
   hardcoded to `~/seeds/_KULT_/kultivait`), and the parallel worktree variant, whose header *also* calls itself `herdr-loop-swarm`.
7. **Stale models** in `swarm.config.toml` and the pm brief (`claude-3-7-sonnet`, `gemini-2.5-*`). Harmless while the config is dead;
   T-003 makes them live.

## Scope review of the plan (PRD-001 / STATE.md)

| Ticket | Looper's slot | PM call |
|---|---|---|
| T-002 profile, fail-closed repo | M2 | **Move to M1, top priority.** The only item that prevents mutating the wrong repo under a fake-green gate. |
| T-004 workspace focus | M1 | **Downgrade.** Premise (V1) is overstated. Keep only the "key workspace on `$PWD`, not basename" part; fold it into T-002. |
| T-005 namespacing | M1, already "decided" in STATE §1 | **Gate on T-001.** Touches launcher, supervisor, and all 5 briefs. Build only if names are proven global *and* two concurrent swarms is a real need. Remove it from "Decisions Made". |
| T-013 bats + `HERDR_FAKE` | M1 | **Right-size.** Shellcheck plus a `--plan` dry-run now; bats only around `profile.sh` and the TOML emitter, added with T-002/T-003. |
| T-012 ops-tab additions | M3 | **Defer / cut.** New capability (reviewer default-on, status board). The NFR "p95 `up` < 60s" is premature. |
| T-007 supervisor | M2 | **Split:** land the two bug fixes above now (small), genericize later. |
| T-015 README truth | M3 | **Pull a minimal slice forward:** strike claims for unwired telemetry/circuit breakers today. |

## Prioritized recommendations

1. **Re-order M1:** T-001 (spike) → T-002 (fail-closed repo + refuse mode `a` when `TEST_CMD=true`) → supervisor bug fixes
   (dedupe-on-RED, undefined `note`) → minimal README truth pass. Move T-004/T-005/T-013 behind T-001's findings.
2. **Refresh `STATE.md`:** mark T-014 done; move namespacing out of "Decisions Made" into "Open questions (pending T-001)".
3. **Version the PRD:** move `/tmp/arch-out.md` into `docs/prd/PRD-001-universal-herd.md` so the plan survives a reboot.
4. **Exercise the gate once:** after the fixes, run `loop-bot-herd.sh once` against kultivait to prove harvest → gate → file works.
5. **Driver decision needed:** which entrypoint is "the herd"? Recommended: the seating wizard plus the supervisor is the product;
   park the parallel claude variant as the M4 reference.
6. **Ops:** confirm arch's rate-limit status; route mechanical M1 work (README, gitignore, STATE refresh) to agy-flash.
