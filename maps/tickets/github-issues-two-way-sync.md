---
id: T-017
title: "GitHub Issues Two-Way Synchronization Protocol & Tooling"
type: wayfinder:prototype
status: in_progress
assignee: agy-gh
prototype_asset: docs/findings/github-issues-sync.md,lib/gh_sync.sh
parent: maps/universal-herdr-swarm.md
---

# GitHub Issues Two-Way Synchronization Protocol & Tooling (T-017)

## Question

How should the Universal Herdr Swarm synchronize local markdown tickets in `maps/tickets/*.md` with remote GitHub Issues when an upstream Git remote is connected via `gh`, preserving offline-first local operation while allowing team visibility on GitHub?

## Preamble

1. **Intended Outcome**: `agy-gh` authors `docs/findings/github-issues-sync.md` documenting the bi-directional mapping between local YAML-frontmatter markdown tickets and GitHub Issues, and prototypes a non-destructive dry-run sync script `lib/gh_sync.sh`.
2. **Explicit Done-Criteria**:
   - `docs/findings/github-issues-sync.md`:
     - Documents frontmatter schema mapping: `id`, `title`, `status` (`backlog` | `in_progress` | `resolved` | `blocked`), `assignee`, `labels`.
     - Details sync rules: Local is source of truth for architecture; GitHub issue number is recorded in local ticket frontmatter (`github_issue: <number>`).
     - Zero unconfirmed writes: dry-run mode by default, fail-closed if `gh auth status` or remote origin is absent.
   - `lib/gh_sync.sh`:
     - Validates `gh` authentication and remote existence.
     - Supports `--dry-run` listing proposed issue creations or status updates.
     - Passes shellcheck cleanly.
3. **Verification Step**:
   - Run `shellcheck lib/gh_sync.sh` with 0 warnings.
   - Run `bash lib/gh_sync.sh --dry-run` to test fail-closed handling in repos without a remote.
