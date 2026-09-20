---
id: T-003
title: "TOML Configuration Schema and Shell Binding"
type: wayfinder:prototype
status: closed
assignee: looper
prototype_asset: lib/config.sh
owns: lib/config.sh
parent: maps/universal-herdr-swarm.md
---

# TOML Configuration Schema and Shell Binding

## Question

What exact schema structure in `swarm.config.toml` cleanly captures seat definitions (names, agent kinds, model overrides, briefs, initial prompts), topology layout, and Ops-tab flags (reviewer, proxy, log) without duplication, and what minimal `python3 -c tomllib` emitter renders it into safe, evaluable shell key-value variables?

## Resolution

Implemented and verified the TOML configuration registry in [`lib/config.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/config.sh):
1. **Unified Schema:** `swarm.config.toml` serves as the single source of truth for swarm metadata, seat definitions (`[seats.<key>]`), geometry constraints (`min_cols`, `min_rows`), proxy settings, and trace directories.
2. **Zero-Dependency Python Emitter:** Uses Python 3's built-in `tomllib` to evaluate nested dot paths (`config_get "proxy.enabled"`), list enabled seats (`config_get_seats`), and generate sanitized, evaluable shell environment blocks (`config_dump_env "$slug"`).
3. **Namespacing & Dry-Run Preview:** Binds runtime seat names using the verified hypenated convention (`<seat_name>-<slug>`) and provides a rich `--plan` / `plan` dry-run preview printing markdown topology tables without launching agents.
