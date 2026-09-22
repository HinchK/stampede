---
id: T-017
title: "GitHub Issues Two-Way Synchronization Protocol & Tooling"
type: wayfinder:prototype
status: resolved
assignee: agy-gh
prototype_asset: docs/findings/github-issues-sync.md,lib/gh_sync.sh
owns: docs/findings/github-issues-sync.md,lib/gh_sync.sh
parent: maps/universal-herdr-swarm.md
github_issue: 28
github_url: "https://github.com/HinchK/stampede/issues/28"
synced_at: "2026-09-22T03:50:13Z"
---

# GitHub Issues Two-Way Synchronization Protocol & Tooling (T-017)

## Question

How should the Universal Herdr Swarm synchronize local markdown tickets in `maps/tickets/*.md` with remote GitHub Issues when an upstream Git remote is connected via `gh`, preserving offline-first local operation while allowing team visibility on GitHub?

## Resolution

Built and validated prototype in [`docs/findings/github-issues-sync.md`](../../docs/findings/github-issues-sync.md) and [`lib/gh_sync.sh`](../../lib/gh_sync.sh):
1. **Bi-Directional Schema Mapping:**
   - Documented frontmatter schema mapping (`id`, `title`, `status`, `type`, `assignee`, `github_issue`, `github_url`, `synced_at`, `synced_sha`).
   - Mapped local status lifecycle (`backlog`, `in_progress`, `resolved`, `closed`, `blocked`) to GitHub state, stateReason, and `status:*` labels.
   - Established local tickets as canonical single source of truth for architecture and criteria, with remote issue numbers anchored in YAML frontmatter.
2. **Fail-Closed Remote Policies:**
   - Enforced preflight validation matrix: `gh` CLI presence, active authentication (`gh auth status`), and canonical repository resolution via `lib/profile.sh` `detect_repo`.
   - Zero unconfirmed writes: `--dry-run` is active by default; explicit `--apply` required for remote mutations or frontmatter updates.
3. **Synchronization Tooling Prototype (`lib/gh_sync.sh`):**
   - Implemented `lib/gh_sync.sh` supporting `--dry-run`, `--apply`, `--repo`, `--target-dir`, `--direction`, `--ticket`, and `--json`.
   - Reconciles unlinked tickets (`[CREATE]`), matching remote titles (`[LINK]`), and drifted statuses (`[UPDATE]`).
   - ShellCheck compliant with 0 warnings.
   - Verified fail-closed handling when invoked without a configured remote origin.
