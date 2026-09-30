---
id: GRANT-1
title: "Session-scoped promote grant: remove per-promote friction without removing human control"
type: wayfinder:task
status: resolved
commit: e472cb8
assignee: arch
owns: lib/arbiter.sh,tests/test_arbiter.sh,briefs/looper.in.md
parent: maps/universal-herdr-swarm.md
github_issue: 73
github_url: "https://github.com/HinchK/stampede/issues/73"
synced_at: "2026-09-30T17:16:14Z"
---

# GRANT-1 — session-scoped promote authorization

## Intended Outcome

The human can explicitly authorize promote+push once per session (`bash lib/arbiter.sh grant-session [--ttl
<seconds>]`), and `looper` can then run `arbiter_promote` for the duration of that grant without requiring
`--confirm`/`PROMOTE_CONFIRM=1` or passing GATE-1's pane check on every single call. This replaces the
credential-separation direction (rejected 2026-09-29 as too much onboarding friction — see CRED-1) with something
that removes repeated friction while keeping the one property that actually matters: an agent can never grant
itself permission.

## Design

1. **`arbiter_grant_session`**: a new function, called via `bash lib/arbiter.sh grant-session [--ttl SECONDS]`
   (default TTL: 4 hours). It reuses `_arb_promote_pane_check()` (GATE-1) as its own gate — creating a grant
   requires the SAME proof of a non-agent pane that promoting itself required before. This is the load-bearing
   invariant: `looper` cannot create its own grant any more than it could pass the old pane check, so the second
   incident (an agent routing around a block on its own initiative) stays fully closed.
2. On success, writes `.herdr-swarm/promote-grant.json`: `{"granted_at": <epoch>, "expires_at": <epoch>,
   "granted_from_pane": "<pane id or 'no-herdr-context'>"}`.
3. **`arbiter_promote`**: before falling through to the existing `--confirm`/`PROMOTE_CONFIRM` refusal, check for a
   valid (unexpired) grant. If present, proceed as if `--confirm` were passed — no pane check, no confirm flag
   needed for this call. If the grant is expired or absent, fall through to today's behavior unchanged (refuse,
   print the human-action message).
4. **`arbiter_revoke_session`** (`lib/arbiter.sh revoke-session`): deletes the grant file. Also human-only via the
   same pane check — an agent shouldn't be able to revoke a grant it can't create, but this is a cheap safety net
   either way.
5. Grant is single-use-per-scope, not a standing config toggle: no `swarm.config.toml` flag that flips this on
   permanently. Every session starts ungranted; the human opts in each time they want it.

## Done-Criteria

1. `bash lib/arbiter.sh grant-session` from a non-agent pane (or no Herdr context) succeeds and writes the grant
   file; from an agent-occupied pane, refuses with the same message style as the existing pane check.
2. `arbiter_promote --confirm` behavior is unchanged when no grant exists.
3. With a valid grant, `arbiter_promote` (no flags) succeeds even when called from an agent's own pane.
4. Grant expiry is enforced — a call after `expires_at` behaves as if no grant exists.
5. `bash lib/arbiter.sh revoke-session` removes the grant; a subsequent promote without a fresh grant refuses again.
6. `briefs/looper.in.md` updated: promote is now "human-only, unless a valid session grant exists (check
   `.herdr-swarm/promote-grant.json`) — never assume one exists, never create one yourself, always check first."
7. `tests/test_arbiter.sh` gains assertions for grant creation (pane-gated same as promote), grant-gated promote
   succeeding, expiry enforcement, and revoke.
8. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_arbiter.sh
```

## Resolution

- **Implementation**:
  - `lib/arbiter.sh`: Added `arbiter_grant_session [--ttl SECONDS]` and `arbiter_revoke_session` reusing `_arb_promote_pane_check()`.
  - `arbiter_promote`: Valid session grant (`.herdr-swarm/promote-grant.json`) waives `--confirm` and pane checks; expired/absent/malformed grants fall through to human refusal.
  - `briefs/looper.in.md`: Updated to check-first promote policy.
- **Suite Gate**: `tests/test_arbiter.sh` 77/77 passing (+11 assertions); `make check` green (19 suites, 0 shellcheck warnings).
- **Review**: Autonomous Reviewer Loop PASS verdict by `reviewer-hinchk-stampede` (Round 1/2) in `.herdr-swarm/reviews/GRANT-1-e472cb858ce8a33b387b59a268c5f06073de3d55.md`.
- **Integrated**: Auto-drained and integrated on `swarm/stampede/integration` at `c7d8367`.
