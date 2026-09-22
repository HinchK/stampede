---
id: PUB-9
title: "stampede quota: read-only provider headroom probing"
type: wayfinder:task
status: ready
assignee: arch
owns: lib/quota.sh,lib/cli/stampede-quota.sh,tests/test_quota.sh
parent: maps/public-multi-provider.md
blocked_by: PUB-2
supersedes: maps/tickets-parked/cross-llm-quota-and-credit-probing.md
---

# PUB-9 — `stampede quota`: provider headroom, read-only (Wave 11)

## 1. Intended Outcome

`stampede quota` prints per-provider headroom (credits / rate budget /
quota, as the provider CLI or its config exposes them) as a table plus one
telemetry event per probe. Providers that expose nothing report `unknown` —
never a guess. No throttling, no rerouting, no writes anywhere.

## 2. Problem

The parked P3 ticket scoped quota probing *and* auto-pausing together —
a big blast radius for a benefit nobody has measured yet. Multi-provider
users still need visibility: the herd stalls mysteriously when one vendor
hits a wall, and today nothing surfaces that. Revived deliberately
narrower: observe first, automate only if the numbers say so.

## 3. Plan

- `lib/quota.sh`: per-kind probe functions returning
  `ok:<number><unit>` / `unknown` / `error:<msg>`. Known probes at
  landing: the `[proxy]` credentials file (OpenRouter-style, already
  config-gated) and any CLI that reports usage locally. Remote API calls
  only where the provider's own CLI already holds credentials — and
  read-only.
- `lib/cli/stampede-quota.sh`: renders the table keyed to configured
  seats (via PUB-2's registry for kind → probe binding).
- Telemetry: `quota.probe {seat, kind, status}` through `lib/telemetry.py`.
- `tests/test_quota.sh`: stub credential files and CLIs; assert `unknown`
  for opaque providers, correct parsing for the stubbed ones, exit codes.

## 4. Explicit Done-Criteria

- Opaque provider renders `unknown`, never `0` (0 means "empty", which
  would be a lie with teeth).
- Zero writes outside `.herdr-swarm/traces/`.
- 0 shellcheck warnings.

## 5. Verification Step

```bash
bin/stampede quota
make check
```
