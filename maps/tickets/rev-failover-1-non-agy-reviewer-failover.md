---
id: REV-FAILOVER-1
title: "Non-AGY reviewer failover on quota exhaustion"
type: wayfinder:task
status: backlog
assignee: arch
owns: swarm.config.toml, briefs/, loop-bot-herd.sh
parent: maps/pick-up-where-we-left-off.md
---

# REV-FAILOVER-1 — reviewer dispatch fails over to a non-AGY seat when the agy account is walled

## Intended Outcome

When the primary (agy) reviewer is quota-walled, the supervisor's reviewer dispatch fails over to
a configured **non-AGY reviewer seat**; one reviewer is active at a time; when the agy account
clears, dispatch returns to the primary. Closes the review availability SPOF named by the PM audit
2026-10-08 and completes FALLBACK-1's story per ADR 0018.

## Background (receipts)

- PM audit input in
  [REV-07](rev-07-multi-reviewer-quorum-decision.md): during the quota-outage experiment the
  stand-in orchestrator could dispatch and harvest, but nothing could pass review — the single
  reviewer seat (`default_kind = "agy"`) shares the exhausted account.
- QUOTA-2 built the exhaustion signal (`_agy_quota_exhausted` via `quota_probe_kind agy`,
  account-wide scan per QUOTA-5) and the deferral marker
  `.herdr-swarm/quota-deferred.jsonl`; QUOTA-3 built the point-in-time gate command
  (`bash lib/quota.sh gate agy <seat>`).
- [ADR 0018](../../../docs/adr/0018-single-reviewer-accepted-limit-with-quota-failover.md)
  settled: failover, not quorum; the OpenRig §7 #6 cross-vendor critique idea is realized here.

## Done-Criteria

1. `swarm.config.toml` declares a failover reviewer seat (or alias to an existing non-AGY seat,
   `kind != "agy"`), config-bound via `lib/config.sh` — no hardcoded seat names.
2. In `loop-bot-herd.sh`, when the primary reviewer is quota-exhausted (the QUOTA-2/QUOTA-5
   account-wide signal), reviewer dispatch (fresh, deferred-retry, and critique rounds) routes to
   the failover seat instead of deferring; when the account clears, dispatch returns to the
   primary. Exactly one reviewer serves a given verdict — no dual-active.
3. The failover reviewer satisfies the same reviewer contract as the primary: verdict anchor
   grammar (`REVIEW VERDICT #<id> <sha> <PASS|BLOCK>`), evidence-file schema
   (`.herdr-swarm/reviews/<ticket>-<sha>.md`), findings format, round budget — brief template
   derived from the existing reviewer brief (`briefs/reviewer.in.md`).
4. `reviews.json` / telemetry record which seat (primary vs failover) delivered each verdict.
5. Resolution is unambiguous per deferred verdict: a marker entry either retries to the primary
   (account clear) or fails over — never both.
6. Tests in `tests/test_async_gate.sh`: exhausted primary → dispatch to failover; account clear →
   return to primary; no dual-active; failover verdict drives the same REV-1..5 state machine.
7. `make check` green (all suites), 0 ShellCheck warnings.

## Verification Step

```bash
bash tests/test_async_gate.sh && make check
```
