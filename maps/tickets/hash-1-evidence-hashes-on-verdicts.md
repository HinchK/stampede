---
id: HASH-1
title: "Evidence hashes on session verdict records"
type: wayfinder:task
status: resolved
assignee: arch
owns: loop-bot-herd.sh, lib/telemetry.py
parent: maps/pick-up-where-we-left-off.md
---

# HASH-1 — tamper-evident verdict records: sha256 of the gate log, plus host/pid

## Intended Outcome

Every row appended to `.herdr-swarm/session-verdicts.jsonl` — supervisor-harvested verdicts and
the arbiter-written integration records (INTEG-REC-1) — carries an evidence digest
(`sha256` of the per-verdict gate log) and supervising `host`/`pid`, making the verdict trail
tamper-evident in the judgment-ledger style (OpenRig comparison §7 #3, adopted via BORROW-1).

## Background (receipts)

- Current schema (supervisor harvest, `loop-bot-herd.sh`):
  `{"ts", "ticket", "sha", "seat", "suite", "exit_code", "verdict"}` — records the *claim of
  green* but not a verifiable pointer to the evidence that produced it; the per-verdict gate logs
  exist (`.herdr-swarm/gate-logs/`, `.herdr-swarm/gates/`) but nothing binds a row to its log.
- OpenRig `Judgment` records carry SHA-256 evidence refs and named judges
  (`openrig:packages/daemon/src/domain/proof/judgments.ts:L7-L24`, per
  `.herdr-swarm/research/2026-10-08-openrig-comparison-review.md` §5.4) — auditable claims. We
  adopt the *format*, not their gate: our records still point at mechanically re-executed
  evidence (the §8 decline on reviewer-verdicts-as-verification stands).
- Small schema change, additive fields only; legacy rows must keep parsing.

## Done-Criteria

1. Supervisor harvest appends `gate_log_sha256` (sha256 over the gate log bytes for that
   `(ticket, sha)` run), `host` (`hostname -s` or `$HOSTNAME` fallback), and `pid` (supervisor
   process) to each new verdict row.
2. The arbiter's INTEG-REC-1 integration records gain the same fields (hash over the arbiter gate
   log for the integrated candidate).
3. Readers tolerate legacy rows without the fields (`jq '.gate_log_sha256 // empty'` — no suite
   or status surface may break on old rows).
4. Tests: `tests/test_async_gate.sh` (verdict rows carry the fields; hash matches an independently
   computed `shasum -a 256` of the gate log) and `tests/test_arbiter.sh` (integration records).
5. `make check` green (all suites), 0 ShellCheck warnings.

## Verification Step

```bash
bash tests/test_async_gate.sh && bash tests/test_arbiter.sh && make check
```

## Resolution (2026-10-08)

Resolved in commit `7dc5aa5a9247c4f4bdf194ea0770af13457be3f1` (`7dc5aa5`).

Delivered across all criteria:
1. **Supervisor rows**: `_verdict_evidence` (loop-bot-herd.sh:46) appends `"host"` (`hostname -s`, `$HOSTNAME` fallback via `evidence_host`, lib/common.sh) and `"pid"` (`$$`, the supervisor) to every one of the 10 session-verdicts append sites — async reap, headless dead-letter, skipped/unresolvable/stale, inline invalidated/green/RED, no-runnable-suite, gate-off. `gate_log_sha256` (`evidence_sha256`: `shasum -a 256`, GNU `sha256sum` fallback) is added exactly where a gate log exists for the run; rows that never ran a gate (skipped/stale/dead-letter) omit the key rather than fabricate a hash.
2. **Arbiter rows**: `_arb_verdict_record` (lib/arbiter.sh:97) now takes the gate-log path from `_arb_integrate`; integration rows carry host + pid always, and the sha256 of `gate-logs/arbiter-<ticket>-<sha7>.log` when the combined tree was actually suite-gated (an ungated integration records no hash — receipt in test 215).
3. **Legacy tolerance**: fields are additive; readers access via `.gate_log_sha256 // empty` / `== null`. Existing suites over legacy-shaped fixture rows (test_cli_status §fixtures, cli/headless) pass unchanged — that IS the backward-compat receipt — plus explicit legacy-row assertions in both new sections.
4. **Tests**: `tests/test_async_gate.sh` §1f/14c2-14c4 (reaped green rows for two seats match independently computed `shasum -a 256` of their gate logs; host equals this host; pid equals the supervising shell; a skipped fabricated-sha row carries host/pid and NO hash; a seeded legacy row parses clean) and `tests/test_arbiter.sh` §2d (#201 row hash matches an independent shasum; host/pid typed correctly; ungated #215 integration has no fabricated hash; legacy row reads clean). Suites: async 96/96, arbiter 103/103.
5. **Verification**: `bash tests/test_async_gate.sh && bash tests/test_arbiter.sh` green; `make check` green (21 suites); `make lint` 0 warnings.
