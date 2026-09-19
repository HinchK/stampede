# GitHub Issues Two-Way Synchronization Protocol (T-017)

**Date:** 2026-09-19 · **Agent:** `agy-gh` · **Context:** Universal Herdr Swarm (`herd-swarm`)  
**Prototype Assets:** [`docs/findings/github-issues-sync.md`](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/findings/github-issues-sync.md), [`lib/gh_sync.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/gh_sync.sh)  
**Ticket:** [T-017 (GitHub Issues Two-Way Synchronization Protocol & Tooling)](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/github-issues-two-way-sync.md) · **Parent Map:** [`maps/universal-herdr-swarm.md`](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/universal-herdr-swarm.md)

---

## 1. Executive Summary

The Universal Herdr Swarm operates on an **offline-first, local-first architecture**. Local markdown tickets in `maps/tickets/*.md` serve as the authoritative single source of truth for architectural spikes, acceptance criteria, milestone verification, and implementation decisions.

However, distributed engineering teams, human supervisors, and open-source contributors require visibility into the swarm's activity via GitHub Issues and GitHub Projects. This document establishes the **Two-Way Synchronization Protocol** between local ticket markdown files and remote GitHub Issues.

### Core Invariants

1. **Local Architecture as Canonical Source of Truth:**
   The markdown specification, done-criteria, and technical constraints in `maps/tickets/*.md` always take precedence over remote issue descriptions.
2. **Fail-Closed Remote Policies:**
   If `gh` CLI is unauthenticated, if the git remote (`origin` or `upstream`) is absent, or if the canonical repository cannot be verified, synchronization **fails closed** immediately. No guesses, no hardcoded fallbacks.
3. **Zero Unconfirmed Writes (Dry-Run by Default):**
   Every sync operation defaults to `--dry-run`. Remote issues are never created, modified, or closed, and local frontmatter is never mutated without the explicit `--apply` flag.
4. **Frontmatter Lineage Tracking:**
   Once linked or created, the remote GitHub Issue number, canonical URL, and synchronization timestamp are permanently anchored in the local ticket's YAML frontmatter (`github_issue: <int>`, `github_url: <str>`, `synced_at: <iso8601>`).

---

## 2. Frontmatter Schema & Data Model Mapping

Local tickets utilize YAML frontmatter bounded by `---` blocks. Below is the standard schema and its bi-directional mapping to GitHub Issues entities.

### A. Frontmatter Schema Specification

```yaml
---
id: T-017
title: "GitHub Issues Two-Way Synchronization Protocol & Tooling"
type: wayfinder:prototype
status: in_progress
assignee: agy-gh
parent: maps/universal-herdr-swarm.md
prototype_asset: docs/findings/github-issues-sync.md,lib/gh_sync.sh
github_issue: 42
github_url: "https://github.com/owner/repo/issues/42"
synced_at: "2026-09-19T06:30:00Z"
synced_sha: "95044cc18e47"
---
```

### B. Field-by-Field Entity Mapping

| Frontmatter Key | Type | GitHub Issues Mapping | Description & Sync Behavior |
| :--- | :--- | :--- | :--- |
| `id` | String | Title prefix `[<id>]` | Unique ticket key (e.g. `T-017`). Remote issue titles are formatted as `[<id>] <title>`. |
| `title` | String | Title suffix | Human-readable title. Remote issue title: `[T-017] Title Here`. |
| `status` | String | State & Labels | Maps local lifecycle status (`backlog`, `in_progress`, `resolved`, `closed`, `blocked`) to GitHub state and labels. |
| `type` | String | Labels | Maps ticket classification (e.g. `wayfinder:prototype` -> label `type:prototype`). |
| `assignee` | String | Issue Assignee | Maps swarm seats (`arch`, `pm`, `looper`, `agy-gh`, `agy-docs`) to GitHub users via config mapping. |
| `parent` | String | Issue Body Metadata | Markdown link back to the Wayfinder parent map in the repository. |
| `prototype_asset` | String | Issue Body Metadata | Comma-separated list of code/doc deliverables tracked by the ticket. |
| `github_issue` | Integer | Remote Issue Number | The remote `#<number>`. Set on initial creation or link. **Anchors the two-way relationship.** |
| `github_url` | String | Remote Issue URL | Canonical web URL (`https://github.com/owner/repo/issues/<number>`). |
| `synced_at` | Timestamp | None (Audit) | ISO 8601 UTC timestamp of last successful sync. |
| `synced_sha` | String | None (Integrity) | Git blob SHA or content hash at the time of sync to detect local edits. |

### C. Status Lifecycle Mapping

| Local Status | GitHub State | GitHub State Reason | GitHub Labels | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `backlog` | `OPEN` | — | `status:backlog` | Planned work not yet seated. |
| `in_progress` | `OPEN` | — | `status:in-progress` | Agent seated or branch active. |
| `blocked` | `OPEN` | — | `status:blocked` | Waiting on dependency or human intervention. |
| `resolved` | `CLOSED` | `completed` | `status:resolved` | Implementation committed and test gate green. |
| `closed` / `done` | `CLOSED` | `completed` | `status:closed` | Audited, merged, or retired. |

### D. Ticket Type Mapping

| Local `type` | GitHub Label | Label Color |
| :--- | :--- | :--- |
| `wayfinder:prototype` | `type:prototype` | `#0E8A16` (Green) |
| `wayfinder:milestone` | `type:milestone` | `#5319E7` (Purple) |
| `wayfinder:grilling` | `type:spec` | `#FBCA04` (Yellow) |
| `wayfinder:task` | `type:task` | `#1D76DB` (Blue) |
| `wayfinder:research` | `type:research` | `#D4C5F9` (Lavender) |
| `bug` | `type:bug` | `#D93F0B` (Red) |

---

## 3. Two-Way Synchronization Protocols

```mermaid
flowchart TD
    subgraph Local["Local Project (maps/tickets/*.md)"]
        LT[Local Ticket]
        FM[YAML Frontmatter]
    end

    subgraph Preflight["Fail-Closed Gate"]
        GHA[gh auth status]
        GHR[detect_repo / git remote]
        WT[Clean Worktree Check]
    end

    subgraph SyncTool["lib/gh_sync.sh"]
        SCAN[Parse Local Tickets]
        FETCH[Fetch Remote Issues]
        DIFF[Compute Reconciliation Plan]
        DRY{Mode?}
        PLAN[Output Dry-Run Plan]
        EXEC[Execute gh issue API & Update Frontmatter]
    end

    subgraph Remote["GitHub Issues (Upstream)"]
        GHI[GitHub Issue #N]
    end

    LT --> SCAN
    GHA --> GHR --> WT --> SCAN
    SCAN --> DIFF
    FETCH <-- Remote --> DIFF
    DIFF --> DRY
    DRY -- Default: --dry-run --> PLAN
    DRY -- Explicit: --apply --> EXEC
    EXEC --> Remote
    EXEC --> FM
```

### A. Push Protocol (Local -> Remote)

The push flow exports local tickets to GitHub:

1. **Ticket Discovery & Parsing:**
   - Scan all `maps/tickets/*.md`. Extract YAML frontmatter and body.
2. **Linkage Check:**
   - **Case 1: Unlinked (`github_issue` is absent):**
     - Query remote issues list for titles starting with `[<id>]` (e.g. `[T-017]`).
     - *If found on remote:* Link local ticket without creating a duplicate. Write `github_issue: <number>` and `github_url` to local frontmatter.
     - *If not found:* Propose `[CREATE]`. When applied, call `gh issue create`, capture the issue number, and write to local frontmatter.
   - **Case 2: Linked (`github_issue` is present):**
     - Check remote issue `#<github_issue>`.
     - If local status changed (e.g. `in_progress` -> `resolved`), propose `[UPDATE_REMOTE]` to close the issue or update labels.
     - If remote issue is already in sync, flag as `[NO-OP]`.

### B. Pull Protocol (Remote -> Local)

The pull flow reconciles external changes back into local tickets:

1. **External Closure Detection:**
   - If a linked remote issue was closed on GitHub (e.g. via merged PR with `Closes #42` or manual human triage), but local status remains `in_progress` or `backlog`, propose `[UPDATE_LOCAL]` to set `status: resolved`.
2. **External Issue Import:**
   - In `--direction both` or `--direction pull`, if an issue exists on GitHub with label `swarm:ticket` or title matching `[T-XXX]` that does not exist in `maps/tickets/*.md`, propose `[IMPORT_LOCAL]` to generate the local markdown file.

### C. Conflict Resolution & Precedence Rules

1. **Content & Technical Criteria:**
   Local markdown body is always authoritative. Remote edits to the issue description made via the GitHub web UI are overwritten by local markdown upon apply.
2. **Lifecycle Closures:**
   Remote closures by repository maintainers or merged PRs take precedence over local `in_progress` status.
3. **Concurrent Mutation Protection:**
   The tool calculates `synced_sha` from the local file content. If the local file has been edited since `synced_at`, the tool prompts or requires confirmation to avoid clobbering uncommitted work.

---

## 4. Fail-Closed Remote Policies & Safety Rails

To ensure the swarm never executes rogue network operations or clobbers repository state, `lib/gh_sync.sh` adheres to strict fail-closed safety policies:

### A. Preflight Verification Matrix

Before examining any ticket or constructing any payload, the tool executes:

```bash
# 1. Binary presence
command -v gh >/dev/null 2>&1 || fail "GitHub CLI ('gh') is not installed"

# 2. Authentication status
gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated (run 'gh auth login')"

# 3. Canonical remote resolution
REPO=$(detect_repo "$TARGET_DIR") || fail "No canonical GitHub remote detected"
```

### B. Fail-Closed Trigger Conditions

| Condition | Observed State | Swarm Action | Remediation Hint |
| :--- | :--- | :--- | :--- |
| **Missing CLI** | `command -v gh` returns 1 | Exit 1 immediately | `Install via 'brew install gh' or system package manager.` |
| **Unauthenticated** | `gh auth status` returns 1 | Exit 1 immediately | `Run 'gh auth login' to authenticate with GitHub.` |
| **Missing Git Remote** | No `upstream` or `origin` in `git remote -v` | Exit 1 immediately | `Add remote: git remote add origin git@github.com:OWNER/REPO.git` |
| **Missing Repo Override** | `profile.env` empty and `--repo` omitted | Exit 1 immediately | `Specify --repo OWNER/REPO or set REPO in .herdr-swarm/profile.env.` |
| **Invalid Slug Format** | Target not matching `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` | Exit 1 immediately | `Verify repository slug follows 'owner/repo' syntax.` |
| **Dirty Working Tree** | Uncommitted git changes in `maps/tickets/` | Warn / require confirmation on `--apply` | `Commit or stash local ticket changes before applying sync.` |

### C. Zero Unconfirmed Writes Guarantee

- By default, invoking `lib/gh_sync.sh` operates strictly in **dry-run mode**.
- Dry-run outputs a comprehensive, formatted plan detailing every planned `[CREATE]`, `[LINK]`, `[UPDATE]`, and `[NO-OP]` action.
- Only when invoked with explicit `--apply` (or `--sync`) will any network API call or filesystem write execute.

---

## 5. Tooling Prototype: `lib/gh_sync.sh`

The shell prototype [`lib/gh_sync.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/lib/gh_sync.sh) implements this protocol.

### A. CLI Synopsis & Flags

```text
Usage: lib/gh_sync.sh [OPTIONS]

Synchronize local maps/tickets/*.md with upstream GitHub Issues.

Options:
  --dry-run              Preview planned actions without making changes (DEFAULT)
  --apply                Execute planned changes (API mutations and frontmatter updates)
  --repo <OWNER/REPO>    Target GitHub repository (overrides auto-detected remote)
  --target-dir <DIR>     Root project directory (default: current working directory)
  --direction <DIR>      Sync direction: push | pull | both (default: push)
  --ticket <ID_OR_FILE>  Restrict sync to a specific ticket (e.g. T-017)
  --json                 Output machine-readable JSON plan/results
  --help, -h             Show this help message
```

### B. Dry-Run Output Example (Simulated)

```text
=== Universal Swarm: GitHub Issues Sync ===
Target Directory : /Users/hinchk/Fun/loop-bot-herd-agy
GitHub Repo      : HinchK/loop-bot-herd-agy
Authentication   : Verified (@HinchK)
Direction        : push
Mode             : DRY-RUN (safe, zero unconfirmed writes)

Discovered Tickets: 24 local ticket(s) in maps/tickets/

Planned Synchronization Actions:
  [CREATE]  T-014 -> "chore: init git repo and establish clean baseline" (New issue)
  [CREATE]  T-017 -> "GitHub Issues Two-Way Synchronization Protocol & Tooling" (New issue)
  [LINK]    T-001 -> matches existing remote issue #3 "research: herdr semantics"
  [UPDATE]  T-006 -> remote #8 open -> close (status: closed)
  [NO-OP]   T-002 -> in sync with remote #5

Summary:
  To Create : 22
  To Link   : 1
  To Update : 1
  In Sync   : 0
  Total     : 24

DRY RUN: No remote GitHub changes or local file writes were executed.
Pass --apply to execute these operations.
```

### C. Fail-Closed Output Example (No Remote Configured)

When executed in a repository without a configured git remote:

```text
$ bash lib/gh_sync.sh --dry-run
ERROR: No canonical GitHub repository detected for /Users/hinchk/Fun/loop-bot-herd-agy.

Fail-Closed Policy: Cannot synchronize issues without a verified GitHub remote.
Remediation:
  1. Add a git remote:
     git remote add origin git@github.com:OWNER/REPO.git
  2. Or set REPO in .herdr-swarm/profile.env:
     REPO="owner/repo"
  3. Or pass explicit repository flag:
     lib/gh_sync.sh --repo OWNER/REPO --dry-run
```

---

## 6. Integration Roadmap & Swarm Hooks

1. **Launcher Integration:**
   `herdr-loop-swarm.sh` gains `sync` subcommand:
   `./herdr-loop-swarm.sh sync [--dry-run|--apply]`
2. **Supervisor Telemetry Integration:**
   When `loop-bot-herd.sh` issues an autonomous GREEN verdict, it triggers a background non-blocking sync ping to update the linked GitHub Issue status to `resolved`.
3. **Agent Briefing:**
   The `gh` swarm seat (`agy-gh` / `worker-gh`) uses `lib/gh_sync.sh` as its primary tool to reconcile tasks, monitor upstream comments, and report status back to the swarm orchestrator (`looper`).
