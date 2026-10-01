# Parked-Queue Triage Audit (HORIZON-5)

**Date:** 2026-09-30 · **Author:** pm · **Scope:** the five tickets in `maps/tickets-parked/`, plus one stale
duplicate discovered in `maps/tickets-staged/` while cross-checking the same incident class.

Every verdict below is backed by a direct read of the current source, not an assumption from the ticket text or
`status:` field (several of which are stale).

## Verdicts

### 1. `launcher-target-dir-and-sha-validation.md` (T-016-arch) — **CLOSE, superseded by reality**

All three done-criteria are live in the current tree:
- `[dir]` positional argument: `herdr-loop-swarm.sh status [dir]` / `verify [dir] [timeout_ms]` / `up [dir] -m s`
  are the documented, working command forms (CLAUDE.md).
- SHA existence check before gating: `loop-bot-herd.sh:635` —
  `if ! git -C "$REPO_DIR" cat-file -e "${sha}^{commit}" 2>/dev/null; then`
- `interactive-ready` label: `lib/lifecycle.sh:553` prints it verbatim.

File still says `status: in_progress`. It finished without the ticket being closed.

### 2. `safe-workspace-targeting-in-launcher.md` (T-016c) — **CLOSE, superseded by reality**

`herdr-loop-swarm.sh:270-299` implements exactly the described fix: `WS_ID=$(find_workspace_by_cwd "$PWD")` is
the primary resolution path (never the ambient `$HERDR_WORKSPACE_ID`), workspace creation is the fallback, and
`EXTERNAL` is set correctly when the target workspace differs from the host workspace. The code even carries a
comment block stating the exact rationale the ticket asked for: "the swarm ALWAYS binds to the workspace whose
pane cwd is this directory — never to the caller's ambient `$HERDR_WORKSPACE_ID`."

(Note: this is a different layer than the `pm` seat's own stale `$HERDR_WORKSPACE_ID` env var confusion earlier
this session — that was this session's own shell environment, not a bug in this script's internal resolution,
which is confirmed correct.)

### 3. `worktree-config-and-ledger-integration.md` (P2-2) — **CLOSE, superseded by reality**

Describes exactly the worktree-isolation architecture (`worktree = true` per seat, `seats.json` v2 with
`worktree_dir`/`branch`, provisioning before pane split) that has been live and in continuous use all session —
every `arch-1`/`arch-2` dispatch this session depended on it working.

### 4. `arbiter-batch-integration.md` (P3-4) — **KEEP PARKED**

Not superseded by `PROVE-4` (auto-triggers drain on enqueue; doesn't batch multiple tickets into one suite run) or
`HEADLESS-6` (worktree+ledger provisioning inside headless batch mode; a different concern). The underlying
problem this ticket describes — one suite run per ticket, serial drain — is real and still true today, but no
session has yet demonstrated actual throughput pain from it (arbiter drain has not been an observed bottleneck).
Recommend re-evaluating if/when concurrent-seat throughput becomes a measured problem, rather than speculatively
building it now.

### 5. `cross-llm-quota-and-credit-probing.md` (P3) — **PARTIALLY SUPERSEDED; re-release narrower scope recommended**

Read-only provider-headroom probing shipped under `PUB-9` (`lib/quota.sh`): one probe function per provider
surface, explicitly **"no throttling, no rerouting, no writes anywhere"** by design. Covers the OpenRouter-style
`[proxy]` credentials surface. Critically, `quota_probe_kind()` — the per-seat-kind extension seam for `claude`,
`opencode`, `agy`, `pi` — answers `unknown` for every kind, always, because "no seat-kind CLI exposes a parseable
local usage surface at landing."

That premise just failed for real: today (2026-09-30), `looper` (`agy`/Gemini via Antigravity CLI) hit an
account-level quota wall mid-session, with a parseable, structured message in its own pane output:

```
⚠ Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h26m33s.
```

This is a receipt the original speculative ticket never had. Recommend closing `P3` as superseded-in-spirit by
`PUB-9`'s read-only design decision (throttling/rerouting stay explicitly out of scope — that part of P3 is
rightly dead), but **re-releasing a narrow follow-up** — implement `quota_probe_kind agy` against this exact
pane-output pattern, surfaced read-only the same way the OpenRouter probe is — rather than reviving P3's full
original multi-provider ambition.

## Stale duplicate found while cross-checking (not one of the original five)

### `tickets-staged/prove-reconcile-and-promote.md` (PROVE-1) — **DELETE, dead duplicate**

This ticket was resolved on 2026-09-23 at commit `9b4491c` — `maps/prove-and-reconcile.md`'s own "Decisions so
far" and "Active Frontier" (marked `[x]`) confirm this directly. The staged file itself was simply never deleted
after resolution, leaving a `status: backlog` ghost that looks live to anyone who finds it without checking the
parent map — exactly the kind of staleness this audit exists to catch.

## Summary

| Ticket | Verdict |
|---|---|
| T-016-arch | Close — superseded by reality |
| T-016c | Close — superseded by reality |
| P2-2 | Close — superseded by reality |
| P3-4 | Keep parked — not superseded, not yet justified |
| P3 (quota) | Close as superseded-in-spirit; re-release narrower `quota_probe_kind agy` follow-up |
| PROVE-1 (staged dup) | Delete — already resolved elsewhere |
