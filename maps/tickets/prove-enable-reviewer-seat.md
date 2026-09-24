---
id: PROVE-2
title: "Enable the Reviewer seat"
type: wayfinder:task
status: resolved
commit: d7c3563
assignee: arch
owns: swarm.config.toml
parent: maps/prove-and-reconcile.md
---

# PROVE-2 — Enable the Reviewer seat (Wave 1)

**Source:** `docs/audits/2026-09-23-promote-blocker-and-unproven-reviewer-loop.md` §7.

## Intended Outcome

The Reviewer seat is switched on: verdict-anchored review rounds actually run instead of staying purely advisory.

## Background

```
$ sed -n '/\[reviewer\]/,/^\[/p' swarm.config.toml
[reviewer]
loop = false          # keeps the reviewer advisory: nothing harvested
max_rounds = 2

$ sed -n '/\[seats\.reviewer\]/,/^$/p' swarm.config.toml
[seats.reviewer]
...
enabled = false
```

Both flags have sat at their off default since REV-5 shipped. `briefs/reviewer.in.md` was already rewritten for
this by PUB-8 — the seat is ready to go, just off. Neither flag is dispatch-path-specific work; this is a two-line
config change.

## Done-Criteria

1. `[reviewer] loop = true` in `swarm.config.toml`.
2. `[seats.reviewer] enabled = true` in `swarm.config.toml`.
3. `make test` still green (`tests/test_config.sh` covers config binding).

## Verification Step

```bash
grep -A1 '^\[reviewer\]' swarm.config.toml   # loop = true
sed -n '/\[seats\.reviewer\]/,/^$/p' swarm.config.toml   # enabled = true
make test
```

## Notes

This ticket only flips the config; it does not itself seat the reviewer or run a review round. **Its effect isn't
live until it's promoted to `main`** — the launcher and supervisor run from the root checkout on `main`, not from
an arch worktree branch. See PROVE-3, which is blocked by this ticket landing on `main`.
