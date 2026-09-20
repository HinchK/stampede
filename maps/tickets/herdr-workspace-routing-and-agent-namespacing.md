---
id: T-001
title: "Herdr Semantics: Workspace Routing and Agent Namespacing"
type: wayfinder:research
status: closed
assignee: arch
resolution_commits: [97b67d0, 6ad4afe]
findings_doc: docs/findings/herdr-semantics.md
owns: docs/findings/herdr-semantics.md
parent: maps/universal-herdr-swarm.md
---

# Herdr Semantics: Workspace Routing and Agent Namespacing

## Question

How does Herdr route pane split and agent commands across workspaces, are agent names server-global or workspace-scoped, and which character grammar is legally accepted in agent names?

## Resolution

Investigated empirically via live probes against scratch workspace `probe-t001` (recorded in `docs/findings/herdr-semantics.md`):
1. **Workspace Routing:** Pane IDs are workspace-prefixed (`wM:p1`, `wN:p2`) and route unambiguously server-wide regardless of UI focus. However, `pane split --current` routes to the terminal UI's last foreground pane and will leak splits across workspaces. Scripts must strictly ban `--current` and use explicit anchor pane IDs.
2. **Agent Naming Scope:** Agent names occupy a single server-global registry. Multiple concurrent projects cannot seat duplicate agent names; namespacing is mandatory.
3. **Legal Grammar:** Legal agent names must conform to `^[a-z][a-z0-9_-]*$`. Middle dot `·` (proposed in brainstorm `arch·slug`) is rejected by Herdr CLI; hyphens (`arch-<slug>`) or underscores (`arch_<slug>`) must be used.
