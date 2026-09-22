---
id: PUB-6
title: "Per-seat provider fallback chains (kinds = [...])"
type: wayfinder:task
status: ready
assignee: arch
owns: herdr-loop-swarm.sh,lib/config.sh,swarm.config.toml,tests/test_config.sh,lib/providers.sh,lib/cli/stampede-doctor.sh,tests/test_providers.sh,tests/test_cli_doctor.sh,Makefile
parent: maps/public-multi-provider.md
blocked_by: PUB-2
---

> owns amended at execution (receipted): added `lib/providers.sh` (chain
> resolver + timeout-optional probe hardening), `lib/cli/stampede-doctor.sh`
> (chain-aware rows), `tests/test_providers.sh` / `tests/test_cli_doctor.sh`
> (resolver + FALLBACK assertions), and `Makefile` (lint coverage for
> `lib/cli/*.sh` — a coverage hole PUB-1 left). No other live ticket owns
> these files in this wave.

# PUB-6 — Fallback chains: seats survive a missing provider (Wave 10, runs alone)

## 1. Intended Outcome

A seat may declare an ordered chain, `kinds = ["opencode", "claude"]`.
Seating probes the chain in order and seats the first healthy provider
(using PUB-2's registry); `default_kind` remains valid as the
single-element form. A fallback seating emits a `seat.fallback` telemetry
event. No provider in the chain healthy → the seat fails; mode `a` aborts
fail-closed, mode `s` warns.

## 2. Problem

Today a missing/down provider CLI bricks its seat and usually the whole
`up`. Multi-provider users — the target audience — want graceful
degradation, not a hard stop, when one vendor has an outage or a quota
wall. The pipeline already doesn't care which CLI sits in the pane; only
seating does.

## 3. Plan

- `lib/config.sh`: accept `kinds` (array) alongside `default_kind` (string);
  emit `SEAT_KINDS_<seat>` as a space-separated, shlex-quoted list and keep
  `SEAT_KIND_<seat>` as the resolved primary for backward compatibility.
- `herdr-loop-swarm.sh`: at seat time, walk `SEAT_KINDS_*`, probe via
  `lib/providers.sh`, first pass wins; log `seat.fallback {seat, wanted,
  used}` through `lib/telemetry.py` when `used != wanted`.
- `swarm.config.toml`: convert `arch_1`/`arch_2` to chains as the living
  example (`opencode` primary, `claude` fallback).
- `tests/test_config.sh`: array parsing, single-kind sugar, empty-chain
  rejection; launcher behaviour covered by stubbed-provider assertions in
  the same test file (launcher owned here, so no cross-file dispatch).

## 4. Explicit Done-Criteria

- With the primary CLI absent from `PATH` and the fallback present,
  `up -m s` seats via the fallback and emits one `seat.fallback` event.
- With the entire chain absent, mode `a` aborts non-zero and mode `s`
  warns — the existing fail-closed semantics, unchanged.
- Backward compat: configs using only `default_kind` behave byte-identically.
- 0 shellcheck warnings.

## 5. Verification Step

```bash
make check
PATH=/usr/bin:/bin bin/stampede up <demo-dir> -m s   # fallback path, then down
```
