---
id: T-003
title: "TOML Configuration Schema and Shell Binding"
type: wayfinder:prototype
status: open
assignee: unassigned
blocked_by: []
parent: maps/universal-herdr-swarm.md
---

# TOML Configuration Schema and Shell Binding

## Question

What exact schema structure in `swarm.config.toml` cleanly captures seat definitions (names, agent kinds, model overrides, briefs, initial prompts), topology layout, and Ops-tab flags (reviewer, proxy, log) without duplication, and what minimal `python3 -c tomllib` emitter renders it into safe, evaluable shell key-value variables?
