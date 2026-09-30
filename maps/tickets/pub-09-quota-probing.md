---
id: PUB-9
title: "stampede quota: read-only provider headroom probing"
type: wayfinder:task
status: resolved
assignee: arch-2
owns: lib/quota.sh,lib/cli/stampede-quota.sh,tests/test_quota.sh
parent: maps/public-multi-provider.md
blocked_by: PUB-2
supersedes: maps/tickets-parked/cross-llm-quota-and-credit-probing.md
github_issue: 98
github_url: "https://github.com/HinchK/stampede/issues/98"
synced_at: "2026-09-30T17:16:14Z"
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

## 6. Resolution (2026-09-22, `d5083eb`)

- `lib/quota.sh`: `quota_probe_kind` (the seat-kind seam — every registered kind answers `unknown` at landing) and `quota_probe_openrouter` (env `OPENROUTER_API_KEY` first, then the config-gated `[proxy]` credentials file's `openrouter.api_key`; result is `total_credits - total_usage` as `ok:<n>USD`). The unknown/error contract is enforced hard: missing or non-numeric credit fields are `error:unparsable credits response`, never an arithmetic-default 0; unreachable endpoint is `error:credits endpoint unreachable`; anything unconfigured is `unknown`.
- `lib/cli/stampede-quota.sh`: seat-kind rows enumerated through the PUB-2 registry (`providers_seats_from_config`), disabled seats SKIP without probing, plus one `- / openrouter` row; one `quota.probe {seat, kind, status}` telemetry event per actual probe. Zero writes outside `.herdr-swarm/traces/` — the herd session id is reused read-only instead of calling `telemetry_session_id()` (which would write the session file). Exit 0 when probes answer; 1 on config trouble or any probe error.
- `tests/test_quota.sh`: 28 hermetic assertions — fixture-driven stub curl (zero network), the full unknown/error matrix, bearer-header capture, seat-keyed table rendering, one-event-per-probe counts, a before/after filesystem snapshot proving the zero-writes rule, read-only session reuse, and exit codes.
- Receipts: `bin/stampede quota` renders the live roster (all kinds `unknown`, proxy `unknown`, rc 0); `shellcheck lib/quota.sh lib/cli/stampede-quota.sh` 0 warnings; 12/13 suites green including this one (28/28). `make check`'s single red is `test_async_gate.sh [1b]`, a wall-clock assertion (1500 ms) that fails under desktop load ~15–18 with `scan blocked (2.1–3.1 s)` — proven pre-existing: a detached control worktree at `ec941fd` (before this ticket's files existed) fails identically under the same load, and the same suite passed at 170 ms twice earlier on the quiet machine. No file in this ticket's owns touches the gated path.
